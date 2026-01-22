// Azure Virtual Desktop Multi-Session deployment with Intune management
// Optimized for golden image + MSIX app attach strategy
// Windows 11 Enterprise Multi-session with Business Premium licensing

param location string = resourceGroup().location
param avdResourceLocation string = 'northeurope'
param secondaryLocation string = 'swedencentral'
param subnetName string = 'avd-subnet'
param agentUpdate object = {
      maintenanceWindow: {
        dayOfWeek: 'Sunday'
        hour: '3'
      } 
      maintenanceWindowTimeZone: 'Romance Standard Time'
      type: 'Default'
      useSessionHostLocalTime: true
    }
@description('Entra ID Group Object ID for AVD users - grants access to the desktop and VM login')
param avdUserGroupId string
param resourcePrefix string = 'avd'
param vnetAddressPrefix string = '10.0.0.0/16'
param subnetAddressPrefix string = '10.0.0.0/24'
param adminUsername string
@secure()
param adminPassword string
param vmSize string = 'Standard_D4s_v5'
param numberOfVMs int = 2
param maxSessionLimit int = 10
param useCustomImage bool = false
param customImageId string = ''
param deploymentTime string = utcNow()
param vnetExists bool = false
param existingVnetName string = ''
@description('Deployment iteration number - increment when doing fresh deployments to avoid Entra ID device name conflicts')
@minLength(2)
@maxLength(2)
param deploymentNumber string = '01'

// Compute subnet ID based on VNet scenario
var subnetId = vnetExists ? resourceId('Microsoft.Network/virtualNetworks/subnets', existingVnetName, subnetName) : '${resourceId('Microsoft.Network/virtualNetworks', '${resourcePrefix}-vnet')}/subnets/${subnetName}'

resource existingVnet 'Microsoft.Network/virtualNetworks@2025-01-01' existing = if (vnetExists) {
  name: existingVnetName
}

// Network Security Group
resource nsg 'Microsoft.Network/networkSecurityGroups@2025-01-01' = {
  name: '${resourcePrefix}-nsg'
  location: location
  properties: {
    securityRules: [
      {
        name: 'AllowAVDServiceTag'
        properties: {
          priority: 100
          direction: 'Outbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '443'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: 'WindowsVirtualDesktop'
        }
      }
            {
        name: 'AllowAzureAD'
        properties: {
          priority: 110
          direction: 'Outbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '443'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: 'AzureActiveDirectory'
        }
      }
      {
        name: 'AllowAzureCloud'
        properties: {
          priority: 120
          direction: 'Outbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '443'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: 'AzureCloud'
        }
      }
    ]
  }
}

resource subnet 'Microsoft.Network/virtualNetworks/subnets@2025-01-01' = if (vnetExists) {
  parent: existingVnet
  name: subnetName
  properties: {
    addressPrefix: subnetAddressPrefix
    networkSecurityGroup: {
      id: nsg.id
    }
  }
}

// Virtual Network
resource vnet 'Microsoft.Network/virtualNetworks@2025-01-01' = if (!vnetExists) {
  name: '${resourcePrefix}-vnet'
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [vnetAddressPrefix]
    }
    subnets: [
      {
        name: subnetName
        properties: {
          addressPrefix: subnetAddressPrefix
          networkSecurityGroup: {
            id: nsg.id
          }
        }
      }
    ]
  }
}

// Storage Account for MSIX App Attach
resource storageAccount 'Microsoft.Storage/storageAccounts@2025-06-01' = {
  name: '${resourcePrefix}msix${uniqueString(resourceGroup().id)}'
  location: location
  sku: {
    name: 'Premium_LRS'
  }
  kind: 'FileStorage'
  properties: {
    azureFilesIdentityBasedAuthentication: {
      directoryServiceOptions: 'AADKERB'
    }
    supportsHttpsTrafficOnly: true
    minimumTlsVersion: 'TLS1_2'
  }
}

// File Share for MSIX packages
resource fileShare 'Microsoft.Storage/storageAccounts/fileServices/shares@2025-06-01' = {
  name: '${storageAccount.name}/default/msix-packages'
  properties: {
    shareQuota: 1024
    enabledProtocols: 'SMB'
  }
}

// Storage Account for FSLogix profiles
resource profileStorage 'Microsoft.Storage/storageAccounts@2025-06-01' = {
  name: '${resourcePrefix}prof${uniqueString(resourceGroup().id)}'
  location: location
  sku: {
    name: 'Premium_LRS'
  }
  kind: 'FileStorage'
  properties: {
    azureFilesIdentityBasedAuthentication: {
      directoryServiceOptions: 'AADKERB'
    }
    networkAcls: {
      bypass: 'AzureServices'
      virtualNetworkRules: []
      ipRules: []
      defaultAction: 'Allow'
    }
    supportsHttpsTrafficOnly: true
    minimumTlsVersion: 'TLS1_2'
  }
}

// File Share for FSLogix profiles
resource profileShare 'Microsoft.Storage/storageAccounts/fileServices/shares@2025-06-01' = {
  name: '${profileStorage.name}/default/profiles'
  properties: {
    shareQuota: 10240
  }
}

// RBAC: Session hosts need elevated permissions to create and manage profile containers
resource profileStorageVMRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = [for i in range(0, numberOfVMs): {
  name: guid(profileStorage.id, sessionHost[i].id, 'a7264617-510b-434b-a828-9731dc254ea7')
  scope: profileStorage
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'a7264617-510b-434b-a828-9731dc254ea7') // Storage File Data SMB Share Elevated Contributor
    principalId: sessionHost[i].identity.principalId
    principalType: 'ServicePrincipal'
  }
  dependsOn: [
    sessionHost[i]
  ]
}]

// RBAC: End users need standard contributor access to read/write their profiles
// FSLogix enforces NTFS ACLs to prevent cross-user access
resource profileStorageUserRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(profileStorage.id, avdUserGroupId, '0c867c2a-1d8c-454a-a3db-ab2ea1bdc8bb')
  scope: profileStorage
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '0c867c2a-1d8c-454a-a3db-ab2ea1bdc8bb') // Storage File Data SMB Share Contributor
    principalId: avdUserGroupId
    principalType: 'Group'
  }
}

// Network Interfaces
resource nic 'Microsoft.Network/networkInterfaces@2025-01-01' = [for i in range(0, numberOfVMs): {
  name: '${resourcePrefix}-nic-${deploymentNumber}-${padLeft(i + 1, 2, '0')}'
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          subnet: {
            id: subnetId
          }
          privateIPAllocationMethod: 'Dynamic'
        }
      }
    ]
  }
}]

module hostPool 'modules/hostPool.bicep' = {
  name: 'hostPoolTokenModule'
  params: {
    hostPoolName: '${resourcePrefix}-hostpool'
    location: avdResourceLocation
    tags: {}
    friendlyName: 'AVD Host Pool'
    hostPoolType: 'Pooled'
    loadBalancerType: 'BreadthFirst'
    preferredAppGroupType: 'Desktop'
    maxSessionLimit: maxSessionLimit
    startVMOnConnect: false
    validationEnvironment: false
    agentUpdate: agentUpdate
    baseTime: deploymentTime
    tokenValidityLength: 'PT24H'
    logAnalyticsWorkspaceId: logAnalytics.id
  }
}

// Application Group
resource appGroup 'Microsoft.DesktopVirtualization/applicationGroups@2025-04-01-preview' = {
  name: '${resourcePrefix}-appgroup'
  location: avdResourceLocation
  properties: {
    hostPoolArmPath: hostPool.outputs.hostPoolId
    applicationGroupType: 'Desktop'
  }
}

// RBAC Assignment: Virtual Machine User Login role at Resource Group level
resource vmUserLoginRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, avdUserGroupId, 'fb879df8-f326-4884-b1cf-06f3ad86be52')
  scope: resourceGroup()
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'fb879df8-f326-4884-b1cf-06f3ad86be52')
    principalId: avdUserGroupId
    principalType: 'Group'
  }
}

// Workspace
resource workspace 'Microsoft.DesktopVirtualization/workspaces@2025-04-01-preview' = {
  name: '${resourcePrefix}-workspace'
  location: avdResourceLocation
  properties: {
    applicationGroupReferences: [
      appGroup.id
    ]
  }
}

// Session Host VMs - Multi-session
resource sessionHost 'Microsoft.Compute/virtualMachines@2025-04-01' = [for i in range(0, numberOfVMs): {
  name: '${resourcePrefix}vm-${deploymentNumber}-${padLeft(i + 1, 2, '0')}'
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    hardwareProfile: {
      vmSize: vmSize
    }
    osProfile: {
      computerName: '${resourcePrefix}vm${deploymentNumber}${padLeft(i + 1, 2, '0')}'
      adminUsername: adminUsername
      adminPassword: adminPassword
      windowsConfiguration: {
        enableAutomaticUpdates: true
        patchSettings: {
          patchMode: 'AutomaticByOS'
        }
        provisionVMAgent: true
      }
    }
    storageProfile: useCustomImage ? {
      imageReference: {
        id: customImageId
      }
      osDisk: {
        name: '${resourcePrefix}vm-${deploymentNumber}-osdisk-${padLeft(i + 1, 2, '0')}'
        createOption: 'FromImage'
        managedDisk: {
          storageAccountType: 'Premium_LRS'
        }
        diskSizeGB: 128
      }
    } : {
      imageReference: {
        publisher: 'MicrosoftWindowsDesktop'
        offer: 'office-365'
        sku: 'win11-23h2-avd-m365'
        version: 'latest'
      }
      osDisk: {
        name: '${resourcePrefix}vm-${deploymentNumber}-osdisk-${padLeft(i + 1, 2, '0')}'
        createOption: 'FromImage'
        managedDisk: {
          storageAccountType: 'Premium_LRS'
        }
        diskSizeGB: 128
      }
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: nic[i].id
        }
      ]
    }
    licenseType: 'Windows_Client'
  }
  dependsOn: [
    hostPool
  ]
}]

// Azure AD Join Extension
resource aadExtension 'Microsoft.Compute/virtualMachines/extensions@2025-04-01' = [for i in range(0, numberOfVMs): {
  parent: sessionHost[i]
  name: 'AADLoginForWindows'
  location: location
  properties: {
    publisher: 'Microsoft.Azure.ActiveDirectory'
    type: 'AADLoginForWindows'
    typeHandlerVersion: '1.0'
    autoUpgradeMinorVersion: true
    settings: {
      mdmId: '0000000a-0000-0000-c000-000000000000'
    }
  }
}]

// AVD Agent Extension
resource avdExtension 'Microsoft.Compute/virtualMachines/extensions@2025-04-01' = [for i in range(0, numberOfVMs): {
  parent: sessionHost[i]
  name: 'Microsoft.PowerShell.DSC'
  location: location
  properties: {
    publisher: 'Microsoft.Powershell'
    type: 'DSC'
    typeHandlerVersion: '2.73'
    autoUpgradeMinorVersion: true
    settings: {
      modulesUrl: 'https://wvdportalstorageblob.blob.${environment().suffixes.storage}/galleryartifacts/Configuration_09-08-2022.zip'
      configurationFunction: 'Configuration.ps1\\AddSessionHost'
      properties: {
        hostPoolName: hostPool.outputs.hostPoolName
        registrationInfoToken: hostPool.outputs.registrationToken

        aadJoin: true
        useAgentDownloadEndpoint: true
        mdmId: '0000000a-0000-0000-c000-000000000000'
      }
    }
  }
  dependsOn: [
    aadExtension[i]
  ]
}]

// Log Analytics Workspace for monitoring
resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2025-07-01' = {
  name: '${resourcePrefix}-logs'
  location: secondaryLocation
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 90
  }
}

// Outputs
output hostPoolName string = hostPool.outputs.hostPoolName
output workspaceName string = workspace.name
output appGroupName string = appGroup.name
output appGroupId string = appGroup.id
output sessionHostNames array = [for i in range(0, numberOfVMs): sessionHost[i].name]
output vnetId string = vnetExists ? existingVnet.id : vnet.id
output subnetId string = subnetId
output msixStorageAccountName string = storageAccount.name
output msixFileShareName string = 'msix-packages'
output msixFileSharePath string = '\\\\${storageAccount.name}.file.${environment().suffixes.storage}\\msix-packages'
output profileStorageAccountName string = profileStorage.name
output profileFileSharePath string = '\\\\${profileStorage.name}.file.${environment().suffixes.storage}\\profiles'
output logAnalyticsWorkspaceId string = logAnalytics.id

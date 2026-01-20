//Add parameters to pass in existing host pool properties
param hostPoolName string
param location string
param tags object
param friendlyName string
param hostPoolType string
param loadBalancerType string
param preferredAppGroupType string
param maxSessionLimit int
param startVMOnConnect bool
param validationEnvironment bool
param agentUpdate object
param baseTime string
param tokenValidityLength string
param logAnalyticsWorkspaceId string = ''
param customRdpProperty string = 'drivestoredirect:s:;audiomode:i:0;videoplaybackmode:i:1;redirectclipboard:i:0;redirectprinters:i:0;devicestoredirect:s:;redirectcomports:i:0;redirectsmartcards:i:0;usbdevicestoredirect:s:;enablecredsspsupport:i:1;use multimon:i:1;targetisaadjoined:i:1;enablerdsaadauth:i:1'
param description string = 'Standard Host Pool'
// Update an existing host pool to generate a new registration token

resource hostPool 'Microsoft.DesktopVirtualization/hostPools@2025-04-01-preview' = {
  name: hostPoolName
  location: location
  tags: tags
  properties: {
    description: description
    friendlyName: friendlyName
    hostPoolType: hostPoolType
    loadBalancerType: loadBalancerType
    preferredAppGroupType: preferredAppGroupType
    maxSessionLimit: maxSessionLimit
    startVMOnConnect: startVMOnConnect
    validationEnvironment: validationEnvironment
    agentUpdate: agentUpdate
    customRdpProperty: customRdpProperty
    // Update the registration info with a new token
    registrationInfo: {
      expirationTime: dateTimeAdd(baseTime, tokenValidityLength)
      registrationTokenOperation: 'Update'
    }
  }
}

// Diagnostic Settings for Host Pool
resource diagnosticSettings 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (!empty(logAnalyticsWorkspaceId)) {
  scope: hostPool
  name: 'avd-diagnostics'
  properties: {
    workspaceId: logAnalyticsWorkspaceId
    logs: [
      {
        category: 'Checkpoint'
        enabled: true
      }
      {
        category: 'Error'
        enabled: true
      }
      {
        category: 'Management'
        enabled: true
      }
      {
        category: 'Connection'
        enabled: true
      }
      {
        category: 'HostRegistration'
        enabled: true
      }
    ]
  }
}

@secure()
output registrationToken string = first(hostPool.listRegistrationTokens().value)!.token

output hostPoolId string = hostPool.id
output hostPoolName string = hostPool.name

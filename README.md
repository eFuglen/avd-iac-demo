# Azure Virtual Desktop - Infrastructure as Code

Bicep templates for deploying Azure Virtual Desktop (AVD) with Windows 11 Enterprise multi-session VMs, Microsoft Entra ID join, and Intune management.

## Architecture Overview

This solution deploys a complete AVD environment with:

- **Host Pool**: Pooled Windows 11 multi-session (23H2) with Office 365
- **Session Hosts**: Configurable number of VMs (default: 2x Standard_D4s_v5)
- **Identity**: Microsoft Entra ID joined with Intune MDM enrollment
- **Storage**: 
  - Premium file storage for FSLogix user profiles
  - Premium file storage for MSIX app packages
- **Networking**: Virtual network with NSG configured for AVD service tags
- **Monitoring**: Log Analytics workspace with diagnostic settings
- **RBAC**: Automated role assignments for users and VMs

## Features

✅ Windows 11 Enterprise multi-session with Microsoft 365 Apps  
✅ Microsoft Entra ID join with Intune automatic enrollment  
✅ FSLogix profile storage with Azure Files + Entra Kerberos  
✅ MSIX app attach storage (Premium file share)  
✅ Golden image support (optional custom image deployment)  
✅ Network security with service tags for AVD, Azure AD, Azure Cloud  
✅ Log Analytics integration for monitoring  
✅ RBAC automation (VM login, storage access, desktop users)  
✅ Configurable deployment numbers to avoid device name conflicts  

## Prerequisites

- **Azure Subscription** with Owner or Contributor + User Access Administrator roles
- **Microsoft Entra ID** tenant
- **Intune License** (Microsoft 365 Business Premium or E3/E5)
- **Entra ID Group Object ID** for AVD users

## Repository Structure

```
├── bicep/
│   ├── main.bicep              # Main deployment template
│   └── modules/
│       └── hostPool.bicep      # Host pool with registration token
├── parameters/
│   └── main.bicepparam         # Parameter file
└── scripts/
    ├── Deploy-AVD.ps1          # PowerShell deployment script
    ├── Install-FSLogix.ps1     # Optional: FSLogix agent installation
    └── Cleanup-RG.ps1          # Cleanup script
```

## Quick Start

### 1. Configure Parameters

Edit [parameters/main.bicepparam](parameters/main.bicepparam):

```bicep
param location = 'denmarkeast'              // VM location
param avdResourceLocation = 'northeurope'   // AVD metadata location
param resourcePrefix = 'myavd'              // Resource naming prefix
param adminUsername = 'avdadmin'
param adminPassword = 'ChangeMe!P@ssw0rd'  // Use secure password
param numberOfVMs = 2
param vmSize = 'Standard_D4s_v5'
param deploymentNumber = '01'               // Increment for fresh deployments
param avdUserGroupId = 'your-group-id'      // Entra ID group object ID
```

### 2. Deploy with Azure CLI

```bash
az group create --name rg-avd-demo --location denmarkeast

az deployment group create \
  --resource-group rg-avd-demo \
  --template-file bicep/main.bicep \
  --parameters @parameters/main.bicepparam
```

### 3. Deploy with PowerShell

```powershell
.\scripts\Deploy-AVD.ps1 `
  -ResourceGroup "rg-avd-demo" `
  -ParameterFile "parameters\main.bicepparam" `
  -AdminPassword (ConvertTo-SecureString "YourPassword123!" -AsPlainText -Force)
```

## Configuration Details

### Deployment Number Strategy

The `deploymentNumber` parameter (e.g., "01", "02") is used in VM naming to avoid Entra ID device object conflicts during redeployments. Increment this value when doing fresh deployments to the same resource group.

- VMs are named: `{prefix}vm-{deploymentNumber}-{index}` (e.g., `avdvm-01-01`, `avdvm-01-02`)
- Computer names: `{prefix}vm{deploymentNumber}{index}` (e.g., `avdvm0101`)

### Network Security

The NSG includes outbound rules for:

- Windows Virtual Desktop service tag (port 443)
- Azure Active Directory service tag (port 443)
- Azure Cloud service tag (port 443)

### Storage Configuration

**FSLogix Profiles**:

- Premium LRS file storage
- Entra Kerberos authentication (AADKERB)
- File share: `profiles` (10 TB quota)
- RBAC: VMs get "Storage File Data SMB Share Elevated Contributor"
- RBAC: Users get "Storage File Data SMB Share Contributor"

**MSIX App Attach**:

- Premium LRS file storage  
- File share: `msix-packages` (1 TB quota)
- Supports expanded .vhdx packages

### Custom Image Support

To use a custom golden image:

```bicep
param useCustomImage = true
param customImageId = '/subscriptions/.../images/myCustomImage'
```

Default marketplace image: `MicrosoftWindowsDesktop/office-365/win11-23h2-avd-m365`

## Post-Deployment

### 1. Assign Desktop Users

Users in the Entra ID group specified by `avdUserGroupId` automatically get:

- "Desktop Virtualization User" role on the application group (via RG assignment)
- "Virtual Machine User Login" role for VM sign-in
- "Storage File Data SMB Share Contributor" for FSLogix profiles

### 2. Install and Configure FSLogix

**Installation**:

- **Option A (Recommended)**: Include FSLogix in your custom golden image
- **Option B**: Deploy via Intune Win32 app
- **Option C**: Run the provided script manually: `scripts\Install-FSLogix.ps1`

**Configuration** (via Intune Settings Catalog):

1. In Intune, create a **Settings Catalog** policy
2. Search for "FSLogix" and configure:
   - **Enabled**: Yes
   - **VHD Locations**: `\\{storageAccountName}.file.core.windows.net\profiles`
   - **Size in MBs**: 30000
   - **Volume Type**: VHDX
   - **Delete Local Profile**: Enabled
3. Assign to your AVD session hosts device group

**Alternative**: Use FSLogix ADMX templates with Group Policy (if domain-joined)

📖 **Detailed guide**: See [docs/FSLogix-Intune-Configuration.md](docs/FSLogix-Intune-Configuration.md) for complete step-by-step instructions.

### 3. Deploy Apps

- **MSIX App Attach**: Upload .vhdx packages to the MSIX storage share
- **Intune**: Deploy apps via Intune app management
- **Custom Image**: Pre-install apps in your golden image

### 4. Connect to AVD

Users access via:

- [Azure Virtual Desktop Web Client](https://client.wvd.microsoft.com)
- Windows AVD client app
- Remote Desktop app (macOS, iOS, Android)

## Known Issues & Workarounds

### Entra ID Join Extension Failures

In some cases, the AADLoginForWindows extension may fail with error code -2145648526. This is often related to network connectivity or regional issues.

**Workaround Options**:

1. **Manual Join (Post-Deployment)**:
   - RDP to the VM using local admin credentials
   - Run: `dsregcmd /join`
   - Verify: `dsregcmd /status`
   - Enroll in Intune via Settings > Accounts > Access work or school

2. **Remove Extension and Join via Intune**:
   - Comment out the `aadExtension` resource in main.bicep
   - Deploy successfully
   - Use Intune Autopilot or manual enrollment

## Monitoring

### Log Analytics Queries

```kusto
// Host pool connections
WVDConnections
| where State == "Connected"
| summarize count() by UserName, bin(TimeGenerated, 1h)

// Host pool errors
WVDErrors
| where TimeGenerated > ago(24h)
| summarize count() by ActivityType, ErrorShortMessage
```

Diagnostic settings are configured automatically for the host pool.

## Security Best Practices

- ✅ Use Azure Key Vault for admin passwords in production
- ✅ Enable Conditional Access policies for AVD users
- ✅ Deploy in a private virtual network with proper NSG rules
- ✅ Enable Microsoft Defender for Cloud
- ✅ Use Privileged Identity Management (PIM) for admin access
- ✅ Regular security assessments with Azure Policy

## Cost Optimization

- VMs use Premium SSD for OS disks (required for production)
- Consider VM shutdown schedules during non-business hours
- Use Azure Reserved Instances for predictable workloads
- Monitor with Azure Cost Management + Billing

## Cleanup

To remove all resources:

```powershell
.\scripts\Cleanup-RG.ps1 -ResourceGroup "rg-avd-demo"
```

Or using Azure CLI:

```bash
az group delete --name rg-avd-demo --yes --no-wait
```

## Contributing

Contributions welcome! Please ensure:

- Bicep code follows best practices
- API versions are up to date
- Documentation is updated for changes
- Test in development environment first

## Support

For issues:

- Review this README and [MSIX guidance](https://learn.microsoft.com/azure/virtual-desktop/app-attach-overview)
- Check [Azure Virtual Desktop documentation](https://learn.microsoft.com/azure/virtual-desktop/)
- Review deployment outputs for diagnostic information

## License

MIT License - see LICENSE file for details

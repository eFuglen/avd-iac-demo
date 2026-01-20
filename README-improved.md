# Azure Virtual Desktop - Infrastructure as Code

This repository contains Bicep templates for deploying Azure Virtual Desktop (AVD) with Windows 11 multi-session VMs managed by Microsoft Intune.

## Architecture Overview

- **Host Pool**: Windows 11 multi-session with pooled configuration
- **Session Hosts**: 2x Windows 11 Enterprise multi-session VMs
- **Identity**: Microsoft Entra ID joined with Intune enrollment
- **Storage**: FSLogix profile storage on Azure Storage Account
- **Monitoring**: Log Analytics workspace for diagnostics
- **Cost Optimization**: Automated VM shutdown schedules

## Features

✅ **Windows 11 Multi-session**: Latest Windows 11 Enterprise multi-session (23H2)  
✅ **Intune Management**: Automatic enrollment for device and user policies  
✅ **FSLogix Profiles**: Persistent user profiles with Azure Files  
✅ **Security Hardening**: Azure AD join, encrypted storage, RBAC  
✅ **Cost Optimization**: VM shutdown schedules, optimized VM sizes  
✅ **Monitoring**: Boot diagnostics and Log Analytics integration  
✅ **Best Practices**: Following Microsoft AVD and Bicep guidelines  

## Prerequisites

Before deploying this template, ensure you have:

1. **Azure Subscription** with appropriate permissions
2. **Existing Virtual Network** and subnet for AVD session hosts
3. **Microsoft Intune License** (included with Microsoft 365 E3/E5)
4. **User/Group Object ID** for access assignments

## Quick Start

1. **Clone the repository**
   ```bash
   git clone <repository-url>
   cd avd-iac-test
   ```

2. **Update parameters**
   Edit `parameters/tst-main.bicepparam`:
   ```bicep
   param vnetResourceGroup = 'your-network-rg'
   param vnetName = 'your-vnet-name'
   param subnetName = 'your-subnet-name'
   param userObjectId = 'your-user-or-group-objectid'
   ```

3. **Deploy using Azure CLI**
   ```bash
   az deployment group create \
     --resource-group rg-avd-test \
     --template-file bicep/main.bicep \
     --parameters @parameters/tst-main.bicepparam \
     --parameters adminPassword='YourSecurePassword123!'
   ```

## Secure Deployment with Key Vault

For production deployments, store the admin password in Azure Key Vault:

1. **Create Key Vault and store password**
   ```bash
   az keyvault secret set \
     --vault-name "kv-avd-secrets" \
     --name "avd-admin-password" \
     --value "YourSecurePassword123!"
   ```

2. **Deploy referencing Key Vault**
   ```bash
   az deployment group create \
     --resource-group rg-avd-prod \
     --template-file bicep/main.bicep \
     --parameters @parameters/prod-main.bicepparam \
     --parameters adminPassword="$(az keyvault secret show --vault-name kv-avd-secrets --name avd-admin-password --query value -o tsv)"
   ```

## Post-Deployment Configuration

After successful deployment:

### 1. Configure FSLogix (if enabled)
- Navigate to the created Storage Account
- Note the file share name and storage account key
- Configure FSLogix GPO or Intune policy with storage settings

### 2. Assign Users to Application Group
```bash
# Get the application group resource ID from deployment outputs
az role assignment create \
  --assignee-object-id <user-object-id> \
  --role "Desktop Virtualization User" \
  --scope <application-group-resource-id>
```

### 3. Configure Intune Policies
- Device compliance policies
- Configuration profiles
- App deployment policies
- Security baselines

### 4. Test Connection
- Users can connect via:
  - Azure Virtual Desktop web client
  - AVD Store app for Windows
  - Remote Desktop client

## Monitoring and Maintenance

### Log Analytics Queries
Monitor your AVD environment with these KQL queries:

```kusto
// Session host performance
Perf
| where Computer startswith "AVDDemo"
| where CounterName in ("% Processor Time", "Available MBytes")
| summarize avg(CounterValue) by Computer, CounterName, bin(TimeGenerated, 5m)

// User connections
WVDConnections
| where State == "Connected"
| summarize count() by UserName, bin(TimeGenerated, 1h)
```

### Cost Optimization
- VMs automatically shut down at 7 PM (configurable)
- Use Azure Advisor recommendations
- Consider Azure Reserved Instances for production

## Security Considerations

- **Network Security**: Deploy in a secure subnet with NSG rules
- **Identity**: Use Conditional Access policies
- **Data**: Enable encryption at rest and in transit
- **Monitoring**: Enable security monitoring and alerts
- **Compliance**: Apply security baselines via Intune

## Troubleshooting

### Common Issues

1. **VMs not joining domain/Entra ID**
   - Verify subnet has internet connectivity
   - Check Intune enrollment settings

2. **AVD Agent installation fails**
   - Ensure host pool registration token is valid
   - Check VM extensions logs in Azure portal

3. **Users cannot connect**
   - Verify RBAC assignments on application group
   - Check user licensing (AVD requires appropriate license)

### Useful Commands

```bash
# Check deployment status
az deployment group show --resource-group rg-avd-test --name main

# View VM extension logs
az vm extension show --resource-group rg-avd-test --vm-name AVDDemo-vm-00 --name AADLoginForWindows

# Test Intune enrollment
az ad signed-in-user show --query objectId -o tsv
```

## Key Improvements Made

### 1. **Updated API Versions**
- All resources now use the latest stable API versions
- Improved reliability and access to latest features

### 2. **Enhanced Security**
- Windows 11 23H2 multi-session (latest version)
- Proper Intune MDM enrollment ID
- Premium SSD storage for better performance
- Automatic patching configuration

### 3. **Better Resource Organization**
- Consistent naming with zero-padding
- Comprehensive tagging strategy
- Resource dependencies properly managed

### 4. **FSLogix Integration**
- Optional storage account for user profiles
- Azure Files integration for persistent profiles
- Proper RBAC for storage access

### 5. **Cost Optimization**
- VM shutdown schedules
- Optimized VM sizes (D4s_v5 instead of D2s_v5)
- Resource cleanup automation

### 6. **Monitoring & Diagnostics**
- Log Analytics workspace
- Boot diagnostics enabled
- Performance monitoring ready

### 7. **Bicep Best Practices**
- User-defined types where appropriate
- Secure parameter handling
- Environment-specific configuration
- Child resources with parent references

## Contributing

1. Follow Bicep best practices
2. Update documentation for any changes
3. Test deployments in development environment first
4. Use semantic versioning for releases

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Support

For issues and questions:
- Check the troubleshooting section above
- Review Azure Virtual Desktop documentation
- Contact your IT support team
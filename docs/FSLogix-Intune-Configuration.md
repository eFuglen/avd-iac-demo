# FSLogix Configuration via Intune

This guide explains how to configure FSLogix Profile Containers using Microsoft Intune for AVD session hosts.

## Why Intune for FSLogix Configuration?

✅ **Scalability**: Automatically applies to new session hosts  
✅ **Centralized Management**: Single pane of glass for all configurations  
✅ **Drift Prevention**: Intune enforces and remediates configuration drift  
✅ **Separation of Concerns**: IaC handles infrastructure, Intune handles configuration  
✅ **Compliance Reporting**: Built-in monitoring and reporting  

## Prerequisites

- Session hosts are **Entra ID joined** and **Intune enrolled**
- FSLogix agent installed (via custom image, Intune app, or manual script)
- Azure Files storage account with profile share created (deployed via Bicep)
- RBAC roles assigned (handled automatically in Bicep deployment)

## Step 1: Create FSLogix Settings Catalog Policy

### In Microsoft Intune Admin Center:

1. Navigate to **Devices** > **Configuration** > **Create** > **New policy**
2. Select:
   - **Platform**: Windows 10 and later
   - **Profile type**: Settings catalog
3. **Name**: FSLogix Profile Container Configuration
4. **Description**: Configures FSLogix profile redirection to Azure Files

### Step 2: Add FSLogix Settings

Click **Add settings** and search for "FSLogix". Configure the following:

#### Core Settings (Required)

| Setting | Value | Description |
|---------|-------|-------------|
| **Enabled** | 1 (True) | Enables FSLogix Profile Containers |
| **VHD Locations** | `\\{storageAccountName}.file.core.windows.net\profiles` | Replace with your storage account name |
| **Size in MBs** | 30000 | Maximum profile size (30 GB) |
| **Is Dynamic** | 1 (True) | Profiles grow dynamically |
| **Volume Type** | VHDX | Use VHDX format |
| **Delete Local Profile When VHD Should Apply** | 1 (True) | Remove local profiles |
| **Flip Flop Profile Directory Name** | 1 (True) | Use username_SID format |

#### Authentication Settings

| Setting | Value | Description |
|---------|-------|-------------|
| **Access Network As Computer Object** | 1 (True) | Required for Entra Kerberos auth |

#### Resilience Settings (Recommended)

| Setting | Value | Description |
|---------|-------|-------------|
| **Prevent Login With Failure** | 0 (False) | Allow login even if FSLogix fails |
| **Prevent Login With Temp Profile** | 0 (False) | Allow temp profiles as fallback |
| **Locked Retry Count** | 3 | Number of retries for locked profiles |
| **Locked Retry Interval** | 15 | Seconds between retries |

#### Advanced Settings (Optional)

| Setting | Value | Description |
|---------|-------|-------------|
| **VHD Access Mode** | 3 | Direct access mode (best performance) |
| **Clear Cache On Logoff** | 1 (True) | Clean local cache on logoff |
| **Profile Type** | 0 | Normal profile (not read-only) |
| **Concurrent User Sessions** | 1 | One session per user |

#### Logging Settings

| Setting | Value | Description |
|---------|-------|-------------|
| **Logging Enabled** | 1 (True) | Enable FSLogix logging |
| **Logging Level** | 2 | Info level (0=Error, 1=Warning, 2=Info, 3=Debug) |
| **Log File Keeping Period** | 7 | Days to retain logs |

### Step 3: Configure User Filtering (Optional)

To apply profiles only to specific users:

1. Add setting: **Include User Groups**
2. Value: `S-1-5-11` (Authenticated Users)
   - Or use specific group SIDs for targeted users

### Step 4: Assign the Policy

1. Click **Next** to Assignments
2. **Include**: Select your AVD session hosts device group
   - Example: "AVD-SessionHosts-Group"
3. **Exclude**: (optional) Test devices during rollout
4. Click **Next** > **Create**

## Step 2: Create FSLogix Win32 App (Optional)

If not using a custom image with FSLogix pre-installed:

### Package FSLogix as Intune Win32 App:

1. Download FSLogix from: https://aka.ms/fslogix_download
2. Extract and package using [Microsoft Win32 Content Prep Tool](https://github.com/Microsoft/Microsoft-Win32-Content-Prep-Tool)
3. Upload to Intune as Win32 app with:
   - **Install command**: `FSLogixAppsSetup.exe /install /quiet /norestart`
   - **Detection rule**: File exists - `C:\Program Files\FSLogix\Apps\frx.exe`
   - **Assignment**: Required for AVD session hosts device group

## Step 3: Verify Configuration

### On Session Hosts:

1. Sign in to a session host
2. Open Registry Editor
3. Navigate to: `HKEY_LOCAL_MACHINE\SOFTWARE\FSLogix\Profiles`
4. Verify settings are applied correctly

### Check FSLogix Status:

```powershell
# Check service
Get-Service frxsvc

# Check logs
Get-Content "C:\ProgramData\FSLogix\Logs\Profile\*.log" -Tail 50

# Verify registry settings
Get-ItemProperty -Path "HKLM:\SOFTWARE\FSLogix\Profiles"
```

## Step 4: Test User Sign-In

1. Sign in as a test user
2. Navigate to the Azure Files share
3. Verify profile VHD/VHDX is created: `\\{storage}.file.core.windows.net\profiles\{username}_{SID}\Profile_{username}_{SID}.vhdx`
4. Check FSLogix logs for successful mount

## Troubleshooting

### Profile Not Created

- Verify RBAC permissions on storage account
- Check network connectivity to Azure Files
- Review FSLogix logs in `C:\ProgramData\FSLogix\Logs`
- Ensure Entra Kerberos is enabled on storage account

### Intune Policy Not Applying

- Check device is enrolled in Intune: `dsregcmd /status`
- Sync policy manually: Settings > Accounts > Access work or school > Sync
- Review Intune device compliance status
- Check Event Viewer > Applications and Services Logs > Microsoft > Windows > DeviceManagement-Enterprise-Diagnostics-Provider

### Permission Errors

- Session host system identity needs: **Storage File Data SMB Share Elevated Contributor**
- Users need: **Storage File Data SMB Share Contributor**
- Verify role assignments in Azure Portal

## Alternative: Group Policy (Domain-Joined Only)

If using traditional AD-joined session hosts:

1. Download FSLogix ADMX templates from: https://aka.ms/fslogix_download
2. Copy ADMX files to Group Policy Central Store
3. Create GPO linked to AVD session hosts OU
4. Configure settings under: **Computer Configuration > Policies > Administrative Templates > FSLogix**

## Best Practices

✅ **Test in pilot group** before rolling out to production  
✅ **Monitor profile sizes** - alert on profiles approaching quota  
✅ **Set appropriate quotas** - balance user needs with cost  
✅ **Regular log reviews** - identify authentication or performance issues  
✅ **Use exclusions wisely** - exclude temp/cache folders to reduce profile size  
✅ **Document storage account name** - needed for user support and troubleshooting  

## References

- [FSLogix Documentation](https://learn.microsoft.com/fslogix/)
- [Intune Settings Catalog](https://learn.microsoft.com/mem/intune/configuration/settings-catalog)
- [Azure Files with Entra Kerberos](https://learn.microsoft.com/azure/storage/files/storage-files-identity-auth-azure-active-directory-enable)
- [AVD FSLogix Best Practices](https://learn.microsoft.com/azure/virtual-desktop/fslogix-containers-azure-files)

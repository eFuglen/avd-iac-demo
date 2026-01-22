# Azure Virtual Desktop Deployment Script
# Deploys AVD infrastructure using Bicep and Azure CLI

param(
    [Parameter(Mandatory = $true)]
    [string]$ResourceGroup,
    
    [Parameter(Mandatory = $false)]
    [string]$Location = "denmarkeast",
    
    [Parameter(Mandatory = $false)]
    [string]$ParameterFile = "..\parameters\main.bicepparam",
    
    [Parameter(Mandatory = $false)]
    [SecureString]$AdminPassword,
    
    [Parameter(Mandatory = $false)]
    [switch]$WhatIf,
    
    [Parameter(Mandatory = $false)]
    [switch]$SkipGroupAssignment
)

$ErrorActionPreference = 'Stop'

function Write-Info($msg) { Write-Host "[INFO] $msg" -ForegroundColor Green }
function Write-Warn($msg) { Write-Host "[WARN] $msg" -ForegroundColor Yellow }

# Helper to extract parameter value from bicepparam file
function Get-ParamValue {
    param($content, $paramName)
    if ($content -match "param $paramName\s*=\s*'([^']*)'") { return $Matches[1] }
    return $null
}

# Deploy Bicep template
function Start-Deployment {
    param($plainPassword)
    
    $deploymentName = "avd-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
    $templateFile = Join-Path (Split-Path $PSScriptRoot -Parent) "bicep\main.bicep"
    
    Write-Info "Starting deployment: $deploymentName"
    Write-Info "Template: $templateFile"
    Write-Info "Parameters: $ParameterFile"
    
    $args = @("deployment", "group", "create",
              "--resource-group", $ResourceGroup,
              "--name", $deploymentName,
              "--template-file", $templateFile,
              "--parameters", $ParameterFile,
              "--output", "json")

    if ($plainPassword) { $args += @("--parameters", "adminPassword=$plainPassword") }
    if ($WhatIf) { $args += "--what-if" }

    $result = az @args
    if ($LASTEXITCODE -ne 0) {
        throw "Deployment failed with exit code $LASTEXITCODE"
    }
    
    return ($result | ConvertFrom-Json)
}

# Assign Entra ID group to Application Group
function Set-AppGroupAssignment {
    param($appGroupId, $groupId)
    
    Write-Info "Assigning group $groupId to application group..."
    
    az role assignment create `
        --assignee $groupId `
        --role "Desktop Virtualization User" `
        --scope $appGroupId `
        --output none 2>&1 | Out-Null
    
    if ($LASTEXITCODE -eq 0) {
        Write-Info "Group assignment completed"
    }
    else {
        Write-Warn "Group assignment failed - assign manually in Azure Portal"
    }
}

# Check VM extensions status
function Test-VMExtensions {
    param($rgName)
    
    Write-Info "Checking VM extensions..."
    $vms = az vm list --resource-group $rgName --query "[].name" -o json | ConvertFrom-Json
    
    foreach ($vm in $vms) {
        $exts = az vm extension list --resource-group $rgName --vm-name $vm --query "[].{name:name,state:provisioningState}" -o json | ConvertFrom-Json
        Write-Host "  VM: $vm" -ForegroundColor Cyan
        foreach ($ext in $exts) {
            $icon = if ($ext.state -eq "Succeeded") { "✅" } else { "❌" }
            $color = if ($ext.state -eq "Succeeded") { "Green" } else { "Red" }
            Write-Host "    $icon $($ext.name): $($ext.state)" -ForegroundColor $color
        }
    }
}

# ============================================
# Main Execution
# ============================================

try {
    Write-Host "`n=== Azure Virtual Desktop Deployment ===" -ForegroundColor Blue
    
    # Prerequisites
    if (-not (Get-Command "az" -ErrorAction SilentlyContinue)) { throw "Azure CLI not installed" }
    if (-not (Test-Path $ParameterFile)) { throw "Parameter file not found: $ParameterFile" }
    
    $account = az account show -o json | ConvertFrom-Json
    Write-Info "Subscription: $($account.name) ($($account.id))"
    
    # Ensure resource group exists
    if ((az group exists --name $ResourceGroup) -eq 'false') {
        Write-Info "Creating resource group: $ResourceGroup"
        az group create --name $ResourceGroup --location $Location -o none
    }
    
    # Get/prompt for password
    $plainPassword = $null
    if ($AdminPassword) {
        $plainPassword = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto(
            [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($AdminPassword))
    } elseif (-not $WhatIf) {
        $AdminPassword = Read-Host "Enter VM admin password" -AsSecureString
        $plainPassword = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto(
            [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($AdminPassword))
    }
    
    # Deploy
    $result = Start-Deployment -plainPassword $plainPassword
    
    if ($WhatIf) {
        Write-Info "What-if completed - no resources deployed"
        exit 0
    }
    
    Write-Info "Deployment state: $($result.properties.provisioningState)"
    
    # Post-deployment tasks
    Test-VMExtensions -rgName $ResourceGroup
    
    # Assign Entra ID group to app group
    if (-not $SkipGroupAssignment -and $result.properties.outputs.appGroupId) {
        $paramContent = Get-Content $ParameterFile -Raw
        $groupId = Get-ParamValue -content $paramContent -paramName "avdUserGroupId"
        
        if ($groupId -and $groupId -ne 'YOUR_ENTRA_ID_GROUP_OBJECT_ID_HERE') {
            Set-AppGroupAssignment -appGroupId $result.properties.outputs.appGroupId.value -groupId $groupId
        } else {
            Write-Warn "avdUserGroupId not configured - skipping group assignment"
        }
    }
    
    # Show key outputs
    Write-Host "`n=== Deployment Outputs ===" -ForegroundColor Cyan
    if ($result.properties.outputs) {
        $result.properties.outputs.PSObject.Properties | ForEach-Object {
            Write-Host "  $($_.Name): $($_.Value.value)"
        }
    }
    
    Write-Host "`n=== Next Steps ===" -ForegroundColor Cyan
    Write-Host "  1. Configure FSLogix in Intune"
    Write-Host "  2. Verify user access in Azure Portal"
    Write-Host "  3. Test connections via AVD client"
    
    Write-Info "Deployment completed successfully!"
    
} catch {
    Write-Host "`n[ERROR] $_" -ForegroundColor Red
    exit 1
}
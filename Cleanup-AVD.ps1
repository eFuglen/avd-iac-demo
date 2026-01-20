# Cleanup-AVD.ps1 - Cleanup existing deployment for fresh start
param(
    [Parameter(Mandatory = $true)]
    [string]$ResourceGroupName,
    
    [string]$SubscriptionId
)

# Set error action
$ErrorActionPreference = "Stop"

try {
    Write-Host "🧹 Starting AVD cleanup for fresh deployment..." -ForegroundColor Yellow
    
    if ($SubscriptionId) {
        Write-Host "Setting subscription context: $SubscriptionId"
        az account set --subscription $SubscriptionId
    }
    
    # Check if resource group exists
    $rgExists = az group exists --name $ResourceGroupName | ConvertFrom-Json
    if (-not $rgExists) {
        Write-Host "✅ Resource group '$ResourceGroupName' doesn't exist - nothing to clean up" -ForegroundColor Green
        return
    }
    
    Write-Host "📋 Listing resources to delete..."
    $resources = az resource list --resource-group $ResourceGroupName --query "[].{name:name, type:type}" | ConvertFrom-Json
    
    if ($resources.Count -eq 0) {
        Write-Host "✅ No resources found in resource group" -ForegroundColor Green
        return
    }
    
    Write-Host "Found $($resources.Count) resources:"
    $resources | ForEach-Object {
        Write-Host "  - $($_.name) ($($_.type))"
    }
    
    Write-Host ""
    $confirm = Read-Host "Do you want to delete the entire resource group? This will remove ALL resources. (y/N)"
    
    if ($confirm -eq 'y' -or $confirm -eq 'Y') {
        Write-Host "🗑️ Deleting resource group '$ResourceGroupName'..." -ForegroundColor Red
        az group delete --name $ResourceGroupName --yes --no-wait
        
        Write-Host "✅ Deletion initiated. This may take several minutes to complete." -ForegroundColor Green
        Write-Host "💡 You can check progress with: az group show --name '$ResourceGroupName'"
    } else {
        Write-Host "❌ Cleanup cancelled by user" -ForegroundColor Yellow
    }
    
} catch {
    Write-Error "❌ Cleanup failed: $($_.Exception.Message)"
    exit 1
}
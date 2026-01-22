# Cleanup-RG.ps1 - Cleanup existing deployment for fresh start
param(
    [Parameter(Mandatory = $true)]
    [string]$ResourceGroupName,
    
    [string]$SubscriptionId
)

# Set error action
$ErrorActionPreference = "Stop"

try {
    Write-Host "🧹 Starting resource group cleanup for fresh deployment..." -ForegroundColor Yellow
    
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
        Write-Host "🗑️  Deleting resource group '$ResourceGroupName'..." -ForegroundColor Red
        az group delete --name $ResourceGroupName --yes --no-wait
        
        Write-Host "⏳ Waiting for resource group deletion to complete..." -ForegroundColor Yellow

        $iteration = 0
        $delaySeconds = 10

        while ($true) {
            $iteration++
            Start-Sleep -Seconds $delaySeconds
            $exists = az group exists --name $ResourceGroupName | ConvertFrom-Json
            if (-not $exists) { 
                break 
            }

            $resourcesLeft = az resource list --resource-group $ResourceGroupName --query "[].{name:name}" | ConvertFrom-Json
            Write-Host "🔄 Pass #$iteration (next check in ${delaySeconds}s) - Still deleting - resources left: $($resourcesLeft.Count) " -ForegroundColor Cyan
#⏳⌛🔄
            if ($iteration -eq 3)
            {
                Write-Host "⏱️  While we wait you can grab a ☕"
                $delaySeconds = 15
            }
            if ($iteration -eq 4)
            {
                Write-Host "⏲️  Still working on it... grab a 🥐"
            }
            if ($iteration -eq 6)
            {
                Write-Host "⌛ This is taking longer than usual. Thanks for your patience!"
                $delaySeconds = 20
            }
        }
        Write-Host "✅ Deletion completed." -ForegroundColor Green
        Write-Host "💡 You can now redeploy your resources." -ForegroundColor Magenta
    } else {
        Write-Host "❌ Cleanup cancelled by user" -ForegroundColor Yellow
    }
    
} catch {
    Write-Error "❌ Cleanup failed: $($_.Exception.Message)"
    exit 1
}
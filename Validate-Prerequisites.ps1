# Quick validation script to troubleshoot deployment issues
param(
    [string]$ResourceGroup = 'avdTest01'
)

Write-Host "=== Troubleshooting AVD Deployment ===" -ForegroundColor Cyan

# 1. Check if connected to Azure
Write-Host "`n1. Checking Azure connection..." -ForegroundColor Yellow
try {
    $context = Get-AzContext
    if ($context) {
        Write-Host "✓ Connected to Azure as: $($context.Account.Id)" -ForegroundColor Green
        Write-Host "✓ Subscription: $($context.Subscription.Name)" -ForegroundColor Green
    }
    else {
        Write-Host "✗ Not connected to Azure. Run Connect-AzAccount" -ForegroundColor Red
        exit 1
    }
}
catch {
    Write-Host "✗ Error checking Azure connection: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# 2. Check network resources
Write-Host "`n2. Checking network prerequisites..." -ForegroundColor Yellow
try {
    # Check network resource group
    $networkRG = Get-AzResourceGroup -Name 'avdNet01' -ErrorAction SilentlyContinue
    if ($networkRG) {
        Write-Host "✓ Network resource group 'avdNet01' exists" -ForegroundColor Green
    } else {
        Write-Host "✗ Network resource group 'avdNet01' not found" -ForegroundColor Red
    }
    
    # Check VNet
    $vnet = Get-AzVirtualNetwork -ResourceGroupName 'avdNet01' -Name 'avd-base-net' -ErrorAction SilentlyContinue
    if ($vnet) {
        Write-Host "✓ Virtual Network 'avd-base-net' exists" -ForegroundColor Green
        
        # Check subnet
        $subnet = $vnet.Subnets | Where-Object { $_.Name -eq 'default' }
        if ($subnet) {
            Write-Host "✓ Subnet 'default' exists" -ForegroundColor Green
            Write-Host "  Address prefix: $($subnet.AddressPrefix)" -ForegroundColor Gray
        } else {
            Write-Host "✗ Subnet 'default' not found" -ForegroundColor Red
            Write-Host "Available subnets:" -ForegroundColor Yellow
            $vnet.Subnets | ForEach-Object { Write-Host "  - $($_.Name) ($($_.AddressPrefix))" -ForegroundColor Gray }
        }
    } else {
        Write-Host "✗ Virtual Network 'avd-base-net' not found" -ForegroundColor Red
    }
}
catch {
    Write-Host "✗ Error checking network resources: $($_.Exception.Message)" -ForegroundColor Red
}

# 3. Check user object ID
Write-Host "`n3. Checking user object..." -ForegroundColor Yellow
try {
    $userObjectId = '03abd695-ee5f-45d2-aabb-284b86ec949d'
    $user = Get-AzADUser -ObjectId $userObjectId -ErrorAction SilentlyContinue
    if ($user) {
        Write-Host "✓ User object ID is valid: $($user.DisplayName)" -ForegroundColor Green
    } else {
        Write-Host "✗ User object ID not found: $userObjectId" -ForegroundColor Red
        Write-Host "To get your object ID, run: Get-AzADUser -UserPrincipalName 'your-email@domain.com'" -ForegroundColor Yellow
    }
}
catch {
    Write-Host "✗ Error checking user object: $($_.Exception.Message)" -ForegroundColor Red
}

# 4. Validate template syntax
Write-Host "`n4. Checking Bicep template syntax..." -ForegroundColor Yellow
try {
    if (Test-Path "bicep\main.bicep") {
        # Try to compile bicep to ARM to check for syntax errors
        $tempFile = [System.IO.Path]::GetTempFileName() + ".json"
        az bicep build --file "bicep\main.bicep" --outfile $tempFile 2>$null
        if ($LASTEXITCODE -eq 0) {
            Write-Host "✓ Bicep template syntax is valid" -ForegroundColor Green
            Remove-Item $tempFile -ErrorAction SilentlyContinue
        } else {
            Write-Host "✗ Bicep template has syntax errors" -ForegroundColor Red
            Write-Host "Run: az bicep build --file bicep\main.bicep" -ForegroundColor Yellow
        }
    } else {
        Write-Host "✗ Bicep template not found: bicep\main.bicep" -ForegroundColor Red
    }
}
catch {
    Write-Host "✗ Error checking template: $($_.Exception.Message)" -ForegroundColor Red
}

# 5. Check quota and region support
Write-Host "`n5. Checking Azure region and quotas..." -ForegroundColor Yellow
try {
    $location = 'swedencentral'
    
    # Check if region supports VM size
    $vmSizes = Get-AzVMSize -Location $location | Where-Object { $_.Name -eq 'Standard_D4s_v5' }
    if ($vmSizes) {
        Write-Host "✓ VM size 'Standard_D4s_v5' available in $location" -ForegroundColor Green
    } else {
        Write-Host "✗ VM size 'Standard_D4s_v5' not available in $location" -ForegroundColor Red
    }
    
    # Check if region supports AVD
    $providers = Get-AzResourceProvider -ProviderNamespace Microsoft.DesktopVirtualization
    $locations = $providers.ResourceTypes | Where-Object { $_.ResourceTypeName -eq 'hostpools' } | Select-Object -ExpandProperty Locations
    if ($locations -contains $location) {
        Write-Host "✓ Azure Virtual Desktop supported in $location" -ForegroundColor Green
    } else {
        Write-Host "✗ Azure Virtual Desktop not supported in $location" -ForegroundColor Red
        Write-Host "Supported locations: $($locations -join ', ')" -ForegroundColor Yellow
    }
}
catch {
    Write-Host "✗ Error checking region support: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host "`n=== Validation Complete ===" -ForegroundColor Cyan
# Install-FSLogix.ps1
# Installs FSLogix agent on AVD session hosts
# Configuration should be managed via Intune or Group Policy

$ErrorActionPreference = 'Stop'

Write-Host "Installing FSLogix agent..." -ForegroundColor Green

# FSLogix download URL (latest version as of script creation)
$fslogixUrl = "https://aka.ms/fslogix_download"
$downloadPath = "$env:TEMP\FSLogix.zip"
$extractPath = "$env:TEMP\FSLogix"

try {
    # Download FSLogix
    Write-Host "Downloading FSLogix from $fslogixUrl..." -ForegroundColor Cyan
    Invoke-WebRequest -Uri $fslogixUrl -OutFile $downloadPath -UseBasicParsing
    
    # Extract
    Write-Host "Extracting FSLogix installer..." -ForegroundColor Cyan
    Expand-Archive -Path $downloadPath -DestinationPath $extractPath -Force
    
    # Find and install the x64 agent
    $installerPath = Get-ChildItem -Path $extractPath -Recurse -Filter "FSLogixAppsSetup.exe" | 
                     Where-Object { $_.FullName -like "*x64*" } | 
                     Select-Object -First 1
    
    if (-not $installerPath) {
        throw "FSLogix installer not found in extracted files"
    }
    
    Write-Host "Installing FSLogix from: $($installerPath.FullName)" -ForegroundColor Cyan
    
    # Install silently
    $installArgs = @(
        "/install"
        "/quiet"
        "/norestart"
    )
    
    $process = Start-Process -FilePath $installerPath.FullName -ArgumentList $installArgs -Wait -PassThru
    
    if ($process.ExitCode -eq 0 -or $process.ExitCode -eq 3010) {
        Write-Host "✓ FSLogix agent installed successfully!" -ForegroundColor Green
        if ($process.ExitCode -eq 3010) {
            Write-Host "  Note: A reboot is required to complete installation" -ForegroundColor Yellow
        }
    } else {
        throw "FSLogix installation failed with exit code: $($process.ExitCode)"
    }
    
    # Verify service exists
    $service = Get-Service -Name "frxsvc" -ErrorAction SilentlyContinue
    if ($service) {
        Write-Host "✓ FSLogix service detected: $($service.Status)" -ForegroundColor Green
    } else {
        Write-Host "⚠ FSLogix service not found - may require reboot" -ForegroundColor Yellow
    }
    
} catch {
    Write-Host "✗ Installation failed: $_" -ForegroundColor Red
    throw
} finally {
    # Cleanup
    if (Test-Path $downloadPath) { Remove-Item $downloadPath -Force -ErrorAction SilentlyContinue }
    if (Test-Path $extractPath) { Remove-Item $extractPath -Recurse -Force -ErrorAction SilentlyContinue }
}

Write-Host "`n=== Next Steps ===" -ForegroundColor Cyan
Write-Host "FSLogix agent is installed but NOT configured." -ForegroundColor Yellow
Write-Host "Configure FSLogix settings using one of these methods:" -ForegroundColor Yellow
Write-Host "  1. Intune Configuration Profile (Recommended for cloud-native)" -ForegroundColor White
Write-Host "  2. Group Policy with FSLogix ADMX templates" -ForegroundColor White
Write-Host "  3. Manual registry configuration (testing only)" -ForegroundColor White
Write-Host "`nProfile path to configure: \\<storageaccount>.file.core.windows.net\profiles" -ForegroundColor Cyan
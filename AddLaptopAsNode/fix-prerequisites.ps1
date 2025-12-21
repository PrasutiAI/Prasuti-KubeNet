$ErrorActionPreference = "Stop"

Write-Host "=== Fixing Kubernetes Node Prerequisites ===" -ForegroundColor Cyan

# 1. Clean up leftover certificates
$pkiCa = "C:\etc\kubernetes\pki\ca.crt"
if (Test-Path $pkiCa) {
    Write-Host "Removing leftover certificate: $pkiCa" -ForegroundColor Yellow
    Remove-Item $pkiCa -Force
}

# 2. Install crictl
Write-Host "Installing crictl..." -ForegroundColor Cyan
& "c:\DATA\Work\CICD\Prasuti-KubeNet\AddLaptopAsNode\install-crictl.ps1"

# 3. Install nssm
$nssmPath = "C:\Program Files\Kubernetes\bin\nssm.exe"
if (-not (Test-Path $nssmPath)) {
    Write-Host "Downloading nssm..." -ForegroundColor Cyan
    $nssmZip = "$env:TEMP\nssm.zip"
    $nssmUrl = "https://nssm.cc/release/nssm-2.24.zip"
    Invoke-WebRequest -Uri $nssmUrl -OutFile $nssmZip -UseBasicParsing
    
    # Extract nssm.exe (win64 version)
    Expand-Archive -Path $nssmZip -DestinationPath "$env:TEMP\nssm" -Force
    Copy-Item "$env:TEMP\nssm\nssm-2.24\win64\nssm.exe" -Destination $nssmPath -Force
    
    Remove-Item $nssmZip -Force
    Remove-Item "$env:TEMP\nssm" -Recurse -Force
    Write-Host "nssm installed to $nssmPath" -ForegroundColor Green
}
else {
    Write-Host "nssm already exists at $nssmPath" -ForegroundColor Green
}

Write-Host "=== Prerequisites Fixed ===" -ForegroundColor Green

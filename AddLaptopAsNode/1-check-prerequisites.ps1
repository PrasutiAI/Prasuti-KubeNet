# Kubernetes Worker Node - Prerequisites Check Script
# Run this script as Administrator

Write-Host "=== Kubernetes Worker Node Prerequisites Check ===" -ForegroundColor Cyan
Write-Host ""

# Check if running as Administrator
$currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
$isAdmin = $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Host "[WARNING] This script should be run as Administrator (Attempting to proceed causing strict check failure...)" -ForegroundColor Yellow
    # Write-Host "Right-click PowerShell and select 'Run as Administrator'" -ForegroundColor Yellow
    # exit 1 
}
Write-Host "[OK] Running as Administrator" -ForegroundColor Green

# Check Windows Version
Write-Host "`nChecking Windows Version..." -ForegroundColor Yellow
$osInfo = Get-ComputerInfo | Select-Object OsName, OsVersion, OsBuildNumber
Write-Host "OS: $($osInfo.OsName)" -ForegroundColor White
Write-Host "Version: $($osInfo.OsVersion)" -ForegroundColor White
Write-Host "Build: $($osInfo.OsBuildNumber)" -ForegroundColor White

$minBuild = 17763  # Windows Server 2019 / Windows 10 1809
if ([int]$osInfo.OsBuildNumber -ge $minBuild) {
    Write-Host "[OK] Windows version is compatible" -ForegroundColor Green
}
else {
    Write-Host "[ERROR] Windows build must be at least $minBuild" -ForegroundColor Red
    exit 1
}

# Check Hyper-V capability
Write-Host "`nChecking Hyper-V support..." -ForegroundColor Yellow
$hyperv = Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V-All -ErrorAction SilentlyContinue
if ($hyperv) {
    Write-Host "Hyper-V State: $($hyperv.State)" -ForegroundColor White
    if ($hyperv.State -eq "Enabled") {
        Write-Host "[OK] Hyper-V is enabled" -ForegroundColor Green
    }
    else {
        Write-Host "[WARNING] Hyper-V is available but not enabled" -ForegroundColor Yellow
        Write-Host "To enable, run: Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V -All" -ForegroundColor Yellow
    }
}
else {
    Write-Host "[WARNING] Hyper-V not available (may not be needed for containerd)" -ForegroundColor Yellow
}

# Check Containers feature
Write-Host "`nChecking Containers feature..." -ForegroundColor Yellow
$containers = Get-WindowsOptionalFeature -Online -FeatureName Containers -ErrorAction SilentlyContinue
if ($containers) {
    Write-Host "Containers State: $($containers.State)" -ForegroundColor White
    if ($containers.State -eq "Enabled") {
        Write-Host "[OK] Containers feature is enabled" -ForegroundColor Green
    }
    else {
        Write-Host "[WARNING] Containers feature is not enabled. Enabling now..." -ForegroundColor Yellow
        Enable-WindowsOptionalFeature -Online -FeatureName Containers -All -NoRestart
        Write-Host "[INFO] Containers feature enabled. A restart may be required." -ForegroundColor Cyan
    }
}
else {
    Write-Host "[ERROR] Containers feature not found" -ForegroundColor Red
}

# Check network connectivity to API server
Write-Host "`nChecking connectivity to Kubernetes API server..." -ForegroundColor Yellow
$apiServer = "e6cb868d-ac12-47af-a171-67420418f77f-ap-south-noi-1.kaas.theacecloud.com"
$apiPort = 6443

try {
    $result = Test-NetConnection -ComputerName $apiServer -Port $apiPort -WarningAction SilentlyContinue
    if ($result.TcpTestSucceeded) {
        Write-Host "[OK] Can connect to $apiServer`:$apiPort" -ForegroundColor Green
    }
    else {
        Write-Host "[ERROR] Cannot connect to $apiServer`:$apiPort" -ForegroundColor Red
        Write-Host "Check your network connection and firewall settings" -ForegroundColor Yellow
    }
}
catch {
    Write-Host "[ERROR] Network test failed: $_" -ForegroundColor Red
}

# Check available disk space
Write-Host "`nChecking disk space..." -ForegroundColor Yellow
$systemDrive = $env:SystemDrive
$disk = Get-PSDrive -Name $systemDrive.Substring(0, 1)
$freeSpaceGB = [math]::Round($disk.Free / 1GB, 2)
Write-Host "Free space on $systemDrive : $freeSpaceGB GB" -ForegroundColor White

if ($freeSpaceGB -ge 20) {
    Write-Host "[OK] Sufficient disk space available" -ForegroundColor Green
}
else {
    Write-Host "[WARNING] Low disk space. At least 20GB recommended" -ForegroundColor Yellow
}

# Check RAM
Write-Host "`nChecking system memory..." -ForegroundColor Yellow
$ram = Get-CimInstance Win32_ComputerSystem
$totalRamGB = [math]::Round($ram.TotalPhysicalMemory / 1GB, 2)
Write-Host "Total RAM: $totalRamGB GB" -ForegroundColor White

if ($totalRamGB -ge 4) {
    Write-Host "[OK] Sufficient memory available" -ForegroundColor Green
}
else {
    Write-Host "[WARNING] Low memory. At least 4GB recommended" -ForegroundColor Yellow
}

# Summary
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Prerequisites check complete!" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "`nYou can proceed to the next step: 2-install-containerd.ps1" -ForegroundColor Green

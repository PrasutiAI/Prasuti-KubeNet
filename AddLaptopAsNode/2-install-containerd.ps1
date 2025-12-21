# Kubernetes Worker Node - Install containerd
# Run this script as Administrator

Write-Host "=== Installing containerd Container Runtime ===" -ForegroundColor Cyan
Write-Host ""

# Check if running as Administrator
$currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
$isAdmin = $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Host "[WARNING] This script should be run as Administrator (Attempting to proceed...)" -ForegroundColor Yellow
    # exit 1 
}

# Variables
$containerdVersion = "1.7.13"
$containerdUrl = "https://github.com/containerd/containerd/releases/download/v$containerdVersion/containerd-$containerdVersion-windows-amd64.tar.gz"
$downloadPath = "$env:TEMP\containerd.tar.gz"
$installPath = "C:\Program Files\containerd"
$binPath = "$installPath\bin"

Write-Host "Installing containerd version $containerdVersion..." -ForegroundColor Yellow

# Create installation directory
if (-not (Test-Path $installPath)) {
    New-Item -Path $installPath -ItemType Directory -Force | Out-Null
    Write-Host "[OK] Created directory: $installPath" -ForegroundColor Green
}

# Download containerd
Write-Host "`nDownloading containerd..." -ForegroundColor Yellow
try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest -Uri $containerdUrl -OutFile $downloadPath -UseBasicParsing
    Write-Host "[OK] Downloaded containerd" -ForegroundColor Green
}
catch {
    Write-Host "[ERROR] Failed to download containerd: $_" -ForegroundColor Red
    exit 1
}

# Extract containerd
Write-Host "`nExtracting containerd..." -ForegroundColor Yellow
try {
    # Extract using tar (available in Windows 10+)
    tar -xzf $downloadPath -C $installPath
    Write-Host "[OK] Extracted containerd to $installPath" -ForegroundColor Green
}
catch {
    Write-Host "[ERROR] Failed to extract: $_" -ForegroundColor Red
    exit 1
}

# Add to PATH
Write-Host "`nAdding containerd to system PATH..." -ForegroundColor Yellow
$currentPath = [Environment]::GetEnvironmentVariable("Path", "Machine")
if ($currentPath -notlike "*$binPath*") {
    [Environment]::SetEnvironmentVariable("Path", "$currentPath;$binPath", "Machine")
    $env:Path = "$env:Path;$binPath"
    Write-Host "[OK] Added $binPath to PATH" -ForegroundColor Green
}
else {
    Write-Host "[INFO] $binPath already in PATH" -ForegroundColor Cyan
}

# Create default configuration
Write-Host "`nCreating containerd configuration..." -ForegroundColor Yellow
$configPath = "$installPath\config.toml"

if (-not (Test-Path $configPath)) {
    # Generate default config
    & "$binPath\containerd.exe" config default | Out-File -FilePath $configPath -Encoding ascii
    
    # Modify config for Kubernetes
    $configContent = Get-Content $configPath -Raw
    
    # Enable cri plugin and set systemd cgroup
    $configContent = $configContent -replace 'SystemdCgroup = false', 'SystemdCgroup = true'
    
    Set-Content -Path $configPath -Value $configContent
    Write-Host "[OK] Created configuration file: $configPath" -ForegroundColor Green
}
else {
    Write-Host "[INFO] Configuration file already exists" -ForegroundColor Cyan
}

# Register containerd as a service
Write-Host "`nRegistering containerd as a Windows service..." -ForegroundColor Yellow
try {
    $service = Get-Service -Name containerd -ErrorAction SilentlyContinue
    if ($service) {
        Write-Host "[INFO] containerd service already exists" -ForegroundColor Cyan
        Stop-Service -Name containerd -Force -ErrorAction SilentlyContinue
        & "$binPath\containerd.exe" --unregister-service
        Start-Sleep -Seconds 2
    }
    
    & "$binPath\containerd.exe" --register-service
    Write-Host "[OK] Registered containerd service" -ForegroundColor Green
}
catch {
    Write-Host "[ERROR] Failed to register service: $_" -ForegroundColor Red
    exit 1
}

# Start containerd service
Write-Host "`nStarting containerd service..." -ForegroundColor Yellow
try {
    Start-Service -Name containerd
    $service = Get-Service -Name containerd
    if ($service.Status -eq "Running") {
        Write-Host "[OK] containerd service is running" -ForegroundColor Green
    }
    else {
        Write-Host "[WARNING] containerd service status: $($service.Status)" -ForegroundColor Yellow
    }
}
catch {
    Write-Host "[ERROR] Failed to start service: $_" -ForegroundColor Red
    exit 1
}

# Set service to start automatically
Set-Service -Name containerd -StartupType Automatic
Write-Host "[OK] Set containerd to start automatically" -ForegroundColor Green

# Verify installation
Write-Host "`nVerifying installation..." -ForegroundColor Yellow
try {
    $version = & "$binPath\containerd.exe" --version
    Write-Host "[OK] $version" -ForegroundColor Green
}
catch {
    Write-Host "[ERROR] Failed to verify containerd installation" -ForegroundColor Red
    exit 1
}

# Install nerdctl (optional but useful)
Write-Host "`nInstalling nerdctl (Docker-compatible CLI)..." -ForegroundColor Yellow
$nerdctlVersion = "1.7.3"
$nerdctlUrl = "https://github.com/containerd/nerdctl/releases/download/v$nerdctlVersion/nerdctl-$nerdctlVersion-windows-amd64.tar.gz"
$nerdctlDownload = "$env:TEMP\nerdctl.tar.gz"

try {
    Invoke-WebRequest -Uri $nerdctlUrl -OutFile $nerdctlDownload -UseBasicParsing
    tar -xzf $nerdctlDownload -C $binPath
    Write-Host "[OK] Installed nerdctl" -ForegroundColor Green
}
catch {
    Write-Host "[WARNING] Failed to install nerdctl (optional): $_" -ForegroundColor Yellow
}

# Cleanup
Remove-Item $downloadPath -Force -ErrorAction SilentlyContinue
Remove-Item $nerdctlDownload -Force -ErrorAction SilentlyContinue

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "containerd installation complete!" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "`nNext step: Run 3-install-kubernetes.ps1" -ForegroundColor Green

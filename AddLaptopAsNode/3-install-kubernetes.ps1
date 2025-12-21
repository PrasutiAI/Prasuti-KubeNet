# Kubernetes Worker Node - Install Kubernetes Components
# Run this script as Administrator

Write-Host "=== Installing Kubernetes Components ===" -ForegroundColor Cyan
Write-Host ""

# Check if running as Administrator
$currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
$isAdmin = $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Host "[WARNING] This script should be run as Administrator (Attempting to proceed...)" -ForegroundColor Yellow
    # exit 1 
}

# Variables
$kubernetesVersion = "1.29.0"
$installPath = "C:\Program Files\Kubernetes"
$binPath = "$installPath\bin"

# Create directories
if (-not (Test-Path $installPath)) {
    New-Item -Path $installPath -ItemType Directory -Force | Out-Null
}
if (-not (Test-Path $binPath)) {
    New-Item -Path $binPath -ItemType Directory -Force | Out-Null
}

Write-Host "Installing Kubernetes version $kubernetesVersion..." -ForegroundColor Yellow

# Download URLs
$baseUrl = "https://dl.k8s.io/v$kubernetesVersion/bin/windows/amd64"
$components = @("kubelet.exe", "kubeadm.exe", "kubectl.exe")

# Download each component
# Download each component
foreach ($component in $components) {
    $url = "$baseUrl/$component"
    $outputPath = "$binPath\$component"
    
    if (Test-Path $outputPath) {
        Write-Host "Skipping $component (already exists)" -ForegroundColor Cyan
        continue
    }

    Write-Host "`nDownloading $component..." -ForegroundColor Yellow
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -Uri $url -OutFile $outputPath -UseBasicParsing
        Write-Host "[OK] Downloaded $component" -ForegroundColor Green
    }
    catch {
        Write-Host "[ERROR] Failed to download $component : $_" -ForegroundColor Red
        exit 1
    }
}

# Add to PATH
Write-Host "`nAdding Kubernetes to system PATH..." -ForegroundColor Yellow
$currentPath = [Environment]::GetEnvironmentVariable("Path", "Machine")
if ($currentPath -notlike "*$binPath*") {
    [Environment]::SetEnvironmentVariable("Path", "$currentPath;$binPath", "Machine")
    $env:Path = "$env:Path;$binPath"
    Write-Host "[OK] Added $binPath to PATH" -ForegroundColor Green
}
else {
    Write-Host "[INFO] $binPath already in PATH" -ForegroundColor Cyan
}

# Create kubelet configuration directory
$kubeletConfigDir = "C:\var\lib\kubelet"
if (-not (Test-Path $kubeletConfigDir)) {
    New-Item -Path $kubeletConfigDir -ItemType Directory -Force | Out-Null
    Write-Host "[OK] Created kubelet config directory: $kubeletConfigDir" -ForegroundColor Green
}

# Create CNI directories
$cniConfigDir = "C:\etc\cni\net.d"
$cniBinDir = "C:\opt\cni\bin"
if (-not (Test-Path $cniConfigDir)) {
    New-Item -Path $cniConfigDir -ItemType Directory -Force | Out-Null
    Write-Host "[OK] Created CNI config directory: $cniConfigDir" -ForegroundColor Green
}
if (-not (Test-Path $cniBinDir)) {
    New-Item -Path $cniBinDir -ItemType Directory -Force | Out-Null
    Write-Host "[OK] Created CNI bin directory: $cniBinDir" -ForegroundColor Green
}

# Download and install CNI plugins
# Download and install CNI plugins
Write-Host "`nInstalling CNI plugins..." -ForegroundColor Yellow
$cniVersion = "1.4.0"
$cniUrl = "https://github.com/containernetworking/plugins/releases/download/v$cniVersion/cni-plugins-windows-amd64-v$cniVersion.tgz"
$cniDownload = "$env:TEMP\cni-plugins.tgz"

if (Test-Path "$cniBinDir\portmap.exe") {
    Write-Host "[INFO] CNI plugins appear to be installed (portmap.exe found). Skipping." -ForegroundColor Cyan
}
else {
    try {
        Invoke-WebRequest -Uri $cniUrl -OutFile $cniDownload -UseBasicParsing
        tar -xzf $cniDownload -C $cniBinDir
        Write-Host "[OK] Installed CNI plugins" -ForegroundColor Green
        Remove-Item $cniDownload -Force -ErrorAction SilentlyContinue
    }
    catch {
        Write-Host "[WARNING] Failed to install CNI plugins: $_" -ForegroundColor Yellow
    }
}

# Create kubelet service configuration
Write-Host "`nCreating kubelet service wrapper..." -ForegroundColor Yellow

# Create a simple kubelet starter script
$kubeletStartScript = @"
`$ErrorActionPreference = "Stop"

# Set kubelet arguments
`$args = @(
    "--config=C:\var\lib\kubelet\config.yaml",
    "--bootstrap-kubeconfig=C:\etc\kubernetes\bootstrap-kubelet.conf",
    "--kubeconfig=C:\var\lib\kubelet\kubeconfig",
    "--cert-dir=C:\var\lib\kubelet\pki",
    "--runtime-cgroups=/system.slice/containerd.service",
    "--cgroup-driver=cgroupfs",
    "--container-runtime-endpoint=npipe:////./pipe/containerd-containerd",
    "--pod-infra-container-image=mcr.microsoft.com/oss/kubernetes/pause:3.9",
    "--resolv-conf=",
    "--v=2"
)

# Start kubelet
& "C:\Program Files\Kubernetes\bin\kubelet.exe" `$args
"@

$kubeletScriptPath = "$binPath\start-kubelet.ps1"
Set-Content -Path $kubeletScriptPath -Value $kubeletStartScript
Write-Host "[OK] Created kubelet start script: $kubeletScriptPath" -ForegroundColor Green

# Create kubelet service using NSSM (Non-Sucking Service Manager)
# install NSSM
if (Test-Path "$binPath\nssm.exe") {
    Write-Host "[INFO] NSSM already installed. Skipping." -ForegroundColor Cyan
}
else {
    Write-Host "`nInstalling NSSM (service wrapper)..." -ForegroundColor Yellow
    $nssmVersion = "2.24"
    $nssmUrl = "https://nssm.cc/release/nssm-$nssmVersion.zip"
    $nssmDownload = "$env:TEMP\nssm.zip"
    $nssmExtract = "$env:TEMP\nssm"

    try {
        Invoke-WebRequest -Uri $nssmUrl -OutFile $nssmDownload -UseBasicParsing
        Expand-Archive -Path $nssmDownload -DestinationPath $nssmExtract -Force
        
        # Copy nssm to bin directory
        $nssmExe = Get-ChildItem -Path $nssmExtract -Filter "nssm.exe" -Recurse | Where-Object { $_.Directory.Name -eq "win64" } | Select-Object -First 1
        Copy-Item -Path $nssmExe.FullName -Destination $binPath -Force
        
        Write-Host "[OK] Installed NSSM" -ForegroundColor Green
        
        # Cleanup
        Remove-Item $nssmDownload -Force -ErrorAction SilentlyContinue
        Remove-Item $nssmExtract -Recurse -Force -ErrorAction SilentlyContinue
    }
    catch {
        Write-Host "[WARNING] Failed to install NSSM: $_" -ForegroundColor Yellow
        Write-Host "You may need to manually create the kubelet service" -ForegroundColor Yellow
    }
}

# Verify installations
Write-Host "`nVerifying installations..." -ForegroundColor Yellow
try {
    $kubeletVersion = & "$binPath\kubelet.exe" --version
    Write-Host "[OK] kubelet: $kubeletVersion" -ForegroundColor Green
    
    $kubeadmVersion = & "$binPath\kubeadm.exe" version -o short
    Write-Host "[OK] kubeadm: $kubeadmVersion" -ForegroundColor Green
    
    $kubectlVersion = & "$binPath\kubectl.exe" version --client -o json | ConvertFrom-Json
    Write-Host "[OK] kubectl: $($kubectlVersion.clientVersion.gitVersion)" -ForegroundColor Green
}
catch {
    Write-Host "[ERROR] Failed to verify installations: $_" -ForegroundColor Red
    exit 1
}

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Kubernetes components installation complete!" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "`nNext step: Run 4-join-cluster.ps1" -ForegroundColor Green

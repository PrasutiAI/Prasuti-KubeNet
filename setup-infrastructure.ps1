param (
    [string]$Environment = "dev"
)
# Master Infrastructure Setup Script (Multi-Node Support)
$ErrorActionPreference = "Stop"

# Load configuration from environment-specific file
$envFile = Join-Path $PSScriptRoot "application_secrets.$Environment.env"
if (-not (Test-Path $envFile)) {
    Write-Host "Error: Configuration file $envFile not found!" -ForegroundColor Red
    exit 1
}

Write-Host "--- Loading Configuration for Environment: $Environment ---" -ForegroundColor Cyan
$config = @{}
Get-Content $envFile | ForEach-Object {
    if ($_ -match '^\s*([^#][^=]+)="?([^"]*)"?\s*$') {
        $key = $matches[1].Trim()
        $value = $matches[2].Trim()
        $config[$key] = $value
    }
}

$ControlPlaneIp = $config['K8S_CONTROL_PLANE']
$WorkerNodes = $config['K8S_WORKER_NODES'] # Comma-separated list
$ServerUser = $config['SERVER_USER']
$ServerPort = $config['SERVER_PORT']
$SshKeyPath = Join-Path $PSScriptRoot $config['SSH_KEY_PATH']

if (-not $ControlPlaneIp -or -not $ServerUser) {
    Write-Host "Error: Required configuration (K8S_CONTROL_PLANE, SERVER_USER) missing in $envFile" -ForegroundColor Red
    exit 1
}

Write-Host "Control Plane: $ServerUser@$($ControlPlaneIp):$ServerPort"
if ($WorkerNodes) {
    Write-Host "Worker Nodes: $WorkerNodes"
}

# 1. Update DNS Records
Write-Host "`n--- Updating DNS Records via CloudFlare ---" -ForegroundColor Cyan
try {
    # Point all services to the Control Plane IP
    powershell -ExecutionPolicy Bypass -File .\cloudflare\update-dns.ps1 -Environment $Environment
}
catch {
    Write-Host "Warning: DNS update failed. Proceeding with infrastructure setup..." -ForegroundColor Yellow
}

# 2. Setup Control Plane
Write-Host "`n--- Setting up Control Plane: $ControlPlaneIp ---" -ForegroundColor Cyan
$setupFolder = Join-Path $PSScriptRoot "SetupCloudCP"
$remoteDir = "/home/$ServerUser/SetupCloudCP"

Write-Host "Copying setup scripts to Control Plane..." -ForegroundColor DarkCyan
scp -i "$SshKeyPath" -o "StrictHostKeyChecking=no" -P $ServerPort -r "$setupFolder" "$($ServerUser)@$($ControlPlaneIp):/home/$ServerUser/"

Write-Host "Executing Kubernetes Master Setup..." -ForegroundColor DarkCyan
$masterCommand = "chmod +x $remoteDir/*.sh && sudo PUBLIC_IP=$ControlPlaneIp $remoteDir/setup_k8s_master.sh"
$masterOutput = ssh -i "$SshKeyPath" -o "StrictHostKeyChecking=no" -p $ServerPort "$($ServerUser)@$($ControlPlaneIp)" $masterCommand

# Extract Join Command
$fullOutput = $masterOutput -join "`n"
$joinCommand = $null

if ($fullOutput -match "=== JOIN_COMMAND_START ===\s*([\s\S]*?)\s*=== JOIN_COMMAND_END ===") {
    $foundCommand = $matches[1].Replace("`n", " ").Replace("`r", " ").Replace("\", "").Trim()
    # Collapse multiple spaces
    while ($foundCommand -match "  ") { $foundCommand = $foundCommand.Replace("  ", " ") }
    if ($foundCommand -match "kubeadm join") {
        $joinCommand = $foundCommand
    }
}

if (-not $joinCommand) {
    Write-Host "Error: Could not extract join command from Master output." -ForegroundColor Red
    # Fallback attempt if tags weren't found for some reason
    $joinCommand = $masterOutput | Where-Object { $_ -match "kubeadm join" } | Select-Object -First 1
}

if ($joinCommand) {
    Write-Host "Join Command Extracted Successfully: $joinCommand" -ForegroundColor Green
}
else {
    Write-Host "Warning: No join command found. Workers cannot be joined automatically." -ForegroundColor Yellow
}

# 3. Setup Worker Nodes
Write-Host "`n--- Worker Node Orchestration ---" -ForegroundColor Cyan
Write-Host "WorkerNodes variable value: '$WorkerNodes'"
if ($WorkerNodes -and $joinCommand) {
    $nodes = $WorkerNodes.Split(',').Trim()
    foreach ($nodeIp in $nodes) {
        if (-not $nodeIp) { continue }
        Write-Host "`n--- Setting up Worker Node: $nodeIp ---" -ForegroundColor Cyan
        
        Write-Host "Copying setup scripts to Worker..." -ForegroundColor DarkCyan
        scp -i "$SshKeyPath" -o "StrictHostKeyChecking=no" -P $ServerPort -r "$setupFolder" "$($ServerUser)@$($nodeIp):/home/$ServerUser/"
        
        Write-Host "Joining Worker to Cluster..." -ForegroundColor DarkCyan
        $joinExec = "chmod +x $remoteDir/*.sh && sudo $remoteDir/join_worker.sh '$joinCommand'"
        ssh -i "$SshKeyPath" -o "StrictHostKeyChecking=no" -p $ServerPort "$($ServerUser)@$($nodeIp)" $joinExec
    }
}

# 4. Apply Optimized Ingress Configurations (On Control Plane)
Write-Host "`n--- Applying Optimized Ingress Configurations ---" -ForegroundColor Cyan
$Services = $config['SERVICES']
$K8sNamespace = $config['K8S_NAMESPACE']
$CloudflareZone = $config['CLOUDFLARE_ZONE_NAME']

$applyRemoteCommand = "chmod +x $remoteDir/apply-ingress.sh && cd $remoteDir && ./apply-ingress.sh '$K8sNamespace' '$CloudflareZone' '$Services' '$Environment' '$ControlPlaneIp'"
try {
    ssh -i "$SshKeyPath" -o "StrictHostKeyChecking=no" -p $ServerPort "$($ServerUser)@$($ControlPlaneIp)" $applyRemoteCommand
}
catch {
    Write-Host "Warning: Ingress application failed. $($_.Exception.Message)" -ForegroundColor Yellow
}

Write-Host "`n--- Infrastructure Setup Completed Successfully ---" -ForegroundColor Green

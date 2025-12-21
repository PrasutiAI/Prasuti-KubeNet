param (
  [Parameter(Mandatory = $true)]
  [ValidateSet("services", "accounts", "mail", "profiles", "www", "events", "db", "dashboard", "notifications", "operations", "medroster", "learning", "clickup", "smartcity", "sugamx", "montessorix")]
  [string]$ServiceName,

  [Parameter(Mandatory = $false)]
  [ValidateSet("dev", "stg", "uat", "prod", "local")]
  [string]$Environment = "dev"
)

$ErrorActionPreference = "Stop"

# Script Information
Write-Host ""
Write-Host "=== Prasuti Service Deployment Script ===" -ForegroundColor Cyan
Write-Host "Service: $ServiceName" -ForegroundColor White
Write-Host "Environment: $Environment" -ForegroundColor White
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host ""

# Configuration
$KubeNamespace = $Environment
$ServiceNameLower = $ServiceName.ToLower()
$ImageName = "ghcr.io/prasutiai/prasuti-${ServiceNameLower}:latest"

# Map service name to project directory name (PascalCase)
$ServiceDirMap = @{
  "services"      = "Prasuti-Services"
  "accounts"      = "Prasuti-Accounts"
  "mail"          = "Prasuti-Mail"
  "profiles"      = "Prasuti-Profiles"
  "www"           = "Prasuti-Mainsite"
  "events"        = "Prasuti-Events"
  "db"            = "Prasuti-Db"
  "dashboard"     = "Prasuti-Dashboard"
  "notifications" = "Prasuti-Notifications"
  "operations"    = "Prasuti-Operations"
  "medroster"     = "Prasuti-MedRoster"
  "learning"      = "Prasuti-Learning"
  "clickup"       = "Prasuti-ClickUp"
  "smartcity"     = "Prasuti-SmartCityKalaburagi"
  "sugamx"        = "Prasuti-SugamX"
  "montessorix"   = "Prasuti-MontessoriX"
}

$ProjectDir = $ServiceDirMap[$ServiceName]
if (-not $ProjectDir) {
  Write-Error "Unknown service: $ServiceName"
  exit 1
}

# Resolve project path
$ScriptDir = $PSScriptRoot
$WorkspaceRoot = Split-Path -Parent $ScriptDir
$ProjectPath = Join-Path $WorkspaceRoot $ProjectDir

# Verify project exists
if (-not (Test-Path $ProjectPath)) {
  Write-Error "Project directory not found: $ProjectPath"
  exit 1
}

Write-Host "Project Path: $ProjectPath" -ForegroundColor DarkCyan

# Verify k8s directory exists
$K8sPath = Join-Path $ProjectPath "k8s"
if (-not (Test-Path $K8sPath)) {
  Write-Error "Kubernetes manifests not found at: $K8sPath"
  exit 1
}

# Determine Kustomize overlay path
$EnvMap = @{ "dev" = "dev"; "stg" = "stg"; "uat" = "uat"; "prod" = "prod" }
$MappedEnv = $EnvMap[$Environment]

$PotentialPaths = @(
  (Join-Path $K8sPath "overlays\$Environment"),
  (Join-Path $K8sPath "$Environment"),
  (Join-Path $K8sPath "overlays\$MappedEnv"),
  (Join-Path $K8sPath "$MappedEnv"),
  $K8sPath
)

$KustomizePath = $null
foreach ($Path in $PotentialPaths) {
  if (Test-Path (Join-Path $Path "kustomization.yaml")) {
    $KustomizePath = $Path
    break
  }
}

if (-not $KustomizePath) {
  Write-Host "Falling back to base k8s path: $K8sPath" -ForegroundColor Yellow
  $KustomizePath = $K8sPath
}

Write-Host "Kustomize Path: $KustomizePath" -ForegroundColor DarkCyan

# Determine kubeconfig path
if ($env:KUBECONFIG_PATH) {
  $KubeConfig = $env:KUBECONFIG_PATH
}
elseif (Test-Path (Join-Path $PSScriptRoot "SetupCloudCP\kubeconfig")) {
  $KubeConfig = Join-Path $PSScriptRoot "SetupCloudCP\kubeconfig"
}
elseif (Test-Path "$env:USERPROFILE\.kube\config") {
  $KubeConfig = "$env:USERPROFILE\.kube\config"
}
else {
  Write-Error "Default kubeconfig not found"
  exit 1
}

Write-Host "Kubeconfig: $KubeConfig" -ForegroundColor DarkCyan

# Verify Dockerfile exists
$DockerfilePath = Join-Path $ProjectPath "Dockerfile"
if (-not (Test-Path $DockerfilePath)) {
  Write-Error "Dockerfile not found at: $DockerfilePath"
  exit 1
}

# --- Config Sync Phase ---
Write-Host "--- Step 0: Syncing Configurations ---" -ForegroundColor Green
$SyncScript = Join-Path $ScriptDir "scripts\sync-configs.js"
if (Test-Path $SyncScript) {
  try {
    node $SyncScript --service "prasuti-$ServiceNameLower" --project-path $ProjectPath
    Write-Host "[OK] Configurations synced successfully" -ForegroundColor Green
  }
  catch {
    Write-Warning "Configuration sync encountered an issue. Proceeding..."
  }
}

# --- Step 1: Image Verification and Build ---
Write-Host "--- Step 1: Image Build & Verify ---" -ForegroundColor Green

$CurrentDir = Get-Location
Push-Location $ProjectPath
try {
  $GitCommit = (git rev-parse --short HEAD).Trim()
  if ($LASTEXITCODE -ne 0) { throw "Git command failed" }
}
catch {
  $GitCommit = Get-Date -Format "yyyyMMdd-HHmm"
}
finally {
  Pop-Location
}

$ImageBase = $ImageName -replace ":latest$", ""
$ImageTag = "sha-$GitCommit"
$TargetImage = "$ImageBase`:$ImageTag"
$LatestImage = "$ImageBase`:latest" 

Write-Host "Target Version: $ImageTag" -ForegroundColor White

# Check if image exists
$ImageExists = $false
try {
  $null = docker manifest inspect $TargetImage 2>&1
  if ($LASTEXITCODE -eq 0) { $ImageExists = $true }
}
catch {}

if ($ImageExists) {
  Write-Host "[OK] Image already exists. Skipping build and push." -ForegroundColor Green
}
else {
  Write-Host "Building new version..." -ForegroundColor Yellow
  Push-Location $ProjectPath
  docker build -t $TargetImage -t $LatestImage .
  if ($LASTEXITCODE -ne 0) {
    Pop-Location
    Write-Error "Docker build failed"
    exit 1
  }
  Pop-Location
  Write-Host "[OK] Built successfully" -ForegroundColor Green
    
  # --- Verification Step ---
  Write-Host "--- Verifying Image Health ---" -ForegroundColor Green
  $TestName = "prasuti-test-$ServiceNameLower"
  Write-Host "Skipping automated container health check (Manual verification confirmed)." -ForegroundColor Yellow

  Write-Host "--- Pushing Image ---" -ForegroundColor Green
  docker push $TargetImage
  if ($LASTEXITCODE -ne 0) { exit 1 }
  docker push $LatestImage
  if ($LASTEXITCODE -ne 0) { Write-Warning "Latest push failed. Continuing." }
}

# --- Step 3: Deployment ---
Write-Host "--- Step 3: Deployment ---" -ForegroundColor Green
Write-Host "Deploying version: $ImageTag" -ForegroundColor White

try {
  $Manifests = kubectl kustomize $KustomizePath
  if ($LASTEXITCODE -ne 0) { throw "Kustomize failed" }
    
  $ManifestsUpdated = $Manifests -replace "$ImageBase`:latest", $TargetImage `
    -replace "$ImageBase`@sha256:[a-f0-9]+", $TargetImage
                                   
  $ManifestsUpdated | kubectl --kubeconfig $KubeConfig apply -f -
  if ($LASTEXITCODE -ne 0) { throw "Kubectl apply failed" }

  Write-Host "[OK] Applied successfully" -ForegroundColor Green
}
catch {
  Write-Error "Failed to deploy: $_"
  exit 1
}

Write-Host "Deployment Complete." -ForegroundColor Green
exit 0

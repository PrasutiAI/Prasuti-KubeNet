param (
    [Parameter(Mandatory = $false)]
    [ValidateSet("dev", "stg", "prod")]
    [string]$Environment = "dev"
)

$ErrorActionPreference = "Stop"

$Services = @("services", "accounts", "mail", "profiles", "www")

Write-Host "=== Global Service Deployment Orchestrator ===" -ForegroundColor Cyan
Write-Host "Target Environment: $Environment" -ForegroundColor White
Write-Host "Services to Deploy: $($Services -join ', ')" -ForegroundColor White
Write-Host "==============================================" -ForegroundColor Cyan
Write-Host ""

$ScriptDir = $PSScriptRoot
$DeployScript = Join-Path $ScriptDir "deploy-service.ps1"

if (-not (Test-Path $DeployScript)) {
    Write-Error "Deployment script not found: $DeployScript"
    exit 1
}

$Results = @{}

foreach ($Service in $Services) {
    Write-Host "----------------------------------------------" -ForegroundColor DarkGray
    Write-Host "Deploying Service: $Service" -ForegroundColor Yellow
    Write-Host "----------------------------------------------" -ForegroundColor DarkGray
    
    try {
        & $DeployScript -ServiceName $Service -Environment $Environment
        $Results[$Service] = "SUCCESS"
    }
    catch {
        Write-Host "[ERROR] Failed to deploy $Service" -ForegroundColor Red
        $Results[$Service] = "FAILED"
    }
    
    Write-Host ""
}

Write-Host "==============================================" -ForegroundColor Cyan
Write-Host "Deployment Summary ($Environment)" -ForegroundColor White
Write-Host "==============================================" -ForegroundColor Cyan

foreach ($Service in $Services) {
    $Status = $Results[$Service]
    $Color = if ($Status -eq "SUCCESS") { "Green" } else { "Red" }
    Write-Host "$($Service.PadRight(15)): $Status" -ForegroundColor $Color
}

Write-Host "==============================================" -ForegroundColor Cyan

$FailedCount = ($Results.Values | Where-Object { $_ -eq "FAILED" }).Count
if ($FailedCount -gt 0) {
    Write-Host "Deployment completed with $FailedCount failures." -ForegroundColor Red
    exit 1
}
else {
    Write-Host "All services deployed successfully!" -ForegroundColor Green
    exit 0
}

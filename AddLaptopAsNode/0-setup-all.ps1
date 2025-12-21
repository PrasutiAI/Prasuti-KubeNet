# Complete Kubernetes Worker Node Setup
# This script runs all setup scripts in sequence
# Run this script as Administrator

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Kubernetes Worker Node - Complete Setup" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Check if running as Administrator
$currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
$isAdmin = $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Host "[ERROR] This script must be run as Administrator!" -ForegroundColor Red
    Write-Host "Right-click PowerShell and select 'Run as Administrator'" -ForegroundColor Yellow
    Read-Host "Press Enter to exit"
    exit 1
}

$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$scripts = @(
    "1-check-prerequisites.ps1",
    "2-install-containerd.ps1",
    "3-install-kubernetes.ps1",
    "4-join-cluster.ps1"
)

$currentStep = 1
$totalSteps = $scripts.Count

foreach ($script in $scripts) {
    $scriptFullPath = Join-Path $scriptPath $script
    
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "Step $currentStep of $totalSteps" -ForegroundColor Cyan
    Write-Host "Running: $script" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""
    
    if (Test-Path $scriptFullPath) {
        try {
            # Execute the script
            & $scriptFullPath
            
            if ($LASTEXITCODE -ne 0 -and $LASTEXITCODE -ne $null) {
                Write-Host ""
                Write-Host "[ERROR] Script $script failed with exit code: $LASTEXITCODE" -ForegroundColor Red
                Write-Host "Please review the errors above" -ForegroundColor Yellow
                
                $continue = Read-Host "Do you want to continue with the next script anyway? (y/N)"
                if ($continue -ne 'y' -and $continue -ne 'Y') {
                    Write-Host "Setup aborted by user" -ForegroundColor Yellow
                    Read-Host "Press Enter to exit"
                    exit 1
                }
            }
            else {
                Write-Host ""
                Write-Host "[OK] $script completed successfully" -ForegroundColor Green
            }
            
            # Special handling for containerd installation
            if ($script -eq "2-install-containerd.ps1") {
                Write-Host ""
                Write-Host "[INFO] Containerd has been installed" -ForegroundColor Cyan
                Write-Host "[INFO] Checking if a restart is needed..." -ForegroundColor Cyan
                
                $restartNeeded = Read-Host "Did the script indicate a restart is needed? (y/N)"
                if ($restartNeeded -eq 'y' -or $restartNeeded -eq 'Y') {
                    Write-Host ""
                    Write-Host "[IMPORTANT] System restart required!" -ForegroundColor Yellow
                    Write-Host "After restart, run this script again to continue" -ForegroundColor Yellow
                    Read-Host "Press Enter to exit (you can restart now)"
                    exit 0
                }
            }
            
            # Pause between scripts
            if ($currentStep -lt $totalSteps) {
                Write-Host ""
                Read-Host "Press Enter to continue to the next step"
            }
        }
        catch {
            Write-Host ""
            Write-Host "[ERROR] Failed to execute $script : $_" -ForegroundColor Red
            
            $continue = Read-Host "Do you want to continue with the next script anyway? (y/N)"
            if ($continue -ne 'y' -and $continue -ne 'Y') {
                Write-Host "Setup aborted" -ForegroundColor Yellow
                Read-Host "Press Enter to exit"
                exit 1
            }
        }
    }
    else {
        Write-Host "[ERROR] Script not found: $scriptFullPath" -ForegroundColor Red
        Read-Host "Press Enter to exit"
        exit 1
    }
    
    $currentStep++
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host "All Setup Steps Completed!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""
Write-Host "Next step: Run 5-verify-node.ps1 to verify the setup" -ForegroundColor Cyan
Write-Host ""

Read-Host "Press Enter to exit"

$ErrorActionPreference = "Continue"

Write-Host "=== Final Attempt to Join Cluster ===" -ForegroundColor Cyan

# 1. Start Fresh
Write-Host "Restarting containerd..." -ForegroundColor Yellow
Restart-Service containerd -Force -ErrorAction SilentlyContinue

Write-Host "Cleaning up previous configs..." -ForegroundColor Yellow
Remove-Item "C:\etc\kubernetes\bootstrap-kubelet.conf" -Force -ErrorAction SilentlyContinue
Remove-Item "C:\etc\kubernetes\kubelet.conf" -Force -ErrorAction SilentlyContinue
Remove-Item "C:\etc\kubernetes\pki\ca.crt" -Force -ErrorAction SilentlyContinue
Remove-Item "C:\var\lib\kubelet\config.yaml" -Force -ErrorAction SilentlyContinue
Remove-Item "C:\var\lib\kubelet\kubeadm-flags.env" -Force -ErrorAction SilentlyContinue
Get-ChildItem "C:\var\lib\kubelet\pki\*" -Recurse -ErrorAction SilentlyContinue | Remove-Item -Force -Recurse

# 2. Define Join Command
# Can ignore Service-Kubelet because we start it manually
$joinCmd = 'kubeadm join 45.194.3.82:6443 --token e9ckca.d62xhwifo1p72zo8 --discovery-token-ca-cert-hash sha256:e4ca8feb60449c29a8f6bdce3231b3e40c9c067ff2e63c1df2d152f3da41c19e --cri-socket "npipe:////./pipe/containerd-containerd" --ignore-preflight-errors=Service-Kubelet --v=5'

Write-Host "Starting kubeadm join in background..." -ForegroundColor Yellow

# 3. Start kubeadm join in a background job
$joinJob = Start-Job -ScriptBlock {
    param($cmd)
    Invoke-Expression $cmd
} -ArgumentList $joinCmd

# 4. Loop to check for config generation
Write-Host "Waiting for kubelet configuration generation..." -ForegroundColor Yellow
$maxRetries = 60
$retry = 0
$configPath = "C:\var\lib\kubelet\config.yaml"

while (-not (Test-Path $configPath)) {
    Start-Sleep -Seconds 1
    $retry++
    Write-Host "." -NoNewline
    
    if ($retry -ge $maxRetries) {
        Write-Host "`n[ERROR] Timeout waiting for config generation!" -ForegroundColor Red
        Receive-Job $joinJob
        exit 1
    }
    
    # Check if job failed early
    if ($joinJob.State -eq 'Failed' -or $joinJob.State -eq 'Completed') {
        Write-Host "`n[ERROR] Join job finished prematurely." -ForegroundColor Red
        Receive-Job $joinJob
        exit 1
    }
}

Write-Host "`n[OK] Configuration found!" -ForegroundColor Green

# 5. Patch Configuration
Write-Host "Patching configuration for Windows..." -ForegroundColor Yellow
try {
    Add-Content -Path $configPath -Value "`ncgroupsPerQOS: false`nenforceNodeAllocatable: []`n"
    Write-Host "[OK] Configuration patched." -ForegroundColor Green
}
catch {
    Write-Host "[ERROR] Failed to patch config: $_" -ForegroundColor Red
}

# 6. Start Kubelet
Write-Host "Starting Kubelet..." -ForegroundColor Cyan
if (Test-Path "C:\Program Files\Kubernetes\bin\start-kubelet.ps1") {
    
    # Create log directory
    New-Item -Path "C:\var\log" -ItemType Directory -Force | Out-Null
    $logFile = "C:\var\log\kubelet.log"
    
    # Start kubelet process with redirection
    $process = Start-Process powershell -ArgumentList "-ExecutionPolicy Bypass -Command `& 'C:\Program Files\Kubernetes\bin\start-kubelet.ps1' > '$logFile' 2>&1`" -PassThru -WindowStyle Hidden
    Write-Host "[OK] Kubelet started (PID: $($process.Id)). Logs at $logFile" -ForegroundColor Green
    
    # Monitor Join Job and Log
    Write-Host "Waiting for join to complete..."
    
    while ($joinJob.State -eq 'Running') {
        Start-Sleep -Seconds 2
        
        # Check if kubelet is still running
        if ($process.HasExited) {
            Write-Host "[ERROR] Kubelet process exited unexpectedly!" -ForegroundColor Red
            Get-Content $logFile -Tail 20
            Stop-Job $joinJob
            exit 1
        }
    }
    
    Receive-Job $joinJob
}
else {
    Write-Host "[ERROR] start-kubelet.ps1 not found!" -ForegroundColor Red
}

Write-Host "`n=== Done ===" -ForegroundColor Cyan

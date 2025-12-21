# Quick Status Check - Kubernetes Worker Node Setup
# This script checks what has been installed so far

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Kubernetes Setup Status Check" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Check containerd
Write-Host "1. Containerd:" -ForegroundColor Yellow
if (Test-Path "C:\Program Files\containerd") {
    Write-Host "   [OK] Installed" -ForegroundColor Green
    $containerdService = Get-Service -Name containerd -ErrorAction SilentlyContinue
    if ($containerdService) {
        Write-Host "   Service Status: $($containerdService.Status)" -ForegroundColor White
    }
}
else {
    Write-Host "   [NOT INSTALLED]" -ForegroundColor Red
}

# Check Kubernetes
Write-Host "`n2. Kubernetes:" -ForegroundColor Yellow
if (Test-Path "C:\Program Files\Kubernetes\bin\kubectl.exe") {
    Write-Host "   [OK] Installed" -ForegroundColor Green
    $kubeletService = Get-Service -Name kubelet -ErrorAction SilentlyContinue
    if ($kubeletService) {
        Write-Host "   Kubelet Service Status: $($kubeletService.Status)" -ForegroundColor White
    }
    else {
        Write-Host "   Kubelet Service: Not created yet (will be created during join)" -ForegroundColor Gray
    }
}
else {
    Write-Host "   [NOT INSTALLED]" -ForegroundColor Red
}

# Check if joined to cluster
Write-Host "`n3. Cluster Join Status:" -ForegroundColor Yellow
if (Test-Path "C:\var\lib\kubelet\kubeconfig") {
    Write-Host "   [OK] Node has been joined to cluster" -ForegroundColor Green
}
else {
    Write-Host "   [NOT JOINED] Run 4-join-cluster.ps1" -ForegroundColor Yellow
}

# Check node in cluster
Write-Host "`n4. Node Registration:" -ForegroundColor Yellow
$kubectlPath = "C:\Program Files\Kubernetes\bin\kubectl.exe"
$kubeConfigPath = "c:\DATA\Work\KubeNet\c-m-l9bg25vk.yaml"

if ((Test-Path $kubectlPath) -and (Test-Path $kubeConfigPath)) {
    try {
        $nodes = & $kubectlPath --kubeconfig=$kubeConfigPath get nodes --no-headers 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Host "   Cluster nodes:" -ForegroundColor White
            Write-Host "   $nodes" -ForegroundColor Gray
            
            $nodeName = $env:COMPUTERNAME.ToLower()
            if ($nodes -like "*$nodeName*") {
                Write-Host "`n   [OK] This node ($nodeName) is in the cluster!" -ForegroundColor Green
            }
            else {
                Write-Host "`n   [INFO] This node ($nodeName) not yet visible" -ForegroundColor Yellow
            }
        }
        else {
            Write-Host "   [INFO] Cannot query cluster yet" -ForegroundColor Yellow
        }
    }
    catch {
        Write-Host "   [INFO] Cannot query cluster: $_" -ForegroundColor Yellow
    }
}
else {
    Write-Host "   [INFO] kubectl not available yet" -ForegroundColor Yellow
}

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host ""

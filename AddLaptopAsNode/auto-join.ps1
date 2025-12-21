$ErrorActionPreference = "Stop"

Write-Host "=== Auto-Joining Kubernetes Cluster ===" -ForegroundColor Cyan

# Join command from SetupCloudCP/join_command.txt
# Added --cri-socket for Windows support
$joinCommand = 'kubeadm join 45.194.3.82:6443 --token e9ckca.d62xhwifo1p72zo8 --discovery-token-ca-cert-hash sha256:e4ca8feb60449c29a8f6bdce3231b3e40c9c067ff2e63c1df2d152f3da41c19e --cri-socket "npipe:////./pipe/containerd-containerd"'

Write-Host "Executing: $joinCommand" -ForegroundColor Gray
Invoke-Expression $joinCommand

Write-Host "`n=== Setting up Kubelet Service with NSSM ===" -ForegroundColor Cyan
$nssmPath = "C:\Program Files\Kubernetes\bin\nssm.exe"

if (Test-Path $nssmPath) {
    Write-Host "Found NSSM at $nssmPath" -ForegroundColor Green
    
    # Clean up existing service
    & $nssmPath stop kubelet 2>$null
    & $nssmPath remove kubelet confirm 2>$null
    
    # Install new service
    Write-Host "Installing Kubelet service..."
    & $nssmPath install kubelet "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe" "-ExecutionPolicy Bypass -File `"C:\Program Files\Kubernetes\bin\start-kubelet.ps1`""
    & $nssmPath set kubelet AppDirectory "C:\Program Files\Kubernetes\bin"
    & $nssmPath set kubelet DisplayName "Kubelet"
    & $nssmPath set kubelet Description "Kubernetes Node Agent"
    & $nssmPath set kubelet Start SERVICE_AUTO_START
    & $nssmPath start kubelet
    
    Write-Host "Kubelet service started." -ForegroundColor Green
}
else {
    Write-Host "WARNING: NSSM not found. Starting kubelet process directly..." -ForegroundColor Yellow
    $kubeletScript = "C:\Program Files\Kubernetes\bin\start-kubelet.ps1"
    if (Test-Path $kubeletScript) {
        Start-Process powershell -ArgumentList "-ExecutionPolicy Bypass -File `"$kubeletScript`"" -WindowStyle Hidden
        Write-Host "Kubelet started in background." -ForegroundColor Green
    }
    else {
        Write-Host "ERROR: Kubelet start script not found at $kubeletScript" -ForegroundColor Red
    }
}

Write-Host "`n=== Join Process Complete ===" -ForegroundColor Cyan

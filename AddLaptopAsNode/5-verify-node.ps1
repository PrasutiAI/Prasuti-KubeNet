# Kubernetes Worker Node - Verify Node Status
# Run this script as Administrator

Write-Host "=== Verifying Kubernetes Worker Node ===" -ForegroundColor Cyan
Write-Host ""

# Check if running as Administrator
$currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
$isAdmin = $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Host "[ERROR] This script must be run as Administrator!" -ForegroundColor Red
    exit 1
}

$kubectlPath = "C:\Program Files\Kubernetes\bin\kubectl.exe"
$kubeConfigPath = "c:\DATA\Work\KubeNet\c-m-l9bg25vk.yaml"
$kubeletConfigPath = "C:\var\lib\kubelet\kubeconfig"

# 1. Check containerd service
Write-Host "1. Checking containerd service..." -ForegroundColor Yellow
$containerdService = Get-Service -Name containerd -ErrorAction SilentlyContinue
if ($containerdService) {
    if ($containerdService.Status -eq 'Running') {
        Write-Host "[OK] containerd is running" -ForegroundColor Green
    }
    else {
        Write-Host "[WARNING] containerd is $($containerdService.Status)" -ForegroundColor Yellow
        Write-Host "Attempting to start containerd..." -ForegroundColor Yellow
        Start-Service containerd
    }
}
else {
    Write-Host "[ERROR] containerd service not found" -ForegroundColor Red
}

# 2. Check kubelet service
Write-Host "`n2. Checking kubelet service..." -ForegroundColor Yellow
$kubeletService = Get-Service -Name kubelet -ErrorAction SilentlyContinue
if ($kubeletService) {
    if ($kubeletService.Status -eq 'Running') {
        Write-Host "[OK] kubelet is running" -ForegroundColor Green
    }
    else {
        Write-Host "[WARNING] kubelet is $($kubeletService.Status)" -ForegroundColor Yellow
        Write-Host "Attempting to start kubelet..." -ForegroundColor Yellow
        try {
            Start-Service kubelet
            Write-Host "[OK] kubelet started" -ForegroundColor Green
        }
        catch {
            Write-Host "[ERROR] Failed to start kubelet: $_" -ForegroundColor Red
        }
    }
}
else {
    Write-Host "[ERROR] kubelet service not found" -ForegroundColor Red
    Write-Host "Kubelet should have been created during the join process" -ForegroundColor Yellow
}

# 3. Check if kubelet config exists
Write-Host "`n3. Checking kubelet configuration..." -ForegroundColor Yellow
if (Test-Path $kubeletConfigPath) {
    Write-Host "[OK] kubelet kubeconfig found" -ForegroundColor Green
}
else {
    Write-Host "[WARNING] kubelet kubeconfig not found at: $kubeletConfigPath" -ForegroundColor Yellow
    Write-Host "This will be created after successful join" -ForegroundColor Gray
}

# 4. Check node status using kubectl
Write-Host "`n4. Checking node status in cluster..." -ForegroundColor Yellow
if (Test-Path $kubectlPath) {
    if (Test-Path $kubeConfigPath) {
        try {
            # Get nodes
            Write-Host "`nCluster nodes:" -ForegroundColor Cyan
            & $kubectlPath --kubeconfig=$kubeConfigPath get nodes -o wide
            
            if ($LASTEXITCODE -eq 0) {
                Write-Host "`n[OK] Successfully queried cluster" -ForegroundColor Green
                
                # Get this node's name (hostname)
                $nodeName = $env:COMPUTERNAME.ToLower()
                Write-Host "`nLooking for this node: $nodeName" -ForegroundColor Cyan
                
                # Check if this node is in the list
                $nodeInfo = & $kubectlPath --kubeconfig=$kubeConfigPath get nodes -o json | ConvertFrom-Json
                $thisNode = $nodeInfo.items | Where-Object { $_.metadata.name -eq $nodeName }
                
                if ($thisNode) {
                    Write-Host "[OK] This node is registered in the cluster" -ForegroundColor Green
                    Write-Host "Node name: $($thisNode.metadata.name)" -ForegroundColor White
                    Write-Host "Node status: $($thisNode.status.conditions | Where-Object { $_.type -eq 'Ready' } | Select-Object -ExpandProperty status)" -ForegroundColor White
                }
                else {
                    Write-Host "[WARNING] This node ($nodeName) is not yet visible in the cluster" -ForegroundColor Yellow
                    Write-Host "It may take a few minutes for the node to register" -ForegroundColor Gray
                }
            }
            else {
                Write-Host "[ERROR] Failed to query cluster" -ForegroundColor Red
            }
        }
        catch {
            Write-Host "[ERROR] Error querying cluster: $_" -ForegroundColor Red
        }
    }
    else {
        Write-Host "[WARNING] kubeconfig file not found: $kubeConfigPath" -ForegroundColor Yellow
    }
}
else {
    Write-Host "[ERROR] kubectl not found at: $kubectlPath" -ForegroundColor Red
}

# 5. Check pods (if node is joined)
Write-Host "`n5. Checking pods on this node..." -ForegroundColor Yellow
if (Test-Path $kubectlPath -and (Test-Path $kubeConfigPath)) {
    try {
        $nodeName = $env:COMPUTERNAME.ToLower()
        & $kubectlPath --kubeconfig=$kubeConfigPath get pods --all-namespaces --field-selector spec.nodeName=$nodeName
        
        if ($LASTEXITCODE -eq 0) {
            Write-Host "[OK] Pod query successful" -ForegroundColor Green
        }
    }
    catch {
        Write-Host "[WARNING] Could not query pods: $_" -ForegroundColor Yellow
    }
}

# 6. Check Windows features
Write-Host "`n6. Checking Windows features..." -ForegroundColor Yellow
$containers = Get-WindowsOptionalFeature -Online -FeatureName Containers -ErrorAction SilentlyContinue
if ($containers -and $containers.State -eq 'Enabled') {
    Write-Host "[OK] Containers feature is enabled" -ForegroundColor Green
}
else {
    Write-Host "[WARNING] Containers feature is not enabled" -ForegroundColor Yellow
}

# 7. Summary
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Verification Summary" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

Write-Host "`nNext steps:" -ForegroundColor Yellow
Write-Host "- If the node is not visible, wait a few minutes and check again" -ForegroundColor White
Write-Host "- Check kubelet logs for any errors:" -ForegroundColor White
Write-Host "  Get-EventLog -LogName Application -Source kubelet -Newest 50" -ForegroundColor Green
Write-Host "- Or use NSSM to check the service:" -ForegroundColor White
Write-Host "  & 'C:\Program Files\Kubernetes\bin\nssm.exe' status kubelet" -ForegroundColor Green
Write-Host ""

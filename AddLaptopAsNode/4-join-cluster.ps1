# Kubernetes Worker Node - Join Cluster
# Run this script as Administrator

Write-Host "=== Joining Kubernetes Cluster ===" -ForegroundColor Cyan
Write-Host ""

# Check if running as Administrator
$currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
$isAdmin = $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Host "[ERROR] This script must be run as Administrator!" -ForegroundColor Red
    exit 1
}

# Cluster information from kubeconfig
$apiServer = "https://e6cb868d-ac12-47af-a171-67420418f77f-ap-south-noi-1.kaas.theacecloud.com:6443"
$kubeConfigPath = "c:\DATA\Work\KubeNet\c-m-l9bg25vk.yaml"

Write-Host "Cluster API Server: $apiServer" -ForegroundColor Cyan
Write-Host ""

# Important: Get join token from control plane
Write-Host "========================================" -ForegroundColor Yellow
Write-Host "IMPORTANT: JOIN TOKEN REQUIRED" -ForegroundColor Yellow
Write-Host "========================================" -ForegroundColor Yellow
Write-Host ""
Write-Host "To join this node to the cluster, you need a join token from the control plane." -ForegroundColor White
Write-Host ""
Write-Host "OPTIONS TO GET THE JOIN TOKEN:" -ForegroundColor Cyan
Write-Host ""
Write-Host "Option 1: Using kubectl (if you have access to a control plane node)" -ForegroundColor White
Write-Host "  Run this command on a control plane node:" -ForegroundColor Gray
Write-Host "  kubeadm token create --print-join-command" -ForegroundColor Green
Write-Host ""
Write-Host "Option 2: Using The Ace Cloud Dashboard (for managed Kubernetes)" -ForegroundColor White
Write-Host "  1. Log into The Ace Cloud dashboard" -ForegroundColor Gray
Write-Host "  2. Navigate to your cluster 'prasuti-fqdn'" -ForegroundColor Gray
Write-Host "  3. Look for 'Add Node' or 'Get Join Command' option" -ForegroundColor Gray
Write-Host ""
Write-Host "Option 3: Using kubectl with your kubeconfig" -ForegroundColor White
Write-Host "  If you have cluster-admin access via the kubeconfig:" -ForegroundColor Gray
Write-Host "  kubectl --kubeconfig $kubeConfigPath -n kube-system get secret" -ForegroundColor Green
Write-Host "  Then manually construct the join command" -ForegroundColor Gray
Write-Host ""
Write-Host "========================================" -ForegroundColor Yellow

# Try to get token using kubectl with existing kubeconfig
Write-Host "`nAttempting to retrieve join token using kubectl..." -ForegroundColor Yellow

$kubectlPath = "C:\Program Files\Kubernetes\bin\kubectl.exe"
if (Test-Path $kubectlPath) {
    try {
        # Check if we can access the cluster
        $nodes = & $kubectlPath --kubeconfig=$kubeConfigPath get nodes 2>&1
        
        if ($LASTEXITCODE -eq 0) {
            Write-Host "[OK] Successfully connected to cluster" -ForegroundColor Green
            Write-Host "`nCurrent nodes in cluster:" -ForegroundColor Cyan
            Write-Host $nodes -ForegroundColor White
            
            Write-Host "`nAttempting to create join token..." -ForegroundColor Yellow
            
            # Try to create token (requires admin privileges)
            $tokenOutput = & $kubectlPath --kubeconfig=$kubeConfigPath -n kube-system create token default-node --duration=24h 2>&1
            
            if ($LASTEXITCODE -eq 0) {
                $token = $tokenOutput
                Write-Host "[OK] Generated token" -ForegroundColor Green
                
                # Get CA certificate hash
                Write-Host "`nGetting CA certificate hash..." -ForegroundColor Yellow
                
                # Read kubeconfig to get CA cert using regex (PowerShell doesn't have ConvertFrom-Yaml by default)
                $kubeconfigContent = Get-Content $kubeConfigPath -Raw
                
                # Extract certificate-authority-data using regex
                if ($kubeconfigContent -match 'certificate-authority-data:\s*>?-?\s*\n?\s*([A-Za-z0-9+/=\n\s]+)') {
                    $caCertBase64 = $matches[1] -replace '\s', ''  # Remove whitespace and newlines
                    
                    # Decode and hash
                    $caCertBytes = [System.Convert]::FromBase64String($caCertBase64)
                    $sha256 = [System.Security.Cryptography.SHA256]::Create()
                    $hashBytes = $sha256.ComputeHash($caCertBytes)
                    $hashHex = [System.BitConverter]::ToString($hashBytes).Replace('-', '').ToLower()
                    $discoveryTokenHash = "sha256:$hashHex"
                }
                else {
                    Write-Host "[ERROR] Could not extract CA certificate from kubeconfig" -ForegroundColor Red
                    $discoveryTokenHash = $null
                }
                
                if ($discoveryTokenHash) {
                    Write-Host "[OK] CA cert hash: $discoveryTokenHash" -ForegroundColor Green
                    
                    # Construct join command
                    $joinCommand = @"
kubeadm join $($apiServer.Replace('https://', '')) `
  --token $token `
  --discovery-token-ca-cert-hash $discoveryTokenHash `
  --cri-socket "npipe:////./pipe/containerd-containerd"
"@
                    
                    Write-Host "`n========================================" -ForegroundColor Cyan
                    Write-Host "GENERATED JOIN COMMAND:" -ForegroundColor Cyan
                    Write-Host "========================================" -ForegroundColor Cyan
                    Write-Host $joinCommand -ForegroundColor Green
                    Write-Host ""
                }
                else {
                    Write-Host "[ERROR] Cannot construct join command without CA cert hash" -ForegroundColor Red
                }
                
            }
            else {
                Write-Host "[WARNING] Could not create token automatically" -ForegroundColor Yellow
                Write-Host "Error: $tokenOutput" -ForegroundColor Red
            }
            
        }
        else {
            Write-Host "[WARNING] Could not connect to cluster with kubeconfig" -ForegroundColor Yellow
            Write-Host "Error: $nodes" -ForegroundColor Red
        }
    }
    catch {
        Write-Host "[WARNING] Error accessing cluster: $_" -ForegroundColor Yellow
    }
}
else {
    Write-Host "[WARNING] kubectl not found at expected location" -ForegroundColor Yellow
}

# Manual join section
Write-Host "`n========================================" -ForegroundColor Yellow
Write-Host "MANUAL JOIN PROCESS" -ForegroundColor Yellow
Write-Host "========================================" -ForegroundColor Yellow
Write-Host ""
Write-Host "If you have the join command, enter it below:" -ForegroundColor White
Write-Host "Format: kubeadm join <server> --token <token> --discovery-token-ca-cert-hash sha256:<hash>" -ForegroundColor Gray
Write-Host ""
Write-Host "Enter the full join command (or press Enter to skip):" -ForegroundColor Cyan
$userJoinCommand = Read-Host

if ($userJoinCommand -and $userJoinCommand.Trim().Length -gt 0) {
    Write-Host "`nExecuting join command..." -ForegroundColor Yellow
    
    # Add Windows-specific flags if not already present
    if ($userJoinCommand -notlike "*--cri-socket*") {
        $userJoinCommand += ' --cri-socket "npipe:////./pipe/containerd-containerd"'
    }
    
    # Execute join command
    try {
        Invoke-Expression $userJoinCommand
        
        if ($LASTEXITCODE -eq 0) {
            Write-Host "`n[OK] Successfully joined the cluster!" -ForegroundColor Green
            
            # Start kubelet service
            Write-Host "`nStarting kubelet service..." -ForegroundColor Yellow
            
            # Create kubelet service using NSSM
            $nssmPath = "C:\Program Files\Kubernetes\bin\nssm.exe"
            if (Test-Path $nssmPath) {
                # Remove existing service if it exists
                & $nssmPath stop kubelet 2>$null
                & $nssmPath remove kubelet confirm 2>$null
                
                # Install service
                & $nssmPath install kubelet "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe" "-ExecutionPolicy Bypass -File `"C:\Program Files\Kubernetes\bin\start-kubelet.ps1`""
                & $nssmPath set kubelet AppDirectory "C:\Program Files\Kubernetes\bin"
                & $nssmPath set kubelet DisplayName "Kubelet"
                & $nssmPath set kubelet Description "Kubernetes Node Agent"
                & $nssmPath set kubelet Start SERVICE_AUTO_START
                & $nssmPath start kubelet
                
                Write-Host "[OK] Kubelet service started" -ForegroundColor Green
            }
            
        }
        else {
            Write-Host "`n[ERROR] Failed to join cluster" -ForegroundColor Red
            Write-Host "Check the error messages above" -ForegroundColor Yellow
        }
        
    }
    catch {
        Write-Host "`n[ERROR] Failed to execute join command: $_" -ForegroundColor Red
    }
    
}
else {
    Write-Host "`n[INFO] Skipped manual join" -ForegroundColor Cyan
}

# Additional guidance section
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Post-Join Instructions" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

Write-Host "If you successfully joined the cluster:" -ForegroundColor Green
Write-Host "  1. Run 5-verify-node.ps1 to verify the node status" -ForegroundColor White
Write-Host "  2. Check that kubelet service is running" -ForegroundColor White
Write-Host "  3. Wait a few minutes for the node to appear in cluster" -ForegroundColor White
Write-Host ""

Write-Host "If the automatic join failed:" -ForegroundColor Yellow
Write-Host "  1. Get the join token from The Ace Cloud dashboard or control plane" -ForegroundColor White
Write-Host "  2. Run this script again and paste the join command when prompted" -ForegroundColor White
Write-Host "  3. OR manually run: kubeadm join <server> --token <token> --discovery-token-ca-cert-hash <hash> --cri-socket `"npipe:////./pipe/containerd-containerd`"" -ForegroundColor White
Write-Host ""

Write-Host "Troubleshooting:" -ForegroundColor Yellow
Write-Host "  - Ensure containerd is running: Get-Service containerd" -ForegroundColor White
Write-Host "  - Check firewall allows connections to $apiServer" -ForegroundColor White
Write-Host "  - View kubelet logs: Get-EventLog -LogName Application -Source kubelet -Newest 50" -ForegroundColor White
Write-Host "  - Check NSSM service status: & 'C:\Program Files\Kubernetes\bin\nssm.exe' status kubelet" -ForegroundColor White
Write-Host ""

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Script Complete!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan


# Execute Kubernetes Join - Simplified
# Run as Administrator

$ErrorActionPreference = "Continue"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Kubernetes Worker Node - Join Cluster" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Check Admin
$currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "[ERROR] Must run as Administrator!" -ForegroundColor Red
    exit 1
}

$kubectlPath = "C:\Program Files\Kubernetes\bin\kubectl.exe"
$kubeadmPath = "C:\Program Files\Kubernetes\bin\kubeadm.exe"
$kubeConfigPath = "c:\DATA\Work\KubeNet\c-m-l9bg25vk.yaml"
$apiServer = "e6cb868d-ac12-47af-a171-67420418f77f-ap-south-noi-1.kaas.theacecloud.com:6443"

Write-Host "Step 1: Extracting CA Certificate Hash..." -ForegroundColor Yellow
$kubeconfigContent = Get-Content $kubeConfigPath -Raw

# Extract certificate-authority-data using regex
if ($kubeconfigContent -match 'certificate-authority-data:\s*>?-?\s*\n?\s*([A-Za-z0-9+/=\n\s]+)') {
    $caCertBase64 = $matches[1] -replace '\s', ''
    
    # Decode and hash
    $caCertBytes = [System.Convert]::FromBase64String($caCertBase64)
    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    $hashBytes = $sha256.ComputeHash($caCertBytes)
    $hashHex = [System.BitConverter]::ToString($hashBytes).Replace('-', '').ToLower()
    $discoveryTokenHash = "sha256:$hashHex"
    
    Write-Host "[OK] CA Hash: $discoveryTokenHash" -ForegroundColor Green
}
else {
    Write-Host "[ERROR] Could not extract CA certificate" -ForegroundColor Red
    exit 1
}

Write-Host "`nStep 2: Attempting to create join token..." -ForegroundColor Yellow

# Try different token creation methods
$token = $null

# Method 1: Try to create a bootstrap token
try {
    $tokenOutput = & $kubectlPath --kubeconfig=$kubeConfigPath create token default --namespace kube-system --duration=24h 2>&1
    if ($LASTEXITCODE -eq 0 -and $tokenOutput -match '^[a-z0-9\.\-]+$') {
        $token = $tokenOutput.Trim()
        Write-Host "[OK] Generated token using kubectl create token" -ForegroundColor Green
    }
}
catch {
    Write-Host "[INFO] Method 1 failed" -ForegroundColor Gray
}

# Method 2: Try kubeadm token creation via kubectl exec (if we had pod access)
if (-not $token) {
    Write-Host "[INFO] Automatic token generation not available" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Yellow
    Write-Host "MANUAL TOKEN REQUIRED" -ForegroundColor Yellow
    Write-Host "========================================" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Please get the join token from The Ace Cloud dashboard:" -ForegroundColor White
    Write-Host "1. Go to https://dashboard.theacecloud.com" -ForegroundColor Gray
    Write-Host "2. Navigate to cluster 'prasuti-fqdn'" -ForegroundColor Gray
    Write-Host "3. Look for 'Add Worker Node' or 'Get Join Token'" -ForegroundColor Gray
    Write-Host "4. Copy ONLY the token (format: xxxxxx.xxxxxxxxxxxxxxxx)" -ForegroundColor Gray
    Write-Host ""
    Write-Host "Enter the join token (or press Ctrl+C to cancel):" -ForegroundColor Cyan
    $token = Read-Host
    
    if (-not $token -or $token.Trim().Length -eq 0) {
        Write-Host "[ERROR] No token provided" -ForegroundColor Red
        exit 1
    }
    $token = $token.Trim()
}

Write-Host "`nStep 3: Executing join command..." -ForegroundColor Yellow
Write-Host ""

# Construct and execute join command
$joinArgs = @(
    "join",
    $apiServer,
    "--token", $token,
    "--discovery-token-ca-cert-hash", $discoveryTokenHash,
    "--cri-socket", "npipe:////./pipe/containerd-containerd",
    "--v=5"
)

Write-Host "Join command:" -ForegroundColor Cyan
Write-Host "kubeadm $($joinArgs -join ' ')" -ForegroundColor Green
Write-Host ""

try {
    & $kubeadmPath $joinArgs
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "`n========================================" -ForegroundColor Green
        Write-Host "Successfully Joined Cluster!" -ForegroundColor Green
        Write-Host "========================================" -ForegroundColor Green
        
        # Start kubelet service
        Write-Host "`nStep 4: Setting up kubelet service..." -ForegroundColor Yellow
        
        $nssmPath = "C:\Program Files\Kubernetes\bin\nssm.exe"
        if (Test-Path $nssmPath) {
            # Stop and remove if exists
            & $nssmPath stop kubelet 2>$null
            & $nssmPath remove kubelet confirm 2>$null
            
            # Install kubelet service
            & $nssmPath install kubelet "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe" "-ExecutionPolicy Bypass -File `"C:\Program Files\Kubernetes\bin\start-kubelet.ps1`""
            & $nssmPath set kubelet AppDirectory "C:\Program Files\Kubernetes\bin"
            & $nssmPath set kubelet DisplayName "Kubelet"
            & $nssmPath set kubelet Description "Kubernetes Node Agent"
            & $nssmPath set kubelet Start SERVICE_AUTO_START
            & $nssmPath start kubelet
            
            Write-Host "[OK] Kubelet service created and started" -ForegroundColor Green
        }
        else {
            Write-Host "[WARNING] NSSM not found - kubelet service not created" -ForegroundColor Yellow
            Write-Host "You may need to start kubelet manually" -ForegroundColor Yellow
        }
        
        Write-Host "`n========================================" -ForegroundColor Cyan
        Write-Host "Next Steps:" -ForegroundColor Cyan
        Write-Host "1. Run .\5-verify-node.ps1 to check node status" -ForegroundColor White
        Write-Host "2. Wait a few minutes for node to be Ready" -ForegroundColor White
        Write-Host "========================================" -ForegroundColor Cyan
    }
    else {
        Write-Host "`n[ERROR] Join command failed with exit code: $LASTEXITCODE" -ForegroundColor Red
        Write-Host "Check the error messages above" -ForegroundColor Yellow
    }
}
catch {
    Write-Host "`n[ERROR] Failed to execute join: $_" -ForegroundColor Red
}

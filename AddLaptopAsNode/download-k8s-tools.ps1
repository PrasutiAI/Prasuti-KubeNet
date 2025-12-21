# Download missing Kubernetes components
# Run as Administrator

$ErrorActionPreference = "Stop"

Write-Host "Downloading missing Kubernetes components..." -ForegroundColor Cyan

$baseUrl = "https://dl.k8s.io/v1.29.0/bin/windows/amd64"
$binPath = "C:\Program Files\Kubernetes\bin"

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

foreach ($tool in @('kubectl.exe', 'kubeadm.exe')) {
    $url = "$baseUrl/$tool"
    $outFile = "$binPath\$tool"
    
    if (-not (Test-Path $outFile)) {
        Write-Host "Downloading $tool..." -ForegroundColor Yellow
        try {
            Invoke-WebRequest -Uri $url -OutFile $outFile -UseBasicParsing
            Write-Host "[OK] Downloaded $tool" -ForegroundColor Green
        }
        catch {
            Write-Host "[ERROR] Failed to download $tool : $_" -ForegroundColor Red
        }
    }
    else {
        Write-Host "[INFO] $tool already exists" -ForegroundColor Cyan
    }
}

Write-Host "`n[OK] Download complete!" -ForegroundColor Green
Write-Host "`nInstalled binaries:" -ForegroundColor Cyan
Get-ChildItem "$binPath\*.exe" | Select-Object Name, @{Name = 'SizeMB'; Expression = { [math]::Round($_.Length / 1MB, 2) } }

$ErrorActionPreference = "Stop"
$logFile = "$PSScriptRoot\setup_log.txt"
"Starting Setup..." | Out-File $logFile
Start-Transcript -Path $logFile -Append

try {
    Write-Host "Running 1-check-prerequisites.ps1"
    & "$PSScriptRoot\1-check-prerequisites.ps1"
    if ($LASTEXITCODE -ne 0) { throw "Prerequisites check failed with code $LASTEXITCODE" }

    Write-Host "Running 2-install-containerd.ps1"
    & "$PSScriptRoot\2-install-containerd.ps1"
    if ($LASTEXITCODE -ne 0) { throw "Containerd installation failed with code $LASTEXITCODE" }

    Write-Host "Running 3-install-kubernetes.ps1"
    & "$PSScriptRoot\3-install-kubernetes.ps1"
    if ($LASTEXITCODE -ne 0) { throw "Kubernetes installation failed with code $LASTEXITCODE" }

    Write-Host "Running auto-join.ps1"
    & "$PSScriptRoot\auto-join.ps1"
    if ($LASTEXITCODE -ne 0) { throw "Auto-join failed with code $LASTEXITCODE" }

    Write-Host "Running 5-verify-node.ps1"
    & "$PSScriptRoot\5-verify-node.ps1"
    
    Write-Host "Setup Completed Successfully"
}
catch {
    Write-Error "Setup Failed: $_"
    Write-Host "Check $logFile for details."
}
finally {
    Stop-Transcript
}

Write-Host "Press Enter to exit..."
Read-Host

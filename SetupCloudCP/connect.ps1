param (
    [string]$Environment = "dev"
)
# PowerShell Script to Connect to Server
# Usage: .\connect.ps1

# Load configuration from environment-specific file
$envFile = Join-Path $PSScriptRoot "..\application_secrets.$Environment.env"
if (-not (Test-Path $envFile)) {
    Write-Host "Error: Configuration file $envFile not found!" -ForegroundColor Red
    exit 1
}

Write-Host "--- Loading Configuration for Environment: $Environment ---" -ForegroundColor Cyan
$config = @{}
Get-Content $envFile | ForEach-Object {
    if ($_ -match '^\s*([^#][^=]+)="?([^"]*)"?\s*$') {
        $key = $matches[1].Trim()
        $value = $matches[2].Trim()
        $config[$key] = $value
    }
    elseif ($_ -match '^\s*([^#][^=]+)=(.+)$') {
        $key = $matches[1].Trim()
        $value = $matches[2].Trim()
        $config[$key] = $value
    }
}

# Validate required variables
$required = @('SERVER_HOST', 'SERVER_USER', 'SERVER_PORT', 'SSH_KEY_PATH')
foreach ($var in $required) {
    if (-not $config.ContainsKey($var) -or $config[$var] -match 'your-server') {
        Write-Host "Error: $var is not set in $envFile" -ForegroundColor Red
        Write-Host "Please edit $envFile with your actual server details" -ForegroundColor Yellow
        exit 1
    }
}

# Build the SSH key path
$sshKeyPath = Join-Path $PSScriptRoot $config['SSH_KEY_PATH']

if (-not (Test-Path $sshKeyPath)) {
    Write-Host "Error: SSH key not found at $sshKeyPath" -ForegroundColor Red
    exit 1
}

# Display connection info
Write-Host "Connecting to server..." -ForegroundColor Green
Write-Host "  Host: $($config['SERVER_HOST'])" -ForegroundColor Cyan
Write-Host "  User: $($config['SERVER_USER'])" -ForegroundColor Cyan
Write-Host "  Port: $($config['SERVER_PORT'])" -ForegroundColor Cyan
Write-Host "  Key:  $sshKeyPath" -ForegroundColor Cyan
Write-Host ""

# Connect using SSH
ssh -i "$sshKeyPath" -p $config['SERVER_PORT'] "$($config['SERVER_USER'])@$($config['SERVER_HOST'])"

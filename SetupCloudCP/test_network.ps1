# PowerShell Network Testing Script
# Usage: .\test_network.ps1

# Load configuration from server_config.env
$configFile = Join-Path $PSScriptRoot "server_config.env"

if (-not (Test-Path $configFile)) {
    Write-Host "Error: server_config.env not found!" -ForegroundColor Red
    exit 1
}

# Parse the .env file
$config = @{}
Get-Content $configFile | ForEach-Object {
    if ($_ -match '^\s*([^#][^=]+)=(.+)$') {
        $key = $matches[1].Trim()
        $value = $matches[2].Trim()
        $config[$key] = $value
    }
}

# Validate required variables
if (-not $config.ContainsKey('SERVER_HOST') -or $config['SERVER_HOST'] -match 'your-server') {
    Write-Host "Error: SERVER_HOST is not set in server_config.env" -ForegroundColor Red
    exit 1
}

if (-not $config.ContainsKey('SERVER_USER')) {
    $config['SERVER_USER'] = 'ubuntu'
}

if (-not $config.ContainsKey('SERVER_PORT')) {
    $config['SERVER_PORT'] = '22'
}

# Build SSH key path
$sshKeyPath = Join-Path $PSScriptRoot $config['SSH_KEY_PATH']

if (-not (Test-Path $sshKeyPath)) {
    Write-Host "Error: SSH key not found at $sshKeyPath" -ForegroundColor Red
    exit 1
}

Write-Host "==========================================" -ForegroundColor White
Write-Host "    Network Connectivity Tests" -ForegroundColor White
Write-Host "==========================================" -ForegroundColor White
Write-Host ""

# Test 1: Ping test
Write-Host "[Test 1]" -ForegroundColor Blue -NoNewline
Write-Host " Ping test to $($config['SERVER_HOST'])"
try {
    $ping = Test-Connection -ComputerName $config['SERVER_HOST'] -Count 4 -Quiet
    if ($ping) {
        Write-Host "  ✓ Ping successful" -ForegroundColor Green
    }
    else {
        Write-Host "  ✗ Ping failed (may be blocked by firewall)" -ForegroundColor Yellow
    }
}
catch {
    Write-Host "  ✗ Ping failed (may be blocked by firewall)" -ForegroundColor Yellow
}
Write-Host ""

# Test 2: Port connectivity
Write-Host "[Test 2]" -ForegroundColor Blue -NoNewline
Write-Host " Testing SSH port $($config['SERVER_PORT']) connectivity"
try {
    $tcpClient = New-Object System.Net.Sockets.TcpClient
    $connect = $tcpClient.BeginConnect($config['SERVER_HOST'], [int]$config['SERVER_PORT'], $null, $null)
    $wait = $connect.AsyncWaitHandle.WaitOne(5000, $false)
    if ($wait) {
        $tcpClient.EndConnect($connect)
        $tcpClient.Close()
        Write-Host "  ✓ Port $($config['SERVER_PORT']) is open" -ForegroundColor Green
    }
    else {
        Write-Host "  ✗ Port $($config['SERVER_PORT']) is closed or filtered" -ForegroundColor Red
    }
}
catch {
    Write-Host "  ✗ Port $($config['SERVER_PORT']) is closed or filtered" -ForegroundColor Red
}
Write-Host ""

# Test 3: SSH connection test
Write-Host "[Test 3]" -ForegroundColor Blue -NoNewline
Write-Host " Testing SSH authentication"
$sshCmd = "ssh -i `"$sshKeyPath`" -p $($config['SERVER_PORT']) -o BatchMode=yes -o ConnectTimeout=10 `"$($config['SERVER_USER'])@$($config['SERVER_HOST'])`" `"echo 'SSH connection successful'`""
try {
    $result = Invoke-Expression $sshCmd 2>$null
    if ($LASTEXITCODE -eq 0) {
        Write-Host "  ✓ SSH authentication successful" -ForegroundColor Green
    }
    else {
        Write-Host "  ✗ SSH authentication failed" -ForegroundColor Red
        Write-Host "    Check your SSH key and user credentials" -ForegroundColor Yellow
    }
}
catch {
    Write-Host "  ✗ SSH authentication failed" -ForegroundColor Red
    Write-Host "    Check your SSH key and user credentials" -ForegroundColor Yellow
}
Write-Host ""

# Test 4: Remote system information
Write-Host "[Test 4]" -ForegroundColor Blue -NoNewline
Write-Host " Gathering remote system information"
$remoteCmd = "cat /etc/os-release | grep PRETTY_NAME | cut -d'\\`"' -f2; hostname; uptime"
$sshCmd = "ssh -i `"$sshKeyPath`" -p $($config['SERVER_PORT']) -o BatchMode=yes -o ConnectTimeout=10 `"$($config['SERVER_USER'])@$($config['SERVER_HOST'])`" `"$remoteCmd`""
try {
    $result = Invoke-Expression $sshCmd 2>$null
    if ($LASTEXITCODE -eq 0) {
        $lines = $result -split "`n"
        Write-Host "  OS: $($lines[0])" -ForegroundColor Cyan
        Write-Host "  Hostname: $($lines[1])" -ForegroundColor Cyan
        Write-Host "  Uptime: $($lines[2])" -ForegroundColor Cyan
    }
    else {
        Write-Host "  ✗ Failed to retrieve system information" -ForegroundColor Red
    }
}
catch {
    Write-Host "  ✗ Failed to retrieve system information" -ForegroundColor Red
}
Write-Host ""

# Test 5: Network interfaces
Write-Host "[Test 5]" -ForegroundColor Blue -NoNewline
Write-Host " Checking remote network interfaces"
$remoteCmd = "ip -4 addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}'"
$sshCmd = "ssh -i `"$sshKeyPath`" -p $($config['SERVER_PORT']) -o BatchMode=yes -o ConnectTimeout=10 `"$($config['SERVER_USER'])@$($config['SERVER_HOST'])`" `"$remoteCmd`""
try {
    $ips = Invoke-Expression $sshCmd 2>$null
    if ($LASTEXITCODE -eq 0) {
        foreach ($ip in $ips -split "`n") {
            if ($ip.Trim()) {
                Write-Host "  IP Address: $($ip.Trim())" -ForegroundColor Cyan
            }
        }
    }
}
catch {
    Write-Host "  ✗ Failed to retrieve network information" -ForegroundColor Red
}
Write-Host ""

# Test 6: Internet connectivity
Write-Host "[Test 6]" -ForegroundColor Blue -NoNewline
Write-Host " Testing internet connectivity from remote server"
$remoteCmd = "ping -c 2 8.8.8.8 > /dev/null 2>&1"
$sshCmd = "ssh -i `"$sshKeyPath`" -p $($config['SERVER_PORT']) -o BatchMode=yes -o ConnectTimeout=10 `"$($config['SERVER_USER'])@$($config['SERVER_HOST'])`" `"$remoteCmd`""
try {
    Invoke-Expression $sshCmd 2>$null | Out-Null
    if ($LASTEXITCODE -eq 0) {
        Write-Host "  ✓ Remote server has internet connectivity" -ForegroundColor Green
    }
    else {
        Write-Host "  ✗ Remote server has no internet connectivity" -ForegroundColor Red
    }
}
catch {
    Write-Host "  ✗ Remote server has no internet connectivity" -ForegroundColor Red
}
Write-Host ""

Write-Host "==========================================" -ForegroundColor White
Write-Host "    Test Summary Complete" -ForegroundColor White
Write-Host "==========================================" -ForegroundColor White

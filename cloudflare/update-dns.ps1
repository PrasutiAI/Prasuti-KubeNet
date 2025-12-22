param (
    [string]$Environment = "dev",
    [string]$ServiceName = ""
)
# Cloudflare DNS Management Script
$ErrorActionPreference = "Stop"

# Load configuration from environment-specific file
$envFile = Join-Path $PSScriptRoot "..\application_secrets.$Environment.env"
if (-not (Test-Path $envFile)) {
    Write-Host "Error: Configuration file $envFile not found!" -ForegroundColor Red
    exit 1
}

$config = @{}
Get-Content $envFile | ForEach-Object {
    if ($_ -match '^\s*([^#][^=]+)="?([^"]*)"?\s*$') {
        $config[$matches[1].Trim()] = $matches[2].Trim()
    }
}

$ApiKey = $config['CLOUDFLARE_API_KEY']
$ZoneName = $config['CLOUDFLARE_ZONE_NAME']
$ServerIp = $config['K8S_CONTROL_PLANE']
if (-not $ServerIp) { $ServerIp = $config['SERVER_HOST'] }

# Determine services to update
if ($ServiceName) {
    $Services = $ServiceName
    Write-Host "Targeting single service: $ServiceName" -ForegroundColor Cyan
}
else {
    $Services = $config['SERVICES']
}

if (-not $ApiKey -or -not $ZoneName -or -not $ServerIp -or -not $Services) {
    Write-Host "Error: Missing required configuration in application_secrets.$Environment.env" -ForegroundColor Red
    exit 1
}

function Get-CloudflareZoneId {
    param($Name)
    $url = "https://api.cloudflare.com/client/v4/zones?name=$Name"
    $headers = @{"Content-Type" = "application/json" }
    
    if ($config['CLOUDFLARE_EMAIL']) {
        $headers["X-Auth-Email"] = $config['CLOUDFLARE_EMAIL']
        $headers["X-Auth-Key"] = $ApiKey
    }
    else {
        $headers["Authorization"] = "Bearer $ApiKey"
    }

    try {
        $response = Invoke-RestMethod -Uri $url -Method Get -Headers $headers
        if ($response.success -and $response.result.Count -gt 0) {
            return $response.result[0].id
        }
        else {
            Write-Host "No zone found for $Name" -ForegroundColor Red
            return $null
        }
    }
    catch {
        $errorResponse = $_.Exception.Response
        if ($errorResponse) {
            $reader = New-Object System.IO.StreamReader($errorResponse.GetResponseStream())
            $body = $reader.ReadToEnd()
            Write-Host "API Error: $body" -ForegroundColor Red
        }
        else {
            Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
        }
        return $null
    }
}

function Set-DnsRecord {
    param($ZoneId, $Name, $Type, $Content, $Proxied = $true)
    
    # Check if record exists
    $url = "https://api.cloudflare.com/client/v4/zones/$ZoneId/dns_records?name=$Name"
    $headers = @{"Content-Type" = "application/json" }
    
    if ($config['CLOUDFLARE_EMAIL']) {
        $headers["X-Auth-Email"] = $config['CLOUDFLARE_EMAIL']
        $headers["X-Auth-Key"] = $ApiKey
    }
    else {
        $headers["Authorization"] = "Bearer $ApiKey"
    }

    try {
        $response = Invoke-RestMethod -Uri $url -Method Get -Headers $headers
    }
    catch {
        Write-Host "Error checking record $($Name): $($_.Exception.Message)" -ForegroundColor Red
        return
    }
    
    $body = @{
        type    = $Type
        name    = $Name
        content = $Content
        ttl     = 1 # Auto
        proxied = $Proxied
    } | ConvertTo-Json
    
    $existingRecord = $response.result | Where-Object { $_.name -eq $Name -and $_.type -eq $Type }

    if ($existingRecord) {
        $recordId = $existingRecord.id
        if ($existingRecord.content -eq $Content) {
            Write-Host "Record already points to $($Content): $($Name) ($($Type))" -ForegroundColor Green
            return
        }
        Write-Host "Updating existing record: $($Name) ($($Type)) -> $($Content)" -ForegroundColor Yellow
        $url = "https://api.cloudflare.com/client/v4/zones/$ZoneId/dns_records/$recordId"
        Invoke-RestMethod -Uri $url -Method Put -Headers $headers -Body $body
    }
    else {
        Write-Host "Creating new record: $($Name) ($($Type)) -> $($Content)" -ForegroundColor Cyan
        $url = "https://api.cloudflare.com/client/v4/zones/$ZoneId/dns_records"
        Invoke-RestMethod -Uri $url -Method Post -Headers $headers -Body $body
    }
}

# Execute Updates
Write-Host "Starting DNS updates for zone: $ZoneName (Environment: $Environment)..." -ForegroundColor Green
$zoneId = Get-CloudflareZoneId -Name $ZoneName

if ($zoneId) {
    if ($Services) {
        $serviceList = $Services.Split(',').Trim()
        foreach ($service in $serviceList) {
            if ($service) {
                # Derive domain: service-env.zone.com or service.zone.com if production
                if ($Environment -eq "prod") {
                    $domain = "$service.$ZoneName"
                }
                else {
                    $domain = "$service-$Environment.$ZoneName"
                }

                # Proxy enabled for all domains as requested
                Set-DnsRecord -ZoneId $zoneId -Name $domain -Type "A" -Content $ServerIp -Proxied $true

                # If domain is www.zone.com (production), also update zone.com (root domain)
                if ($Environment -eq "prod" -and $domain -eq "www.$ZoneName") {
                    Write-Host "Detected www domain in production, also updating root domain: $ZoneName" -ForegroundColor Gray
                    Set-DnsRecord -ZoneId $zoneId -Name $ZoneName -Type "A" -Content $ServerIp -Proxied $true
                }
            }
        }
    }
    else {
        Write-Host "No services found to update." -ForegroundColor Yellow
    }
}

Write-Host "`nDNS updates completed successfully (with warnings if any)." -ForegroundColor Green

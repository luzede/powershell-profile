# ======================================================================
# Module 00: Core Helpers & Primitives
# ======================================================================

function Enable-Tls12 {
    try {
        $protocol = [Net.ServicePointManager]::SecurityProtocol
        if ($protocol -ne [Net.SecurityProtocolType]::SystemDefault -and -not ($protocol -band [Net.SecurityProtocolType]::Tls12)) {
            [Net.ServicePointManager]::SecurityProtocol = $protocol -bor [Net.SecurityProtocolType]::Tls12
        }
    }
    catch {
        Write-Verbose "Unable to enable TLS 1.2 explicitly: $_"
    }
}

function IsInteractiveShell {
    try {
        return $Host.Name -eq 'ConsoleHost' -and
        -not [Console]::IsInputRedirected -and
        -not [Console]::IsOutputRedirected
    }
    catch {
        return $false
    }
}

function Get-ProfileDir {
    if ($PROFILE.CurrentUserCurrentHost) {
        return Split-Path -Path $PROFILE.CurrentUserCurrentHost -Parent
    }
    switch ($PSVersionTable.PSEdition) {
        'Core' { Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'PowerShell'; break }
        'Desktop' { Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'WindowsPowerShell'; break }
        default {
            throw "Unsupported PowerShell edition: $($PSVersionTable.PSEdition)"
        }
    }
}

function Test-Command {
    param([Parameter(Mandatory)][string]$Name)
    $null -ne (Get-Command -Name ([System.Management.Automation.WildcardPattern]::Escape($Name)) -ErrorAction SilentlyContinue)
}

function Save-UriToFile {
    param(
        [Parameter(Mandatory)][string]$Uri,
        [Parameter(Mandatory)][string]$OutFile
    )

    $parsedUri = [System.Uri]$Uri
    if ($parsedUri.Scheme -ne [System.Uri]::UriSchemeHttps) {
        throw "Only HTTPS URIs are allowed: '$Uri'"
    }

    $resolvedOutFile = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutFile)
    $outDir = Split-Path -Path $resolvedOutFile -Parent
    if ($outDir -and -not (Test-Path -LiteralPath $outDir -PathType Container)) {
        New-Item -ItemType Directory -Path $outDir -Force -ErrorAction Stop | Out-Null
    }

    Enable-Tls12
    $tempFile = Join-Path $env:TEMP ("download-$PID-$([guid]::NewGuid().ToString('N')).tmp")
    $client = New-Object System.Net.WebClient
    try {
        $client.DownloadFile($parsedUri, $tempFile)
        Move-Item -LiteralPath $tempFile -Destination $resolvedOutFile -Force -ErrorAction Stop
    }
    finally {
        $client.Dispose()
        Remove-Item -LiteralPath $tempFile -Force -ErrorAction SilentlyContinue
    }
}

function Get-UriContent {
    param([Parameter(Mandatory)][string]$Uri)

    $parsedUri = [System.Uri]$Uri
    if ($parsedUri.Scheme -ne [System.Uri]::UriSchemeHttps) {
        throw "Only HTTPS URIs are allowed: '$Uri'"
    }

    Enable-Tls12
    $client = New-Object System.Net.WebClient
    $client.Encoding = [System.Text.Encoding]::UTF8
    try {
        $client.DownloadString($parsedUri)
    }
    finally {
        $client.Dispose()
    }
}

function Set-PersistentEnv {
    param(
        [Parameter(Mandatory)][string]$Name,
        [AllowEmptyString()][string]$Value
    )
    if ($Name -notmatch '^[A-Za-z_][A-Za-z0-9_]*$') {
        throw "Invalid environment variable name: '$Name'"
    }

    if ([string]::IsNullOrEmpty($Value)) {
        [Environment]::SetEnvironmentVariable($Name, $null, 'User')
        [Environment]::SetEnvironmentVariable($Name, $null, 'Process')
    }
    else {
        [Environment]::SetEnvironmentVariable($Name, $Value, 'User')
        [Environment]::SetEnvironmentVariable($Name, $Value, 'Process')
    }
}

function Get-ProfileCacheDir {
    $cacheHome = if (-not [string]::IsNullOrWhiteSpace($env:XDG_CACHE_HOME)) {
        $env:XDG_CACHE_HOME
    }
    else {
        Join-Path $HOME '.cache'
    }
    Join-Path $cacheHome 'powershell'
}

function Get-ProfileCustomDir {
    Join-Path (Get-ProfileDir) 'Custom'
}


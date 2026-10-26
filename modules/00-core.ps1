# ======================================================================
# Module 00: Core Helpers & Primitives (PowerShell 7+)
# ======================================================================

function Enable-Tls12 {
    <# PowerShell 7 uses OS-negotiated TLS 1.2/1.3 natively in .NET Core #>
}

$script:ProfileDir = if ($PROFILE.CurrentUserCurrentHost) {
    Split-Path -Path $PROFILE.CurrentUserCurrentHost -Parent
} else {
    Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'PowerShell'
}

$script:CacheDir = if (-not [string]::IsNullOrWhiteSpace($env:XDG_CACHE_HOME)) {
    Join-Path $env:XDG_CACHE_HOME 'powershell'
} else {
    Join-Path $HOME '.cache\powershell'
}

$script:CustomDir = Join-Path $script:ProfileDir 'Custom'

function Get-ProfileDir { $script:ProfileDir }
function Get-ProfileCacheDir { $script:CacheDir }
function Get-ProfileCustomDir { $script:CustomDir }

function IsInteractiveShell {
    try {
        return ($Host.Name -in @('ConsoleHost', 'Visual Studio Code Host')) -and
        -not [Console]::IsInputRedirected -and
        -not [Console]::IsOutputRedirected
    }
    catch {
        return $false
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
    if ($outDir -and -not [System.IO.Directory]::Exists($outDir)) {
        [System.IO.Directory]::CreateDirectory($outDir) | Out-Null
    }

    $tempFile = Join-Path $env:TEMP ("download-$PID-$([guid]::NewGuid().ToString('N')).tmp")
    $httpClient = [System.Net.Http.HttpClient]::new()
    try {
        $response = $httpClient.GetAsync($parsedUri).GetAwaiter().GetResult()
        $response.EnsureSuccessStatusCode() | Out-Null
        $fileStream = [System.IO.FileStream]::new($tempFile, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
        try {
            $response.Content.CopyToAsync($fileStream).GetAwaiter().GetResult()
        }
        finally {
            $fileStream.Dispose()
        }
        [System.IO.File]::Move($tempFile, $resolvedOutFile, $true)
    }
    finally {
        $httpClient.Dispose()
        if ([System.IO.File]::Exists($tempFile)) {
            [System.IO.File]::Delete($tempFile)
        }
    }
}

function Get-UriContent {
    param([Parameter(Mandatory)][string]$Uri)

    $parsedUri = [System.Uri]$Uri
    if ($parsedUri.Scheme -ne [System.Uri]::UriSchemeHttps) {
        throw "Only HTTPS URIs are allowed: '$Uri'"
    }

    $httpClient = [System.Net.Http.HttpClient]::new()
    try {
        $httpClient.GetStringAsync($parsedUri).GetAwaiter().GetResult()
    }
    finally {
        $httpClient.Dispose()
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

    if ($null -eq $Value) {
        [Environment]::SetEnvironmentVariable($Name, $null, 'User')
        [Environment]::SetEnvironmentVariable($Name, $null, 'Process')
    }
    else {
        [Environment]::SetEnvironmentVariable($Name, $Value, 'User')
        [Environment]::SetEnvironmentVariable($Name, $Value, 'Process')
    }
}

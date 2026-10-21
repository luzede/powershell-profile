# ======================================================================
# Module 00: Core Helpers & Primitives
# ======================================================================

function Enable-Tls12 {
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    }
    catch {
        Write-Verbose "Unable to enable TLS 1.2 explicitly: $_"
    }
}

function Test-InteractiveShell {
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
    $null -ne (Get-Command -Name $Name -ErrorAction SilentlyContinue)
}

function Save-UriToFile {
    param(
        [Parameter(Mandatory)][string]$Uri,
        [Parameter(Mandatory)][string]$OutFile
    )

    Enable-Tls12
    $client = New-Object System.Net.WebClient
    try {
        $client.DownloadFile($Uri, $OutFile)
    }
    finally {
        $client.Dispose()
    }
}

function Get-UriContent {
    param([Parameter(Mandatory)][string]$Uri)

    Enable-Tls12
    $client = New-Object System.Net.WebClient
    $client.Encoding = [System.Text.Encoding]::UTF8
    try {
        $client.DownloadString($Uri)
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
    Set-Item -Path "env:$Name" -Value $Value -Force -ErrorAction Stop
    if ([Environment]::GetEnvironmentVariable($Name, 'User') -ne $Value) {
        [Environment]::SetEnvironmentVariable($Name, $Value, 'User')
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

$isInteractiveShell = Test-InteractiveShell
$repo_root = 'https://raw.githubusercontent.com/luzede'
$profileDir = Get-ProfileDir
$timeFilePath = Join-Path (Get-ProfileCacheDir) 'LastExecutionTime.txt'
$updateInterval = 7


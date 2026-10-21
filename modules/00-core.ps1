# ======================================================================
# Module 00: Core Helpers, Overrides & Primitives
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

$script:ProfileRoot = if ($PSScriptRoot) {
    if ((Split-Path -Path $PSScriptRoot -Leaf) -eq 'modules') {
        Split-Path -Path $PSScriptRoot -Parent
    }
    else {
        $PSScriptRoot
    }
}
else {
    Split-Path -Path $PROFILE.CurrentUserCurrentHost -Parent
}
$script:CustomProfile = @(
    (Join-Path -Path (Split-Path -Path $PROFILE.CurrentUserCurrentHost -Parent) -ChildPath 'CTTcustom.ps1'),
    (Join-Path -Path $script:ProfileRoot -ChildPath 'CTTcustom.ps1')
) | Select-Object -Unique | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1

if ($script:CustomProfile) {
    . $script:CustomProfile
}

$isInteractiveShell = Test-InteractiveShell
$debug = if ($null -ne $debug_Override) { [bool]$debug_Override } else { $false }
$repo_root = if ($repo_root_Override) { $repo_root_Override } else { 'https://raw.githubusercontent.com/luzede' }
$profileDir = Get-ProfileDir
$timeFilePath = if ($timeFilePath_Override) { $timeFilePath_Override } else { Join-Path $profileDir 'LastExecutionTime.txt' }
$updateInterval = if ($null -ne $updateInterval_Override) { [int]$updateInterval_Override } else { 7 }
$showHelpOnLaunch = if ($null -ne $show_help_Override) { [bool]$show_help_Override } else { $false }


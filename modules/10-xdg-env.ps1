# ======================================================================
# Module 10: XDG Base Directory Provisioning
# ======================================================================

# XDG Base Directory Specification defaults for user binaries, configs, data, cache, and state.
if (-not $env:XDG_BIN_HOME)    { $env:XDG_BIN_HOME    = "$HOME\.local\bin" }
if (-not $env:XDG_CONFIG_HOME) { $env:XDG_CONFIG_HOME = "$HOME\.config" }
if (-not $env:XDG_DATA_HOME)   { $env:XDG_DATA_HOME   = "$HOME\.local\share" }
if (-not $env:XDG_CACHE_HOME)  { $env:XDG_CACHE_HOME  = "$HOME\.cache" }
if (-not $env:XDG_STATE_HOME)  { $env:XDG_STATE_HOME  = "$HOME\.local\state" }

if ((Test-Path -LiteralPath $env:XDG_BIN_HOME -PathType Container) -and (($env:PATH -split ';') -notcontains $env:XDG_BIN_HOME)) {
    $env:PATH = "$env:XDG_BIN_HOME;$env:PATH"
}

function Initialize-XdgEnvironment {
    <#
    .SYNOPSIS
        One-time provisioning of persistent User XDG base environment variables and directories.
        Run automatically on first setup or manually with -Force to repair paths.
    #>
    [CmdletBinding()]
    param([switch]$Force)

    $cacheDir = Get-ProfileCacheDir
    $customDir = Get-ProfileCustomDir
    $sentinelFile = Join-Path $cacheDir '.xdg-initialized'
    if (-not $Force -and (Test-Path -LiteralPath $sentinelFile -PathType Leaf)) {
        return
    }

    Set-PersistentEnv 'XDG_BIN_HOME' $env:XDG_BIN_HOME
    Set-PersistentEnv 'XDG_CONFIG_HOME' $env:XDG_CONFIG_HOME
    Set-PersistentEnv 'XDG_DATA_HOME' $env:XDG_DATA_HOME
    Set-PersistentEnv 'XDG_CACHE_HOME' $env:XDG_CACHE_HOME
    Set-PersistentEnv 'XDG_STATE_HOME' $env:XDG_STATE_HOME

    $directories = @(
        $env:XDG_BIN_HOME,
        $env:XDG_CONFIG_HOME,
        $env:XDG_DATA_HOME,
        $env:XDG_CACHE_HOME,
        $env:XDG_STATE_HOME,
        $cacheDir,
        $customDir
    )

    foreach ($dir in $directories) {
        if (-not (Test-Path -LiteralPath $dir -PathType Container)) {
            New-Item -ItemType Directory -Path $dir -Force -ErrorAction Stop | Out-Null
        }
    }

    Get-Date -Format 'o' | Set-Content -LiteralPath $sentinelFile -Encoding UTF8 -ErrorAction Stop
}

# Only run one-time XDG provisioning if the sentinel file doesn't exist yet
if (-not (Test-Path -LiteralPath (Join-Path (Get-ProfileCacheDir) '.xdg-initialized') -PathType Leaf)) {
    Initialize-XdgEnvironment
}

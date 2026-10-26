# ======================================================================
# Module 10: XDG Base Directory Provisioning
# ======================================================================

# XDG Base Directory Specification defaults for user binaries, configs, data, cache, and state.
if (-not $env:XDG_BIN_HOME)    { $env:XDG_BIN_HOME    = "$HOME\.local\bin" }
if (-not $env:XDG_CONFIG_HOME) { $env:XDG_CONFIG_HOME = "$HOME\.config" }
if (-not $env:XDG_DATA_HOME)   { $env:XDG_DATA_HOME   = "$HOME\.local\share" }
if (-not $env:XDG_CACHE_HOME)  { $env:XDG_CACHE_HOME  = "$HOME\.cache" }
if (-not $env:XDG_STATE_HOME)  { $env:XDG_STATE_HOME  = "$HOME\.local\state" }

if (($env:PATH -split ';') -notcontains $env:XDG_BIN_HOME) {
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
    $profileDir = Get-ProfileDir
    $sentinelFile = Join-Path $profileDir '.xdg-initialized'
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
        if ([string]::IsNullOrWhiteSpace($dir) -or -not [System.IO.Path]::IsPathRooted($dir)) {
            Write-Warning "Skipping XDG directory with non-absolute path: '$dir'"
            continue
        }
        if (-not (Test-Path -LiteralPath $dir -PathType Container)) {
            New-Item -ItemType Directory -Path $dir -Force -ErrorAction Stop | Out-Null
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($env:XDG_BIN_HOME) -and [System.IO.Path]::IsPathRooted($env:XDG_BIN_HOME)) {
        if (($env:PATH -split ';') -notcontains $env:XDG_BIN_HOME) {
            $env:PATH = "$env:XDG_BIN_HOME;$env:PATH"
        }

        $envKey = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Environment', $true)
        if (-not $envKey) {
            $envKey = [Microsoft.Win32.Registry]::CurrentUser.CreateSubKey('Environment')
        }
        try {
            $rawUserPath = [string]$envKey.GetValue('Path', '', [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
            $userParts = @($rawUserPath -split ';' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
            $expandedParts = @($userParts | ForEach-Object { [Environment]::ExpandEnvironmentVariables($_) })
            if ($expandedParts -notcontains $env:XDG_BIN_HOME) {
                $newPath = if ($userParts.Count -gt 0) { "$env:XDG_BIN_HOME;$rawUserPath" } else { $env:XDG_BIN_HOME }
                $envKey.SetValue('Path', $newPath, [Microsoft.Win32.RegistryValueKind]::ExpandString)
            }
        }
        finally {
            $envKey.Dispose()
        }
    }

    Get-Date -Format 'o' | Set-Content -LiteralPath $sentinelFile -Encoding UTF8 -ErrorAction Stop
}

# Run XDG provisioning safely (it checks its own sentinel unless -Force is given)
try {
    Initialize-XdgEnvironment -ErrorAction Stop
}
catch {
    Write-Warning "XDG environment provisioning failed: $_"
}

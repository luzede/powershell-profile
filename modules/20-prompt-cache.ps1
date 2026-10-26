# ======================================================================
# Module 20: Prompt, Themes & Cached Tool Initialization (PowerShell 7+)
# ======================================================================

if (-not $global:RegisteredCachedInits) {
    $global:RegisteredCachedInits = @{}
}

if (IsInteractiveShell) {
    try {
        $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
        $adminSuffix = if ($isAdmin) { ' [ADMIN]' } else { '' }
        $Host.UI.RawUI.WindowTitle = "PowerShell $($PSVersionTable.PSVersion)$adminSuffix"
    }
    catch {
        Write-Verbose "Unable to set console title: $_"
    }
}

function Get-Theme {
    param(
        [Parameter(Mandatory = $true)]
        [ValidatePattern('^[a-zA-Z0-9._-]+$')]
        [string]$ThemeName
    )
    $theme = $ThemeName.ToLower()
    $themeDir = Join-Path (Get-ProfileDir) 'Themes'
    $themePath = Join-Path $themeDir "$theme.omp.json"

    if (-not [System.IO.Directory]::Exists($themeDir)) {
        [System.IO.Directory]::CreateDirectory($themeDir) | Out-Null
    }

    try {
        $Uri = "https://raw.githubusercontent.com/JanDeDobbeleer/oh-my-posh/main/themes/$theme.omp.json"
        Save-UriToFile -Uri $Uri -OutFile $themePath
        Write-Host "Downloaded Oh My Posh Theme: $theme" -ForegroundColor Green
        return $themePath
    }
    catch {
        Write-Error "Failed to download theme '$ThemeName'. Please verify the name or your internet connection."
        return $null
    }
}

function Set-Theme {
    param(
        [Parameter(Mandatory = $true)]
        [ValidatePattern('^[a-zA-Z0-9._-]+$')]
        [string]$ThemeName
    )

    $theme = $ThemeName.ToLower()
    $themesDir = Join-Path (Get-ProfileDir) 'Themes'
    $themePath = Join-Path $themesDir "$theme.omp.json"

    if (-not [System.IO.File]::Exists($themePath)) {
        $downloaded = Get-Theme -ThemeName $theme
        if (-not $downloaded) {
            return
        }
    }

    Set-PersistentEnv 'POSH_CONFIG' $themePath
    Update-InitCache -Tool 'oh-my-posh'
    . Initialize-PromptTool
    if (Get-Command -Name 'Initialize-CustomProfile' -ErrorAction SilentlyContinue) {
        . Initialize-CustomProfile
    }
}

function Resolve-OhMyPoshTheme {
    if ($env:POSH_CONFIG -and [System.IO.File]::Exists($env:POSH_CONFIG)) {
        return $env:POSH_CONFIG
    }
    $userPoshConfig = [Environment]::GetEnvironmentVariable('POSH_CONFIG', 'User')
    if ($userPoshConfig -and [System.IO.File]::Exists($userPoshConfig)) {
        return $userPoshConfig
    }
    $defaultTheme = Join-Path (Get-ProfileDir) 'Themes\cobalt2.omp.json'
    if ([System.IO.File]::Exists($defaultTheme)) {
        return $defaultTheme
    }
    return $null
}

function Use-CachedInit {
    <#
    .SYNOPSIS
        Caches the output of a CLI initialization scriptblock to a file and dot-sources it.
        Automatically rebuilt when Clear-InitCache is run or when -Force is passed.
    .EXAMPLE
        Use-CachedInit -Name 'mise' -Command { mise activate pwsh }
    .EXAMPLE
        Use-CachedInit -Name 'fnm' -Command { fnm env --use-on-cd --shell power-shell }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidatePattern('^[a-zA-Z0-9._-]+$')]
        [string]$Name,

        [Parameter(Mandatory)]
        [scriptblock]$Command,

        [switch]$Force,

        [switch]$NoLoad
    )

    $key = $Name.ToLower()
    $global:RegisteredCachedInits[$key] = $Command

    $cacheDir = Get-ProfileCacheDir
    $cacheFile = Join-Path $cacheDir "$key-init.ps1"

    if ($Force -or -not [System.IO.File]::Exists($cacheFile)) {
        if (-not [System.IO.Directory]::Exists($cacheDir)) {
            [System.IO.Directory]::CreateDirectory($cacheDir) | Out-Null
        }

        $global:LASTEXITCODE = 0
        $rawLines = @(& $Command)
        if ($LASTEXITCODE -ne 0 -or $rawLines.Count -eq 0) {
            Write-Warning "Failed to generate '$key' init cache (exit code: $LASTEXITCODE)."
            if ([System.IO.File]::Exists($cacheFile)) {
                [System.IO.File]::Delete($cacheFile)
            }
            return
        }

        $baselinePaths = @(
            ([Environment]::GetEnvironmentVariable('Path', 'Machine') -split ';'),
            ([Environment]::GetEnvironmentVariable('Path', 'User') -split ';'),
            $env:XDG_BIN_HOME
        ) | ForEach-Object { $_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique

        $transformedLines = $rawLines | ForEach-Object {
            if ($_ -match '^\$\{?Env:PATH\}?\s*=\s*[''"]([^''"]+)[''"](.*)$') {
                # Convert static PATH snapshot into non-destructive dynamic prepend against persistent Machine/User PATH
                $capturedPaths = $Matches[1] -split ';' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
                $remainder = $Matches[2]
                $addedPaths = @($capturedPaths | Where-Object { $baselinePaths -notcontains $_ })
                if ($addedPaths.Count -gt 0) {
                    foreach ($p in $addedPaths) {
                        $escapedPath = $p -replace "'", "''"
                        "if (`$env:PATH.IndexOf('$escapedPath', [System.StringComparison]::OrdinalIgnoreCase) -lt 0 -and [System.IO.Directory]::Exists('$escapedPath')) { `$env:PATH = '$escapedPath;' + `$env:PATH }"
                    }
                }
                if (-not [string]::IsNullOrWhiteSpace($remainder)) {
                    Write-Verbose "Dropping trailing PATH fragment for '$key': $remainder"
                }
            }
            elseif ($_ -match '^function\s+(?!([Gg]lobal|[Ss]cript):)(?!__enable_)([A-Za-z0-9_-]+)') {
                $_ -replace '^function\s+', 'function global:'
            }
            else {
                $_.Replace(
                    'if ([Microsoft.PowerShell.PSConsoleReadLine]::GetHistoryItems()[-1].CommandLine',
                    '$__hist = [Microsoft.PowerShell.PSConsoleReadLine]::GetHistoryItems(); if ($__hist -and $__hist[-1].CommandLine'
                )
            }
        }

        [System.IO.File]::WriteAllText($cacheFile, ($transformedLines -join "`n"), [System.Text.UTF8Encoding]::new($false))
    }

    if (-not $NoLoad -and (IsInteractiveShell) -and [System.IO.File]::Exists($cacheFile)) {
        . $cacheFile
    }
}

function Update-InitCache {
    <#
    .SYNOPSIS
        Generates or refreshes cached initialization scripts for oh-my-posh, zoxide, and any custom Use-CachedInit tools.
    #>
    [CmdletBinding()]
    param(
        [string]$Tool = 'All'
    )

    $cacheDir = Get-ProfileCacheDir
    if (-not [System.IO.Directory]::Exists($cacheDir)) {
        [System.IO.Directory]::CreateDirectory($cacheDir) | Out-Null
    }

    if ($Tool -in @('All', 'oh-my-posh') -and (Test-Command oh-my-posh)) {
        $theme = Resolve-OhMyPoshTheme
        if ($theme) {
            $ompCache = Join-Path $cacheDir 'omp-init.ps1'
            $ompThemeMeta = Join-Path $cacheDir 'omp-theme.txt'
            $ompLines = & oh-my-posh init pwsh --config $theme --print
            if ($LASTEXITCODE -ne 0 -or -not $ompLines) {
                Write-Warning "Failed to generate oh-my-posh init cache (exit code: $LASTEXITCODE)."
            }
            else {
                $ompScript = $ompLines -join "`n"

                $oldOmpScript = $ompScript
                # 1. Give each terminal session a unique POSH_SESSION_ID instead of a static cached GUID
                $ompScript = $ompScript -replace '(?m)^\$env:POSH_SESSION_ID\s*=\s*"[^"]+"', '$env:POSH_SESSION_ID = [guid]::NewGuid().ToString()'
                if ($ompScript -eq $oldOmpScript) {
                    Write-Verbose 'POSH_SESSION_ID assignment pattern was not found in oh-my-posh output.'
                }

                # 2. Pre-compute the secondary continuation prompt so startup doesn't spawn oh-my-posh.exe synchronously (~380ms saved)
                $secondaryLines = & oh-my-posh print secondary --config $theme --shell=pwsh
                if ($LASTEXITCODE -eq 0 -and $null -ne $secondaryLines) {
                    $secondaryPrompt = ($secondaryLines -join "`n") -replace "'", "''"
                    $ompScript = $ompScript.Replace(
                        '((Invoke-Utf8Posh @("print", "secondary", "--shell=$script:ShellName")) -join "`n")',
                        "'$secondaryPrompt'"
                    )
                }

                [System.IO.File]::WriteAllText($ompCache, $ompScript, [System.Text.UTF8Encoding]::new($false))
                [System.IO.File]::WriteAllText($ompThemeMeta, $theme, [System.Text.UTF8Encoding]::new($false))
            }
        }
    }

    if ($Tool -in @('All', 'zoxide') -and (Test-Command zoxide)) {
        $zoxideCache = Join-Path $cacheDir 'zoxide-init.ps1'
        $zoxideLines = & zoxide init --cmd z powershell
        if ($LASTEXITCODE -ne 0 -or -not $zoxideLines) {
            Write-Warning "Failed to generate zoxide init cache (exit code: $LASTEXITCODE)."
        }
        else {
            [System.IO.File]::WriteAllText($zoxideCache, ($zoxideLines -join "`n"), [System.Text.UTF8Encoding]::new($false))
        }
    }

    if ($global:RegisteredCachedInits -and $global:RegisteredCachedInits.Count -gt 0) {
        foreach ($entry in @($global:RegisteredCachedInits.GetEnumerator())) {
            if ($Tool -in @('All', $entry.Key)) {
                Use-CachedInit -Name $entry.Key -Command $entry.Value -Force -NoLoad
            }
        }
    }
}

function Clear-InitCache {
    <#
    .SYNOPSIS
        Clears and regenerates cached shell startup scripts for oh-my-posh, zoxide, and any custom Use-CachedInit tools.
    #>
    [CmdletBinding()]
    param()

    $cacheDir = Get-ProfileCacheDir
    if ([System.IO.Directory]::Exists($cacheDir)) {
        Get-ChildItem -LiteralPath $cacheDir -Filter '*-init.ps1' -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
        $themeMeta = Join-Path $cacheDir 'omp-theme.txt'
        if ([System.IO.File]::Exists($themeMeta)) {
            [System.IO.File]::Delete($themeMeta)
        }
    }
    Update-InitCache -Tool 'All'
    Write-Host 'Shell initialization cache rebuilt.' -ForegroundColor Green
}

function Initialize-PromptTool {
    if (-not (IsInteractiveShell)) {
        return
    }

    $cacheDir = Get-ProfileCacheDir

    # Reset prompt hook sentinels so reloading the profile cleanly re-chains oh-my-posh -> zoxide -> custom hooks
    Remove-Item -Path Function:\prompt -ErrorAction SilentlyContinue
    $global:__zoxide_hooked = $null
    $global:__mise_pwsh_previous_prompt_function = $null

    # 1. Oh My Posh (Cached)
    $ompLoaded = $false
    $ompCache = Join-Path $cacheDir 'omp-init.ps1'
    $ompThemeMeta = Join-Path $cacheDir 'omp-theme.txt'
    $theme = Resolve-OhMyPoshTheme

    if ($theme) {
        $cachedTheme = if ([System.IO.File]::Exists($ompThemeMeta)) {
            [System.IO.File]::ReadAllText($ompThemeMeta).Trim()
        } else { $null }

        if (-not [System.IO.File]::Exists($ompCache) -or $cachedTheme -ne $theme) {
            Update-InitCache -Tool 'oh-my-posh'
        }

        if ([System.IO.File]::Exists($ompCache)) {
            . $ompCache
            $ompLoaded = $true
        }
    }
    elseif (Test-Command oh-my-posh) {
        Write-Warning 'Oh My Posh theme not found. Run setup.ps1 to install cobalt2.omp.json.'
    }

    if (-not $ompLoaded) {
        function global:prompt {
            $marker = if ($isAdmin) { '#' } else { '$' }
            "[$(Get-Location)] $marker "
        }
    }

    # 2. zoxide (Cached)
    $zoxideCache = Join-Path $cacheDir 'zoxide-init.ps1'
    if (-not [System.IO.File]::Exists($zoxideCache)) {
        Update-InitCache -Tool 'zoxide'
    }
    if ([System.IO.File]::Exists($zoxideCache)) {
        . $zoxideCache
    }
}

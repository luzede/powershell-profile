# ======================================================================
# Module 20: Prompt, Themes & Cached Tool Initialization
# ======================================================================

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $global:RegisteredCachedInits) {
    $global:RegisteredCachedInits = @{}
}

if ($isInteractiveShell) {
    try {
        $adminSuffix = if ($isAdmin) { ' [ADMIN]' } else { '' }
        $Host.UI.RawUI.WindowTitle = "PowerShell $($PSVersionTable.PSVersion)$adminSuffix"
    }
    catch {
        Write-Verbose "Unable to set console title: $_"
    }
}

function prompt {
    $marker = if ($isAdmin) { '#' } else { '$' }
    "[$(Get-Location)] $marker "
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

    if (-not (Test-Path -LiteralPath $themeDir -PathType Container)) {
        New-Item -Path $themeDir -ItemType Directory -Force -ErrorAction Stop | Out-Null
    }

    try {
        $Uri = "https://raw.githubusercontent.com/JanDeDobbeleer/oh-my-posh/main/themes/$theme.omp.json"
        Invoke-WebRequest -Uri $Uri -OutFile $themePath -ErrorAction Stop
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

    if (-not (Test-Path -LiteralPath $themePath -PathType Leaf)) {
        $downloaded = Get-Theme -ThemeName $theme
        if (-not $downloaded) {
            return
        }
    }

    Set-PersistentEnv 'POSH_CONFIG' $themePath
    Update-InitCache -Tool 'oh-my-posh'
    $ompCache = Join-Path (Get-ProfileCacheDir) 'omp-init.ps1'
    if (Test-Path -LiteralPath $ompCache -PathType Leaf) {
        . $ompCache
    }
}

function Resolve-OhMyPoshTheme {
    $poshConfig = if ($env:POSH_CONFIG) { $env:POSH_CONFIG } else { [Environment]::GetEnvironmentVariable('POSH_CONFIG', 'User') }

    $candidates = @(
        $poshConfig,
        (Join-Path (Join-Path (Get-ProfileDir) 'Themes') 'cobalt2.omp.json')
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }

    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            return $candidate
        }
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

    if ($Force -or -not (Test-Path -LiteralPath $cacheFile -PathType Leaf)) {
        if (-not (Test-Path -LiteralPath $cacheDir -PathType Container)) {
            New-Item -ItemType Directory -Path $cacheDir -Force -ErrorAction Stop | Out-Null
        }

        $global:LASTEXITCODE = 0
        $rawLines = @(& $Command)
        if ($LASTEXITCODE -ne 0 -or $rawLines.Count -eq 0) {
            Write-Warning "Failed to generate '$key' init cache (exit code: $LASTEXITCODE)."
            return
        }

        $baselinePaths = @(
            ([Environment]::GetEnvironmentVariable('Path', 'Machine') -split ';'),
            ([Environment]::GetEnvironmentVariable('Path', 'User') -split ';'),
            $env:XDG_BIN_HOME
        ) | ForEach-Object { $_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique

        $transformedLines = $rawLines | ForEach-Object {
            if ($_ -match '^\$Env:PATH\s*=\s*[''"]([^''"]+)[''"]') {
                # Convert static PATH snapshot into non-destructive dynamic prepend against persistent Machine/User PATH
                $capturedPaths = $Matches[1] -split ';' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
                $addedPaths = @($capturedPaths | Where-Object { $baselinePaths -notcontains $_ })
                if ($addedPaths.Count -gt 0) {
                    foreach ($p in $addedPaths) {
                        $escapedPath = $p -replace "'", "''"
                        "if ((Test-Path -LiteralPath '$escapedPath' -PathType Container) -and ((`$env:PATH -split ';') -notcontains '$escapedPath')) { `$env:PATH = '$escapedPath;' + `$env:PATH }"
                    }
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

        ($transformedLines -join "`n") | Set-Content -LiteralPath $cacheFile -Encoding UTF8 -ErrorAction Stop
    }

    if (-not $NoLoad -and $isInteractiveShell -and (Test-Path -LiteralPath $cacheFile -PathType Leaf)) {
        $__existingVars = @{}
        foreach ($__v in (Get-Variable -Scope Local)) {
            $__existingVars[$__v.Name] = $true
        }

        . $cacheFile

        foreach ($__v in (Get-Variable -Scope Local)) {
            if (-not $__existingVars.ContainsKey($__v.Name) -and $__v.Name -ne '__existingVars') {
                Set-Variable -Name $__v.Name -Value $__v.Value -Scope Global -Force -ErrorAction SilentlyContinue
            }
        }
        foreach ($__fn in (Get-ChildItem -Path Function:\)) {
            if ($__fn.Name -ne 'Use-CachedInit') {
                Set-Item -Path "Function:\global:$($__fn.Name)" -Value $__fn.ScriptBlock -Force
            }
        }
        foreach ($__al in (Get-Alias)) {
            if ($__al.Options -notmatch 'ReadOnly|Constant') {
                Set-Alias -Name $__al.Name -Value $__al.Definition -Scope Global -Force -ErrorAction SilentlyContinue
            }
        }
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
    if (-not (Test-Path -LiteralPath $cacheDir -PathType Container)) {
        New-Item -ItemType Directory -Path $cacheDir -Force -ErrorAction Stop | Out-Null
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

                # 1. Give each terminal session a unique POSH_SESSION_ID instead of a static cached GUID
                $ompScript = $ompScript -replace '(?m)^\$env:POSH_SESSION_ID\s*=\s*"[^"]+"', '$env:POSH_SESSION_ID = [guid]::NewGuid().ToString()'

                # 2. Pre-compute the secondary continuation prompt so startup doesn't spawn oh-my-posh.exe synchronously (~380ms saved)
                $secondaryLines = & oh-my-posh print secondary --config $theme --shell=pwsh
                if ($LASTEXITCODE -eq 0 -and $null -ne $secondaryLines) {
                    $secondaryPrompt = ($secondaryLines -join "`n") -replace "'", "''"
                    $ompScript = $ompScript.Replace(
                        '((Invoke-Utf8Posh @("print", "secondary", "--shell=$script:ShellName")) -join "`n")',
                        "'$secondaryPrompt'"
                    )
                }

                $ompScript | Set-Content -LiteralPath $ompCache -Encoding UTF8 -ErrorAction Stop
                $theme | Set-Content -LiteralPath $ompThemeMeta -Encoding UTF8 -ErrorAction Stop
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
            ($zoxideLines -join "`n") | Set-Content -LiteralPath $zoxideCache -Encoding UTF8 -ErrorAction Stop
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
    if (Test-Path -LiteralPath $cacheDir -PathType Container) {
        Get-ChildItem -LiteralPath $cacheDir -Filter '*-init.ps1' -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath (Join-Path $cacheDir 'omp-theme.txt') -Force -ErrorAction SilentlyContinue
    }
    Update-InitCache -Tool 'All'
    Write-Host 'Shell initialization cache rebuilt.' -ForegroundColor Green
}

function Initialize-PromptTool {
    if (-not $isInteractiveShell) {
        return
    }

    $cacheDir = Get-ProfileCacheDir

    # 1. Oh My Posh (Cached)
    $ompCache = Join-Path $cacheDir 'omp-init.ps1'
    $ompThemeMeta = Join-Path $cacheDir 'omp-theme.txt'
    $theme = Resolve-OhMyPoshTheme

    if ($theme) {
        $cachedTheme = if (Test-Path -LiteralPath $ompThemeMeta -PathType Leaf) {
            ([string](Get-Content -LiteralPath $ompThemeMeta -Raw -ErrorAction SilentlyContinue)).Trim()
        } else { $null }

        if (-not (Test-Path -LiteralPath $ompCache -PathType Leaf) -or $cachedTheme -ne $theme) {
            Update-InitCache -Tool 'oh-my-posh'
        }

        if (Test-Path -LiteralPath $ompCache -PathType Leaf) {
            . $ompCache
        }
    }
    elseif (Test-Command oh-my-posh) {
        Write-Warning 'Oh My Posh theme not found. Run setup.ps1 to install cobalt2.omp.json.'
    }

    # 2. zoxide (Cached)
    $zoxideCache = Join-Path $cacheDir 'zoxide-init.ps1'
    if (-not (Test-Path -LiteralPath $zoxideCache -PathType Leaf)) {
        Update-InitCache -Tool 'zoxide'
    }
    if (Test-Path -LiteralPath $zoxideCache -PathType Leaf) {
        . $zoxideCache
    }
}

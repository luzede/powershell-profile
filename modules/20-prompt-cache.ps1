# ======================================================================
# Module 20: Prompt, Themes & Cached Tool Initialization
# ======================================================================

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

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

function Update-InitCache {
    <#
    .SYNOPSIS
        Generates or refreshes cached initialization scripts for oh-my-posh, zoxide, and mise.
        Pre-computes static prompt values and strips redundant synchronous CLI calls.
    #>
    [CmdletBinding()]
    param(
        [ValidateSet('All', 'oh-my-posh', 'zoxide', 'mise')]
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

    if ($Tool -in @('All', 'mise')) {
        $miseApp = Get-Command -Name 'mise' -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($miseApp) {
            $miseCache = Join-Path $cacheDir 'mise-init.ps1'
            $rawMiseLines = @(& $miseApp.Source activate pwsh)
            if ($LASTEXITCODE -ne 0 -or $rawMiseLines.Count -eq 0) {
                Write-Warning "Failed to generate mise init cache (exit code: $LASTEXITCODE)."
            }
            else {
                # 1. Replace hardcoded PATH snapshot with dynamic shims injection so new system PATH entries are never overwritten
                $dynamicPathBlock = @'
$__miseShims = Join-Path $env:LOCALAPPDATA 'mise\shims'
if ((Test-Path -LiteralPath $__miseShims -PathType Container) -and (($env:PATH -split ';') -notcontains $__miseShims)) {
    $env:PATH = "$__miseShims;$env:PATH"
}
'@

                # 2. Transform lines: dynamic PATH, global function scope, defer initial top-level _mise_hook to prompt, and guard empty PSReadLine history
                $miseLines = $rawMiseLines | ForEach-Object {
                    if ($_ -like '$Env:PATH=*') {
                        $dynamicPathBlock
                    }
                    elseif ($_ -eq '_mise_hook') {
                        '# _mise_hook deferred to prompt/chpwd hook'
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

                ($miseLines -join "`n") | Set-Content -LiteralPath $miseCache -Encoding UTF8 -ErrorAction Stop
            }
        }
    }
}

function Clear-InitCache {
    <#
    .SYNOPSIS
        Clears and regenerates cached shell startup scripts for oh-my-posh, zoxide, and mise.
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

    ########################################################################
    # ===================================
    # Name: mise-en-place
    # Winget: jdx.mise
    # Link: https://github.com/jdx/mise
    # Description:
    #   Tools version management, this script activates the mise tool
    #   automatically whenever you open powershell so you can have access
    #   to global installed version of tools or the local one if configuration
    #   for it exists.
    # ===================================
    $miseCache = Join-Path $cacheDir 'mise-init.ps1'
    if (-not (Test-Path -LiteralPath $miseCache -PathType Leaf)) {
        Update-InitCache -Tool 'mise'
    }
    if (Test-Path -LiteralPath $miseCache -PathType Leaf) {
        . $miseCache
    }
    # ===================================
    ########################################################################
}

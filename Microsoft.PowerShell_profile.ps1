### PowerShell Profile (Bundled from modules/*.ps1 via setprofile.ps1)
# Do not edit this bundled file directly; edit files in modules/ and run ./setprofile.ps1

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

$isInteractiveShell = Test-InteractiveShell
$repo_root = 'https://raw.githubusercontent.com/luzede'
$profileDir = Get-ProfileDir
$timeFilePath = Join-Path $profileDir 'LastExecutionTime.txt'
$updateInterval = 7

# ======================================================================
# Module 10: XDG Base Directory & Tool Environment Provisioning
# ======================================================================

# * COMMON ENVIRONMENT VARIABLES AND SETTINGS FOR INSTALLED TOOLS *
# **********************************************************************
# XDG is a set of standards for defining where user data files,
# configuration files, cache files, and other types of files should be stored.
if (-not $env:XDG_BIN_HOME)    { $env:XDG_BIN_HOME    = "$HOME\.local\bin" }
if (-not $env:XDG_CONFIG_HOME) { $env:XDG_CONFIG_HOME = "$HOME\.config" }
if (-not $env:XDG_DATA_HOME)   { $env:XDG_DATA_HOME   = "$HOME\.local\share" }
if (-not $env:XDG_CACHE_HOME)  { $env:XDG_CACHE_HOME  = "$HOME\.cache" }
if (-not $env:XDG_STATE_HOME)  { $env:XDG_STATE_HOME  = "$HOME\.local\state" }

# Fast in-session defaults in case persistent User environment has not been inherited yet
if (-not $env:LESSHISTFILE)                { $env:LESSHISTFILE                = "$env:XDG_CONFIG_HOME\less\_lesshst" }
if (-not $env:BUN_INSTALL)                 { $env:BUN_INSTALL                 = "$env:XDG_DATA_HOME\bun" }
if (-not $env:BUN_INSTALL_GLOBAL_DIR)      { $env:BUN_INSTALL_GLOBAL_DIR      = "$env:XDG_DATA_HOME\bun\global" }
if (-not $env:BUN_INSTALL_BIN)             { $env:BUN_INSTALL_BIN             = "$env:XDG_DATA_HOME\bun\bin" }
if (-not $env:AWS_SHARED_CREDENTIALS_FILE) { $env:AWS_SHARED_CREDENTIALS_FILE = "$env:XDG_CONFIG_HOME\aws\credentials" }
if (-not $env:AWS_CONFIG_FILE)             { $env:AWS_CONFIG_FILE             = "$env:XDG_CONFIG_HOME\aws\config" }
if (-not $env:AZURE_CONFIG_DIR)            { $env:AZURE_CONFIG_DIR            = "$env:XDG_DATA_HOME\azure" }
if (-not $env:RUSTUP_HOME)                 { $env:RUSTUP_HOME                 = "$env:XDG_DATA_HOME\rustup" }
if (-not $env:CARGO_HOME)                  { $env:CARGO_HOME                  = "$env:XDG_DATA_HOME\cargo" }
if (-not $env:CLAUDE_CONFIG_DIR)           { $env:CLAUDE_CONFIG_DIR           = "$env:XDG_CONFIG_HOME\claude" }

function Initialize-XdgEnvironment {
    <#
    .SYNOPSIS
        One-time provisioning of persistent User environment variables and XDG directories.
        Run automatically on first setup or manually whenever tool paths need to be repaired.
    #>
    [CmdletBinding()]
    param([switch]$Force)

    $cacheDir = Get-ProfileCacheDir
    $sentinelFile = Join-Path $cacheDir '.xdg-initialized'
    if (-not $Force -and (Test-Path -LiteralPath $sentinelFile -PathType Leaf)) {
        return
    }

    Set-PersistentEnv 'XDG_BIN_HOME' $env:XDG_BIN_HOME
    Set-PersistentEnv 'XDG_CONFIG_HOME' $env:XDG_CONFIG_HOME
    Set-PersistentEnv 'XDG_DATA_HOME' $env:XDG_DATA_HOME
    Set-PersistentEnv 'XDG_CACHE_HOME' $env:XDG_CACHE_HOME
    Set-PersistentEnv 'XDG_STATE_HOME' $env:XDG_STATE_HOME

    ########################################################################
    # ===================================
    # Name: less
    # Winget: jftuga.less
    # Link: https://github.com/jftuga/less-Windows
    # Description:
    #   Because I didn't like that it was creating the "_lesshst" file
    #   in the user's folder, I am changing the environment variable
    #   and creating a specified folder for it in ".config/less"
    #   so that "_lesshst" will be created there
    #
    #   Also "less" is installed because it helps "bat" command and is
    #   more feature full than the powershell equivalent.
    # ===================================
    $lessConfigDir = "$env:XDG_CONFIG_HOME\less"
    $lessHistFile = Join-Path $lessConfigDir '_lesshst'
    Set-PersistentEnv 'LESSHISTFILE' $lessHistFile
    # ===================================
    ########################################################################

    ########################################################################
    # ===================================
    # Name: Git
    # Winget: Git.Git
    # Link: https://git-scm.com/
    # Description:
    #   I don't like that git creates the ".gitconfig"
    #   file in the user's folder, so I create and use the "config"
    #   file in ".config/git" because git website says
    #   "write to $XDG_CONFIG_HOME/git/config file if this file exists and the
    #   ~/.gitconfig file doesn’t"
    # ===================================
    $gitConfigDir = "$env:XDG_CONFIG_HOME\git"
    $gitConfigFile = "$gitConfigDir\config"
    # ===================================
    ########################################################################

    # ########################################################################
    # # ===================================
    # # Name: docker
    # # Winget: Docker.DockerDesktop
    # # Link: https://www.docker.com/products/docker-desktop/
    # # Description:
    # #   I want docker config to be in XDG_CONFIG_HOME as well,
    # #   instead of the user's folder at "~/.docker"
    # # ===================================
    # # Set the DOCKER_CONFIG environment variable to point to the new directory
    # $dockerConfigDir = "$env:XDG_CONFIG_HOME\docker"
    # $env:DOCKER_CONFIG = $dockerConfigDir
    # ! RIGHT NOW THERE IS NO WAY TO STOP DOCKER DESKTOP FROM CREATING THE ".docker" FOLDER
    # ! SO THIS IS COMMENTED OUT FOR NOW UNTIL A SOLUTION IS FOUND
    # # ===================================
    # ########################################################################

    ########################################################################
    # ===================================
    # Name: bun
    # Winget:
    # Link: https://bun.com/docs/installation#windows
    # Description:
    #   Where to install bun, I want it to follow XDG specification
    # ===================================
    Set-PersistentEnv 'BUN_INSTALL' "$env:XDG_DATA_HOME\bun"
    Set-PersistentEnv 'BUN_INSTALL_GLOBAL_DIR' "$env:XDG_DATA_HOME\bun\global"
    Set-PersistentEnv 'BUN_INSTALL_BIN' "$env:XDG_DATA_HOME\bun\bin"
    # ===================================
    ########################################################################

    ########################################################################
    # ===================================
    # Name: aws
    # Winget: Amazon.AWSCLI
    # Link: https://aws.amazon.com/cli/
    # Description:
    #   I don't like that aws cli creates the ".aws" folder
    #   in the user's folder, so I am changing the environment variables
    #   to follow XDG Base Directory Specification
    # ===================================
    $awsConfigDir = "$env:XDG_CONFIG_HOME\aws"
    Set-PersistentEnv 'AWS_SHARED_CREDENTIALS_FILE' "$awsConfigDir\credentials"
    Set-PersistentEnv 'AWS_CONFIG_FILE' "$awsConfigDir\config"
    # ===================================
    ########################################################################

    ########################################################################
    # ===================================
    # Name: azure-cli
    # Winget: Microsoft.AzureCLI
    # Link: https://learn.microsoft.com/en-us/cli/azure/
    # Description:
    #   I don't like that azure cli creates the ".azure" folder
    #   in the user's folder, so I am changing the environment variable
    #   to follow XDG Base Directory Specification
    # ===================================
    $azureConfigDir = "$env:XDG_DATA_HOME\azure"
    Set-PersistentEnv 'AZURE_CONFIG_DIR' $azureConfigDir
    # ===================================
    ########################################################################

    ########################################################################
    # ===================================
    # Name: Rust, Cargo and Rustup
    # Winget: Rustlang.Rustup
    # Link: https://www.rust-lang.org/learn/get-started
    # Description:
    #   I don't like that Rust, Cargo, and Rustup create the ".cargo" and ".rustup" folders
    #   in the user's folder, so I am changing the environment variables
    #   to follow XDG Base Directory Specification
    # ===================================
    $rustupConfigDir = "$env:XDG_DATA_HOME\rustup"
    $cargoConfigDir = "$env:XDG_DATA_HOME\cargo"
    Set-PersistentEnv 'RUSTUP_HOME' $rustupConfigDir
    Set-PersistentEnv 'CARGO_HOME' $cargoConfigDir
    # ===================================
    ########################################################################

    ########################################################################
    # ===================================
    # Name: Claude Code
    # Winget: Anthropic.ClaudeCode
    # Link: https://claude.ai/code
    # Description:
    #   I don't like that Claude Code creates '~/.claude' folder
    #   in the user's folder, so I am changing the environment variable
    # ===================================
    $claudeConfigDir = "$env:XDG_CONFIG_HOME\claude"
    Set-PersistentEnv 'CLAUDE_CONFIG_DIR' $claudeConfigDir
    # ===================================
    ########################################################################

    $directories = @(
        $env:XDG_BIN_HOME,
        $env:XDG_CONFIG_HOME,
        $env:XDG_DATA_HOME,
        $env:XDG_CACHE_HOME,
        $env:XDG_STATE_HOME,
        $cacheDir,
        $lessConfigDir,
        $gitConfigDir,
        "$env:XDG_DATA_HOME\bun",
        "$env:XDG_DATA_HOME\bun\global",
        "$env:XDG_DATA_HOME\bun\bin",
        $awsConfigDir,
        $azureConfigDir,
        $rustupConfigDir,
        $cargoConfigDir,
        $claudeConfigDir
    )

    foreach ($dir in $directories) {
        if (-not (Test-Path -LiteralPath $dir -PathType Container)) {
            New-Item -ItemType Directory -Path $dir -Force -ErrorAction Stop | Out-Null
        }
    }

    if (-not (Test-Path -LiteralPath $gitConfigFile -PathType Leaf)) {
        New-Item -ItemType File -Path $gitConfigFile -Force -ErrorAction Stop | Out-Null
    }

    Get-Date -Format 'o' | Set-Content -LiteralPath $sentinelFile -Encoding UTF8 -ErrorAction Stop
}

# Only run one-time XDG provisioning if the sentinel file doesn't exist yet
if (-not (Test-Path -LiteralPath (Join-Path (Get-ProfileCacheDir) '.xdg-initialized') -PathType Leaf)) {
    Initialize-XdgEnvironment
}
# **********************************************************************

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

# ======================================================================
# Module 30: PSReadLine, Completions & Deferred Modules
# ======================================================================

function Set-PSReadLineOptionsCompat {
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)][hashtable]$Options)

    $safeOptions = $Options.Clone()
    if ($PSVersionTable.PSEdition -ne 'Core') {
        $safeOptions.Remove('PredictionSource')
        $safeOptions.Remove('PredictionViewStyle')
    }

    if ($PSCmdlet.ShouldProcess('PSReadLine', 'Set PSReadLine options')) {
        Set-PSReadLineOption @safeOptions
    }
}

function Set-PredictionSource {
    [CmdletBinding(SupportsShouldProcess)]
    param()

    if ($PSCmdlet.ShouldProcess('PSReadLine', 'Set prediction source')) {
        if ($PSVersionTable.PSEdition -eq 'Core') {
            Set-PSReadLineOption -PredictionSource HistoryAndPlugin
        }

        Set-PSReadLineOption -MaximumHistoryCount 10000
    }
}

function Initialize-PSReadLine {
    if (-not $isInteractiveShell) {
        return
    }

    $options = @{
        EditMode                      = 'Windows'
        HistoryNoDuplicates           = $true
        HistorySearchCursorMovesToEnd = $true
        PredictionSource              = 'History'
        PredictionViewStyle           = 'ListView'
        BellStyle                     = 'None'
        Colors                        = @{
            Command   = '#87CEEB'
            Parameter = '#98FB98'
            Operator  = '#FFB6C1'
            Variable  = '#DDA0DD'
            String    = '#FFDAB9'
            Number    = '#B0E0E6'
            Type      = '#F0E68C'
            Comment   = '#D3D3D3'
            Keyword   = '#8367c7'
            Error     = '#FF6347'
        }
    }

    Set-PSReadLineOptionsCompat -Options $options
    Set-PSReadLineKeyHandler -Key UpArrow -Function HistorySearchBackward
    Set-PSReadLineKeyHandler -Key DownArrow -Function HistorySearchForward
    Set-PSReadLineKeyHandler -Key Tab -Function MenuComplete
    Set-PSReadLineKeyHandler -Chord 'Ctrl+d' -Function DeleteChar
    Set-PSReadLineKeyHandler -Chord 'Ctrl+w' -Function BackwardDeleteWord
    Set-PSReadLineKeyHandler -Chord 'Alt+d' -Function DeleteWord
    Set-PSReadLineKeyHandler -Chord 'Ctrl+LeftArrow' -Function BackwardWord
    Set-PSReadLineKeyHandler -Chord 'Ctrl+RightArrow' -Function ForwardWord
    Set-PSReadLineKeyHandler -Chord 'Ctrl+z' -Function Undo
    Set-PSReadLineKeyHandler -Chord 'Ctrl+y' -Function Redo

    Set-PSReadLineOption -AddToHistoryHandler {
        param([string]$line)
        $line -notmatch '(?i)(password|secret|token|apikey|connectionstring)'
    }

    Set-PredictionSource
}

function Register-CustomCompletion {
    if (-not $isInteractiveShell) {
        return
    }

    $completionMap = @{
        git  = @('status', 'add', 'commit', 'push', 'pull', 'clone', 'checkout')
        npm  = @('install', 'start', 'run', 'test', 'build')
        deno = @('run', 'compile', 'bundle', 'test', 'lint', 'fmt', 'cache', 'info', 'doc', 'upgrade')
    }

    Register-ArgumentCompleter -Native -CommandName git, npm, deno -ScriptBlock {
        param($wordToComplete, $commandAst, $cursorPosition)
        $null = $cursorPosition
        $completionWord = $wordToComplete
        $map = $completionMap
        $command = [System.IO.Path]::GetFileNameWithoutExtension($commandAst.CommandElements[0].Value)
        if ($map.ContainsKey($command)) {
            $map[$command] |
            Where-Object { $_ -like "$completionWord*" } |
            ForEach-Object { [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_) }
        }
    }.GetNewClosure()

    Register-ArgumentCompleter -Native -CommandName dotnet -ScriptBlock {
        param($wordToComplete, $commandAst, $cursorPosition)
        $null = $wordToComplete
        if (Get-Command -Name dotnet -ErrorAction SilentlyContinue) {
            dotnet complete --position $cursorPosition $commandAst.ToString() |
            ForEach-Object { [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_) }
        }
    }
}

function Initialize-OptionalModule {
    if (-not $isInteractiveShell) {
        return
    }

    # Defer heavy Terminal-Icons and Chocolatey module imports to OnIdle so prompt renders immediately
    Register-EngineEvent -SourceIdentifier PowerShell.OnIdle -MaxTriggerCount 1 -Action {
        try {
            Import-Module -Name Terminal-Icons -Global -ErrorAction Stop
        }
        catch {
            Write-Verbose "Terminal-Icons module is not installed: $_"
        }

        if ($env:ChocolateyInstall) {
            $chocolateyProfile = Join-Path $env:ChocolateyInstall 'helpers\chocolateyProfile.psm1'
            if (Test-Path -LiteralPath $chocolateyProfile -PathType Leaf) {
                Import-Module $chocolateyProfile -Global -ErrorAction SilentlyContinue
            }
        }
    } | Out-Null
}

# ======================================================================
# Module 40: Linux / POSIX-Style Utilities & Shell Helpers
# ======================================================================

function touch {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromRemainingArguments)]
        [string[]]$Path
    )
    process {
        foreach ($item in $Path) {
            if (Test-Path -LiteralPath $item) {
                (Get-Item -LiteralPath $item -Force).LastWriteTime = Get-Date
            }
            else {
                New-Item -Path $item -ItemType File -Force | Out-Null
            }
        }
    }
}

function nf {
    param([Parameter(Mandatory)][string]$Name)
    New-Item -ItemType File -Path . -Name $Name -Force | Out-Null
}

function mkcd {
    param([Parameter(Mandatory)][string]$Path)
    New-Item -Path $Path -ItemType Directory -Force | Out-Null
    Set-Location -LiteralPath $Path
}

function ff {
    param(
        [Parameter(Mandatory, Position = 0)][string]$Name,
        [Parameter(Position = 1)][string]$Path = '.'
    )
    Get-ChildItem -Path $Path -Recurse -Filter "*$Name*" -ErrorAction SilentlyContinue |
        Select-Object -ExpandProperty FullName
}

function pubip {
    (Get-UriContent -Uri 'https://ifconfig.me/ip').Trim()
}

function winutil {
    & ([ScriptBlock]::Create((Invoke-RestMethod -Uri 'https://christitus.com/win'))) @args
}

function winutildev {
    & ([ScriptBlock]::Create((Invoke-RestMethod -Uri 'https://christitus.com/windev'))) @args
}

function windev {
    $winutilRepo = Join-Path ([Environment]::GetFolderPath('UserProfile')) 'github\winutil'
    $compileScript = Join-Path $winutilRepo 'Compile.ps1'
    $compiledScript = Join-Path $winutilRepo 'winutil.ps1'

    if (-not (Test-Path -LiteralPath $compileScript -PathType Leaf)) {
        throw "WinUtil's Compile.ps1 was not found at '$compileScript'."
    }

    Push-Location -LiteralPath $winutilRepo
    try {
        & $compileScript
        if (-not $?) {
            throw 'WinUtil compilation failed.'
        }
    }
    finally {
        Pop-Location
    }

    if (-not (Test-Path -LiteralPath $compiledScript -PathType Leaf)) {
        throw "WinUtil compilation did not create '$compiledScript'."
    }

    $quotedCompiledScript = '"' + $compiledScript + '"'
    $shell = if (Test-Command pwsh) { 'pwsh.exe' } else { 'powershell.exe' }
    Start-Process -FilePath $shell -WorkingDirectory $winutilRepo -ArgumentList @(
        '-NoProfile',
        '-ExecutionPolicy', 'Bypass',
        '-File', $quotedCompiledScript
    )
}

function admin {
    $cwd = (Get-Location).ProviderPath
    $quotedCwd = '"' + $cwd + '"'
    $shell = if (Test-Command pwsh) { 'pwsh.exe' } else { 'powershell.exe' }
    $shellArgs = if ($args.Count -gt 0) { @('-NoExit', '-Command', ('"' + (($args -join ' ') -replace '"', '\"') + '"')) } else { @('-NoExit') }

    if (Test-Command wt) {
        Start-Process wt -Verb RunAs -ArgumentList (@('-d', $quotedCwd, $shell) + $shellArgs)
    }
    else {
        Start-Process $shell -Verb RunAs -WorkingDirectory $cwd -ArgumentList $shellArgs
    }
}
Set-Alias -Name su -Value admin -Scope Global -Force

function uptime {
    $boot = if (Get-Command Get-Uptime -ErrorAction SilentlyContinue) {
        Get-Uptime -Since
    }
    else {
        (Get-CimInstance -ClassName Win32_OperatingSystem).LastBootUpTime
    }

    (Get-Date) - $boot | Select-Object Days, Hours, Minutes, Seconds
}

function unzip {
    param(
        [Parameter(Mandatory, Position = 0)][string]$File,
        [Parameter(Position = 1)][Alias('d')][string]$Destination = (Get-Location).ProviderPath
    )

    if (-not (Test-Path -LiteralPath $File -PathType Leaf)) {
        Write-Error "File not found: $File"
        return
    }

    Expand-Archive -LiteralPath $File -DestinationPath $Destination -Force
}

function grep {
    <#
    .SYNOPSIS
        Linux-like grep supporting streaming pipeline input, file/directory search, -i, -c, -v, and -r.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)][string]$Pattern,
        [Parameter(Position = 1, ValueFromRemainingArguments)][string[]]$Path,
        [Parameter(ValueFromPipeline)][object]$InputObject,
        [Alias('i')][switch]$IgnoreCase,
        [Alias('c')][switch]$CaseSensitive,
        [Alias('v')][switch]$InvertMatch,
        [Alias('r')][switch]$Recurse
    )

    begin {
        $selectParams = @{
            Pattern       = $Pattern
            CaseSensitive = [bool]($CaseSensitive -and -not $IgnoreCase)
            NotMatch      = [bool]$InvertMatch
        }
        $hasPipeline = $MyInvocation.ExpectingInput
    }

    process {
        if ($PSBoundParameters.ContainsKey('InputObject') -and $null -ne $InputObject) {
            $hasPipeline = $true
            $InputObject | Select-String @selectParams
        }
    }

    end {
        if (-not $hasPipeline) {
            if ($Path -and $Path.Count -gt 0) {
                foreach ($item in $Path) {
                    if (Test-Path -LiteralPath $item -PathType Container) {
                        Get-ChildItem -LiteralPath $item -Recurse -File -ErrorAction SilentlyContinue | Select-String @selectParams
                    }
                    elseif ($Recurse) {
                        Get-ChildItem -Path $item -Recurse -File -ErrorAction SilentlyContinue | Select-String @selectParams
                    }
                    else {
                        Select-String -Path $item @selectParams
                    }
                }
            }
            else {
                Write-Error 'Usage: grep [-i] [-c] [-v] [-r] <pattern> [path...] or pipe input to grep'
            }
        }
    }
}

function df {
    Get-Volume @args
}

function sed {
    <#
    .SYNOPSIS
        Replaces text in a file or pipeline.
        Supports both:
          sed <File> <Find> <Replace>
          sed 's/find/replace/g' [File] (or via pipeline)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)][string]$First,
        [Parameter(Position = 1)][string]$Second,
        [Parameter(Position = 2)][string]$Third,
        [Parameter(ValueFromPipeline)][string]$InputObject
    )

    begin {
        $isExprMode = $First -match '^s(.)(.+?)\1(.*?)\1([gi]*)$'
        if ($isExprMode) {
            $findPattern = $Matches[2]
            $replaceWith = $Matches[3]
            $flags = $Matches[4]
            $targetFile = $Second
            $regexOptions = if ($flags -match 'i') { [Text.RegularExpressions.RegexOptions]::IgnoreCase } else { [Text.RegularExpressions.RegexOptions]::None }
            $replaceAll = $flags -match 'g'
        }
        $hasPipeline = $MyInvocation.ExpectingInput
    }

    process {
        if ($PSBoundParameters.ContainsKey('InputObject')) {
            $hasPipeline = $true
            if ($null -eq $InputObject) {
                return
            }
            if ($isExprMode) {
                $regex = [regex]::new($findPattern, $regexOptions)
                if ($replaceAll) {
                    $regex.Replace($InputObject, $replaceWith)
                }
                else {
                    $regex.Replace($InputObject, $replaceWith, 1)
                }
            }
            elseif (-not [string]::IsNullOrEmpty($First)) {
                $InputObject.Replace($First, [string]$Second)
            }
        }
    }

    end {
        if ($hasPipeline) {
            return
        }

        if ($isExprMode) {
            if (-not $targetFile -or -not (Test-Path -LiteralPath $targetFile -PathType Leaf)) {
                Write-Error "File not found: $targetFile"
                return
            }
            $raw = Get-Content -LiteralPath $targetFile -Raw
            if ($null -ne $raw) {
                $regex = [regex]::new($findPattern, $regexOptions)
                $updated = if ($replaceAll) { $regex.Replace($raw, $replaceWith) } else { $regex.Replace($raw, $replaceWith, 1) }
                Set-Content -LiteralPath $targetFile -Value $updated -NoNewline
            }
        }
        else {
            $file = $First
            $find = $Second
            $replace = [string]$Third
            if ([string]::IsNullOrEmpty($find)) {
                Write-Error "Usage: sed <File> <Find> <Replace> or sed 's/find/replace/g' [File]"
                return
            }
            if (-not (Test-Path -LiteralPath $file -PathType Leaf)) {
                Write-Error "File not found: $file"
                return
            }
            $raw = Get-Content -LiteralPath $file -Raw
            if ($null -ne $raw) {
                Set-Content -LiteralPath $file -Value $raw.Replace($find, $replace) -NoNewline
            }
        }
    }
}

function which {
    <#
    .SYNOPSIS
        Shows the full path or definition of commands, similar to Linux `which`.
        Use -a / -All to list all matching commands in PATH.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromRemainingArguments)][string[]]$Name,
        [Alias('a')][switch]$All
    )

    foreach ($cmdName in $Name) {
        $cmds = Get-Command -Name $cmdName -All:$All -ErrorAction SilentlyContinue
        if (-not $cmds) {
            Write-Error "$cmdName not found"
            continue
        }
        if (-not $All) {
            $cmds = $cmds | Select-Object -First 1
        }
        foreach ($cmd in $cmds) {
            switch ($cmd.CommandType) {
                'Alias'       { "$($cmd.Name): aliased to $($cmd.Definition)" }
                'Function'    { "$($cmd.Name): shell function" }
                'Filter'      { "$($cmd.Name): shell filter" }
                'Cmdlet'      { "$($cmd.Name): PowerShell cmdlet ($($cmd.ModuleName))" }
                default       { if ($cmd.Path) { $cmd.Path } else { $cmd.Source } }
            }
        }
    }
}

function export {
    <#
    .SYNOPSIS
        Linux-compatible `export` command.
        Usage:
          export                     -> Lists all environment variables (KEY=VALUE)
          export KEY=VALUE [K2=V2]   -> Sets one or more session environment variables
          export KEY VALUE           -> Sets KEY=VALUE
          export -p KEY=VALUE        -> Sets both session and persistent User environment variable
    #>
    [CmdletBinding()]
    param(
        [Alias('p')][switch]$Persist,
        [Parameter(ValueFromRemainingArguments)][string[]]$Arguments
    )

    if (-not $Arguments -or $Arguments.Count -eq 0) {
        Get-ChildItem Env: | Sort-Object Name | ForEach-Object { "$($_.Name)=$($_.Value)" }
        return
    }

    # Support legacy `export KEY VALUE` when 2 arguments are passed and neither contains '='
    if ($Arguments.Count -eq 2 -and $Arguments[0] -notmatch '=' -and $Arguments[1] -notmatch '=') {
        $key = $Arguments[0]
        $val = $Arguments[1]
        if ($Persist) {
            Set-PersistentEnv -Name $key -Value $val
        }
        else {
            Set-Item -Path "env:$key" -Value $val -Force
        }
        return
    }

    for ($i = 0; $i -lt $Arguments.Count; $i++) {
        $arg = $Arguments[$i]

        # Handle `export KEY = VALUE`
        if ($i + 2 -lt $Arguments.Count -and $Arguments[$i + 1] -eq '=') {
            $arg = "$arg=$($Arguments[$i + 2])"
            $i += 2
        }
        # Handle PowerShell tokenization of `export KEY="quoted value"` -> ('KEY=', 'quoted value')
        elseif ($arg.EndsWith('=') -and ($i + 1 -lt $Arguments.Count) -and ($Arguments[$i + 1] -notmatch '^[A-Za-z_][A-Za-z0-9_]*=')) {
            $arg = "$arg$($Arguments[$i + 1])"
            $i++
        }

        $eqIndex = $arg.IndexOf('=')
        if ($eqIndex -gt 0) {
            $key = $arg.Substring(0, $eqIndex).Trim()
            $val = $arg.Substring($eqIndex + 1)
            if ($val.Length -ge 2 -and (($val.StartsWith('"') -and $val.EndsWith('"')) -or ($val.StartsWith("'") -and $val.EndsWith("'")))) {
                $val = $val.Substring(1, $val.Length - 2)
            }
            if ($Persist) {
                Set-PersistentEnv -Name $key -Value $val
            }
            else {
                Set-Item -Path "env:$key" -Value $val -Force
            }
        }
        else {
            $existing = [Environment]::GetEnvironmentVariable($arg, 'Process')
            if ($null -ne $existing -and $Persist) {
                Set-PersistentEnv -Name $arg -Value $existing
            }
            elseif ($null -eq $existing) {
                Set-Item -Path "env:$arg" -Value '' -Force
            }
        }
    }
}

function unset {
    <#
    .SYNOPSIS
        Linux-compatible `unset` command to remove environment variables.
        Use -p / -Persist to also remove from the persistent Windows User environment.
    #>
    [CmdletBinding()]
    param(
        [Alias('p')][switch]$Persist,
        [Parameter(Mandatory, Position = 0, ValueFromRemainingArguments)][string[]]$Name
    )

    foreach ($varName in $Name) {
        Remove-Item -Path "env:$varName" -ErrorAction SilentlyContinue
        if ($Persist) {
            [Environment]::SetEnvironmentVariable($varName, $null, 'User')
        }
    }
}

function printenv {
    <#
    .SYNOPSIS
        Linux-compatible `printenv` command.
        Prints all environment variables (KEY=VALUE) when called with no arguments,
        or prints the value(s) of the specified environment variable(s).
    #>
    [CmdletBinding()]
    param(
        [Alias('0', 'null')][switch]$NullTerminated,
        [Parameter(Position = 0, ValueFromRemainingArguments)][string[]]$Name
    )

    $terminator = if ($NullTerminated) { "`0" } else { $null }

    if (-not $Name -or $Name.Count -eq 0) {
        $global:LASTEXITCODE = 0
        Get-ChildItem Env: | Sort-Object Name | ForEach-Object {
            $entry = "$($_.Name)=$($_.Value)"
            if ($NullTerminated) {
                Write-Host -NoNewline "$entry$terminator"
            }
            else {
                $entry
            }
        }
        return
    }

    $allFound = $true
    foreach ($varName in $Name) {
        $item = Get-Item -LiteralPath "Env:$varName" -ErrorAction SilentlyContinue
        if ($null -ne $item) {
            if ($NullTerminated) {
                Write-Host -NoNewline "$($item.Value)$terminator"
            }
            else {
                $item.Value
            }
        }
        else {
            $allFound = $false
        }
    }

    $global:LASTEXITCODE = if ($allFound) { 0 } else { 1 }
}

function pkill {
    param([Parameter(Mandatory, Position = 0)][string]$Name)
    $cleanName = $Name -replace '\.exe$', ''
    Get-Process -Name $cleanName -ErrorAction SilentlyContinue | Stop-Process -Force
}

function pgrep {
    param([Parameter(Mandatory, Position = 0)][string]$Name)
    $cleanName = $Name -replace '\.exe$', ''
    Get-Process -Name $cleanName -ErrorAction SilentlyContinue
}

function head {
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)][string]$Path,
        [Alias('Lines')][int]$n = 10,
        [Parameter(ValueFromPipeline)][object]$InputObject
    )

    begin {
        $pipeBuffer = [System.Collections.Generic.List[object]]::new()
        $hasPipeline = $MyInvocation.ExpectingInput
    }

    process {
        if ($PSBoundParameters.ContainsKey('InputObject')) {
            $hasPipeline = $true
            if ($pipeBuffer.Count -lt $n) {
                $pipeBuffer.Add($InputObject)
            }
        }
    }

    end {
        if ($hasPipeline) {
            $pipeBuffer
        }
        elseif ($Path) {
            Get-Content -Path $Path -TotalCount $n
        }
        else {
            Write-Error 'Usage: head <path> [-n 10] or pipe input to head'
        }
    }
}

function tail {
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)][string]$Path,
        [Alias('Lines')][int]$n = 10,
        [Alias('Follow')][switch]$f,
        [Parameter(ValueFromPipeline)][object]$InputObject
    )

    begin {
        $pipeQueue = [System.Collections.Generic.Queue[object]]::new()
        $hasPipeline = $MyInvocation.ExpectingInput
    }

    process {
        if ($PSBoundParameters.ContainsKey('InputObject')) {
            $hasPipeline = $true
            if ($n -gt 0) {
                if ($pipeQueue.Count -ge $n) {
                    $null = $pipeQueue.Dequeue()
                }
                $pipeQueue.Enqueue($InputObject)
            }
        }
    }

    end {
        if ($hasPipeline) {
            $pipeQueue.ToArray()
        }
        elseif ($Path) {
            Get-Content -Path $Path -Tail $n -Wait:$f
        }
        else {
            Write-Error 'Usage: tail <path> [-n 10] [-f] or pipe input to tail'
        }
    }
}

function trash {
    <#
    .SYNOPSIS
        Safely moves files or directories (including hidden files and wildcards) to the Windows Recycle Bin.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipeline, ValueFromPipelineByPropertyName, ValueFromRemainingArguments)]
        [Alias('FullName', 'LiteralPath')]
        [string[]]$Path
    )

    begin {
        if (-not ('Microsoft.VisualBasic.FileIO.FileSystem' -as [type])) {
            Add-Type -AssemblyName Microsoft.VisualBasic -ErrorAction SilentlyContinue
        }
    }

    process {
        foreach ($target in $Path) {
            $items = @()
            if ([System.Management.Automation.WildcardPattern]::ContainsWildcardCharacters($target)) {
                $items = @(Get-Item -Path $target -Force -ErrorAction SilentlyContinue)
            }
            elseif (Test-Path -LiteralPath $target) {
                $items = @(Get-Item -LiteralPath $target -Force -ErrorAction SilentlyContinue)
            }

            if ($items.Count -eq 0) {
                Write-Error "Item not found: $target"
                continue
            }

            foreach ($item in $items) {
                $fullPath = $item.FullName
                try {
                    if ($item.PSIsContainer) {
                        [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteDirectory(
                            $fullPath,
                            [Microsoft.VisualBasic.FileIO.UIOption]::OnlyErrorDialogs,
                            [Microsoft.VisualBasic.FileIO.RecycleOption]::SendToRecycleBin
                        )
                    }
                    else {
                        [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile(
                            $fullPath,
                            [Microsoft.VisualBasic.FileIO.UIOption]::OnlyErrorDialogs,
                            [Microsoft.VisualBasic.FileIO.RecycleOption]::SendToRecycleBin
                        )
                    }
                }
                catch {
                    Write-Error "Could not move '$fullPath' to Recycle Bin: $_"
                }
            }
        }
    }
}

function docs {
    Set-Location -LiteralPath ([Environment]::GetFolderPath('MyDocuments'))
}

function dtop {
    Set-Location -LiteralPath ([Environment]::GetFolderPath('Desktop'))
}

function k9 { param([Parameter(Mandatory)][string]$Name) pkill $Name }
function la { Get-ChildItem @args | Format-Table -AutoSize }
function ll { Get-ChildItem -Force @args | Format-Table -AutoSize }

function sysinfo { Get-ComputerInfo }

function flushdns {
    Clear-DnsClientCache
    Write-Host 'DNS has been flushed'
}

function cpy { Set-Clipboard ($args -join ' ') }
function pst { Get-Clipboard }

# ======================================================================
# Module 50: Profile Updater, Maintenance & Startup Orchestration
# ======================================================================

function Invoke-Profile {
    . $PROFILE.CurrentUserCurrentHost

    foreach ($fn in (Get-ChildItem -Path Function:\)) {
        if ($fn.Name -ne 'Invoke-Profile') {
            Set-Item -Path "Function:\global:$($fn.Name)" -Value $fn.ScriptBlock -Force
        }
    }
    foreach ($al in (Get-Alias)) {
        if ($al.Options -notmatch 'ReadOnly|Constant') {
            Set-Alias -Name $al.Name -Value $al.Definition -Scope Global -Force -ErrorAction SilentlyContinue
        }
    }
}

function Test-ProfileUpdateDue {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][int]$IntervalDays
    )

    if ($IntervalDays -lt 0 -or -not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return $true
    }

    $rawDate = [string](Get-Content -LiteralPath $Path -Raw -ErrorAction SilentlyContinue)
    if ([string]::IsNullOrWhiteSpace($rawDate)) {
        return $true
    }
    $rawDate = $rawDate.Trim()

    $lastRun = [datetime]::MinValue
    if (-not [datetime]::TryParseExact(
            $rawDate,
            'yyyy-MM-dd',
            [Globalization.CultureInfo]::InvariantCulture,
            [Globalization.DateTimeStyles]::None,
            [ref]$lastRun
        )) {
        return $true
    }

    return ((Get-Date).Date - $lastRun.Date).TotalDays -ge $IntervalDays
}

function Test-ProfileIsSymlink {
    $profilePath = $PROFILE.CurrentUserCurrentHost
    $profileItem = Get-Item -LiteralPath $profilePath -Force -ErrorAction SilentlyContinue
    if ($profileItem -and $profileItem.LinkType -eq 'SymbolicLink') {
        return $true
    }
    if ($global:IsRepoLinkedProfile -or $script:IsRepoLinkedProfile) {
        return $true
    }
    if ($profileItem -and (Select-String -LiteralPath $profilePath -Pattern 'IsRepoLinkedProfile' -Quiet -ErrorAction SilentlyContinue)) {
        return $true
    }
    return $false
}

function Update-Profile {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [switch]$Force,
        [switch]$PassThru
    )

    if ((Test-ProfileIsSymlink) -and -not $Force) {
        if ($isInteractiveShell) {
            Write-Host 'Profile is linked to local git repository; skipping remote overwrite.' -ForegroundColor Cyan
        }
        if ($PassThru) { return $true }
        return
    }

    $url = "$repo_root/powershell-profile/main/Microsoft.PowerShell_profile.ps1"
    $target = $PROFILE.CurrentUserCurrentHost
    $tempFile = Join-Path $env:TEMP "Microsoft.PowerShell_profile-$PID-$([guid]::NewGuid().ToString('N')).ps1"

    try {
        Save-UriToFile -Uri $url -OutFile $tempFile

        $targetExists = Test-Path -LiteralPath $target -PathType Leaf
        $oldHash = if ($targetExists) { (Get-FileHash -LiteralPath $target -ErrorAction Stop).Hash } else { $null }
        $newHash = (Get-FileHash -LiteralPath $tempFile -ErrorAction Stop).Hash

        if (-not $Force -and $targetExists -and $oldHash -eq $newHash) {
            if ($isInteractiveShell) {
                Write-Host 'Profile is up to date.' -ForegroundColor Green
            }
            if ($PassThru) { return $true }
            return
        }

        if ($PSCmdlet.ShouldProcess($target, 'Update PowerShell profile')) {
            $targetDir = Split-Path -Path $target -Parent
            if (-not (Test-Path -LiteralPath $targetDir -PathType Container)) {
                New-Item -Path $targetDir -ItemType Directory -Force -ErrorAction Stop | Out-Null
            }

            Copy-Item -LiteralPath $tempFile -Destination $target -Force -ErrorAction Stop
            Clear-InitCache
            Write-Host 'Profile has been updated. Restart your shell to use the new version.' -ForegroundColor Magenta
        }

        if ($PassThru) { return $true }
    }
    catch {
        Write-Warning "Unable to check for profile updates: $_"
        if ($PassThru) { return $false }
    }
    finally {
        Remove-Item -LiteralPath $tempFile -ErrorAction SilentlyContinue
    }
}

function Invoke-ScheduledProfileUpdate {
    if (-not $isInteractiveShell -or
        (Test-ProfileIsSymlink) -or
        -not (Test-ProfileUpdateDue -Path $timeFilePath -IntervalDays $updateInterval)) {
        return
    }

    # Defer network update check to OnIdle so it never blocks terminal startup
    Get-EventSubscriber -SourceIdentifier PowerShell.OnIdle -ErrorAction SilentlyContinue |
        Where-Object { $_.Action -and $_.Action.ToString() -match 'Update-Profile' } |
        Unregister-Event -ErrorAction SilentlyContinue
    Register-EngineEvent -SourceIdentifier PowerShell.OnIdle -MaxTriggerCount 1 -MessageData $timeFilePath -Action {
        $stampPath = $Event.MessageData
        if (Update-Profile -PassThru) {
            $timeDir = Split-Path -Path $stampPath -Parent
            if (-not (Test-Path -LiteralPath $timeDir -PathType Container)) {
                New-Item -Path $timeDir -ItemType Directory -Force | Out-Null
            }
            Get-Date -Format 'yyyy-MM-dd' | Set-Content -LiteralPath $stampPath
        }
    } | Out-Null
}

function Update-PowerShell {
    [CmdletBinding(SupportsShouldProcess)]
    param()

    if (-not (Test-Command winget)) {
        Write-Warning 'winget is required to update PowerShell automatically.'
        return
    }

    try {
        $release = Invoke-RestMethod -Uri 'https://api.github.com/repos/PowerShell/PowerShell/releases/latest' -ErrorAction Stop
        $currentVersion = [version](($PSVersionTable.PSVersion.ToString() -split '[-+]')[0])
        $latestVersion = [version]((($release.tag_name -replace '^v', '') -split '[-+]')[0])

        if ($currentVersion -ge $latestVersion) {
            Write-Host "PowerShell $currentVersion is up to date." -ForegroundColor Green
            return
        }

        if ($PSCmdlet.ShouldProcess("PowerShell $currentVersion", "Upgrade to $latestVersion")) {
            winget upgrade --id Microsoft.PowerShell --exact --accept-source-agreements --accept-package-agreements
            if ($LASTEXITCODE -ne 0) {
                Write-Error "winget failed to update PowerShell. Exit code: $LASTEXITCODE"
                return
            }
            Write-Host 'PowerShell has been updated. Restart your shell to use the new version.' -ForegroundColor Magenta
        }
    }
    catch {
        Write-Error "Failed to update PowerShell. Error: $_"
    }
}

function Clear-Cache {
    [CmdletBinding(SupportsShouldProcess)]
    param()

    $paths = @(
        "$env:SystemRoot\Prefetch\*",
        "$env:SystemRoot\Temp\*",
        "$env:TEMP\*",
        "$env:LOCALAPPDATA\Microsoft\Windows\INetCache\*"
    )

    foreach ($path in $paths) {
        if ($PSCmdlet.ShouldProcess($path, 'Remove cached files')) {
            Remove-Item -Path $path -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    if ($PSCmdlet.ShouldProcess((Get-ProfileCacheDir), 'Rebuild shell initialization cache')) {
        Clear-InitCache
    }
}

function Show-Help {
    @'
PowerShell Profile Help
=======================

Profile & Environment:
  Invoke-Profile            Reload this profile in the current session.
  Update-Profile            Check for profile updates.
  Update-PowerShell         Check for the latest PowerShell release and update with winget.
  Set-Theme <theme>         Download and set the Oh My Posh theme.
  Clear-InitCache           Rebuild cached startup scripts (oh-my-posh, zoxide, mise).
  Initialize-XdgEnvironment Provision persistent XDG environment variables and directories.

Linux / Shell Utilities:
  export [K=V ...] [-p]     List env vars or set session/persistent (-p) env vars.
  unset <name...> [-p]      Remove session/persistent (-p) env vars.
  printenv [name...] [-0]   Print all env vars or the values of specified vars.
  grep [-i|-c|-v|-r] <p>    Search files or streaming pipeline input.
  head / tail [-n 10] [-f]  Show first/last lines of a file or pipeline.
  sed <f> <a> <b>           Replace text in a file or via 's/find/replace/g'.
  which [-a] <name>         Show resolved command path or type.
  touch / nf <file...>      Create file(s) or update timestamps.
  mkcd <dir>                Create and enter a directory.
  la / ll [path]            List visible / all files in a directory.
  df                        Show volume information.
  unzip <file> [dest]       Extract a zip archive.
  pkill / k9 <name>         Kill processes by name (with or without .exe).
  pgrep <name>              Find processes by name.
  trash <path...>           Move file(s) or directories to the Recycle Bin.

System & Shortcuts:
  admin (su) [cmd]          Open an elevated terminal in the current directory.
  cpy <text> / pst          Copy to or paste from the clipboard.
  docs / dtop               Go to Documents / Desktop.
  ff <name> [path]          Find files recursively by name.
  flushdns                  Clear the DNS client cache.
  pubip                     Show public IP address.
  sysinfo                   Show system information.
  uptime                    Show system uptime.
  windev                    Compile and run the local WinUtil checkout.
  winutil / winutildev      Run the latest WinUtil release / prerelease script.
'@ | Write-Host
}

Initialize-PSReadLine
Register-CustomCompletion
. Initialize-PromptTool
Initialize-OptionalModule
Invoke-ScheduledProfileUpdate

if ($isInteractiveShell) {
    Write-Host "Use 'Show-Help' to display help" -ForegroundColor Yellow
}

### PowerShell Profile (Bundled from modules/*.ps1 via setprofile.ps1)
# Do not edit this bundled file directly; edit files in modules/ and commit (pre-commit hook bundles automatically)

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

# ======================================================================
# Module 10: XDG Base Directory Provisioning
# ======================================================================

# XDG Base Directory Specification defaults for user binaries, configs, data, cache, and state.
if (-not $env:XDG_BIN_HOME)    { $env:XDG_BIN_HOME    = "$HOME\.local\bin" }
if (-not $env:XDG_CONFIG_HOME) { $env:XDG_CONFIG_HOME = "$HOME\.config" }
if (-not $env:XDG_DATA_HOME)   { $env:XDG_DATA_HOME   = "$HOME\.local\share" }
if (-not $env:XDG_CACHE_HOME)  { $env:XDG_CACHE_HOME  = "$HOME\.cache" }
if (-not $env:XDG_STATE_HOME)  { $env:XDG_STATE_HOME  = "$HOME\.local\state" }

if ($env:PATH.IndexOf($env:XDG_BIN_HOME, [System.StringComparison]::OrdinalIgnoreCase) -lt 0) {
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
    if (-not $Force -and [System.IO.File]::Exists($sentinelFile)) {
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
        if (-not [System.IO.Directory]::Exists($dir)) {
            [System.IO.Directory]::CreateDirectory($dir) | Out-Null
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($env:XDG_BIN_HOME) -and [System.IO.Path]::IsPathRooted($env:XDG_BIN_HOME)) {
        if ($env:PATH.IndexOf($env:XDG_BIN_HOME, [System.StringComparison]::OrdinalIgnoreCase) -lt 0) {
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

    [System.IO.File]::WriteAllText($sentinelFile, (Get-Date -Format 'o'))
}

# Run XDG provisioning safely (fast-path sentinel check)
$script:xdgSentinel = Join-Path (Get-ProfileDir) '.xdg-initialized'
if (-not [System.IO.File]::Exists($script:xdgSentinel)) {
    try {
        Initialize-XdgEnvironment -ErrorAction Stop
    }
    catch {
        Write-Warning "XDG environment provisioning failed: $_"
    }
}

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

# ======================================================================
# Module 30: PSReadLine, Completions & Deferred Modules (PowerShell 7+)
# ======================================================================

function Initialize-PSReadLine {
    if (-not (IsInteractiveShell)) {
        return
    }

    try {
        Set-PSReadLineOption -EditMode Windows `
            -HistoryNoDuplicates `
            -HistorySearchCursorMovesToEnd `
            -BellStyle None `
            -MaximumHistoryCount 10000 `
            -Colors @{
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
            } `
            -AddToHistoryHandler {
                param([string]$line)
                $normalized = $line -replace '[-_ ]', ''
                $normalized -notmatch '(?i)(password|passwd|pwd|secret|token|apikey|connectionstring|credential)'
            }

        Set-PSReadLineOption -PredictionSource HistoryAndPlugin -PredictionViewStyle ListView
    }
    catch {
        Write-Verbose "Unable to set all PSReadLine options: $_"
    }

    $keyBindings = @(
        @{ Key = 'UpArrow'; Function = 'HistorySearchBackward' }
        @{ Key = 'DownArrow'; Function = 'HistorySearchForward' }
        @{ Key = 'Tab'; Function = 'MenuComplete' }
        @{ Chord = 'Ctrl+d'; Function = 'DeleteChar' }
        @{ Chord = 'Ctrl+w'; Function = 'BackwardDeleteWord' }
        @{ Chord = 'Alt+d'; Function = 'DeleteWord' }
        @{ Chord = 'Ctrl+LeftArrow'; Function = 'BackwardWord' }
        @{ Chord = 'Ctrl+RightArrow'; Function = 'ForwardWord' }
        @{ Chord = 'Ctrl+z'; Function = 'Undo' }
        @{ Chord = 'Ctrl+y'; Function = 'Redo' }
    )

    foreach ($kb in $keyBindings) {
        try {
            Set-PSReadLineKeyHandler @kb -ErrorAction SilentlyContinue
        }
        catch {
            Write-Verbose "Failed to bind PSReadLine key: $_"
        }
    }
}

function Register-CustomCompletion {
    if (-not (IsInteractiveShell)) {
        return
    }

    $gitCommands = @('status', 'add', 'commit', 'push', 'pull', 'clone', 'checkout')

    try {
        Register-ArgumentCompleter -Native -CommandName git -ScriptBlock {
            param($wordToComplete, $commandAst, $cursorPosition)
            $null = $commandAst
            $null = $cursorPosition
            $pattern = [System.Management.Automation.WildcardPattern]::Escape($wordToComplete) + '*'
            $gitCommands |
                Where-Object { $_ -like $pattern } |
                ForEach-Object { [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_) }
        }.GetNewClosure()
    }
    catch {
        Write-Verbose "Unable to register argument completers: $_"
    }
}

function Initialize-OptionalModule {
    if (-not (IsInteractiveShell)) {
        return
    }

    if ($global:__terminalIconsScheduled) {
        return
    }
    $global:__terminalIconsScheduled = $true

    # Defer heavy Terminal-Icons module import to OnIdle so prompt renders immediately
    Register-EngineEvent -SourceIdentifier PowerShell.OnIdle -MaxTriggerCount 1 -Action {
        try {
            Import-Module -Name Terminal-Icons -Global -ErrorAction Stop
        }
        catch {
            Write-Warning "Failed to load Terminal-Icons module: $_"
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
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(ValueFromRemainingArguments)][object[]]$Rest)
    if ($PSCmdlet.ShouldProcess('https://christitus.com/win', 'Download and run Chris Titus WinUtil script')) {
        $scriptText = Get-UriContent -Uri 'https://christitus.com/win'
        & ([ScriptBlock]::Create($scriptText)) @Rest
    }
}

function winutildev {
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(ValueFromRemainingArguments)][object[]]$Rest)
    if ($PSCmdlet.ShouldProcess('https://christitus.com/windev', 'Download and run Chris Titus WinUtil Dev script')) {
        $scriptText = Get-UriContent -Uri 'https://christitus.com/windev'
        & ([ScriptBlock]::Create($scriptText)) @Rest
    }
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
    $shellArgs = if ($args.Count -gt 0) {
        $command = $args -join ' '
        @('-NoExit', '-EncodedCommand', [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command)))
    }
    else {
        @('-NoExit')
    }

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
        [switch]$CaseSensitive,
        [Alias('c')][switch]$Count,
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
        $totalMatches = 0
    }

    process {
        if ($PSBoundParameters.ContainsKey('InputObject') -and $null -ne $InputObject) {
            $hasPipeline = $true
            if ($Count) {
                $totalMatches += @($InputObject | Select-String @selectParams).Count
            }
            else {
                $InputObject | Select-String @selectParams
            }
        }
    }

    end {
        if (-not $hasPipeline) {
            if ($Path -and $Path.Count -gt 0) {
                foreach ($item in $Path) {
                    if (Test-Path -LiteralPath $item -PathType Container) {
                        $childParams = @{ LiteralPath = $item; File = $true; ErrorAction = 'SilentlyContinue' }
                        if ($Recurse) { $childParams['Recurse'] = $true }
                        if ($Count) {
                            $totalMatches += @(Get-ChildItem @childParams | Select-String @selectParams).Count
                        }
                        else {
                            Get-ChildItem @childParams | Select-String @selectParams
                        }
                    }
                    elseif ($Recurse) {
                        if ($Count) {
                            $totalMatches += @(Get-ChildItem -Path $item -Recurse -File -ErrorAction SilentlyContinue | Select-String @selectParams).Count
                        }
                        else {
                            Get-ChildItem -Path $item -Recurse -File -ErrorAction SilentlyContinue | Select-String @selectParams
                        }
                    }
                    else {
                        if ($Count) {
                            $totalMatches += @(Select-String -Path $item @selectParams).Count
                        }
                        else {
                            Select-String -Path $item @selectParams
                        }
                    }
                }
            }
            else {
                Write-Error 'Usage: grep [-i] [-c] [-v] [-r] <pattern> [path...] or pipe input to grep'
                return
            }
        }
        if ($Count) {
            $totalMatches
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
        if (-not $isExprMode -and $First -cmatch '^s[^A-Za-z0-9]' -and -not (Test-Path -LiteralPath $First -PathType Leaf)) {
            Write-Error "Invalid sed expression syntax. Usage: sed 's/find/replace/g' [File]"
            $invalidExpr = $true
            return
        }
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
        if ($invalidExpr) { return }
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
        if ($invalidExpr -or $hasPipeline) {
            return
        }

        if ($isExprMode) {
            if (-not $targetFile -or -not (Test-Path -LiteralPath $targetFile -PathType Leaf)) {
                Write-Error "File not found: $targetFile"
                return
            }
            $resolvedTarget = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($targetFile)
            $raw = Get-Content -LiteralPath $resolvedTarget -Raw
            if ($null -ne $raw) {
                $regex = [regex]::new($findPattern, $regexOptions)
                $updated = if ($replaceAll) { $regex.Replace($raw, $replaceWith) } else { $regex.Replace($raw, $replaceWith, 1) }
                $tempFile = Join-Path $env:TEMP ("sed-$PID-$([guid]::NewGuid().ToString('N')).tmp")
                try {
                    Set-Content -LiteralPath $tempFile -Value $updated -NoNewline
                    Move-Item -LiteralPath $tempFile -Destination $resolvedTarget -Force
                }
                finally {
                    Remove-Item -LiteralPath $tempFile -Force -ErrorAction SilentlyContinue
                }
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
            $resolvedTarget = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($file)
            $raw = Get-Content -LiteralPath $resolvedTarget -Raw
            if ($null -ne $raw) {
                $updated = $raw.Replace($find, $replace)
                $tempFile = Join-Path $env:TEMP ("sed-$PID-$([guid]::NewGuid().ToString('N')).tmp")
                try {
                    Set-Content -LiteralPath $tempFile -Value $updated -NoNewline
                    Move-Item -LiteralPath $tempFile -Destination $resolvedTarget -Force
                }
                finally {
                    Remove-Item -LiteralPath $tempFile -Force -ErrorAction SilentlyContinue
                }
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
        if ($key -notmatch '^[A-Za-z_][A-Za-z0-9_]*$') {
            Write-Error "Invalid environment variable name: '$key'"
            return
        }
        if ($Persist) {
            Set-PersistentEnv -Name $key -Value $val
        }
        else {
            [Environment]::SetEnvironmentVariable($key, $val, 'Process')
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
            if ($key -notmatch '^[A-Za-z_][A-Za-z0-9_]*$') {
                Write-Error "Invalid environment variable name: '$key'"
                continue
            }
            if ($Persist) {
                Set-PersistentEnv -Name $key -Value $val
            }
            else {
                [Environment]::SetEnvironmentVariable($key, $val, 'Process')
            }
        }
        else {
            if ($arg -notmatch '^[A-Za-z_][A-Za-z0-9_]*$') {
                Write-Error "Invalid environment variable name: '$arg'"
                continue
            }
            $existing = [Environment]::GetEnvironmentVariable($arg, 'Process')
            if ($null -ne $existing -and $Persist) {
                Set-PersistentEnv -Name $arg -Value $existing
            }
            elseif ($null -eq $existing) {
                [Environment]::SetEnvironmentVariable($arg, '', 'Process')
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
        if ($varName -notmatch '^[A-Za-z_][A-Za-z0-9_]*$') {
            Write-Warning "Skipping invalid environment variable name: '$varName'"
            continue
        }
        [Environment]::SetEnvironmentVariable($varName, $null, 'Process')
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
                [Console]::Out.Write("$entry$terminator")
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
                [Console]::Out.Write("$($item.Value)$terminator")
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
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory, Position = 0)][string]$Name)
    $cleanName = $Name -replace '\.exe$', ''
    if ($cleanName -notmatch '^[A-Za-z0-9_.-]+$') {
        Write-Error "Invalid process name: '$Name'"
        return
    }
    $procs = @(Get-Process | Where-Object { $_.ProcessName -eq $cleanName })
    foreach ($proc in $procs) {
        if ($PSCmdlet.ShouldProcess("$($proc.ProcessName) (PID: $($proc.Id))", 'Stop process')) {
            $proc | Stop-Process -Force
        }
    }
}

function pgrep {
    param([Parameter(Mandatory, Position = 0)][string]$Name)
    $cleanName = $Name -replace '\.exe$', ''
    if ($cleanName -notmatch '^[A-Za-z0-9_.-]+$') {
        Write-Error "Invalid process name: '$Name'"
        return
    }
    Get-Process | Where-Object { $_.ProcessName -eq $cleanName }
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
    [CmdletBinding(SupportsShouldProcess)]
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
                if ($PSCmdlet.ShouldProcess($fullPath, 'Move to Recycle Bin')) {
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
}

function docs {
    Set-Location -LiteralPath ([Environment]::GetFolderPath('MyDocuments'))
}

function dtop {
    Set-Location -LiteralPath ([Environment]::GetFolderPath('Desktop'))
}

function k9 { param([Parameter(Mandatory)][string]$Name) pkill $Name }
function la { Get-ChildItem @args }
function ll { Get-ChildItem -Force @args }

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

function Update-Profile {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [switch]$Force,
        [switch]$PassThru
    )

    $url = 'https://raw.githubusercontent.com/luzede/powershell-profile/main/Microsoft.PowerShell_profile.ps1'
    $target = $PROFILE.CurrentUserCurrentHost
    $tempFile = Join-Path $env:TEMP "Microsoft.PowerShell_profile-$PID-$([guid]::NewGuid().ToString('N')).ps1"
    $updated = $false

    try {
        Save-UriToFile -Uri $url -OutFile $tempFile

        $parseErrors = $null
        $tokens = $null
        $null = [System.Management.Automation.Language.Parser]::ParseFile($tempFile, [ref]$tokens, [ref]$parseErrors)
        if ($parseErrors -and $parseErrors.Count -gt 0) {
            throw "Downloaded profile has syntax errors: $($parseErrors[0].Message)"
        }

        $targetExists = [System.IO.File]::Exists($target)
        $oldHash = if ($targetExists) { (Get-FileHash -LiteralPath $target -ErrorAction Stop).Hash } else { $null }
        $newHash = (Get-FileHash -LiteralPath $tempFile -ErrorAction Stop).Hash

        if (-not $Force -and $targetExists -and $oldHash -eq $newHash) {
            if (IsInteractiveShell) {
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

            if ($targetExists) {
                $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
                $backupPath = Join-Path $targetDir "oldprofile-$timestamp.ps1"
                Copy-Item -LiteralPath $target -Destination $backupPath -Force -ErrorAction Stop
            }

            Move-Item -LiteralPath $tempFile -Destination $target -Force -ErrorAction Stop
            $updated = $true
            Clear-InitCache
            Write-Host 'Profile has been updated. Restart your shell to use the new version.' -ForegroundColor Magenta
        }

        if ($PassThru) { return $updated }
    }
    catch {
        Write-Warning "Unable to check for profile updates: $_"
        if ($PassThru) { return $false }
    }
    finally {
        Remove-Item -LiteralPath $tempFile -ErrorAction SilentlyContinue
    }
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
                Write-Warning "winget failed to update PowerShell. Exit code: $LASTEXITCODE"
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

    $patterns = @(
        if ($env:SystemRoot) { Join-Path $env:SystemRoot 'Prefetch\*' }
        if ($env:SystemRoot) { Join-Path $env:SystemRoot 'Temp\*' }
        if ($env:TEMP)       { Join-Path $env:TEMP '*' }
        if ($env:LOCALAPPDATA) { Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\INetCache\*' }
    )

    foreach ($pattern in $patterns) {
        $items = @(Get-Item -Path $pattern -Force -ErrorAction SilentlyContinue)
        foreach ($item in $items) {
            if ($PSCmdlet.ShouldProcess($item.FullName, 'Remove cached file')) {
                Remove-Item -LiteralPath $item.FullName -Recurse -Force -ErrorAction SilentlyContinue
            }
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
  Update-Profile            Check for profile updates.
  Update-PowerShell         Check for the latest PowerShell release and update with winget.
  Set-Theme <theme>         Download and set the Oh My Posh theme.
  Use-CachedInit <n> <sb>   Cache and load a CLI tool initializer (e.g., mise, fnm).
  Clear-InitCache           Rebuild cached startup scripts.
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

function Initialize-CustomProfile {
    $customDir = Get-ProfileCustomDir
    if ([System.IO.Directory]::Exists($customDir)) {
        foreach ($customFile in (Get-ChildItem -LiteralPath $customDir -Filter '*.ps1' -File | Sort-Object Name)) {
            try {
                . $customFile.FullName
            }
            catch {
                Write-Warning "Error loading custom profile script '$($customFile.Name)': $_"
            }
        }
    }
}

Initialize-PSReadLine
Register-CustomCompletion
. Initialize-PromptTool
. Initialize-CustomProfile
Initialize-OptionalModule

if (IsInteractiveShell) {
    Write-Host "Use 'Show-Help' to display help" -ForegroundColor Yellow
}

### PowerShell Profile (Bundled from modules/*.ps1 via setprofile.ps1)
# Do not edit this bundled file directly; edit files in modules/ and commit (pre-commit hook bundles automatically)

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

$script:isInteractiveShell = Test-InteractiveShell

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
    . Initialize-PromptTool
    if (Get-Command -Name 'Initialize-CustomProfile' -ErrorAction SilentlyContinue) {
        . Initialize-CustomProfile
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
            if ($__fn.Name -notin @('Use-CachedInit', 'prompt') -and $__fn.ScriptBlock -and $__fn.ScriptBlock.File -eq $cacheFile) {
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
        $cachedTheme = if (Test-Path -LiteralPath $ompThemeMeta -PathType Leaf) {
            ([string](Get-Content -LiteralPath $ompThemeMeta -Raw -ErrorAction SilentlyContinue)).Trim()
        } else { $null }

        if (-not (Test-Path -LiteralPath $ompCache -PathType Leaf) -or $cachedTheme -ne $theme) {
            Update-InitCache -Tool 'oh-my-posh'
        }

        if (Test-Path -LiteralPath $ompCache -PathType Leaf) {
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
    if (-not (Test-Path -LiteralPath $zoxideCache -PathType Leaf)) {
        Update-InitCache -Tool 'zoxide'
    }
    if (Test-Path -LiteralPath $zoxideCache -PathType Leaf) {
        . $zoxideCache
    }
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

    # Defer heavy Terminal-Icons module import to OnIdle so prompt renders immediately
    Register-EngineEvent -SourceIdentifier PowerShell.OnIdle -MaxTriggerCount 1 -Action {
        try {
            Import-Module -Name Terminal-Icons -Global -ErrorAction Stop
        }
        catch {
            Write-Verbose "Terminal-Icons module is not installed: $_"
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

$repo_root = 'https://raw.githubusercontent.com/luzede'
$timeFilePath = Join-Path (Get-ProfileCacheDir) 'LastExecutionTime.txt'
$updateInterval = 7

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

function Update-Profile {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [switch]$Force,
        [switch]$PassThru
    )

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
    if (Test-Path -LiteralPath $customDir -PathType Container) {
        foreach ($customFile in (Get-ChildItem -LiteralPath $customDir -Filter '*.ps1' -File | Sort-Object Name)) {
            . $customFile.FullName
        }
    }
}

Initialize-PSReadLine
Register-CustomCompletion
. Initialize-PromptTool
. Initialize-CustomProfile
Initialize-OptionalModule
Invoke-ScheduledProfileUpdate

if ($isInteractiveShell) {
    Write-Host "Use 'Show-Help' to display help" -ForegroundColor Yellow
}

# ======================================================================
# Module 30: PSReadLine, Completions & Deferred Modules
# ======================================================================

function Set-PSReadLineOptionsCompat {
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)][hashtable]$Options)

    $safeOptions = $Options.Clone()
    $psrl = Get-Module -Name PSReadLine
    if (-not $psrl) {
        $psrl = Get-Module -Name PSReadLine -ListAvailable | Sort-Object Version -Descending | Select-Object -First 1
    }
    $psrlVersion = if ($psrl) { $psrl.Version } else { [version]'0.0.0' }

    if ($psrlVersion -lt [version]'2.0.0') {
        $safeOptions.Remove('PredictionSource')
        $safeOptions.Remove('Colors')
    }
    if ($psrlVersion -lt [version]'2.1.0') {
        $safeOptions.Remove('PredictionViewStyle')
    }

    if ($PSCmdlet.ShouldProcess('PSReadLine', 'Set PSReadLine options')) {
        try {
            Set-PSReadLineOption @safeOptions
        }
        catch {
            Write-Verbose "Unable to set all PSReadLine options: $_"
        }
    }
}

function Set-PredictionSource {
    [CmdletBinding(SupportsShouldProcess)]
    param()

    $psrl = Get-Module -Name PSReadLine
    if (-not $psrl) {
        $psrl = Get-Module -Name PSReadLine -ListAvailable | Sort-Object Version -Descending | Select-Object -First 1
    }
    $psrlVersion = if ($psrl) { $psrl.Version } else { [version]'0.0.0' }

    if ($PSCmdlet.ShouldProcess('PSReadLine', 'Set prediction source')) {
        if ($psrlVersion -ge [version]'2.1.0' -and $PSVersionTable.PSEdition -eq 'Core') {
            try {
                Set-PSReadLineOption -PredictionSource HistoryAndPlugin
            }
            catch {
                Write-Verbose "Unable to set PredictionSource to HistoryAndPlugin: $_"
            }
        }

        try {
            Set-PSReadLineOption -MaximumHistoryCount 10000
        }
        catch {
            Write-Verbose "Unable to set MaximumHistoryCount: $_"
        }
    }
}

function Initialize-PSReadLine {
    if (-not (IsInteractiveShell)) {
        return
    }

    $psrl = Get-Module -Name PSReadLine
    if (-not $psrl) {
        $psrl = Get-Module -Name PSReadLine -ListAvailable | Sort-Object Version -Descending | Select-Object -First 1
    }
    $psrlVersion = if ($psrl) { $psrl.Version } else { [version]'0.0.0' }

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

    $keyBindings = @(
        @{ Key = 'UpArrow'; Function = 'HistorySearchBackward' },
        @{ Key = 'DownArrow'; Function = 'HistorySearchForward' },
        @{ Key = 'Tab'; Function = 'MenuComplete' },
        @{ Chord = 'Ctrl+d'; Function = 'DeleteChar' },
        @{ Chord = 'Ctrl+w'; Function = 'BackwardDeleteWord' },
        @{ Chord = 'Alt+d'; Function = 'DeleteWord' },
        @{ Chord = 'Ctrl+LeftArrow'; Function = 'BackwardWord' },
        @{ Chord = 'Ctrl+RightArrow'; Function = 'ForwardWord' },
        @{ Chord = 'Ctrl+z'; Function = 'Undo' },
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

    if ($psrlVersion -ge [version]'2.0.0') {
        try {
            Set-PSReadLineOption -AddToHistoryHandler {
                param([string]$line)
                $normalized = $line -replace '[-_ ]', ''
                $normalized -notmatch '(?i)(password|passwd|pwd|secret|token|apikey|connectionstring|credential)'
            }
        }
        catch {
            Write-Verbose "Unable to set AddToHistoryHandler: $_"
        }
    }

    Set-PredictionSource
}

function Register-CustomCompletion {
    if (-not (IsInteractiveShell)) {
        return
    }

    $completionMap = @{
        git  = @('status', 'add', 'commit', 'push', 'pull', 'clone', 'checkout')
        npm  = @('install', 'start', 'run', 'test', 'build')
        deno = @('run', 'compile', 'bundle', 'test', 'lint', 'fmt', 'cache', 'info', 'doc', 'upgrade')
    }

    $nativeParams = if ($PSVersionTable.PSEdition -eq 'Core') { @{ Native = $true } } else { @{} }

    try {
        Register-ArgumentCompleter @nativeParams -CommandName git, npm, deno -ScriptBlock {
            param($wordToComplete, $commandAst, $cursorPosition)
            $null = $cursorPosition
            $completionWord = $wordToComplete
            $map = $completionMap
            $command = [System.IO.Path]::GetFileNameWithoutExtension($commandAst.CommandElements[0].Value)
            if ($map.ContainsKey($command)) {
                $pattern = [System.Management.Automation.WildcardPattern]::Escape($completionWord) + '*'
                $map[$command] |
                    Where-Object { $_ -like $pattern } |
                    ForEach-Object { [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_) }
            }
        }.GetNewClosure()

        Register-ArgumentCompleter @nativeParams -CommandName dotnet -ScriptBlock {
            param($wordToComplete, $commandAst, $cursorPosition)
            $null = $wordToComplete
            if (Get-Command -Name dotnet -ErrorAction SilentlyContinue) {
                dotnet complete --position $cursorPosition $commandAst.ToString() |
                    ForEach-Object { [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_) }
            }
        }
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


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

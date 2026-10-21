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
Set-Alias -Name su -Value admin -Force

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


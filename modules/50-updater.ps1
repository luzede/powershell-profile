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

        $targetExists = Test-Path -LiteralPath $target -PathType Leaf
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
    if (Test-Path -LiteralPath $customDir -PathType Container) {
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


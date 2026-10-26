[CmdletBinding()]
param(
    [string]$ExpectedProfileHash = $env:POWERSHELL_PROFILE_SHA256
)

$profileSourceUri = 'https://github.com/luzede/powershell-profile/raw/main/Microsoft.PowerShell_profile.ps1'
$themeSourceUri = 'https://raw.githubusercontent.com/JanDeDobbeleer/oh-my-posh/main/themes/cobalt2.omp.json'

function Enable-Tls12 {
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    }
    catch {
        Write-Verbose "Unable to enable TLS 1.2 explicitly: $_"
    }
}

Enable-Tls12

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]$identity
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
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

    $client = New-Object System.Net.WebClient
    try {
        $client.DownloadFile($Uri, $OutFile)
    }
    finally {
        $client.Dispose()
    }
}

function Get-ProfileDir {
    if ($PROFILE.CurrentUserCurrentHost) {
        return Split-Path -Path $PROFILE.CurrentUserCurrentHost -Parent
    }
    switch ($PSVersionTable.PSEdition) {
        'Core' { Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'PowerShell'; break }
        'Desktop' { Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'WindowsPowerShell'; break }
        default { throw "Unsupported PowerShell edition: $($PSVersionTable.PSEdition)" }
    }
}

function Test-InternetConnection {
    $response = $null
    try {
        $request = [System.Net.WebRequest]::Create('https://github.com')
        $request.Method = 'HEAD'
        $request.Timeout = 10000
        $response = $request.GetResponse()
        return $true
    }
    catch {
        Write-Warning 'Internet connection is required but GitHub is not reachable.'
        return $false
    }
    finally {
        if ($response) {
            $response.Close()
        }
    }
}

function Save-ProfileBackup {
    param([Parameter(Mandatory)][string]$ProfilePath)

    if (-not (Test-Path -Path $ProfilePath -PathType Leaf)) {
        return $null
    }

    $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $backupPath = Join-Path (Split-Path -Path $ProfilePath -Parent) "oldprofile-$timestamp.ps1"
    Copy-Item -Path $ProfilePath -Destination $backupPath -Force -ErrorAction Stop
    return $backupPath
}

function Install-Profile {
    param(
        [Parameter(Mandatory)][string]$SourceUri,
        [Parameter(Mandatory)][string]$ProfilePath,
        [string]$ExpectedHash
    )

    $profileDir = Split-Path -Path $ProfilePath -Parent
    if (-not (Test-Path -LiteralPath $profileDir)) {
        New-Item -Path $profileDir -ItemType Directory -Force -ErrorAction Stop | Out-Null
    }

    $tempProfile = Join-Path $env:TEMP "Microsoft.PowerShell_profile-$PID-$([guid]::NewGuid().ToString('N')).ps1"
    try {
        Save-UriToFile -Uri $SourceUri -OutFile $tempProfile
        $downloadedHash = (Get-FileHash -LiteralPath $tempProfile -Algorithm SHA256 -ErrorAction Stop).Hash
        if (-not [string]::IsNullOrWhiteSpace($ExpectedHash) -and $downloadedHash -ne $ExpectedHash.Trim()) {
            throw "Downloaded profile SHA-256 hash ($downloadedHash) does not match expected hash ($ExpectedHash)."
        }

        $backupPath = Save-ProfileBackup -ProfilePath $ProfilePath
        Copy-Item -LiteralPath $tempProfile -Destination $ProfilePath -Force -ErrorAction Stop

        Write-Host "PowerShell profile installed to [$ProfilePath]."
        if ($backupPath) {
            Write-Host "Previous profile backed up to [$backupPath]."
        }
        return $downloadedHash
    }
    finally {
        Remove-Item -LiteralPath $tempProfile -ErrorAction SilentlyContinue
    }
}

function Install-WinGetPackage {
    param(
        [Parameter(Mandatory)][string]$Id,
        [Parameter(Mandatory)][string]$Name,
        [string]$CommandName
    )

    if ($CommandName -and (Test-Command $CommandName)) {
        Write-Host "$Name is already installed."
        return $true
    }

    if (-not (Test-Command winget)) {
        Write-Warning "winget was not found. Skipping $Name."
        return $false
    }

    try {
        $null = winget install --id $Id --exact --source winget --accept-source-agreements --accept-package-agreements --silent
        # 0 = installed, -1978335189 (0x8A15002B) = already installed / no applicable update, -1978335135 (0x8A150061) = package already installed
        if ($LASTEXITCODE -notin @(0, -1978335189, -1978335135)) {
            Write-Warning "winget failed to install $Name. Exit code: $LASTEXITCODE"
            return $false
        }
        return $true
    }
    catch {
        Write-Warning "Failed to install $Name. Error: $_"
        return $false
    }
}

function Install-OhMyPoshTheme {
    param(
        [string]$ThemeName = 'cobalt2',
        [string]$ThemeUri = $themeSourceUri
    )

    $profileDir = Get-ProfileDir
    if (-not (Test-Path -LiteralPath $profileDir -PathType Container)) {
        New-Item -Path $profileDir -ItemType Directory -Force -ErrorAction Stop | Out-Null
    }

    # Create the Themes directory if it doesn't exist
    $themesDir = Join-Path $profileDir 'Themes'
    if (-not (Test-Path -LiteralPath $themesDir -PathType Container)) {
        New-Item -Path $themesDir -ItemType Directory -Force -ErrorAction Stop | Out-Null
    }
    $themePath = Join-Path $themesDir "$ThemeName.omp.json"
    $tempTheme = Join-Path $themesDir "$ThemeName-$PID-$([guid]::NewGuid().ToString('N')).omp.json.tmp"
    try {
        Save-UriToFile -Uri $ThemeUri -OutFile $tempTheme
        $null = Get-Content -LiteralPath $tempTheme -Raw | ConvertFrom-Json -ErrorAction Stop
        Move-Item -LiteralPath $tempTheme -Destination $themePath -Force -ErrorAction Stop
        $env:POSH_CONFIG = $themePath
        [Environment]::SetEnvironmentVariable('POSH_CONFIG', $themePath, 'User')
        Write-Host "Oh My Posh theme installed to [$themePath]."
        return $themePath
    }
    catch {
        Write-Warning "Failed to download or validate Oh My Posh theme. Error: $_"
        return $null
    }
    finally {
        Remove-Item -LiteralPath $tempTheme -Force -ErrorAction SilentlyContinue
    }
}

function Get-InstalledFontName {
    try {
        Add-Type -AssemblyName System.Drawing -ErrorAction Stop
        return (New-Object System.Drawing.Text.InstalledFontCollection).Families.Name
    }
    catch {
        Write-Warning "Unable to inspect installed fonts. Error: $_"
        return @()
    }
}

function Install-NerdFont {
    param(
        [string]$FontName = 'CascadiaCode',
        [string]$FontDisplayName = 'CaskaydiaCove NF',
        [string]$Version = '3.2.1'
    )

    if ((Get-InstalledFontName) -contains $FontDisplayName) {
        Write-Host "Font [$FontDisplayName] is already installed."
        return $true
    }

    $fontZipUrl = "https://github.com/ryanoasis/nerd-fonts/releases/download/v$Version/$FontName.zip"
    $zipFilePath = Join-Path $env:TEMP "$FontName.zip"
    $extractPath = Join-Path $env:TEMP $FontName

    try {
        Remove-Item -Path $extractPath -Recurse -Force -ErrorAction SilentlyContinue
        Save-UriToFile -Uri $fontZipUrl -OutFile $zipFilePath
        Expand-Archive -Path $zipFilePath -DestinationPath $extractPath -Force -ErrorAction Stop

        $fontsDir = [Environment]::GetFolderPath('Fonts')
        $fontShellFolder = (New-Object -ComObject Shell.Application).Namespace(0x14)
        $pendingFonts = [System.Collections.Generic.List[string]]::new()
        Get-ChildItem -Path $extractPath -Recurse -Filter '*.ttf' -ErrorAction Stop | ForEach-Object {
            $targetFontPath = Join-Path $fontsDir $_.Name
            if (-not (Test-Path -LiteralPath $targetFontPath)) {
                $fontShellFolder.CopyHere($_.FullName, 0x14)
                $pendingFonts.Add($targetFontPath)
            }
        }

        if ($pendingFonts.Count -gt 0) {
            $deadline = (Get-Date).AddSeconds(30)
            while ((Get-Date) -lt $deadline) {
                $remaining = @($pendingFonts | Where-Object { -not (Test-Path -LiteralPath $_) })
                if ($remaining.Count -eq 0) {
                    break
                }
                Start-Sleep -Milliseconds 200
            }
        }

        $installedFamilies = @(Get-InstalledFontName)
        if ($installedFamilies.Count -gt 0 -and $installedFamilies -notcontains $FontDisplayName) {
            Write-Warning "Font [$FontDisplayName] was not registered (installed families: $($installedFamilies.Count))."
            return $false
        }

        Write-Host "Font [$FontDisplayName] installed."
        return $true
    }
    catch {
        Write-Warning "Failed to install $FontDisplayName. Error: $_"
        return $false
    }
    finally {
        Remove-Item -LiteralPath $extractPath -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $zipFilePath -Force -ErrorAction SilentlyContinue
    }
}

function Install-TerminalIconsModule {
    try {
        Install-Module -Name Terminal-Icons -Repository PSGallery -Scope CurrentUser -Force -ErrorAction Stop
        Write-Host 'Terminal-Icons module installed.'
        return $true
    }
    catch {
        Write-Warning "Failed to install Terminal-Icons. Error: $_"
        return $false
    }
}

if (-not (Test-IsAdministrator)) {
    Write-Warning 'Please run this script as an Administrator.'
    $global:LASTEXITCODE = 1
    return
}

if (-not (Test-InternetConnection)) {
    $global:LASTEXITCODE = 1
    return
}

try {
    [Environment]::SetEnvironmentVariable('POWERSHELL_TELEMETRY_OPTOUT', '1', [EnvironmentVariableTarget]::Machine)
}
catch {
    Write-Warning "Unable to set PowerShell telemetry opt-out. Error: $_"
}

$profilePath = $PROFILE.CurrentUserCurrentHost
if ([string]::IsNullOrWhiteSpace($ExpectedProfileHash) -and $PSScriptRoot) {
    $localBundledProfile = Join-Path $PSScriptRoot 'Microsoft.PowerShell_profile.ps1'
    if (Test-Path -LiteralPath $localBundledProfile -PathType Leaf) {
        $ExpectedProfileHash = (Get-FileHash -LiteralPath $localBundledProfile -Algorithm SHA256 -ErrorAction Stop).Hash
    }
}

$failures = [System.Collections.Generic.List[string]]::new()
$installedProfileHash = Install-Profile -SourceUri $profileSourceUri -ProfilePath $profilePath -ExpectedHash $ExpectedProfileHash
if (-not $installedProfileHash) { $failures.Add('Profile installation') }
if (-not (Install-WinGetPackage -Id 'JanDeDobbeleer.OhMyPosh' -Name 'Oh My Posh' -CommandName 'oh-my-posh')) { $failures.Add('Oh My Posh') }
if (-not (Install-WinGetPackage -Id 'ajeetdsouza.zoxide' -Name 'zoxide' -CommandName 'zoxide')) { $failures.Add('zoxide') }
if (-not (Install-OhMyPoshTheme)) { $failures.Add('Oh My Posh theme') }
if (-not (Install-NerdFont)) { $failures.Add('Nerd Font') }
if (-not (Install-TerminalIconsModule)) { $failures.Add('Terminal-Icons module') }

if ($installedProfileHash -and (Test-Path -LiteralPath $profilePath -PathType Leaf)) {
    try {
        $currentProfileHash = (Get-FileHash -LiteralPath $profilePath -Algorithm SHA256 -ErrorAction Stop).Hash
        if ($currentProfileHash -ne $installedProfileHash) {
            throw "Profile integrity check failed before execution: expected $installedProfileHash, got $currentProfileHash."
        }

        $machinePath = [Environment]::GetEnvironmentVariable('Path', 'Machine')
        $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
        $env:PATH = (@($machinePath, $userPath) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) -join ';'

        . $profilePath
        Initialize-XdgEnvironment -Force
        Update-InitCache -Tool 'All'
        Write-Host 'Initialized persistent XDG environment variables and startup script cache.'
    }
    catch {
        Write-Warning "Profile post-setup initialization encountered an issue: $_"
    }
}

if ($failures.Count -gt 0) {
    Write-Warning "Setup completed with $($failures.Count) issue(s): $($failures -join ', ')."
    $global:LASTEXITCODE = 1
    return
}

Write-Host 'Setup completed successfully. Restart PowerShell to load the profile.'

#requires -RunAsAdministrator
#requires -Version 7.0

if (-not ($Env:WT_SESSION)) {
    Throw "Windows Terminal (wt) is required."
}

if (Test-Path $Profile) {
    Move-Item -Path $Profile -Destination ($Profile + ".bak") -Force
}
else {
    New-Item -Path $Profile -Force | Out-Null
}

# Disable pwsh telemetry for funnzies :)
[System.Environment]::SetEnvironmentVariable('POWERSHELL_TELEMETRY_OPTOUT', '1', 'Machine')

Invoke-WebRequest -Uri https://raw.githubusercontent.com/luzede/powershell-profile/main/Microsoft.PowerShell_profile.ps1 -OutFile $Profile

# Set the default theme for Oh My Posh to 'Cobalt2' if not already set
if (-not $env:OmpTheme) { $env:OmpTheme = 'cobalt2' }
[System.Environment]::SetEnvironmentVariable('OmpTheme', $env:OmpTheme, 'User')

# Create the Themes directory if it doesn't exist
$ThemesPath = "$Home\Documents\PowerShell\Themes"
if (-not (Test-Path $ThemesPath)) {
    New-Item -Path $ThemesPath -ItemType Directory -Force | Out-Null
}
# Download the specified Oh My Posh theme
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/JanDeDobbeleer/oh-my-posh/main/themes/${env:OmpTheme}.omp.json" -OutFile ${ThemesPath}\${env:OmpTheme}.omp.json

Install-Module -Name Terminal-Icons -Force -Repository PSGallery

winget install JanDeDobbeleer.OhMyPosh ajeetdsouza.zoxide DEVCOM.JetBrainsMonoNerdFont --source winget --silent
Write-Host "Successfully Installed PowerShell Profile." -ForegroundColor Green

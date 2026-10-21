[CmdletBinding()]
param(
    [switch]$BuildOnly
)

$ErrorActionPreference = 'Stop'

$modulesDir = Join-Path -Path $PSScriptRoot -ChildPath 'modules'
$bundledPath = Join-Path -Path $PSScriptRoot -ChildPath 'Microsoft.PowerShell_profile.ps1'
$hooksDir = Join-Path -Path $PSScriptRoot -ChildPath '.githooks'

if (-not (Test-Path -LiteralPath $modulesDir -PathType Container)) {
    throw "Modules directory not found: $modulesDir"
}

# 1. Bundle modules/*.ps1 into Microsoft.PowerShell_profile.ps1
$moduleFiles = @(Get-ChildItem -LiteralPath $modulesDir -Filter '*.ps1' -File | Sort-Object Name)
if ($moduleFiles.Count -eq 0) {
    throw "No module files (*.ps1) found in: $modulesDir"
}

$bundleBuilder = [System.Text.StringBuilder]::new()
[void]$bundleBuilder.AppendLine('### PowerShell Profile (Bundled from modules/*.ps1 via setprofile.ps1)')
[void]$bundleBuilder.AppendLine('# Do not edit this bundled file directly; edit files in modules/ and commit (pre-commit hook bundles automatically)')
[void]$bundleBuilder.AppendLine()

foreach ($file in $moduleFiles) {
    $content = Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8
    if (-not [string]::IsNullOrEmpty($content)) {
        [void]$bundleBuilder.AppendLine($content.TrimEnd())
        [void]$bundleBuilder.AppendLine()
    }
}

$bundleBuilder.ToString().TrimEnd() + "`n" | Set-Content -LiteralPath $bundledPath -Encoding UTF8 -NoNewline
Write-Host "Bundled $($moduleFiles.Count) modules into [$bundledPath]." -ForegroundColor Cyan

# 2. Ensure git pre-commit hook is configured
if ((Test-Path -LiteralPath (Join-Path $PSScriptRoot '.git')) -and (Test-Path -LiteralPath $hooksDir -PathType Container)) {
    if (Get-Command -Name 'git' -ErrorAction SilentlyContinue) {
        $currentHooksPath = git -C $PSScriptRoot config --get core.hooksPath 2>$null
        if ($currentHooksPath -ne '.githooks') {
            git -C $PSScriptRoot config core.hooksPath .githooks
            Write-Host 'Configured git core.hooksPath -> .githooks' -ForegroundColor DarkCyan
        }
    }
}

if ($BuildOnly) {
    return
}

# 3. Copy bundled profile to local $PROFILE.CurrentUserCurrentHost and refresh cache
$profilePath = $PROFILE.CurrentUserCurrentHost
$profileDir = Split-Path -Path $profilePath -Parent
if (-not (Test-Path -LiteralPath $profileDir -PathType Container)) {
    New-Item -Path $profileDir -ItemType Directory -Force | Out-Null
}

Copy-Item -LiteralPath $bundledPath -Destination $profilePath -Force
Write-Host "Installed bundled profile to [$profilePath]." -ForegroundColor Green

. $profilePath
Initialize-XdgEnvironment -Force
Clear-InitCache

### Chris Titus Tech's PowerShell profile

oh-my-posh init pwsh --config $Home\Documents\PowerShell\Themes\${env:OmpTheme}.omp.json | Invoke-Expression
zoxide init --cmd z powershell | Out-String | Invoke-Expression
Import-Module -Name Terminal-Icons

Write-Host "Use 'Show-Help' to list all available functions" -ForegroundColor Yellow

# History & Colors
Set-PSReadLineOption -PredictionViewStyle ListView -Colors @{
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

#KeyBinds
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

# Functions
function Update-Profile {
    Invoke-WebRequest -Uri https://raw.githubusercontent.com/luzede/powershell-profile/main/Microsoft.PowerShell_profile.ps1 -OutFile $Profile
    Write-Host "Updated PowerShell Profile" -ForegroundColor Green
}

function Set-Theme {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Theme
    )
    $env:OmpTheme = $Theme
    [System.Environment]::SetEnvironmentVariable('OmpTheme', $env:OmpTheme, 'User')
    Update-Theme
    
    # Refresh Oh My Posh in the current session
    $env:POSH_THEME = "$Home\Documents\PowerShell\Themes\${env:OmpTheme}.omp.json"
}

function Update-Theme {
    if ([string]::IsNullOrWhiteSpace($env:OmpTheme)) {
        Write-Warning "No Oh My Posh theme is currently set in the environment."
        return
    }
    Get-Theme $env:OmpTheme
}

function Get-Theme {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Theme
    )
    $Theme = $Theme.ToLower()
    $ThemeDir = "$Home\Documents\PowerShell\Themes"
    $ThemePath = "$ThemeDir\$Theme.omp.json"

    if (-not (Test-Path -Path $ThemeDir)) {
        New-Item -Path $ThemeDir -ItemType Directory -Force | Out-Null
    }

    try {
        $Uri = "https://raw.githubusercontent.com/JanDeDobbeleer/oh-my-posh/main/themes/$Theme.omp.json"
        Invoke-WebRequest -Uri $Uri -OutFile $ThemePath -ErrorAction Stop
        Write-Host "Downloaded Oh My Posh Theme: $Theme" -ForegroundColor Green
    }
    catch {
        Write-Error "Failed to download theme '$Theme'. Please verify the name or your internet connection."
    }
}

# File / Directory Utilities
function touch ($File) {
    if (Test-Path $File) {
        (Get-Item $File).LastWriteTime = Get-Date
    }
    else {
        New-Item $File -ItemType File | Out-Null
    }
}

function mkcd ($Path) {
    New-Item -Path $Path -ItemType Directory -Force | Out-Null
    Set-Location -Path $Path
}

function trash ($Path) {
    if (Test-Path $Path -PathType Container) {
        [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteDirectory($Path, 'OnlyErrorDialogs', 'SendToRecycleBin')
    }
    else {
        [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile($Path, 'OnlyErrorDialogs', 'SendToRecycleBin')
    }
}

function ff ($Name) {
    Get-ChildItem -Recurse -Filter $Name -File | Select-Object -ExpandProperty FullName
}

function head ($Path) {
    Get-Content $Path -Head 10
}

function sed ($File, $Find, $Replace) {
    (Get-Content $File).replace("$Find", $Replace) | Set-Content $file
}

function which ($Name) {
    (Get-Command $Name).Source
}

function pgrep ($Name) {
    Get-Process -Name $Name -ErrorAction SilentlyContinue
}

function pkill ($Name) {
    Get-Process -Name $Name -ErrorAction SilentlyContinue | Stop-Process -Force
}

function k9 ($Name) {
    pkill $Name
}

# System Utilities
function uptime {
    (Get-Date) - (Get-CimInstance -ClassName Win32_OperatingSystem).LastBootUpTime | Select-Object Days, Hours, Minutes, Seconds
}

function winutil {
    Invoke-RestMethod https://christitus.com/win | Invoke-Expression
}

function winutildev {
    Invoke-RestMethod https://christitus.com/windev | Invoke-Expression
}

# Bash Aliases
function export ($arg) {
    if ($arg -match '^(.*?)=(.*)$') {
        $name = $matches[1]
        $value = $matches[2]
        
        # Remove surrounding quotes if they exist
        if ($value -match "^['`"](.*)['`"]$") {
            $value = $matches[1]
        }
        
        Set-Item -Path "env:$name" -Value $value
    }
    else {
        Write-Warning "Usage: export VAR=value"
    }
}

# Git Shortcuts
function gs { git status }
function ga { git add . }
function gp { git push }
function gpush { git push }
function gpull { git pull }
function gcl { git clone $args }
function g { __zoxide_z github }

function gcom {
    git add .
    git commit -m "$args"
}

function lazyg {
    git add .
    git commit -m "$args"
    git push
}

function docs {
    Set-Location -Path ([Environment]::GetFolderPath("MyDocuments"))
}

# Listing / Viewing
function la {
    Get-ChildItem | Format-Table -AutoSize
}

function ll {
    Get-ChildItem -Force | Format-Table -AutoSize
}

# Aliases
Set-Alias -Name unzip -Value Expand-Archive
Set-Alias -Name grep -Value Select-String

# Help Function
function Show-Help {
    $title = $PSStyle.Foreground.BrightMagenta
    $section = $PSStyle.Foreground.BrightBlue
    $command = $PSStyle.Foreground.BrightGreen
    $desc = $PSStyle.Foreground.BrightWhite
    $accent = $PSStyle.Foreground.BrightYellow
    $dim = $PSStyle.Foreground.BrightBlack
    $reset = $PSStyle.Reset

    Write-Host @"
${title}󰘳 PowerShell Profile Help${reset}
${dim}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${reset}

${section}󰊢 Update${reset}
  ${command}Update-Profile${reset}  ${accent}→${reset} ${desc}Updates the profile from a remote repository.${reset}

${section}󰊢 Git Shortcuts${reset}
${dim}────────────────────────────────────────────────────${reset}
  ${command}g${reset}                  ${accent}→${reset} ${desc}Changes to the GitHub directory${reset}
  ${command}ga${reset}                 ${accent}→${reset} ${desc}git add .${reset}
  ${command}gcl <repo>${reset}         ${accent}→${reset} ${desc}git clone${reset}
  ${command}gcom <message>${reset}     ${accent}→${reset} ${desc}add + commit${reset}
  ${command}gp / gpush${reset}         ${accent}→${reset} ${desc}git push${reset}
  ${command}gpull${reset}              ${accent}→${reset} ${desc}git pull${reset}
  ${command}gs${reset}                 ${accent}→${reset} ${desc}git status${reset}
  ${command}lazyg <message>${reset}    ${accent}→${reset} ${desc}add + commit + push${reset}

${section}󰘴 System Shortcuts${reset}
${dim}────────────────────────────────────────────────────${reset}
  ${command}docs${reset}               ${accent}→${reset} ${desc}Documents folder${reset}
  ${command}ff <name>${reset}          ${accent}→${reset} ${desc}Search files${reset}
    ${command}grep <pattern> [path]${reset} ${accent}→${reset} ${desc}Search text${reset}
  ${command}head <file>${reset}        ${accent}→${reset} ${desc}First lines${reset}
    ${command}k9 <name>${reset}          ${accent}→${reset} ${desc}Kill process by name${reset}
  ${command}ll${reset}                 ${accent}→${reset} ${desc}List files${reset}
  ${command}mkcd <dir>${reset}         ${accent}→${reset} ${desc}Create + enter dir${reset}
    ${command}pgrep <name>${reset}       ${accent}→${reset} ${desc}Find process by name${reset}
    ${command}pkill <name>${reset}       ${accent}→${reset} ${desc}Stop process by name${reset}
  ${command}sed <file> <find> <replace>${reset} ${accent}→${reset} ${desc}Replace text${reset}
  ${command}touch <file>${reset}       ${accent}→${reset} ${desc}Create file${reset}
  ${command}unzip <file>${reset}       ${accent}→${reset} ${desc}Extract zip${reset}
  ${command}uptime${reset}             ${accent}→${reset} ${desc}System uptime${reset}
  ${command}which <name>${reset}       ${accent}→${reset} ${desc}Locate command${reset}
  ${command}winutil${reset}            ${accent}→${reset} ${desc}Run WinUtil${reset}
  ${command}winutildev${reset}         ${accent}→${reset} ${desc}Run WinUtil Dev${reset}

${dim}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${reset}
"@
}



# EXTEND WITH CUSTOM SETTINGS FOR EACH INSTALLED TOOL




# * COMMON ENVIRONMENT VARIABLES AND SETTINGS FOR INSTALLED TOOLS *
# **********************************************************************
# XDG is a set of standards for defining where user data files,
# configuration files, cache files, and other types of files should be stored.
$env:XDG_BIN_HOME = "$HOME\.local\bin"
$env:XDG_CONFIG_HOME = "$HOME\.config"
$env:XDG_DATA_HOME   = "$HOME\.local\share"
$env:XDG_CACHE_HOME  = "$HOME\.cache"
$env:XDG_STATE_HOME  = "$HOME\.local\state"

# Helper: only write to registry if the value differs
function Set-PersistentEnv([string]$Name, [string]$Value) {
    if ([Environment]::GetEnvironmentVariable($Name, 'User') -ne $Value) {
        [Environment]::SetEnvironmentVariable($Name, $Value, 'User')
    }
}

Set-PersistentEnv 'XDG_BIN_HOME' $env:XDG_BIN_HOME
Set-PersistentEnv 'XDG_CONFIG_HOME' $env:XDG_CONFIG_HOME
Set-PersistentEnv 'XDG_DATA_HOME' $env:XDG_DATA_HOME
Set-PersistentEnv 'XDG_CACHE_HOME' $env:XDG_CACHE_HOME
Set-PersistentEnv 'XDG_STATE_HOME' $env:XDG_STATE_HOME

# Ensure directories exist
New-Item -ItemType Directory -Force -Path $env:XDG_CONFIG_HOME, $env:XDG_DATA_HOME, $env:XDG_CACHE_HOME, $env:XDG_STATE_HOME | Out-Null

# **********************************************************************


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
(&mise activate pwsh) | Out-String | Invoke-Expression
# ===================================
########################################################################


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
# Set the history path for 'less' globally for this session
$lessConfigDir = "$env:XDG_CONFIG_HOME\less"
if (-not (Test-Path $lessConfigDir)) { New-Item -Path $lessConfigDir -ItemType Directory -Force | Out-Null }

$lessHistFile = Join-Path $lessConfigDir "_lesshst"
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


# Check and create the directory if it doesn't exist
New-Item -ItemType Directory -Path $gitConfigDir -Force | Out-Null

# Unlike directory creation, file creation overwrites existing files,
# so we first check if the file exists
if (-not (Test-Path $gitConfigFile)) {
    # If the file doesn't exist, create it
    New-Item -ItemType File -Path $gitConfigFile -Force | Out-Null
}
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



# ########################################################################
# # ===================================
# # Name: bun
# # Winget:
# # Link: https://bun.com/docs/installation#windows
# # Description:
# #   Where to install bun, I want it to follow XDG specification
# # ===================================
Set-PersistentEnv 'BUN_INSTALL' "$env:XDG_DATA_HOME\bun"
Set-PersistentEnv 'BUN_INSTALL_GLOBAL_DIR' "$env:XDG_DATA_HOME\bun\global"
Set-PersistentEnv 'BUN_INSTALL_BIN' "$env:XDG_DATA_HOME\bun\bin"
# # ===================================
# ########################################################################



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
# Ensure the directory exists, create it if it doesn't
New-Item -ItemType Directory -Path $awsConfigDir -Force | Out-Null

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
# Ensure the directory exists, create it if it doesn't
New-Item -ItemType Directory -Path $azureConfigDir -Force | Out-Null

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

# Ensure the directory exists, create it if it doesn't
New-Item -ItemType Directory -Path $rustupConfigDir -Force | Out-Null
New-Item -ItemType Directory -Path $cargoConfigDir -Force | Out-Null


Set-PersistentEnv 'RUSTUP_HOME' $rustupConfigDir
Set-PersistentEnv 'CARGO_HOME' $cargoConfigDir
# ===================================
########################################################################
# ======================================================================
# Module 10: XDG Base Directory & Tool Environment Provisioning
# ======================================================================

# * COMMON ENVIRONMENT VARIABLES AND SETTINGS FOR INSTALLED TOOLS *
# **********************************************************************
# XDG is a set of standards for defining where user data files,
# configuration files, cache files, and other types of files should be stored.
if (-not $env:XDG_BIN_HOME)    { $env:XDG_BIN_HOME    = "$HOME\.local\bin" }
if (-not $env:XDG_CONFIG_HOME) { $env:XDG_CONFIG_HOME = "$HOME\.config" }
if (-not $env:XDG_DATA_HOME)   { $env:XDG_DATA_HOME   = "$HOME\.local\share" }
if (-not $env:XDG_CACHE_HOME)  { $env:XDG_CACHE_HOME  = "$HOME\.cache" }
if (-not $env:XDG_STATE_HOME)  { $env:XDG_STATE_HOME  = "$HOME\.local\state" }

# Fast in-session defaults in case persistent User environment has not been inherited yet
if (-not $env:LESSHISTFILE)                { $env:LESSHISTFILE                = "$env:XDG_CONFIG_HOME\less\_lesshst" }
if (-not $env:BUN_INSTALL)                 { $env:BUN_INSTALL                 = "$env:XDG_DATA_HOME\bun" }
if (-not $env:BUN_INSTALL_GLOBAL_DIR)      { $env:BUN_INSTALL_GLOBAL_DIR      = "$env:XDG_DATA_HOME\bun\global" }
if (-not $env:BUN_INSTALL_BIN)             { $env:BUN_INSTALL_BIN             = "$env:XDG_DATA_HOME\bun\bin" }
if (-not $env:AWS_SHARED_CREDENTIALS_FILE) { $env:AWS_SHARED_CREDENTIALS_FILE = "$env:XDG_CONFIG_HOME\aws\credentials" }
if (-not $env:AWS_CONFIG_FILE)             { $env:AWS_CONFIG_FILE             = "$env:XDG_CONFIG_HOME\aws\config" }
if (-not $env:AZURE_CONFIG_DIR)            { $env:AZURE_CONFIG_DIR            = "$env:XDG_DATA_HOME\azure" }
if (-not $env:RUSTUP_HOME)                 { $env:RUSTUP_HOME                 = "$env:XDG_DATA_HOME\rustup" }
if (-not $env:CARGO_HOME)                  { $env:CARGO_HOME                  = "$env:XDG_DATA_HOME\cargo" }
if (-not $env:CLAUDE_CONFIG_DIR)           { $env:CLAUDE_CONFIG_DIR           = "$env:XDG_CONFIG_HOME\claude" }

function Initialize-XdgEnvironment {
    <#
    .SYNOPSIS
        One-time provisioning of persistent User environment variables and XDG directories.
        Run automatically on first setup or manually whenever tool paths need to be repaired.
    #>
    [CmdletBinding()]
    param([switch]$Force)

    $cacheDir = Get-ProfileCacheDir
    $sentinelFile = Join-Path $cacheDir '.xdg-initialized'
    if (-not $Force -and (Test-Path -LiteralPath $sentinelFile -PathType Leaf)) {
        return
    }

    Set-PersistentEnv 'XDG_BIN_HOME' $env:XDG_BIN_HOME
    Set-PersistentEnv 'XDG_CONFIG_HOME' $env:XDG_CONFIG_HOME
    Set-PersistentEnv 'XDG_DATA_HOME' $env:XDG_DATA_HOME
    Set-PersistentEnv 'XDG_CACHE_HOME' $env:XDG_CACHE_HOME
    Set-PersistentEnv 'XDG_STATE_HOME' $env:XDG_STATE_HOME

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
    $lessConfigDir = "$env:XDG_CONFIG_HOME\less"
    $lessHistFile = Join-Path $lessConfigDir '_lesshst'
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

    ########################################################################
    # ===================================
    # Name: bun
    # Winget:
    # Link: https://bun.com/docs/installation#windows
    # Description:
    #   Where to install bun, I want it to follow XDG specification
    # ===================================
    Set-PersistentEnv 'BUN_INSTALL' "$env:XDG_DATA_HOME\bun"
    Set-PersistentEnv 'BUN_INSTALL_GLOBAL_DIR' "$env:XDG_DATA_HOME\bun\global"
    Set-PersistentEnv 'BUN_INSTALL_BIN' "$env:XDG_DATA_HOME\bun\bin"
    # ===================================
    ########################################################################

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
    Set-PersistentEnv 'RUSTUP_HOME' $rustupConfigDir
    Set-PersistentEnv 'CARGO_HOME' $cargoConfigDir
    # ===================================
    ########################################################################

    ########################################################################
    # ===================================
    # Name: Claude Code
    # Winget: Anthropic.ClaudeCode
    # Link: https://claude.ai/code
    # Description:
    #   I don't like that Claude Code creates '~/.claude' folder
    #   in the user's folder, so I am changing the environment variable
    # ===================================
    $claudeConfigDir = "$env:XDG_CONFIG_HOME\claude"
    Set-PersistentEnv 'CLAUDE_CONFIG_DIR' $claudeConfigDir
    # ===================================
    ########################################################################

    $directories = @(
        $env:XDG_BIN_HOME,
        $env:XDG_CONFIG_HOME,
        $env:XDG_DATA_HOME,
        $env:XDG_CACHE_HOME,
        $env:XDG_STATE_HOME,
        $cacheDir,
        $lessConfigDir,
        $gitConfigDir,
        "$env:XDG_DATA_HOME\bun",
        "$env:XDG_DATA_HOME\bun\global",
        "$env:XDG_DATA_HOME\bun\bin",
        $awsConfigDir,
        $azureConfigDir,
        $rustupConfigDir,
        $cargoConfigDir,
        $claudeConfigDir
    )

    foreach ($dir in $directories) {
        if (-not (Test-Path -LiteralPath $dir -PathType Container)) {
            New-Item -ItemType Directory -Path $dir -Force -ErrorAction Stop | Out-Null
        }
    }

    if (-not (Test-Path -LiteralPath $gitConfigFile -PathType Leaf)) {
        New-Item -ItemType File -Path $gitConfigFile -Force -ErrorAction Stop | Out-Null
    }

    Get-Date -Format 'o' | Set-Content -LiteralPath $sentinelFile -Encoding UTF8 -ErrorAction Stop
}

# Only run one-time XDG provisioning if the sentinel file doesn't exist yet
if (-not (Test-Path -LiteralPath (Join-Path (Get-ProfileCacheDir) '.xdg-initialized') -PathType Leaf)) {
    Initialize-XdgEnvironment
}
# **********************************************************************


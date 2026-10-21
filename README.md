# Pretty PowerShell

A fast, modular PowerShell 7 profile for Windows Terminal with cached startup scripts, XDG Base Directory provisioning, PSReadLine enhancements, Linux-compatible utilities, Terminal-Icons, oh-my-posh, and zoxide.

## Architecture & Repository Layout

The profile is organized into modular components under [`modules/`](modules) and bundled into [`Microsoft.PowerShell_profile.ps1`](Microsoft.PowerShell_profile.ps1) via [`setprofile.ps1`](setprofile.ps1):

- [`modules/00-core.ps1`](modules/00-core.ps1) — Core helpers, TLS/HTTP utilities, cache/custom directory resolvers (`Get-ProfileCacheDir`, `Get-ProfileCustomDir`), and environment persistence helper.
- [`modules/10-xdg-env.ps1`](modules/10-xdg-env.ps1) — Fast in-session XDG Base Directory defaults (`XDG_BIN_HOME`, `XDG_CONFIG_HOME`, `XDG_DATA_HOME`, `XDG_CACHE_HOME`, `XDG_STATE_HOME`) and one-time persistent `User` environment & directory provisioning (`Initialize-XdgEnvironment`).
- [`modules/20-prompt-cache.ps1`](modules/20-prompt-cache.ps1) — Theme management (`Get-Theme`, `Set-Theme`), cached initialization for `oh-my-posh` and `zoxide`, and the generic `Use-CachedInit` helper (`Update-InitCache`, `Clear-InitCache`).
- [`modules/30-readline.ps1`](modules/30-readline.ps1) — `PSReadLine` colors, keybinds, predictions, sensitive history filtering, custom completions, and deferred `OnIdle` loading for `Terminal-Icons`.
- [`modules/40-linux-utils.ps1`](modules/40-linux-utils.ps1) — Linux/POSIX utilities (`export`, `unset`, `printenv`, `grep`, `sed`, `head`, `tail`, `which`, `touch`, `trash`, etc.) and system shortcuts (`admin`, `winutil`, `winutildev`, `windev`, etc.).
- [`modules/50-updater.ps1`](modules/50-updater.ps1) — Non-blocking `OnIdle` scheduled profile updates, `Update-PowerShell`, `Clear-Cache`, `Show-Help`, user `Custom/*.ps1` drop-in loading, and startup orchestration.

### Local Development & Pre-Commit Hook
A Git `pre-commit` hook in [`.githooks/pre-commit`](.githooks/pre-commit) automatically bundles `modules/*.ps1` into `Microsoft.PowerShell_profile.ps1` and stages it whenever you run `git commit`.

Run [`./setprofile.ps1`](setprofile.ps1) once after cloning to:
1. Configure `git config core.hooksPath .githooks` so commits automatically rebuild and stage `Microsoft.PowerShell_profile.ps1`.
2. Bundle `modules/*.ps1` into `Microsoft.PowerShell_profile.ps1` and copy it to `$PROFILE.CurrentUserCurrentHost`.
3. Provision XDG base directories and pre-build the startup cache.

## Remote Install

Run PowerShell as Administrator inside Windows Terminal:

```powershell
irm "https://raw.githubusercontent.com/luzede/powershell-profile/raw/main/setup.ps1" | iex
```

The installer:
- Backs up an existing profile with a timestamped `oldprofile-*.ps1` file.
- Installs the bundled `Microsoft.PowerShell_profile.ps1`.
- Installs Oh My Posh, zoxide, Terminal-Icons, and the CaskaydiaCove Nerd Font.
- Downloads the `cobalt2.omp.json` theme into your PowerShell `Themes` directory.
- Provisions persistent `User` XDG base environment variables, creates `Documents\PowerShell\Custom`, and pre-builds cached startup scripts (`oh-my-posh`, `zoxide`).

After installing, restart Windows Terminal and set your PowerShell font to `CaskaydiaCove NF`.

## User Customization (`Documents\PowerShell\Custom\*.ps1`)

All personal, machine-specific, or optional tool configurations live in **`Documents\PowerShell\Custom\*.ps1`** (open anytime with `explorer (Get-ProfileCustomDir)`).

Any `*.ps1` files in that directory are automatically dot-sourced in alphabetical order (`10-tools.ps1`, `20-aliases.ps1`, `30-work.ps1`, etc.) at startup and are never overwritten by `Update-Profile` or `setprofile.ps1`.

### 1. Cached CLI Tool Initializers (`Use-CachedInit`)
Use `Use-CachedInit` for any CLI tool that prints a PowerShell activation or completion script to stdout. It runs the command **once**, caches the output to `~/.cache/powershell/<name>-init.ps1` (with automatic `global:` function scoping and non-destructive `PATH` handling), and loads it instantly on subsequent launches:

```powershell
# Documents\PowerShell\Custom\10-tools.ps1

# mise (polyglot runtime manager)
if (Test-Command mise) {
    Use-CachedInit -Name 'mise' -Command { mise activate pwsh }
}

# fnm (Fast Node Manager)
if (Test-Command fnm) {
    Use-CachedInit -Name 'fnm' -Command { fnm env --use-on-cd --shell power-shell }
}

# GitHub CLI tab completions
if (Test-Command gh) {
    Use-CachedInit -Name 'gh' -Command { gh completion -s powershell }
}

# pay-respects
if (Test-Command pay-respects) {
    Use-CachedInit -Name 'pay-respects' -Command { pay-respects pwsh --alias }
}

# Carapace (multi-shell argument completer)
if (Test-Command carapace) {
    Use-CachedInit -Name 'carapace' -Command { carapace _carapace powershell }
}
```

Whenever you upgrade one of those CLI tools, run **`Clear-InitCache`** to rebuild all cached startup scripts.

### 2. Tool Environment Variables & XDG Overrides
You can persist environment variables once from the terminal using `export -p`:

```powershell
export -p BUN_INSTALL="$env:XDG_DATA_HOME\bun"
export -p CARGO_HOME="$env:XDG_DATA_HOME\cargo"
export -p RUSTUP_HOME="$env:XDG_DATA_HOME\rustup"
```

Or define them portably in `Documents\PowerShell\Custom\10-tools.ps1`:

```powershell
if (-not $env:LESSHISTFILE)      { $env:LESSHISTFILE      = "$env:XDG_CONFIG_HOME\less\_lesshst" }
if (-not $env:BUN_INSTALL)       { $env:BUN_INSTALL       = "$env:XDG_DATA_HOME\bun" }
if (-not $env:CARGO_HOME)        { $env:CARGO_HOME        = "$env:XDG_DATA_HOME\cargo" }
if (-not $env:RUSTUP_HOME)       { $env:RUSTUP_HOME       = "$env:XDG_DATA_HOME\rustup" }
if (-not $env:CLAUDE_CONFIG_DIR) { $env:CLAUDE_CONFIG_DIR = "$env:XDG_CONFIG_HOME\claude" }
```

### 3. Deferred PowerShell Modules (`PowerShell.OnIdle`)
To load heavy PowerShell modules (such as `posh-git` or `PSFzf`) without delaying prompt rendering, register them on `PowerShell.OnIdle`:

```powershell
# Documents\PowerShell\Custom\20-modules.ps1
if (IsInteractiveShell) {
    Register-EngineEvent -SourceIdentifier PowerShell.OnIdle -MaxTriggerCount 1 -Action {
        Import-Module posh-git -Global -ErrorAction SilentlyContinue
    } | Out-Null
}
```

## What's Included

- **PSReadLine**: Syntax colors, list-view suggestions, sensitive history filtering, and shell-friendly keybinds.
- **Linux / POSIX Utilities**:
  - `export` (`export KEY=VALUE`, `export A=1 B=2`, `export -p KEY=VALUE` for persistent env, `export` to list all), `unset` (`unset KEY`, `unset -p KEY`), & `printenv` (`printenv [KEY...] [-0]`).
  - `grep` (streaming pipeline and file search with `-i`, `-c`, `-v`, `-r`).
  - `head` & `tail` (supports both files and streaming pipeline input, plus `tail -f`).
  - `sed` (supports `sed <file> <find> <replace>` and `sed 's/find/replace/g' [file]`).
  - `which` (resolves command paths/types cleanly; supports `-a` for all matches).
  - `touch`, `nf`, `mkcd`, `trash`, `ff`, `la`, `ll`, `df`, `unzip`.
  - `pgrep`, `pkill`, `k9` (automatically handles `.exe` suffixes and wildcards).
- **System Helpers**: `admin` (`su`), `uptime`, `sysinfo`, `flushdns`, `pubip`, `cpy`, `pst`, `windev`, `winutil`, `winutildev`.

Run `Show-Help` in PowerShell to see the full command list.

## Support

If this profile helps you, star the repo, share it, or sponsor development:
https://github.com/sponsors/luzede
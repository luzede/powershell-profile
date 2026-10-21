# Pretty PowerShell

A fast, modular PowerShell 7 profile for Windows Terminal with cached startup scripts, XDG Base Directory provisioning, PSReadLine enhancements, Linux-compatible utilities, Terminal-Icons, oh-my-posh, zoxide, and mise.

## Architecture & Repository Layout

The profile is organized into modular components under [`modules/`](modules) and bundled into [`Microsoft.PowerShell_profile.ps1`](Microsoft.PowerShell_profile.ps1) via [`setprofile.ps1`](setprofile.ps1):

- [`modules/00-core.ps1`](modules/00-core.ps1) — Core helpers, TLS/HTTP utilities, and environment persistence helper.
- [`modules/10-xdg-env.ps1`](modules/10-xdg-env.ps1) — Fast in-session XDG defaults and one-time persistent `User` environment & directory provisioning (`Initialize-XdgEnvironment`).
- [`modules/20-prompt-cache.ps1`](modules/20-prompt-cache.ps1) — Theme management (`Get-Theme`, `Set-Theme`) and cached initialization script generator (`Update-InitCache`, `Clear-InitCache`) for `oh-my-posh`, `zoxide`, and `mise`.
- [`modules/30-readline.ps1`](modules/30-readline.ps1) — `PSReadLine` colors, keybinds, sensitive history filtering, custom completions, and deferred `OnIdle` loading for `Terminal-Icons`.
- [`modules/40-linux-utils.ps1`](modules/40-linux-utils.ps1) — Linux/POSIX utilities (`export`, `unset`, `printenv`, `grep`, `sed`, `head`, `tail`, `which`, `touch`, `trash`, etc.) and system shortcuts.
- [`modules/50-updater.ps1`](modules/50-updater.ps1) — Non-blocking `OnIdle` scheduled profile updates, `Update-PowerShell`, `Clear-Cache`, `Show-Help`, and startup orchestration.

### Local Development
Run [`./setprofile.ps1`](setprofile.ps1) to:
1. Bundle `modules/*.ps1` into `Microsoft.PowerShell_profile.ps1`.
2. Link your local `$PROFILE.CurrentUserCurrentHost` directly to `modules/*.ps1` so any edits in `modules/` take effect immediately on next terminal launch (and are protected from remote auto-update overwrites).
3. Provision XDG environment variables and pre-build the startup cache.

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
- Provisions persistent `User` XDG environment variables, creates tool directories once, and pre-builds cached startup scripts (`oh-my-posh`, `zoxide`, `mise`).

After installing, restart Windows Terminal and set your PowerShell font to `CaskaydiaCove NF`.

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
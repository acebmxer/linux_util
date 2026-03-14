# Linux System Setup & Utilities Installer

An interactive multi-select TUI script for managing system setup tasks and common utilities across all major Linux distributions.

## Requirements

- Bash 4.0+
- `sudo` access (do **not** run as root)
- An interactive terminal
- Internet connection for downloads
- Arch-based distros: `yay` or `paru` recommended for AUR packages

## Installation & Usage

```bash
git clone https://github.com/acebmxer/linux_util.git
cd linux_util
chmod +x linux_util.sh
./linux_util.sh
```

## CLI Flags

The script supports non-interactive use for scripting and automation:

| Flag | Description |
|------|-------------|
| `--help` | Show usage information |
| `--list` | List all utilities with current install status |
| `--dry-run` | Preview actions without making any changes |
| `--install <name>` | Install a utility by name |
| `--uninstall <name>` | Uninstall a utility by name |
| `--update <name>` | Update a utility by name |
| `--update-all` | Update every currently installed utility |
| `--check <name>` | Exit 0 if installed, 1 if not |

Utility names must match exactly as shown by `--list`. `--dry-run` can be combined with any flag.

```bash
./linux_util.sh --list
./linux_util.sh --check "Docker"
./linux_util.sh --install "Visual Studio Code"
./linux_util.sh --dry-run --update-all
```

## Interactive Menu

```
╔══════════════════════════════════════════════════════════════╗
║   Linux System Setup & Utilities - Select Programs/Tasks     ║
╚══════════════════════════════════════════════════════════════╝

Script commit: abc1234  |  Latest commit: abc1234

System Tasks:
  [ ] Full System Upgrade/Update     [ ] KDE Desktop Environment
  [ ] NVIDIA Drivers                 [ ] System Updates
  [ ] XEN Guest Utilities            [ ] Self-Update Script

────────────────────────────────────────────────────────────────

Utilities:
  [ ] Bitwarden Client               [ ] OpenSSH Server
  [ ] Brave Browser                  [x] Steam App
  [x] Devolutions RDM (installed)    [U] Syncthing (installed)
  [x] Docker (installed)             [ ] Termius SSH Client
  [ ] Dotfiles                       [ ] Timeshift
  [ ] Joplin Client                  [x] Visual Studio Code (installed)
  [ ] LibreOffice

────────────────────────────────────────────────────────────────
Actions: Install: 1 | Uninstall: 1 | Update: 1

↑/↓/←/→ navigate  SPACE select  U update installed  A select-all  D deselect-all  ENTER confirm  Q quit
Legend: [x] select  [U] update  [ ] none  (installed) = on system
```

### Menu Controls

| Key | Action |
|-----|--------|
| ↑ / ↓ | Move up/down within column |
| ← / → | Switch columns |
| `Space` | Toggle install/uninstall |
| `U` | Queue an installed item for update (`[U]`) |
| `A` | Select all |
| `D` | Deselect all |
| `Enter` | Confirm and proceed |
| `Q` | Quit without changes |

### Selection Logic

| Checkbox | Installed? | Action |
|----------|------------|--------|
| `[x]` | No | **Install** |
| `[x]` | Yes | **Uninstall** |
| `[U]` | Yes | **Update** |
| `[ ]` | Either | Skip |

## Available Options

### System Tasks

| Task | Description |
|------|-------------|
| **Full System Upgrade/Update** | Full system upgrade, essential tools, Landscape Client (Ubuntu), and package cache cleanup |
| **KDE Desktop Environment** | Installs KDE Plasma with SDDM |
| **NVIDIA Drivers** | Detects available drivers, lets you choose a version, installs 32-bit libs, nvtop, and NVIDIA Container Toolkit if Docker is present |
| **System Updates** | Package list refresh, full upgrade, autoremove, and cache clean |
| **XEN Guest Utilities** | Mounts XCP-NG ISO and runs the tools installer |
| **Self-Update Script** | `git pull --ff-only` the repo; exits and prompts a re-run if updated |

### Utilities

| Utility | Install Method |
|---------|----------------|
| **Bitwarden Client** | `.deb` / `.rpm` / AUR / snap / flatpak |
| **Brave Browser** | Native repo (all distros) / AUR |
| **Devolutions RDM** | Cloudsmith repo / AUR / flatpak / snap |
| **Docker** | Official Docker repos; adds user to `docker` group |
| **Dotfiles** | git clone + setup script (Debian/Ubuntu/Arch only) |
| **Joplin Client** | AppImage via official installer script |
| **LibreOffice** | Direct download (Debian) / native packages / flatpak |
| **OpenSSH Server** | Native packages, enabled as a service |
| **Steam App** | Native packages / RPM Fusion / flatpak |
| **Syncthing** | Native packages + user service |
| **Termius SSH Client** | `.deb` / AUR / snap / flatpak |
| **Timeshift** | Native packages |
| **Visual Studio Code** | Microsoft repo (all distros) / AUR |

## Supported Distributions

| Family | Distributions | Package Manager |
|--------|--------------|-----------------|
| Debian/Ubuntu | Ubuntu, Debian, Linux Mint, Pop!\_OS, elementary OS, Zorin, Kali, KDE neon | apt |
| Fedora | Fedora | dnf |
| RHEL | RHEL, CentOS, Rocky Linux, AlmaLinux, Oracle Linux | dnf / yum |
| Arch | Arch Linux, Manjaro, EndeavourOS, Garuda, Artix | pacman + AUR |
| openSUSE | openSUSE Leap, Tumbleweed, SLES | zypper |

Unrecognised distributions are matched via `ID_LIKE` in `/etc/os-release`, then by auto-detecting the available package manager.

## Logging

Every run creates timestamped log files in `logs/`:

- `logs/success_YYYYMMDD_HHMMSS.log` — successful operations
- `logs/error_YYYYMMDD_HHMMSS.log` — errors and warnings (only created if needed)
- `logs/success_latest.log` / `logs/error_latest.log` — symlinks to the most recent logs

Use the included `manage_logs.sh` for common log operations:

```bash
chmod +x manage_logs.sh
./manage_logs.sh list             # list all log files
./manage_logs.sh view latest      # view latest logs
./manage_logs.sh search "Docker"  # search logs
./manage_logs.sh stats            # show statistics
./manage_logs.sh clean 30         # remove logs older than 30 days
./manage_logs.sh compress         # compress old logs
```

## Adding New Utilities

Insert a registration block and implementation functions in the alphabetically correct position in the `UTILITY DEFINITIONS` section. If adding a **System Task**, increment `SYSTEM_TASK_COUNT`.

```bash
UTILITIES+=("My Utility")
INSTALL_FUNCS["My Utility"]="install_my_utility"
CHECK_FUNCS["My Utility"]="check_my_utility"
UNINSTALL_FUNCS["My Utility"]="uninstall_my_utility"
UPDATE_FUNCS["My Utility"]="update_my_utility"

check_my_utility()     { command -v my-utility &>/dev/null; }
install_my_utility()   { pkg_install my-utility; }
uninstall_my_utility() { pkg_remove my-utility; }
update_my_utility()    { pkg_upgrade my-utility; }
```

### Key Helper Functions

| Function | Description |
|----------|-------------|
| `pkg_install <pkg>` | Install a package |
| `pkg_remove <pkg>` | Remove a package |
| `pkg_upgrade <pkg>` | Upgrade a package |
| `pkg_check_installed <pkg>` | Returns 0 if installed |
| `pkg_install_local <file>` | Install from a local `.deb`/`.rpm` |
| `pkg_refresh` | Refresh package lists |
| `pkg_full_upgrade` | Full system upgrade |
| `pkg_autoremove` | Remove orphaned packages |
| `pkg_clean` | Clean package cache |
| `has_snap` / `has_flatpak` / `has_aur_helper` | Availability checks |
| `aur_install <pkg>` | Install from AUR |
| `ensure_tools` | Ensure curl/wget/gpg are present |
| `check_internet` | Connectivity check (warns, does not abort) |
| `download_file <url> <dest> [retries]` | Retry-aware downloader |

Use `$DISTRO_FAMILY` (`debian`, `fedora`, `rhel`, `arch`, `suse`) for distro-specific logic.

## Troubleshooting

**Script won't run** — ensure it is executable (`chmod +x linux_util.sh`) and you are not running as root.

**Package installation fails** — verify internet access and that repositories are reachable. Steam on Fedora requires RPM Fusion; the script offers to enable it automatically.

**AUR packages on Arch** — install `yay` or `paru` first. The script can fall back to building from AUR directly, but an AUR helper is recommended.

**No colours / piped output** — set the `NO_COLOR` environment variable or pipe output to a file; ANSI colours are automatically disabled in non-interactive terminals.

## License

MIT License

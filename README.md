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
| `--help`, `-h` | Show usage information |
| `--version` | Show script version (git commit) |
| `--list` | List all utilities with current install status |
| `--dry-run` | Preview actions without making any changes |
| `--verbose` | Enable verbose output |
| `--debug` | Enable debug output |
| `--install <name>` | Install a utility by name |
| `--uninstall <name>` | Uninstall a utility by name |
| `--update <name>` | Update a utility by name |
| `--update-all` | Update every currently installed utility |
| `--check <name>` | Exit 0 if installed, 1 if not |
| `--no-color` | Disable colored output |
| `--setup-logrotate` | Install logrotate config for linux\_util logs |

Utility names are matched case-insensitively and support partial matches. `--dry-run` can be combined with any flag.

```bash
./linux_util.sh --list
./linux_util.sh --check "Docker"
./linux_util.sh --install "Visual Studio Code"
./linux_util.sh --dry-run --update-all
```

## Interactive Menu

```
╔══════════════════════════════════════════════════════════════════════╗
║        Linux System Setup & Utilities - Select Programs/Tasks        ║
╚══════════════════════════════════════════════════════════════════════╝

  Script commit: abc1234  |  Latest commit: def5678
                    Script out of date, please update.
              Detected System: Ubuntu   Version: 24.04.4
  Last Timeshift Snapshot: 2026-03-22_12-30-16 [0] - linux_util: ...

System Tasks:
  [ ] Full System Upgrade/Update       [ ] XEN Guest Utilities (v7.30.0)
  [ ] System Updates                   [ ] Local MOTD
  [ ] KDE Desktop                      [ ] Create Snapshot
  [ ] NVIDIA Drivers                   [ ] Restore Snapshot

────────────────────────────────────────────────────────────────────────

Utilities:
  [ ] Bitwarden Client                 [ ] PIA VPN
  [ ] Brave Browser                    [ ] QBittorrent
  [ ] Devolutions RDM                  [ ] Steam App
  [ ] Docker                           [ ] Syncthing
  [ ] Dotfiles                         [ ] Termius SSH Client
  [ ] Joplin Client                    [ ] Timeshift (v24.01.1)
  [ ] LibreOffice                      [ ] Visual Studio Code
  [ ] OpenSSH Server (v9.6p1)

────────────────────────────────────────────────────────────────────────
Actions: Install: 0 | Uninstall: 0 | Update: 0

↑↓←→ move  SPACE select  U update  A all  D none  ENTER confirm  Q quit

Legend: [✓] select  [U] update  [ ] none  (installed) = on system
[✓] on installed = uninstall; [✓] on missing = install; [U] on installed = update.
```

### Menu Controls

| Key | Action |
|-----|--------|
| ↑ / ↓ / ← / → | Move between items |
| `Space` | Toggle select |
| `U` | Queue an installed item for update (`[U]`) |
| `A` | Select all |
| `D` | Deselect none (clear all) |
| `Enter` | Confirm and proceed |
| `Q` | Quit without changes |

### Selection Logic

| Checkbox | Installed? | Action |
|----------|------------|--------|
| `[✓]` | No | **Install** |
| `[✓]` | Yes | **Uninstall** |
| `[U]` | Yes | **Update** |
| `[ ]` | Either | Skip |

## Available Options

### System Tasks

| Task | Description |
|------|-------------|
| **Full System Upgrade/Update** | Full system upgrade, essential tools, Landscape Client (Ubuntu), and package cache cleanup |
| **System Updates** | Package list refresh, full upgrade, autoremove, and cache clean |
| **KDE Desktop** | Installs KDE Plasma with SDDM |
| **NVIDIA Drivers** | Detects available drivers, lets you choose a version, installs 32-bit libs, nvtop, and NVIDIA Container Toolkit if Docker is present |
| **XEN Guest Utilities** | Mounts XCP-NG ISO and runs the tools installer |
| **Local MOTD** | Installs Landscape Client and configures local MOTD (Ubuntu/Kubuntu/Neon only) |
| **Create Snapshot** | Creates a Timeshift or Snapper snapshot with a user-provided description |
| **Restore Snapshot** | Lists available snapshots, creates a safety snapshot ("before restore"), then restores the selected snapshot |

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
| **PIA VPN** | Official repos (Debian/Fedora) / AUR (Arch) / Flatpak (openSUSE) |
| **QBittorrent** | Native packages / flatpak (openSUSE) |
| **Steam App** | Native packages / RPM Fusion / flatpak |
| **Syncthing** | Native packages + user service |
| **Termius SSH Client** | `.deb` / AUR / snap / flatpak |
| **Timeshift** | Native packages |
| **Visual Studio Code** | Microsoft repo (all distros) / AUR |

## Project Structure

The script has been modularized for easier maintenance and navigation:

```
linux_util/
├── linux_util.sh          Main orchestrator, CLI parsing, initialization
├── lib/
│   ├── config.sh          Configuration file parsing, verbose/debug helpers
│   ├── logging.sh         Logging, cleanup, performance metrics
│   ├── pkg_manager.sh     Package manager abstraction, distro detection
│   ├── aur.sh             Arch User Repository functions
│   ├── system.sh          Pre-flight checks, logrotate, system helpers
│   ├── snapshot.sh        Snapshot integration — Timeshift and Snapper
│   ├── utilities.sh       Utility registry, name resolution, dependency resolution
│   ├── menu.sh            TUI menu with keyboard navigation
│   ├── installers.sh      Loader + registration for all utilities/system tasks
│   └── installers/        Per-utility installer scripts (one file per utility)
│       ├── bitwarden.sh
│       ├── brave.sh
│       ├── docker.sh
│       ├── ...            (22 files total — one per utility/system task)
│       └── xen_guest_utilities.sh
├── logs/                  Timestamped execution logs
├── manage_logs.sh         Log management utility
└── README.md              This file
```

### Module Responsibilities

| Module | Purpose | Edit When... |
|--------|---------|--------------|
| **linux_util.sh** | Main script, CLI argument parsing, initialization | Modifying menu structure, argument parsing, or main flow |
| **lib/logging.sh** | Logging functions, error handling, cleanup | Changing log format or adding new log functions |
| **lib/pkg_manager.sh** | Package manager abstraction, distro detection | Adding support for new distros or package managers |
| **lib/aur.sh** | AUR/pacman-specific functions | Modifying AUR installation logic |
| **lib/config.sh** | Configuration file parsing, verbose/debug output helpers | Changing default settings or adding new config options |
| **lib/system.sh** | Pre-flight checks, logrotate setup, system helpers | Adding pre-flight checks or system helper functions |
| **lib/menu.sh** | TUI rendering, keyboard navigation, 2-column layout | Changing menu appearance or navigation behavior |
| **lib/snapshot.sh** | Automatic snapshots via Timeshift or Snapper | Adding snapshot backends or changing snapshot behavior |
| **lib/utilities.sh** | Utility registry, name resolution, dependency resolution, health checks | Modifying how utilities are registered or checked |
| **lib/installers.sh** | Loader that sources `lib/installers/*.sh` and registers all utilities | **Adding a new registration line for a new utility** |
| **lib/installers/\*.sh** | Per-utility install/uninstall/update/check functions (one file each) | **Adding or modifying a specific utility's installer** |

## Supported Distributions

| Family | Distributions | Package Manager |
|--------|--------------|-----------------|
| Debian/Ubuntu | Ubuntu, Debian, Linux Mint, Pop!\_OS, elementary OS, Zorin, Kali, KDE neon | apt |
| Fedora | Fedora | dnf |
| RHEL | RHEL, CentOS, Rocky Linux, AlmaLinux, Oracle Linux | dnf / yum |
| Arch | Arch Linux, Manjaro, EndeavourOS, Garuda, Artix | pacman + AUR |
| openSUSE | openSUSE Leap, Tumbleweed, SLES | zypper |

Unrecognised distributions are matched via `ID_LIKE` in `/etc/os-release`, then by auto-detecting the available package manager.

## Automatic Snapshots

The script automatically creates a system snapshot before every install, uninstall, or update operation, providing an easy rollback point if anything goes wrong.

### Supported Snapshot Tools

| Tool | Distros | Notes |
|------|---------|-------|
| **Timeshift** | All supported distros | Used whenever `timeshift` is installed |
| **Snapper** | Arch-based (CachyOS, Manjaro, etc.) | Used as fallback when Timeshift is not installed and Snapper has a root config |

- Auto-detects which snapshot tool is available
- On Arch-based systems with Snapper (e.g. CachyOS ships Snapper by default), snapshots work out of the box — no need to install Timeshift
- Timeshift auto-detects and configures the backup device on first use
- Each snapshot is tagged with a description of the operation (e.g., `linux_util: Install Docker`)
- **Create Snapshot** and **Restore Snapshot** are available as System Tasks in the menu
- Restore always takes a safety snapshot before proceeding
- Non-blocking — if snapshot creation fails, the operation continues normally

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
./manage_logs.sh tail success     # follow a log in real time
./manage_logs.sh search "Docker"  # search logs
./manage_logs.sh stats            # show statistics
./manage_logs.sh clean 30         # remove logs older than 30 days
./manage_logs.sh compress         # compress old logs
```

## Adding New Utilities

Each utility lives in its own file under `lib/installers/`. The file is sourced automatically — no loader changes needed.

### Steps to Add a New Utility

1. **Create `lib/installers/my_utility.sh`** with the required functions:
   ```bash
   #!/bin/bash
   # My Utility installer functions

   check_my_utility() {
       command -v my-utility &>/dev/null
   }

   install_my_utility() {
       pkg_install my-utility
   }

   uninstall_my_utility() {
       pkg_remove my-utility
   }

   update_my_utility() {
       pkg_upgrade my-utility
   }

   get_version_my_utility() {    # optional
       my-utility --version 2>/dev/null | head -1
   }
   ```
2. **Register it in `lib/installers.sh`** — add a line in alphabetical order in the Utilities section:
   ```bash
   register_utility "My Utility" install_my_utility check_my_utility uninstall_my_utility update_my_utility get_version_my_utility
   ```
3. **Test** with `--dry-run` and verify menu rendering

### Adding System Tasks

System tasks use `register_system_task` instead of `register_utility`. They appear in the top section of the menu.

1. Create a file in `lib/installers/` with the task functions
2. Register it in `lib/installers.sh` in the System Tasks section:
   ```bash
   register_system_task "My Task" setup_my_task check_my_task uninstall_my_task update_my_task
   ```

The system task count is derived automatically from the `SYSTEM_TASKS` array — no manual counter to update.

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

**No colours / piped output** — use `--no-color`, set the `NO_COLOR` environment variable, or pipe output to a file; ANSI colours are automatically disabled in non-interactive terminals.

## License

MIT License

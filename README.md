# Linux System Setup & Utilities Installer

An interactive multi-select TUI for installing, uninstalling, and updating system tasks and utilities across all major Linux distributions. Supports 55+ utilities organized by category, automatic pre-operation snapshots, and full CLI automation.

## Requirements

- Bash 4.0+
- `sudo` access (do **not** run as root)
- An interactive terminal (for the TUI menu)
- Internet connection for downloads
- Arch-based distros: `yay` or `paru` recommended for AUR packages

## Quick Start

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
| `--verbose` | Enable verbose output (extra status messages) |
| `--debug` | Enable debug output (internal state details) |
| `--install <name>` | Install a utility by name |
| `--uninstall <name>` | Uninstall a utility by name |
| `--update <name>` | Update a utility by name |
| `--update-all` | Update every currently installed utility |
| `--check <name>` | Exit 0 if installed, 1 if not |
| `--no-color` | Disable colored output |
| `--setup-logrotate` | Install logrotate config for linux\_util logs |

Utility names are matched case-insensitively and support partial matches. `--dry-run` can be combined with any action flag.

```bash
./linux_util.sh --list
./linux_util.sh --check "Docker"
./linux_util.sh --install "Visual Studio Code"
./linux_util.sh --dry-run --update-all
```

## Interactive Menu

The TUI uses a two-panel layout: a left sidebar with category tabs and system info, and a right panel listing items with a description pane. Items are organized into categories and subcategories, and version numbers are shown inline for installed utilities.

```
┌──────────────────────┬──────────────────────────────────────────────────┐
│ linux_util (main: a1b2c3)                                   / search    │
├──────────────────────┼──────────────────────────────────────────────────┤
│ CATEGORIES           │ Internet ─────────────────────────────────────── │
├──────────────────────┤   [D]  Email Clients                             │
│ > System Tasks       │   [D]  Messaging                                 │
│   Development        │   [D]  Remote Access                             │
│   Gaming             │   [D]  VPN                                       │
│   Internet           │   [D]  Web Browsers                              │
│   Productivity       │   [x]  QBittorrent             (v4.6.4)          │
│   System Tools       │   [ ]  Syncthing               (v1.27.6)         │
├──────────────────────┤                                                  │
│ PROFILES             │                                                  │
├──────────────────────┤                                                  │
│   Run Me First       │                                                  │
│   Default VM Server  │                                                  │
│   Default Phys. PC   │                                                  │
│   Custom Profile 1   │                                                  │
│   Custom Profile 2   │                                                  │
├──────────────────────┤                                                  │
│ SYSTEM Details       │                                                  │
├──────────────────────┤                                                  │
│     Host: linux-pc   │                                                  │
│       OS: Arch Linux │                                                  │
│   Kernel: 6.12.8-1   │                                                  │
│      CPU: i9-14900K  │──────────────────────────────────────────────────│
│      Mem: 8.2G/32G   │  Open-source BitTorrent client with a clean      │
│     Disk: 245G/500G  │  interface and no ads.                           │
│   Uptime: 3d 12h     │                                                  │
├──────────────────────┴──────────────────────────────────────────────────┤
│ Actions: Install: 0 | Uninstall: 1 | Update: 0                          │
│ [^v] Navigate  [Space] Select  [U] Update  [/] Search  [Enter] Confirm  │
└─────────────────────────────────────────────────────────────────────────┘
```

Subcategories (marked `[D]`) group related items — press Enter to drill in, `..` to go back.

### Controls

| Key | Action |
|-----|--------|
| ↑ / ↓ | Navigate items |
| `Space` | Toggle select |
| `U` | Queue an installed item for update |
| `Enter` | Confirm selection / enter subcategory |
| `/` | Search across all categories |
| `Tab` | Switch focus between categories and items |
| `A` | Select all |
| `D` | Deselect all |
| `Q` | Quit |

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
| **Full System Upgrade/Update** | Comprehensive system upgrade — all configured package managers, essential tools, and cache cleanup |
| **System Updates** | Package list refresh, full upgrade, autoremove, and cache clean |
| **KDE Desktop** | Installs KDE Plasma desktop environment with SDDM |
| **NVIDIA Drivers** | Detects available drivers, lets you choose a version, installs 32-bit libs, nvtop, and NVIDIA Container Toolkit if Docker is present |
| **AMD Drivers** | Installs open-source AMD GPU drivers (AMDGPU/Mesa) for optimal graphics performance |
| **XEN Guest Utilities** | Mounts XCP-NG ISO and runs the tools installer |
| **Enable RDP** | Enables Remote Desktop Protocol access via XRDP server |
| **Flatpak Setup** | Configures Flatpak and adds the Flathub repository |
| **UFW Firewall** | Installs and configures Uncomplicated Firewall with sensible defaults |
| **Local MOTD** | Replaces Ubuntu's default dynamic MOTD with a clean, fast local version *(Ubuntu/Kubuntu/Neon only)* |
| **Command-Not-Found Prompt** | Enables auto-suggestion to install missing command packages *(Ubuntu/Kubuntu/Neon only)* |
| **Create Snapshot** | Creates a Timeshift or Snapper snapshot with a user-provided description |
| **Restore Snapshot** | Lists available snapshots, creates a safety snapshot, then restores the selected one |

### Utilities by Category

#### Development

| Utility | Description |
|---------|-------------|
| **Claude Code** | Anthropic's AI coding assistant for the terminal |
| **Cursor IDE** | AI-powered code editor built on VS Code |
| **DBeaver** | Universal database management tool |
| **Docker** | Container platform — official repos, adds user to `docker` group |
| **GitHub CLI** | Official CLI for GitHub — repos, issues, PRs, and workflows |
| **JetBrains Toolbox** | Manager for JetBrains IDEs (IntelliJ, PyCharm, WebStorm, etc.) |
| **NVM** | Node Version Manager — install and switch Node.js versions |
| **Postman** | API development and testing platform |
| **Visual Studio Code** | Microsoft's extensible code editor |

#### Gaming

| Utility | Description |
|---------|-------------|
| **Bottles** | Wine prefix manager for running Windows software |
| **Feral Gamemode** | Optimizes system performance while gaming |
| **Heroic Games Launcher** | Open-source launcher for Epic, GOG, and Amazon Prime Gaming |
| **Lutris** | Open gaming platform for multiple game sources |
| **MangoHud** | Vulkan/OpenGL overlay for FPS, frame times, and hardware monitoring |
| **ProtonUp-Qt** | Manages Proton-GE and Wine-GE compatibility layers |
| **Steam App** | Valve's gaming platform — native packages / RPM Fusion / flatpak |

#### Internet

| Utility | Description |
|---------|-------------|
| **Brave Browser** | Privacy-focused Chromium browser with built-in ad blocking |
| **Chromium** | Open-source browser, upstream base for Chrome |
| **Devolutions RDM** | Remote Desktop Manager — Cloudsmith repo / AUR / flatpak / snap |
| **Discord** | Voice, video, and text communication platform |
| **FileZilla** | FTP, FTPS, and SFTP client |
| **Firefox** | Mozilla's open-source browser |
| **Google Chrome** | Google's browser with sync and developer tools |
| **KMail** | KDE's email client with PGP encryption |
| **OpenSSH Server** | Secure Shell server for remote access |
| **PIA VPN** | Private Internet Access VPN client |
| **ProtonVPN** | Free and open-source VPN by Proton |
| **QBittorrent** | Open-source BitTorrent client |
| **Remmina** | Remote desktop client (RDP, VNC, SSH, SPICE) |
| **Signal Desktop** | End-to-end encrypted messaging |
| **Syncthing** | Peer-to-peer file sync between devices |
| **Tailscale** | Zero-config mesh VPN built on WireGuard |
| **Telegram Desktop** | Cloud-based messaging with groups, channels, and file sharing |
| **Termius SSH Client** | Modern SSH client with cross-device sync |
| **Thorium Browser** | Speed-optimized Chromium browser |
| **Thunderbird** | Mozilla's email client with calendar and PGP |
| **Vivaldi Browser** | Highly customizable Chromium browser |
| **WireGuard Client** | Lightweight VPN client using WireGuard protocol |
| **WireGuard Server** | Sets up a WireGuard VPN server |

#### Productivity

| Utility | Description |
|---------|-------------|
| **Bitwarden Client** | Open-source password manager — `.deb` / `.rpm` / AUR / snap / flatpak |
| **GIMP** | GNU Image Manipulation Program |
| **Joplin Client** | Note-taking app with Markdown and sync (AppImage) |
| **LibreOffice** | Open-source office suite — direct download / native packages / flatpak |
| **Nextcloud Desktop** | Sync client for self-hosted Nextcloud cloud storage |
| **OBS Studio** | Video recording and live streaming |
| **Obsidian** | Markdown-based knowledge base with graphs and plugins |
| **OnlyOffice** | Office suite with MS Office format compatibility |
| **Standard Notes** | End-to-end encrypted notes with cross-platform sync |
| **WPS Office** | MS Office-compatible office suite |

#### System Tools

| Utility | Description |
|---------|-------------|
| **Btop** | Terminal-based resource monitor with rich visuals |
| **Dotfiles** | Deploys personal shell config from your repository |
| **Fastfetch** | Fast system information display tool |
| **Stacer** | Graphical system optimizer and monitor |
| **Timeshift** | System restore utility using rsync or BTRFS snapshots |
| **Zsh + Oh My Zsh** | Z shell with Oh My Zsh framework, themes, and plugins |

## Supported Distributions

| Family | Distributions | Package Manager |
|--------|--------------|-----------------|
| Debian/Ubuntu | Ubuntu, Debian, Linux Mint, Pop!\_OS, elementary OS, Zorin, Kali, KDE neon | apt |
| Fedora | Fedora | dnf |
| RHEL | RHEL, CentOS, Rocky Linux, AlmaLinux, Oracle Linux | dnf / yum |
| Arch | Arch Linux, Manjaro, EndeavourOS, Garuda, Artix, CachyOS | pacman + AUR |
| openSUSE | openSUSE Leap, Tumbleweed, SLES | zypper |

Unrecognised distributions are matched via `ID_LIKE` in `/etc/os-release`, then by auto-detecting the available package manager.

## Automatic Snapshots

A system snapshot is automatically created before every install, uninstall, or update operation, providing an easy rollback point.

| Tool | Distros | Notes |
|------|---------|-------|
| **Timeshift** | All supported distros | Used whenever `timeshift` is installed |
| **Snapper** | Arch-based (CachyOS, Manjaro, etc.) | Fallback when Timeshift is absent and Snapper has a root config |

- Auto-detects which snapshot tool is available
- Arch-based systems with Snapper (e.g. CachyOS) work out of the box
- Timeshift auto-detects and configures the backup device on first use
- Each snapshot is tagged with the operation (e.g., `linux_util: Install Docker`)
- **Create Snapshot** and **Restore Snapshot** are available as System Tasks in the menu
- Restore always takes a safety snapshot before proceeding
- Non-blocking — if snapshot creation fails, the operation continues normally

## Configuration

Copy the example config and edit as needed:

```bash
cp linux_util.conf.example linux_util.conf
```

| Setting | Default | Description |
|---------|---------|-------------|
| `log_retention_days` | `30` | Days to keep log files |
| `max_log_size_mb` | `50` | Maximum log file size in MB |
| `max_logs_per_day` | `15` | Maximum log files per day |
| `compress_old_logs` | `true` | Compress older log files |
| `log_level` | `INFO` | Log level: `DEBUG`, `INFO`, `WARNING`, `ERROR` |
| `auto_confirm` | `false` | Skip confirmation prompts |
| `retry_failed` | `true` | Retry failed installations |
| `retry_attempts` | `3` | Number of retry attempts |
| `dns_check_enabled` | `true` | Check DNS connectivity at startup |
| `dns_timeout_seconds` | `10` | DNS check timeout |
| `disk_min_mb` | `1024` | Minimum free disk space (MB) before allowing installs |
| `auto_cleanup` | `true` | Automatic cleanup of temp files |
| `create_backups` | `true` | Create backups before changes |
| `verbose` | `false` | Enable verbose output |
| `debug` | `false` | Enable debug output |

## Logging

Every run creates timestamped log files in `logs/`:

- `success_YYYYMMDD_HHMMSS.log` — successful operations
- `error_YYYYMMDD_HHMMSS.log` — errors and warnings (only created if needed)
- `success_latest.log` / `error_latest.log` — symlinks to the most recent logs

Use `manage_logs.sh` for log management:

```bash
./manage_logs.sh list             # list all log files
./manage_logs.sh view latest      # view latest logs
./manage_logs.sh tail success     # follow a log in real time
./manage_logs.sh search "Docker"  # search logs
./manage_logs.sh stats            # show statistics
./manage_logs.sh clean 30         # remove logs older than 30 days
./manage_logs.sh compress         # compress old logs
```

## Project Structure

```
linux_util/
├── linux_util.sh            Main script — CLI parsing, initialization, orchestration
├── linux_util.conf.example  Example configuration file
├── linux_util.logrotate     Logrotate config for log rotation
├── manage_logs.sh           Log management utility
├── lib/
│   ├── config.sh            Configuration file parsing, verbose/debug helpers
│   ├── logging.sh           Logging functions, error handling, cleanup, metrics
│   ├── pkg_manager.sh       Package manager abstraction, distro detection
│   ├── aur.sh               Arch User Repository functions
│   ├── system.sh            Pre-flight checks, logrotate setup, system helpers
│   ├── snapshot.sh          Snapshot integration — Timeshift and Snapper
│   ├── utilities.sh         Utility registry, name resolution, dependency resolution
│   ├── menu.sh              TUI rendering, keyboard navigation, category layout
│   ├── installers.sh        Loader + registration for all utilities/system tasks
│   ├── profiles.sh          Curated installation presets
│   └── installers/          Per-utility installer scripts (69 files, one per utility/task)
├── logs/                    Timestamped execution logs
├── tests/
│   └── test_linux_util.sh   Test suite
└── README.md
```

### Module Responsibilities

| Module | Purpose | Edit When... |
|--------|---------|--------------|
| `linux_util.sh` | Main script, CLI argument parsing, initialization | Changing argument parsing or main flow |
| `lib/config.sh` | Configuration file parsing, verbose/debug output helpers | Adding new config options |
| `lib/logging.sh` | Logging functions, error handling, cleanup | Changing log format or adding log functions |
| `lib/pkg_manager.sh` | Package manager abstraction, distro detection | Adding new distros or package managers |
| `lib/aur.sh` | AUR/pacman-specific functions | Modifying AUR installation logic |
| `lib/system.sh` | Pre-flight checks, logrotate setup, system helpers | Adding pre-flight checks |
| `lib/snapshot.sh` | Automatic snapshots via Timeshift or Snapper | Adding snapshot backends |
| `lib/menu.sh` | TUI rendering, keyboard navigation, categories | Changing menu appearance or navigation |
| `lib/profiles.sh` | Curated selection presets | Adding, removing, or customizing a profile |
| `lib/utilities.sh` | Utility registry, name resolution, health checks | Modifying how utilities are registered |
| `lib/installers.sh` | Sources `lib/installers/*.sh`, registers all entries | **Adding a registration line for a new utility** |
| `lib/installers/*.sh` | Per-utility install/uninstall/update/check functions | **Adding or modifying a specific utility** |

## Profiles

Profiles are curated presets that pre-populate the install/update queue in one step. They appear in the left sidebar below `CATEGORIES` — press `Tab` to focus `PROFILES`, then `↑`/`↓` to navigate and `Enter` to apply.

Applying a profile clears all current selections and queues the profile's items. Items already installed are skipped; items unavailable on the current distro are silently ignored.

| Profile | Description |
|---------|-------------|
| **Run Me First** | Installs Timeshift for a restore point before any other changes |
| **Default VM Server Profile** | Xen Guest Utilities, Btop, Zsh + Oh My Zsh |
| **Default Physical PC** | Desktop essentials — VSCode, GitHub CLI, Steam, Brave, and more |
| **Custom Profile 1** | Blank user-defined slot |
| **Custom Profile 2** | Second blank user-defined slot |

To customize, edit `_profile_custom_1()` or `_profile_custom_2()` in `lib/profiles.sh`:

```bash
_profile_custom_1() {
    _profile_select_for_install "Docker"
    _profile_select_task        "UFW Firewall"
}
register_profile "Custom Profile 1" _profile_custom_1 "Short description."
```

Available helpers: `_profile_select_for_install`, `_profile_select_for_update`, `_profile_select_task`. Valid utility names are listed at the top of `lib/profiles.sh`.

## Adding New Utilities

Each utility lives in its own file under `lib/installers/`. Files are auto-sourced — no loader changes needed.

### Steps

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

2. **Register in `lib/installers.sh`** — add a line in alphabetical order in the Utilities section:

   ```bash
   register_utility "My Utility" install_my_utility check_my_utility uninstall_my_utility update_my_utility get_version_my_utility
   ```

3. **Assign a category** in the category section of `lib/installers.sh`:

   ```bash
   UTILITY_CATEGORY["My Utility"]="Development"
   ```

4. **Test** with `--dry-run` and verify menu rendering.

System tasks use `register_system_task` instead of `register_utility` and appear in the System Tasks section of the menu.

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

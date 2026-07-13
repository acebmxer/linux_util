# Linux System Setup & Utilities Installer

[![CI](https://github.com/acebmxer/linux_util/actions/workflows/ci.yml/badge.svg)](https://github.com/acebmxer/linux_util/actions/workflows/ci.yml)

An interactive multi-select TUI for installing, uninstalling, and updating system tasks and utilities across all major Linux distributions. Supports 100+ utilities organized by category, automatic pre-operation snapshots, and full CLI automation.

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
│  Developer Workstat. │                                                  │
│    Home Desktop      │                                                  │
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
| **Fix Package Repos** | Refreshes repository metadata and repairs common repo errors (stale caches, unreachable mirrors, missing keys); cache wipe / keyring reinit is confirmed first |
| **Fix Broken Packages** | Repairs half-installed packages and unmet dependencies (`dpkg --configure -a` / `apt --fix-broken`, `dnf distro-sync`, `pacman -Syu`, `zypper verify`) |
| **Reset Repos to Default** | Restores base distro repos toward stock state — backs up all repo config, keeps third-party repos with installed dependents, prompts keep/disable/remove for the rest |
| **Fix RDP Kerberos Delay** | Stops Remmina/FreeRDP (`xfreerdp`) stalling ~20s before each Windows RDP login by setting `dns_lookup_kdc`/`dns_lookup_realm`/`rdns` to `false` under `[libdefaults]` in `/etc/krb5.conf` — realm-agnostic (fixes every domain), backs up the file first, and is reversible |
| **Delete Default Cloud-Init User** | Removes the stock cloud-image account and its home directory (`ubuntu`/`debian`/`centos`/`alpine`) via `deluser --remove-home` (`userdel --remove` where `deluser` is absent); shows "Cloud Init user found" in status while one exists, confirms before deleting, and refuses to delete the logged-in user |
| **Mount Local Drive** | Interactively select an unmounted block device and add it to `/etc/fstab` |
| **Mount NFS Share** | Discover and mount an NFS export from a remote server, persisted in `/etc/fstab` |
| **Mount SMB Share** | Connect to an SMB/CIFS server, store credentials securely, and persist mount in `/etc/fstab` |
| **Manage Share** | Update or unmount an existing linux_util-managed mount |
| **Flatpak Setup** | Configures Flatpak and adds the Flathub repository |
| **UFW Firewall** | Installs and configures Uncomplicated Firewall with sensible defaults |
| **Num Lock at Boot** | Enables Num Lock on TTY consoles and the display manager login screen |
| **Local Time Zone / Locale** | Interactive wizard to set system time zone, locale, or both |
| **Window Button Layout** | Restores minimize/maximize/close on window title bars for GTK apps (GNOME/Cinnamon/MATE/Xfce); fixes the missing buttons seen on Ubuntu under WSLg |
| **Command-Not-Found Prompt** | Enables auto-suggestion to install missing command packages *(Ubuntu/Kubuntu/KDE Neon only)* |
| **Fix Grub on BTRFS** | Fixes GRUB boot entries after BTRFS snapshot restores *(Ubuntu/Kubuntu/KDE Neon only)* |
| **Fix Monitor Layout at Login** | Restores monitor layout on the login screen *(Ubuntu/Kubuntu/KDE Neon only)* |

### Utilities by Category

#### Bootloaders

| Utility | Description |
|---------|-------------|
| **GRUB** | GRand Unified Bootloader — BIOS/UEFI, multi-OS menus, encrypted volumes, virtually every filesystem |
| **Limine** | Modern, portable bootloader for BIOS and UEFI (x86_64/aarch64) with fast startup and clean config *(non-Debian)* |
| **systemd-boot** | Lightweight EFI-only bootloader that ships with systemd — simple drop-in entries, automatic kernel discovery *(non-Debian)* |
| **Switch Bootloader** | Interactively switch between GRUB, Limine, and systemd-boot, deploying the chosen one to disk/EFI |
| **Configure Bootloader** | Tune the active bootloader (timeout, kernel parameters, default entry) and rebuild missing initramfs images |
| **GRUB Theme Selector** | Switch the active GRUB theme between any already-installed themes (or the stock no-theme menu) without reinstalling *(GRUB Themes)* |
| **Distro GRUB Themes** | Per-distro logo boot themes from AdisonCavani/distro-grub-themes, auto-matched to your distribution *(GRUB Themes)* |
| **vinceliuice GRUB Themes** | Polished GRUB themes from vinceliuice/grub2-themes (tela/vimix/stylish/whitesur/slaze) *(GRUB Themes)* |
| **Catppuccin GRUB Theme** | The soothing pastel Catppuccin theme for GRUB — mocha by default (catppuccin/grub) *(GRUB Themes)* |
| **HyperFluent GRUB Theme** | Sleek, modern animated GRUB theme matched to your distribution (Coopydood/HyperFluent-GRUB-Theme) *(GRUB Themes)* |

#### Drivers

| Utility | Description |
|---------|-------------|
| **AMD Drivers** | Installs open-source AMD GPU drivers (AMDGPU/Mesa) |
| **AMD CPU Microcode & Firmware** | Installs AMD CPU microcode updates and firmware packages |
| **Intel CPU Microcode & Thermal** | Installs Intel CPU microcode updates and thermal management tools |
| **LACT** | Linux AMDGPU Control Application — fan curves, power limits, overclocking |
| **NVIDIA Drivers** | Detects available drivers, lets you choose a version, installs 32-bit libs, nvtop, and NVIDIA Container Toolkit if Docker is present |
| **XEN Guest Utilities** | Mounts XCP-NG ISO and runs the tools installer |

#### Desktop Environments

| Utility | Description |
|---------|-------------|
| **Budgie Desktop** | Solus-origin desktop focused on simplicity and elegance |
| **Cinnamon Desktop** | Traditional layout desktop from the Linux Mint team |
| **COSMIC Desktop** | New Rust-based desktop from System76 |
| **Deepin Desktop** | Visually polished desktop from the Deepin project |
| **GNOME Desktop** | Default desktop on Ubuntu and Fedora |
| **KDE Desktop** | KDE Plasma desktop environment with SDDM |
| **LXQt Desktop** | Lightweight Qt-based desktop |
| **MATE Desktop** | Continuation of the classic GNOME 2 desktop |
| **Pantheon Desktop** | elementary OS desktop environment |
| **Xfce Desktop** | Lightweight and fast traditional desktop |

#### Backup

| Utility | Description |
|---------|-------------|
| **Timeshift** | System restore utility using rsync or BTRFS snapshots |
| **Create Snapshot** | Creates a Timeshift snapshot with a user-provided description |
| **Restore Snapshot** | Lists snapshots, takes a safety snapshot, then restores the selected one |
| **Delete Snapshot** | Lists and deletes existing Timeshift snapshots |
| **Snapper** | Btrfs/LVM snapshot manager used on Arch-based distros |
| **Create Snapshot (Snapper)** | Creates a Snapper snapshot with a user-provided description |
| **Restore Snapshot (Snapper)** | Restores from a Snapper snapshot |
| **Delete Snapshot (Snapper)** | Lists and deletes existing Snapper snapshots |
| **Déjà Dup** | Simple GNOME backup tool with cloud and local storage support |
| **Kup** | KDE backup tool — incremental (bup) or synchronized (rsync) backups via System Settings |
| **Vorta** | Borg Backup GUI — deduplicating, encrypted backups |
| **Duplicati** | Browser-based backup tool with cloud provider support |

#### Disk Utilities

| Utility | Description |
|---------|-------------|
| **GParted** | Graphical partition editor — create, resize, move, and delete partitions |
| **Ventoy** | Bootable USB tool — boot multiple ISOs from one drive |
| **Btrfs Assistant** | GUI for managing Btrfs subvolumes and Snapper snapshots *(Btrfs Tools)* |
| **btrfsmaintenance** | Automates scheduled Btrfs scrub, balance, trim, and defrag *(Btrfs Tools)* |
| **btrbk** | Btrfs snapshot and backup tool with remote send/receive *(Btrfs Tools)* |
| **duperemove** | Extent-based deduplication tool for Btrfs *(Btrfs Tools)* |

#### Development

| Utility | Description |
|---------|-------------|
| **Ansible** | IT automation and configuration management tool |
| **Claude Code** | Anthropic's AI coding assistant for the terminal |
| **Cursor IDE** | AI-powered code editor built on VS Code |
| **DBeaver** | Universal database management tool |
| **Distrobox** | Run any Linux distro in an integrated terminal container (needs Podman/Docker) |
| **BoxBuddy** | GTK4 graphical front-end for Distrobox (Flatpak) |
| **DistroShelf** | GTK4 graphical manager for Distrobox containers (Flatpak) |
| **Docker** | Container platform — official repos, adds user to `docker` group |
| **GitHub CLI** | Official CLI for GitHub — repos, issues, PRs, and workflows |
| **Go SDK** | Official Go programming language toolchain |
| **JetBrains Toolbox** | Manager for JetBrains IDEs (IntelliJ, PyCharm, WebStorm, etc.) |
| **k9s** | Terminal UI for managing Kubernetes clusters |
| **kubectl** | Kubernetes command-line tool |
| **Neovim** | Extensible Vim-based text editor |
| **Node.js** | JavaScript runtime — LTS release via NodeSource |
| **NVM** | Node Version Manager — install and switch Node.js versions |
| **OpenTofu** | Open-source Terraform-compatible infrastructure-as-code tool |
| **Podman** | Daemonless OCI container engine |
| **Postman** | API development and testing platform |
| **pyenv** | Python version manager |
| **Rustup** | Rust toolchain installer and version manager |
| **Terraform** | HashiCorp infrastructure-as-code tool |
| **Virt-Manager** | GUI for managing KVM/QEMU virtual machines |
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
| **Wine** | Compatibility layer for running Windows applications and games on Linux |

#### Internet

| Utility | Description |
|---------|-------------|
| **Bitwarden Extension** | Bitwarden browser extension installer |
| **Brave Browser** | Privacy-focused Chromium browser with built-in ad blocking |
| **Brave Origin** | Streamlined Brave build without Rewards, Wallet, VPN, and Leo AI |
| **Chromium** | Open-source browser, upstream base for Chrome |
| **Discord** | Voice, video, and text communication platform |
| **Element (Matrix)** | Matrix protocol client for decentralised messaging |
| **FileZilla** | FTP, FTPS, and SFTP client |
| **Firefox** | Mozilla's open-source browser |
| **Google Chrome** | Google's browser with sync and developer tools |
| **Joplin Web Clipper** | Browser extension for saving web content to Joplin |
| **KMail** | KDE's email client with PGP encryption |
| **LibreWolf** | Privacy-hardened Firefox fork |
| **PIA VPN** | Private Internet Access VPN client |
| **ProtonVPN** | Free and open-source VPN by Proton |
| **QBittorrent** | Open-source BitTorrent client |
| **Signal Desktop** | End-to-end encrypted messaging |
| **Slack** | Team messaging and collaboration platform |
| **SponsorBlock Extension** | Browser extension to skip sponsored segments in YouTube videos |
| **Syncthing** | Peer-to-peer file sync between devices |
| **Tailscale** | Zero-config mesh VPN built on WireGuard |
| **Telegram Desktop** | Cloud-based messaging with groups, channels, and file sharing |
| **Thorium Browser** | Speed-optimized Chromium browser |
| **Thunderbird** | Mozilla's email client with calendar and PGP |
| **Tor Browser** | Anonymous browsing via the Tor network |
| **UniFi Endpoint** | Ubiquiti's UniFi Identity VPN client for UniFi-managed networks — `.deb` / `.rpm` |
| **Vivaldi Browser** | Highly customizable Chromium browser |
| **WireGuard Client** | Lightweight VPN client using WireGuard protocol |
| **WireGuard Server** | Sets up a WireGuard VPN server |
| **Zen Browser** | Privacy-focused Firefox-based browser with vertical tabs and split view (beta) |
| **Zoom** | Video conferencing and collaboration platform |

#### Productivity

| Utility | Description |
|---------|-------------|
| **Audacity** | Open-source audio editor and recorder |
| **Bitwarden Client** | Open-source password manager — `.deb` / `.rpm` / AUR / snap / flatpak |
| **Flameshot** | Feature-rich screenshot tool with annotation support |
| **GIMP** | GNU Image Manipulation Program |
| **HandBrake** | Open-source video transcoder |
| **Inkscape** | Professional vector graphics editor |
| **Joplin Client** | Note-taking app with Markdown and sync (AppImage) |
| **Kdenlive** | Open-source video editor by KDE |
| **Krita** | Professional digital painting application |
| **Libation** | Audible audiobook manager — `.deb` / `.rpm` / AUR |
| **LibreOffice** | Open-source office suite — direct download / native packages / flatpak |
| **Logseq** | Privacy-first knowledge management and outliner |
| **Mark Text** | Simple and elegant Markdown editor |
| **Nextcloud Desktop** | Sync client for self-hosted Nextcloud cloud storage |
| **OBS Studio** | Video recording and live streaming |
| **Obsidian** | Markdown-based knowledge base with graphs and plugins |
| **OnlyOffice** | Office suite with MS Office format compatibility |
| **Standard Notes** | End-to-end encrypted notes with cross-platform sync |
| **VLC** | Versatile media player supporting virtually all formats |
| **WPS Office** | MS Office-compatible office suite |
| **Zotero** | Reference manager and research tool |

#### Remote Admin Tools

| Utility | Description |
|---------|-------------|
| **AnyDesk** | Remote desktop application *(Remote Access)* |
| **Cockpit** | Web-based server management console at `https://<host>:9090`; enables `cockpit.socket` and opens the firewall port *(Remote Access)* |
| **Devolutions RDM** | Remote Desktop Manager — Cloudsmith repo / AUR / flatpak / snap *(Remote Access)* |
| **Enable RDP** | Enables Remote Desktop Protocol access via XRDP server *(Remote Access)* |
| **OpenSSH Server** | Secure Shell server for remote access *(Remote Access)* |
| **Remmina** | Remote desktop client (RDP, VNC, SSH, SPICE) *(Remote Access)* |
| **RustDesk** | Open-source remote desktop and remote assistance tool *(Remote Access)* |
| **Termius SSH Client** | Modern SSH client with cross-device sync *(Remote Access)* |
| **OpenRSAT** | Active Directory management console (Microsoft RSAT-like) from Tranquil IT — installs the latest GitHub release as a `.deb` (Debian/Ubuntu), `.rpm` (Fedora/RHEL x86_64), or standalone binary (openSUSE); not available on Arch |

#### System Tools

| Utility | Description |
|---------|-------------|
| **Btop** | Terminal-based resource monitor with rich visuals |
| **ClamAV** | Open-source antivirus engine |
| **Fastfetch** | Fast system information display tool |
| **Filelight** | Disk usage analyzer with interactive sunburst chart |
| **Input Leap** | Software KVM — share keyboard and mouse across machines |
| **OCCT** | CPU/RAM/GPU stability and stress testing — free Personal edition, x86_64 binary from ocbase.com, installed per-user under `~/.local/share/occt` |
| **Stacer** | Graphical system optimizer and monitor |
| **Zsh + Oh My Zsh** | Z shell with Oh My Zsh framework, themes, and plugins |

Grouped under a **Kernel Managers** folder inside the System Tools tab — tools for installing and switching alternate kernels. Each is listed on every distro but installs only on the family it supports (warning and stopping otherwise):

| Utility | Description |
|---------|-------------|
| **Mainline** | Ubuntu mainline-kernel installer (cappelikan/bkw777 fork of ukuu) — GUI + CLI for kernels from kernel.ubuntu.com. Debian/Ubuntu only (PPA, or upstream `.deb` fallback) |
| **CachyOS Kernel Manager** | GUI to install/build/swap kernels on Arch (also configures sched-ext). Ships only in the CachyOS repo, not the AUR; installs where that repo is enabled |
| **Fedora Mainline Kernel** | Enables the `@kernel-vanilla/mainline` Copr and installs the latest upstream mainline kernel. Fedora only (requires Secure Boot disabled) |
| **linux-tkg** | Frogging-Family custom-kernel **builder** — compiles a kernel from source with your choice of scheduler (BORE/EEVDF/PDS), compiler, and config. Cross-distro (Arch via makepkg; Debian/Ubuntu, Fedora, openSUSE via `install.sh`). Interactive, long compile |

## Supported Distributions

| Family | Distributions | Package Manager |
|--------|--------------|-----------------|
| Debian/Ubuntu | Ubuntu, Debian, Linux Mint, Pop!\_OS, elementary OS, Zorin, Kali, KDE neon | apt |
| Fedora | Fedora | dnf |
| RHEL | RHEL, CentOS, Rocky Linux, AlmaLinux, Oracle Linux | dnf / yum |
| Arch | Arch Linux, Manjaro, EndeavourOS, Garuda, Artix, CachyOS | pacman + AUR |
| openSUSE | openSUSE Leap, Tumbleweed, SLES | zypper |

Unrecognised distributions are matched via `ID_LIKE` in `/etc/os-release`, then by auto-detecting the available package manager.

## WSL (Windows Subsystem for Linux)

The script runs on WSL distributions (e.g. Ubuntu under WSL2) and detects the
WSL environment automatically. WSL is identified via the `WSL_DISTRO_NAME`
environment variable or the `microsoft`/`-WSL2` marker in `/proc/version`.

When running under WSL:

- A one-line notice is shown at startup, and the menu's **System Details** panel
  includes an `Env: WSL (<distro>)` row.
- The **Reboot** action behaves differently. A real reboot is not possible from
  inside a WSL distribution — Windows owns the virtual machine lifecycle and
  there is no bootloader (`sudo systemctl reboot` is unreliable, and on
  distros without systemd it fails outright). Instead, choosing to reboot
  **restarts only the current distribution** (Windows itself is never affected)
  by terminating it from the Windows side via the `wsl.exe` interop bridge:

  ```powershell
  wsl --terminate <DistroName>
  wsl -d <DistroName>
  ```

  The script performs the `--terminate` step for you. Your session ends
  immediately (expected) and the distro auto-starts the next time you open a
  terminal or run `wsl -d <DistroName>`. If the `wsl.exe` bridge is unavailable,
  the script prints the exact PowerShell commands above for you to run manually.
- Under WSLg, GTK apps (e.g. Remmina, Nautilus, Files) often launch with only a
  close button — GNOME's default window-manager layout omits minimize/maximize.
  The **Window Button Layout** system task restores all three by setting
  `org.gnome.desktop.wm.preferences button-layout` to `:minimize,maximize,close`.
  Qt/KDE apps such as Konsole are unaffected because they do not read this key.

On a normal Linux host or VM, reboot behavior is unchanged (`sudo systemctl reboot`).

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

## Shell Completions

Tab-completion scripts for bash and zsh are provided in the `completions/` directory.

### Bash

```bash
# Source for the current session
source completions/linux_util.bash

# Install system-wide (requires root)
sudo cp completions/linux_util.bash /etc/bash_completion.d/linux_util

# Or install for your user only
mkdir -p ~/.local/share/bash-completion/completions
cp completions/linux_util.bash ~/.local/share/bash-completion/completions/linux_util
```

### Zsh

```zsh
# Add the completions directory to fpath (add this to ~/.zshrc)
fpath=(/path/to/linux_util/completions $fpath)
autoload -Uz compinit && compinit

# Or install system-wide
sudo cp completions/_linux_util /usr/local/share/zsh/site-functions/_linux_util

# Or install for your user only
mkdir -p ~/.zsh/completions
cp completions/_linux_util ~/.zsh/completions/_linux_util
# Add to ~/.zshrc:  fpath=(~/.zsh/completions $fpath)
```

Once installed, tab-completing `./linux_util.sh --install <TAB>` lists all available utility names.

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
│   └── installers/          Per-utility installer scripts (132 files, one per utility/task)
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
| **Developer Workstation** | UFW, OpenSSH Server, Docker, VSCode, GitHub CLI, NVM, Postman, DBeaver, Bitwarden Client, Btop, Zsh + Oh My Zsh, Fastfetch |
| **Home Desktop** | Flatpak, Firefox, Thunderbird, Signal, LibreOffice, GIMP, Nextcloud Desktop, Bitwarden Client, Joplin Client, QBittorrent, ProtonVPN, Btop, Zsh + Oh My Zsh, Fastfetch |

To add your own profile, edit `_profile_custom_1()` or `_profile_custom_2()` in `lib/profiles.sh` and change the registered name:

```bash
_profile_custom_1() {
    _profile_select_for_install "Docker"
    _profile_select_task        "UFW Firewall"
}
register_profile "Developer Workstation" _profile_custom_1 "Short description."
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

This project is licensed under the [MIT License](LICENSE).

# Utility Catalogue

Every system task and utility `linux_util.sh` can install, by category — the same
entries the interactive menu shows. For the live state of your own machine
(what is installed, and at what version) run `./linux_util.sh --list`.

Some entries are limited to one distribution family; where that is the case it
is noted in italics beside the description. Names in italics such as *(GRUB
Themes)* or *(Remote Access)* are the subcategory folder the item sits in.

| | | |
|---|---|---|
| [System Tasks](#system-tasks) | [Bootloaders](#bootloaders) | [Drivers](#drivers) |
| [Desktop Environments](#desktop-environments) | [Backup](#backup) | [Disk Utilities](#disk-utilities) |
| [Development](#development) | [Gaming](#gaming) | [Internet](#internet) |
| [Package Managers](#package-managers) | [Productivity](#productivity) | [Remote Admin Tools](#remote-admin-tools) |
| [File Managers](#file-managers) | [Firewalls](#firewalls) | [Login Screens](#login-screens) |
| [System Tools](#system-tools) | [Window Managers](#window-managers) | |

Run `./linux_util.sh --list` for the live list on your own machine. Entries
that depend on the distribution (for example the Debian/Ubuntu-only tasks) only
appear when it applies.

## System Tasks

| Task | Description |
|------|-------------|
| **Full System Upgrade** | Upgrades to the next OS release when one is available and confirmed (installs pending packages first, since the release upgrade requires it); does nothing otherwise — use System Updates for regular package updates. Arch-family defers to the distro's own full-update tool |
| **System Updates** | Package list refresh, full upgrade, autoremove, and cache clean |
| **Fix Package Repos** | Refreshes repository metadata and repairs common repo errors (stale caches, unreachable mirrors, missing keys); cache wipe / keyring reinit is confirmed first |
| **Fix Broken Packages** | Repairs half-installed packages and unmet dependencies (`dpkg --configure -a` / `apt --fix-broken`, `dnf distro-sync`, `pacman -Syu`, `zypper verify`) |
| **Reset Repos to Default** | Restores base distro repos toward stock state — backs up all repo config, keeps third-party repos with installed dependents, prompts keep/disable/remove for the rest |
| **Fix RDP Kerberos Delay** | Stops Remmina/FreeRDP (`xfreerdp`) stalling ~20s before each Windows RDP login by setting `dns_lookup_kdc`/`dns_lookup_realm`/`rdns` to `false` under `[libdefaults]` in `/etc/krb5.conf` — realm-agnostic (fixes every domain), backs up the file first, and is reversible |
| **Delete Default Cloud-Init User** | Removes the stock cloud-image account and its home directory (`ubuntu`/`debian`/`centos`/`alpine`/`fedora`) via `deluser --remove-home` (`userdel --remove` where `deluser` is absent); shows "Cloud Init user found" in status while one exists, confirms before deleting, and refuses to delete the logged-in user |
| **Mount Local Drive** | Interactively select an unmounted block device and add it to `/etc/fstab` |
| **Mount NFS Share** | Discover and mount an NFS export from a remote server, persisted in `/etc/fstab` |
| **Mount SMB Share** | Connect to an SMB/CIFS server, store credentials securely, and persist mount in `/etc/fstab` |
| **Manage Share** | Update or unmount an existing linux_util-managed mount |
| **UFW Firewall** | Installs and configures Uncomplicated Firewall with sensible defaults |
| **Num Lock at Boot** | Enables Num Lock on TTY consoles and the display manager login screen |
| **Parallel Downloads** | Raises parallel package downloads to 10 — `max_parallel_downloads` in `/etc/dnf/dnf.conf` or `ParallelDownloads` in `/etc/pacman.conf`; backs up the file first and is reversible *(Fedora/RHEL/Arch only)* |
| **Configure Syncthing Folders** | Wizard that picks which folders Syncthing syncs, following Linux best practice — nothing changes without your confirmation |
| **Local Time Zone / Locale** | Interactive wizard to set system time zone, locale, or both |
| **Unattended Upgrades** | Enables the `unattended-upgrades` package so security (and optionally other) updates install automatically in the background, using the package's own debconf setup *(Debian/Ubuntu only)* |
| **Configure Unattended Upgrades** | Opens `/etc/apt/apt.conf.d/50unattended-upgrades` in your editor to choose update origins, blacklist packages and set auto-reboot and notifications; only shown once the package is installed *(Debian/Ubuntu only)* |
| **Install fail2ban** | Installs fail2ban and enables its service, banning IPs that repeatedly fail logins *(Debian/Ubuntu only)* |
| **GTK Window Fix** | Restores minimize/maximize/close on window title bars for GTK apps (GNOME/Cinnamon/MATE/Xfce); GNOME's default window-manager button layout omits them |
| **Command-Not-Found Prompt** | Enables auto-suggestion to install missing command packages *(Ubuntu/Kubuntu/KDE Neon only)* |
| **Fix Grub on BTRFS** | Fixes GRUB boot entries after BTRFS snapshot restores *(Ubuntu/Kubuntu/KDE Neon only)* |
| **Fix Monitor Layout at Login** | Restores monitor layout on the login screen *(Ubuntu/Kubuntu/KDE Neon only)* |

## Bootloaders

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

## Drivers

| Utility | Description |
|---------|-------------|
| **AMD Drivers** | Installs open-source AMD GPU drivers (AMDGPU/Mesa) and VA-API video acceleration — full-codec `mesa-va-drivers-freeworld` from RPM Fusion on Fedora |
| **Intel Drivers** | Installs open-source Intel GPU drivers (Mesa), Vulkan, and VA-API video acceleration — full-codec `intel-media-driver` from RPM Fusion on Fedora/RHEL |
| **AMD CPU Microcode & Firmware** | Installs AMD CPU microcode updates and firmware packages |
| **Intel CPU Microcode & Thermal** | Installs Intel CPU microcode updates and thermal management tools |
| **LACT** | Linux AMDGPU Control Application — fan curves, power limits, overclocking |
| **NVIDIA Drivers** | Detects available drivers, lets you choose a version, installs 32-bit libs, nvtop, and NVIDIA Container Toolkit if Docker is present |
| **OpenLogi** | Local-first alternative to Logitech Options+ — button/gesture remapping, DPI, SmartShift, and webcam controls for Logi Bolt, Unifying, Bluetooth, and wired devices. Installed from upstream's `.deb`/`.rpm`/`.pkg.tar.zst` (in no distro repo); enables the per-user `openlogi-agent.service` |
| **Thermalright TRCC** | Community Linux port of the Thermalright LCD Control Center — LCD screens and RGB LED segments on Thermalright coolers, AIO pump heads and fan hubs. Upstream's `.deb`/`.pkg.tar.zst` on Debian/Ubuntu and Arch; PyPI via `pipx` on Fedora, RHEL and openSUSE, whose RPM upstream cannot serve |
| **XEN Guest Utilities** | Mounts XCP-NG ISO and runs the tools installer |

## Desktop Environments

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

## Backup

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
| **Snapper GUI** | GTK graphical interface for Snapper — browse, create, delete and compare snapshots on any filesystem Snapper supports; Btrfs is not required |
| **Déjà Dup** | Simple GNOME backup tool with cloud and local storage support |
| **Kup** | KDE backup tool — incremental (bup) or synchronized (rsync) backups via System Settings |
| **Vorta** | Borg Backup GUI — deduplicating, encrypted backups |
| **Duplicati** | Browser-based backup tool with cloud provider support |
| **Back In Time** | Snapshot backups of your files with rsync and a Qt window. Distro package (EPEL on RHEL clones 8 and 9), AUR on Arch (AUR support must be on); not available on Rocky/Alma 10 or Alpine *(File Backup)* |
| **Pika Backup** | Scheduled home-folder backups with BorgBackup. Distro package on Arch and openSUSE Tumbleweed, Flathub elsewhere; not available on Alpine *(File Backup)* |
| **luckyBackup** | Rsync-based backup and sync with profiles and scheduling. Distro package, AUR on Arch (AUR support must be on); not available on RHEL clones or Alpine *(File Backup)* |
| **Grsync** | Graphical front-end for rsync with saved presets. Distro package (EPEL on RHEL clones); not available on Alpine *(File Backup)* |
| **restic** | Encrypted, deduplicating command-line backup to local, SFTP, S3 and cloud stores. Distro package; not available on Rocky/Alma 8 *(Command Line)* |
| **rclone** | Command-line copy and sync to dozens of cloud storage services. Distro package; not available on Rocky/Alma 8 *(Command Line)* |
| **Kopia** | Fast, encrypted, deduplicating backup with a web page (`kopia server start`). Distro package on Fedora and openSUSE, SHA-256 checked GitHub release elsewhere; command line only; not available on Alpine *(Command Line)* |
| **rsnapshot** | Scheduled rsync snapshots with hard links; you write the config and the schedule *(Command Line)* |
| **Clonezilla** | Disk and partition cloning for disks that are not mounted; the live disk is needed to clone the running system. Debian, Ubuntu and Arch only |

## Disk Utilities

| Utility | Description |
|---------|-------------|
| **GParted** | Graphical partition editor — create, resize, move, and delete partitions |
| **Ventoy** | Bootable USB tool — boot multiple ISOs from one drive |
| **KDiskMark** | HDD/SSD benchmark (GUI for fio) — Flathub build where the distro has no package |
| **Btrfs Assistant** | GUI for managing Btrfs subvolumes and Snapper snapshots *(Btrfs Tools)* |
| **btrfsmaintenance** | Automates scheduled Btrfs scrub, balance, trim, and defrag *(Btrfs Tools)* |
| **btrbk** | Btrfs snapshot and backup tool with remote send/receive *(Btrfs Tools)* |
| **duperemove** | Extent-based deduplication tool for Btrfs *(Btrfs Tools)* |

## Development

| Utility | Description |
|---------|-------------|
| **Ansible** | IT automation and configuration management tool |
| **DBeaver** | Universal database management tool |
| **OpenTofu** | Open-source Terraform-compatible infrastructure-as-code tool |
| **Postman** | API development and testing platform |
| **PowerShell** | Microsoft's cross-platform automation shell built on .NET — Microsoft's apt repo where available, otherwise the GitHub release `.deb` |
| **Terraform** | HashiCorp infrastructure-as-code tool |
| **Toolbx** | Containerized command-line environments on Podman, integrated with the host (not available on openSUSE) |

Grouped into folders inside the Development tab:

### IDEs & Editors

| Utility | Description |
|---------|-------------|
| **Visual Studio Code** | Microsoft's extensible code editor |
| **VSCodium** | Telemetry-free community build of VS Code (Open VSX extensions) |
| **Cursor IDE** | AI-powered code editor built on VS Code |
| **JetBrains Toolbox** | Manager for JetBrains IDEs (IntelliJ, PyCharm, WebStorm, etc.) |
| **Neovim** | Extensible Vim-based text editor |
| **Vim** | The classic modal editor (`vim-enhanced` on Fedora and RHEL clones) |
| **Emacs** | GNU Emacs, the extensible editor, with its graphical window |
| **Helix** | Modal terminal editor with language-server support built in. Distro package (Fedora, Rocky/Alma 9 and 10, Arch, openSUSE, Alpine); on Debian, Ubuntu and Rocky/Alma 8 the GitHub release, SHA-256 checked, in `/opt/helix` |
| **Sublime Text** | Fast text and code editor (paid licence, free to evaluate). Sublime HQ's own signed repository on Debian, Ubuntu, Fedora, RHEL clones and openSUSE; the AUR on Arch (only with AUR support on); not available on Alpine or Rocky/Alma 9 and 10 (their RPM refuses the key's SHA-1 signature) |
| **Zed** | Fast code editor with built-in collaboration and AI. Distro package on Arch and openSUSE Tumbleweed, Flathub elsewhere; not available on Alpine |

### AI Tools

| Utility | Description |
|---------|-------------|
| **Claude Code** | Anthropic's AI coding assistant for the terminal |
| **Claude Desktop** | Anthropic's Claude desktop app — Chat, Cowork and Claude Code (Linux beta). Native on Debian/Ubuntu; on other distros it runs in an Ubuntu 26.04 distrobox and appears in the app menu |
| **Codex** | OpenAI's AI coding agent for the terminal (npm; settings in `~/.codex` are kept on uninstall) |
| **Hermes Agent** | Nous Research's open-source AI agent for the terminal (installed per user; update and uninstall use its own commands, settings in `~/.hermes` are kept) |
| **LM Studio** | Desktop app for running large language models locally (AppImage, about 1 GB; models in `~/.lmstudio` are kept on uninstall) |
| **Ollama** | Runs large language models locally, as a service. Distro package (Fedora, Arch, openSUSE, Alpine); elsewhere the GitHub release, SHA-256 checked, with an `ollama` user and systemd service. CPU and NVIDIA GPUs; AMD GPUs need Ollama's ROCm add-on, which is not installed. Uninstall keeps downloaded models |

### Languages & Runtimes

| Utility | Description |
|---------|-------------|
| **Python** | The distro's Python 3 with pip, venv and development headers (pyenv installs other versions). Uninstall keeps `python3` itself |
| **Java JDK** | OpenJDK with the compiler: `default-jdk` on Debian/Ubuntu, otherwise the newest long-term-support build the repositories carry (25, 21 or 17) |
| **PHP** | The PHP command-line interpreter from the distro's packages (not a web-server module) |
| **Ruby** | Ruby with the headers gems need to build native extensions |
| **Go SDK** | Official Go programming language toolchain |
| **Node.js** | JavaScript runtime — LTS release via NodeSource |
| **Rustup** | Rust toolchain installer and version manager |
| **pyenv** | Python version manager |
| **NVM** | Node Version Manager — install and switch Node.js versions |

### Git

| Utility | Description |
|---------|-------------|
| **GitHub CLI** | Official CLI for GitHub — repos, issues, PRs, and workflows |
| **lazygit** | Terminal UI for git. Distro package where there is one (Debian 13, Ubuntu 26.04, Fedora, Arch, openSUSE, Alpine); elsewhere the GitHub release, SHA-256 checked, in `/usr/local/bin` |

### Containers & Kubernetes

| Utility | Description |
|---------|-------------|
| **Docker** | Container platform — official repos, adds user to `docker` group |
| **Podman** | Daemonless OCI container engine |
| **Podman Desktop** | Graphical manager for Podman containers, pods and Kubernetes. Distro package on Arch, Flathub elsewhere; not available on Alpine |
| **kubectl** | Kubernetes command-line tool |
| **k9s** | Terminal UI for managing Kubernetes clusters |
| **Helm** | Kubernetes package manager. Distro package (Fedora, Rocky/Alma 9 and 10, Arch, openSUSE, Alpine); elsewhere the release from `get.helm.sh`, checked against Helm's published SHA-256 |
| **minikube** | Local single-node Kubernetes cluster for development. Distro package on Arch and openSUSE Tumbleweed; elsewhere the GitHub release, SHA-256 checked. Needs a driver (Docker, Podman or KVM); not available on Alpine |
| **k3s** | Lightweight Kubernetes node, started as a service. Alpine: distro package; elsewhere k3s's own install script from `get.k3s.io`. Uninstalling deletes the cluster data in `/var/lib/rancher/k3s` |

### Virtualization

| Utility | Description |
|---------|-------------|
| **VirtualBox** | Runs virtual machines. Distro package on Ubuntu, Arch and openSUSE; Oracle's own signed repository on Debian 12/13, Fedora up to 44 and Rocky/Alma 8 to 10. The kernel module must be signed under Secure Boot; your VMs are kept on uninstall; not available on Alpine |
| **Virt-Manager** | GUI for managing KVM/QEMU virtual machines |
| **Firecracker** | Lightweight KVM microVM monitor (AWS) — Arch package on Arch, otherwise the upstream `firecracker` and `jailer` binaries in `/usr/local/bin`; needs `/dev/kvm` access |

### Network & Security

| Utility | Description |
|---------|-------------|
| **Wireshark** | Network packet analyser; the installing user joins the `wireshark` group to capture without root (log out and in) |
| **nmap** | Network scanner for hosts and open ports; not in openSUSE Leap |

### Distrobox

| Utility | Description |
|---------|-------------|
| **Distrobox** | Run any Linux distro in an integrated terminal container (needs Podman/Docker) |
| **BoxBuddy** | GTK4 graphical front-end for Distrobox (Flatpak) |
| **DistroShelf** | GTK4 graphical manager for Distrobox containers (Flatpak) |
| **Kontainer** | Kirigami/QML graphical manager for Distrobox containers, built for KDE Plasma (Flatpak) |

## Gaming

| Utility | Description |
|---------|-------------|
| **Bottles** | Wine prefix manager for running Windows software |
| **Boxflat** | Settings manager for Moza Racing sim-racing hardware (Flatpak) |
| **Dolphin Emulator** | Nintendo GameCube and Wii emulator. Distro package; Flathub on RHEL clones *(Emulators)* |
| **Feral Gamemode** | Optimizes system performance while gaming |
| **Flatseal** | Shows and changes the permissions of Flatpak apps. Distro package where there is one, else Flathub; not available on Alpine *(Gaming Utilities)* |
| **Gear Lever** | Manages AppImage files (menu entries, updates, removal). Distro package on openSUSE, Flathub elsewhere; not available on Alpine *(Gaming Utilities)* |
| **Heroic Games Launcher** | Open-source launcher for Epic, GOG, and Amazon Prime Gaming |
| **Lutris** | Open gaming platform for multiple game sources |
| **MangoHud** | Vulkan/OpenGL overlay for FPS, frame times, and hardware monitoring |
| **Moonlight** | Streams games from a Sunshine or GeForce PC to this one. Distro package on Fedora, Arch, openSUSE and Alpine, Flathub elsewhere *(Game Streaming)* |
| **PPSSPP** | Sony PSP emulator. Distro package on Arch, openSUSE and Alpine, Flathub elsewhere *(Emulators)* |
| **Prism Launcher** | Minecraft launcher with separate instances per version and mod loader. Distro package where there is one, else Flathub *(Game Launchers)* |
| **ProtonUp-Qt** | Manages Proton-GE and Wine-GE compatibility layers |
| **RetroArch** | Frontend for the libretro emulator cores (consoles, arcade, computers). Distro package; Flathub on RHEL clones *(Emulators)* |
| **Steam App** | Valve's gaming platform — native packages / RPM Fusion / flatpak |
| **Sunshine** | Game-streaming server for Moonlight clients. Flathub plus Sunshine's own setup step for virtual input (asks for your password in a desktop session); not available on Alpine *(Game Streaming)* |
| **Wine** | Compatibility layer for running Windows applications and games on Linux |
| **Xodus Nexus** | Unofficial Xbox-inspired launcher for Microsoft Store PC games (owned or Game Pass), x86_64 AppImage |

## Internet

| Utility | Description |
|---------|-------------|
| **Angry IP Scanner** | Network scanner that pings IP ranges, resolves hostnames, scans ports and exports CSV, TXT or XML; needs Java |
| **Betterbird** | Thunderbird fork with extra fixes and features — Flatpak / AUR |
| **Bitwarden Extension** | Bitwarden browser extension installer |
| **Brave Browser** | Privacy-focused Chromium browser with built-in ad blocking |
| **Brave Origin** | Streamlined Brave build without Rewards, Wallet, VPN, and Leo AI |
| **Brave Debloat** | Turns off Brave's Rewards, Wallet, VPN, Leo AI, News, Talk and Tor through enterprise policy, and disables telemetry *(Web Browser Tweaks)* |
| **Chromium** | Open-source browser, upstream base for Chrome |
| **Claws Mail** | Fast, lightweight GTK email client with a plugin system |
| **Discord** | Voice, video, and text communication platform |
| **Element (Matrix)** | Matrix protocol client for decentralised messaging |
| **Evolution** | GNOME mail, calendar, and contacts suite with Exchange (EWS) support |
| **FileZilla** | FTP, FTPS, and SFTP client |
| **Firefox** | Mozilla's open-source browser |
| **Geary** | Lightweight GNOME email client with conversation threading |
| **Google Chrome** | Google's browser with sync and developer tools |
| **Joplin Web Clipper** | Browser extension for saving web content to Joplin |
| **KMail** | KDE's email client with PGP encryption |
| **LibreWolf** | Privacy-hardened Firefox fork |
| **LocalSend** | Open-source AirDrop alternative — sends files and text between devices on the same network with no account or cloud; uses port 53317. Official `.deb` on Debian/Ubuntu, Flathub elsewhere *(File Transfer)* |
| **Mattermost** | Desktop app for Mattermost team chat. Distro package on Arch, Flathub elsewhere; not available on Alpine *(Messaging)* |
| **Microsoft Teams** | Teams for Linux, the open-source client that wraps the Teams web app (Microsoft stopped its own Linux app in 2022). Flathub, or the distro package where one exists; not available on Alpine *(Messaging)* |
| **Mullvad VPN** | Mullvad's VPN app. Mullvad's signed repository on Debian, Ubuntu, Fedora, RHEL clones and openSUSE, the distro package on Arch; not available on Alpine *(VPN)* |
| **NeoMutt** | Terminal email client, a maintained fork of Mutt |
| **NordVPN** | NordVPN client and service; adds you to the `nordvpn` group. NordVPN's signed repository on Debian, Ubuntu, Fedora, RHEL clones 10+ (x86_64) and openSUSE, the AUR on Arch (AUR support must be on); not available on Alpine or Rocky/Alma 8 and 9 *(VPN)* |
| **OpenVPN** | OpenVPN client for `.ovpn` profiles. Distro package on every family (EPEL on RHEL clones) *(VPN)* |
| **Opera** | Browser with built-in ad blocker and sidebar messengers. Opera's signed repository on Debian, Ubuntu, Fedora, RHEL clones (x86_64) and openSUSE; Flathub, else the AUR, on Arch; not available on Alpine *(Web Browsers)* |
| **PIA VPN** | Private Internet Access VPN client |
| **Proton Mail Bridge** | Local IMAP/SMTP gateway for Proton Mail — needs a paid plan |
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
| **Trojita** | Fast Qt-native IMAP client — Fedora, Arch (AUR), and openSUSE only |
| **UniFi Endpoint** | Ubiquiti's UniFi Identity VPN client for UniFi-managed networks — `.deb` / `.rpm` |
| **Vivaldi Browser** | Highly customizable Chromium browser |
| **WhatsApp** | ZapZap, an open-source desktop client that wraps WhatsApp Web (WhatsApp has no official Linux app). Distro package on openSUSE, Flathub elsewhere; not available on Alpine *(Messaging)* |
| **WireGuard Client** | Lightweight VPN client using WireGuard protocol |
| **WireGuard Server** | Sets up a WireGuard VPN server |
| **Zen Browser** | Privacy-focused Firefox-based browser with vertical tabs and split view (beta) |
| **Zoom** | Video conferencing and collaboration platform |

## Package Managers

Additional, cross-distro managers that run alongside the native package manager — the native one is never replaced or touched.

| Utility | Description |
|---------|-------------|
| **Flatpak Setup** | Configures Flatpak and adds the Flathub repository — the install path for several utilities here (Bottles, BoxBuddy, DistroShelf, Kontainer, Boxflat, Duplicati, ProtonUp-Qt) |
| **Homebrew** | Linuxbrew — installs into your home directory and runs entirely in user space; newer CLI tools without root. Cannot be installed as root |
| **Nix** | Purely-functional manager with reproducible, isolated, rollback-able installs, via the Determinate Systems installer |
| **Snap (snapd)** | Canonical's sandboxed self-contained apps; enables the snapd socket and `/snap` path automatically |
| **deb-get** | `apt-get`-style management of third-party .debs (Chrome, VS Code, Discord…) *(Debian/Ubuntu only)* |
| **Pacstall** | The "AUR for Ubuntu/Debian" — community build scripts (pacscripts) *(Debian/Ubuntu only)* |
| **yay** | Popular Go-based AUR helper wrapping pacman *(Arch family only)* |
| **paru** | Feature-rich Rust-based AUR helper, an alternative to yay *(Arch family only)* |

## Productivity

| Utility | Description |
|---------|-------------|
| **ArtCraft Launcher** | The launcher app that installs and updates the Craft apps — `.deb` / `.rpm` / AppImage with menu entry (Arch family) |
| **NVIDIA PAIR** | NVIDIA's Personal AI Router, which links home-network machines into one local AI inference cluster (Ollama, llama.cpp, LM Studio). Upstream ships a `.deb` only: installed as-is on Debian/Ubuntu, unpacked into `/opt/PAIR` elsewhere |
| **Audacity** | Open-source audio editor and recorder *(Video & Audio)* |
| **1Password** | Password manager and secrets vault. 1Password's own signed repository on Debian/Ubuntu, Fedora, RHEL clones and openSUSE (updates arrive with the system); AUR on Arch, only with AUR support enabled. Needs a 1Password account; not on Alpine. Uninstall keeps your account data *(Password Managers)* |
| **Anki** | Spaced-repetition flashcards with sync. Distro package on Arch and Alpine, otherwise Flathub. Uninstall keeps your decks *(Notes)* |
| **Bitwarden Client** | Open-source password manager — `.deb` / `.rpm` / AUR / snap / flatpak *(Password Managers)* |
| **Blender** | Free 3D creation suite — modelling, sculpting, animation, rendering and video editing. Distro package, Flathub where the repository has none *(Graphics & Photo)* |
| **Calibre** | E-book library manager and reader with format conversion and e-reader sync. Distro package, Flathub on RHEL clones; not on Alpine *(Documents & Reading)* |
| **Cryptomator** | Client-side encryption for cloud storage — vaults are ordinary folders your sync tool uploads. Flathub on every distro; not on Alpine. Uninstall keeps your vaults *(Encryption)* |
| **Darktable** | Open-source raw photo workflow and editor. Distro package, Flathub where the repository has none *(Graphics & Photo)* |
| **Euro-Office** | European community fork of ONLYOFFICE — **built from source**, since upstream ships no desktop binaries. Runs their `docker buildx bake` build and installs the resulting `.deb`/`.rpm` (AUR on Arch). Needs Docker + Buildx; the compile takes hours and tens of GB *(Office Suites)* |
| **Flameshot** | Feature-rich screenshot tool with annotation support |
| **GIMP** | GNU Image Manipulation Program *(Graphics & Photo)* |
| **HandBrake** | Open-source video transcoder *(Video & Audio)* |
| **Inkscape** | Professional vector graphics editor *(Graphics & Photo)* |
| **Joplin Client** | Note-taking app with Markdown and sync (AppImage) *(Notes)* |
| **Kdenlive** | Open-source video editor by KDE *(Video & Audio)* |
| **KeePassXC** | Offline password manager that keeps passwords in an encrypted file you control, with browser integration and TOTP. Distro package, Flathub where the repository has none. Uninstall keeps your database *(Password Managers)* |
| **Kodi** | Home-theater media center for local and network media. Distro package on Debian/Ubuntu and Arch, RPM Fusion Free on Fedora and RHEL clones, Flathub on openSUSE *(Media)* |
| **Krita** | Professional digital painting application *(Graphics & Photo)* |
| **Libation** | Audible audiobook manager — `.deb` / `.rpm` / AUR *(Media)* |
| **LibreOffice** | Open-source office suite — direct download / native packages / flatpak *(Office Suites)* |
| **Logseq** | Privacy-first knowledge management and outliner *(Notes)* |
| **Mark Text** | Simple and elegant Markdown editor *(Notes)* |
| **mpv** | Minimal, scriptable media player for nearly every video and audio format. Distro package, Flathub where the repository has none *(Media)* |
| **Multimedia Codecs** | Full audio and video codecs (H.264, HEVC, AAC and more) for FFmpeg and GStreamer apps. Fedora: enables RPM Fusion, replaces `ffmpeg-free` with the full `ffmpeg` and installs the `multimedia` group; RHEL clones: RPM Fusion for EL (with EPEL and CRB); Debian/Ubuntu and Arch: `ffmpeg` and the GStreamer plugin sets (Ubuntu needs universe); openSUSE: Packman through `opi codecs`. Uninstall is not offered, since media apps link against the codecs *(Media)* |
| **Nextcloud Desktop** | Sync client for self-hosted Nextcloud cloud storage |
| **OBS Studio** | Video recording and live streaming *(Video & Audio)* |
| **Obsidian** | Markdown-based knowledge base with graphs and plugins *(Notes)* |
| **Okular** | KDE's document viewer — PDF, ePub, comics, annotations and signatures; works on any desktop. Distro package, Flathub where the repository has none *(Documents & Reading)* |
| **OnlyOffice** | Office suite with MS Office format compatibility *(Office Suites)* |
| **RawTherapee** | Open-source raw photo developer. Distro package, Flathub where the repository has none (RHEL clones) *(Graphics & Photo)* |
| **Scribus** | Desktop publishing — page layout and print-ready PDFs. Distro package, Flathub where the repository has none *(Graphics & Photo)* |
| **Shotcut** | Cross-platform video editor with a multi-track timeline. Distro package, Flathub where the repository has none (RHEL clones) *(Video & Audio)* |
| **Spotify** | Spotify music streaming client — Flathub on every distro; not on Alpine. Needs a Spotify account. Uninstall keeps your login and cache *(Media)* |
| **Standard Notes** | End-to-end encrypted notes with cross-platform sync *(Notes)* |
| **VeraCrypt** | Disk and file encryption — containers, partitions and hidden volumes. Arch repository package; on Debian/Ubuntu (12/13, 22.04+), Fedora, RHEL clones and openSUSE the package from VeraCrypt's GitHub release, signature checked against its pinned key; not on Alpine *(Encryption)* |
| **VLC** | Versatile media player supporting virtually all formats *(Media)* |
| **WinApps** | Run Windows apps as native-feeling windows via a Windows VM + FreeRDP RemoteApp — installs prerequisites, writes a config template, and optionally creates the Windows VM via Docker/Podman (needs KVM; Windows licensed separately) |
| **WPS Office** | MS Office-compatible office suite *(Office Suites)* |
| **Xournal++** | Handwriting notebook and PDF annotator for pen tablets and touchscreens. Distro package, Flathub where the repository has none *(Notes)* |
| **Zotero** | Reference manager and research tool *(Documents & Reading)* |

## Remote Admin Tools

| Utility | Description |
|---------|-------------|
| **AnyDesk** | Remote desktop application *(Remote Access)* |
| **Cockpit** | Web-based server management console at `https://<host>:9090`; enables `cockpit.socket` and opens the firewall port *(Remote Access)* |
| **Devolutions RDM** | Remote Desktop Manager — Cloudsmith repo / AUR / flatpak / snap *(Remote Access)* |
| **Enable RDP** | Enables Remote Desktop Protocol access with xrdp or krdp (KDE's own server; the only one that works on Plasma 6.8+, which removed the X11 session xrdp needs). Uninstall can switch to the other server instead. With xrdp it also installs a polkit rule so seatless RDP sessions can manage NetworkManager without a password prompt *(Remote Access)* |
| **OpenSSH Server** | Secure Shell server for remote access *(Remote Access)* |
| **tmux** | Terminal multiplexer; SSH sessions survive dropped connections *(Remote Access)* |
| **tmux Resurrect** | Saves and restores tmux session layout across reboots *(Remote Access)* |
| **Remmina** | Remote desktop client (RDP, VNC, SSH, SPICE) *(Remote Access)* |
| **RustDesk** | Open-source remote desktop and remote assistance tool *(Remote Access)* |
| **Termius SSH Client** | Modern SSH client with cross-device sync *(Remote Access)* |
| **OpenRSAT** | Active Directory management console (Microsoft RSAT-like) from Tranquil IT — installs the latest GitHub release as a `.deb` (Debian/Ubuntu), `.rpm` (Fedora/RHEL x86_64), or standalone binary (openSUSE); not available on Arch |

## File Managers

| Utility | Description |
|---------|-------------|
| **Nautilus** | GNOME's default file manager (Files) — simple GTK interface with sidebar and network browsing *(Graphical)* |
| **Dolphin** | KDE Plasma's default file manager — split views, tabs, embedded terminal and KIO protocols (`sftp://`, `smb://`) *(Graphical)* |
| **Thunar** | Xfce's fast, lightweight file manager with bulk rename and custom actions *(Graphical)* |
| **Nemo** | Cinnamon's file manager, a Nautilus fork with dual-pane view and an editable address bar *(Graphical)* |
| **Caja** | MATE's file manager, a GNOME 2-era fork with dual-pane view and plugins *(Graphical)* |
| **PCManFM-Qt** | LXQt's very lightweight file manager with tabs, dual panes and trash *(Graphical)* |
| **Krusader** | Twin-panel file manager for KDE in the style of Total Commander — archives, batch rename, comparison and sync *(Graphical)* |
| **Midnight Commander** | Classic text-mode twin-panel file manager (`mc`) with built-in editor and FTP/SFTP *(Terminal)* |
| **Ranger** | Vim-style terminal file manager with Miller columns and previews *(Terminal)* |
| **nnn** | Tiny, fast terminal file manager with optional previews and plugins *(Terminal)* |
| **Superfile** | Modern terminal file manager (`spf`) with multiple panes, previews, fuzzy search and themes *(Terminal)* |

Any of these runs on any desktop; the desktop-named ones pull in that desktop's libraries.

## Firewalls

| Utility | Description |
|---------|-------------|
| **Gufw (Firewall GUI)** | Graphical front-end for UFW — status, rules and app profiles; installs UFW first if needed |
| **firewalld** | Zone-based firewall daemon, the default on Fedora, RHEL and openSUSE; disables UFW first if it is active |
| **firewall-config (GUI)** | Graphical tool for firewalld zones, services, ports and rich rules; installs firewalld first if needed |

UFW Firewall is listed under [System Tasks](#system-tasks).

## Login Screens

| Utility | Description |
|---------|-------------|
| **SDDM** | Qt display manager used by KDE Plasma and LXQt; enabled when no login screen is active, otherwise asks first. Reboot to use it *(Display Managers)* |
| **GDM** | GNOME's GTK display manager (`gdm3` on Debian/Ubuntu, `gdm` elsewhere) *(Display Managers)* |
| **LightDM** | Lightweight cross-desktop display manager, installed with a GTK greeter *(Display Managers)* |
| **ly** | Minimal text-mode display manager that needs no X/Wayland greeter; packaged on Arch and openSUSE only *(Display Managers)* |
| **LXDM** | Lightweight GTK display manager from LXDE *(Display Managers)* |
| **SDDM Breeze Theme** | Sets KDE's Breeze as the SDDM login theme through an `/etc/sddm.conf.d` drop-in *(SDDM Themes)* |
| **SDDM Sugar Candy** | Configurable QtQuick SDDM theme with a blurred background, downloaded from GitHub *(SDDM Themes)* |
| **SDDM Astronaut** | QtQuick SDDM theme bundle in several sci-fi styles, downloaded from GitHub *(SDDM Themes)* |
| **LightDM Slick Greeter** | The themeable GTK greeter used by Linux Mint, selected for LightDM through a drop-in *(LightDM Greeters)* |

## System Tools

| Utility | Description |
|---------|-------------|
| **ClamAV** | Open-source antivirus engine — prompts for a desktop front-end, defaulting to ClamUI (Flathub) |
| **CUPS** | The printing system; starts at boot, printers are added at `http://localhost:631` |
| **Input Leap** | Software KVM — share keyboard and mouse across machines |
| **OCCT** | CPU/RAM/GPU stability and stress testing — free Personal edition, x86_64 binary from ocbase.com, installed per-user under `~/.local/share/occt` |

Grouped into folders inside the System Tools tab:

### Monitors

Resource, GPU and task monitors.

| Utility | Description |
|---------|-------------|
| **Btop** | Terminal-based resource monitor with rich visuals |
| **htop** | Interactive process viewer |
| **nvtop** | `htop` for GPUs (NVIDIA, AMD, Intel); not available on Alpine |
| **GPU Task Manager** | Terminal task manager for the GPU (`gputaskman`): per-process VRAM and GPU load, and which runtimes and model files use it — NVIDIA, AMD (amdgpu) and Intel (i915). Upstream's portable build, SHA-256 checked, installed per user in `~/.local/opt/gputaskman`; needs glibc 2.35 or newer (not Rocky/RHEL 9) |
| **TMOG** | Native Qt task manager with real-time system metrics — no repo, AUR, or checksums upstream; installed from tmog.org's `.deb` on Debian/Ubuntu, AppImage elsewhere |
| **Stacer** | Graphical system optimizer and monitor |

### Power & Memory

Battery, CPU power and memory-pressure tools.

| Utility | Description |
|---------|-------------|
| **TLP** | Laptop battery and power tuning, started at boot. Replaces power-profiles-daemon, cannot run beside auto-cpufreq; not available on Rocky/Alma 10, where EPEL has no package |
| **auto-cpufreq** | Adjusts CPU speed and power use to the battery and load, with a background service, for laptops. Arch: the AUR (only with AUR support on). Elsewhere upstream's own installer runs from the GitHub release into `/opt/auto-cpufreq` — upstream publishes no checksum. Cannot run beside TLP; not available on Alpine, on openSUSE Leap (upstream's installer cannot find its Python packages) or on Rocky/Alma 8 and 9 (the program needs Python 3.10) |
| **zram** | Compressed swap in RAM. `zram-tools` on Debian/Ubuntu, `zram-generator` elsewhere (half of RAM, at most 4 GiB, unless a config already exists); not available on Alpine |
| **earlyoom** | Ends the biggest memory hog before the machine freezes; started at boot |

### Disk & Cleanup

Drive health, disk usage and cleaning.

| Utility | Description |
|---------|-------------|
| **smartmontools** | `smartctl` and `smartd` for drive health; services left as the package sets them |
| **ncdu** | Terminal disk-usage browser |
| **Filelight** | Disk usage analyzer with interactive sunburst chart |
| **BleachBit** | Disk cleaner for caches, logs, history and temporary files. Distro package (EPEL on Rocky/Alma 8 and 9), Flathub on Rocky/Alma 10; not available on Alpine |

### System Info

Hardware and system information.

| Utility | Description |
|---------|-------------|
| **Fastfetch** | Fast system information display tool |
| **inxi** | Readable hardware and system summary (`inxi -Fxz`); not available on Rocky/Alma 10, where EPEL has no package |
| **HardInfo** | System profiler and benchmark window. Installs HardInfo2 (the old HardInfo on Ubuntu 22.04); EPEL on Rocky/Alma; not available on Alpine |
| **CPU-X** | CPU-Z-style window for CPU, motherboard, memory and GPU details. Distro package, Flathub on Rocky/Alma/RHEL; not available on Alpine |

### Shell Tools

Command-line helpers and shells.

| Utility | Description |
|---------|-------------|
| **bat** | `cat` with syntax highlighting, line numbers and Git change markers — on Debian/Ubuntu, where the command is `batcat`, a `bat` link to it is added in `~/.local/bin` |
| **ripgrep** | `rg`: searches a folder tree for text much faster than `grep -r`, skipping files in `.gitignore` |
| **Pay Respects** | Press `F` to fix the last failed command — Rust `thefuck` replacement with inline `Ctrl+X` correction. Installed from upstream's `.deb`/`.rpm` (in no distro repo; AUR on Arch) and wired into `~/.bashrc`/`~/.zshrc`; its AI module is disabled by default |
| **Zsh + Oh My Zsh** | Z shell with Oh My Zsh framework, themes, and plugins |
| **fzf** | Command-line fuzzy finder with Ctrl+R / Ctrl+T / Alt+C in the shell (loaded from `~/.bashrc`, and `~/.zshrc` when it exists) |
| **eza** | `ls` replacement with colours, icons and git status. Distro package where there is one; elsewhere the GitHub release, SHA-256 checked (x86_64 only) |
| **zoxide** | Smarter `cd`: jump to frequently used folders with `z`. Distro package (every release except Rocky/Alma 10); elsewhere the GitHub release, SHA-256 checked. Loaded from the shell profile |
| **starship** | Fast, themeable shell prompt. Distro package where there is one; elsewhere the GitHub release, SHA-256 checked. Loaded from the shell profile |
| **tldr** | Short, example-first help pages for commands (`tldr tar`). The distro's client: tealdeer, tlrc or the Python tldr (EPEL on Rocky/Alma); not available on Alpine |

### Terminal Emulators

| Utility | Description |
|---------|-------------|
| **Alacritty** | GPU-accelerated terminal emulator configured by a text file. Distro package; not offered on Rocky/Alma/RHEL or Ubuntu 22.04, which have none |
| **Ghostty** | Fast GPU-accelerated terminal emulator. From the distro package: Arch, openSUSE Tumbleweed, Ubuntu 26.04 and newer. Upstream publishes no Linux packages, so elsewhere it says so and changes nothing; not offered on Fedora, Rocky/Alma/RHEL or Alpine |
| **kitty** | GPU-accelerated terminal emulator with tabs, splits and image display |
| **WezTerm** | GPU-accelerated terminal emulator configured in Lua. Offered on Arch, openSUSE and Alpine only: upstream's stable build is from 2024 and its other channels are nightlies |

### Kernel Managers

Tools for installing and switching alternate kernels. Each is listed on every distro but installs only on the family it supports (warning and stopping otherwise).

| Utility | Description |
|---------|-------------|
| **Mainline** | Ubuntu mainline-kernel installer (cappelikan/bkw777 fork of ukuu) — GUI + CLI for kernels from kernel.ubuntu.com. Debian/Ubuntu only (PPA, or upstream `.deb` fallback) |
| **CachyOS Kernel Manager** | GUI to install/build/swap kernels on Arch (also configures sched-ext). Ships only in the CachyOS repo, not the AUR; installs where that repo is enabled |
| **Fedora Mainline Kernel** | Enables the `@kernel-vanilla/mainline` Copr and installs the latest upstream mainline kernel. Fedora only (requires Secure Boot disabled) |
| **linux-tkg** | Frogging-Family custom-kernel **builder** — compiles a kernel from source with your choice of scheduler (BORE/EEVDF/PDS), compiler, and config. Cross-distro (Arch via makepkg; Debian/Ubuntu, Fedora, openSUSE via `install.sh`). Interactive, long compile |

## Window Managers

| Utility | Description |
|---------|-------------|
| **awesome** | Highly configurable X11 window manager with dynamic tiling, configured in Lua |
| **bspwm** | X11 tiling window manager that arranges windows as a binary tree, controlled by `bspc`; installs `sxhkd` for keybindings |
| **dwm** | Suckless dynamic X11 window manager; the packaged build is stock, changes need editing `config.h` and recompiling |
| **Hyprland** | Animated Wayland tiling compositor — Arch, Fedora, openSUSE Tumbleweed and Ubuntu 24.04+; not RHEL or Debian stable |
| **i3** | Classic X11 tiling window manager with simple text configuration |
| **Openbox** | Minimal, fast X11 stacking window manager with XML configuration |
| **Sway** | Wayland tiling compositor, a drop-in replacement for i3 that reads i3 configs |

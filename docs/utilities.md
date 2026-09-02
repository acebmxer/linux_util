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
| [System Tools](#system-tools) | | |

> **Incomplete:** 226 utilities and system tasks are registered in
> `lib/installers.sh`; 188 are listed below. The **File Managers**, **Firewalls**,
> **Login Screens** and **Window Managers** categories have no table here at all,
> and a handful of entries in the documented categories are missing too (Angry IP
> Scanner, Brave Debloat, LocalSend, PowerShell, Snapper GUI, fail2ban,
> Unattended Upgrades, GTK Window Fix). Run `./linux_util.sh --list` for the
> authoritative list.

## System Tasks

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
| **UFW Firewall** | Installs and configures Uncomplicated Firewall with sensible defaults |
| **Num Lock at Boot** | Enables Num Lock on TTY consoles and the display manager login screen |
| **Local Time Zone / Locale** | Interactive wizard to set system time zone, locale, or both |
| **Window Button Layout** | Restores minimize/maximize/close on window title bars for GTK apps (GNOME/Cinnamon/MATE/Xfce); fixes the missing buttons seen on Ubuntu under WSLg |
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
| **AMD Drivers** | Installs open-source AMD GPU drivers (AMDGPU/Mesa) |
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
| **Déjà Dup** | Simple GNOME backup tool with cloud and local storage support |
| **Kup** | KDE backup tool — incremental (bup) or synchronized (rsync) backups via System Settings |
| **Vorta** | Borg Backup GUI — deduplicating, encrypted backups |
| **Duplicati** | Browser-based backup tool with cloud provider support |

## Disk Utilities

| Utility | Description |
|---------|-------------|
| **GParted** | Graphical partition editor — create, resize, move, and delete partitions |
| **Ventoy** | Bootable USB tool — boot multiple ISOs from one drive |
| **Btrfs Assistant** | GUI for managing Btrfs subvolumes and Snapper snapshots *(Btrfs Tools)* |
| **btrfsmaintenance** | Automates scheduled Btrfs scrub, balance, trim, and defrag *(Btrfs Tools)* |
| **btrbk** | Btrfs snapshot and backup tool with remote send/receive *(Btrfs Tools)* |
| **duperemove** | Extent-based deduplication tool for Btrfs *(Btrfs Tools)* |

## Development

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
| **VSCodium** | Telemetry-free community build of VS Code (Open VSX extensions) |

## Gaming

| Utility | Description |
|---------|-------------|
| **Bottles** | Wine prefix manager for running Windows software |
| **Boxflat** | Settings manager for Moza Racing sim-racing hardware (Flatpak) |
| **Feral Gamemode** | Optimizes system performance while gaming |
| **Heroic Games Launcher** | Open-source launcher for Epic, GOG, and Amazon Prime Gaming |
| **Lutris** | Open gaming platform for multiple game sources |
| **MangoHud** | Vulkan/OpenGL overlay for FPS, frame times, and hardware monitoring |
| **ProtonUp-Qt** | Manages Proton-GE and Wine-GE compatibility layers |
| **Steam App** | Valve's gaming platform — native packages / RPM Fusion / flatpak |
| **Wine** | Compatibility layer for running Windows applications and games on Linux |

## Internet

| Utility | Description |
|---------|-------------|
| **Betterbird** | Thunderbird fork with extra fixes and features — Flatpak / AUR |
| **Bitwarden Extension** | Bitwarden browser extension installer |
| **Brave Browser** | Privacy-focused Chromium browser with built-in ad blocking |
| **Brave Origin** | Streamlined Brave build without Rewards, Wallet, VPN, and Leo AI |
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
| **NeoMutt** | Terminal email client, a maintained fork of Mutt |
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
| **WireGuard Client** | Lightweight VPN client using WireGuard protocol |
| **WireGuard Server** | Sets up a WireGuard VPN server |
| **Zen Browser** | Privacy-focused Firefox-based browser with vertical tabs and split view (beta) |
| **Zoom** | Video conferencing and collaboration platform |

## Package Managers

Additional, cross-distro managers that run alongside the native package manager — the native one is never replaced or touched.

| Utility | Description |
|---------|-------------|
| **Flatpak Setup** | Configures Flatpak and adds the Flathub repository — the install path for several utilities here (Bottles, BoxBuddy, DistroShelf, Boxflat, Duplicati, ProtonUp-Qt) |
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
| **Audacity** | Open-source audio editor and recorder |
| **Bitwarden Client** | Open-source password manager — `.deb` / `.rpm` / AUR / snap / flatpak |
| **Euro-Office** | European community fork of ONLYOFFICE — **built from source**, since upstream ships no desktop binaries. Runs their `docker buildx bake` build and installs the resulting `.deb`/`.rpm` (AUR on Arch). Needs Docker + Buildx; the compile takes hours and tens of GB |
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
| **WinApps** | Run Windows apps as native-feeling windows via a Windows VM + FreeRDP RemoteApp — installs prerequisites, writes a config template, and optionally creates the Windows VM via Docker/Podman (needs KVM; Windows licensed separately) |
| **WPS Office** | MS Office-compatible office suite |
| **Zotero** | Reference manager and research tool |

## Remote Admin Tools

| Utility | Description |
|---------|-------------|
| **AnyDesk** | Remote desktop application *(Remote Access)* |
| **Cockpit** | Web-based server management console at `https://<host>:9090`; enables `cockpit.socket` and opens the firewall port *(Remote Access)* |
| **Devolutions RDM** | Remote Desktop Manager — Cloudsmith repo / AUR / flatpak / snap *(Remote Access)* |
| **Enable RDP** | Enables Remote Desktop Protocol access via XRDP server; also installs a polkit rule so seatless RDP sessions can manage NetworkManager without a password prompt *(Remote Access)* |
| **OpenSSH Server** | Secure Shell server for remote access *(Remote Access)* |
| **Remmina** | Remote desktop client (RDP, VNC, SSH, SPICE) *(Remote Access)* |
| **RustDesk** | Open-source remote desktop and remote assistance tool *(Remote Access)* |
| **Termius SSH Client** | Modern SSH client with cross-device sync *(Remote Access)* |
| **OpenRSAT** | Active Directory management console (Microsoft RSAT-like) from Tranquil IT — installs the latest GitHub release as a `.deb` (Debian/Ubuntu), `.rpm` (Fedora/RHEL x86_64), or standalone binary (openSUSE); not available on Arch |

## System Tools

| Utility | Description |
|---------|-------------|
| **Btop** | Terminal-based resource monitor with rich visuals |
| **ClamAV** | Open-source antivirus engine — prompts for a desktop front-end, defaulting to ClamUI (Flathub) |
| **Fastfetch** | Fast system information display tool |
| **Filelight** | Disk usage analyzer with interactive sunburst chart |
| **Input Leap** | Software KVM — share keyboard and mouse across machines |
| **OCCT** | CPU/RAM/GPU stability and stress testing — free Personal edition, x86_64 binary from ocbase.com, installed per-user under `~/.local/share/occt` |
| **Pay Respects** | Press `F` to fix the last failed command — Rust `thefuck` replacement with inline `Ctrl+X` correction. Installed from upstream's `.deb`/`.rpm` (in no distro repo; AUR on Arch) and wired into `~/.bashrc`/`~/.zshrc`; its AI module is disabled by default |
| **Stacer** | Graphical system optimizer and monitor |
| **Zsh + Oh My Zsh** | Z shell with Oh My Zsh framework, themes, and plugins |

Grouped under a **Kernel Managers** folder inside the System Tools tab — tools for installing and switching alternate kernels. Each is listed on every distro but installs only on the family it supports (warning and stopping otherwise):

| Utility | Description |
|---------|-------------|
| **Mainline** | Ubuntu mainline-kernel installer (cappelikan/bkw777 fork of ukuu) — GUI + CLI for kernels from kernel.ubuntu.com. Debian/Ubuntu only (PPA, or upstream `.deb` fallback) |
| **CachyOS Kernel Manager** | GUI to install/build/swap kernels on Arch (also configures sched-ext). Ships only in the CachyOS repo, not the AUR; installs where that repo is enabled |
| **Fedora Mainline Kernel** | Enables the `@kernel-vanilla/mainline` Copr and installs the latest upstream mainline kernel. Fedora only (requires Secure Boot disabled) |
| **linux-tkg** | Frogging-Family custom-kernel **builder** — compiles a kernel from source with your choice of scheduler (BORE/EEVDF/PDS), compiler, and config. Cross-distro (Arch via makepkg; Debian/Ubuntu, Fedora, openSUSE via `install.sh`). Interactive, long compile |


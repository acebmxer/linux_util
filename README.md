# Linux System Setup & Utilities Installer

[![CI](https://github.com/acebmxer/linux_util/actions/workflows/ci.yml/badge.svg)](https://github.com/acebmxer/linux_util/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Shell: Bash](https://img.shields.io/badge/shell-bash-4EAA25?logo=gnubash&logoColor=white)](linux_util.sh)
[![Platform: Linux](https://img.shields.io/badge/platform-linux-333333?logo=linux&logoColor=white)](#supported-distributions)

An interactive multi-select TUI for installing, uninstalling, and updating system
tasks and utilities across all major Linux distributions. Over 100 utilities
organized by category, automatic pre-operation snapshots, and full CLI automation
for unattended use.

```bash
git clone https://github.com/acebmxer/linux_util.git
cd linux_util
chmod +x linux_util.sh
./linux_util.sh
```

Run with no options and you get the menu. Every action is also a flag, for
scripting and automation.

## Read next

| Topic | Page |
| --- | --- |
| Everything it can install, by category | [docs/utilities.md](docs/utilities.md) |
| The menu — controls, selection logic, profiles | [docs/menu.md](docs/menu.md) |
| Config file, logging, shell completions | [docs/configuration.md](docs/configuration.md) |
| Running under WSL | [docs/wsl.md](docs/wsl.md) |
| Something went wrong | [docs/troubleshooting.md](docs/troubleshooting.md) |
| Adding a utility, code style, tests | [CONTRIBUTING.md](CONTRIBUTING.md) |

## Requirements

- Bash 4.0+
- `sudo` access (do **not** run as root)
- An interactive terminal (for the TUI menu)
- Internet connection for downloads
- Arch-based distros: `yay` or `paru` recommended for AUR packages

---

## The menu

```
┌─────────────────────────────────┬────────────────────────────────────────────────────────────────┐
│ linux_util (main: a1b2c3)       │ SEARCH  Type to search (/)                                     │
│ By: PozzaTech                   │                                                                │
├─────────────────────────────────┼────────────────────────────────────────────────────────────────┤
│ CATEGORIES                      │  Internet ─────────────────────────────────────────────────────┤
├─────────────────────────────────┤ > [D]  Web Browsers                                            │
│   System Tasks                  │   [D]  Web Browser Tweaks                                      │
│   Backup                        │   [D]  Web Browser Extensions                                  │
│   Bootloaders                   │   [D]  Messaging                                               │
│   Desktop Environments          │   [D]  Email Clients                                           │
│   Development                   │   [D]  File Transfer                                           │
│   Disk Utilities                │   [D]  VPN                                                     │
│   Drivers                       │   [ ] Angry IP Scanner                                         │
│   File Managers                 │   [ ] QBittorrent                                              │
│   Firewalls                     │   [ ] Syncthing                                       (v2.1.3) │
│   Gaming                        │                                                                │
│ > Internet                      │                                                                │
│   Login Screens                 │                                                                │
│   Package Managers              │                                                                │
│   Productivity                  │                                                                │
│   Remote Admin Tools            │                                                                │
│   System Tools                  │                                                                │
│   Window Managers               │                                                                │
├─────────────────────────────────┤                                                                │
│ PROFILES                        │                                                                │
├─────────────────────────────────┤                                                                │
│ > Run Me First                  │                                                                │
│   Default VM Server Profile     │                                                                │
│   Default Physical PC           │                                                                │
│   Developer Workstation         │                                                                │
│   Home Desktop                  │                                                                │
├─────────────────────────────────┤                                                                │
│ SYSTEM DETAILS                  │────────────────────────────────────────────────────────────────┤
├─────────────────────────────────┤  Browse 10 item(s) in the Web Browsers subcategory.            │
│    Host: linux-pc               │                                                                │
│      OS: Arch Linux             │                                                                │
│  Kernel: 6.12.8-1               │                                                                │
│     CPU: Intel Core i9-14900K   │                                                                │
│     GPU: NVIDIA GeForce RTX 4070│                                                                │
│     Mem: 8.2G / 32G             │                                                                │
│    Disk: 245G / 500G (49%)      │                                                                │
│  Uptime: 3d 12h                 │                                                                │
├─────────────────────────────────┴────────────────────────────────────────────────────────────────┤
│ Actions: Install: 0 | Uninstall: 0 | Update: 0                                                   │
│ [↑↓] Navigate  [Space] Select  [U] Update  [/] Search  [Enter] Confirm  [Tab] Focus  [Q] Quit    │
└──────────────────────────────────────────────────────────────────────────────────────────────────┘
```

Arrow keys move, **Space** ticks an item, **U** queues an installed item for
update, **Enter** runs everything ticked, **/** searches every category, **Q**
quits. A ticked item that is already installed is *uninstalled* — the checkbox
means "change this", not "install this".

Subcategories (marked `[D]`) group related items — press Enter to drill in.
**Profiles** in the left sidebar queue a curated set in one step. Full key list,
selection rules and the profile table: [docs/menu.md](docs/menu.md).

---

## What it installs

| Category | Covers |
| --- | --- |
| **System Tasks** | Updates and repo repair, broken-package fixes, drive/NFS/SMB mounts, UFW, time zone and locale, Num Lock, assorted distro fixes |
| **Bootloaders** | GRUB, Limine, systemd-boot, switching between them, and five GRUB theme packs |
| **Drivers** | NVIDIA, AMD GPU, Intel and AMD microcode, LACT, OpenLogi, Thermalright TRCC, XEN guest tools |
| **Desktop Environments** | KDE Plasma, GNOME, Xfce, Cinnamon, MATE, LXQt, Budgie, COSMIC, Deepin, Pantheon |
| **Backup** | Timeshift and Snapper (create/restore/delete), Déjà Dup, Kup, Vorta, Duplicati |
| **Disk Utilities** | GParted, Ventoy, and a Btrfs toolset (Assistant, btrfsmaintenance, btrbk, duperemove) |
| **Development** | Docker, Podman, Distrobox, VS Code, VSCodium, Cursor, Claude Code, Node/NVM, Go, Rust, pyenv, Terraform, OpenTofu, Ansible, kubectl, k9s, DBeaver, Virt-Manager |
| **Gaming** | Steam, Lutris, Heroic, Bottles, Wine, ProtonUp-Qt, MangoHud, Gamemode, Boxflat |
| **Internet** | Browsers (Firefox, Brave, Chrome, Chromium, Vivaldi, LibreWolf, Zen, Thorium, Tor), email clients, messaging, and VPNs (ProtonVPN, PIA, Tailscale, WireGuard) |
| **Package Managers** | Flatpak, Homebrew, Nix, Snap, deb-get, Pacstall, yay, paru — added alongside the native manager, never replacing it |
| **Productivity** | LibreOffice, OnlyOffice, WPS, GIMP, Inkscape, Krita, Kdenlive, OBS, VLC, Obsidian, Joplin, Logseq, Bitwarden, Nextcloud, WinApps |
| **Remote Admin** | Cockpit, XRDP, OpenSSH, Remmina, RustDesk, AnyDesk, Termius, Devolutions RDM, OpenRSAT |
| **File Managers** | Nautilus, Dolphin, Thunar, Nemo, Caja, PCManFM-Qt, Krusader, and the terminal managers (Midnight Commander, Ranger, nnn) |
| **Firewalls** | UFW and firewalld, each with its GUI front end (Gufw, firewall-config) |
| **Login Screens** | SDDM, GDM, LightDM, ly, LXDM, plus SDDM themes and the LightDM Slick Greeter |
| **Window Managers** | Hyprland, Sway, i3, bspwm, awesome, dwm, Openbox |
| **System Tools** | Btop, Fastfetch, ClamAV, Stacer, Filelight, Input Leap, OCCT, Pay Respects, Zsh + Oh My Zsh, and a Kernel Managers folder |

Every entry, with its per-utility description and any distro limits, is in
[docs/utilities.md](docs/utilities.md). For what is installed on *this* machine,
run `./linux_util.sh --list`.

---

## Command-line use

```
./linux_util.sh [options]

  -h, --help              Show usage information
      --version           Show script version (release tag, or commit between releases)
      --list              List all utilities with current install status
      --install <name>    Install a utility by name
      --uninstall <name>  Uninstall a utility by name
      --update <name>     Update a utility by name
      --update-all        Update every currently installed utility
      --check <name>      Exit 0 if installed, 1 if not
      --dry-run           Preview actions without making any changes
      --verbose           Extra status messages
      --debug             Internal state details
      --no-color          Disable coloured output
      --setup-logrotate   Install logrotate config for linux_util logs
```

Utility names are matched case-insensitively and support partial matches.
`--dry-run` can be combined with any action flag.

```bash
./linux_util.sh --list
./linux_util.sh --check "Docker"
./linux_util.sh --install "Visual Studio Code"
./linux_util.sh --dry-run --update-all
```

Tab-completion for bash and zsh ships in `completions/` — setup is in
[docs/configuration.md](docs/configuration.md#shell-completions).

---

## Supported distributions

| Family | Distributions | Package manager |
|--------|--------------|-----------------|
| Debian/Ubuntu | Ubuntu, Debian, Linux Mint, Pop!\_OS, elementary OS, Zorin, Kali, KDE neon | `apt` |
| Fedora | Fedora | `dnf` |
| RHEL | RHEL, CentOS, Rocky Linux, AlmaLinux, Oracle Linux | `dnf` / `yum` |
| Arch | Arch Linux, Manjaro, EndeavourOS, Garuda, Artix, CachyOS | `pacman` + AUR |
| openSUSE | openSUSE Leap, Tumbleweed, SLES | `zypper` |

Unrecognised distributions are matched via `ID_LIKE` in `/etc/os-release`, then
by auto-detecting the available package manager.

The script also runs under **WSL2**, which it detects automatically and adapts
to — most visibly, "reboot" restarts the distribution rather than the machine.
See [docs/wsl.md](docs/wsl.md).

---

## Automatic snapshots

A system snapshot is taken before every install, uninstall, or update, giving
you a rollback point.

| Tool | Distros | Notes |
|------|---------|-------|
| **Timeshift** | All supported distros | Used whenever `timeshift` is installed |
| **Snapper** | Arch-based (CachyOS, Manjaro, …) | Fallback when Timeshift is absent and Snapper has a root config |

Whichever is available is detected automatically; Timeshift configures its
backup device on first use. Each snapshot is tagged with the operation that
triggered it (e.g. `linux_util: Install Docker`), and **Create Snapshot** /
**Restore Snapshot** are also available as System Tasks — a restore always takes
a safety snapshot first. Snapshotting is non-blocking: if it fails, the
operation still proceeds.

---

## Logs and configuration

Every run writes timestamped logs to `logs/`, with `success_latest.log` and
`error_latest.log` symlinked to the most recent pair. `./manage_logs.sh` lists,
views, tails, searches, and prunes them.

Behaviour is tuned with an optional config file:

```bash
cp linux_util.conf.example linux_util.conf
```

It controls log retention and level, confirmation prompts, retry behaviour, the
DNS and free-disk pre-flight checks, and backups. Full setting table:
[docs/configuration.md](docs/configuration.md).

---

## Something not working?

Common problems — the script refusing to run, failed package installs, AUR
support being off by default, and the password prompts that appear inside xrdp
sessions — are covered in
[docs/troubleshooting.md](docs/troubleshooting.md).

## Contributing

Project layout, how to add a new utility installer, code style, and the test
suite are in [CONTRIBUTING.md](CONTRIBUTING.md).

```bash
bash tests/test_linux_util.sh
```

## License

This project is licensed under the [MIT License](LICENSE).

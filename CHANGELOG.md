# Changelog

All notable changes to this project are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
This project does not tag semantic-version releases — `linux_util.sh --version`
reports the current git commit — so changes are grouped by month, newest first.
Add new entries under **[Unreleased]** as work lands; move them into a dated
section when a batch is cut.

## [Unreleased]

- **Fixed** — **Cockpit** now has a description in the TUI. It was registered
  with a category and subcategory but no `UTILITY_DESCRIPTION`, so highlighting
  it rendered an empty description pane — `menu.sh` falls back to `""` for a
  missing key rather than erroring, so the gap was silent. Cockpit was the only
  one of the 190 registered utilities affected. Added a test that diffs the
  `UTILITY_CATEGORY` key set against the `UTILITY_DESCRIPTION` key set, so a
  utility registered without a description now fails the suite instead of
  shipping a blank pane.
- **Changed** — **Termius** on Fedora, RHEL and openSUSE now installs natively
  into `/opt/Termius` by unpacking the upstream `.deb`, instead of using
  Flathub. The Flatpak's `/usr` belongs to the `org.freedesktop.Platform`
  runtime rather than the host, and its manifest grants no filesystem access at
  all, so the built-in local terminal could never reach the user's shell and
  permanently pinned `/bin/sh` as its "Local Terminal Path". The native install
  sees the real `/usr` and picks up `$SHELL` the same way the Debian package
  does. Existing Flatpak and snap copies are detected and reported with removal
  instructions rather than being removed automatically.
- **Fixed** — **xrdp** on Fedora and RHEL now installs `xorgxrdp` (and
  `xrdp-selinux`) alongside `xrdp`. Unlike Debian, the Fedora/EPEL `xrdp`
  package does not pull in the Xorg backend that sesman launches per session,
  and `xrdp-selinux` is only a weak dependency — without them every login failed
  with "X server could not be started".
- **Added** — **Firewalls** category with four installable utilities: **UFW**,
  **Gufw** (UFW's GTK frontend), **firewalld**, and **firewall-config**
  (firewalld's GUI). UFW moved out of System Tasks into this category, and Gufw
  is now its own registry entry rather than being auto-installed as a side
  effect of the UFW task. Installing UFW disables an active firewalld and vice
  versa, so only one firewall manager is ever running.
- **Fixed** — **Stacer** on the rpm family now installs as a self-contained
  AppImage. The upstream `.rpm` is unsigned and rpm >= 6 rejects it outright,
  and Flathub has never carried a Stacer package, so both prior approaches were
  dead ends. This also fixes the openSUSE fallback path. Additionally,
  `pkg_get_version` no longer leaks rpm's "package X is not installed" message
  into the returned version string on rpm/dnf/zypper systems.
- **Changed** — `--version` now reports the release tag via `git describe`
  (e.g. `v1.0.0`, or `v1.0.0-5-g<hash>` between releases) instead of a bare
  commit hash.

## [1.0.0] - 2026-07-18

First tagged release. See the dated sections below for the full history leading up
to this release.

### Added
- **Boxflat** installer under the **Gaming** category — settings manager for Moza
  Racing sim-racing hardware (wheelbase, wheel, pedals, shifter). Installed via
  Flatpak from Flathub by default, with a `boxflat-git` AUR fallback on Arch when
  Flatpak is unavailable. Registered in the "Gaming Utilities" subcategory and
  added to the shell-completion lists.

### Fixed
- Self-update no longer drags a pinned checkout back onto `main`. When launched
  from a detached HEAD (e.g. after `git checkout v1.0.0`), it now recognises the
  pin, skips the auto-pull, and reports the pinned ref — making tagged releases
  usable as frozen versions. Run from a branch to resume rolling updates.

## 2026-07

### Added
- Config editor for `unattended-upgrades`.
- OCCT stability-testing tool installer.
- UniFi Endpoint and Libation installers.
- Fedora/RHEL and openSUSE support for the krdp RDP server.
- fwupd firmware-update support in the system-updates task.
- Kup KDE backup tool support.

### Fixed
- xrdp: install the KDE X11 packages and open the firewall port.
- System updates/snapshots: clean only dnf/yum packages and include Flatpak.

## 2026-06

### Added
- **Bootloaders** category: GRUB, Limine, and systemd-boot installers with config
  generation, plus initramfs repair.
- GRUB theme utilities and a GRUB Theme Selector to switch installed themes.
- **Kernel Managers** subcategory (four kernel tools).
- **Login Screens** category (display managers and themes).
- Distrobox, BoxBuddy, and DistroShelf installers.
- Zen Browser installer with extension-policy support; Brave Origin browser support.
- Cockpit web-based server management utility.
- WSL support: environment detection, reboot handling, and the GTK Window Fix task.
- Minimal/standard/full install-tier selection.
- Package-repair tasks, the Delete Default Cloud-Init User task, and the Fix RDP
  Kerberos Delay task.
- OpenRSAT installer and a reorganised Remote Admin Tools category.

### Fixed
- Numerous SDDM, KDE, btrfs, Docker, Fedora, GRUB, Limine, AUR, and LACT fixes;
  honour `/var/run/reboot-required` on Debian/Ubuntu; skip flock for read-only
  commands.

## 2026-05

### Added
- **Package Managers** category (7 cross-distro tools).
- **Disk Utilities** category (GParted) and **File Managers** / **Window Managers**
  categories.
- Interactive Zsh theme selector with Powerlevel10k support.
- CachyOS-specific support across multiple installers.
- ClamAV daemon enablement and ClamTK preference configuration.
- Syncthing folder-setup wizard as a standalone task.
- Angry IP Scanner, LibreWolf, Thorium, and Brave Debloat utilities.
- Locale auto-generation on minimal systems.
- Expanded btrfs/Snapper snapshot support (Debian/Ubuntu and Fedora).

### Fixed
- Reboot via `systemctl`, lock-fd release before reboot, apt cache-freshness
  checks, and safe handling of empty mount options.

## 2026-04

### Added
- **Desktop Environments** category with distro-aware DE registration.
- **Backup** category (Déjà Dup, Vorta, Duplicati, Snapper) and snapshot tools.
- Browser-extension utilities with subcategory ordering.
- Profiles system with curated installation presets and export/import.
- Large utility-registry expansion (60+ apps: Firefox/Chromium/Chrome/Vivaldi/
  Thorium/Thunderbird/KMail, VS Code, PowerShell, Node.js, WireGuard client/server,
  and more).
- AMD and Intel chipset-driver installers; LACT GPU overclocking tool.
- Mount Local Drive plus NFS/SMB share discovery and mount tasks.
- Time Zone / Locale wizard and a Num Lock at boot task.
- Download verification, JSON output, and a description panel in the TUI menu.

### Fixed
- Numerous menu, `pkg_manager`, SDDM, and EPEL/RHEL fixes; auto-enable EPEL on
  RHEL; detect deb822 apt sources in the preflight check.

## 2026-03

### Added
- Distribution version-upgrade support: Debian codename swap, RHEL family via
  leapp, Linux Mint, Zorin OS, Elementary OS, and Ubuntu LTS→non-LTS tracks.
- xrdp and krdp RDP server support.
- Feral Gamemode installer.
- command-not-found auto-install prompt for Ubuntu/zsh.
- Thorough system-cleanup routine and an animated spinner for package operations.

### Fixed
- Extensive stabilisation across Arch/Manjaro, Fedora/RHEL, KDE Neon, and Kubuntu;
  Xen guest-tools installs; menu rendering and flicker over SSH; version detection
  and formatting; Docker, Steam/NVIDIA, and many other installers.

## 2026-02

### Added
- Initial version: core TUI installer with Fedora support and the `manage_logs.sh`
  log-management script.

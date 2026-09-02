# Interactive Menu

Running `./linux_util.sh` with no flags opens the TUI. Everything the menu can
do is also reachable from the command line — see the flag table in the
[README](../README.md#command-line-use).

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


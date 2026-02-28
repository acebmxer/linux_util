# Linux System Setup & Utilities Installer

An interactive multi-select script combining comprehensive system setup tasks and utility management.

## Menu Preview

When you run the script, you'll see an interactive menu like this:

```
╔══════════════════════════════════════════════════════════════╗
║   Linux System Setup & Utilities - Select Programs/Tasks     ║
╚══════════════════════════════════════════════════════════════╝

Use ↑/↓/←/→ to navigate, SPACE to select/deselect, ENTER to continue, Q to quit

Legend: [✓] = selected  [ ] = not selected  (installed) = already on system

System Tasks:
▸ [✓] Full System Upgrade/Update
  [ ] XEN Guest Utilities
  [ ] System Updates

────────────────────────────────────────────────────────────────

Utilities:
  [✓] Dotfiles (installed)                [ ] Termius SSH Client
  [✓] Docker (installed)                  [ ] Steam App
  [ ] Bitwarden Client                    [✓] Visual Studio Code (installed)
  [ ] Brave Browser                       [ ] KDE Desktop Environment
  [✓] Joplin Client (installed)

────────────────────────────────────────────────────────────────
Actions: Install/Run: 1 | Update: 4 | Uninstall: 0

```

The menu dynamically detects which utilities are already installed and intelligently determines the action:
- **Selected + Not Installed** → Install
- **Selected + Installed** → Update  
- **Not Selected + Installed** → Uninstall
- **Not Selected + Not Installed** → Skip

## Features

- **Interactive TUI Menu** - Navigate with arrow keys, select with spacebar
- **Multi-Distro Support** - Works on Debian/Ubuntu, Fedora, RHEL/CentOS, Arch/Manjaro, and openSUSE
- **Auto-Detection** - Automatically detects your distribution and which utilities are already installed
- **System Setup Tasks** - Full system updates, XCP-NG tools, Docker installation
- **Utility Management** - Install, update, or uninstall common applications
- **Visual Indicators** - Clear display of installed status and pending actions
- **Universal Package Managers** - Supports apt, dnf, yum, pacman, and zypper along with snap, flatpak, and AUR helpers
- **Comprehensive Logging** - Automatic logging of all operations to timestamped log files with separate success and error tracking

## Logging System

The script automatically logs all operations with no configuration required. The `logs/` directory is created automatically on first run, and every execution generates detailed timestamped log files for both successful operations and errors.

### Log Files

Each time you run the script, it automatically creates timestamped log files in the `logs/` directory:

- **Success Logs**: `logs/success_YYYYMMDD_HHMMSS.log` - Records successful operations, system info, installation progress, and execution summary
- **Error Logs**: `logs/error_YYYYMMDD_HHMMSS.log` - Captures errors, warnings, failed operations, and troubleshooting information
- **Latest Logs**: `logs/success_latest.log` and `logs/error_latest.log` - Symlinks automatically updated to point to the most recent logs

All log files are created with timestamps in the format `YYYYMMDD_HHMMSS` (e.g., `success_20260227_143052.log`), making it easy to track when operations occurred.

### Log Management

The `manage_logs.sh` utility provides easy access to view, search, and maintain your log files. Make it executable first:

```bash
chmod +x manage_logs.sh
```

Then use any of these commands to manage your logs:

```bash
# View all log files
./manage_logs.sh list

# View latest logs
./manage_logs.sh view latest

# Search logs for specific text
./manage_logs.sh search "Docker"

# Show statistics
./manage_logs.sh stats

# Clean old logs (older than 30 days)
./manage_logs.sh clean 30

# Compress old logs
./manage_logs.sh compress

# Show help
./manage_logs.sh help
```

### What Gets Logged

The script automatically captures detailed information about every operation:

- **System Information**: Distribution detected, package manager in use, architecture
- **Pre-flight Checks**: DNS connectivity tests, repository availability
- **Installation Progress**: Each utility/task being processed with real-time status
- **Package Management**: All package installs, updates, and removals with full output
- **Success Messages**: Confirmation of completed operations with timestamps
- **Error Details**: Failed operations with error messages and exit codes
- **Warnings**: Potential issues that don't stop execution but need attention
- **Execution Summary**: Final count of successful and failed operations
- **Timing Information**: When the script started and completed

### Viewing Logs After Execution

After running the script, logs are automatically saved and the script displays:
```
Log files saved to: /home/nick/Github/linux_util/logs
```

You can quickly view or manage logs using the included log management utility (see below).

## Supported Distributions

| Distro Family | Distributions | Package Manager |
|---------------|--------------|----------------|
| Debian/Ubuntu | Ubuntu, Debian, Linux Mint, Pop!_OS, elementary OS, Zorin, Kali, KDE neon | apt |
| Fedora | Fedora | dnf |
| RHEL | RHEL, CentOS, Rocky Linux, AlmaLinux, Oracle Linux | dnf / yum |
| Arch | Arch Linux, Manjaro, EndeavourOS, Garuda, Artix | pacman (+ AUR helpers) |
| openSUSE | openSUSE Leap, openSUSE Tumbleweed, SLES | zypper |

Derivative distributions not explicitly listed are detected via the `ID_LIKE` field in `/etc/os-release`, or by auto-detecting the available package manager.

## Requirements

- A supported Linux distribution (see above)
- Bash 4.0+
- sudo access (script must NOT be run as root)
- Interactive terminal
- For Arch-based distros: an AUR helper (yay or paru) is recommended for some utilities
- Internet connection (for downloads)

## Installation & Usage

```bash
# Clone the repository
git clone "https://github.com/acebmxer/linux_util.git"
cd linux_util

# Make the script executable
chmod +x linux_util.sh

# Run the installer
./linux_util.sh
```

**Note:** All operations are automatically logged to the `logs/` directory. You can review what happened at any time using the log management utility or by viewing the log files directly.

## Menu Controls

| Key | Action |
|-----|--------|
| ↑ / ↓ | Navigate up/down |
| Space | Toggle selection |
| Enter | Confirm and proceed |
| Q | Quit without changes |

## How It Works

When the script starts, it checks which utilities are already installed on your system:

- **Installed utilities** are pre-selected and marked with `(installed)`
- **Not installed utilities** are unselected

Based on your selections, the script determines what action to take:

| Selection State | Installed? | Action |
|-----------------|------------|--------|
| ✓ Selected | No | **Install** or **Run** (for setup tasks) |
| ✓ Selected | Yes | **Update** |
| Not Selected | Yes | **Uninstall** |
| Not Selected | No | Skip |

## Available Options

### System Setup Tasks

#### 1. Full System Upgrade/Update
- Updates package lists
- Installs essential tools (jq, tzdata, git, curl, wget, gnupg)
- Installs software-properties-common (Ubuntu, Linux Mint, Pop!_OS only)
- Installs Landscape Client (Ubuntu only)
- Performs full system upgrade and cleanup
- Removes unnecessary packages and cleans package cache

#### 2. XEN Guest Utilities
- Checks for existing xe-guest-utilities or xen-guest-agent
- Prompts to uninstall conflicting packages
- Mounts XCP-NG ISO (requires manual insertion)
- Runs XCP-NG tools installer
- Automatically unmounts ISO after installation

#### 3. System Updates
- Updates package lists
- Performs full system upgrade
- Removes unnecessary packages
- Cleans package cache

### Utilities

| Utility | Description | Install Method |
|---------|-------------|----------------|
| **Dotfiles** | Shell configuration and theming from [flipsidecreations/dotfiles](https://github.com/flipsidecreations/dotfiles) | git clone + setup script |
| **Docker** | Container platform with Engine, CLI, Compose, and Buildx | Official Docker repositories |
| **Bitwarden Client** | Password manager | snap / flatpak / AUR |
| **Brave Browser** | Privacy-focused web browser | Native repo (all distros) / AUR |
| **Joplin Client** | Note-taking application | AppImage (universal) |
| **Termius SSH Client** | SSH client for remote connections | .deb / snap / flatpak |
| **Steam App** | Gaming platform | Native packages / RPM Fusion / flatpak |
| **Visual Studio Code** | Code editor | Native repo (all distros) / AUR |
| **KDE Desktop Environment** | Full KDE Plasma desktop environment | Native packages (all distros) |

**Note for Dotfiles:** Installation is skipped on Fedora, RHEL, CentOS, Rocky Linux, and AlmaLinux due to compatibility considerations.

**Note for Docker:** After installation, you'll be added to the docker group. Log out and log back in or reboot to use Docker without sudo.

## Examples

### Installing Multiple Utilities

1. Run the script: `./linux_util.sh`
2. Use arrow keys to navigate
3. Press Space to select utilities you want to install
4. Press Enter to confirm
5. The script will install all selected utilities

### Updating Installed Software

1. Run the script - installed utilities are pre-selected
2. Keep the selections as-is or modify them
3. Press Enter
4. The script will update selected utilities that are already installed

### System Setup

1. Run the script
2. Navigate to "Full System Upgrade/Update" or "System Updates"
3. Press Space to select
4. Press Enter to execute
5. Follow any prompts



## XCP-NG Tools Installation

When installing XEN Guest Utilities:
1. The script checks for conflicting packages (xe-guest-utilities, xen-guest-agent)
2. You'll be prompted to remove any existing installations
3. Insert the XCP-NG tools ISO when prompted
4. The script mounts from `/dev/cdrom` to `/mnt`
5. Installation runs automatically
6. ISO is unmounted after completion

## Adding New Utilities

To add a new utility, edit `linux_util.sh` and add the following in the `UTILITY DEFINITIONS` section:

```bash
# --- My New Utility ---
UTILITIES+=("My New Utility")
INSTALL_FUNCS["My New Utility"]="install_my_utility"
CHECK_FUNCS["My New Utility"]="check_my_utility"
UNINSTALL_FUNCS["My New Utility"]="uninstall_my_utility"
UPDATE_FUNCS["My New Utility"]="update_my_utility"

check_my_utility() {
    # Return 0 if installed, non-zero if not
    command -v my-utility &>/dev/null || pkg_check_installed my-utility
}

install_my_utility() {
    echo "Installing My New Utility..."
    pkg_install my-utility
}

uninstall_my_utility() {
    echo "Uninstalling My New Utility..."
    pkg_remove my-utility
}

update_my_utility() {
    echo "Updating My New Utility..."
    pkg_upgrade my-utility
}
```

### Available Helper Functions

| Helper Function | Description |
|----------------|-------------|
| `pkg_install <pkg>` | Install a package using the detected package manager |
| `pkg_remove <pkg>` | Remove a package |
| `pkg_upgrade <pkg>` | Upgrade a package |
| `pkg_check_installed <pkg>` | Check if a package is installed (returns 0/1) |
| `pkg_install_local <file>` | Install from a local .deb/.rpm file |
| `pkg_refresh` | Refresh package lists |
| `pkg_full_upgrade` | Perform full system upgrade |
| `pkg_autoremove` | Remove unnecessary packages |
| `pkg_clean` | Clean package cache |
| `has_snap` | Check if snap is available |
| `has_flatpak` | Check if flatpak is available |
| `has_aur_helper` | Check if yay/paru is available (Arch) |
| `aur_install <pkg>` | Install from AUR via yay/paru |

For distro-specific logic, use `$DISTRO_FAMILY` (values: `debian`, `fedora`, `rhel`, `arch`, `suse`) in a `case` statement.

## Troubleshooting

### Script Won't Run
- Ensure the script is executable: `chmod +x linux_util.sh`
- Make sure you're NOT running as root
- Check that you're in an interactive terminal

### Package Installation Fails
- Ensure you have internet connectivity
- Check that package repositories are accessible
- Some packages may require additional repositories (e.g., RPM Fusion for Steam on Fedora)

### AUR Packages on Arch
- Install an AUR helper first: `yay` or `paru`
- Some utilities require an AUR helper on Arch-based distributions

## Credits

This project integrates and builds upon:
- [linux_setup_script](https://github.com/acebmxer/linux_setup_script) - System setup and configuration tasks
- [install_linux_utilities](https://github.com/acebmxer/install_linux_utilities) - Application installation framework
- [flipsidecreations/dotfiles](https://github.com/flipsidecreations/dotfiles) - Dotfiles configuration

## License

MIT License

---

**Note:** This script performs system-level changes. Always review the code before running it, especially on production systems. The script requires sudo privileges and will prompt for your password when needed.

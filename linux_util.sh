#!/bin/bash

# ============================================================================
# Linux Utilities Installer & System Setup
# Interactive multi-select installer combining system setup and utility management
# Compatible with: Debian/Ubuntu, Fedora/RHEL/CentOS, Arch/Manjaro, openSUSE
# ============================================================================

# Prevent running as root
if [[ $EUID -eq 0 ]]; then
    echo "Error: This script should NOT be run as root."
    echo "Please run as a regular user. sudo will be used when needed."
    exit 1
fi

# Require Bash 4.0+ (associative arrays, mapfile, etc.)
if (( BASH_VERSINFO[0] < 4 )); then
    echo "Error: Bash 4.0 or newer is required (running: ${BASH_VERSION})."
    exit 1
fi

# Dry-run flag — set to true via --dry-run CLI argument
DRY_RUN=false

# Preserve original CLI arguments for self-update re-exec
ORIGINAL_ARGS=("$@")

# Prevent concurrent runs via flock
LOCK_FILE="/tmp/linux_util_${USER}.lock"
exec 9>"$LOCK_FILE"
if ! flock -n 9; then
    echo "Error: Another instance of this script is already running."
    exit 1
fi

# ============================================================================
# LOGGING SETUP
# ============================================================================

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_PATH="${SCRIPT_DIR}/$(basename "${BASH_SOURCE[0]}")"
LOG_DIR="${SCRIPT_DIR}/logs"

# Restrict log file permissions (owner-only read/write)
umask 077

# Create log directory if it doesn't exist
mkdir -p "$LOG_DIR"

# Log file names with timestamp
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
SUCCESS_LOG="${LOG_DIR}/success_${TIMESTAMP}.log"
ERROR_LOG="${LOG_DIR}/error_${TIMESTAMP}.log"

# Also maintain latest logs (symlinks or copies)
LATEST_SUCCESS_LOG="${LOG_DIR}/success_latest.log"
LATEST_ERROR_LOG="${LOG_DIR}/error_latest.log"

# Config file that persists the NVIDIA driver version chosen at install time
# (used by other installers, e.g. Steam, to install matching 32-bit libraries)
NVIDIA_VERSION_FILE="${HOME}/.config/linux_util/nvidia_driver_version"

# Track if any errors have occurred
ERROR_LOG_INITIALIZED=false

# Initialize success log only
{
    echo "════════════════════════════════════════════════════════════════"
    echo "Linux Utilities Installer - Execution Log"
    echo "Started: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "User: $USER"
    echo "Hostname: $(hostname)"
    echo "════════════════════════════════════════════════════════════════"
    echo ""
} > "$SUCCESS_LOG"

# Create/update latest success log symlink
ln -sf "$(basename "$SUCCESS_LOG")" "$LATEST_SUCCESS_LOG" 2>/dev/null || cp "$SUCCESS_LOG" "$LATEST_SUCCESS_LOG"

# Function to initialize error log on first error
init_error_log() {
    if [[ "$ERROR_LOG_INITIALIZED" == "false" ]]; then
        {
            echo "════════════════════════════════════════════════════════════════"
            echo "Linux Utilities Installer - Error Log"
            echo "Started: $(date '+%Y-%m-%d %H:%M:%S')"
            echo "User: $USER"
            echo "Hostname: $(hostname)"
            echo "════════════════════════════════════════════════════════════════"
            echo ""
        } > "$ERROR_LOG"
        ERROR_LOG_INITIALIZED=true
        # Create/update latest error log symlink
        ln -sf "$(basename "$ERROR_LOG")" "$LATEST_ERROR_LOG" 2>/dev/null || cp "$ERROR_LOG" "$LATEST_ERROR_LOG"
    fi
}

# Logging functions
log_success() {
    local message="$1"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[${timestamp}] [SUCCESS] ${message}" >> "$SUCCESS_LOG"
}

log_error() {
    local message="$1"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    init_error_log
    echo "[${timestamp}] [ERROR] ${message}" | tee -a "$ERROR_LOG" >&2
}

log_warning() {
    local message="$1"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    init_error_log
    echo "[${timestamp}] [WARNING] ${message}" | tee -a "$ERROR_LOG"
}

log_info() {
    local message="$1"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[${timestamp}] [INFO] ${message}" >> "$SUCCESS_LOG"
}

# Function to log command execution with error capture
log_command() {
    local description="$1"
    shift
    local cmd="$*"
    
    log_info "Executing: ${description}"
    log_info "Command: ${cmd}"
    
    local output
    local exit_code
    
    output=$("$@" 2>&1)
    exit_code=$?
    
    if [[ $exit_code -eq 0 ]]; then
        log_success "${description} completed successfully"
        if [[ -n "$output" ]]; then
            echo "[OUTPUT] ${output}" >> "$SUCCESS_LOG"
        fi
    else
        log_error "${description} failed with exit code ${exit_code}"
        log_error "Command: ${cmd}"
        if [[ -n "$output" ]]; then
            init_error_log
            echo "[ERROR OUTPUT] ${output}" >> "$ERROR_LOG"
        fi
    fi
    
    return $exit_code
}

# --- Global temp-file cleanup ---
# Functions that create temp files should append paths to this array.
# On exit (normal or interrupted), all registered files are removed.
declare -a CLEANUP_FILES=()
SUDO_KEEPALIVE_PID=""

cleanup_on_exit() {
    # Kill sudo keep-alive background process
    [[ -n "$SUDO_KEEPALIVE_PID" ]] && kill "$SUDO_KEEPALIVE_PID" 2>/dev/null || true
    # Remove any registered temp files/dirs
    for _f in "${CLEANUP_FILES[@]}"; do
        rm -rf "$_f" 2>/dev/null || true
    done
}
trap cleanup_on_exit EXIT

# Trap errors and log them (skip intentional failures in conditionals)
_err_handler() {
    local _exit_code=$?
    # Suppress logging for common intentional-failure patterns
    case "$BASH_COMMAND" in
        *"command -v"*|*"grep -q"*|*"2>/dev/null"*|*"|| true"*|*"|| return"*|*"|| warn"*|*"|| echo"*)
            return 0 ;;
    esac
    log_error "Unexpected error at line $LINENO: Command \"$BASH_COMMAND\" failed (exit $_exit_code)"
}
trap '_err_handler' ERR

# ============================================================================
# DISTRO DETECTION & PACKAGE MANAGER ABSTRACTION
# ============================================================================

detect_distro() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        DISTRO_ID="${ID}"
        DISTRO_ID_LIKE="${ID_LIKE:-}"
        DISTRO_VERSION_ID="${VERSION_ID:-}"
        DISTRO_VERSION_CODENAME="${VERSION_CODENAME:-}"
        DISTRO_NAME="${NAME}"
    else
        echo "Error: Cannot detect Linux distribution (/etc/os-release not found)."
        exit 1
    fi

    # Determine distro family
    case "$DISTRO_ID" in
        ubuntu|debian|linuxmint|pop|elementary|zorin|kali|neon)
            DISTRO_FAMILY="debian"
            PKG_MGR="apt"
            ;;
        fedora)
            DISTRO_FAMILY="fedora"
            PKG_MGR="dnf"
            ;;
        rhel|centos|rocky|alma|ol|almalinux)
            DISTRO_FAMILY="rhel"
            PKG_MGR="dnf"
            command -v dnf &>/dev/null || PKG_MGR="yum"
            ;;
        arch|manjaro|endeavouros|garuda|artix)
            DISTRO_FAMILY="arch"
            PKG_MGR="pacman"
            ;;
        opensuse-leap|opensuse-tumbleweed|sles|opensuse-microos|opensuse)
            DISTRO_FAMILY="suse"
            PKG_MGR="zypper"
            ;;
        *)
            # Try ID_LIKE for derivatives
            case "$DISTRO_ID_LIKE" in
                *debian*|*ubuntu*)
                    DISTRO_FAMILY="debian"; PKG_MGR="apt" ;;
                *fedora*|*rhel*)
                    DISTRO_FAMILY="fedora"; PKG_MGR="dnf"
                    command -v dnf &>/dev/null || PKG_MGR="yum"
                    ;;
                *arch*)
                    DISTRO_FAMILY="arch"; PKG_MGR="pacman" ;;
                *suse*)
                    DISTRO_FAMILY="suse"; PKG_MGR="zypper" ;;
                *)
                    echo "Warning: Unrecognized distribution '${DISTRO_NAME}' (${DISTRO_ID})."
                    echo "Supported: Debian/Ubuntu, Fedora/RHEL, Arch, openSUSE"
                    # Auto-detect by available package manager
                    if command -v apt &>/dev/null; then
                        DISTRO_FAMILY="debian"; PKG_MGR="apt"
                    elif command -v dnf &>/dev/null; then
                        DISTRO_FAMILY="fedora"; PKG_MGR="dnf"
                    elif command -v yum &>/dev/null; then
                        DISTRO_FAMILY="rhel"; PKG_MGR="yum"
                    elif command -v pacman &>/dev/null; then
                        DISTRO_FAMILY="arch"; PKG_MGR="pacman"
                    elif command -v zypper &>/dev/null; then
                        DISTRO_FAMILY="suse"; PKG_MGR="zypper"
                    else
                        echo "Error: No supported package manager found."
                        exit 1
                    fi
                    echo "Auto-detected package manager: $PKG_MGR"
                    ;;
            esac
            ;;
    esac

    echo "Detected: ${DISTRO_NAME} (family: ${DISTRO_FAMILY}, package manager: ${PKG_MGR})"
    log_info "System detected: ${DISTRO_NAME} (family: ${DISTRO_FAMILY}, package manager: ${PKG_MGR})"
}

# --- Package Manager Wrappers ---

pkg_refresh() {
    case "$PKG_MGR" in
        apt)     sudo apt update ;;
        dnf|yum) sudo "$PKG_MGR" makecache ;;
        # NOTE: On Arch, -Sy without -u risks partial upgrades. We use -Syu
        # here so that any subsequent pkg_install calls have a consistent DB+system.
        pacman)  sudo pacman -Syu --noconfirm ;;
        zypper)  sudo zypper refresh ;;
    esac
}

pkg_install() {
    case "$PKG_MGR" in
        apt)     sudo apt install -y "$@" ;;
        dnf|yum) sudo "$PKG_MGR" install -y "$@" ;;
        pacman)  sudo pacman -S --noconfirm "$@" ;;
        zypper)  sudo zypper install -y "$@" ;;
    esac
}

pkg_remove() {
    case "$PKG_MGR" in
        apt)     sudo apt remove -y "$@" ;;
        dnf|yum) sudo "$PKG_MGR" remove -y "$@" ;;
        pacman)  sudo pacman -Rs --noconfirm "$@" ;;
        zypper)  sudo zypper remove -y "$@" ;;
    esac
}

pkg_upgrade() {
    case "$PKG_MGR" in
        apt)     sudo apt update && sudo apt upgrade -y "$@" ;;
        dnf|yum) sudo "$PKG_MGR" upgrade -y "$@" ;;
        pacman)  sudo pacman -S --noconfirm "$@" ;;
        zypper)  sudo zypper update -y "$@" ;;
    esac
}

pkg_check_installed() {
    case "$PKG_MGR" in
        apt)     dpkg -l "$1" 2>/dev/null | grep -q "^ii" ;;
        dnf|yum) rpm -q "$1" &>/dev/null ;;
        pacman)  pacman -Q "$1" &>/dev/null ;;
        zypper)  rpm -q "$1" &>/dev/null ;;
    esac
}

pkg_install_local() {
    case "$PKG_MGR" in
        apt)     sudo apt install -y "$1" ;;
        dnf|yum) sudo "$PKG_MGR" install -y "$1" ;;
        pacman)  sudo pacman -U --noconfirm "$1" ;;
        zypper)  sudo zypper install -y --allow-unsigned-rpm "$1" ;;
    esac
}

pkg_autoremove() {
    case "$PKG_MGR" in
        apt)     sudo apt autoremove -y ;;
        dnf|yum) sudo "$PKG_MGR" autoremove -y ;;
        pacman)  pacman -Qdtq 2>/dev/null | sudo pacman -Rs --noconfirm - 2>/dev/null || true ;;
        zypper)  true ;;
    esac
}

pkg_full_upgrade() {
    case "$PKG_MGR" in
        apt)     sudo apt update && sudo apt full-upgrade -y ;;
        dnf|yum) sudo "$PKG_MGR" upgrade -y ;;
        pacman)  sudo pacman -Syu --noconfirm ;;
        zypper)  sudo zypper update -y ;;
    esac
}

pkg_clean() {
    case "$PKG_MGR" in
        apt)     sudo apt clean && sudo apt autoclean ;;
        dnf|yum) sudo "$PKG_MGR" clean all ;;
        pacman)  sudo pacman -Sc --noconfirm ;;
        zypper)  sudo zypper clean -a ;;
    esac
}

pkg_get_version() {
    local pkg="$1"
    case "$PKG_MGR" in
        apt)     dpkg-query -W -f='${Version}' "$pkg" 2>/dev/null || echo "unknown" ;;
        dnf|yum|zypper) rpm -q --queryformat '%{VERSION}-%{RELEASE}' "$pkg" 2>/dev/null || echo "unknown" ;;
        pacman)  pacman -Q "$pkg" 2>/dev/null | awk '{print $2}' || echo "unknown" ;;
    esac
}

# --- Snap / Flatpak / AUR Helpers ---

has_snap() {
    command -v snap &>/dev/null
}

has_flatpak() {
    command -v flatpak &>/dev/null
}

has_aur_helper() {
    command -v yay &>/dev/null || command -v paru &>/dev/null
}

aur_install() {
    if command -v yay &>/dev/null; then
        yay -S --noconfirm "$@"
    elif command -v paru &>/dev/null; then
        paru -S --noconfirm "$@"
    else
        echo "Error: No AUR helper found. Please install yay or paru first."
        return 1
    fi
}

aur_remove() {
    if command -v yay &>/dev/null; then
        yay -Rs --noconfirm "$@"
    elif command -v paru &>/dev/null; then
        paru -Rs --noconfirm "$@"
    else
        sudo pacman -Rs --noconfirm "$@"
    fi
}

aur_upgrade() {
    if command -v yay &>/dev/null; then
        yay -S --noconfirm "$@"
    elif command -v paru &>/dev/null; then
        paru -S --noconfirm "$@"
    else
        echo "Error: No AUR helper found. Please install yay or paru first."
        return 1
    fi
}

# Ensure packages required to build AUR packages are present (Arch/Manjaro only)
ensure_aur_build_deps() {
    if [[ "$PKG_MGR" != "pacman" ]]; then
        return 0
    fi
    echo "Ensuring AUR build dependencies (base-devel, git)..."
    sudo pacman -S --noconfirm --needed base-devel git
}

# Build and install a package from AUR without a helper (yay/paru).
# Usage: aur_build <aur-package-name>
aur_build() {
    local pkg_name="$1"
    ensure_aur_build_deps
    local build_dir
    build_dir=$(mktemp -d)
    CLEANUP_FILES+=("$build_dir")
    git clone "https://aur.archlinux.org/${pkg_name}.git" "$build_dir/${pkg_name}"
    (cd "$build_dir/${pkg_name}" && makepkg -si --noconfirm)
    rm -rf "$build_dir"
}

# Detect the distro at startup
detect_distro
echo ""

# Cache sudo credentials and keep them alive in the background so the user
# is not re-prompted mid-install when the sudo timeout expires.
sudo -v
( exec 9>&-; while true; do sudo -n true; sleep 50; done ) 2>/dev/null &
SUDO_KEEPALIVE_PID=$!

# ============================================================================
# SYSTEM SETUP OPTIONS (from linux_setup_script)
# ============================================================================

# Helper functions
# NOTE: run_as_root passes its arguments as a single string to sh -c.
# Arguments containing spaces, quotes, or special characters will be
# subject to word-splitting by sh. For commands with complex quoting,
# use 'sudo bash -c "..."' directly instead of this helper.
run_as_root() { sudo -E sh -c "$*"; }
info()  { printf '\e[32m[INFO]\e[0m %s\n' "$*"; }
warn()  { printf '\e[33m[WARN]\e[0m %s\n' "$*"; }
error() { printf '\e[31m[ERROR]\e[0m %s\n' "$*" >&2; }

# Ensure required tools are installed
ensure_tools() {
    case "$PKG_MGR" in
        apt)
            # Check if gnupg, curl, and wget are installed
            if ! command -v gpg &>/dev/null || ! command -v curl &>/dev/null || ! command -v wget &>/dev/null; then
                info "Installing required tools (gnupg, curl, wget)..."
                sudo apt-get update -qq
                sudo apt-get install -y gnupg curl wget 2>/dev/null || true
            fi
            ;;
        dnf|yum)
            if ! command -v gpg &>/dev/null || ! command -v curl &>/dev/null || ! command -v wget &>/dev/null; then
                sudo "$PKG_MGR" install -y gnupg2 curl wget 2>/dev/null || true
            fi
            ;;
        pacman)
            if ! command -v gpg &>/dev/null || ! command -v curl &>/dev/null || ! command -v wget &>/dev/null; then
                info "Installing required tools (gnupg, curl, wget)..."
                sudo pacman -S --noconfirm --needed gnupg curl wget 2>/dev/null || true
            fi
            ;;
        zypper)
            if ! command -v gpg &>/dev/null || ! command -v curl &>/dev/null || ! command -v wget &>/dev/null; then
                sudo zypper install -y gpg2 curl wget 2>/dev/null || true
            fi
            ;;
    esac
}

# Check for internet connectivity; warns but does not abort (best-effort).
check_internet() {
    if ! { curl -fsS --max-time 5 https://1.1.1.1 || ping -c1 -W3 8.8.8.8; } &>/dev/null; then
        warn "Internet connectivity check failed. Downloads may not work."
        return 1
    fi
    return 0
}

# download_file <url> <dest> [retries=3]
# Robust download with retries; prefers wget, falls back to curl.
# NOTE: Checksum verification is not implemented because download URLs
# change frequently and upstream projects do not consistently provide
# checksum files at predictable URLs. If a utility provides a .sha256
# file alongside its download, verify it in the individual install function.
download_file() {
    local url="$1" dest="$2" retries="${3:-3}" attempt=1
    while (( attempt <= retries )); do
        if command -v wget &>/dev/null; then
            wget -q --timeout=30 -O "$dest" "$url" && return 0
        else
            curl -fsSL --max-time 30 --retry 2 -o "$dest" "$url" && return 0
        fi
        warn "Download attempt $attempt/$retries failed: $(basename "$url")"
        (( attempt++ ))
        (( attempt <= retries )) && sleep 2
    done
    error "Failed to download after $retries attempts: $url"
    return 1
}

# --- Option 1: Full System Update (Bare Metal) ---
setup_full_update_bare_metal() {
    info "Starting full system update and upgrade (bare metal)..."
    
    # Install basic tools
    case "$PKG_MGR" in
        apt)
            run_as_root "apt-get update"
            # Install core packages first
            run_as_root "apt-get install -y --no-install-recommends jq tzdata git curl wget gnupg"
            # Install software-properties-common only on Ubuntu
            if [[ "$DISTRO_ID" == "ubuntu" ]] || [[ "$DISTRO_ID" == "linuxmint" ]] || [[ "$DISTRO_ID" == "pop" ]]; then
                run_as_root "apt-get install -y --no-install-recommends software-properties-common"
            fi
            ;;
        dnf|yum)
            run_as_root "$PKG_MGR install -y jq git curl wget util-linux-user"
            ;;
        pacman)
            run_as_root "pacman -S --noconfirm --needed jq git curl wget"
            ;;
        zypper)
            run_as_root "zypper install -y jq git curl wget"
            ;;
        *)
            run_as_root "$PKG_MGR install -y jq git curl wget"
            ;;
    esac
    
    # Install landscape-client for Ubuntu/Debian
    if [[ "$DISTRO_FAMILY" == "debian" && "$DISTRO_ID" == "ubuntu" ]]; then
        info "Installing Landscape Client..."
        run_as_root "add-apt-repository -y ppa:landscape/self-hosted-beta 2>/dev/null || true"
        run_as_root "apt-get update && apt-get install -y --no-install-recommends landscape-client" || warn "Failed to install landscape-client"
    fi
    
    # Backup GNOME keyring before upgrade to prevent credentials being wiped
    # if gnome-keyring or libsecret is upgraded and restarts the daemon mid-session.
    local keyring_dir="${HOME}/.local/share/keyrings"
    local keyring_backup=""
    if [[ -d "$keyring_dir" ]] && [[ -n "$(ls -A "$keyring_dir" 2>/dev/null)" ]]; then
        keyring_backup=$(mktemp -d)
        CLEANUP_FILES+=("$keyring_backup")
        cp -a "$keyring_dir/." "$keyring_backup/"
        info "Keyring backed up to ${keyring_backup}"
    fi

    # Full system upgrade
    pkg_full_upgrade
    pkg_autoremove
    pkg_clean

    # Restore keyring if the upgrade caused any keyring files to change
    if [[ -n "$keyring_backup" ]]; then
        local restored=false
        for backed_up_file in "$keyring_backup"/*; do
            local filename
            filename=$(basename "$backed_up_file")
            local live_file="${keyring_dir}/${filename}"
            # Restore if the live file is missing or smaller than the backup
            # (upgrade reset it to an empty/new keyring)
            if [[ ! -f "$live_file" ]] || \
               [[ $(stat -c%s "$backed_up_file") -gt $(stat -c%s "$live_file") ]]; then
                mkdir -p "$keyring_dir"
                cp -a "$backed_up_file" "$live_file"
                restored=true
                info "Restored keyring file: ${filename}"
            fi
        done
        if [[ "$restored" == "true" ]]; then
            info "Keyring restored. Restarting gnome-keyring daemon..."
            pkill -u "$USER" gnome-keyring-daemon 2>/dev/null || true
            sleep 1
        fi
        rm -rf "$keyring_backup"
    fi

    info "System has been fully updated and upgraded."
    return 0
}

# --- Option 2: Install/Update XEN Guest Utilities ---
setup_xen_guest_utilities() {
    info "Installing/Updating XEN Guest Utilities..."

    # CentOS / Fedora: install from EPEL repository
    if [[ "$DISTRO_ID" == "centos" || "$DISTRO_ID" == "fedora" ]]; then
        info "Installing xe-guest-utilities-latest via yum (EPEL)..."
        run_as_root "yum install -y xe-guest-utilities-latest" || { error "Failed to install xe-guest-utilities-latest"; return 1; }
        info "Enabling and starting xe-linux-distribution service..."
        run_as_root "systemctl enable xe-linux-distribution" || warn "Failed to enable xe-linux-distribution"
        run_as_root "systemctl start xe-linux-distribution" || warn "Failed to start xe-linux-distribution"
        info "XEN Guest Utilities installation completed."
        return 0
    fi

    # Check for existing installations and optionally remove them
    if pkg_check_installed xe-guest-utilities; then
        ver=$(pkg_get_version xe-guest-utilities)
        info "xe-guest-utilities is installed, version $ver."
        read -n 1 -rp "Would you like to uninstall existing xe-guest-utilities (v$ver) before installing new tools? [y/N] " ans
        echo
        case "$ans" in
            y|Y)
                info "Uninstalling existing xe-guest-utilities..."
                pkg_remove xe-guest-utilities || warn "Failed to remove xe-guest-utilities."
                ;;
            *)
                info "Keeping existing xe-guest-utilities."
                ;;
        esac
    fi
    
    if pkg_check_installed xen-guest-agent; then
        ver=$(pkg_get_version xen-guest-agent)
        info "xen-guest-agent is installed, version $ver."
        read -n 1 -rp "Would you like to uninstall existing xen-guest-agent (v$ver) before installing new tools? [y/N] " ans
        echo
        case "$ans" in
            y|Y)
                info "Uninstalling existing xen-guest-agent..."
                pkg_remove xen-guest-agent || warn "Failed to remove xen-guest-agent."
                ;;
            *)
                info "Keeping existing xen-guest-agent."
                ;;
        esac
    fi
    
    # Mount ISO and install
    MOUNT_POINT="/mnt"
    if ! mountpoint -q "${MOUNT_POINT}"; then
        warn "ISO not mounted. Please insert the XCP-NG ISO and press Enter to continue..."
        read -r
        run_as_root "mount /dev/cdrom '${MOUNT_POINT}'" || { error "Failed to mount /dev/cdrom"; return 1; }
    fi
    
    if [[ -f "${MOUNT_POINT}/Linux/install.sh" ]]; then
        info "Running XCP-NG installer script..."

        # Debian-family distros (debian, ubuntu, kubuntu, kde neon, etc.) are auto-detected.
        # RHEL derivatives (alma, rocky, etc.) need explicit -d rhel -m <major_version> flags.
        # See: https://docs.xcp-ng.org/vms/#install-from-the-guest-tools-iso
        local install_flags=""
        local major_ver="${DISTRO_VERSION_ID%%.*}"

        case "$DISTRO_FAMILY" in
            debian)
                install_flags=""
                ;;
            rhel)
                install_flags="-d rhel -m ${major_ver}"
                ;;
            arch|suse)
                warn "Xen Guest Tools installer may not officially support ${DISTRO_NAME}. Attempting without distro flags..."
                ;;
            *)
                warn "Unknown distro family '${DISTRO_FAMILY}'. Attempting without distro flags..."
                ;;
        esac

        [[ -n "$install_flags" ]] && info "Using installer flags: ${install_flags}"
        run_as_root "bash '${MOUNT_POINT}/Linux/install.sh' ${install_flags}"
        info "Waiting 5 seconds for services to initialize..."
        sleep 5
        run_as_root "umount '${MOUNT_POINT}'" || warn "Failed to unmount ${MOUNT_POINT}"
        info "XCP-NG Tools installation completed."
    else
        error "Installer script not found at ${MOUNT_POINT}/Linux/install.sh"
        return 1
    fi
    
    return 0
}

# --- Option 4: System Updates ---
setup_system_updates() {
    info "Running system updates..."
    pkg_full_upgrade
    pkg_autoremove
    pkg_clean
    info "System updates completed."
    return 0
}

# --- Option 5: Install Dotfiles ---
setup_install_dotfiles() {
    info "Installing dotfiles..."
    
    # Skip for Fedora-based distros
    if [[ "$DISTRO_ID" == "fedora" || "$DISTRO_ID" == "rhel" || "$DISTRO_ID" == "centos" || "$DISTRO_ID" == "rocky" || "$DISTRO_ID" == "almalinux" ]]; then
        warn "Dotfiles installation not supported for Fedora-based distros."
        return 1
    fi
    
    # Install dotfiles for current user
    info "Starting as regular user"
    # Remove dotfiles folder from previous install
    rm -rf ~/dotfiles
    info "Previous dotfiles folder was removed."
    git clone https://github.com/flipsidecreations/dotfiles.git ~/dotfiles || { warn "Failed to clone dotfiles"; return 1; }
    # Run install.sh in a subshell to avoid changing the script's working directory
    (
        cd ~/dotfiles || exit 1
        # Note: If you see "apt: command not found" errors below, they come from the dotfiles
        # install.sh script and may be ignored on non-Debian systems if the script continues.
        ./install.sh
    ) || { warn "Dotfiles install.sh failed"; return 1; }
    chsh -s /bin/zsh || warn "Failed to change shell to zsh for current user."
    
    # Install dotfiles for root
    info "Installing dotfiles for root..."
    sudo -s <<'EOF'
info() { printf '\e[32m[INFO]\e[0m %s\n' "$*"; }
warn() { printf '\e[33m[WARN]\e[0m %s\n' "$*"; }
info "Now running as root"
# Remove dotfiles folder from previous install
rm -rf ~/dotfiles
git clone https://github.com/flipsidecreations/dotfiles.git ~/dotfiles || exit 0
cd ~/dotfiles || exit 0
# Note: If you see "apt: command not found" errors below, they come from the dotfiles
# install.sh script and may be ignored on non-Debian systems if the script continues.
./install.sh
if command -v chsh &> /dev/null; then
    chsh -s /bin/zsh || warn "Failed to change shell to zsh for root."
else
    warn "chsh command not found for root. Run 'chsh -s /bin/zsh' manually after installing util-linux-user package."
fi
EOF
    info "Back to regular user."
    
    info "Dotfiles installation completed."
    return 0
}

# --- Option 6: Install KDE Desktop Environment ---
setup_install_kde() {
    info "Installing KDE Desktop Environment..."
    ensure_tools
    
    case "$PKG_MGR" in
        apt)
            # Debian/Ubuntu-based systems
            run_as_root "apt-get update"
            info "Installing KDE Full Desktop Environment..."
            run_as_root "apt-get install -y kde-full sddm" || {
                error "Failed to install KDE Full Desktop Environment"
                return 1
            }
            info "Enabling display manager..."
            run_as_root "systemctl enable sddm" || warn "Failed to enable sddm"
            ;;

        dnf|yum)
            # Fedora/RHEL-based systems
            info "Installing KDE Full Desktop Environment..."
            if ! run_as_root "$PKG_MGR groupinstall -y 'KDE Plasma Workspaces'" 2>/dev/null && \
               ! run_as_root "$PKG_MGR group install -y @kde-desktop-environment" 2>/dev/null; then
                # RHEL 9+ / AlmaLinux 9+ don't have the KDE group — install individual packages
                info "Group install not available, installing KDE packages individually..."
                run_as_root "$PKG_MGR install -y epel-release" 2>/dev/null || true
                run_as_root "crb enable" 2>/dev/null || run_as_root "$PKG_MGR config-manager --set-enabled crb" 2>/dev/null || true
                run_as_root "$PKG_MGR install -y plasma-desktop plasma-workspace sddm \
                    plasma-nm plasma-pa plasma-systemmonitor kdeplasma-addons plasma-thunderbolt \
                    bluedevil breeze-gtk kscreen kinfocenter kwrited \
                    konsole dolphin kate ark gwenview okular spectacle \
                    kde-settings-plasma kde-gtk-config xdg-desktop-portal-kde \
                    phonon-qt5-backend-gstreamer" || {
                    error "Failed to install KDE Full Desktop Environment packages"
                    return 1
                }
            fi
            info "Enabling display manager..."
            run_as_root "systemctl enable sddm" || run_as_root "systemctl set-default graphical.target"
            ;;

        zypper)
            # openSUSE/SLES
            info "Installing KDE Full Desktop Environment..."
            run_as_root "zypper install -y -t pattern kde kde_plasma kde_utilities kde_imaging kde_multimedia kde_office kde_games" || {
                error "Failed to install KDE Full Desktop Environment"
                return 1
            }
            info "Enabling display manager..."
            run_as_root "systemctl enable sddm" || run_as_root "systemctl set-default graphical.target"
            ;;

        pacman)
            # Arch Linux
            info "Installing KDE Full Desktop Environment..."
            run_as_root "pacman -S --noconfirm plasma-meta kde-applications-meta sddm" || {
                error "Failed to install KDE Full Desktop Environment"
                return 1
            }
            info "Enabling display manager..."
            run_as_root "systemctl enable sddm"
            ;;
            
        *)
            error "KDE installation not fully supported for ${DISTRO_ID}"
            return 1
            ;;
    esac
    
    info "KDE Desktop Environment installed successfully. Reboot to start using KDE."
    info "To switch to KDE immediately, log out and select 'Plasma' from your display manager."
    
    return 0
}

# --- Option 7: Install Docker ---
setup_install_docker() {
    info "Installing Docker..."
    ensure_tools
    
    case "$PKG_MGR" in
        apt)
            # Debian/Ubuntu-based systems
            run_as_root "apt-get update"
            run_as_root "apt-get install -y apt-transport-https ca-certificates curl gnupg"
            
            # Install software-properties-common only on Ubuntu-based distros
            if [[ "$DISTRO_ID" == "ubuntu" || "$DISTRO_ID" == "linuxmint" || "$DISTRO_ID" == "pop" || "$DISTRO_ID" == "neon" ]]; then
                run_as_root "apt-get install -y software-properties-common"
            fi
            
            local docker_dist="$DISTRO_ID"
            local docker_codename="${DISTRO_VERSION_CODENAME:-stable}"
            # Distros that don't have their own Docker repo — map to ubuntu
            if [[ "$DISTRO_ID" == "linuxmint" || "$DISTRO_ID" == "pop" || "$DISTRO_ID" == "neon" ]]; then
                docker_dist="ubuntu"
                # KDE Neon: resolve the upstream Ubuntu codename
                if [[ "$DISTRO_ID" == "neon" && -z "$docker_codename" ]] || [[ "$DISTRO_ID" == "neon" ]]; then
                    if [[ -f /etc/upstream-release/lsb-release ]]; then
                        docker_codename=$(grep -oP '(?<=DISTRIB_CODENAME=).+' /etc/upstream-release/lsb-release)
                    fi
                    docker_codename="${docker_codename:-noble}"
                fi
            fi

            run_as_root "curl -fsSL https://download.docker.com/linux/${docker_dist}/gpg | gpg --yes --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg"
            echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/${docker_dist} ${docker_codename} stable" | \
                sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
            run_as_root "apt-get update"
            run_as_root "apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin"
            ;;
            
        dnf|yum)
            # Fedora/RHEL-based systems
            run_as_root "$PKG_MGR install -y dnf-plugins-core 2>/dev/null || $PKG_MGR install -y yum-utils"
            
            local docker_repo
            [[ "$DISTRO_ID" == "fedora" ]] && docker_repo="https://download.docker.com/linux/fedora/docker-ce.repo" || docker_repo="https://download.docker.com/linux/centos/docker-ce.repo"
            
            run_as_root "curl -fsSLo /etc/yum.repos.d/docker-ce.repo ${docker_repo}"
            run_as_root "$PKG_MGR install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin"
            run_as_root "systemctl start docker"
            run_as_root "systemctl enable docker"
            ;;
            
        zypper)
            # openSUSE/SLES
            run_as_root "zypper install -y docker docker-compose"
            run_as_root "systemctl start docker"
            run_as_root "systemctl enable docker"
            ;;
            
        pacman)
            # Arch/Manjaro - containerd must be running before docker starts
            run_as_root "pacman -S --noconfirm docker docker-compose docker-buildx"
            run_as_root "systemctl enable --now containerd.service"
            run_as_root "systemctl enable --now docker.service"
            ;;
            
        *)
            error "Docker installation not fully supported for ${DISTRO_ID}"
            return 1
            ;;
    esac
    
    # Add user to docker group
    run_as_root "groupadd docker 2>/dev/null || true"
    run_as_root "usermod -aG docker ${USER}"
    
    info "Docker installed successfully. You may need to log out and back in for group membership to take effect."
    
    # Verify Docker
    sudo docker version &>/dev/null && info "Docker verification complete."
    
    return 0
}

# ============================================================================
# UTILITY DEFINITIONS (from install_linux_utilities)
# ============================================================================

declare -a UTILITIES
declare -A INSTALL_FUNCS
declare -A CHECK_FUNCS
declare -A UNINSTALL_FUNCS
declare -A UPDATE_FUNCS
declare -A VERSION_FUNCS

# Registration helper — reduces boilerplate when adding new utilities.
# Usage: register_utility "Name" install_fn check_fn uninstall_fn update_fn [version_fn]
register_utility() {
    local name="$1" install_fn="$2" check_fn="$3" uninstall_fn="$4" update_fn="$5"
    local version_fn="${6:-}"
    UTILITIES+=("$name")
    INSTALL_FUNCS["$name"]="$install_fn"
    CHECK_FUNCS["$name"]="$check_fn"
    UNINSTALL_FUNCS["$name"]="$uninstall_fn"
    UPDATE_FUNCS["$name"]="$update_fn"
    [[ -n "$version_fn" ]] && VERSION_FUNCS["$name"]="$version_fn" || true
}

# ============================================================================
# UTILITY DEFINITIONS
# ============================================================================

# --- System Setup Tasks ---
# Tracked separately so the menu can render them in their own section.
declare -a SYSTEM_TASKS=()

SYSTEM_TASKS+=("Full System Upgrade/Update")
register_utility "Full System Upgrade/Update" setup_full_update_bare_metal check_always_false noop_function setup_full_update_bare_metal

SYSTEM_TASKS+=("KDE Desktop Environment")
register_utility "KDE Desktop Environment" install_kde check_kde uninstall_kde update_kde get_version_kde

SYSTEM_TASKS+=("NVIDIA Drivers")
register_utility "NVIDIA Drivers" install_nvidia_drivers check_nvidia_drivers uninstall_nvidia_drivers update_nvidia_drivers get_version_nvidia_drivers

SYSTEM_TASKS+=("System Updates")
register_utility "System Updates" setup_system_updates check_always_false noop_function setup_system_updates

SYSTEM_TASKS+=("XEN Guest Utilities")
register_utility "XEN Guest Utilities" setup_xen_guest_utilities check_xen_guest_utilities noop_function setup_xen_guest_utilities get_version_xen_guest_utilities

# Computed from the SYSTEM_TASKS array — no manual increment needed.
readonly SYSTEM_TASK_COUNT=${#SYSTEM_TASKS[@]}

# Helper functions for system setup tasks
check_always_false() { return 1; }
noop_function() { return 0; }
check_xen_guest_utilities() {
    pkg_check_installed xe-guest-utilities || pkg_check_installed xen-guest-agent || pkg_check_installed xe-guest-utilities-latest
}
get_version_xen_guest_utilities() {
    local ver=""
    if pkg_check_installed xe-guest-utilities; then
        ver=$(pkg_get_version xe-guest-utilities)
    elif pkg_check_installed xen-guest-agent; then
        ver=$(pkg_get_version xen-guest-agent)
    elif pkg_check_installed xe-guest-utilities-latest; then
        ver=$(pkg_get_version xe-guest-utilities-latest)
    fi
    [[ -n "$ver" ]] && echo "$ver"
}
check_kde() {
    command -v plasmashell &>/dev/null || \
        pkg_check_installed plasma-desktop || \
        pkg_check_installed kde-plasma-desktop || \
        pkg_check_installed kde-full || \
        pkg_check_installed plasma-meta
}
install_kde() {
    setup_install_kde
}
uninstall_kde() {
    echo "Uninstalling KDE Desktop Environment..."
    case "$DISTRO_FAMILY" in
        debian)
            sudo apt remove -y kde-full kde-plasma-desktop plasma-desktop sddm
            sudo apt autoremove -y
            ;;
        fedora|rhel)
            sudo "$PKG_MGR" group remove -y @kde-desktop-environment || \
                sudo "$PKG_MGR" group remove -y 'KDE Plasma Workspaces'
            sudo "$PKG_MGR" autoremove -y
            ;;
        arch)
            sudo pacman -Rs --noconfirm plasma-meta kde-applications-meta sddm 2>/dev/null || true
            ;;
        suse)
            sudo zypper remove -y -t pattern kde kde_plasma
            ;;
    esac
    echo "KDE Desktop Environment uninstalled. You may need to install another desktop environment."
}
update_kde() {
    echo "Updating KDE Desktop Environment..."
    case "$DISTRO_FAMILY" in
        debian)
            sudo apt update
            sudo apt upgrade -y kde-full plasma-desktop
            ;;
        fedora|rhel)
            sudo "$PKG_MGR" group update -y @kde-desktop-environment || \
                sudo "$PKG_MGR" group update -y 'KDE Plasma Workspaces'
            ;;
        arch)
            sudo pacman -Syu --noconfirm plasma-meta kde-applications-meta
            ;;
        suse)
            sudo zypper update -y -t pattern kde kde_plasma
            ;;
    esac
}
get_version_kde() {
    plasmashell --version 2>/dev/null | sed 's/plasmashell //' || echo ""
}

self_update_script() {
    info "Checking for script updates..."
    if ! command -v git &>/dev/null; then
        warn "git is not installed; cannot self-update."
        return 1
    fi
    if [[ ! -d "${SCRIPT_DIR}/.git" ]]; then
        warn "Script directory is not a git repository; cannot self-update."
        return 1
    fi
    local before
    before=$(git -C "$SCRIPT_DIR" rev-parse HEAD 2>/dev/null)
    if ! git -C "$SCRIPT_DIR" pull --ff-only; then
        warn "git pull failed. Ensure you have network access and no local uncommitted changes."
        return 1
    fi
    local after
    after=$(git -C "$SCRIPT_DIR" rev-parse HEAD 2>/dev/null)
    if [[ "$before" != "$after" ]]; then
        info "Script updated to $(git -C "$SCRIPT_DIR" rev-parse --short HEAD). Restarting..."
        # Clean up before re-exec (EXIT trap does not fire on exec)
        [[ -n "$SUDO_KEEPALIVE_PID" ]] && kill "$SUDO_KEEPALIVE_PID" 2>/dev/null || true
        exec bash "$SCRIPT_PATH" "${ORIGINAL_ARGS[@]}"
    else
        info "Script is already up to date."
    fi
    return 0
}

# --- Installable Utilities ---
# NOTE: Utilities are sorted A-Z by display name.
# When adding a new utility, insert its registration block and its
# implementation functions in the correct alphabetical position to
# maintain the sorted order in the menu.

register_utility "Bitwarden Client"    install_bitwarden       check_bitwarden       uninstall_bitwarden       update_bitwarden          get_version_bitwarden
register_utility "Brave Browser"       install_brave           check_brave           uninstall_brave           update_brave              get_version_brave
register_utility "Devolutions RDM"     install_devolutions_rdm check_devolutions_rdm uninstall_devolutions_rdm update_devolutions_rdm    get_version_devolutions_rdm
register_utility "Docker"              setup_install_docker    check_docker          uninstall_docker          update_docker             get_version_docker
register_utility "Dotfiles"            setup_install_dotfiles  check_dotfiles        noop_function             setup_install_dotfiles
register_utility "Joplin Client"       install_joplin          check_joplin          uninstall_joplin          update_joplin             get_version_joplin
register_utility "LibreOffice"         install_libreoffice     check_libreoffice     uninstall_libreoffice     update_libreoffice        get_version_libreoffice
register_utility "OpenSSH Server"      install_openssh_server  check_openssh_server  uninstall_openssh_server  update_openssh_server     get_version_openssh_server
register_utility "Steam App"           install_steam           check_steam           uninstall_steam           update_steam              get_version_steam
register_utility "Syncthing"           install_syncthing       check_syncthing       uninstall_syncthing       update_syncthing          get_version_syncthing
register_utility "Termius SSH Client"  install_termius         check_termius         uninstall_termius         update_termius            get_version_termius
register_utility "Timeshift"           install_timeshift       check_timeshift       uninstall_timeshift       update_timeshift          get_version_timeshift
register_utility "Visual Studio Code"  install_vscode          check_vscode          uninstall_vscode          update_vscode             get_version_vscode

check_dotfiles() {
    [[ -d ~/dotfiles ]] && [[ -f ~/.zshrc ]]
}

# --- NVIDIA Drivers & Toolkit ---
check_nvidia_drivers() {
    command -v nvidia-smi &>/dev/null || lsmod | grep -q "^nvidia"
}
get_version_nvidia_drivers() {
    nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null | head -1 || echo ""
}

install_nvtop_package() {
    echo "Installing nvtop..."
    case "$PKG_MGR" in
        apt)
            sudo apt-get update
            sudo apt-get install -y nvtop
            ;;
        dnf|yum)
            sudo "$PKG_MGR" install -y nvtop
            ;;
        pacman)
            sudo pacman -S --noconfirm nvtop
            ;;
        zypper)
            sudo zypper install -y nvtop
            ;;
    esac
}

install_nvidia_container_toolkit() {
    echo "Installing NVIDIA Container Toolkit for Docker..."
    case "$DISTRO_FAMILY" in
        debian)
            ensure_tools
            curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | \
                sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
            curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
                sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
                sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list >/dev/null
            sudo apt-get update
            sudo apt-get install -y nvidia-container-toolkit
            ;;
        fedora|rhel)
            ensure_tools
            curl -s -L https://nvidia.github.io/libnvidia-container/gpgkey | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
            curl -s -L https://nvidia.github.io/libnvidia-container/stable/rpm/nvidia-container-toolkit.repo | \
                sudo tee /etc/yum.repos.d/nvidia-container-toolkit.repo >/dev/null
            sudo "$PKG_MGR" makecache
            sudo "$PKG_MGR" install -y nvidia-container-toolkit
            ;;
        arch)
            pkg_install nvidia-container-toolkit
            ;;
        suse)
            curl -s -L https://nvidia.github.io/libnvidia-container/gpgkey | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
            curl -s -L https://nvidia.github.io/libnvidia-container/stable/rpm/nvidia-container-toolkit.repo | \
                sudo tee /etc/zypp/repos.d/nvidia-container-toolkit.repo >/dev/null
            sudo zypper refresh
            sudo zypper install -y nvidia-container-toolkit
            ;;
        *)
            warn "NVIDIA Container Toolkit installation not implemented for ${DISTRO_NAME}."
            return 1
            ;;
    esac
}

# --- NVIDIA i386 / 32-bit library helpers ---

# Save the selected NVIDIA driver version to a persistent config file so that
# other installers (e.g. Steam) can reference it later.
save_nvidia_driver_version() {
    local version="$1"
    mkdir -p "$(dirname "$NVIDIA_VERSION_FILE")"
    echo "$version" > "$NVIDIA_VERSION_FILE"
}

# Return the saved NVIDIA driver version, falling back to package detection.
get_nvidia_installed_version() {
    if [[ -f "$NVIDIA_VERSION_FILE" ]]; then
        cat "$NVIDIA_VERSION_FILE"
        return 0
    fi
    # Fallback: detect from installed packages
    case "$DISTRO_FAMILY" in
        debian)
            dpkg -l 'nvidia-driver-*' 2>/dev/null | grep '^ii' | \
                grep -oP 'nvidia-driver-\K[0-9]+' | sort -rn | head -1
            ;;
        *)
            echo ""
            ;;
    esac
}

# Return 0 if the matching NVIDIA 32-bit libraries are already installed.
check_nvidia_i386_libs() {
    local driver_version
    driver_version=$(get_nvidia_installed_version)
    [[ -z "$driver_version" ]] && return 1

    case "$DISTRO_FAMILY" in
        debian)
            dpkg -l "libnvidia-gl-${driver_version}:i386" 2>/dev/null | grep -q '^ii'
            ;;
        fedora|rhel)
            rpm -q nvidia-driver-libs.i686 &>/dev/null || \
                rpm -q xorg-x11-drv-nvidia-470xx-libs.i686 &>/dev/null || \
                rpm -q xorg-x11-drv-nvidia-390xx-libs.i686 &>/dev/null
            ;;
        arch)
            pacman -Qi lib32-nvidia-utils &>/dev/null
            ;;
        suse)
            rpm -q nvidia-32bit &>/dev/null
            ;;
        *)
            return 1
            ;;
    esac
}

# Install the NVIDIA 32-bit libraries that match the installed driver version.
# An explicit version can be passed as $1; otherwise the saved version is used.
install_nvidia_i386_libs() {
    local driver_version="${1:-}"
    if [[ -z "$driver_version" ]]; then
        driver_version=$(get_nvidia_installed_version)
    fi

    if [[ -z "$driver_version" ]]; then
        warn "Cannot determine NVIDIA driver version for 32-bit library installation."
        return 1
    fi

    echo "Installing NVIDIA 32-bit libraries (version ${driver_version})..."
    case "$DISTRO_FAMILY" in
        debian)
            sudo dpkg --add-architecture i386
            sudo apt update

            # Show currently installed NVIDIA driver to confirm version
            echo "Installed NVIDIA driver packages:"
            dpkg -l | grep nvidia-driver || echo "  (none found)"

            echo "Installing libnvidia-gl-${driver_version}:i386..."
            if ! sudo apt install -y "libnvidia-gl-${driver_version}:i386"; then
                echo ""
                echo "⚠  libnvidia-gl-${driver_version}:i386 is unavailable via apt."
                echo "Alternative: manually extract 32-bit libraries from the NVIDIA installer."
                echo ""
                echo "  1. Download the driver .run file from NVIDIA's website:"
                echo "     https://www.nvidia.com/en-us/drivers/"
                echo "     (e.g. NVIDIA-Linux-x86_64-${driver_version}.run)"
                echo ""
                echo "  2. Extract the installer:"
                echo "     sudo ./NVIDIA-Linux-x86_64-${driver_version}.run -x"
                echo ""
                echo "  3. Copy 32-bit libraries to /usr/lib32:"
                echo "     sudo cp NVIDIA-Linux-x86_64-${driver_version}/32/*.so* /usr/lib32/"
                echo "     sudo ldconfig"
                echo ""
                warn "32-bit library installation incomplete. Use the manual method above if needed."
                return 1
            fi
            ;;
        fedora|rhel)
            case "$driver_version" in
                470xx)
                    sudo "$PKG_MGR" install -y xorg-x11-drv-nvidia-470xx-libs.i686
                    ;;
                390xx)
                    sudo "$PKG_MGR" install -y xorg-x11-drv-nvidia-390xx-libs.i686
                    ;;
                *)
                    sudo "$PKG_MGR" install -y nvidia-driver-libs.i686
                    ;;
            esac
            ;;
        arch)
            sudo pacman -S --noconfirm lib32-nvidia-utils
            ;;
        suse)
            if [[ "$driver_version" =~ ^G0[0-9]$ ]]; then
                sudo zypper install -y "nvidia-${driver_version}-32bit" 2>/dev/null || \
                    sudo zypper install -y nvidia-32bit 2>/dev/null || true
            else
                sudo zypper install -y "libnvidia-gl${driver_version}-32bit" 2>/dev/null || \
                    sudo zypper install -y nvidia-32bit 2>/dev/null || true
            fi
            ;;
        *)
            warn "NVIDIA 32-bit library installation not implemented for ${DISTRO_NAME}."
            return 1
            ;;
    esac
}

install_nvidia_drivers() {
    echo "Installing NVIDIA drivers..."
    ensure_tools

    local driver_version=""
    local -a available_drivers=()

    # Detect available NVIDIA drivers based on distribution
    case "$DISTRO_FAMILY" in
        debian)
            echo "Detecting available NVIDIA drivers..."
            pkg_refresh >/dev/null 2>&1
            
            if [[ "$DISTRO_ID" == "ubuntu" ]]; then
                command -v ubuntu-drivers &>/dev/null || sudo apt-get install -y ubuntu-drivers-common
                mapfile -t available_drivers < <(ubuntu-drivers list --gpgpu 2>/dev/null | grep -oP 'nvidia-driver-\K[0-9]+' | sort -rn | uniq)
            else
                # Debian and derivatives
                mapfile -t available_drivers < <(apt-cache search '^nvidia-driver-[0-9]+$' 2>/dev/null | grep -oP 'nvidia-driver-\K[0-9]+' | sort -rn | uniq)
            fi
            ;;
        fedora|rhel)
            echo "Detecting available NVIDIA drivers..."
            
            # Check if RPM Fusion (nonfree) is enabled
            if ! dnf repolist 2>/dev/null | grep -qi 'rpmfusion.*nonfree'; then
                echo ""
                echo "[!] RPM Fusion (nonfree) repository is required for NVIDIA drivers on Fedora/RHEL."
                echo ""
                read -rp "Would you like to enable RPM Fusion repositories now? (y/N): " enable_rpmfusion
                
                if [[ "$enable_rpmfusion" =~ ^[Yy]$ ]]; then
                    echo "Enabling RPM Fusion repositories..."
                    if [[ "$DISTRO_ID" == "fedora" ]]; then
                        sudo "$PKG_MGR" install -y \
                            "https://download1.rpmfusion.org/free/fedora/rpmfusion-free-release-${DISTRO_VERSION_ID}.noarch.rpm" \
                            "https://download1.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-${DISTRO_VERSION_ID}.noarch.rpm"
                    else
                        # RHEL/CentOS
                        sudo "$PKG_MGR" install -y \
                            "https://download1.rpmfusion.org/free/el/rpmfusion-free-release-${DISTRO_VERSION_ID}.noarch.rpm" \
                            "https://download1.rpmfusion.org/nonfree/el/rpmfusion-nonfree-release-${DISTRO_VERSION_ID}.noarch.rpm"
                    fi
                    pkg_refresh >/dev/null 2>&1
                else
                    warn "RPM Fusion is required for NVIDIA drivers. Installation cancelled."
                    return 1
                fi
            fi
            
            pkg_refresh >/dev/null 2>&1
            
            # Check for available NVIDIA driver packages
            # Main driver: akmod-nvidia (latest, recommended)
            if $PKG_MGR list available akmod-nvidia &>/dev/null; then
                available_drivers+=("latest")
            fi
            
            # Legacy drivers
            if $PKG_MGR list available xorg-x11-drv-nvidia-470xx &>/dev/null; then
                available_drivers+=("470xx")
            fi
            
            if $PKG_MGR list available xorg-x11-drv-nvidia-390xx &>/dev/null; then
                available_drivers+=("390xx")
            fi
            
            # Also check for any kmod-nvidia versioned packages
            local kmod_versions
            mapfile -t kmod_versions < <($PKG_MGR list available 'kmod-nvidia-*' 2>/dev/null | grep -oP 'kmod-nvidia-\K[0-9]+' | sort -rn | uniq)
            available_drivers+=("${kmod_versions[@]}")
            ;;
        arch)
            echo "Detecting available NVIDIA drivers..."
            # Arch typically has nvidia (latest), nvidia-lts, nvidia-dkms
            available_drivers=("latest" "dkms" "lts")
            ;;
        suse)
            echo "Detecting available NVIDIA drivers..."
            pkg_refresh >/dev/null 2>&1
            
            mapfile -t available_drivers < <(zypper search -s nvidia-driver 2>/dev/null | grep -oP 'nvidia-driver-\K[0-9]+' | sort -rn | uniq)
            
            # Check for G06/G05 packages (openSUSE naming)
            if zypper search -s nvidia-computeG06 &>/dev/null; then
                available_drivers+=("G06")
            fi
            if zypper search -s nvidia-computeG05 &>/dev/null; then
                available_drivers+=("G05")
            fi
            ;;
        *)
            warn "NVIDIA driver detection not implemented for ${DISTRO_NAME}."
            return 1
            ;;
    esac

    # Display available drivers and let user select
    if [[ ${#available_drivers[@]} -eq 0 ]]; then
        warn "No NVIDIA drivers found in repositories. Please check your repository configuration."
        return 1
    fi

    echo ""
    echo "Available NVIDIA driver versions:"
    echo "────────────────────────────────────────────────────────────────"
    for i in "${!available_drivers[@]}"; do
        echo "  $((i+1)). ${available_drivers[$i]}"
    done
    echo "  0. Cancel"
    echo "────────────────────────────────────────────────────────────────"
    
    local choice
    read -rp "Select driver version to install (1-${#available_drivers[@]}, or 0 to cancel): " choice
    
    if [[ "$choice" == "0" ]] || [[ -z "$choice" ]]; then
        warn "Installation cancelled."
        return 1
    fi
    
    if [[ "$choice" =~ ^[0-9]+$ ]] && [[ "$choice" -ge 1 ]] && [[ "$choice" -le ${#available_drivers[@]} ]]; then
        driver_version="${available_drivers[$((choice-1))]}"
        echo "Selected driver version: $driver_version"
        # Persist the chosen version so other installers (e.g. Steam) can reference it
        save_nvidia_driver_version "$driver_version"
    else
        warn "Invalid selection. Cancelling installation."
        return 1
    fi

    # Install the selected driver
    case "$DISTRO_FAMILY" in
        debian)
            sudo apt-get update
            sudo apt-get install -y "nvidia-driver-${driver_version}"
            ;;
        fedora|rhel)
            case "$driver_version" in
                latest)
                    echo "Installing latest NVIDIA driver (akmod-nvidia)..."
                    sudo "$PKG_MGR" install -y akmod-nvidia xorg-x11-drv-nvidia-cuda
                    ;;
                470xx)
                    echo "Installing legacy NVIDIA 470 driver..."
                    sudo "$PKG_MGR" install -y xorg-x11-drv-nvidia-470xx akmod-nvidia-470xx
                    ;;
                390xx)
                    echo "Installing legacy NVIDIA 390 driver..."
                    sudo "$PKG_MGR" install -y xorg-x11-drv-nvidia-390xx akmod-nvidia-390xx
                    ;;
                [0-9]*)
                    echo "Installing NVIDIA driver version ${driver_version}..."
                    sudo "$PKG_MGR" install -y "kmod-nvidia-${driver_version}"
                    ;;
                *)
                    warn "Unknown driver version: ${driver_version}"
                    return 1
                    ;;
            esac
            ;;
        arch)
            case "$driver_version" in
                latest)
                    sudo pacman -S --noconfirm nvidia nvidia-utils
                    ;;
                dkms)
                    sudo pacman -S --noconfirm nvidia-dkms nvidia-utils
                    ;;
                lts)
                    sudo pacman -S --noconfirm nvidia-lts nvidia-utils
                    ;;
            esac
            ;;
        suse)
            if [[ "$driver_version" =~ ^G0[0-9]$ ]]; then
                sudo zypper install -y "nvidia-compute${driver_version}"
            else
                sudo zypper install -y "nvidia-driver-${driver_version}"
            fi
            ;;
    esac

    # Install matching 32-bit libraries (required by Steam and other 32-bit apps)
    install_nvidia_i386_libs "$driver_version"

    install_nvtop_package

    if check_docker; then
        install_nvidia_container_toolkit || warn "Failed to install NVIDIA Container Toolkit."
    else
        info "Docker not detected. Skipping NVIDIA Container Toolkit installation."
    fi
}

uninstall_nvidia_drivers() {
    echo "Uninstalling NVIDIA drivers..."
    case "$PKG_MGR" in
        apt)
            sudo apt-get remove -y 'nvidia-driver-*' nvtop
            sudo apt-get autoremove -y
            ;;
        dnf|yum)
            sudo "$PKG_MGR" remove -y nvidia* nvtop
            ;;
        pacman)
            sudo pacman -Rs --noconfirm nvidia nvidia-utils nvtop 2>/dev/null || true
            ;;
        zypper)
            sudo zypper remove -y nvidia* nvtop
            ;;
    esac
}

update_nvidia_drivers() {
    install_nvidia_drivers
}

# --- Bitwarden Client ---

check_bitwarden() {
    command -v bitwarden &>/dev/null || \
        (has_snap && snap list bitwarden &>/dev/null) || \
        (has_flatpak && flatpak list 2>/dev/null | grep -qi bitwarden) || \
        pkg_check_installed bitwarden-bin || \
        pkg_check_installed bitwarden
}
install_bitwarden() {
    echo "Installing Bitwarden Client..."
    case "$DISTRO_FAMILY" in
        debian)
            ensure_tools
            local tmp_deb
            tmp_deb=$(mktemp /tmp/bitwarden-XXXXXX.deb)
            CLEANUP_FILES+=("$tmp_deb")
            if ! wget -qO "$tmp_deb" "https://vault.bitwarden.com/download/?app=desktop&platform=linux&variant=deb"; then
                echo "Error: Failed to download Bitwarden .deb."
                rm -f "$tmp_deb"
                return 1
            fi
            # Try installing; if deps are missing, fix them and retry
            if ! sudo dpkg -i "$tmp_deb"; then
                sudo apt-get install -f -y || true
                if ! sudo dpkg -i "$tmp_deb"; then
                    echo "Error: Failed to install Bitwarden .deb."
                    rm -f "$tmp_deb"
                    return 1
                fi
            fi
            rm -f "$tmp_deb"
            ;;
        fedora|rhel)
            ensure_tools
            local tmp_rpm
            tmp_rpm=$(mktemp /tmp/bitwarden-XXXXXX.rpm)
            CLEANUP_FILES+=("$tmp_rpm")
            if ! wget -qO "$tmp_rpm" "https://vault.bitwarden.com/download/?app=desktop&platform=linux&variant=rpm"; then
                echo "Error: Failed to download Bitwarden .rpm."
                rm -f "$tmp_rpm"
                return 1
            fi
            if ! sudo "$PKG_MGR" install -y "$tmp_rpm"; then
                echo "Error: Failed to install Bitwarden .rpm."
                rm -f "$tmp_rpm"
                return 1
            fi
            rm -f "$tmp_rpm"
            ;;
        arch)
            if has_aur_helper; then
                aur_install bitwarden-bin
            else
                aur_build bitwarden-bin
            fi
            ;;
        *)
            if has_snap; then
                sudo snap install bitwarden
            elif has_flatpak; then
                flatpak install -y flathub com.bitwarden.desktop
            else
                echo "Error: snap or flatpak is required to install Bitwarden."
                return 1
            fi
            ;;
    esac
}
uninstall_bitwarden() {
    echo "Uninstalling Bitwarden Client..."
    if has_snap && snap list bitwarden &>/dev/null; then
        sudo snap remove bitwarden
    elif has_flatpak && flatpak list 2>/dev/null | grep -qi bitwarden; then
        flatpak uninstall -y com.bitwarden.desktop
    elif pkg_check_installed bitwarden-bin; then
        pkg_remove bitwarden-bin
    elif pkg_check_installed bitwarden; then
        pkg_remove bitwarden
    else
        echo "Bitwarden installation not found."
        return 1
    fi
}
update_bitwarden() {
    echo "Updating Bitwarden Client..."
    if has_snap && snap list bitwarden &>/dev/null; then
        sudo snap refresh bitwarden
    elif has_flatpak && flatpak list 2>/dev/null | grep -qi bitwarden; then
        flatpak update -y com.bitwarden.desktop
    elif [[ "$DISTRO_FAMILY" == "debian" ]]; then
        install_bitwarden
    elif [[ "$DISTRO_FAMILY" == "fedora" || "$DISTRO_FAMILY" == "rhel" ]]; then
        install_bitwarden
    elif pkg_check_installed bitwarden-bin; then
        if has_aur_helper; then
            aur_upgrade bitwarden-bin
        else
            install_bitwarden
        fi
    elif pkg_check_installed bitwarden; then
        pkg_upgrade bitwarden
    else
        echo "Bitwarden installation not found."
        return 1
    fi
}
get_version_bitwarden() {
    if has_snap && snap list bitwarden &>/dev/null; then
        snap list bitwarden 2>/dev/null | awk 'NR==2{print $2}'
    elif has_flatpak && flatpak list 2>/dev/null | grep -qi bitwarden; then
        flatpak list 2>/dev/null | grep -i bitwarden | awk -F'\t' '{print $3}'
    elif pkg_check_installed bitwarden-bin; then
        pkg_get_version bitwarden-bin
    elif pkg_check_installed bitwarden; then
        pkg_get_version bitwarden
    else
        echo ""
    fi
}

# --- Brave Browser ---

check_brave() {
    command -v brave-browser &>/dev/null || pkg_check_installed brave-browser
}
install_brave() {
    echo "Installing Brave Browser..."
    ensure_tools
    case "$DISTRO_FAMILY" in
        debian)
            sudo curl -fsSLo /usr/share/keyrings/brave-browser-archive-keyring.gpg \
                https://brave-browser-apt-release.s3.brave.com/brave-browser-archive-keyring.gpg
            echo "deb [signed-by=/usr/share/keyrings/brave-browser-archive-keyring.gpg] https://brave-browser-apt-release.s3.brave.com/ stable main" | \
                sudo tee /etc/apt/sources.list.d/brave-browser-release.list > /dev/null
            sudo apt update
            sudo apt install -y brave-browser
            ;;
        fedora|rhel)
            sudo "$PKG_MGR" install -y dnf-plugins-core 2>/dev/null || true
            sudo curl -fsSLo /etc/yum.repos.d/brave-browser.repo https://brave-browser-rpm-release.s3.brave.com/brave-browser.repo
            sudo rpm --import https://brave-browser-rpm-release.s3.brave.com/brave-core.asc
            sudo "$PKG_MGR" install -y brave-browser
            ;;
        arch)
            if has_aur_helper; then
                aur_install brave-bin
            else
                aur_build brave-bin
            fi
            ;;
        suse)
            sudo rpm --import https://brave-browser-rpm-release.s3.brave.com/brave-core.asc
            sudo zypper addrepo -f https://brave-browser-rpm-release.s3.brave.com/brave-browser.repo brave-browser 2>/dev/null || true
            sudo zypper refresh
            sudo zypper install -y brave-browser
            ;;
    esac
}
uninstall_brave() {
    echo "Uninstalling Brave Browser..."
    case "$DISTRO_FAMILY" in
        debian)
            sudo apt remove -y brave-browser
            sudo rm -f /etc/apt/sources.list.d/brave-browser-release.list
            sudo rm -f /usr/share/keyrings/brave-browser-archive-keyring.gpg
            ;;
        fedora|rhel)
            sudo "$PKG_MGR" remove -y brave-browser
            sudo rm -f /etc/yum.repos.d/brave-browser.repo
            ;;
        arch)
            aur_remove brave-bin 2>/dev/null || pkg_remove brave-browser 2>/dev/null || true
            ;;
        suse)
            sudo zypper remove -y brave-browser
            sudo zypper removerepo brave-browser 2>/dev/null || true
            ;;
    esac
}
update_brave() {
    echo "Updating Brave Browser..."
    case "$DISTRO_FAMILY" in
        debian)
            sudo apt update
            sudo apt upgrade -y brave-browser
            ;;
        arch)
            if has_aur_helper; then
                aur_upgrade brave-bin
            else
                aur_build brave-bin
            fi
            ;;
        *)
            pkg_upgrade brave-browser
            ;;
    esac
}
get_version_brave() {
    brave-browser --version 2>/dev/null | grep -oP 'Brave Browser \K[0-9]+\.[0-9]+\.[0-9]+' || echo ""
}

# --- Joplin Client ---

# Detect and export the desktop environment for AppImage installers (Joplin, etc.)
detect_and_export_desktop_env() {
    local desktop_env=""
    if [[ -n "${XDG_CURRENT_DESKTOP:-}" ]]; then
        desktop_env="$XDG_CURRENT_DESKTOP"
    elif command -v plasmashell &>/dev/null; then
        desktop_env="KDE"
    elif command -v gnome-shell &>/dev/null; then
        desktop_env="GNOME"
    elif command -v xfce4-session &>/dev/null; then
        desktop_env="XFCE"
    elif command -v cinnamon &>/dev/null; then
        desktop_env="X-Cinnamon"
    fi
    if [[ -n "$desktop_env" ]]; then
        export XDG_CURRENT_DESKTOP="$desktop_env"
    fi
}

check_joplin() {
    [[ -f ~/.joplin/Joplin.AppImage ]] || command -v joplin &>/dev/null
}
install_joplin() {
    echo "Installing Joplin Client..."
    detect_and_export_desktop_env

    # Download and run installer script
    local install_script
    install_script=$(wget -qO- https://raw.githubusercontent.com/laurent22/joplin/dev/Joplin_install_and_update.sh) || {
        echo "Error: Failed to download Joplin installer script."
        return 1
    }
    
    if [[ -z "$install_script" ]]; then
        echo "Error: Downloaded installer script is empty."
        return 1
    fi
    
    echo "$install_script" | bash || {
        echo "Error: Joplin installation script failed."
        return 1
    }

    # Ubuntu 24.04+ restricts unprivileged user namespaces via AppArmor,
    # which breaks Electron-based AppImages like Joplin (causes SIGTRAP crash).
    if [[ "$DISTRO_ID" == "ubuntu" ]] && [[ "${DISTRO_VERSION_ID%%.*}" -ge 24 ]]; then
        local sysctl_file="/etc/sysctl.d/99-appimage-userns.conf"
        local sysctl_key="kernel.apparmor_restrict_unprivileged_userns"
        if [[ "$(sysctl -n "$sysctl_key" 2>/dev/null)" == "1" ]]; then
            echo "Configuring system to allow AppImage user namespaces (required for Joplin on Ubuntu 24.04+)..."
            echo "${sysctl_key}=0" | sudo tee "$sysctl_file" >/dev/null
            sudo sysctl --system >/dev/null 2>&1
            echo "AppImage user namespace restriction disabled."
        fi
    fi
}
uninstall_joplin() {
    echo "Uninstalling Joplin Client..."
    rm -rf ~/.joplin
    rm -f ~/.local/share/applications/joplin.desktop
    rm -f ~/.local/share/applications/appimagekit-joplin.desktop
    rm -f ~/.local/share/icons/hicolor/*/apps/joplin.png
    rm -f ~/.local/share/icons/hicolor/*/apps/appimagekit-joplin.png
    rm -f ~/.local/bin/joplin
    command -v update-desktop-database &>/dev/null && update-desktop-database ~/.local/share/applications || true
    command -v gtk-update-icon-cache &>/dev/null && gtk-update-icon-cache ~/.local/share/icons/hicolor || true
}
update_joplin() {
    echo "Updating Joplin Client..."
    detect_and_export_desktop_env
    wget -O - https://raw.githubusercontent.com/laurent22/joplin/dev/Joplin_install_and_update.sh | bash
}
get_version_joplin() {
    # NOTE: Do NOT run the AppImage with --version — it opens a GUI error dialog.
    local pkg_json="$HOME/.config/joplin-desktop/package.json"
    if [[ -f "$pkg_json" ]]; then
        grep -oP '"version"\s*:\s*"\K[^"]+' "$pkg_json" 2>/dev/null || echo ""
    else
        echo ""
    fi
}

# --- LibreOffice ---

check_libreoffice() {
    command -v libreoffice &>/dev/null || \
        command -v soffice &>/dev/null || \
        pkg_check_installed libreoffice || \
        pkg_check_installed libreoffice-common || \
        pkg_check_installed libreoffice-fresh || \
        pkg_check_installed libreoffice-still || \
        (has_flatpak && flatpak list 2>/dev/null | grep -qi libreoffice)
}
install_libreoffice() {
    echo "Installing LibreOffice..."
    case "$DISTRO_FAMILY" in
        debian)
            sudo add-apt-repository -y ppa:libreoffice/ppa
            sudo apt update
            sudo apt install -y libreoffice
            ;;
        fedora|rhel)
            sudo "$PKG_MGR" install -y libreoffice
            ;;
        arch)
            sudo pacman -S --noconfirm libreoffice-fresh
            ;;
        suse)
            sudo zypper install -y libreoffice
            ;;
        *)
            if has_flatpak; then
                flatpak install -y flathub org.libreoffice.LibreOffice
            else
                echo "Error: Unsupported distribution and flatpak is not available."
                return 1
            fi
            ;;
    esac
}
uninstall_libreoffice() {
    echo "Uninstalling LibreOffice..."
    case "$DISTRO_FAMILY" in
        debian)
            sudo apt remove -y libreoffice*
            sudo apt autoremove -y
            ;;
        fedora|rhel)
            sudo "$PKG_MGR" remove -y libreoffice*
            sudo "$PKG_MGR" autoremove -y
            ;;
        arch)
            sudo pacman -Rs --noconfirm libreoffice-fresh 2>/dev/null || \
                sudo pacman -Rs --noconfirm libreoffice-still 2>/dev/null || true
            ;;
        suse)
            sudo zypper remove -y libreoffice
            ;;
        *)
            if has_flatpak && flatpak list 2>/dev/null | grep -qi libreoffice; then
                flatpak uninstall -y org.libreoffice.LibreOffice
            fi
            ;;
    esac
    echo "LibreOffice has been uninstalled."
}
update_libreoffice() {
    echo "Updating LibreOffice..."
    case "$DISTRO_FAMILY" in
        debian)
            sudo add-apt-repository -y ppa:libreoffice/ppa
            sudo apt update
            sudo apt upgrade -y libreoffice
            ;;
        fedora|rhel)
            sudo "$PKG_MGR" upgrade -y libreoffice
            ;;
        arch)
            sudo pacman -S --noconfirm libreoffice-fresh
            ;;
        suse)
            sudo zypper update -y libreoffice
            ;;
        *)
            if has_flatpak && flatpak list 2>/dev/null | grep -qi libreoffice; then
                flatpak update -y org.libreoffice.LibreOffice
            fi
            ;;
    esac
}
get_version_libreoffice() {
    libreoffice --version 2>/dev/null | grep -oP 'LibreOffice \K[0-9]+\.[0-9]+\.[0-9]+(\.[0-9]+)?' || echo ""
}

# --- Termius SSH Client ---

check_termius() {
    command -v termius &>/dev/null || \
        command -v termius-app &>/dev/null || \
        pkg_check_installed termius || \
        pkg_check_installed termius-app || \
        (has_snap && snap list termius-app &>/dev/null) || \
        (has_flatpak && flatpak list 2>/dev/null | grep -qi termius)
}
install_termius() {
    echo "Installing Termius SSH Client..."
    case "$DISTRO_FAMILY" in
        debian)
            wget -q https://www.termius.com/download/linux/Termius.deb -O /tmp/termius.deb
            sudo apt install -y /tmp/termius.deb
            rm -f /tmp/termius.deb
            ;;
        arch)
            if has_aur_helper; then
                aur_install termius
            else
                aur_build termius
            fi
            ;;
        *)
            if has_snap; then
                sudo snap install termius-app
            elif has_flatpak; then
                # Ensure flathub remote is properly configured
                if ! flatpak remotes | grep -q flathub; then
                    echo "Adding flathub remote..."
                    flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
                fi
                flatpak install -y flathub com.termius.Termius
            else
                echo "Error: snap or flatpak is required to install Termius on ${DISTRO_NAME}."
                return 1
            fi
            ;;
    esac
}
uninstall_termius() {
    echo "Uninstalling Termius SSH Client..."
    if pkg_check_installed termius; then
        pkg_remove termius
    elif pkg_check_installed termius-app; then
        pkg_remove termius-app
    elif has_snap && snap list termius-app &>/dev/null; then
        sudo snap remove termius-app
    elif has_flatpak && flatpak list 2>/dev/null | grep -qi termius; then
        flatpak uninstall -y com.termius.Termius
    else
        echo "Termius installation not found."
        return 1
    fi
}
update_termius() {
    echo "Updating Termius SSH Client..."
    case "$DISTRO_FAMILY" in
        debian)
            wget -q https://www.termius.com/download/linux/Termius.deb -O /tmp/termius.deb
            sudo apt install -y /tmp/termius.deb
            rm -f /tmp/termius.deb
            ;;
        arch)
            if has_aur_helper; then
                aur_upgrade termius
            else
                aur_build termius
            fi
            ;;
        *)
            if has_snap && snap list termius-app &>/dev/null; then
                sudo snap refresh termius-app
            elif has_flatpak && flatpak list 2>/dev/null | grep -qi termius; then
                flatpak update -y com.termius.Termius
            else
                echo "Termius installation not found or no supported update method."
                return 1
            fi
            ;;
    esac
}
get_version_termius() {
    if pkg_check_installed termius; then
        pkg_get_version termius
    elif pkg_check_installed termius-app; then
        pkg_get_version termius-app
    elif has_snap && snap list termius-app &>/dev/null; then
        snap list termius-app 2>/dev/null | awk 'NR==2{print $2}'
    elif has_flatpak && flatpak list 2>/dev/null | grep -qi termius; then
        flatpak list 2>/dev/null | grep -i termius | awk -F'\t' '{print $3}'
    else
        echo ""
    fi
}

# --- Devolutions RDM ---

check_devolutions_rdm() {
    command -v remotedesktopmanager &>/dev/null || pkg_check_installed RemoteDesktopManager || pkg_check_installed remotedesktopmanager || pkg_check_installed remote-desktop-manager
}
install_devolutions_rdm() {
    echo "Installing Devolutions RDM..."
    ensure_tools
    case "$DISTRO_FAMILY" in
        debian)
            # Ubuntu/Debian repository setup
            echo "Setting up Cloudsmith repository for Remote Desktop Manager..."

            # KDE Neon has ID=neon which Cloudsmith's setup.deb.sh doesn't recognise.
            # Manually add the Ubuntu-based repo using the upstream Ubuntu codename.
            if [[ "$DISTRO_ID" == "neon" ]]; then
                local ubuntu_codename="${DISTRO_VERSION_CODENAME}"
                # Fallback: read from KDE Neon's upstream release file
                if [[ -z "$ubuntu_codename" && -f /etc/upstream-release/lsb-release ]]; then
                    ubuntu_codename=$(grep -oP '(?<=DISTRIB_CODENAME=).+' /etc/upstream-release/lsb-release)
                fi
                ubuntu_codename="${ubuntu_codename:-noble}"
                echo "KDE Neon detected (Ubuntu ${ubuntu_codename} base). Configuring repository manually..."
                curl -1sLf 'https://dl.cloudsmith.io/public/devolutions/rdm/gpg.FE7407ECB26FD2FE.key' | \
                    sudo gpg --dearmor -o /usr/share/keyrings/devolutions-rdm.gpg
                echo "deb [signed-by=/usr/share/keyrings/devolutions-rdm.gpg] https://dl.cloudsmith.io/public/devolutions/rdm/deb/ubuntu ${ubuntu_codename} main" | \
                    sudo tee /etc/apt/sources.list.d/devolutions-rdm.list > /dev/null
            else
                curl -1sLf 'https://dl.cloudsmith.io/public/devolutions/rdm/setup.deb.sh' | sudo -E bash
            fi

            # Install required packages for repository management
            sudo apt-get install -y apt-transport-https 2>/dev/null || true

            # Update package lists and install Remote Desktop Manager
            sudo apt-get update
            sudo apt-get install -y remotedesktopmanager
            ;;
        fedora|rhel)
            # Fedora/RHEL repository setup
            echo "Setting up Cloudsmith repository for Remote Desktop Manager..."
            
            # Ensure required tools
            sudo "$PKG_MGR" install -y dnf-plugins-core pygpgme 2>/dev/null || true
            
            # Import GPG key
            sudo rpm --import 'https://dl.cloudsmith.io/public/devolutions/rdm/gpg.FE7407ECB26FD2FE.key'
            
            # Add repository
            curl -1sLf "https://dl.cloudsmith.io/public/devolutions/rdm/config.rpm.txt?distro=${DISTRO_ID}&codename=${DISTRO_VERSION_ID}" | \
                sudo tee /etc/yum.repos.d/devolutions-rdm.repo > /dev/null
            
            # Update repository cache and install
            sudo "$PKG_MGR" makecache -y
            sudo "$PKG_MGR" install -y RemoteDesktopManager
            ;;
        arch)
            # Arch-based distributions using AUR
            if has_aur_helper; then
                echo "Installing from AUR..."
                aur_install remote-desktop-manager
            else
                aur_build remote-desktop-manager
            fi
            ;;
        suse)
            # openSUSE support via Flatpak or snap (as direct repos may not be available)
            if has_flatpak; then
                echo "Installing via Flatpak..."
                flatpak install -y flathub com.devolutions.RemoteDesktopManager
            elif has_snap; then
                echo "Installing via Snap..."
                sudo snap install remote-desktop-manager
            else
                echo "Error: Flatpak or Snap is required to install Remote Desktop Manager on this distribution."
                echo "Please install flatpak or snap first."
                return 1
            fi
            ;;
        *)
            # Fallback to Flatpak or Snap
            if has_flatpak; then
                echo "Installing via Flatpak..."
                flatpak install -y flathub com.devolutions.RemoteDesktopManager
            elif has_snap; then
                echo "Installing via Snap..."
                sudo snap install remote-desktop-manager
            else
                echo "Error: No compatible installation method found for this distribution."
                return 1
            fi
            ;;
    esac
}
uninstall_devolutions_rdm() {
    echo "Uninstalling Devolutions RDM..."
    case "$DISTRO_FAMILY" in
        debian|fedora|rhel)
            pkg_remove RemoteDesktopManager 2>/dev/null || pkg_remove remotedesktopmanager 2>/dev/null || pkg_remove remote-desktop-manager 2>/dev/null || true
            # Clean up repository configuration for Debian
            if [[ "$DISTRO_FAMILY" == "debian" ]]; then
                sudo rm -f /etc/apt/sources.list.d/devolutions-rdm.list
            fi
            # Clean up repository configuration for RHEL/Fedora
            if [[ "$DISTRO_FAMILY" == "fedora" ]] || [[ "$DISTRO_FAMILY" == "rhel" ]]; then
                sudo rm -f /etc/yum.repos.d/devolutions-rdm.repo
            fi
            ;;
        arch)
            aur_remove remote-desktop-manager 2>/dev/null || pkg_remove remote-desktop-manager 2>/dev/null || true
            ;;
        *)
            if has_flatpak && flatpak list 2>/dev/null | grep -qi "remote.*desktop.*manager\|RemoteDesktopManager"; then
                flatpak uninstall -y com.devolutions.RemoteDesktopManager || true
            elif has_snap && snap list 2>/dev/null | grep -qi "remote-desktop-manager"; then
                sudo snap remove remote-desktop-manager || true
            else
                pkg_remove remotedesktopmanager 2>/dev/null || pkg_remove remote-desktop-manager 2>/dev/null || true
            fi
            ;;
    esac
}
update_devolutions_rdm() {
    echo "Updating Devolutions RDM..."
    case "$DISTRO_FAMILY" in
        debian)
            sudo apt update
            sudo apt install --only-upgrade -y remotedesktopmanager
            ;;
        fedora|rhel)
            sudo "$PKG_MGR" upgrade -y RemoteDesktopManager
            ;;
        arch)
            if has_aur_helper; then
                aur_upgrade remote-desktop-manager
            else
                echo "Error: An AUR helper (yay/paru) is required."
                return 1
            fi
            ;;
        *)
            if has_flatpak && flatpak list 2>/dev/null | grep -qi "remote.*desktop.*manager\|RemoteDesktopManager"; then
                flatpak update -y com.devolutions.RemoteDesktopManager
            elif has_snap && snap list 2>/dev/null | grep -qi "remote-desktop-manager"; then
                sudo snap refresh remote-desktop-manager
            else
                pkg_upgrade remotedesktopmanager 2>/dev/null || true
            fi
            ;;
    esac
}
get_version_devolutions_rdm() {
    if command -v remotedesktopmanager &>/dev/null; then
        remotedesktopmanager --version 2>/dev/null | head -1 || echo ""
    elif pkg_check_installed RemoteDesktopManager; then
        pkg_get_version RemoteDesktopManager
    elif pkg_check_installed remotedesktopmanager; then
        pkg_get_version remotedesktopmanager
    elif pkg_check_installed remote-desktop-manager; then
        pkg_get_version remote-desktop-manager
    else
        echo ""
    fi
}

# --- Steam App ---

check_steam() {
    command -v steam &>/dev/null || \
        pkg_check_installed steam-installer || \
        pkg_check_installed steam-launcher || \
        (has_flatpak && flatpak list 2>/dev/null | grep -qi "com.valvesoftware.Steam")
}

# Helper function to ensure contrib component is enabled for Debian
ensure_debian_contrib() {
    if [[ "$DISTRO_FAMILY" != "debian" ]]; then
        return 0
    fi

    local _contrib_found=false

    # Check traditional sources.list format
    if [[ -f /etc/apt/sources.list ]] && \
       grep -qE "^deb .*debian.* main" /etc/apt/sources.list 2>/dev/null; then
        if grep -E "^deb .*debian.* main" /etc/apt/sources.list | grep -q "contrib"; then
            _contrib_found=true
        else
            echo "Steam requires the 'contrib' component in Debian repositories."
            echo "Enabling 'contrib' component in /etc/apt/sources.list..."
            sudo cp /etc/apt/sources.list "/etc/apt/sources.list.backup-$(date +%Y%m%d-%H%M%S)"
            sudo sed -i 's/^\(deb .*debian.* main\)\(.*\)/\1 contrib\2/' /etc/apt/sources.list
            # Deduplicate 'contrib' if it appeared twice
            sudo sed -i 's/contrib contrib/contrib/g' /etc/apt/sources.list
            _contrib_found=true
        fi
    fi

    # Check DEB822 format (.sources files, Debian 12+)
    local _sources_file
    for _sources_file in /etc/apt/sources.list.d/*.sources; do
        [[ -f "$_sources_file" ]] || continue
        if grep -qP '^Components:.*\bmain\b' "$_sources_file" 2>/dev/null; then
            if grep -qP '^Components:.*\bcontrib\b' "$_sources_file" 2>/dev/null; then
                _contrib_found=true
            else
                echo "Adding 'contrib' component to $(basename "$_sources_file")..."
                sudo cp "$_sources_file" "${_sources_file}.backup-$(date +%Y%m%d-%H%M%S)"
                sudo sed -i 's/^\(Components:.*main\)/\1 contrib/' "$_sources_file"
                _contrib_found=true
            fi
        fi
    done

    if [[ "$_contrib_found" == "true" ]]; then
        echo "'contrib' component enabled. Updating package lists..."
        sudo apt update
    fi
}

# Helper function to detect mixed repository issues
detect_debian_repo_mix() {
    if [[ "$DISTRO_FAMILY" != "debian" ]]; then
        return 0
    fi
    
    local has_stable=false
    local has_testing=false
    local has_unstable=false
    
    # Check for different Debian releases in sources.list
    if grep -qE "^deb .*(bookworm|bullseye|buster)" /etc/apt/sources.list /etc/apt/sources.list.d/*.list 2>/dev/null; then
        has_stable=true
    fi
    if grep -qE "^deb .*(trixie|testing)" /etc/apt/sources.list /etc/apt/sources.list.d/*.list 2>/dev/null; then
        has_testing=true
    fi
    if grep -qE "^deb .*(sid|unstable)" /etc/apt/sources.list /etc/apt/sources.list.d/*.list 2>/dev/null; then
        has_unstable=true
    fi
    
    local mix_count=0
    $has_stable && ((mix_count++))
    $has_testing && ((mix_count++))
    $has_unstable && ((mix_count++))
    
    if [[ $mix_count -gt 1 ]]; then
        echo "⚠️  WARNING: Mixed Debian repositories detected!"
        echo "Your system has multiple Debian releases configured:"
        $has_stable && echo "  - Stable (Bookworm/Bullseye)"
        $has_testing && echo "  - Testing (Trixie)"
        $has_unstable && echo "  - Unstable (Sid)"
        echo "This can cause package version conflicts and dependency issues."
        echo "Consider using a single Debian release for better stability."
        echo ""
        return 1
    fi
    return 0
}
install_steam() {
    echo "Installing Steam..."

    # Steam requires NVIDIA 32-bit GL libraries to launch on NVIDIA systems.
    # Check whether they are present and install them if not.
    if check_nvidia_drivers; then
        if check_nvidia_i386_libs; then
            echo "NVIDIA 32-bit libraries already installed."
        else
            echo "NVIDIA drivers detected. Installing required 32-bit libraries for Steam..."
            install_nvidia_i386_libs || warn "Failed to install NVIDIA 32-bit libraries. Steam may not function correctly."
        fi
    fi

    case "$DISTRO_FAMILY" in
        debian)
            # Enable 32-bit architecture support
            sudo dpkg --add-architecture i386
            sudo apt update

            if [[ "$DISTRO_ID" == "ubuntu" ]]; then
                # Ubuntu / Kubuntu: install Steam via the multiverse repository
                echo "Enabling multiverse repository..."
                sudo add-apt-repository multiverse -y
                sudo apt update
                echo "Installing Steam..."
                if ! sudo apt install -y steam; then
                    echo "Error: Steam installation failed."
                    return 1
                fi
            else
                # Debian and other derivatives: download the official .deb installer
                echo "Downloading Steam installer from store.steampowered.com..."
                local steam_deb="/tmp/steam_latest.deb"
                if ! wget -O "$steam_deb" "https://cdn.akamai.steamstatic.com/client/installer/steam.deb"; then
                    echo "Error: Failed to download Steam installer."
                    rm -f "$steam_deb"
                    return 1
                fi

                # Install Steam - prompts will be shown for user to accept/decline
                echo "Installing Steam (follow any on-screen prompts)..."
                sudo apt install "$steam_deb"
                local install_result=$?
                rm -f "$steam_deb"

                if [[ $install_result -ne 0 ]]; then
                    echo "Error: Steam installation failed."
                    return 1
                fi
            fi
            ;;
        fedora)
            if ! rpm -q rpmfusion-nonfree-release &>/dev/null; then
                echo "Enabling RPM Fusion repositories (required for Steam)..."
                if ! sudo "$PKG_MGR" install -y \
                    "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm" \
                    "https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm"; then
                    echo "Error: Failed to enable RPM Fusion repositories."
                    return 1
                fi
                sudo "$PKG_MGR" makecache
            fi
            echo "Installing Steam from RPM Fusion..."
            if ! sudo "$PKG_MGR" install -y steam; then
                echo "Error: Failed to install Steam."
                return 1
            fi
            
            # Install graphics libraries for better compatibility
            echo "Installing graphics libraries (Vulkan, Mesa)..."
            sudo "$PKG_MGR" install -y mesa-vulkan-drivers vulkan-loader 2>/dev/null || true
            ;;
        rhel)
            echo "Steam is not officially available for RHEL-based distributions."
            if has_flatpak; then
                echo "Installing via Flatpak..."
                flatpak install -y flathub com.valvesoftware.Steam
            else
                echo "Consider installing Flatpak: https://flatpak.org/setup/"
                return 1
            fi
            ;;
        arch)
            if ! grep -q "^\[multilib\]" /etc/pacman.conf; then
                echo "Enabling multilib repository (required for 32-bit support)..."
                sudo bash -c 'echo -e "\n[multilib]\nInclude = /etc/pacman.d/mirrorlist" >> /etc/pacman.conf'
                sudo pacman -Sy
            fi
            echo "Installing Steam..."
            if ! sudo pacman -S --noconfirm steam; then
                echo "Error: Failed to install Steam."
                return 1
            fi
            
            # Install 32-bit graphics libraries for better compatibility
            echo "Installing 32-bit graphics libraries (Vulkan, Mesa)..."
            sudo pacman -S --noconfirm lib32-mesa lib32-vulkan-icd-loader lib32-vulkan-intel \
                lib32-vulkan-radeon lib32-nvidia-utils 2>/dev/null || true
            ;;
        suse)
            echo "Installing Steam..."
            if ! sudo zypper install -y steam; then
                echo "Error: Failed to install Steam."
                return 1
            fi
            
            # Install graphics libraries for better compatibility
            echo "Installing graphics libraries (Vulkan, Mesa)..."
            sudo zypper install -y libvulkan1 libvulkan1-32bit \
                Mesa-libGL1 Mesa-libGL1-32bit 2>/dev/null || true
            ;;
    esac
}
uninstall_steam() {
    echo "Uninstalling Steam..."
    if has_flatpak && flatpak list 2>/dev/null | grep -qi "com.valvesoftware.Steam"; then
        flatpak uninstall -y com.valvesoftware.Steam
    else
        case "$DISTRO_FAMILY" in
            debian) sudo apt remove -y steam steam-installer steam-launcher ;;
            *)      pkg_remove steam 2>/dev/null || true ;;
        esac
    fi
}
update_steam() {
    echo "Updating Steam..."
    if has_flatpak && flatpak list 2>/dev/null | grep -qi "com.valvesoftware.Steam"; then
        flatpak update -y com.valvesoftware.Steam
    else
        case "$DISTRO_FAMILY" in
            debian)
                sudo apt update
                sudo apt upgrade -y steam
                ;;
            *)
                pkg_upgrade steam
                ;;
        esac
    fi
}
get_version_steam() {
    if has_flatpak && flatpak list 2>/dev/null | grep -qi "com.valvesoftware.Steam"; then
        flatpak list 2>/dev/null | grep -i "com.valvesoftware.Steam" | awk -F'\t' '{print $3}'
    elif pkg_check_installed steam-installer; then
        pkg_get_version steam-installer
    elif pkg_check_installed steam-launcher; then
        pkg_get_version steam-launcher
    elif pkg_check_installed steam; then
        pkg_get_version steam
    else
        echo ""
    fi
}

# --- Timeshift ---

check_timeshift() {
    command -v timeshift &>/dev/null
}

install_timeshift() {
    echo "Installing Timeshift..."
    case "$DISTRO_FAMILY" in
        debian)
            sudo apt install timeshift -y
            ;;
        fedora|rhel)
            sudo "$PKG_MGR" install -y timeshift
            ;;
        arch)
            sudo pacman -S --noconfirm timeshift
            ;;
        suse)
            sudo zypper install -y timeshift
            ;;
        *)
            warn "Timeshift installation not implemented for ${DISTRO_NAME}."
            return 1
            ;;
    esac
    echo "Timeshift installed successfully."
}

uninstall_timeshift() {
    echo "Uninstalling Timeshift..."
    case "$DISTRO_FAMILY" in
        debian)
            sudo apt remove -y timeshift
            sudo apt autoremove -y
            ;;
        fedora|rhel)
            sudo "$PKG_MGR" remove -y timeshift
            ;;
        arch)
            sudo pacman -Rs --noconfirm timeshift
            ;;
        suse)
            sudo zypper remove -y timeshift
            ;;
    esac
}

update_timeshift() {
    echo "Updating Timeshift..."
    case "$DISTRO_FAMILY" in
        debian)
            sudo apt update && sudo apt upgrade -y timeshift
            ;;
        *)
            pkg_upgrade timeshift
            ;;
    esac
}
get_version_timeshift() {
    timeshift --version 2>/dev/null | grep -oP 'Timeshift \K[0-9]+\.[0-9]+(\.[0-9]+)?' || echo ""
}

# --- Visual Studio Code ---

check_vscode() {
    command -v code &>/dev/null || pkg_check_installed code
}
install_vscode() {
    echo "Installing Visual Studio Code..."
    ensure_tools
    case "$DISTRO_FAMILY" in
        debian)
            wget -qO- https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor > /tmp/packages.microsoft.gpg
            sudo install -D -o root -g root -m 644 /tmp/packages.microsoft.gpg /etc/apt/keyrings/packages.microsoft.gpg
            echo "deb [arch=amd64,arm64,armhf signed-by=/etc/apt/keyrings/packages.microsoft.gpg] https://packages.microsoft.com/repos/code stable main" | \
                sudo tee /etc/apt/sources.list.d/vscode.list > /dev/null
            rm -f /tmp/packages.microsoft.gpg
            sudo apt update
            sudo apt install -y code
            ;;
        fedora|rhel)
            sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc
            printf "[code]\nname=Visual Studio Code\nbaseurl=https://packages.microsoft.com/yumrepos/vscode\nenabled=1\ngpgcheck=1\ngpgkey=https://packages.microsoft.com/keys/microsoft.asc\n" | \
                sudo tee /etc/yum.repos.d/vscode.repo > /dev/null
            sudo "$PKG_MGR" install -y code
            ;;
        arch)
            if has_aur_helper; then
                aur_install visual-studio-code-bin
            else
                aur_build visual-studio-code-bin
            fi
            ;;
        suse)
            sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc
            printf "[code]\nname=Visual Studio Code\nbaseurl=https://packages.microsoft.com/yumrepos/vscode\nenabled=1\ntype=rpm-md\ngpgcheck=1\ngpgkey=https://packages.microsoft.com/keys/microsoft.asc\n" | \
                sudo tee /etc/zypp/repos.d/vscode.repo > /dev/null
            sudo zypper refresh
            sudo zypper install -y code
            ;;
    esac
}
uninstall_vscode() {
    echo "Uninstalling Visual Studio Code..."
    case "$DISTRO_FAMILY" in
        debian)
            sudo apt remove -y code
            sudo rm -f /etc/apt/sources.list.d/vscode.list
            sudo rm -f /etc/apt/keyrings/packages.microsoft.gpg
            ;;
        fedora|rhel)
            sudo "$PKG_MGR" remove -y code
            sudo rm -f /etc/yum.repos.d/vscode.repo
            ;;
        arch)
            aur_remove visual-studio-code-bin 2>/dev/null || pkg_remove code 2>/dev/null || true
            ;;
        suse)
            sudo zypper remove -y code
            sudo rm -f /etc/zypp/repos.d/vscode.repo
            ;;
    esac
}
update_vscode() {
    echo "Updating Visual Studio Code..."
    case "$DISTRO_FAMILY" in
        debian)
            sudo apt update
            sudo apt upgrade -y code
            ;;
        arch)
            if has_aur_helper; then
                aur_upgrade visual-studio-code-bin
            else
                aur_build visual-studio-code-bin
            fi
            ;;
        *)
            pkg_upgrade code
            ;;
    esac
}
get_version_vscode() {
    code --version 2>/dev/null | head -1 || echo ""
}

# --- Syncthing ---

check_syncthing() {
    command -v syncthing &>/dev/null || pkg_check_installed syncthing
}

install_syncthing() {
    echo "Installing Syncthing..."
    ensure_tools
    case "$DISTRO_FAMILY" in
        debian)
            # Add the Syncthing PGP key
            sudo mkdir -p /etc/apt/keyrings
            sudo curl -L -o /etc/apt/keyrings/syncthing-archive-keyring.gpg https://syncthing.net/release-key.gpg

            # Add the Syncthing repository
            echo "deb [signed-by=/etc/apt/keyrings/syncthing-archive-keyring.gpg] https://apt.syncthing.net/ syncthing stable" | \
                sudo tee /etc/apt/sources.list.d/syncthing.list > /dev/null

            # Update and install
            sudo apt update
            sudo apt install -y syncthing
            ;;
        fedora|rhel)
            # Install from official Fedora repos (Syncthing is included by default)
            sudo "$PKG_MGR" install -y syncthing
            ;;
        arch)
            # Syncthing is available in the community repository
            sudo pacman -S --noconfirm syncthing
            ;;
        suse)
            # Install from official repository
            sudo zypper install -y syncthing
            ;;
    esac

    # Enable and start the user service (all distros)
    systemctl --user enable syncthing.service
    systemctl --user start syncthing.service

    echo ""
    echo "Syncthing installed successfully!"
    echo "Service has been enabled and started."
    echo "Access the web GUI at: http://127.0.0.1:8384"
}

uninstall_syncthing() {
    echo "Uninstalling Syncthing..."
    
    # Stop and disable the service if running
    systemctl --user stop syncthing.service 2>/dev/null || true
    systemctl --user disable syncthing.service 2>/dev/null || true
    
    case "$DISTRO_FAMILY" in
        debian)
            sudo apt remove -y syncthing
            sudo rm -f /etc/apt/sources.list.d/syncthing.list
            sudo rm -f /etc/apt/keyrings/syncthing-archive-keyring.gpg
            ;;
        fedora|rhel)
            sudo "$PKG_MGR" remove -y syncthing
            sudo rm -f /etc/yum.repos.d/syncthing.repo
            ;;
        arch)
            sudo pacman -Rs --noconfirm syncthing
            ;;
        suse)
            sudo zypper remove -y syncthing
            ;;
    esac
    
    echo "Syncthing has been uninstalled."
    echo "Note: Your Syncthing configuration and data (~/.config/syncthing) have been preserved."
    echo "To remove them manually, run: rm -rf ~/.config/syncthing"
}

update_syncthing() {
    echo "Updating Syncthing..."
    case "$DISTRO_FAMILY" in
        debian)
            sudo apt update
            sudo apt upgrade -y syncthing
            ;;
        fedora|rhel)
            sudo "$PKG_MGR" upgrade -y syncthing
            ;;
        arch)
            sudo pacman -S --noconfirm syncthing
            ;;
        suse)
            sudo zypper update -y syncthing
            ;;
    esac
}
get_version_syncthing() {
    syncthing --version 2>/dev/null | awk '{print $2}' | sed 's/^v//' || echo ""
}

# --- OpenSSH Server ---
check_openssh_server() {
    pkg_check_installed openssh-server || \
        systemctl is-active --quiet ssh 2>/dev/null || \
        systemctl is-active --quiet sshd 2>/dev/null
}

install_openssh_server() {
    echo "Installing OpenSSH Server..."
    case "$DISTRO_FAMILY" in
        debian)
            sudo apt install openssh-server -y
            sudo systemctl enable ssh
            sudo systemctl start ssh
            ;;
        fedora|rhel)
            sudo "$PKG_MGR" install -y openssh-server
            sudo systemctl enable sshd
            sudo systemctl start sshd
            ;;
        arch)
            sudo pacman -S --noconfirm openssh
            sudo systemctl enable sshd
            sudo systemctl start sshd
            ;;
        suse)
            sudo zypper install -y openssh
            sudo systemctl enable sshd
            sudo systemctl start sshd
            ;;
    esac
    echo "OpenSSH Server installed and started."
}

uninstall_openssh_server() {
    echo "Uninstalling OpenSSH Server..."
    sudo systemctl stop ssh 2>/dev/null || sudo systemctl stop sshd 2>/dev/null || true
    sudo systemctl disable ssh 2>/dev/null || sudo systemctl disable sshd 2>/dev/null || true
    case "$DISTRO_FAMILY" in
        debian)
            sudo apt remove -y openssh-server
            sudo apt autoremove -y
            ;;
        fedora|rhel)
            sudo "$PKG_MGR" remove -y openssh-server
            ;;
        arch)
            sudo pacman -Rs --noconfirm openssh
            ;;
        suse)
            sudo zypper remove -y openssh
            ;;
    esac
    echo "OpenSSH Server has been uninstalled."
}

update_openssh_server() {
    echo "Updating OpenSSH Server..."
    case "$DISTRO_FAMILY" in
        debian)
            sudo apt update
            sudo apt upgrade -y openssh-server
            ;;
        fedora|rhel)
            sudo "$PKG_MGR" upgrade -y openssh-server
            ;;
        arch)
            sudo pacman -S --noconfirm openssh
            ;;
        suse)
            sudo zypper update -y openssh
            ;;
    esac
}
get_version_openssh_server() {
    ssh -V 2>&1 | grep -oP 'OpenSSH_\K[^\s,]+' || echo ""
}

# --- Docker (utility version) ---
check_docker() {
    command -v docker &>/dev/null && docker --version &>/dev/null
}
uninstall_docker() {
    echo "Uninstalling Docker..."
    sudo systemctl stop docker 2>/dev/null || true
    sudo systemctl disable docker 2>/dev/null || true
    case "$DISTRO_FAMILY" in
        debian)
            sudo apt remove -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
            sudo rm -f /etc/apt/sources.list.d/docker.list
            sudo rm -f /etc/apt/keyrings/docker.gpg
            ;;
        fedora|rhel)
            sudo "$PKG_MGR" remove -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
            ;;
        arch)
            sudo pacman -Rs --noconfirm docker docker-compose docker-buildx 2>/dev/null || true
            ;;
        suse)
            sudo zypper remove -y docker docker-compose docker-buildx
            ;;
    esac
}
update_docker() {
    echo "Updating Docker..."
    case "$DISTRO_FAMILY" in
        debian)
            sudo apt update
            sudo apt upgrade -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
            ;;
        fedora|rhel)
            sudo "$PKG_MGR" upgrade -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
            ;;
        arch)
            sudo pacman -S --noconfirm docker docker-compose docker-buildx
            ;;
        suse)
            sudo zypper update -y docker docker-compose docker-buildx
            ;;
    esac
}
get_version_docker() {
    docker --version 2>/dev/null | grep -oP 'Docker version \K[0-9]+\.[0-9]+\.[0-9]+' || echo ""
}

# ============================================================================
# INTERACTIVE SELECTION MENU
# ============================================================================

# Terminal control sequences
ESC=$'\e'
CSI="${ESC}["

# Colors
RED="${CSI}31m"
GREEN="${CSI}32m"
YELLOW="${CSI}33m"
BLUE="${CSI}34m"
CYAN="${CSI}36m"
MAGENTA="${CSI}35m"
BOLD="${CSI}1m"
DIM="${CSI}2m"
RESET="${CSI}0m"

# Respect the NO_COLOR standard (https://no-color.org/) and non-interactive terminals.
if [[ ! -t 1 || -n "${NO_COLOR:-}" ]]; then
    RED="" GREEN="" YELLOW="" BLUE="" CYAN="" MAGENTA="" BOLD="" DIM="" RESET=""
fi

# Track selections (0 = not selected, 1 = selected)
declare -a SELECTED
# Track installed state (0 = not installed, 1 = installed)
declare -a INSTALLED
# Track items queued for update (0 = no, 1 = yes; only valid for installed items)
declare -a UPDATE_SELECTED
# Track installed versions (empty string if unknown)
declare -a INSTALLED_VERSIONS
# Rows per column for utilities section
ROWS_PER_COLUMN=6

# Check which utilities are already installed
check_installed_utilities() {
    echo "Checking installed utilities..."
    for ((i=0; i<${#UTILITIES[@]}; i++)); do
        local util="${UTILITIES[$i]}"
        local check_func="${CHECK_FUNCS[$util]}"
        
        if [[ -n "$check_func" ]] && declare -f "$check_func" > /dev/null; then
            if $check_func 2>/dev/null; then
                INSTALLED[$i]=1
                # Retrieve version if a version function is registered
                local ver_func="${VERSION_FUNCS[$util]:-}"
                if [[ -n "$ver_func" ]] && declare -f "$ver_func" > /dev/null; then
                    INSTALLED_VERSIONS[$i]=$($ver_func 2>/dev/null)
                else
                    INSTALLED_VERSIONS[$i]=""
                fi
            else
                INSTALLED[$i]=0
                INSTALLED_VERSIONS[$i]=""
            fi
        else
            INSTALLED[$i]=0
            INSTALLED_VERSIONS[$i]=""
        fi

        # Keep all options unselected by default; selection determines action
        SELECTED[$i]=0
    done
}

# Initialize arrays
for ((i=0; i<${#UTILITIES[@]}; i++)); do
    SELECTED[$i]=0
    INSTALLED[$i]=0
    UPDATE_SELECTED[$i]=0
    INSTALLED_VERSIONS[$i]=""
done

# Current cursor position
CURSOR=0

# Hide cursor
hide_cursor() { printf "${CSI}?25l"; }
# Show cursor
show_cursor() { printf "${CSI}?25h"; }
# Move cursor up N lines
cursor_up() { printf "${CSI}%dA" "$1"; }
# Move cursor to beginning of line
cursor_start() { printf "\r"; }
# Clear line
clear_line() { printf "${CSI}2K"; }

# Draw the menu
draw_menu() {
    local total=${#UTILITIES[@]}
    local system_tasks=$SYSTEM_TASK_COUNT
    local system_rows_per_column=3  # 3 rows per column for System Tasks
    local rows_per_column=$ROWS_PER_COLUMN  # rows per column for Utilities
    local utilities_start=$system_tasks
    local utilities_count=$((total - system_tasks))
    local num_columns=$(( (utilities_count + rows_per_column - 1) / rows_per_column ))
    local system_num_columns=$(( (system_tasks + system_rows_per_column - 1) / system_rows_per_column ))

    local sys_col_width=40
    local util_col_width=40
    
    local dry_run_label=""
    [[ "$DRY_RUN" == "true" ]] && dry_run_label="  ${BOLD}${YELLOW}[DRY RUN]${RESET}"

    echo ""
    echo "${BOLD}${CYAN}╔══════════════════════════════════════════════════════════════╗${RESET}"
    echo "${BOLD}${CYAN}║   Linux System Setup & Utilities - Select Programs/Tasks     ║${RESET}${dry_run_label}"
    echo "${BOLD}${CYAN}╚══════════════════════════════════════════════════════════════╝${RESET}"
    echo ""

    # Display commit version info (values pre-fetched once in run_selection_menu)
    echo "       Script commit: ${BOLD}${CACHED_LOCAL_COMMIT}${RESET}  |  Latest commit: ${BOLD}${CACHED_REMOTE_COMMIT}${RESET}"
    if [[ "$CACHED_LOCAL_COMMIT" != "unknown" && "$CACHED_REMOTE_COMMIT" != "unknown" && "$CACHED_LOCAL_COMMIT" != "$CACHED_REMOTE_COMMIT" ]]; then
        echo "  ${BOLD}${YELLOW}Script out of date, please update.${RESET}"
    fi
    echo ""

    # Display System Tasks section
    echo "${BOLD}${CYAN}System Tasks:${RESET}"
    for ((row=0; row<system_rows_per_column; row++)); do
        local line=""
        for ((col=0; col<system_num_columns; col++)); do
            local task_idx=$((col * system_rows_per_column + row))
            local i=$task_idx
            
            # Skip if index is beyond system tasks
            if [[ $i -ge $system_tasks ]]; then
                continue
            fi
            
            local prefix="  "
            local checkbox="[ ]"
            local name="${UTILITIES[$i]}"
            local status_tag=""
            
            # Highlight current item
            if [[ $i -eq $CURSOR ]]; then
                prefix="${BOLD}${BLUE}▸ ${RESET}"
            fi
            
            # Show selection / update-queued state
            if [[ ${UPDATE_SELECTED[$i]} -eq 1 ]]; then
                checkbox="${YELLOW}[U]${RESET}"
            elif [[ ${SELECTED[$i]} -eq 1 ]]; then
                checkbox="${GREEN}[✓]${RESET}"
            fi
            
            # Show installed status (with version if available)
            if [[ ${INSTALLED[$i]} -eq 1 ]]; then
                local ver="${INSTALLED_VERSIONS[$i]:-}"
                if [[ -n "$ver" ]]; then
                    status_tag=" ${MAGENTA}(v${ver})${RESET}"
                else
                    status_tag=" ${MAGENTA}(installed)${RESET}"
                fi
            fi

            local item=""
            if [[ $i -eq $CURSOR ]]; then
                item="${prefix}${checkbox} ${BOLD}${name}${RESET}${status_tag}"
            else
                item="${prefix}${checkbox} ${name}${status_tag}"
            fi

            # Add padding for columns using visible width (no ANSI codes)
            if [[ $col -lt $((system_num_columns - 1)) ]]; then
                local plain_status=""
                if [[ ${INSTALLED[$i]} -eq 1 ]]; then
                    local pver="${INSTALLED_VERSIONS[$i]:-}"
                    if [[ -n "$pver" ]]; then
                        plain_status=" (v${pver})"
                    else
                        plain_status=" (installed)"
                    fi
                fi
                # Visible chars: prefix (2), checkbox (3), space (1), name, status text
                local visible_len=$((2 + 3 + 1 + ${#name} + ${#plain_status}))
                local padding=$((util_col_width - visible_len))
                [[ $padding -lt 2 ]] && padding=2
                item="${item}$(printf '%*s' $padding '')"
            fi

            line="${line}${item}"
        done
        echo "$line"
    done
    
    echo ""
    echo "${DIM}----------------------------------------------------------------${RESET}"
    echo ""
    echo "${BOLD}${CYAN}Utilities:${RESET}"
    
    # Build items for utilities in columns
    for ((row=0; row<rows_per_column; row++)); do
        local line=""
        for ((col=0; col<num_columns; col++)); do
            local util_idx=$((col * rows_per_column + row))
            local i=$((utilities_start + util_idx))
            
            # Skip if index is beyond total items
            if [[ $i -ge $total ]]; then
                continue
            fi
            
            local prefix="  "
            local checkbox="[ ]"
            local name="${UTILITIES[$i]}"
            local status_tag=""
            
            # Highlight current item
            if [[ $i -eq $CURSOR ]]; then
                prefix="${BOLD}${BLUE}▸ ${RESET}"
            fi
            
            # Show selection / update-queued state
            if [[ ${UPDATE_SELECTED[$i]} -eq 1 ]]; then
                checkbox="${YELLOW}[U]${RESET}"
            elif [[ ${SELECTED[$i]} -eq 1 ]]; then
                checkbox="${GREEN}[✓]${RESET}"
            fi
            
            # Show installed status (with version if available)
            if [[ ${INSTALLED[$i]} -eq 1 ]]; then
                local ver="${INSTALLED_VERSIONS[$i]:-}"
                if [[ -n "$ver" ]]; then
                    status_tag=" ${MAGENTA}(v${ver})${RESET}"
                else
                    status_tag=" ${MAGENTA}(installed)${RESET}"
                fi
            fi

            local item=""
            if [[ $i -eq $CURSOR ]]; then
                item="${prefix}${checkbox} ${BOLD}${name}${RESET}${status_tag}"
            else
                item="${prefix}${checkbox} ${name}${status_tag}"
            fi

            # Add padding for columns using visible width (no ANSI codes)
            if [[ $col -lt $((num_columns - 1)) ]]; then
                local plain_status=""
                if [[ ${INSTALLED[$i]} -eq 1 ]]; then
                    local pver="${INSTALLED_VERSIONS[$i]:-}"
                    if [[ -n "$pver" ]]; then
                        plain_status=" (v${pver})"
                    else
                        plain_status=" (installed)"
                    fi
                fi
                # Visible chars: prefix (2), checkbox (3), space (1), name, status text
                local visible_len=$((2 + 3 + 1 + ${#name} + ${#plain_status}))
                local padding=$((util_col_width - visible_len))
                [[ $padding -lt 2 ]] && padding=2
                item="${item}$(printf '%*s' $padding '')"
            fi

            line="${line}${item}"
        done
        echo "$line"
    done
    
    echo ""
    echo "----------------------------------------------------------------"
    
    # Count selected items and categorize actions
    local install_count=0
    local uninstall_count=0
    local update_count=0
    for ((i=0; i<total; i++)); do
        if [[ ${UPDATE_SELECTED[$i]} -eq 1 ]]; then
            ((update_count++))
        elif [[ ${SELECTED[$i]} -eq 1 ]]; then
            if [[ ${INSTALLED[$i]} -eq 1 ]]; then
                ((uninstall_count++))
            else
                ((install_count++))
            fi
        fi
    done
    
    echo "${CYAN}Actions: ${GREEN}Install: ${install_count}${RESET} | ${RED}Uninstall: ${uninstall_count}${RESET} | ${YELLOW}Update: ${update_count}${RESET}"
    echo ""
    echo "${YELLOW}↑/↓/←/→ navigate  SPACE select  U update installed  A select-all  D deselect-all  ENTER confirm  Q quit${RESET}"
    echo ""
    echo "${DIM}Legend: ${GREEN}[✓]${RESET}${DIM} select  ${YELLOW}[U]${RESET}${DIM} update  ${RESET}${DIM}[ ]${RESET}${DIM} none  ${MAGENTA}(installed)${RESET}${DIM} = on system${RESET}"
    echo "${DIM}[✓] on installed = uninstall; [✓] on missing = install; [U] on installed = update.${RESET}"
    echo ""
}

# Redraw the menu (clear and redraw for reliability)
redraw_menu() {
    clear
    draw_menu
}

# Dynamically build navigational columns used by keyboard navigation.
# Each visual display-column (spanning both System Tasks and Utilities) becomes
# one navigational column.  Supports any number of columns.
# Results are stored in NAV_FLAT (packed indices), NAV_COL_START (offsets),
# NAV_COL_SIZE (lengths), and NAV_NUM_COLS.
build_nav_columns() {
    NAV_FLAT=()
    NAV_COL_START=()
    NAV_COL_SIZE=()
    NAV_COL_SYS_SIZE=()   # system-task count per column (for section-aware LEFT/RIGHT)
    NAV_NUM_COLS=0
    local total=${#UTILITIES[@]}
    local sys_tasks=$SYSTEM_TASK_COUNT
    local sys_rows=3              # rows per column in System Tasks section
    local util_rows=$ROWS_PER_COLUMN
    local utilities_count=$(( total - sys_tasks ))

    local sys_cols=$(( (sys_tasks + sys_rows - 1) / sys_rows ))
    local util_cols=$(( (utilities_count + util_rows - 1) / util_rows ))
    local max_cols=$(( sys_cols > util_cols ? sys_cols : util_cols ))
    NAV_NUM_COLS=$max_cols

    for (( c=0; c<max_cols; c++ )); do
        NAV_COL_START+=( ${#NAV_FLAT[@]} )
        local col_size=0
        local col_sys_size=0

        # Add system task items for this column
        for (( r=0; r<sys_rows; r++ )); do
            local idx=$(( c * sys_rows + r ))
            if (( idx < sys_tasks )); then
                NAV_FLAT+=( "$idx" )
                (( col_size++ ))
                (( col_sys_size++ ))
            fi
        done

        # Add utility items for this column
        for (( r=0; r<util_rows; r++ )); do
            local u_idx=$(( c * util_rows + r ))
            if (( u_idx < utilities_count )); then
                NAV_FLAT+=( "$(( sys_tasks + u_idx ))" )
                (( col_size++ ))
            fi
        done

        NAV_COL_SIZE+=( "$col_size" )
        NAV_COL_SYS_SIZE+=( "$col_sys_size" )
    done
}

# Read a single keypress
read_key() {
    local key
    IFS= read -rsn1 key
    
    # Check for escape sequence (arrow keys)
    if [[ $key == $ESC ]]; then
        read -rsn2 -t 0.1 key
        case "$key" in
            '[A') echo "UP" ;;
            '[B') echo "DOWN" ;;
            '[C') echo "RIGHT" ;;
            '[D') echo "LEFT" ;;
            *) echo "OTHER" ;;
        esac
    elif [[ $key == "" ]]; then
        echo "ENTER"
    elif [[ $key == " " ]]; then
        echo "SPACE"
    elif [[ $key == "q" ]] || [[ $key == "Q" ]]; then
        echo "QUIT"
    elif [[ $key == "a" ]] || [[ $key == "A" ]]; then
        echo "SELECT_ALL"
    elif [[ $key == "d" ]] || [[ $key == "D" ]]; then
        echo "DESELECT_ALL"
    elif [[ $key == "u" ]] || [[ $key == "U" ]]; then
        echo "UPDATE"
    else
        echo "OTHER"
    fi
}

# Main selection loop
run_selection_menu() {
    local total=${#UTILITIES[@]}
    
    # Check which utilities are already installed
    check_installed_utilities

    # Fetch commit info once to avoid network call on every redraw
    CACHED_LOCAL_COMMIT=$(git -C "$SCRIPT_DIR" rev-parse --short HEAD 2>/dev/null || echo "unknown")
    local _remote_full
    _remote_full=$(git -C "$SCRIPT_DIR" ls-remote origin HEAD 2>/dev/null | awk '{print $1}')
    if [[ -n "$_remote_full" ]]; then
        CACHED_REMOTE_COMMIT="${_remote_full:0:7}"
    else
        CACHED_REMOTE_COMMIT="unknown"
    fi
    
    # Build navigation column layout once (dynamic — adapts to UTILITIES count)
    build_nav_columns

    # Setup terminal
    hide_cursor
    stty -echo
    
    # Cleanup on exit
    trap 'show_cursor; stty echo; echo ""; cleanup_on_exit' EXIT

    # Redraw on terminal resize
    trap 'redraw_menu' WINCH

    # Initial draw
    clear
    draw_menu
    
    while true; do
        local key=$(read_key)

        # Multi-column navigation model.
        # The menu is displayed as N visual columns that span both the
        # System Tasks section and the Utilities section.  UP/DOWN stays
        # within the same column (wrapping at the ends); LEFT/RIGHT jumps
        # one column in that direction to the same row (clamped if shorter).
        # Columns are computed dynamically by build_nav_columns() (called once above).

        # Determine which column the cursor is in and its position within it.
        local _nav_col=-1
        local _nav_pos=-1
        local _c _r
        for (( _c=0; _c<NAV_NUM_COLS; _c++ )); do
            local _start=${NAV_COL_START[$_c]}
            local _size=${NAV_COL_SIZE[$_c]}
            for (( _r=0; _r<_size; _r++ )); do
                if [[ ${NAV_FLAT[$(( _start + _r ))]} -eq $CURSOR ]]; then
                    _nav_col=$_c
                    _nav_pos=$_r
                    break 2
                fi
            done
        done
        # Fallback: keep cursor as-is if somehow not found
        [[ $_nav_col -eq -1 ]] && { _nav_col=0; _nav_pos=0; }

        local _cur_start=${NAV_COL_START[$_nav_col]}
        local _cur_size=${NAV_COL_SIZE[$_nav_col]}

        case "$key" in
            UP)
                local _new_pos=$(( (_nav_pos - 1 + _cur_size) % _cur_size ))
                CURSOR=${NAV_FLAT[$(( _cur_start + _new_pos ))]}
                redraw_menu
                ;;
            DOWN)
                local _new_pos=$(( (_nav_pos + 1) % _cur_size ))
                CURSOR=${NAV_FLAT[$(( _cur_start + _new_pos ))]}
                redraw_menu
                ;;
            LEFT)
                if (( _nav_col > 0 )); then
                    local _target_col=$(( _nav_col - 1 ))
                    local _target_start=${NAV_COL_START[$_target_col]}
                    local _target_size=${NAV_COL_SIZE[$_target_col]}
                    local _cur_sys=${NAV_COL_SYS_SIZE[$_nav_col]}
                    local _target_sys=${NAV_COL_SYS_SIZE[$_target_col]}
                    local _target_pos
                    if (( _nav_pos < _cur_sys )); then
                        # System tasks section — map to same system-task row
                        _target_pos=$(( _nav_pos < _target_sys ? _nav_pos : _target_sys - 1 ))
                    else
                        # Utilities section — map to same utility row
                        local _util_row=$(( _nav_pos - _cur_sys ))
                        local _target_util_size=$(( _target_size - _target_sys ))
                        if (( _target_util_size > 0 )); then
                            _target_pos=$(( _target_sys + (_util_row < _target_util_size ? _util_row : _target_util_size - 1) ))
                        else
                            _target_pos=$(( _target_size - 1 ))
                        fi
                    fi
                    CURSOR=${NAV_FLAT[$(( _target_start + _target_pos ))]}
                fi
                redraw_menu
                ;;
            RIGHT)
                if (( _nav_col < NAV_NUM_COLS - 1 )); then
                    local _target_col=$(( _nav_col + 1 ))
                    local _target_start=${NAV_COL_START[$_target_col]}
                    local _target_size=${NAV_COL_SIZE[$_target_col]}
                    local _cur_sys=${NAV_COL_SYS_SIZE[$_nav_col]}
                    local _target_sys=${NAV_COL_SYS_SIZE[$_target_col]}
                    local _target_pos
                    if (( _nav_pos < _cur_sys )); then
                        # System tasks section — map to same system-task row
                        _target_pos=$(( _nav_pos < _target_sys ? _nav_pos : _target_sys - 1 ))
                    else
                        # Utilities section — map to same utility row
                        local _util_row=$(( _nav_pos - _cur_sys ))
                        local _target_util_size=$(( _target_size - _target_sys ))
                        if (( _target_util_size > 0 )); then
                            _target_pos=$(( _target_sys + (_util_row < _target_util_size ? _util_row : _target_util_size - 1) ))
                        else
                            _target_pos=$(( _target_size - 1 ))
                        fi
                    fi
                    CURSOR=${NAV_FLAT[$(( _target_start + _target_pos ))]}
                fi
                redraw_menu
                ;;
            SPACE)
                # Toggle selection; clear any pending update for this item
                UPDATE_SELECTED[$CURSOR]=0
                if [[ ${SELECTED[$CURSOR]} -eq 0 ]]; then
                    SELECTED[$CURSOR]=1
                else
                    SELECTED[$CURSOR]=0
                fi
                redraw_menu
                ;;
            UPDATE)
                # Toggle update mode for installed items only
                if [[ ${INSTALLED[$CURSOR]} -eq 1 ]]; then
                    SELECTED[$CURSOR]=0   # clear install/uninstall selection
                    if [[ ${UPDATE_SELECTED[$CURSOR]} -eq 0 ]]; then
                        UPDATE_SELECTED[$CURSOR]=1
                    else
                        UPDATE_SELECTED[$CURSOR]=0
                    fi
                    redraw_menu
                fi
                ;;
            SELECT_ALL)
                for ((i=0; i<${#UTILITIES[@]}; i++)); do
                    SELECTED[$i]=1
                    UPDATE_SELECTED[$i]=0
                done
                redraw_menu
                ;;
            DESELECT_ALL)
                for ((i=0; i<${#UTILITIES[@]}; i++)); do
                    SELECTED[$i]=0
                    UPDATE_SELECTED[$i]=0
                done
                redraw_menu
                ;;
            ENTER)
                # Continue to installation
                show_cursor
                stty echo
                trap cleanup_on_exit EXIT
                return 0
                ;;
            QUIT)
                show_cursor
                stty echo
                trap cleanup_on_exit EXIT
                echo ""
                echo "${YELLOW}Operation cancelled.${RESET}"
                exit 0
                ;;
        esac
    done
}

# ============================================================================
# INSTALLATION PROCESS
# ============================================================================

process_selected() {
    local total=${#UTILITIES[@]}
    local system_tasks=$SYSTEM_TASK_COUNT
    declare -a to_install
    declare -a to_uninstall
    declare -a to_update
    local needs_reboot=false
    
    # Categorize utilities based on selection and installed state
    for ((i=0; i<total; i++)); do
        local util="${UTILITIES[$i]}"
        if [[ ${UPDATE_SELECTED[$i]} -eq 1 ]]; then
            to_update+=("$util")
        elif [[ ${SELECTED[$i]} -eq 1 ]]; then
            if [[ ${INSTALLED[$i]} -eq 1 ]]; then
                to_uninstall+=("$util")
            else
                to_install+=("$util")
            fi
            # Reboot required for System Tasks and Docker
            if [[ $i -lt $system_tasks ]] || [[ "$util" == "Docker" ]]; then
                needs_reboot=true
            fi
        fi
    done
    
    # Check if there's anything to do
    if [[ ${#to_install[@]} -eq 0 ]] && [[ ${#to_uninstall[@]} -eq 0 ]] && [[ ${#to_update[@]} -eq 0 ]]; then
        echo ""
        echo "${YELLOW}No changes to make. Exiting.${RESET}"
        exit 0
    fi
    
    echo ""
    echo "${BOLD}${CYAN}════════════════════════════════════════════════════════════════${RESET}"
    echo "${BOLD}${CYAN}                    Summary of Actions                         ${RESET}"
    echo "${BOLD}${CYAN}════════════════════════════════════════════════════════════════${RESET}"
    echo ""
    
    if [[ ${#to_install[@]} -gt 0 ]]; then
        echo "${GREEN}To Install/Run (${#to_install[@]}):${RESET}"
        for util in "${to_install[@]}"; do
            echo "  ${GREEN}+${RESET} $util"
        done
        echo ""
    fi
    
    if [[ ${#to_uninstall[@]} -gt 0 ]]; then
        echo "${RED}To Uninstall (${#to_uninstall[@]}):${RESET}"
        for util in "${to_uninstall[@]}"; do
            echo "  ${RED}-${RESET} $util"
        done
        echo ""
    fi

    if [[ ${#to_update[@]} -gt 0 ]]; then
        echo "${YELLOW}To Update (${#to_update[@]}):${RESET}"
        for util in "${to_update[@]}"; do
            echo "  ${YELLOW}↑${RESET} $util"
        done
        echo ""
    fi
    
    read -p "Press ENTER to continue or Ctrl+C to cancel..."
    echo ""

    if [[ "$DRY_RUN" == "true" ]]; then
        echo "${YELLOW}[DRY RUN] No changes made. Exiting.${RESET}"
        exit 0
    fi

    # Check internet before any downloads
    check_internet || true

    # Update package lists first
    echo "${CYAN}Updating package lists...${RESET}"
    pkg_refresh
    echo ""
    
    # Track results
    local success_count=0
    local fail_count=0
    declare -a failed_utils
    
    # Process uninstallations first
    for util in "${to_uninstall[@]}"; do
        echo ""
        echo "${BOLD}${RED}────────────────────────────────────────────────────────────────${RESET}"
        echo "${DIM}[$(date '+%H:%M:%S')]${RESET} ${BOLD}${RED}Uninstalling: $util${RESET}"
        echo "${BOLD}${RED}────────────────────────────────────────────────────────────────${RESET}"
        echo ""

        log_info "Starting uninstallation: $util"
        local _op_start=$SECONDS

        local func="${UNINSTALL_FUNCS[$util]}"
        if [[ -n "$func" ]] && declare -f "$func" > /dev/null; then
            if $func; then
                echo ""
                echo "${GREEN}✓ Successfully uninstalled: $util${RESET} ${DIM}($(( SECONDS - _op_start ))s)${RESET}"
                log_success "Uninstalled: $util"
                ((success_count++))
            else
                echo ""
                echo "${RED}✗ Failed to uninstall: $util${RESET} ${DIM}($(( SECONDS - _op_start ))s)${RESET}"
                log_error "Failed to uninstall: $util"
                ((fail_count++))
                failed_utils+=("$util (uninstall)")
            fi
        else
            echo "${RED}✗ No uninstall function found for: $util${RESET}"
            log_error "No uninstall function found for: $util"
            ((fail_count++))
            failed_utils+=("$util (uninstall)")
        fi
    done

    # Process installations
    for util in "${to_install[@]}"; do
        echo ""
        echo "${BOLD}${GREEN}────────────────────────────────────────────────────────────────${RESET}"
        echo "${DIM}[$(date '+%H:%M:%S')]${RESET} ${BOLD}${GREEN}Installing/Running: $util${RESET}"
        echo "${BOLD}${GREEN}────────────────────────────────────────────────────────────────${RESET}"
        echo ""

        log_info "Starting installation: $util"
        local _op_start=$SECONDS

        local func="${INSTALL_FUNCS[$util]}"
        if [[ -n "$func" ]] && declare -f "$func" > /dev/null; then
            if $func; then
                echo ""
                echo "${GREEN}✓ Successfully completed: $util${RESET} ${DIM}($(( SECONDS - _op_start ))s)${RESET}"
                log_success "Installed: $util"
                ((success_count++))
            else
                echo ""
                echo "${RED}✗ Failed: $util${RESET} ${DIM}($(( SECONDS - _op_start ))s)${RESET}"
                log_error "Failed to install: $util"
                ((fail_count++))
                failed_utils+=("$util (install)")
            fi
        else
            echo "${RED}✗ No installation function found for: $util${RESET}"
            log_error "No installation function found for: $util"
            ((fail_count++))
            failed_utils+=("$util (install)")
        fi
    done

    # Process updates
    for util in "${to_update[@]}"; do
        echo ""
        echo "${BOLD}${YELLOW}────────────────────────────────────────────────────────────────${RESET}"
        echo "${DIM}[$(date '+%H:%M:%S')]${RESET} ${BOLD}${YELLOW}Updating: $util${RESET}"
        echo "${BOLD}${YELLOW}────────────────────────────────────────────────────────────────${RESET}"
        echo ""

        log_info "Starting update: $util"
        local _op_start=$SECONDS

        local func="${UPDATE_FUNCS[$util]}"
        if [[ -n "$func" ]] && declare -f "$func" > /dev/null; then
            if $func; then
                echo ""
                echo "${GREEN}✓ Successfully updated: $util${RESET} ${DIM}($(( SECONDS - _op_start ))s)${RESET}"
                log_success "Updated: $util"
                ((success_count++))
            else
                echo ""
                echo "${RED}✗ Failed to update: $util${RESET} ${DIM}($(( SECONDS - _op_start ))s)${RESET}"
                log_error "Failed to update: $util"
                ((fail_count++))
                failed_utils+=("$util (update)")
            fi
        else
            echo "${RED}✗ No update function found for: $util${RESET}"
            log_error "No update function found for: $util"
            ((fail_count++))
            failed_utils+=("$util (update)")
        fi
    done
    
    # Summary
    echo ""
    echo "${BOLD}${GREEN}════════════════════════════════════════════════════════════════${RESET}"
    echo "${BOLD}${GREEN}                    Operations Complete                        ${RESET}"
    echo "${BOLD}${GREEN}════════════════════════════════════════════════════════════════${RESET}"
    echo ""
    echo "Summary:"
    echo "  ${GREEN}✓ Successful: ${success_count}${RESET}"
    
    # Log execution summary
    log_info "════════════════════════════════════════════════════════════════"
    log_info "Execution Summary"
    log_info "════════════════════════════════════════════════════════════════"
    log_info "Successful operations: ${success_count}"
    log_info "Failed operations: ${fail_count}"
    
    if [[ $fail_count -gt 0 ]]; then
        echo "  ${RED}✗ Failed: ${fail_count}${RESET}"
        echo ""
        echo "Failed operations:"
        for util in "${failed_utils[@]}"; do
            echo "    ${RED}- $util${RESET}"
            log_error "Operation failed: $util"
        done
    fi
    echo ""
    
    log_info "Script execution completed at: $(date '+%Y-%m-%d %H:%M:%S')"
    log_info "Log files saved to: ${LOG_DIR}"
    log_info "  - Success log: $(basename "$SUCCESS_LOG")"
    if [[ "$ERROR_LOG_INITIALIZED" == "true" ]]; then
        log_info "  - Error log: $(basename "$ERROR_LOG")"
    fi
    
    echo "Log files saved to: ${LOG_DIR}"
    echo ""
    
    # Offer reboot (only for System Tasks and Docker)
    if [[ "$needs_reboot" == "true" ]]; then
        read -n 1 -rp "Reboot now? (y/N) " REBOOT_CHOICE
        echo
        REBOOT_CHOICE=${REBOOT_CHOICE:-N}
        case "$REBOOT_CHOICE" in
            y|Y)
                info "Rebooting…"
                sudo reboot
                ;;
            *)
                info "Remember to reboot later if needed."
                ;;
        esac
    fi
}

# ============================================================================
# MAIN
# ============================================================================

# Parse CLI arguments for non-interactive / scripted usage.
# All flags are processed before the interactive menu is shown.
# Resolve a user-supplied utility name to its canonical form.
# Tries exact match first, then case-insensitive, then substring.
# Sets _RESOLVED to the canonical name or "" if no unique match.
resolve_utility_name() {
    local input="$1"
    _RESOLVED=""

    # Exact match
    for _candidate in "${UTILITIES[@]}"; do
        [[ "$_candidate" == "$input" ]] && { _RESOLVED="$_candidate"; return 0; }
    done

    # Case-insensitive exact match
    local _match_count=0
    for _candidate in "${UTILITIES[@]}"; do
        if [[ "${_candidate,,}" == "${input,,}" ]]; then
            _RESOLVED="$_candidate"
            return 0
        fi
    done

    # Substring match (case-insensitive)
    _match_count=0
    for _candidate in "${UTILITIES[@]}"; do
        if [[ "${_candidate,,}" == *"${input,,}"* ]]; then
            _RESOLVED="$_candidate"
            (( _match_count++ ))
        fi
    done
    if [[ $_match_count -eq 1 ]]; then
        return 0
    elif [[ $_match_count -gt 1 ]]; then
        echo "Error: '${input}' is ambiguous. Matches multiple utilities."
        echo "Run --list to see exact names."
        _RESOLVED=""
        return 1
    fi

    echo "Error: Unknown utility '${input}'. Run --list to see available options."
    _RESOLVED=""
    return 1
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --help|-h)
                cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Options:
  --help, -h            Show this help message and exit
  --version             Show script version (git commit)
  --list                List all available utilities with install status
  --dry-run             Preview actions without making any changes
  --install <name>      Non-interactively install a utility by name
  --uninstall <name>    Non-interactively uninstall a utility by name
  --update <name>       Non-interactively update a utility by name
  --update-all          Update every currently installed utility
  --check <name>        Exit 0 if utility is installed, 1 if not

Utility names are matched case-insensitively and support partial matches.
EOF
                exit 0
                ;;
            --version)
                echo "linux_util $(git -C "$SCRIPT_DIR" rev-parse --short HEAD 2>/dev/null || echo 'unknown')"
                exit 0
                ;;
            --list)
                echo "Available utilities:"
                for util in "${UTILITIES[@]}"; do
                    local check_func="${CHECK_FUNCS[$util]}"
                    local status="not installed"
                    if [[ -n "$check_func" ]] && declare -f "$check_func" &>/dev/null; then
                        if $check_func 2>/dev/null; then
                            status="installed"
                            local ver_func="${VERSION_FUNCS[$util]:-}"
                            if [[ -n "$ver_func" ]] && declare -f "$ver_func" &>/dev/null; then
                                local ver
                                ver=$($ver_func 2>/dev/null)
                                [[ -n "$ver" ]] && status="installed: v${ver}"
                            fi
                        fi
                    fi
                    printf "  %-35s [%s]\n" "$util" "$status"
                done
                exit 0
                ;;
            --dry-run)
                DRY_RUN=true
                echo "${YELLOW}[DRY RUN] No changes will be made.${RESET}"
                shift
                ;;
            --install)
                [[ -z "${2:-}" ]] && { echo "Error: --install requires a utility name."; exit 1; }
                resolve_utility_name "$2" || exit 1
                local _util="$_RESOLVED"; shift 2
                local _func="${INSTALL_FUNCS[$_util]}"
                pkg_refresh
                if [[ "$DRY_RUN" == "true" ]]; then
                    echo "[DRY RUN] Would install: $_util"; exit 0
                fi
                $_func && { echo "Installed: $_util"; exit 0; } || { echo "Failed: $_util"; exit 1; }
                ;;
            --uninstall)
                [[ -z "${2:-}" ]] && { echo "Error: --uninstall requires a utility name."; exit 1; }
                resolve_utility_name "$2" || exit 1
                local _util="$_RESOLVED"; shift 2
                local _func="${UNINSTALL_FUNCS[$_util]}"
                if [[ "$DRY_RUN" == "true" ]]; then
                    echo "[DRY RUN] Would uninstall: $_util"; exit 0
                fi
                $_func && { echo "Uninstalled: $_util"; exit 0; } || { echo "Failed: $_util"; exit 1; }
                ;;
            --update)
                [[ -z "${2:-}" ]] && { echo "Error: --update requires a utility name."; exit 1; }
                resolve_utility_name "$2" || exit 1
                local _util="$_RESOLVED"; shift 2
                local _func="${UPDATE_FUNCS[$_util]}"
                pkg_refresh
                if [[ "$DRY_RUN" == "true" ]]; then
                    echo "[DRY RUN] Would update: $_util"; exit 0
                fi
                $_func && { echo "Updated: $_util"; exit 0; } || { echo "Failed: $_util"; exit 1; }
                ;;
            --update-all)
                shift
                echo "Updating all installed utilities..."
                pkg_refresh
                local _updated=0 _failed=0
                for _util in "${UTILITIES[@]}"; do
                    local _check="${CHECK_FUNCS[$_util]:-}"
                    local _upd="${UPDATE_FUNCS[$_util]:-}"
                    if [[ -n "$_check" ]] && declare -f "$_check" &>/dev/null && $_check 2>/dev/null; then
                        if [[ -n "$_upd" ]] && declare -f "$_upd" &>/dev/null; then
                            echo "Updating: $_util"
                            if [[ "$DRY_RUN" == "true" ]]; then
                                echo "  (dry-run skipped)"
                            elif $_upd; then
                                (( _updated++ ))
                            else
                                echo "  Failed to update: $_util"
                                (( _failed++ ))
                            fi
                        fi
                    fi
                done
                echo "Done. Updated: ${_updated}, Failed: ${_failed}."
                exit $(( _failed > 0 ? 1 : 0 ))
                ;;
            --check)
                [[ -z "${2:-}" ]] && { echo "Error: --check requires a utility name."; exit 1; }
                resolve_utility_name "$2" || exit 1
                local _util="$_RESOLVED"; shift 2
                local _func="${CHECK_FUNCS[$_util]}"
                if $_func 2>/dev/null; then
                    local _ver_func="${VERSION_FUNCS[$_util]:-}"
                    if [[ -n "$_ver_func" ]] && declare -f "$_ver_func" &>/dev/null; then
                        local _ver
                        _ver=$($_ver_func 2>/dev/null)
                        if [[ -n "$_ver" ]]; then
                            echo "${_util} is installed (v${_ver})"; exit 0
                        fi
                    fi
                    echo "${_util} is installed"; exit 0
                else
                    echo "${_util} is not installed"; exit 1
                fi
                ;;
            *)
                echo "Unknown option: $1"
                echo "Run '$(basename "$0") --help' for usage."
                exit 1
                ;;
        esac
    done
}

main() {
    self_update_script "$@"
    parse_args "$@"
    run_selection_menu
    process_selected
}

main "$@"

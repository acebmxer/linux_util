#!/bin/bash

# ============================================================================
# Linux Utilities - Package Manager Module
# Provides distro detection and package manager abstraction layer
# ============================================================================

# Detect the distro and set package manager variables
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
        ubuntu|kubuntu|debian|linuxmint|pop|elementary|zorin|kali|neon)
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
        apt)     sudo apt full-upgrade -y ;;
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

# --- Helper checks for other utilities ---

has_snap() {
    command -v snap &>/dev/null
}

has_flatpak() {
    command -v flatpak &>/dev/null
}

# Ensure required tools are installed (gnupg, curl, wget)
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

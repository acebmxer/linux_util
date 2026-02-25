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
}

# --- Package Manager Wrappers ---

pkg_refresh() {
    case "$PKG_MGR" in
        apt)     sudo apt update ;;
        dnf|yum) sudo "$PKG_MGR" makecache ;;
        pacman)  sudo pacman -Sy ;;
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
        apt)     sudo apt clean -y && sudo apt autoclean -y ;;
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

# Detect the distro at startup
detect_distro
echo ""

# ============================================================================
# SYSTEM SETUP OPTIONS (from linux_setup_script)
# ============================================================================

# Helper functions
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
    esac
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
    
    # Full system upgrade
    pkg_full_upgrade
    pkg_autoremove
    pkg_clean
    
    info "System has been fully updated and upgraded."
    return 0
}

# --- Option 2: Install/Update XEN Guest Utilities ---
setup_xen_guest_utilities() {
    info "Installing/Updating XEN Guest Utilities..."
    
    # Check for existing installations and optionally remove them
    if pkg_check_installed xe-guest-utilities; then
        ver=$(pkg_get_version xe-guest-utilities)
        info "xe-guest-utilities is installed, version $ver."
        read -n 1 -rp "Would you like to uninstall existing xe-guest-utilities (v$ver) before installing new tools? [y/N] " ans
        echo
        case "$ans" in
            y|Y|yes|Yes)
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
            y|Y|yes|Yes)
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
        run_as_root "cd '${MOUNT_POINT}/Linux' && bash ./install.sh"
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
    cd ~/dotfiles || return 1
    # Note: If you see "apt: command not found" errors below, they come from the dotfiles
    # install.sh script and may be ignored on non-Debian systems if the script continues.
    ./install.sh
    chsh -s /bin/zsh || warn "Failed to change shell to zsh for current user."
    cd ..
    
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

# --- Option 6: Install Docker ---
setup_install_docker() {
    info "Installing Docker..."
    ensure_tools
    
    case "$PKG_MGR" in
        apt)
            # Debian/Ubuntu-based systems
            run_as_root "apt-get update"
            run_as_root "apt-get install -y apt-transport-https ca-certificates curl gnupg"
            
            # Install software-properties-common only on Ubuntu
            if [[ "$DISTRO_ID" == "ubuntu" ]] || [[ "$DISTRO_ID" == "linuxmint" ]] || [[ "$DISTRO_ID" == "pop" ]]; then
                run_as_root "apt-get install -y software-properties-common"
            fi
            
            local docker_dist="$DISTRO_ID"
            [[ "$DISTRO_ID" == "linuxmint" || "$DISTRO_ID" == "pop" ]] && docker_dist="ubuntu"
            
            run_as_root "curl -fsSL https://download.docker.com/linux/${docker_dist}/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg"
            echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/${docker_dist} ${DISTRO_VERSION_CODENAME:-stable} stable" | \
                sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
            run_as_root "apt-get update"
            run_as_root "apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin"
            ;;
            
        dnf|yum)
            # Fedora/RHEL-based systems
            run_as_root "$PKG_MGR install -y dnf-plugins-core 2>/dev/null || $PKG_MGR install -y yum-utils"
            
            local docker_repo
            [[ "$DISTRO_ID" == "fedora" ]] && docker_repo="https://download.docker.com/linux/fedora/docker-ce.repo" || docker_repo="https://download.docker.com/linux/centos/docker-ce.repo"
            
            run_as_root "$PKG_MGR config-manager --add-repo ${docker_repo}"
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
            # Arch Linux
            run_as_root "pacman -S --noconfirm docker docker-compose docker-buildx"
            run_as_root "systemctl start docker.service"
            run_as_root "systemctl enable docker.service"
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

# ============================================================================
# UTILITY DEFINITIONS
# ============================================================================

# --- System Setup Tasks ---
UTILITIES+=("Full System Upgrade/Update")
INSTALL_FUNCS["Full System Upgrade/Update"]="setup_full_update_bare_metal"
CHECK_FUNCS["Full System Upgrade/Update"]="check_always_false"
UNINSTALL_FUNCS["Full System Upgrade/Update"]="noop_function"
UPDATE_FUNCS["Full System Upgrade/Update"]="setup_full_update_bare_metal"

UTILITIES+=("XEN Guest Utilities")
INSTALL_FUNCS["XEN Guest Utilities"]="setup_xen_guest_utilities"
CHECK_FUNCS["XEN Guest Utilities"]="check_always_false"
UNINSTALL_FUNCS["XEN Guest Utilities"]="noop_function"
UPDATE_FUNCS["XEN Guest Utilities"]="setup_xen_guest_utilities"

UTILITIES+=("System Updates")
INSTALL_FUNCS["System Updates"]="setup_system_updates"
CHECK_FUNCS["System Updates"]="check_always_false"
UNINSTALL_FUNCS["System Updates"]="noop_function"
UPDATE_FUNCS["System Updates"]="setup_system_updates"

# Helper functions for system setup tasks
check_always_false() { return 1; }
noop_function() { return 0; }
check_xen_guest_utilities() {
    pkg_check_installed xe-guest-utilities || pkg_check_installed xen-guest-agent
}

# --- Installable Utilities ---

# Dotfiles
UTILITIES+=("Dotfiles")
INSTALL_FUNCS["Dotfiles"]="setup_install_dotfiles"
CHECK_FUNCS["Dotfiles"]="check_dotfiles"
UNINSTALL_FUNCS["Dotfiles"]="noop_function"
UPDATE_FUNCS["Dotfiles"]="setup_install_dotfiles"

check_dotfiles() {
    [[ -d ~/dotfiles ]] && [[ -f ~/.zshrc ]]
}

# Docker
UTILITIES+=("Docker")
INSTALL_FUNCS["Docker"]="setup_install_docker"
CHECK_FUNCS["Docker"]="check_docker"
UNINSTALL_FUNCS["Docker"]="uninstall_docker"
UPDATE_FUNCS["Docker"]="update_docker"

# --- Bitwarden Client ---
UTILITIES+=("Bitwarden Client")
INSTALL_FUNCS["Bitwarden Client"]="install_bitwarden"
CHECK_FUNCS["Bitwarden Client"]="check_bitwarden"
UNINSTALL_FUNCS["Bitwarden Client"]="uninstall_bitwarden"
UPDATE_FUNCS["Bitwarden Client"]="update_bitwarden"

check_bitwarden() {
    command -v bitwarden &>/dev/null || \
        (has_snap && snap list bitwarden &>/dev/null) || \
        (has_flatpak && flatpak list 2>/dev/null | grep -qi bitwarden) || \
        pkg_check_installed bitwarden
}
install_bitwarden() {
    echo "Installing Bitwarden Client..."
    case "$DISTRO_FAMILY" in
        arch)
            if has_aur_helper; then
                aur_install bitwarden
            elif has_snap; then
                sudo snap install bitwarden
            else
                echo "Error: An AUR helper (yay/paru) or snap is required."
                return 1
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
    elif pkg_check_installed bitwarden; then
        pkg_upgrade bitwarden
    else
        echo "Bitwarden installation not found."
        return 1
    fi
}

# --- Brave Browser ---
UTILITIES+=("Brave Browser")
INSTALL_FUNCS["Brave Browser"]="install_brave"
CHECK_FUNCS["Brave Browser"]="check_brave"
UNINSTALL_FUNCS["Brave Browser"]="uninstall_brave"
UPDATE_FUNCS["Brave Browser"]="update_brave"

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
            sudo "$PKG_MGR" config-manager --add-repo https://brave-browser-rpm-release.s3.brave.com/brave-browser.repo
            sudo rpm --import https://brave-browser-rpm-release.s3.brave.com/brave-core.asc
            sudo "$PKG_MGR" install -y brave-browser
            ;;
        arch)
            if has_aur_helper; then
                aur_install brave-bin
            else
                echo "Error: An AUR helper (yay/paru) is required to install Brave on Arch."
                return 1
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
                echo "Error: An AUR helper (yay/paru) is required."
                return 1
            fi
            ;;
        *)
            pkg_upgrade brave-browser
            ;;
    esac
}

# --- Joplin Client ---
UTILITIES+=("Joplin Client")
INSTALL_FUNCS["Joplin Client"]="install_joplin"
CHECK_FUNCS["Joplin Client"]="check_joplin"
UNINSTALL_FUNCS["Joplin Client"]="uninstall_joplin"
UPDATE_FUNCS["Joplin Client"]="update_joplin"

check_joplin() {
    [[ -f ~/.joplin/Joplin.AppImage ]] || command -v joplin &>/dev/null
}
install_joplin() {
    echo "Installing Joplin Client..."
    wget -O - https://raw.githubusercontent.com/laurent22/joplin/dev/Joplin_install_and_update.sh | bash
}
uninstall_joplin() {
    echo "Uninstalling Joplin Client..."
    rm -rf ~/.joplin
    rm -f ~/.local/share/applications/joplin.desktop
}
update_joplin() {
    echo "Updating Joplin Client..."
    wget -O - https://raw.githubusercontent.com/laurent22/joplin/dev/Joplin_install_and_update.sh | bash
}

# --- Termius SSH Client ---
UTILITIES+=("Termius SSH Client")
INSTALL_FUNCS["Termius SSH Client"]="install_termius"
CHECK_FUNCS["Termius SSH Client"]="check_termius"
UNINSTALL_FUNCS["Termius SSH Client"]="uninstall_termius"
UPDATE_FUNCS["Termius SSH Client"]="update_termius"

check_termius() {
    command -v termius-app &>/dev/null || \
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
        *)
            if has_snap; then
                sudo snap install termius-app
            elif has_flatpak; then
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
    if pkg_check_installed termius-app; then
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

# --- Steam App ---
UTILITIES+=("Steam App")
INSTALL_FUNCS["Steam App"]="install_steam"
CHECK_FUNCS["Steam App"]="check_steam"
UNINSTALL_FUNCS["Steam App"]="uninstall_steam"
UPDATE_FUNCS["Steam App"]="update_steam"

check_steam() {
    command -v steam &>/dev/null || pkg_check_installed steam || pkg_check_installed steam-launcher
}
install_steam() {
    echo "Installing Steam..."
    case "$DISTRO_FAMILY" in
        debian)
            sudo dpkg --add-architecture i386
            sudo apt update
            sudo apt install -y steam
            ;;
        fedora)
            if ! rpm -q rpmfusion-nonfree-release &>/dev/null; then
                echo "Enabling RPM Fusion repositories (required for Steam)..."
                sudo "$PKG_MGR" install -y \
                    "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm" \
                    "https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm"
            fi
            sudo "$PKG_MGR" install -y steam
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
                echo "Enabling multilib repository..."
                sudo bash -c 'echo -e "\n[multilib]\nInclude = /etc/pacman.d/mirrorlist" >> /etc/pacman.conf'
                sudo pacman -Sy
            fi
            sudo pacman -S --noconfirm steam
            ;;
        suse)
            sudo zypper install -y steam
            ;;
    esac
}
uninstall_steam() {
    echo "Uninstalling Steam..."
    if has_flatpak && flatpak list 2>/dev/null | grep -qi "com.valvesoftware.Steam"; then
        flatpak uninstall -y com.valvesoftware.Steam
    else
        case "$DISTRO_FAMILY" in
            debian) sudo apt remove -y steam steam-launcher ;;
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

# --- Visual Studio Code ---
UTILITIES+=("Visual Studio Code")
INSTALL_FUNCS["Visual Studio Code"]="install_vscode"
CHECK_FUNCS["Visual Studio Code"]="check_vscode"
UNINSTALL_FUNCS["Visual Studio Code"]="uninstall_vscode"
UPDATE_FUNCS["Visual Studio Code"]="update_vscode"

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
                echo "Error: An AUR helper (yay/paru) is required to install VS Code on Arch."
                return 1
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
                echo "Error: An AUR helper (yay/paru) is required."
                return 1
            fi
            ;;
        *)
            pkg_upgrade code
            ;;
    esac
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

# Track selections (0 = not selected, 1 = selected)
declare -a SELECTED
# Track installed state (0 = not installed, 1 = installed)
declare -a INSTALLED

# Check which utilities are already installed
check_installed_utilities() {
    echo "Checking installed utilities..."
    for ((i=0; i<${#UTILITIES[@]}; i++)); do
        local util="${UTILITIES[$i]}"
        local check_func="${CHECK_FUNCS[$util]}"
        
        if [[ -n "$check_func" ]] && declare -f "$check_func" > /dev/null; then
            if $check_func 2>/dev/null; then
                INSTALLED[$i]=1
                SELECTED[$i]=1  # Pre-select installed utilities
            else
                INSTALLED[$i]=0
                SELECTED[$i]=0
            fi
        else
            INSTALLED[$i]=0
            SELECTED[$i]=0
        fi
    done
}

# Initialize arrays
for ((i=0; i<${#UTILITIES[@]}; i++)); do
    SELECTED[$i]=0
    INSTALLED[$i]=0
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
    
    echo ""
    echo "${BOLD}${CYAN}╔══════════════════════════════════════════════════════════════╗${RESET}"
    echo "${BOLD}${CYAN}║   Linux System Setup & Utilities - Select Programs/Tasks     ║${RESET}"
    echo "${BOLD}${CYAN}╚══════════════════════════════════════════════════════════════╝${RESET}"
    echo ""
    echo "${YELLOW}Use ↑/↓ to navigate, SPACE to select/deselect, ENTER to continue, Q to quit${RESET}"
    echo ""
    echo "${DIM}Legend: ${GREEN}[✓]${RESET}${DIM} = selected  ${RESET}${DIM}[ ]${RESET}${DIM} = not selected  ${MAGENTA}(installed)${RESET}${DIM} = already on system${RESET}"
    echo ""
    
    for ((i=0; i<total; i++)); do
        local prefix="  "
        local checkbox="[ ]"
        local name="${UTILITIES[$i]}"
        local status_tag=""
        
        # Highlight current item
        if [[ $i -eq $CURSOR ]]; then
            prefix="${BOLD}${BLUE}▸ ${RESET}"
        fi
        
        # Show selection state
        if [[ ${SELECTED[$i]} -eq 1 ]]; then
            checkbox="${GREEN}[✓]${RESET}"
        fi
        
        # Show installed status
        if [[ ${INSTALLED[$i]} -eq 1 ]]; then
            status_tag=" ${MAGENTA}(installed)${RESET}"
        fi
        
        if [[ $i -eq $CURSOR ]]; then
            echo "${prefix}${checkbox} ${BOLD}${name}${RESET}${status_tag}"
        else
            echo "${prefix}${checkbox} ${name}${status_tag}"
        fi
    done
    
    echo ""
    echo "────────────────────────────────────────────────────────────────"
    
    # Count selected items and categorize actions
    local install_count=0
    local update_count=0
    local uninstall_count=0
    for ((i=0; i<total; i++)); do
        if [[ ${SELECTED[$i]} -eq 1 ]]; then
            if [[ ${INSTALLED[$i]} -eq 1 ]]; then
                ((update_count++))
            else
                ((install_count++))
            fi
        else
            if [[ ${INSTALLED[$i]} -eq 1 ]]; then
                ((uninstall_count++))
            fi
        fi
    done
    
    echo "${CYAN}Actions: ${GREEN}Install/Run: ${install_count}${RESET} | ${BLUE}Update: ${update_count}${RESET} | ${RED}Uninstall: ${uninstall_count}${RESET}"
    echo ""
}

# Redraw the menu (clear and redraw for reliability)
redraw_menu() {
    clear
    draw_menu
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
            *) echo "OTHER" ;;
        esac
    elif [[ $key == "" ]]; then
        echo "ENTER"
    elif [[ $key == " " ]]; then
        echo "SPACE"
    elif [[ $key == "q" ]] || [[ $key == "Q" ]]; then
        echo "QUIT"
    else
        echo "OTHER"
    fi
}

# Main selection loop
run_selection_menu() {
    local total=${#UTILITIES[@]}
    
    # Check which utilities are already installed
    check_installed_utilities
    
    # Setup terminal
    hide_cursor
    stty -echo
    
    # Cleanup on exit
    trap 'show_cursor; stty echo; echo ""' EXIT
    
    # Initial draw
    clear
    draw_menu
    
    while true; do
        local key=$(read_key)
        
        case "$key" in
            UP)
                if [[ $CURSOR -gt 0 ]]; then
                    ((CURSOR--))
                else
                    CURSOR=$((total - 1))  # Wrap to bottom
                fi
                redraw_menu
                ;;
            DOWN)
                if [[ $CURSOR -lt $((total - 1)) ]]; then
                    ((CURSOR++))
                else
                    CURSOR=0  # Wrap to top
                fi
                redraw_menu
                ;;
            SPACE)
                # Toggle selection
                if [[ ${SELECTED[$CURSOR]} -eq 0 ]]; then
                    SELECTED[$CURSOR]=1
                else
                    SELECTED[$CURSOR]=0
                fi
                redraw_menu
                ;;
            ENTER)
                # Continue to installation
                show_cursor
                stty echo
                trap - EXIT
                return 0
                ;;
            QUIT)
                show_cursor
                stty echo
                trap - EXIT
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
    declare -a to_install
    declare -a to_update
    declare -a to_uninstall
    
    # Categorize utilities based on selection and installed state
    for ((i=0; i<total; i++)); do
        local util="${UTILITIES[$i]}"
        if [[ ${SELECTED[$i]} -eq 1 ]]; then
            if [[ ${INSTALLED[$i]} -eq 1 ]]; then
                to_update+=("$util")
            else
                to_install+=("$util")
            fi
        else
            if [[ ${INSTALLED[$i]} -eq 1 ]]; then
                to_uninstall+=("$util")
            fi
        fi
    done
    
    # Check if there's anything to do
    if [[ ${#to_install[@]} -eq 0 ]] && [[ ${#to_update[@]} -eq 0 ]] && [[ ${#to_uninstall[@]} -eq 0 ]]; then
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
    
    if [[ ${#to_update[@]} -gt 0 ]]; then
        echo "${BLUE}To Update (${#to_update[@]}):${RESET}"
        for util in "${to_update[@]}"; do
            echo "  ${BLUE}↑${RESET} $util"
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
    
    read -p "Press ENTER to continue or Ctrl+C to cancel..."
    echo ""
    
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
        echo "${BOLD}${RED}Uninstalling: $util${RESET}"
        echo "${BOLD}${RED}────────────────────────────────────────────────────────────────${RESET}"
        echo ""
        
        local func="${UNINSTALL_FUNCS[$util]}"
        if [[ -n "$func" ]] && declare -f "$func" > /dev/null; then
            if $func; then
                echo ""
                echo "${GREEN}✓ Successfully uninstalled: $util${RESET}"
                ((success_count++))
            else
                echo ""
                echo "${RED}✗ Failed to uninstall: $util${RESET}"
                ((fail_count++))
                failed_utils+=("$util (uninstall)")
            fi
        else
            echo "${RED}✗ No uninstall function found for: $util${RESET}"
            ((fail_count++))
            failed_utils+=("$util (uninstall)")
        fi
    done
    
    # Process updates
    for util in "${to_update[@]}"; do
        echo ""
        echo "${BOLD}${BLUE}────────────────────────────────────────────────────────────────${RESET}"
        echo "${BOLD}${BLUE}Updating: $util${RESET}"
        echo "${BOLD}${BLUE}────────────────────────────────────────────────────────────────${RESET}"
        echo ""
        
        local func="${UPDATE_FUNCS[$util]}"
        if [[ -n "$func" ]] && declare -f "$func" > /dev/null; then
            if $func; then
                echo ""
                echo "${GREEN}✓ Successfully updated: $util${RESET}"
                ((success_count++))
            else
                echo ""
                echo "${RED}✗ Failed to update: $util${RESET}"
                ((fail_count++))
                failed_utils+=("$util (update)")
            fi
        else
            echo "${RED}✗ No update function found for: $util${RESET}"
            ((fail_count++))
            failed_utils+=("$util (update)")
        fi
    done
    
    # Process installations
    for util in "${to_install[@]}"; do
        echo ""
        echo "${BOLD}${GREEN}────────────────────────────────────────────────────────────────${RESET}"
        echo "${BOLD}${GREEN}Installing/Running: $util${RESET}"
        echo "${BOLD}${GREEN}────────────────────────────────────────────────────────────────${RESET}"
        echo ""
        
        local func="${INSTALL_FUNCS[$util]}"
        if [[ -n "$func" ]] && declare -f "$func" > /dev/null; then
            if $func; then
                echo ""
                echo "${GREEN}✓ Successfully completed: $util${RESET}"
                ((success_count++))
            else
                echo ""
                echo "${RED}✗ Failed: $util${RESET}"
                ((fail_count++))
                failed_utils+=("$util (install)")
            fi
        else
            echo "${RED}✗ No installation function found for: $util${RESET}"
            ((fail_count++))
            failed_utils+=("$util (install)")
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
    if [[ $fail_count -gt 0 ]]; then
        echo "  ${RED}✗ Failed: ${fail_count}${RESET}"
        echo ""
        echo "Failed operations:"
        for util in "${failed_utils[@]}"; do
            echo "    ${RED}- $util${RESET}"
        done
    fi
    echo ""
    
    # Offer reboot
    if [[ ${#to_install[@]} -gt 0 ]] || [[ ${#to_update[@]} -gt 0 ]]; then
        read -n 1 -rp "Reboot now? (y/N) " REBOOT_CHOICE
        echo
        REBOOT_CHOICE=${REBOOT_CHOICE:-N}
        case "$REBOOT_CHOICE" in
            y|Y|yes|YES)
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

main() {
    # Check if running in interactive terminal
    if [[ ! -t 0 ]]; then
        echo "Error: This script must be run in an interactive terminal."
        exit 1
    fi
    
    run_selection_menu
    process_selected
}

main "$@"

#!/bin/bash

# ============================================================================
# Linux Utilities - Installers Module
# Provides installation, uninstallation, update, and version check functions
# for all utilities and system setup tasks
# ============================================================================

get_version_landscape_motd() {
    pkg_get_version landscape-client | grep -oE '^[0-9]+\.[0-9]+\.[0-9]+' || echo ""
}

check_landscape_motd() {
    pkg_check_installed landscape-client
}

setup_local_motd() {
    info "Installing/Updating Landscape Client and configuring Local MOTD..."

    run_as_root "add-apt-repository -y ppa:landscape/self-hosted-beta 2>/dev/null || true"
    run_as_root "apt-get update && apt-get install -y --no-install-recommends landscape-client" || {
        warn "Failed to install landscape-client"
        return 1
    }

    local motd_code='# Display MOTD for ZSH
if [ -f /etc/update-motd.d/00-header ]; then
    /etc/update-motd.d/00-header
fi
if [ -f /etc/update-motd.d/10-help-text ]; then
    /etc/update-motd.d/10-help-text
fi
if [ -f /etc/update-motd.d/50-motd-news ]; then
    /etc/update-motd.d/50-motd-news
fi
if [ -f /etc/update-motd.d/85-fwupd ]; then
    /etc/update-motd.d/85-fwupd
fi
if [ -f /etc/update-motd.d/90-updates-available ]; then
    /etc/update-motd.d/90-updates-available
fi
if [ -f /etc/update-motd.d/91-contract-ua-esm-status ]; then
    /etc/update-motd.d/91-contract-ua-esm-status
fi
if [ -f /etc/update-motd.d/91-release-upgrade ]; then
    /etc/update-motd.d/91-release-upgrade
fi
if [ -f /etc/update-motd.d/95-hwe-eol ]; then
    /etc/update-motd.d/95-hwe-eol
fi
if [ -f /etc/update-motd.d/98-fsck-at-reboot ]; then
    /etc/update-motd.d/98-fsck-at-reboot
fi
if [ -f /etc/update-motd.d/98-reboot-required ]; then
    /etc/update-motd.d/98-reboot-required
fi'

    if [[ -f "${HOME}/.bashrc" ]]; then
        if ! grep -q "Display MOTD for ZSH" "${HOME}/.bashrc"; then
            echo "" >> "${HOME}/.bashrc"
            echo "$motd_code" >> "${HOME}/.bashrc"
            info "Added MOTD display code to ~/.bashrc"
            source "${HOME}/.bashrc"
        else
            info "MOTD code already present in ~/.bashrc"
        fi
    fi

    if [[ -f "${HOME}/.zshrc" ]]; then
        if ! grep -q "Display MOTD for ZSH" "${HOME}/.zshrc"; then
            echo "" >> "${HOME}/.zshrc"
            echo "$motd_code" >> "${HOME}/.zshrc"
            info "Added MOTD display code to ~/.zshrc"
            source "${HOME}/.zshrc"
        else
            info "MOTD code already present in ~/.zshrc"
        fi
    fi

    info "Local MOTD configuration complete."
}

uninstall_landscape_motd() {
    info "Uninstalling Landscape Client and removing MOTD configuration..."
    run_as_root "apt-get remove -y landscape-client" || warn "Failed to uninstall landscape-client"

    if [[ -f "${HOME}/.bashrc" ]]; then
        sed -i '/^# Display MOTD for ZSH/,/^fi$/d' "${HOME}/.bashrc"
        info "Removed MOTD code from ~/.bashrc"
        source "${HOME}/.bashrc" 2>/dev/null || true
    fi

    if [[ -f "${HOME}/.zshrc" ]]; then
        sed -i '/^# Display MOTD for ZSH/,/^fi$/d' "${HOME}/.zshrc"
        info "Removed MOTD code from ~/.zshrc"
        source "${HOME}/.zshrc" 2>/dev/null || true
    fi

    info "Local MOTD configuration removed."
}

update_landscape_motd() {
    info "Updating Landscape Client..."
    run_as_root "apt-get update && apt-get upgrade -y landscape-client" || warn "Failed to update landscape-client"
    info "Landscape Client updated."
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
    if ! git -C "$SCRIPT_DIR" pull --ff-only origin main; then
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
# ALPHABETICAL ORDER CRITICAL: Utilities appear A-Z in menu (lines 1253+)
#
# WHEN ADDING A NEW UTILITY, FOLLOW THIS CHECKLIST:
# ┌─ Step 1: Choose alphabetically correct position (between similar names)
# ├─ Step 2: Write register_utility line with these requirements:
# │  • register_utility "Display Name" install_fn check_fn uninstall_fn update_fn [get_version_fn]
# │  • Display Name must be unique and human-readable
# │  • All function names must follow pattern: {verb}_{utility_slug}
# │    (Examples: install_brave, check_docker, get_version_qbittorrent)
# │  • version_fn is OPTIONAL—only provide if you implement get_version_X function
# │
# ├─ Step 3: Implement required functions (place after System Tasks section)
# │  REQUIRED (4 functions):
# │    ├─ install_utility_name() — main installation logic
# │    ├─ check_utility_name() — returns 0 if installed, 1 if missing
# │    ├─ uninstall_utility_name() — remove utility and cleanup
# │    └─ update_utility_name() — update to latest version
# │
# │  OPTIONAL (1 function):
# │    └─ get_version_utility_name() — outputs version string only (no labels)
# │       IF provided, register it as 6th parameter (see register_utility call)
# │       Version function MUST output clean version string: "X.Y.Z" or timestamp
# │       Test it by running: ./linux_util.sh; then check "(vX.Y.Z)" in menu
# │
# ├─ Step 4: Test menu rendering
# │  $ ./linux_util.sh
# │  ├─ Verify new utility appears in correct alphabetical position
# │  ├─ If has version_fn: verify "(vX.Y.Z)" displays in menu
# │  ├─ If no version_fn: verify "(installed)" shows when utility is present
# │  └─ Verify checkbox selection/deselection works (SPACE key)
# │
# └─ Step 5: Test functionality
#    ├─ Test with --dry-run flag (./linux_util.sh --dry-run)
#    ├─ Select utility and press ENTER to verify install() function works
#    ├─ Verify check_utility_name() correctly detects installed state
#    └─ Test uninstall and update functions
#
# EXAMPLE: Adding "FooBar Tool" utility
#   1. Find correct position: Between "Docker" and "Dotfiles"
#   2. Add registration: register_utility "FooBar Tool" install_foobar_tool check_foobar_tool ...
#   3. Implement functions: install_foobar_tool(), check_foobar_tool(), etc.
#   4. Optional: add get_version_foobar_tool() to show version in menu
#   5. Test it shows in menu in correct position with correct status

# --- System Tasks (must be registered before utilities) ---
register_utility "Full System Upgrade/Update" setup_full_update_bare_metal check_always_false noop_function setup_full_update_bare_metal
register_utility "KDE Desktop"        install_kde             check_kde             uninstall_kde             update_kde                get_version_kde
register_utility "NVIDIA Drivers"     install_nvidia_drivers  check_nvidia_drivers  uninstall_nvidia_drivers  update_nvidia_drivers     get_version_nvidia_drivers
register_utility "System Updates"     setup_system_updates    check_always_false    noop_function             setup_system_updates
register_utility "XEN Guest Utilities" setup_xen_guest_utilities check_xen_guest_utilities noop_function setup_xen_guest_utilities get_version_xen_guest_utilities

# Landscape MOTD (Ubuntu, Kubuntu, KDE Neon)
if [[ "$DISTRO_ID" == "ubuntu" ]] || [[ "$DISTRO_ID" == "kubuntu" ]] || [[ "$DISTRO_ID" == "neon" ]]; then
    register_utility "Local MOTD"    setup_local_motd        check_landscape_motd  uninstall_landscape_motd  update_landscape_motd     get_version_landscape_motd
fi

# Update SYSTEM_TASK_COUNT dynamically based on actual registrations
SYSTEM_TASK_COUNT=${#UTILITIES[@]}

# --- Utilities (alphabetical order) ---
register_utility "Bitwarden Client"    install_bitwarden       check_bitwarden       uninstall_bitwarden       update_bitwarden          get_version_bitwarden
register_utility "Brave Browser"       install_brave           check_brave           uninstall_brave           update_brave              get_version_brave
register_utility "Devolutions RDM"     install_devolutions_rdm check_devolutions_rdm uninstall_devolutions_rdm update_devolutions_rdm    get_version_devolutions_rdm
register_utility "Docker"              setup_install_docker    check_docker          uninstall_docker          update_docker             get_version_docker
register_utility "Dotfiles"            setup_install_dotfiles  check_dotfiles        noop_function             setup_install_dotfiles
register_utility "Joplin Client"       install_joplin          check_joplin          uninstall_joplin          update_joplin             get_version_joplin
register_utility "LibreOffice"         install_libreoffice     check_libreoffice     uninstall_libreoffice     update_libreoffice        get_version_libreoffice
register_utility "OpenSSH Server"      install_openssh_server  check_openssh_server  uninstall_openssh_server  update_openssh_server     get_version_openssh_server
register_utility "PIA VPN"             install_pia_vpn         check_pia_vpn         uninstall_pia_vpn         update_pia_vpn            get_version_pia_vpn
register_utility "QBittorrent"         install_qbittorrent     check_qbittorrent     uninstall_qbittorrent     update_qbittorrent        get_version_qbittorrent
register_utility "Steam App"           install_steam           check_steam           uninstall_steam           update_steam              get_version_steam
register_utility "Syncthing"           install_syncthing       check_syncthing       uninstall_syncthing       update_syncthing          get_version_syncthing
register_utility "Termius SSH Client"  install_termius         check_termius         uninstall_termius         update_termius            get_version_termius
register_utility "Timeshift"           install_timeshift       check_timeshift       uninstall_timeshift       update_timeshift          get_version_timeshift
register_utility "Visual Studio Code"  install_vscode          check_vscode          uninstall_vscode          update_vscode             get_version_vscode

# --- Helper Functions for System Tasks ---
noop_function() {
    return 0
}

check_always_false() {
    return 1
}

# --- Utility Check Functions ---
check_dotfiles() {
    [[ -d ~/dotfiles ]] && [[ -f ~/.zshrc ]]
}

setup_install_dotfiles() {
    info "Installing dotfiles..."

    if [[ "$DISTRO_ID" == "fedora" || "$DISTRO_ID" == "rhel" || "$DISTRO_ID" == "centos" || "$DISTRO_ID" == "rocky" || "$DISTRO_ID" == "almalinux" ]]; then
        warn "Dotfiles installation not supported for Fedora-based distros."
        return 1
    fi

    info "Starting as regular user"
    rm -rf ~/dotfiles
    info "Previous dotfiles folder was removed."
    git clone https://github.com/flipsidecreations/dotfiles.git ~/dotfiles || { warn "Failed to clone dotfiles"; return 1; }
    (
        cd ~/dotfiles || exit 1
        ./install.sh
    ) || { warn "Dotfiles install.sh failed"; return 1; }
    chsh -s /bin/zsh || warn "Failed to change shell to zsh for current user."

    info "Installing dotfiles for root..."
    sudo -s <<'EOF'
info() { printf '\e[32m[INFO]\e[0m %s\n' "$*"; }
warn() { printf '\e[33m[WARN]\e[0m %s\n' "$*"; }
info "Now running as root"
rm -rf ~/dotfiles
git clone https://github.com/flipsidecreations/dotfiles.git ~/dotfiles || exit 0
cd ~/dotfiles || exit 0
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

# --- XEN Guest Utilities ---
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

setup_xen_guest_utilities() {
    info "Installing/Updating XEN Guest Utilities..."

    # Primary method: ISO installation

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
        if ! run_as_root "mount /dev/cdrom '${MOUNT_POINT}'" 2>/dev/null; then
            info "Failed to mount ISO. Falling back to repository installation..."
            _install_from_repository
            return $?
        fi
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
        if run_as_root "bash '${MOUNT_POINT}/Linux/install.sh' ${install_flags}"; then
            info "Waiting 5 seconds for services to initialize..."
            sleep 5
            run_as_root "umount '${MOUNT_POINT}'" || warn "Failed to unmount ${MOUNT_POINT}"
            info "XCP-NG Tools installation completed."
            return 0
        else
            warn "ISO installation failed. Falling back to repository installation..."
            run_as_root "umount '${MOUNT_POINT}'" || warn "Failed to unmount ${MOUNT_POINT}"
            _install_from_repository
            return $?
        fi
    else
        warn "Installer script not found at ${MOUNT_POINT}/Linux/install.sh. Falling back to repository installation..."
        run_as_root "umount '${MOUNT_POINT}'" 2>/dev/null || true
        _install_from_repository
        return $?
    fi
}

# Helper function: Install XEN utilities from repository (fallback method)
_install_from_repository() {
    info "Attempting repository installation..."

    case "$DISTRO_FAMILY" in
        debian)
            info "Installing xe-guest-utilities via apt..."
            run_as_root "apt-get update && apt-get install -y xe-guest-utilities"
            return $?
            ;;

        fedora|rhel)
            run_as_root "yum install -y epel-release" 2>/dev/null || true
            info "Installing xe-guest-utilities via yum..."
            if run_as_root "yum install -y xe-guest-utilities-latest" 2>/dev/null || \
               run_as_root "yum install -y xe-guest-utilities"; then
                run_as_root "systemctl enable xe-linux-distribution" || warn "Failed to enable xe-linux-distribution"
                run_as_root "systemctl start xe-linux-distribution" || warn "Failed to start xe-linux-distribution"
                return 0
            fi
            return 1
            ;;

        arch)
            info "Installing xe-guest-utilities via pacman..."
            run_as_root "pacman -S --noconfirm xe-guest-utilities"
            return $?
            ;;

        suse)
            info "Installing xe-guest-utilities via zypper..."
            run_as_root "zypper install -y xe-guest-utilities"
            return $?
            ;;

        alpine)
            info "Installing xe-guest-utilities via apk..."
            run_as_root "apk add -X http://dl-cdn.alpinelinux.org/alpine/edge/community xe-guest-utilities"
            return $?
            ;;

        *)
            error "Repository installation not supported for ${DISTRO_NAME}"
            return 1
            ;;
    esac
}

# --- Full System Update (Bare Metal) ---
setup_full_update_bare_metal() {
    info "Starting full system update and upgrade (bare metal)..."

    # Install basic tools
    case "$PKG_MGR" in
        apt)
            run_as_root "apt-get update"
            run_as_root "apt-get install -y --no-install-recommends jq tzdata git curl wget gnupg"
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

    local keyring_dir="${HOME}/.local/share/keyrings"
    local keyring_backup=""
    if [[ -d "$keyring_dir" ]] && [[ -n "$(ls -A "$keyring_dir" 2>/dev/null)" ]]; then
        keyring_backup=$(mktemp -d)
        CLEANUP_FILES+=("$keyring_backup")
        cp -a "$keyring_dir/." "$keyring_backup/"
        info "Keyring backed up to ${keyring_backup}"
    fi

    pkg_full_upgrade
    pkg_autoremove
    pkg_clean

    if [[ -n "$keyring_backup" ]]; then
        local restored=false
        for backed_up_file in "$keyring_backup"/*; do
            local filename
            filename=$(basename "$backed_up_file")
            local live_file="${keyring_dir}/${filename}"
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

# --- System Updates ---
setup_system_updates() {
    info "Running system updates..."
    pkg_full_upgrade
    pkg_autoremove
    pkg_clean
    info "System updates completed."
    return 0
}

# --- KDE Desktop ---
check_kde() {
    command -v plasmashell &>/dev/null || \
        pkg_check_installed plasma-desktop || \
        pkg_check_installed kde-plasma-desktop || \
        pkg_check_installed kde-full || \
        pkg_check_installed plasma-meta
}

get_version_kde() {
    # Try plasmashell first
    local version
    version=$(plasmashell --version 2>/dev/null | grep -oP 'plasmashell \K[0-9.]+' | head -1)
    if [[ -n "$version" ]]; then
        echo "$version"
    else
        # Fallback: try to get version from package manager
        pkg_get_version plasma-desktop 2>/dev/null || pkg_get_version kde-plasma-desktop 2>/dev/null || echo ""
    fi
}

install_kde() {
    setup_install_kde
}

uninstall_kde() {
    echo "Uninstalling KDE Desktop..."
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
    echo "KDE Desktop uninstalled. You may need to install another desktop environment."
}

update_kde() {
    echo "Updating KDE Desktop..."
    case "$DISTRO_FAMILY" in
        debian)
            sudo apt update
            sudo apt upgrade -y kde-full plasma-desktop
            ;;
        fedora|rhel)
            if ! sudo "$PKG_MGR" group update -y @kde-desktop-environment 2>/dev/null && \
               ! sudo "$PKG_MGR" group update -y 'KDE Plasma Workspaces' 2>/dev/null; then
                # Fallback: update individual packages if group update fails
                echo "Group update not available, updating individual KDE packages..."
                sudo "$PKG_MGR" upgrade -y plasma-desktop plasma-workspace sddm \
                    plasma-nm plasma-pa plasma-systemmonitor kdeplasma-addons \
                    bluedevil breeze-gtk kscreen kinfocenter kwrited \
                    konsole dolphin kate ark gwenview okular spectacle \
                    kde-settings-plasma kde-gtk-config xdg-desktop-portal-kde
            fi
            ;;
        arch)
            sudo pacman -Syu --noconfirm plasma-meta kde-applications-meta
            ;;
        suse)
            sudo zypper update -y -t pattern kde kde_plasma
            ;;
    esac
}

setup_install_kde() {
    info "Installing KDE Desktop..."
    ensure_tools

    case "$PKG_MGR" in
        apt)
            run_as_root "apt-get update"
            info "Installing KDE Full Desktop Environment..."
            run_as_root "apt-get install -y kde-full sddm" || {
                error "Failed to install KDE Full Desktop Environment"
                return 1
            }
            info "Enabling display manager..."
            run_as_root "systemctl enable sddm" || warn "Failed to enable sddm"
            run_as_root "systemctl start sddm" || warn "Failed to start sddm"
            ;;

        dnf|yum)
            info "Installing KDE Full Desktop Environment..."
            if ! run_as_root "$PKG_MGR groupinstall -y 'KDE Plasma Workspaces'" 2>/dev/null && \
               ! run_as_root "$PKG_MGR group install -y @kde-desktop-environment" 2>/dev/null; then
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
            run_as_root "systemctl start sddm" || warn "Failed to start sddm"
            ;;

        zypper)
            info "Installing KDE Full Desktop Environment..."
            run_as_root "zypper install -y -t pattern kde kde_plasma kde_utilities kde_imaging kde_multimedia kde_office kde_games" || {
                error "Failed to install KDE Full Desktop Environment"
                return 1
            }
            info "Enabling display manager..."
            run_as_root "systemctl enable sddm" || run_as_root "systemctl set-default graphical.target"
            run_as_root "systemctl start sddm" || warn "Failed to start sddm"
            ;;

        pacman)
            info "Installing KDE Full Desktop Environment..."
            run_as_root "pacman -S --noconfirm plasma-meta kde-applications-meta sddm" || {
                error "Failed to install KDE Full Desktop Environment"
                return 1
            }
            info "Enabling display manager..."
            run_as_root "systemctl enable sddm"
            run_as_root "systemctl start sddm" || warn "Failed to start sddm"
            ;;

        *)
            error "KDE installation not fully supported for ${DISTRO_ID}"
            return 1
            ;;
    esac

    info "KDE Desktop installed successfully. Reboot to start using KDE."
    return 0
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
    # Try multiple config paths (Fedora may use different location)
    local pkg_json
    for pkg_json in "$HOME/.config/joplin-desktop/package.json" "$HOME/.config/joplin/package.json"; do
        if [[ -f "$pkg_json" ]]; then
            local version
            version=$(grep -oP '"version"\s*:\s*"\K[^"]+' "$pkg_json" 2>/dev/null)
            [[ -n "$version" ]] && echo "$version" && return 0
        fi
    done

    # Fallback: try to extract version from Joplin AppImage if it exists
    if [[ -f ~/.joplin/Joplin.AppImage ]]; then
        # Use the file modification time as a fallback (not ideal but better than nothing)
        file ~/.joplin/Joplin.AppImage 2>/dev/null | grep -oE 'ELF' >/dev/null && echo "installed" && return 0
    fi

    echo ""
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
_libreoffice_install_from_site() {
    # Download and install LibreOffice .deb packages directly from the official site.
    # Usage: _libreoffice_install_from_site
    ensure_tools
    local lo_version arch_dir arch_file tmp_dir
    lo_version=$(wget -qO- "https://download.documentfoundation.org/libreoffice/stable/" \
        | grep -oP 'href="\K[0-9]+\.[0-9]+\.[0-9]+' | sort -V | tail -1)
    if [[ -z "$lo_version" ]]; then
        echo "Error: Could not determine latest LibreOffice version."
        return 1
    fi
    echo "Latest LibreOffice version: $lo_version"
    case "$(uname -m)" in
        x86_64)  arch_dir="x86_64"; arch_file="x86-64" ;;
        aarch64) arch_dir="aarch64"; arch_file="aarch64" ;;
        *)
            echo "Error: Unsupported architecture $(uname -m) for direct download."
            return 1
            ;;
    esac
    local url="https://download.documentfoundation.org/libreoffice/stable/${lo_version}/deb/${arch_dir}/LibreOffice_${lo_version}_Linux_${arch_file}_deb.tar.gz"
    tmp_dir=$(mktemp -d /tmp/libreoffice-install-XXXXXX)
    CLEANUP_FILES+=("$tmp_dir")
    echo "Downloading LibreOffice ${lo_version}..."
    if ! wget -q --show-progress -O "$tmp_dir/libreoffice.tar.gz" "$url"; then
        echo "Error: Failed to download LibreOffice from $url"
        rm -rf "$tmp_dir"
        return 1
    fi
    echo "Extracting..."
    tar -xzf "$tmp_dir/libreoffice.tar.gz" -C "$tmp_dir"
    local deb_dir
    deb_dir=$(find "$tmp_dir" -type d -name "DEBS" | head -1)
    if [[ -z "$deb_dir" ]]; then
        echo "Error: Could not find DEBS directory in archive."
        rm -rf "$tmp_dir"
        return 1
    fi
    echo "Installing .deb packages..."
    if ! sudo dpkg -i "$deb_dir"/*.deb; then
        sudo apt-get install -f -y || true
        if ! sudo dpkg -i "$deb_dir"/*.deb; then
            echo "Error: Failed to install LibreOffice .deb packages."
            rm -rf "$tmp_dir"
            return 1
        fi
    fi
    rm -rf "$tmp_dir"
    echo "LibreOffice ${lo_version} installed successfully."
}
install_libreoffice() {
    echo "Installing LibreOffice..."
    case "$DISTRO_FAMILY" in
        debian)
            _libreoffice_install_from_site
            ;;
        fedora|rhel)
            sudo "$PKG_MGR" check-update >/dev/null 2>&1 || true
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
            _libreoffice_install_from_site
            ;;
        fedora|rhel)
            # Check if libreoffice is installed, if not install it instead of upgrading
            if pkg_check_installed libreoffice; then
                sudo "$PKG_MGR" upgrade -y libreoffice
            else
                install_libreoffice
            fi
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
                    sudo flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
                fi
                sudo flatpak install -y flathub com.termius.Termius
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
    if pkg_check_installed RemoteDesktopManager; then
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
    # Try to extract version from timeshift --version output
    local version
    version=$(timeshift --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -1)
    if [[ -n "$version" ]]; then
        echo "$version"
    else
        # Fallback: try package manager
        pkg_get_version timeshift 2>/dev/null || echo ""
    fi
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

# --- PIA VPN ---

check_pia_vpn() {
    command -v piactl &>/dev/null || pkg_check_installed privateinternetaccess
}

install_pia_vpn() {
    echo "Installing PIA VPN..."
    ensure_tools
    case "$DISTRO_FAMILY" in
        debian)
            # Add PIA repository key and install
            sudo curl -fsSL https://repo.privateinternetaccess.com/debian/key/deb.gpg.key | sudo apt-key add -
            echo "deb https://repo.privateinternetaccess.com/debian/deb_ubuntu jammy main" | sudo tee /etc/apt/sources.list.d/pia.list
            sudo apt update
            sudo apt install -y privateinternetaccess
            ;;
        fedora|rhel)
            # Download and install PIA VPN from official installer
            local pia_installer
            pia_installer=$(mktemp /tmp/pia-XXXXXX.run)
            if ! wget -qO "$pia_installer" "https://installers.privateinternetaccess.com/download/pia-linux-3.7-08412.run"; then
                echo "Error: Failed to download PIA VPN installer. Check network connectivity."
                rm -f "$pia_installer"
                return 1
            fi
            chmod +x "$pia_installer"
            if ! "$pia_installer" --accept --quiet; then
                echo "Error: Failed to install PIA VPN."
                rm -f "$pia_installer"
                return 1
            fi
            rm -f "$pia_installer"
            ;;
        arch)
            # Install from AUR
            if has_aur_helper; then
                aur_install privateinternetaccess-bin
            else
                echo "Installing from AUR requires an AUR helper (yay/paru). Please install one first."
                return 1
            fi
            ;;
        suse)
            # For openSUSE, try Flatpak as primary method
            if has_flatpak; then
                flatpak install -y flathub com.privateinternetaccess.PIA
            else
                echo "PIA is not available in default openSUSE repositories."
                echo "Please install Flatpak and use: flatpak install flathub com.privateinternetaccess.PIA"
                return 1
            fi
            ;;
    esac
    echo "PIA VPN installed successfully."
}

uninstall_pia_vpn() {
    echo "Uninstalling PIA VPN..."
    case "$DISTRO_FAMILY" in
        debian)
            sudo apt remove -y privateinternetaccess
            sudo rm -f /etc/apt/sources.list.d/pia.list
            ;;
        fedora|rhel)
            sudo "$PKG_MGR" remove -y privateinternetaccess
            ;;
        arch)
            sudo pacman -Rs --noconfirm privateinternetaccess-bin 2>/dev/null || \
            sudo pacman -Rs --noconfirm privateinternetaccess 2>/dev/null || true
            ;;
        suse)
            flatpak uninstall -y com.privateinternetaccess.PIA 2>/dev/null || true
            ;;
    esac
    echo "PIA VPN has been uninstalled."
}

update_pia_vpn() {
    echo "Updating PIA VPN..."
    case "$DISTRO_FAMILY" in
        debian)
            sudo apt update
            sudo apt upgrade -y privateinternetaccess
            ;;
        fedora|rhel)
            # Update PIA VPN from official installer
            local pia_installer
            pia_installer=$(mktemp /tmp/pia-XXXXXX.run)
            if wget -qO "$pia_installer" "https://installers.privateinternetaccess.com/download/pia-linux-3.7-08412.run"; then
                chmod +x "$pia_installer"
                "$pia_installer" --accept --quiet
            fi
            rm -f "$pia_installer"
            ;;
        arch)
            sudo pacman -S --noconfirm privateinternetaccess-bin 2>/dev/null || \
            sudo pacman -S --noconfirm privateinternetaccess 2>/dev/null || true
            ;;
        suse)
            flatpak update -y com.privateinternetaccess.PIA 2>/dev/null || true
            ;;
    esac
}

get_version_pia_vpn() {
    piactl --version 2>/dev/null || echo ""
}

# --- QBittorrent ---
check_qbittorrent() {
    command -v qbittorrent &>/dev/null || pkg_check_installed qbittorrent
}

install_qbittorrent() {
    echo "Installing QBittorrent..."
    ensure_tools
    case "$DISTRO_FAMILY" in
        debian)
            sudo apt update
            sudo apt install -y qbittorrent
            ;;
        fedora|rhel)
            sudo "$PKG_MGR" install -y qbittorrent
            ;;
        arch)
            sudo pacman -S -y qbittorrent
            ;;
        suse)
            if has_flatpak; then
                flatpak install -y flathub org.qbittorrent.qBittorrent
            else
                sudo zypper install -y qbittorrent
            fi
            ;;
    esac
    echo "QBittorrent installed successfully."
}

uninstall_qbittorrent() {
    echo "Uninstalling QBittorrent..."
    case "$DISTRO_FAMILY" in
        debian)
            sudo apt remove -y qbittorrent
            ;;
        fedora|rhel)
            sudo "$PKG_MGR" remove -y qbittorrent
            ;;
        arch)
            sudo pacman -Rs --noconfirm qbittorrent 2>/dev/null || true
            ;;
        suse)
            flatpak uninstall -y org.qbittorrent.qBittorrent 2>/dev/null || \
            sudo zypper remove -y qbittorrent 2>/dev/null || true
            ;;
    esac
    echo "QBittorrent has been uninstalled."
}

update_qbittorrent() {
    echo "Updating QBittorrent..."
    case "$DISTRO_FAMILY" in
        debian)
            sudo apt update
            sudo apt upgrade -y qbittorrent
            ;;
        fedora|rhel)
            sudo "$PKG_MGR" upgrade -y qbittorrent
            ;;
        arch)
            sudo pacman -S --noconfirm qbittorrent
            ;;
        suse)
            flatpak update -y org.qbittorrent.qBittorrent 2>/dev/null || \
            sudo zypper update -y qbittorrent 2>/dev/null || true
            ;;
    esac
}

get_version_qbittorrent() {
    pkg_get_version qbittorrent | sed 's/^[0-9]*://; s/~.*//' || echo ""
}

# --- Docker (utility version) ---
setup_install_docker() {
    info "Installing Docker..."
    ensure_tools

    case "$PKG_MGR" in
        apt)
            run_as_root "apt-get update"
            run_as_root "apt-get install -y apt-transport-https ca-certificates curl gnupg"

            if [[ "$DISTRO_ID" == "ubuntu" || "$DISTRO_ID" == "linuxmint" || "$DISTRO_ID" == "pop" || "$DISTRO_ID" == "neon" ]]; then
                run_as_root "apt-get install -y software-properties-common"
            fi

            local docker_dist="$DISTRO_ID"
            local docker_codename="${DISTRO_VERSION_CODENAME:-stable}"
            if [[ "$DISTRO_ID" == "linuxmint" || "$DISTRO_ID" == "pop" || "$DISTRO_ID" == "neon" ]]; then
                docker_dist="ubuntu"
                if [[ "$DISTRO_ID" == "neon" && -z "$docker_codename" ]] || [[ "$DISTRO_ID" == "neon" ]]; then
                    if [[ -f /etc/upstream-release/lsb-release ]]; then
                        docker_codename=$(grep -oP '(?<=DISTRIB_CODENAME=).+' /etc/upstream-release/lsb-release)
                    fi
                    docker_codename="${docker_codename:-noble}"
                fi
            fi

            run_as_root "curl -fsSL https://download.docker.com/linux/${docker_dist}/gpg | gpg --yes --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg"
            run_as_root "chmod 644 /usr/share/keyrings/docker-archive-keyring.gpg"
            echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/${docker_dist} ${docker_codename} stable" | \
                sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
            run_as_root "apt-get update"
            run_as_root "apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin"
            ;;

        dnf|yum)
            run_as_root "$PKG_MGR install -y dnf-plugins-core 2>/dev/null || $PKG_MGR install -y yum-utils"

            local docker_repo
            [[ "$DISTRO_ID" == "fedora" ]] && docker_repo="https://download.docker.com/linux/fedora/docker-ce.repo" || docker_repo="https://download.docker.com/linux/centos/docker-ce.repo"

            run_as_root "curl -fsSLo /etc/yum.repos.d/docker-ce.repo ${docker_repo}"
            run_as_root "$PKG_MGR install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin"
            run_as_root "systemctl start docker"
            run_as_root "systemctl enable docker"
            ;;

        zypper)
            run_as_root "zypper install -y docker docker-compose"
            run_as_root "systemctl start docker"
            run_as_root "systemctl enable docker"
            ;;

        pacman)
            run_as_root "pacman -S --noconfirm docker docker-compose docker-buildx"
            run_as_root "systemctl enable --now containerd.service"
            run_as_root "systemctl enable --now docker.service"
            ;;

        *)
            error "Docker installation not fully supported for ${DISTRO_ID}"
            return 1
            ;;
    esac

    run_as_root "groupadd docker 2>/dev/null || true"
    run_as_root "usermod -aG docker ${USER}"

    info "Docker installed successfully. You may need to log out and back in for group membership to take effect."

    sudo docker version &>/dev/null && info "Docker verification complete."

    return 0
}

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
            sudo rm -f /usr/share/keyrings/docker-archive-keyring.gpg
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
# COLUMN LAYOUT MATH (2-column format, do not modify):
# ├─ system_rows_per_column = ceil(system_tasks / 2)
# │  Example: 5 tasks → (5+1)/2 = 3 rows per column
# │  Result: [left column rows 0-2, right column rows 0-2, some empty]
# │
# ├─ rows_per_column = ceil(utilities_count / 2)
# │  Example: 14 utils → (14+1)/2 = 7 rows per column
# │  Result: [left column 0-6, right column 0-6]
# │
# ├─ Rendering order (top-down, then next column):
# │  LEFT column:  index 0, 1, 2, ...
# │  RIGHT column: index rows_per_column, rows_per_column+1, ...
# │
# └─ Item position calculation: idx = col * rows_per_column + row
#    LEFT (col=0):  0, 1, 2, 3...  RIGHT (col=1): 7, 8, 9...
draw_menu() {
    local total=${#UTILITIES[@]}
    local system_tasks=$SYSTEM_TASK_COUNT
    local utilities_start=$system_tasks
    local utilities_count=$((total - system_tasks))

    # Force 2 columns by calculating rows needed
    local system_rows_per_column=$(( (system_tasks + 1) / 2 ))  # ceil(system_tasks / 2) for 2 columns
    local rows_per_column=$(( (utilities_count + 1) / 2 ))      # ceil(utilities_count / 2) for 2 columns

    # Always 2 columns (unless fewer items)
    local num_columns=$(( utilities_count > 0 ? 2 : 0 ))
    local system_num_columns=$(( system_tasks > 0 ? 2 : 0 ))

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
    echo "         Detected System: ${BOLD}${DISTRO_NAME}${RESET}   Version: ${BOLD}${DISTRO_VERSION_ID}${RESET}"
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
            
            # VERSION DISPLAY LOGIC:
            # ├─ If utility is installed AND has version info → "(vX.Y.Z)" in MAGENTA
            # ├─ If utility is installed but NO version info → "(installed)" in MAGENTA
            # └─ If utility not installed → no status tag displayed
            # IMPORTANT: INSTALLED_VERSIONS[$i] is populated by get_version_*() functions
            # during check_installed_utilities() (line 3220-3232)
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

            # COLUMN PADDING CALCULATION (for alignment in 2-column layout):
            # Spacing is NOT hard-coded—it's calculated based on item width.
            # util_col_width = 40 chars max per column (line 3286)
            # visible_len = actual width of: "  " + "[X]" + " " + name + " (vX.Y.Z)"
            # padding = util_col_width - visible_len (minimum 2 spaces)
            # This ensures right column aligns regardless of name/version length.
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
    # RENDERING LOGIC IDENTICAL TO SYSTEM TASKS SECTION ABOVE:
    # Loop through rows (0 to rows_per_column-1), then columns (left=0, right=1)
    # Calculate array index: utilities_start + (col * rows_per_column + row)
    # This produces left column top-to-bottom, then right column top-to-bottom
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
    local utilities_count=$(( total - sys_tasks ))

    # Force 2 columns by calculating rows needed
    local sys_rows=$(( (sys_tasks + 1) / 2 ))         # ceil(sys_tasks / 2) for 2 columns
    local util_rows=$(( (utilities_count + 1) / 2 ))  # ceil(utilities_count / 2) for 2 columns

    # Always 2 columns (unless fewer items)
    local sys_cols=$(( sys_tasks > 0 ? 2 : 0 ))
    local util_cols=$(( utilities_count > 0 ? 2 : 0 ))
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


#!/bin/bash
# Btrfs Assistant installer functions (Arch and openSUSE only)

# --- Btrfs Assistant ---

check_btrfs_assistant() {
    command -v btrfs-assistant &>/dev/null || command -v btrfs-assistant-bin &>/dev/null
}

install_btrfs_assistant() {
    echo "Installing Btrfs Assistant..."
    case "$DISTRO_FAMILY" in
        arch)
            # btrfs-assistant is in CachyOS repos; AUR on vanilla Arch
            aur_ensure btrfs-assistant || return 1
            ;;
        debian)
            sudo apt install -y btrfs-assistant || return 1
            ;;
        fedora)
            sudo "$PKG_MGR" install -y btrfs-assistant || return 1
            ;;
        suse)
            sudo zypper install -y btrfs-assistant || return 1
            ;;
        *)
            warn "Btrfs Assistant is not available for ${DISTRO_NAME}."
            warn "Supported distros: Arch/Manjaro, Debian/Ubuntu, Fedora, openSUSE."
            return 1
            ;;
    esac
    echo "Btrfs Assistant installed successfully."
}

uninstall_btrfs_assistant() {
    echo "Uninstalling Btrfs Assistant..."
    case "$DISTRO_FAMILY" in
        arch)
            sudo pacman -Rs --noconfirm btrfs-assistant 2>/dev/null || true
            ;;
        debian)
            sudo apt purge --autoremove -y btrfs-assistant
            sudo apt autoclean
            ;;
        fedora)
            sudo "$PKG_MGR" remove -y btrfs-assistant
            ;;
        suse)
            sudo zypper remove -y btrfs-assistant || true
            ;;
    esac
}

update_btrfs_assistant() {
    echo "Updating Btrfs Assistant..."
    case "$DISTRO_FAMILY" in
        arch)
            pkg_upgrade btrfs-assistant
            ;;
        debian)
            sudo apt-get install -y --only-upgrade btrfs-assistant
            ;;
        fedora)
            pkg_upgrade btrfs-assistant
            ;;
        suse)
            sudo zypper update -y btrfs-assistant || true
            ;;
    esac
}

get_version_btrfs_assistant() {
    # Do NOT use `btrfs-assistant --version`: on some builds (e.g. Ubuntu's
    # 2.2-1) the binary still iterates btrfs subvolumes via libbtrfsutil even
    # for --version and segfaults, dumping a core on every version check.
    # The package manager is the safe source.
    _ver_from_pkg btrfs-assistant || echo ""
}

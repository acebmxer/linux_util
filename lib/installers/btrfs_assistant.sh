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
        suse)
            sudo zypper install -y btrfs-assistant || return 1
            ;;
        *)
            warn "Btrfs Assistant is only supported on Arch-based and openSUSE systems."
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
        suse)
            sudo zypper update -y btrfs-assistant || true
            ;;
    esac
}

get_version_btrfs_assistant() {
    _ver_from_cmd btrfs-assistant || _ver_from_pkg btrfs-assistant || echo ""
}

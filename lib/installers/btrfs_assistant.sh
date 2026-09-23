#!/bin/bash
# Btrfs Assistant installer functions (Arch and openSUSE only)

# --- Btrfs Assistant ---

check_btrfs_assistant() {
    _have_cmd btrfs-assistant || _have_cmd btrfs-assistant-bin
}

install_btrfs_assistant() {
    echo "Installing Btrfs Assistant..."
    case "$DISTRO_FAMILY" in
        arch)
            # btrfs-assistant is in extra (and CachyOS repos); AUR only as a fallback
            repo_or_aur btrfs-assistant || return 1
            ;;
        debian)
            pkg_install btrfs-assistant || return 1
            ;;
        fedora)
            pkg_install btrfs-assistant || return 1
            ;;
        suse)
            pkg_install btrfs-assistant || return 1
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
            pkg_remove btrfs-assistant 2>/dev/null || true
            ;;
        debian)
            pkg_remove btrfs-assistant
            ;;
        fedora)
            pkg_remove btrfs-assistant
            ;;
        suse)
            pkg_remove btrfs-assistant || true
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
            pkg_upgrade btrfs-assistant || true
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

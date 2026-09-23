#!/bin/bash
# btrfsmaintenance installer functions (Arch, Debian/Ubuntu, Fedora, openSUSE)

# --- btrfsmaintenance ---

check_btrfsmaintenance() {
    _check_standard btrfsmaintenance btrfsmaintenance ""
}

install_btrfsmaintenance() {
    echo "Installing btrfsmaintenance..."
    case "$DISTRO_FAMILY" in
        arch)
            pkg_install btrfsmaintenance || return 1
            ;;
        debian)
            pkg_install btrfsmaintenance || return 1
            ;;
        fedora)
            pkg_install btrfsmaintenance || return 1
            ;;
        suse)
            pkg_install btrfsmaintenance || return 1
            ;;
        *)
            warn "btrfsmaintenance is not available for ${DISTRO_NAME}."
            warn "Supported distros: Arch/Manjaro, Debian/Ubuntu, Fedora, openSUSE."
            return 1
            ;;
    esac
    echo "btrfsmaintenance installed successfully."
    echo "Edit /etc/btrfsmaintenance/btrfsmaintenance.conf to configure scrub, balance, and trim schedules."
}

uninstall_btrfsmaintenance() {
    echo "Uninstalling btrfsmaintenance..."
    case "$DISTRO_FAMILY" in
        arch)
            pkg_remove btrfsmaintenance 2>/dev/null || true
            ;;
        debian)
            pkg_remove btrfsmaintenance
            ;;
        fedora)
            pkg_remove btrfsmaintenance
            ;;
        suse)
            pkg_remove btrfsmaintenance || true
            ;;
    esac
}

update_btrfsmaintenance() {
    echo "Updating btrfsmaintenance..."
    case "$DISTRO_FAMILY" in
        arch)
            pkg_upgrade btrfsmaintenance
            ;;
        debian)
            sudo apt-get install -y --only-upgrade btrfsmaintenance
            ;;
        fedora)
            pkg_upgrade btrfsmaintenance
            ;;
        suse)
            pkg_upgrade btrfsmaintenance || true
            ;;
    esac
}

get_version_btrfsmaintenance() {
    _ver_from_pkg btrfsmaintenance || echo ""
}

#!/bin/bash
# duperemove installer functions (Arch, Debian/Ubuntu, Fedora)

# --- duperemove ---

check_duperemove() {
    _check_standard duperemove duperemove ""
}

install_duperemove() {
    echo "Installing duperemove..."
    case "$DISTRO_FAMILY" in
        arch)
            pkg_install duperemove || return 1
            ;;
        debian)
            pkg_install duperemove || return 1
            ;;
        fedora)
            pkg_install duperemove || return 1
            ;;
        *)
            warn "duperemove is not available for ${DISTRO_NAME}."
            warn "Supported distros: Arch/Manjaro, Debian/Ubuntu, Fedora."
            return 1
            ;;
    esac
    echo "duperemove installed successfully."
}

uninstall_duperemove() {
    echo "Uninstalling duperemove..."
    case "$DISTRO_FAMILY" in
        arch)
            pkg_remove duperemove 2>/dev/null || true
            ;;
        debian)
            pkg_remove duperemove
            ;;
        fedora)
            pkg_remove duperemove
            ;;
    esac
}

update_duperemove() {
    echo "Updating duperemove..."
    case "$DISTRO_FAMILY" in
        arch)
            pkg_upgrade duperemove
            ;;
        debian)
            sudo apt-get install -y --only-upgrade duperemove
            ;;
        fedora)
            pkg_upgrade duperemove
            ;;
    esac
}

get_version_duperemove() {
    _ver_from_cmd duperemove || _ver_from_pkg duperemove || echo ""
}

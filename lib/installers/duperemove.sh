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
            sudo apt install -y duperemove || return 1
            ;;
        fedora)
            sudo "$PKG_MGR" install -y duperemove || return 1
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
            sudo pacman -Rs --noconfirm duperemove 2>/dev/null || true
            ;;
        debian)
            sudo apt purge --autoremove -y duperemove
            sudo apt autoclean
            ;;
        fedora)
            sudo "$PKG_MGR" remove -y duperemove
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

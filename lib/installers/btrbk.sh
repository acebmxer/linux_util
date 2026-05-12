#!/bin/bash
# btrbk installer functions (Arch, Debian/Ubuntu, Fedora)

# --- btrbk ---

check_btrbk() {
    _check_standard btrbk btrbk ""
}

install_btrbk() {
    echo "Installing btrbk..."
    case "$DISTRO_FAMILY" in
        arch)
            pkg_install btrbk || return 1
            ;;
        debian)
            sudo apt install -y btrbk || return 1
            ;;
        fedora)
            sudo "$PKG_MGR" install -y btrbk || return 1
            ;;
        *)
            warn "btrbk is not available for ${DISTRO_NAME}."
            warn "Supported distros: Arch/Manjaro, Debian/Ubuntu, Fedora."
            return 1
            ;;
    esac
    echo "btrbk installed successfully."
    echo "Create /etc/btrbk/btrbk.conf to configure snapshot and backup targets."
    echo "See: man btrbk.conf  or  /usr/share/doc/btrbk/examples/"
}

uninstall_btrbk() {
    echo "Uninstalling btrbk..."
    case "$DISTRO_FAMILY" in
        arch)
            sudo pacman -Rs --noconfirm btrbk 2>/dev/null || true
            ;;
        debian)
            sudo apt purge --autoremove -y btrbk
            sudo apt autoclean
            ;;
        fedora)
            sudo "$PKG_MGR" remove -y btrbk
            ;;
    esac
}

update_btrbk() {
    echo "Updating btrbk..."
    case "$DISTRO_FAMILY" in
        arch)
            pkg_upgrade btrbk
            ;;
        debian)
            sudo apt-get install -y --only-upgrade btrbk
            ;;
        fedora)
            pkg_upgrade btrbk
            ;;
    esac
}

get_version_btrbk() {
    _ver_from_cmd btrbk || _ver_from_pkg btrbk || echo ""
}

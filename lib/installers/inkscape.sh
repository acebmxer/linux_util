#!/bin/bash
# Inkscape vector graphics editor installer functions

# --- Inkscape ---

check_inkscape() { _check_standard inkscape inkscape org.inkscape.Inkscape; }

install_inkscape() {
    info "Installing Inkscape..."
    ensure_tools
    case "$DISTRO_FAMILY" in
        debian)
            pkg_install inkscape
            ;;
        fedora)
            pkg_install inkscape
            ;;
        rhel)
            pkg_install epel-release 2>/dev/null || true
            pkg_install inkscape 2>/dev/null || {
                warn "inkscape not in repos. Falling back to Flatpak..."
                if has_flatpak; then
                    sudo flatpak install -y flathub org.inkscape.Inkscape
                    return $?
                fi
                error "Inkscape requires Flatpak on this RHEL-based system."
                return 1
            }
            ;;
        arch)
            pkg_install inkscape
            ;;
        suse)
            pkg_install inkscape
            ;;
    esac
    info "Inkscape installed."
}

uninstall_inkscape() {
    info "Uninstalling Inkscape..."
    if flatpak_is_installed "org.inkscape.Inkscape"; then
        flatpak uninstall -y --user org.inkscape.Inkscape 2>/dev/null || \
            sudo flatpak uninstall -y --system org.inkscape.Inkscape
    else
        case "$DISTRO_FAMILY" in
            debian)      pkg_remove inkscape ;;
            fedora|rhel) pkg_remove inkscape ;;
            arch)        pkg_remove inkscape ;;
            suse)        pkg_remove inkscape ;;
        esac
    fi
    rm -rf "$HOME/.config/inkscape"
}

update_inkscape() {
    info "Updating Inkscape..."
    if flatpak_is_installed "org.inkscape.Inkscape"; then
        flatpak update -y --user org.inkscape.Inkscape 2>/dev/null || \
            sudo flatpak update -y --system org.inkscape.Inkscape
    else
        case "$DISTRO_FAMILY" in
            debian)      sudo apt-get install -y --only-upgrade inkscape ;;
            fedora|rhel) pkg_upgrade inkscape ;;
            arch)        pkg_upgrade inkscape ;;
            suse)        pkg_upgrade inkscape ;;
        esac
    fi
}

get_version_inkscape() {
    _ver_from_cmd inkscape || _ver_from_flatpak org.inkscape.Inkscape || _ver_from_pkg inkscape || echo ""
}

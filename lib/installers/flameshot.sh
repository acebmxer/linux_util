#!/bin/bash
# Flameshot screenshot tool installer functions

# --- Flameshot ---

check_flameshot() { _check_standard flameshot flameshot org.flameshot.Flameshot; }

install_flameshot() {
    info "Installing Flameshot..."
    ensure_tools
    case "$DISTRO_FAMILY" in
        debian)
            pkg_install flameshot
            ;;
        fedora)
            pkg_install flameshot
            ;;
        rhel)
            pkg_install epel-release 2>/dev/null || true
            pkg_install flameshot 2>/dev/null || {
                warn "flameshot not in repos. Falling back to Flatpak..."
                if has_flatpak; then
                    sudo flatpak install -y flathub org.flameshot.Flameshot
                    return $?
                fi
                error "Flameshot requires Flatpak on this RHEL-based system."
                return 1
            }
            ;;
        arch)
            pkg_install flameshot
            ;;
        suse)
            pkg_install flameshot
            ;;
    esac
    info "Flameshot installed."
    info "Tip: Bind 'flameshot gui' to a keyboard shortcut (e.g. Print Screen) for quick captures."
}

uninstall_flameshot() {
    info "Uninstalling Flameshot..."
    if flatpak_is_installed "org.flameshot.Flameshot"; then
        flatpak uninstall -y --user org.flameshot.Flameshot 2>/dev/null || \
            sudo flatpak uninstall -y --system org.flameshot.Flameshot
    else
        case "$DISTRO_FAMILY" in
            debian)      pkg_remove flameshot ;;
            fedora|rhel) pkg_remove flameshot ;;
            arch)        pkg_remove flameshot ;;
            suse)        pkg_remove flameshot ;;
        esac
    fi
    rm -rf "$HOME/.config/flameshot"
}

update_flameshot() {
    info "Updating Flameshot..."
    if flatpak_is_installed "org.flameshot.Flameshot"; then
        flatpak update -y --user org.flameshot.Flameshot 2>/dev/null || \
            sudo flatpak update -y --system org.flameshot.Flameshot
    else
        case "$DISTRO_FAMILY" in
            debian)      sudo apt-get install -y --only-upgrade flameshot ;;
            fedora|rhel) pkg_upgrade flameshot ;;
            arch)        pkg_upgrade flameshot ;;
            suse)        pkg_upgrade flameshot ;;
        esac
    fi
}

get_version_flameshot() {
    _ver_from_cmd flameshot --version 2>/dev/null | grep -oP '[0-9]+\.[0-9]+\.[0-9]+' || \
        _ver_from_flatpak org.flameshot.Flameshot || _ver_from_pkg flameshot || echo ""
}

#!/bin/bash
# Audacity audio editor installer functions

# --- Audacity ---

check_audacity() { _check_standard audacity audacity org.audacityteam.Audacity; }

install_audacity() {
    info "Installing Audacity..."
    ensure_tools
    case "$DISTRO_FAMILY" in
        debian)
            pkg_install audacity
            ;;
        fedora)
            pkg_install audacity
            ;;
        rhel)
            pkg_install epel-release 2>/dev/null || true
            pkg_install audacity 2>/dev/null || {
                warn "audacity not in repos. Falling back to Flatpak..."
                if has_flatpak; then
                    sudo flatpak install -y flathub org.audacityteam.Audacity
                    return $?
                fi
                error "Audacity requires Flatpak on this RHEL-based system."
                return 1
            }
            ;;
        arch)
            pkg_install audacity
            ;;
        suse)
            pkg_install audacity 2>/dev/null || {
                if has_flatpak; then
                    sudo flatpak install -y flathub org.audacityteam.Audacity
                else
                    error "Audacity requires Flatpak on this openSUSE system."
                    return 1
                fi
            }
            ;;
    esac
    info "Audacity installed."
}

uninstall_audacity() {
    info "Uninstalling Audacity..."
    if flatpak_is_installed "org.audacityteam.Audacity"; then
        flatpak uninstall -y --user org.audacityteam.Audacity 2>/dev/null || \
            sudo flatpak uninstall -y --system org.audacityteam.Audacity
    else
        case "$DISTRO_FAMILY" in
            debian)      pkg_remove audacity ;;
            fedora|rhel) pkg_remove audacity ;;
            arch)        pkg_remove audacity ;;
            suse)        pkg_remove audacity ;;
        esac
    fi
    rm -rf "$HOME/.config/audacity"
}

update_audacity() {
    info "Updating Audacity..."
    if flatpak_is_installed "org.audacityteam.Audacity"; then
        flatpak update -y --user org.audacityteam.Audacity 2>/dev/null || \
            sudo flatpak update -y --system org.audacityteam.Audacity
    else
        case "$DISTRO_FAMILY" in
            debian)      sudo apt-get install -y --only-upgrade audacity ;;
            fedora|rhel) pkg_upgrade audacity ;;
            arch)        pkg_upgrade audacity ;;
            suse)        pkg_upgrade audacity ;;
        esac
    fi
}

get_version_audacity() {
    _ver_from_cmd audacity || _ver_from_flatpak org.audacityteam.Audacity || _ver_from_pkg audacity || echo ""
}

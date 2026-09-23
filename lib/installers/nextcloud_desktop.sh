#!/bin/bash
# Nextcloud Desktop Client installer functions

# --- Nextcloud Desktop ---

check_nextcloud_desktop() {
    _check_standard nextcloud nextcloud-desktop com.nextcloud.desktopclient.nextcloud || \
        pkg_check_installed nextcloud-client
}

install_nextcloud_desktop() {
    info "Installing Nextcloud Desktop Client..."
    ensure_tools
    case "$DISTRO_FAMILY" in
        debian)
            pkg_install nextcloud-desktop
            ;;
        fedora)
            pkg_install nextcloud-client nextcloud-client-nautilus 2>/dev/null || pkg_install nextcloud-client
            ;;
        rhel)
            pkg_install epel-release 2>/dev/null || true
            pkg_install nextcloud-client 2>/dev/null || {
                warn "nextcloud-client not in repos. Falling back to Flatpak..."
                if has_flatpak; then
                    sudo flatpak install -y flathub com.nextcloud.desktopclient.nextcloud
                    return $?
                fi
                error "Nextcloud Desktop requires Flatpak on this system."
                return 1
            }
            ;;
        arch)
            pkg_install nextcloud-client
            ;;
        suse)
            pkg_install nextcloud-client 2>/dev/null || {
                if has_flatpak; then
                    sudo flatpak install -y flathub com.nextcloud.desktopclient.nextcloud
                else
                    error "Nextcloud Desktop requires Flatpak on this openSUSE system."
                    return 1
                fi
            }
            ;;
    esac
    info "Nextcloud Desktop Client installed."
}

uninstall_nextcloud_desktop() {
    info "Uninstalling Nextcloud Desktop Client..."
    if flatpak_is_installed "com.nextcloud.desktopclient.nextcloud"; then
        flatpak uninstall -y --user com.nextcloud.desktopclient.nextcloud 2>/dev/null || \
            sudo flatpak uninstall -y --system com.nextcloud.desktopclient.nextcloud
    else
        case "$DISTRO_FAMILY" in
            debian)  pkg_remove nextcloud-desktop ;;
            fedora|rhel) pkg_remove nextcloud-client ;;
            arch)    pkg_remove nextcloud-client ;;
            suse)    pkg_remove nextcloud-client ;;
        esac
    fi
    rm -rf "$HOME/.config/Nextcloud"
    rm -rf "$HOME/.local/share/Nextcloud"
}

update_nextcloud_desktop() {
    info "Updating Nextcloud Desktop Client..."
    if flatpak_is_installed "com.nextcloud.desktopclient.nextcloud"; then
        flatpak update -y --user com.nextcloud.desktopclient.nextcloud 2>/dev/null || \
            sudo flatpak update -y --system com.nextcloud.desktopclient.nextcloud
    else
        case "$DISTRO_FAMILY" in
            debian)  sudo apt-get install -y --only-upgrade nextcloud-desktop ;;
            fedora|rhel) pkg_upgrade nextcloud-client ;;
            arch)    pkg_upgrade nextcloud-client ;;
            suse)    pkg_upgrade nextcloud-client ;;
        esac
    fi
}

get_version_nextcloud_desktop() {
    # Do NOT call nextcloud --version — Qt GUI apps may launch a full window.
    _ver_from_pkg nextcloud-desktop || _ver_from_pkg nextcloud-client || \
    _ver_from_flatpak com.nextcloud.desktopclient || echo ""
}

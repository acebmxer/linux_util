#!/bin/bash
# Nextcloud Desktop Client installer functions

# --- Nextcloud Desktop ---

check_nextcloud_desktop() {
    command -v nextcloud &>/dev/null || \
        pkg_check_installed nextcloud-desktop || \
        pkg_check_installed nextcloud-client || \
        (has_flatpak && flatpak list 2>/dev/null | grep -qi "com.nextcloud.desktopclient.nextcloud")
}

install_nextcloud_desktop() {
    info "Installing Nextcloud Desktop Client..."
    ensure_tools
    case "$DISTRO_FAMILY" in
        debian)
            sudo apt install -y nextcloud-desktop
            ;;
        fedora)
            sudo "$PKG_MGR" install -y nextcloud-client nextcloud-client-nautilus 2>/dev/null || \
                sudo "$PKG_MGR" install -y nextcloud-client
            ;;
        rhel)
            sudo "$PKG_MGR" install -y epel-release 2>/dev/null || true
            sudo "$PKG_MGR" install -y nextcloud-client 2>/dev/null || {
                warn "nextcloud-client not in repos. Falling back to Flatpak..."
                if has_flatpak; then
                    flatpak install -y flathub com.nextcloud.desktopclient.nextcloud
                    return $?
                fi
                error "Nextcloud Desktop requires Flatpak on this system."
                return 1
            }
            ;;
        arch)
            sudo pacman -S --noconfirm nextcloud-client
            ;;
        suse)
            sudo zypper install -y nextcloud-client 2>/dev/null || {
                if has_flatpak; then
                    flatpak install -y flathub com.nextcloud.desktopclient.nextcloud
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
    if has_flatpak && flatpak list 2>/dev/null | grep -qi "com.nextcloud.desktopclient.nextcloud"; then
        flatpak uninstall -y com.nextcloud.desktopclient.nextcloud
    else
        case "$DISTRO_FAMILY" in
            debian)  sudo apt purge --autoremove -y nextcloud-desktop ;;
            fedora|rhel) sudo "$PKG_MGR" remove -y nextcloud-client ;;
            arch)    sudo pacman -Rs --noconfirm nextcloud-client ;;
            suse)    sudo zypper remove -y nextcloud-client ;;
        esac
    fi
    rm -rf "$HOME/.config/Nextcloud"
    rm -rf "$HOME/.local/share/Nextcloud"
}

update_nextcloud_desktop() {
    info "Updating Nextcloud Desktop Client..."
    if has_flatpak && flatpak list 2>/dev/null | grep -qi "com.nextcloud.desktopclient.nextcloud"; then
        flatpak update -y com.nextcloud.desktopclient.nextcloud
    else
        case "$DISTRO_FAMILY" in
            debian)  sudo apt update && sudo apt upgrade -y nextcloud-desktop ;;
            fedora|rhel) sudo "$PKG_MGR" upgrade -y nextcloud-client ;;
            arch)    sudo pacman -S --noconfirm nextcloud-client ;;
            suse)    sudo zypper update -y nextcloud-client ;;
        esac
    fi
}

get_version_nextcloud_desktop() {
    nextcloud --version 2>/dev/null | grep -oP '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || \
    (has_flatpak && flatpak list 2>/dev/null | grep -i "com.nextcloud.desktopclient" | awk -F'\t' '{print $3}') || \
    pkg_get_version nextcloud-desktop 2>/dev/null | sed 's/-.*//' || \
    pkg_get_version nextcloud-client 2>/dev/null | sed 's/-.*//' || \
    echo ""
}

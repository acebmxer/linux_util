#!/bin/bash
# Element Matrix client installer functions

# --- Element ---

check_element() { _check_standard element-desktop element-desktop im.riot.Riot; }

install_element() {
    info "Installing Element (Matrix client)..."
    ensure_tools
    case "$DISTRO_FAMILY" in
        debian)
            # Official Element apt repository
            sudo mkdir -p /etc/apt/keyrings
            curl -fsSL https://packages.element.io/debian/element-io-archive-keyring.gpg | \
                sudo tee /etc/apt/keyrings/element-io-archive-keyring.gpg > /dev/null
            echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/element-io-archive-keyring.gpg] https://packages.element.io/debian/ default main" | \
                sudo tee /etc/apt/sources.list.d/element-io.list > /dev/null
            sudo apt update
            sudo apt install -y element-desktop
            ;;
        fedora|rhel)
            if has_flatpak; then
                sudo flatpak install -y flathub im.riot.Riot
            else
                error "Element requires Flatpak on this system. Install Flatpak first."
                return 1
            fi
            ;;
        arch)
            repo_or_aur element-desktop
            ;;
        suse)
            if has_flatpak; then
                sudo flatpak install -y flathub im.riot.Riot
            else
                error "Element requires Flatpak on this openSUSE system. Install Flatpak first."
                return 1
            fi
            ;;
    esac
    info "Element installed."
}

uninstall_element() {
    info "Uninstalling Element..."
    if flatpak_is_installed "im.riot.Riot"; then
        flatpak uninstall -y --user im.riot.Riot 2>/dev/null || \
            sudo flatpak uninstall -y --system im.riot.Riot
    else
        case "$DISTRO_FAMILY" in
            debian)
                sudo apt purge --autoremove -y element-desktop
                sudo rm -f /etc/apt/sources.list.d/element-io.list
                sudo rm -f /etc/apt/keyrings/element-io-archive-keyring.gpg
                ;;
            fedora|rhel) sudo "$PKG_MGR" remove -y element-desktop 2>/dev/null || true ;;
            arch)
                sudo pacman -Rs --noconfirm element-desktop 2>/dev/null || \
                    aur_remove element-desktop 2>/dev/null || true
                ;;
        esac
    fi
    rm -rf "$HOME/.config/Element"
}

update_element() {
    info "Updating Element..."
    if flatpak_is_installed "im.riot.Riot"; then
        flatpak update -y --user im.riot.Riot 2>/dev/null || \
            sudo flatpak update -y --system im.riot.Riot
    else
        case "$DISTRO_FAMILY" in
            debian)      sudo apt-get install -y --only-upgrade element-desktop ;;
            fedora|rhel) sudo "$PKG_MGR" upgrade -y element-desktop 2>/dev/null || true ;;
            arch)        repo_or_aur element-desktop ;;
            suse)        sudo zypper update -y element-desktop 2>/dev/null || true ;;
        esac
    fi
}

get_version_element() {
    _ver_from_pkg element-desktop || _ver_from_flatpak im.riot.Riot || echo ""
}

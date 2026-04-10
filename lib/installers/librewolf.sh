#!/bin/bash
# LibreWolf privacy-hardened browser installer functions

# --- LibreWolf ---

check_librewolf() { _check_standard librewolf "" io.gitlab.librewolf-community.librewolf; }

install_librewolf() {
    info "Installing LibreWolf..."
    ensure_tools
    case "$DISTRO_FAMILY" in
        debian)
            # Official LibreWolf apt repository
            sudo apt install -y wget gnupg lsb-release apt-transport-https ca-certificates
            wget -O- https://deb.librewolf.net/keyring.gpg | \
                sudo gpg --dearmor -o /usr/share/keyrings/librewolf.gpg
            sudo tee /etc/apt/sources.list.d/librewolf.sources <<EOF
Types: deb
URIs: https://deb.librewolf.net
Suites: $(. /etc/os-release && echo "$VERSION_CODENAME")
Components: main
Architectures: amd64
Signed-By: /usr/share/keyrings/librewolf.gpg
EOF
            sudo apt update
            sudo apt install -y librewolf
            ;;
        fedora)
            # COPR repository for LibreWolf on Fedora
            sudo "$PKG_MGR" install -y 'dnf-command(copr)' 2>/dev/null || true
            sudo "$PKG_MGR" copr enable -y bgstack15/librewolf 2>/dev/null || \
                sudo "$PKG_MGR" copr enable -y librewolf/librewolf 2>/dev/null || true
            sudo "$PKG_MGR" install -y librewolf
            ;;
        rhel)
            if has_flatpak; then
                flatpak install -y flathub io.gitlab.librewolf-community.librewolf
            else
                error "LibreWolf requires Flatpak on this RHEL-based system. Install Flatpak first."
                return 1
            fi
            ;;
        arch)
            aur_ensure librewolf-bin
            ;;
        suse)
            if has_flatpak; then
                flatpak install -y flathub io.gitlab.librewolf-community.librewolf
            else
                error "LibreWolf requires Flatpak on this openSUSE system. Install Flatpak first."
                return 1
            fi
            ;;
    esac
    info "LibreWolf installed."
}

uninstall_librewolf() {
    info "Uninstalling LibreWolf..."
    if flatpak_is_installed "io.gitlab.librewolf-community.librewolf"; then
        flatpak uninstall -y io.gitlab.librewolf-community.librewolf
    else
        case "$DISTRO_FAMILY" in
            debian)
                sudo apt purge --autoremove -y librewolf
                sudo rm -f /etc/apt/sources.list.d/librewolf.sources
                sudo rm -f /usr/share/keyrings/librewolf.gpg
                ;;
            fedora)
                sudo "$PKG_MGR" remove -y librewolf
                sudo "$PKG_MGR" copr disable -y bgstack15/librewolf 2>/dev/null || true
                ;;
            arch)
                aur_remove librewolf-bin 2>/dev/null || \
                    sudo pacman -Rs --noconfirm librewolf 2>/dev/null || true
                ;;
        esac
    fi
    rm -rf "$HOME/.librewolf"
}

update_librewolf() {
    info "Updating LibreWolf..."
    if flatpak_is_installed "io.gitlab.librewolf-community.librewolf"; then
        flatpak update -y io.gitlab.librewolf-community.librewolf
    else
        case "$DISTRO_FAMILY" in
            debian)      sudo apt-get install -y --only-upgrade librewolf ;;
            fedora|rhel) sudo "$PKG_MGR" upgrade -y librewolf ;;
            arch)        aur_ensure librewolf-bin ;;
            suse)        sudo zypper update -y librewolf ;;
        esac
    fi
}

get_version_librewolf() {
    _ver_from_cmd librewolf || _ver_from_flatpak io.gitlab.librewolf-community.librewolf || _ver_from_pkg librewolf || echo ""
}

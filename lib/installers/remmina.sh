#!/bin/bash
# Remmina installer functions

# --- Remmina ---

check_remmina() {
    command -v remmina &>/dev/null || \
        pkg_check_installed remmina || \
        (has_flatpak && flatpak list 2>/dev/null | grep -qi "org.remmina.Remmina")
}

install_remmina() {
    info "Installing Remmina..."
    ensure_tools
    case "$DISTRO_FAMILY" in
        debian)
            if [[ "$DISTRO_ID" == "ubuntu" || "$DISTRO_ID" == "kubuntu" || "$DISTRO_ID" == "neon" ]]; then
                # Use the official Remmina PPA for latest version
                sudo add-apt-repository -y ppa:remmina-ppa-team/remmina-next
                sudo apt update
            fi
            sudo apt install -y remmina remmina-plugin-rdp remmina-plugin-vnc remmina-plugin-ssh
            ;;
        fedora)
            sudo "$PKG_MGR" install -y remmina remmina-plugins-rdp remmina-plugins-vnc
            ;;
        rhel)
            sudo "$PKG_MGR" install -y epel-release 2>/dev/null || true
            sudo "$PKG_MGR" install -y remmina remmina-plugins-rdp remmina-plugins-vnc 2>/dev/null || {
                warn "Remmina plugins not found. Installing base package only..."
                sudo "$PKG_MGR" install -y remmina
            }
            ;;
        arch)
            sudo pacman -S --noconfirm remmina freerdp libvncserver
            ;;
        suse)
            sudo zypper install -y remmina remmina-plugin-rdp remmina-plugin-vnc 2>/dev/null || \
                sudo zypper install -y remmina
            ;;
    esac
    info "Remmina installed."
}

uninstall_remmina() {
    info "Uninstalling Remmina..."
    if has_flatpak && flatpak list 2>/dev/null | grep -qi "org.remmina.Remmina"; then
        flatpak uninstall -y org.remmina.Remmina
    else
        case "$DISTRO_FAMILY" in
            debian)
                sudo apt purge --autoremove -y remmina remmina-plugin-rdp remmina-plugin-vnc remmina-plugin-ssh
                sudo add-apt-repository -y --remove ppa:remmina-ppa-team/remmina-next 2>/dev/null || true
                ;;
            fedora|rhel)
                sudo "$PKG_MGR" remove -y remmina remmina-plugins-rdp remmina-plugins-vnc
                ;;
            arch)
                sudo pacman -Rs --noconfirm remmina
                ;;
            suse)
                sudo zypper remove -y remmina remmina-plugin-rdp remmina-plugin-vnc
                ;;
        esac
    fi
    rm -rf "$HOME/.config/remmina"
    rm -rf "$HOME/.local/share/remmina"
}

update_remmina() {
    info "Updating Remmina..."
    if has_flatpak && flatpak list 2>/dev/null | grep -qi "org.remmina.Remmina"; then
        flatpak update -y org.remmina.Remmina
    else
        case "$DISTRO_FAMILY" in
            debian)  sudo apt update && sudo apt upgrade -y remmina ;;
            fedora|rhel) sudo "$PKG_MGR" upgrade -y remmina ;;
            arch)    sudo pacman -S --noconfirm remmina ;;
            suse)    sudo zypper update -y remmina ;;
        esac
    fi
}

get_version_remmina() {
    remmina --version 2>/dev/null | grep -oP '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || \
    pkg_get_version remmina 2>/dev/null | sed 's/-.*//' || \
    echo ""
}

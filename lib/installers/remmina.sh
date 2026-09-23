#!/bin/bash
# Remmina installer functions

# --- Remmina ---

check_remmina() { _check_standard remmina remmina org.remmina.Remmina; }

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
            pkg_install remmina remmina-plugin-rdp remmina-plugin-vnc
            # remmina-plugin-ssh is bundled into remmina on modern Ubuntu; skip if absent
            pkg_install remmina-plugin-ssh 2>/dev/null || true
            ;;
        fedora)
            pkg_install remmina remmina-plugins-rdp remmina-plugins-vnc
            ;;
        rhel)
            pkg_install epel-release 2>/dev/null || true
            pkg_install remmina remmina-plugins-rdp remmina-plugins-vnc 2>/dev/null || {
                warn "Remmina plugins not found. Installing base package only..."
                pkg_install remmina
            }
            ;;
        arch)
            pkg_install remmina freerdp libvncserver
            ;;
        suse)
            pkg_install remmina remmina-plugin-rdp remmina-plugin-vnc 2>/dev/null || pkg_install remmina
            ;;
    esac
    info "Remmina installed."
}

uninstall_remmina() {
    info "Uninstalling Remmina..."
    if flatpak_is_installed "org.remmina.Remmina"; then
        flatpak uninstall -y --user org.remmina.Remmina 2>/dev/null || \
            sudo flatpak uninstall -y --system org.remmina.Remmina
    else
        case "$DISTRO_FAMILY" in
            debian)
                pkg_remove remmina remmina-plugin-rdp remmina-plugin-vnc
                sudo apt purge -y remmina-plugin-ssh 2>/dev/null || true
                sudo add-apt-repository -y --remove ppa:remmina-ppa-team/remmina-next 2>/dev/null || true
                ;;
            fedora|rhel)
                pkg_remove remmina remmina-plugins-rdp remmina-plugins-vnc
                ;;
            arch)
                pkg_remove remmina
                ;;
            suse)
                pkg_remove remmina remmina-plugin-rdp remmina-plugin-vnc
                ;;
        esac
    fi
    rm -rf "$HOME/.config/remmina"
    rm -rf "$HOME/.local/share/remmina"
}

update_remmina() {
    info "Updating Remmina..."
    if flatpak_is_installed "org.remmina.Remmina"; then
        flatpak update -y --user org.remmina.Remmina 2>/dev/null || \
            sudo flatpak update -y --system org.remmina.Remmina
    else
        case "$DISTRO_FAMILY" in
            debian)  sudo apt-get install -y --only-upgrade remmina ;;
            fedora|rhel) pkg_upgrade remmina ;;
            arch)    pkg_upgrade remmina ;;
            suse)    pkg_upgrade remmina ;;
        esac
    fi
}

get_version_remmina() {
    _ver_from_cmd remmina || _ver_from_pkg remmina || echo ""
}

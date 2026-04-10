#!/bin/bash
# Podman rootless container engine installer functions

# --- Podman ---

check_podman() { _check_standard podman podman ""; }

install_podman() {
    info "Installing Podman..."
    ensure_tools
    case "$DISTRO_FAMILY" in
        debian)
            sudo apt install -y podman
            ;;
        fedora)
            sudo "$PKG_MGR" install -y podman
            ;;
        rhel)
            # podman is in the AppStream repository on RHEL/Rocky/Alma/CentOS
            sudo "$PKG_MGR" install -y podman
            ;;
        arch)
            sudo pacman -S --noconfirm podman
            ;;
        suse)
            sudo zypper install -y podman
            ;;
    esac
    info "Podman installed."
    info "Podman is a daemonless, rootless container engine compatible with Docker CLI syntax."
    info "Use 'podman run', 'podman build', etc. as you would with Docker."
}

uninstall_podman() {
    info "Uninstalling Podman..."
    case "$DISTRO_FAMILY" in
        debian)      sudo apt purge --autoremove -y podman ;;
        fedora|rhel) sudo "$PKG_MGR" remove -y podman ;;
        arch)        sudo pacman -Rs --noconfirm podman ;;
        suse)        sudo zypper remove -y podman ;;
    esac
    rm -rf "$HOME/.config/containers" "$HOME/.local/share/containers"
}

update_podman() {
    info "Updating Podman..."
    case "$DISTRO_FAMILY" in
        debian)      sudo apt-get install -y --only-upgrade podman ;;
        fedora|rhel) sudo "$PKG_MGR" upgrade -y podman ;;
        arch)        sudo pacman -S --noconfirm podman ;;
        suse)        sudo zypper update -y podman ;;
    esac
}

get_version_podman() {
    _ver_from_cmd podman || _ver_from_pkg podman || echo ""
}

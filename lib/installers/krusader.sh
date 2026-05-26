#!/bin/bash
# Krusader installer functions

# --- Krusader ---

check_krusader() { _check_standard krusader krusader ""; }

install_krusader() {
    info "Installing Krusader..."
    case "$DISTRO_FAMILY" in
        debian)      sudo apt install -y krusader ;;
        fedora)      sudo "$PKG_MGR" install -y krusader ;;
        rhel)
            sudo "$PKG_MGR" install -y epel-release 2>/dev/null || true
            sudo "$PKG_MGR" install -y krusader 2>/dev/null || {
                warn "krusader not available in repos for this RHEL-based distro."
                return 1
            }
            ;;
        arch)        sudo pacman -S --noconfirm krusader ;;
        suse)        sudo zypper install -y krusader ;;
    esac
    info "Krusader installed."
}

uninstall_krusader() {
    info "Uninstalling Krusader..."
    case "$DISTRO_FAMILY" in
        debian)      sudo apt purge --autoremove -y krusader ;;
        fedora|rhel) sudo "$PKG_MGR" remove -y krusader ;;
        arch)        sudo pacman -Rs --noconfirm krusader ;;
        suse)        sudo zypper remove -y krusader ;;
    esac
}

update_krusader() {
    info "Updating Krusader..."
    case "$DISTRO_FAMILY" in
        debian)      sudo apt-get install -y --only-upgrade krusader ;;
        fedora|rhel) sudo "$PKG_MGR" upgrade -y krusader ;;
        arch)        sudo pacman -S --noconfirm krusader ;;
        suse)        sudo zypper update -y krusader ;;
    esac
}

get_version_krusader() {
    _ver_from_pkg krusader || echo ""
}

#!/bin/bash
# Gufw (graphical frontend for UFW) installer functions

# --- Gufw ---

check_gufw() { _check_standard gufw gufw ""; }

install_gufw() {
    info "Installing Gufw (graphical frontend for UFW)..."
    # Gufw is only a frontend — make sure UFW itself is installed and enabled first
    if ! check_ufw; then
        install_ufw || return 1
    fi
    if ! _have_cmd ufw; then
        warn "UFW is not available on this system. Gufw requires UFW."
        return 1
    fi
    case "$DISTRO_FAMILY" in
        debian)
            sudo apt install -y gufw || return 1
            ;;
        fedora)
            sudo "$PKG_MGR" install -y gufw 2>/dev/null || {
                warn "Gufw is not packaged for Fedora. Use UFW from the command line, or install firewalld with the firewall-config GUI instead."
                return 1
            }
            ;;
        rhel)
            sudo "$PKG_MGR" install -y epel-release 2>/dev/null || true
            sudo "$PKG_MGR" install -y gufw 2>/dev/null || {
                warn "Gufw not available in repos for this RHEL-based distro."
                return 1
            }
            ;;
        arch)
            sudo pacman -S --noconfirm gufw || return 1
            ;;
        suse)
            sudo zypper install -y gufw 2>/dev/null || {
                warn "Gufw not available in default repos for this SUSE-based distro."
                return 1
            }
            ;;
    esac
    info "Gufw installed."
}

uninstall_gufw() {
    info "Uninstalling Gufw..."
    case "$DISTRO_FAMILY" in
        debian)      sudo apt purge --autoremove -y gufw ;;
        fedora|rhel) sudo "$PKG_MGR" remove -y gufw ;;
        arch)        sudo pacman -Rs --noconfirm gufw ;;
        suse)        sudo zypper remove -y gufw ;;
    esac
}

update_gufw() {
    info "Updating Gufw..."
    case "$DISTRO_FAMILY" in
        debian)      sudo apt-get install -y --only-upgrade gufw ;;
        fedora|rhel) sudo "$PKG_MGR" upgrade -y gufw ;;
        arch)        sudo pacman -S --noconfirm gufw ;;
        suse)        sudo zypper update -y gufw ;;
    esac
}

get_version_gufw() {
    _ver_from_pkg gufw || echo ""
}

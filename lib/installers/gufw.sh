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
            pkg_install gufw || return 1
            ;;
        fedora)
            pkg_install gufw 2>/dev/null || {
                warn "Gufw is not packaged for Fedora. Use UFW from the command line, or install firewalld with the firewall-config GUI instead."
                return 1
            }
            ;;
        rhel)
            pkg_install epel-release 2>/dev/null || true
            pkg_install gufw 2>/dev/null || {
                warn "Gufw not available in repos for this RHEL-based distro."
                return 1
            }
            ;;
        arch)
            pkg_install gufw || return 1
            ;;
        suse)
            pkg_install gufw 2>/dev/null || {
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
        debian)      pkg_remove gufw ;;
        fedora|rhel) pkg_remove gufw ;;
        arch)        pkg_remove gufw ;;
        suse)        pkg_remove gufw ;;
    esac
}

update_gufw() {
    info "Updating Gufw..."
    case "$DISTRO_FAMILY" in
        debian)      sudo apt-get install -y --only-upgrade gufw ;;
        fedora|rhel) pkg_upgrade gufw ;;
        arch)        pkg_upgrade gufw ;;
        suse)        pkg_upgrade gufw ;;
    esac
}

get_version_gufw() {
    _ver_from_pkg gufw || echo ""
}

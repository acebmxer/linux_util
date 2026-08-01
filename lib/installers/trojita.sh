#!/bin/bash
# Trojitá installer functions

# --- Trojitá ---
# Fast, Qt-native IMAP client — a light alternative to KMail on KDE.
#
# Availability is uneven and the project is quiet upstream: the current release
# is 0.7 (2016). Fedora still carries it, Arch has it in the AUR only, Debian
# dropped the package entirely, and it was never in the RHEL channels. Those
# two families get a clear error rather than a silent no-op.

check_trojita() { _check_standard trojita trojita ""; }

install_trojita() {
    info "Installing Trojitá..."
    ensure_tools
    case "$DISTRO_FAMILY" in
        fedora)
            sudo "$PKG_MGR" install -y trojita
            ;;
        arch)
            aur_ensure trojita || return 1
            ;;
        suse)
            sudo zypper install -y trojita
            ;;
        debian)
            error "Trojitá was removed from Debian and is not packaged for Debian or Ubuntu."
            error "Use KMail for a Qt-native client, or Claws Mail for a lightweight one."
            return 1
            ;;
        rhel)
            error "Trojitá is not available in the RHEL base channels or EPEL."
            error "Use KMail for a Qt-native client, or Claws Mail for a lightweight one."
            return 1
            ;;
    esac
    info "Trojitá installed."
}

uninstall_trojita() {
    info "Uninstalling Trojitá..."
    case "$DISTRO_FAMILY" in
        fedora)
            sudo "$PKG_MGR" remove -y trojita
            ;;
        arch)
            aur_remove trojita || true
            ;;
        suse)
            sudo zypper remove -y trojita
            ;;
        *)
            warn "Trojitá is not installable on this distro, so there is nothing to remove."
            ;;
    esac
    rm -rf "$HOME/.config/flaska.net"
    rm -rf "$HOME/.cache/flaska.net"
}

update_trojita() {
    info "Updating Trojitá..."
    case "$DISTRO_FAMILY" in
        fedora|suse)
            pkg_upgrade trojita
            ;;
        arch)
            aur_ensure trojita
            ;;
        *)
            warn "Trojitá is not installable on this distro, so there is nothing to update."
            return 1
            ;;
    esac
}

get_version_trojita() {
    _ver_from_pkg trojita || echo ""
}

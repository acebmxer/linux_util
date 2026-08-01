#!/bin/bash
# Claws Mail installer functions

# --- Claws Mail ---
# Lightweight GTK mail client. The binary is "claws-mail" on every distro; the
# package name matches. Not in the RHEL base channels, so EPEL is enabled first
# there.

check_claws_mail() { _check_standard claws-mail claws-mail ""; }

install_claws_mail() {
    info "Installing Claws Mail..."
    ensure_tools
    case "$DISTRO_FAMILY" in
        debian)
            sudo apt update
            sudo apt install -y claws-mail
            ;;
        fedora)
            sudo "$PKG_MGR" install -y claws-mail
            ;;
        rhel)
            sudo "$PKG_MGR" install -y epel-release 2>/dev/null || true
            sudo "$PKG_MGR" install -y claws-mail
            ;;
        arch)
            pkg_install claws-mail
            ;;
        suse)
            sudo zypper install -y claws-mail
            ;;
    esac
    info "Claws Mail installed."
}

uninstall_claws_mail() {
    info "Uninstalling Claws Mail..."
    case "$DISTRO_FAMILY" in
        debian)
            sudo apt purge --autoremove -y claws-mail
            sudo apt autoclean
            ;;
        fedora|rhel)
            sudo "$PKG_MGR" remove -y claws-mail
            ;;
        arch)
            pkg_remove claws-mail
            ;;
        suse)
            sudo zypper remove -y claws-mail
            ;;
    esac
    # Claws Mail keeps mail and account config in ~/.claws-mail (not XDG).
    rm -rf "$HOME/.claws-mail"
    rm -rf "$HOME/.config/claws-mail"
}

update_claws_mail() {
    info "Updating Claws Mail..."
    case "$DISTRO_FAMILY" in
        debian)
            sudo apt update
            sudo apt install -y --only-upgrade claws-mail
            ;;
        arch)
            pkg_install claws-mail
            ;;
        *)
            pkg_upgrade claws-mail
            ;;
    esac
}

get_version_claws_mail() {
    _ver_from_cmd claws-mail || _ver_from_pkg claws-mail || echo ""
}

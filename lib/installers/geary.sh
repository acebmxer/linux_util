#!/bin/bash
# Geary installer functions

# --- Geary (GNOME Mail) ---
# Lightweight conversation-threaded mail client built for GNOME. Not in the
# RHEL base channels, so EPEL is enabled first there.

# No Flatpak ID here on purpose: this installer only ever installs the distro
# package, so reporting a Flatpak copy as "installed" would point update/
# uninstall at a package that isn't there.
check_geary() { _check_standard geary geary ""; }

install_geary() {
    info "Installing Geary..."
    ensure_tools
    case "$DISTRO_FAMILY" in
        debian)
            sudo apt update
            sudo apt install -y geary
            ;;
        fedora)
            sudo "$PKG_MGR" install -y geary
            ;;
        rhel)
            sudo "$PKG_MGR" install -y epel-release 2>/dev/null || true
            sudo "$PKG_MGR" install -y geary
            ;;
        arch)
            pkg_install geary
            ;;
        suse)
            sudo zypper install -y geary
            ;;
    esac
    info "Geary installed."
}

uninstall_geary() {
    info "Uninstalling Geary..."
    case "$DISTRO_FAMILY" in
        debian)
            sudo apt purge --autoremove -y geary
            sudo apt autoclean
            ;;
        fedora|rhel)
            sudo "$PKG_MGR" remove -y geary
            ;;
        arch)
            pkg_remove geary
            ;;
        suse)
            sudo zypper remove -y geary
            ;;
    esac
    rm -rf "$HOME/.config/geary"
    rm -rf "$HOME/.local/share/geary"
    rm -rf "$HOME/.cache/geary"
}

update_geary() {
    info "Updating Geary..."
    case "$DISTRO_FAMILY" in
        debian)
            sudo apt update
            sudo apt install -y --only-upgrade geary
            ;;
        arch)
            pkg_install geary
            ;;
        *)
            pkg_upgrade geary
            ;;
    esac
}

get_version_geary() {
    _ver_from_pkg geary || echo ""
}

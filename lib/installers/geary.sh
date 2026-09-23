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
            pkg_install geary
            ;;
        fedora)
            pkg_install geary
            ;;
        rhel)
            pkg_install epel-release 2>/dev/null || true
            pkg_install geary
            ;;
        arch)
            pkg_install geary
            ;;
        suse)
            pkg_install geary
            ;;
    esac
    info "Geary installed."
}

uninstall_geary() {
    info "Uninstalling Geary..."
    case "$DISTRO_FAMILY" in
        debian)
            pkg_remove geary
            ;;
        fedora|rhel)
            pkg_remove geary
            ;;
        arch)
            pkg_remove geary
            ;;
        suse)
            pkg_remove geary
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
            pkg_upgrade geary
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

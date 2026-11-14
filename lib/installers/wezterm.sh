#!/bin/bash
# WezTerm terminal emulator installer functions
#
# GPU-accelerated terminal configured in Lua. Installed from the distro's own
# package, which exists on Arch, openSUSE and Alpine. Upstream's stable build
# is from February 2024 and its other channels are nightly builds, and
# Flathub's copy is that old build in a sandbox with a read-only home, so
# Debian, Ubuntu, Fedora and RHEL clones do not offer it.

# --- WezTerm ---

check_wezterm() { _check_standard wezterm wezterm ""; }

install_wezterm() {
    info "Installing WezTerm..."
    pkg_refresh
    if ! pkg_in_repo wezterm; then
        error "WezTerm is not in the ${DISTRO_NAME:-system} repositories. Nothing was changed."
        return 1
    fi
    pkg_install wezterm || return 1
    info "WezTerm installed."
}

uninstall_wezterm() {
    info "Uninstalling WezTerm..."
    pkg_remove wezterm
}

update_wezterm() {
    info "Updating WezTerm..."
    pkg_upgrade wezterm
}

get_version_wezterm() { _ver_from_pkg wezterm || echo ""; }

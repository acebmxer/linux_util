#!/bin/bash
# Yakuake terminal emulator installer functions
#
# KDE's drop-down terminal: F12 slides it down from the top of the screen. In
# the distro repositories everywhere, Alpine included (EPEL on RHEL clones).

# --- Yakuake ---

check_yakuake() { _check_standard yakuake yakuake ""; }

install_yakuake() {
    info "Installing Yakuake..."
    ensure_epel
    pkg_install yakuake || return 1
    info "Yakuake installed. Start it once from the app menu; F12 then opens and hides it."
}

uninstall_yakuake() {
    info "Uninstalling Yakuake..."
    pkg_remove yakuake
}

update_yakuake() {
    info "Updating Yakuake..."
    pkg_upgrade yakuake
}

get_version_yakuake() { _ver_from_pkg yakuake || echo ""; }

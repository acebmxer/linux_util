#!/bin/bash
# Gear Lever installer functions
#
# Manager for AppImage files (menu entries, updates, removal). The distro
# package on openSUSE; everywhere else its Flathub listing. Not offered on
# Alpine.

# --- Gear Lever ---

check_gear_lever() { _check_standard "" gearlever it.mijorus.gearlever; }

install_gear_lever() {
    info "Installing Gear Lever..."
    native_or_flatpak_install it.mijorus.gearlever gearlever || return 1
    info "Gear Lever installed."
}

# The AppImages it manages are kept.
uninstall_gear_lever() {
    info "Uninstalling Gear Lever..."
    native_or_flatpak_uninstall it.mijorus.gearlever gearlever
}

update_gear_lever() {
    info "Updating Gear Lever..."
    native_or_flatpak_update it.mijorus.gearlever gearlever
}

get_version_gear_lever() { native_or_flatpak_version it.mijorus.gearlever gearlever; }

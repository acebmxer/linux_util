#!/bin/bash
# BleachBit installer functions
#
# Disk cleaner: clears caches, logs, history and temporary files for the system
# and many applications. Distro package where the repositories have one
# (EPEL on Rocky/Alma 8 and 9), otherwise Flathub (Rocky/Alma 10).
# Alpine has no package, so it is not offered there.

# --- BleachBit ---

check_bleachbit() { _check_standard bleachbit bleachbit org.bleachbit.BleachBit; }

install_bleachbit() {
    info "Installing BleachBit..."
    native_or_flatpak_install org.bleachbit.BleachBit bleachbit || return 1
    info "BleachBit installed."
}

uninstall_bleachbit() {
    info "Uninstalling BleachBit..."
    native_or_flatpak_uninstall org.bleachbit.BleachBit bleachbit
}

update_bleachbit() {
    info "Updating BleachBit..."
    native_or_flatpak_update org.bleachbit.BleachBit bleachbit
}

get_version_bleachbit() { native_or_flatpak_version org.bleachbit.BleachBit bleachbit; }

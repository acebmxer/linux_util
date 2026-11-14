#!/bin/bash
# PPSSPP installer functions
#
# PSP emulator. The distro package on Arch, openSUSE and Alpine; everywhere
# else its Flathub listing.

# --- PPSSPP ---

check_ppsspp() { _check_standard "" ppsspp org.ppsspp.PPSSPP; }

install_ppsspp() {
    info "Installing PPSSPP..."
    native_or_flatpak_install org.ppsspp.PPSSPP ppsspp || return 1
    info "PPSSPP installed."
}

# Your saves and settings are kept.
uninstall_ppsspp() {
    info "Uninstalling PPSSPP..."
    native_or_flatpak_uninstall org.ppsspp.PPSSPP ppsspp
}

update_ppsspp() {
    info "Updating PPSSPP..."
    native_or_flatpak_update org.ppsspp.PPSSPP ppsspp
}

get_version_ppsspp() { native_or_flatpak_version org.ppsspp.PPSSPP ppsspp; }

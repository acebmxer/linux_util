#!/bin/bash
# Cryptomator installer functions
# Cryptomator publishes its Linux app as a Flatpak (org.cryptomator.Cryptomator)
# on Flathub, the same on every distro, so that is the one install route.
# Vaults are ordinary folders chosen by the user and are never touched here.

# --- Cryptomator ---

_CRYPTOMATOR_FLATPAK="org.cryptomator.Cryptomator"

check_cryptomator() { _check_standard "" "" "$_CRYPTOMATOR_FLATPAK"; }

install_cryptomator() {
    info "Installing Cryptomator..."
    flatpak_install_flathub "$_CRYPTOMATOR_FLATPAK" || return 1
    info "Cryptomator installed."
}

uninstall_cryptomator() {
    info "Uninstalling Cryptomator..."
    flatpak uninstall -y --user "$_CRYPTOMATOR_FLATPAK" 2>/dev/null || \
        sudo flatpak uninstall -y --system "$_CRYPTOMATOR_FLATPAK"
}

update_cryptomator() {
    info "Updating Cryptomator..."
    flatpak update -y --user "$_CRYPTOMATOR_FLATPAK" 2>/dev/null || \
        sudo flatpak update -y --system "$_CRYPTOMATOR_FLATPAK"
}

get_version_cryptomator() { _ver_from_flatpak "$_CRYPTOMATOR_FLATPAK" || echo ""; }

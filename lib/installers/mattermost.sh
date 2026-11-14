#!/bin/bash
# Mattermost desktop app installer functions
#
# The distro package on Arch (mattermost-desktop); everywhere else Mattermost's
# own Flathub listing (com.mattermost.Desktop). Not offered on Alpine.

# --- Mattermost ---

check_mattermost() { _check_standard "" mattermost-desktop com.mattermost.Desktop; }

install_mattermost() {
    info "Installing Mattermost..."
    native_or_flatpak_install com.mattermost.Desktop mattermost-desktop || return 1
    info "Mattermost installed."
}

# The saved server connections and sign-in are kept.
uninstall_mattermost() {
    info "Uninstalling Mattermost..."
    native_or_flatpak_uninstall com.mattermost.Desktop mattermost-desktop
}

update_mattermost() {
    info "Updating Mattermost..."
    native_or_flatpak_update com.mattermost.Desktop mattermost-desktop
}

get_version_mattermost() { native_or_flatpak_version com.mattermost.Desktop mattermost-desktop; }

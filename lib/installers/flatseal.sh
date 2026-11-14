#!/bin/bash
# Flatseal installer functions
#
# Permissions manager for Flatpak apps (useful for the Flatpak game apps
# here). The distro package where a repository has one, otherwise Flathub. Not
# offered on Alpine.

# --- Flatseal ---

check_flatseal() { _check_standard "" flatseal com.github.tchx84.Flatseal; }

install_flatseal() {
    info "Installing Flatseal..."
    native_or_flatpak_install com.github.tchx84.Flatseal flatseal || return 1
    info "Flatseal installed."
}

# Per-app permission overrides in ~/.local/share/flatpak/overrides are kept.
uninstall_flatseal() {
    info "Uninstalling Flatseal..."
    native_or_flatpak_uninstall com.github.tchx84.Flatseal flatseal
}

update_flatseal() {
    info "Updating Flatseal..."
    native_or_flatpak_update com.github.tchx84.Flatseal flatseal
}

get_version_flatseal() { native_or_flatpak_version com.github.tchx84.Flatseal flatseal; }

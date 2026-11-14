#!/bin/bash
# Darktable photo workflow installer functions
# Distro package where the repositories have one, otherwise Flathub
# (native_or_flatpak_* in _shared.sh).

# --- Darktable ---

check_darktable() { _check_standard darktable darktable org.darktable.Darktable; }

install_darktable() {
    info "Installing Darktable..."
    native_or_flatpak_install org.darktable.Darktable darktable || return 1
    info "Darktable installed."
}

uninstall_darktable() {
    info "Uninstalling Darktable..."
    native_or_flatpak_uninstall org.darktable.Darktable darktable
}

update_darktable() {
    info "Updating Darktable..."
    native_or_flatpak_update org.darktable.Darktable darktable
}

get_version_darktable() { native_or_flatpak_version org.darktable.Darktable darktable; }

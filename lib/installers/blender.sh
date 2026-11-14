#!/bin/bash
# Blender 3D suite installer functions
# Distro package where the repositories have one, otherwise Flathub
# (native_or_flatpak_* in _shared.sh).

# --- Blender ---

check_blender() { _check_standard blender blender org.blender.Blender; }

install_blender() {
    info "Installing Blender..."
    native_or_flatpak_install org.blender.Blender blender || return 1
    info "Blender installed."
}

uninstall_blender() {
    info "Uninstalling Blender..."
    native_or_flatpak_uninstall org.blender.Blender blender
}

update_blender() {
    info "Updating Blender..."
    native_or_flatpak_update org.blender.Blender blender
}

get_version_blender() { native_or_flatpak_version org.blender.Blender blender; }

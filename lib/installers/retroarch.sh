#!/bin/bash
# RetroArch installer functions
#
# The distro package on Debian, Ubuntu, Fedora, Arch, openSUSE and Alpine;
# Flathub on RHEL clones. Frontend for the libretro emulator cores; cores are
# fetched inside the app (Online Updater).

# --- RetroArch ---

check_retroarch() { _check_standard retroarch retroarch org.libretro.RetroArch; }

install_retroarch() {
    info "Installing RetroArch..."
    native_or_flatpak_install org.libretro.RetroArch retroarch || return 1
    info "RetroArch installed."
}

# Your saves, states and settings are kept.
uninstall_retroarch() {
    info "Uninstalling RetroArch..."
    native_or_flatpak_uninstall org.libretro.RetroArch retroarch
}

update_retroarch() {
    info "Updating RetroArch..."
    native_or_flatpak_update org.libretro.RetroArch retroarch
}

get_version_retroarch() { native_or_flatpak_version org.libretro.RetroArch retroarch; }

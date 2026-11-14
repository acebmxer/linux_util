#!/bin/bash
# Shotcut video editor installer functions
# Distro package where the repositories have one, otherwise Flathub
# (native_or_flatpak_* in _shared.sh).

# --- Shotcut ---

check_shotcut() { _check_standard shotcut shotcut org.shotcut.Shotcut; }

install_shotcut() {
    info "Installing Shotcut..."
    native_or_flatpak_install org.shotcut.Shotcut shotcut || return 1
    info "Shotcut installed."
}

uninstall_shotcut() {
    info "Uninstalling Shotcut..."
    native_or_flatpak_uninstall org.shotcut.Shotcut shotcut
}

update_shotcut() {
    info "Updating Shotcut..."
    native_or_flatpak_update org.shotcut.Shotcut shotcut
}

get_version_shotcut() { native_or_flatpak_version org.shotcut.Shotcut shotcut; }

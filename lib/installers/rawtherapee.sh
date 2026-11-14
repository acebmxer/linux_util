#!/bin/bash
# RawTherapee raw photo developer installer functions
# Distro package where the repositories have one, otherwise Flathub
# (native_or_flatpak_* in _shared.sh).

# --- RawTherapee ---

check_rawtherapee() { _check_standard rawtherapee rawtherapee com.rawtherapee.RawTherapee; }

install_rawtherapee() {
    info "Installing RawTherapee..."
    native_or_flatpak_install com.rawtherapee.RawTherapee rawtherapee || return 1
    info "RawTherapee installed."
}

uninstall_rawtherapee() {
    info "Uninstalling RawTherapee..."
    native_or_flatpak_uninstall com.rawtherapee.RawTherapee rawtherapee
}

update_rawtherapee() {
    info "Updating RawTherapee..."
    native_or_flatpak_update com.rawtherapee.RawTherapee rawtherapee
}

get_version_rawtherapee() { native_or_flatpak_version com.rawtherapee.RawTherapee rawtherapee; }

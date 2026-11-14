#!/bin/bash
# mpv media player installer functions
# Distro package where the repositories have one, otherwise Flathub
# (native_or_flatpak_* in _shared.sh).

# --- mpv ---

check_mpv() { _check_standard mpv mpv io.mpv.Mpv; }

install_mpv() {
    info "Installing mpv..."
    native_or_flatpak_install io.mpv.Mpv mpv || return 1
    info "mpv installed."
}

uninstall_mpv() {
    info "Uninstalling mpv..."
    native_or_flatpak_uninstall io.mpv.Mpv mpv
}

update_mpv() {
    info "Updating mpv..."
    native_or_flatpak_update io.mpv.Mpv mpv
}

get_version_mpv() { native_or_flatpak_version io.mpv.Mpv mpv; }

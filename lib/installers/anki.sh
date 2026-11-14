#!/bin/bash
# Anki flashcards installer functions
# Distro package where the repositories have one, otherwise Flathub
# (native_or_flatpak_* in _shared.sh).

# --- Anki ---

check_anki() { _check_standard anki anki net.ankiweb.Anki; }

install_anki() {
    info "Installing Anki..."
    native_or_flatpak_install net.ankiweb.Anki anki || return 1
    info "Anki installed."
}

uninstall_anki() {
    info "Uninstalling Anki..."
    native_or_flatpak_uninstall net.ankiweb.Anki anki
}

update_anki() {
    info "Updating Anki..."
    native_or_flatpak_update net.ankiweb.Anki anki
}

get_version_anki() { native_or_flatpak_version net.ankiweb.Anki anki; }

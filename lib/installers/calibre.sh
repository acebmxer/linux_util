#!/bin/bash
# Calibre e-book manager installer functions
# Distro package where the repositories have one, otherwise Flathub
# (native_or_flatpak_* in _shared.sh).

# --- Calibre ---

check_calibre() { _check_standard calibre calibre com.calibre_ebook.calibre; }

install_calibre() {
    info "Installing Calibre..."
    native_or_flatpak_install com.calibre_ebook.calibre calibre || return 1
    info "Calibre installed."
}

uninstall_calibre() {
    info "Uninstalling Calibre..."
    native_or_flatpak_uninstall com.calibre_ebook.calibre calibre
}

update_calibre() {
    info "Updating Calibre..."
    native_or_flatpak_update com.calibre_ebook.calibre calibre
}

get_version_calibre() { native_or_flatpak_version com.calibre_ebook.calibre calibre; }

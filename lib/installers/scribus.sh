#!/bin/bash
# Scribus desktop publishing installer functions
# Distro package where the repositories have one, otherwise Flathub
# (native_or_flatpak_* in _shared.sh).

# --- Scribus ---

check_scribus() { _check_standard scribus scribus net.scribus.Scribus; }

install_scribus() {
    info "Installing Scribus..."
    native_or_flatpak_install net.scribus.Scribus scribus || return 1
    info "Scribus installed."
}

uninstall_scribus() {
    info "Uninstalling Scribus..."
    native_or_flatpak_uninstall net.scribus.Scribus scribus
}

update_scribus() {
    info "Updating Scribus..."
    native_or_flatpak_update net.scribus.Scribus scribus
}

get_version_scribus() { native_or_flatpak_version net.scribus.Scribus scribus; }

#!/bin/bash
# Okular document viewer installer functions
# Distro package where the repositories have one, otherwise Flathub
# (native_or_flatpak_* in _shared.sh).

# --- Okular ---

check_okular() { _check_standard okular okular org.kde.okular; }

install_okular() {
    info "Installing Okular..."
    native_or_flatpak_install org.kde.okular okular || return 1
    info "Okular installed."
}

uninstall_okular() {
    info "Uninstalling Okular..."
    native_or_flatpak_uninstall org.kde.okular okular
}

update_okular() {
    info "Updating Okular..."
    native_or_flatpak_update org.kde.okular okular
}

get_version_okular() { native_or_flatpak_version org.kde.okular okular; }

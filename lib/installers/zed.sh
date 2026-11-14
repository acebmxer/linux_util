#!/bin/bash
# Zed installer functions
#
# Fast code editor with built-in collaboration and AI. The distro package on
# Arch and openSUSE Tumbleweed (it installs the zeditor command); everywhere
# else Zed's own Flathub listing. Not offered on Alpine.

# --- Zed ---

check_zed() { _check_standard "" zed dev.zed.Zed; }

install_zed() {
    info "Installing Zed..."
    native_or_flatpak_install dev.zed.Zed zed || return 1
    info "Zed installed."
}

uninstall_zed() {
    info "Uninstalling Zed..."
    native_or_flatpak_uninstall dev.zed.Zed zed
}

update_zed() {
    info "Updating Zed..."
    native_or_flatpak_update dev.zed.Zed zed
}

get_version_zed() { native_or_flatpak_version dev.zed.Zed zed; }

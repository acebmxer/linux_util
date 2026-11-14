#!/bin/bash
# KeePassXC password manager installer functions
# Distro package where the repositories have one, otherwise Flathub
# (native_or_flatpak_* in _shared.sh).

# --- KeePassXC ---

check_keepassxc() { _check_standard keepassxc keepassxc org.keepassxc.KeePassXC; }

install_keepassxc() {
    info "Installing KeePassXC..."
    native_or_flatpak_install org.keepassxc.KeePassXC keepassxc || return 1
    info "KeePassXC installed."
}

uninstall_keepassxc() {
    info "Uninstalling KeePassXC..."
    native_or_flatpak_uninstall org.keepassxc.KeePassXC keepassxc
}

update_keepassxc() {
    info "Updating KeePassXC..."
    native_or_flatpak_update org.keepassxc.KeePassXC keepassxc
}

get_version_keepassxc() { native_or_flatpak_version org.keepassxc.KeePassXC keepassxc; }

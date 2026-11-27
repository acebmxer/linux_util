#!/bin/bash
# Kwi terminal emulator installer functions
#
# KDE's new terminal, built on libghostty-vt and Kirigami
# (https://apps.kde.org/kwi/). Still in early development (0.1). The distro
# package where a repository has one (Arch), otherwise KDE's own Flathub
# listing. Not offered on Alpine, which has neither.

# --- Kwi ---

_KWI_FLATPAK="org.kde.kwi"

check_kwi() { _check_standard "" kwi "$_KWI_FLATPAK"; }

install_kwi() {
    info "Installing Kwi..."
    native_or_flatpak_install "$_KWI_FLATPAK" kwi || return 1
    info "Kwi installed."
}

# Settings in ~/.config are kept.
uninstall_kwi() {
    info "Uninstalling Kwi..."
    native_or_flatpak_uninstall "$_KWI_FLATPAK" kwi
}

update_kwi() {
    info "Updating Kwi..."
    native_or_flatpak_update "$_KWI_FLATPAK" kwi
}

get_version_kwi() { native_or_flatpak_version "$_KWI_FLATPAK" kwi; }

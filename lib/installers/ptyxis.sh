#!/bin/bash
# Ptyxis terminal emulator installer functions
#
# GNOME's terminal and the default on Ubuntu 26.04 and RHEL 10; it opens tabs
# straight into Toolbox, Distrobox and Podman containers. The distro package
# where a repository has one, otherwise its Flathub listing (Ubuntu 22.04 and
# 24.04, Rocky/Alma 8 and 9). Alpine uses its own package (alpine_packages.sh).

# --- Ptyxis ---

_PTYXIS_FLATPAK="app.devsuite.Ptyxis"

check_ptyxis() { _check_standard "" ptyxis "$_PTYXIS_FLATPAK"; }

install_ptyxis() {
    info "Installing Ptyxis..."
    native_or_flatpak_install "$_PTYXIS_FLATPAK" ptyxis || return 1
    info "Ptyxis installed."
}

# Profiles are kept (GSettings).
uninstall_ptyxis() {
    info "Uninstalling Ptyxis..."
    native_or_flatpak_uninstall "$_PTYXIS_FLATPAK" ptyxis
}

update_ptyxis() {
    info "Updating Ptyxis..."
    native_or_flatpak_update "$_PTYXIS_FLATPAK" ptyxis
}

get_version_ptyxis() { native_or_flatpak_version "$_PTYXIS_FLATPAK" ptyxis; }

#!/bin/bash
# Moonlight installer functions
#
# Game-streaming client for a Sunshine or GeForce host. The distro package
# (moonlight-qt; openSUSE calls it moonlight) on Fedora, Arch, openSUSE and
# Alpine; everywhere else Moonlight's own Flathub listing.

# --- Moonlight ---

_MOONLIGHT_FLATPAK="com.moonlight_stream.Moonlight"

_moonlight_pkg() {
    if [[ "${DISTRO_FAMILY:-}" == "suse" ]]; then echo moonlight; else echo moonlight-qt; fi
}

check_moonlight() { _check_standard "" "$(_moonlight_pkg)" "$_MOONLIGHT_FLATPAK"; }

install_moonlight() {
    info "Installing Moonlight..."
    native_or_flatpak_install "$_MOONLIGHT_FLATPAK" "$(_moonlight_pkg)" || return 1
    info "Moonlight installed."
}

# The paired hosts and settings are kept.
uninstall_moonlight() {
    info "Uninstalling Moonlight..."
    native_or_flatpak_uninstall "$_MOONLIGHT_FLATPAK" "$(_moonlight_pkg)"
}

update_moonlight() {
    info "Updating Moonlight..."
    native_or_flatpak_update "$_MOONLIGHT_FLATPAK" "$(_moonlight_pkg)"
}

get_version_moonlight() { native_or_flatpak_version "$_MOONLIGHT_FLATPAK" "$(_moonlight_pkg)"; }

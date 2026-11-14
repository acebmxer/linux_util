#!/bin/bash
# Spotify installer functions
# Spotify's Linux client is installed from Flathub (com.spotify.Client), the same
# on every distro: none of the distro repositories checked carries it.

# --- Spotify ---

_SPOTIFY_FLATPAK="com.spotify.Client"

check_spotify() { _check_standard "" "" "$_SPOTIFY_FLATPAK"; }

install_spotify() {
    info "Installing Spotify..."
    flatpak_install_flathub "$_SPOTIFY_FLATPAK" || return 1
    info "Spotify installed."
}

# Spotify keeps its login and cache in ~/.var/app/com.spotify.Client, which is
# left alone.
uninstall_spotify() {
    info "Uninstalling Spotify..."
    flatpak uninstall -y --user "$_SPOTIFY_FLATPAK" 2>/dev/null || \
        sudo flatpak uninstall -y --system "$_SPOTIFY_FLATPAK"
}

update_spotify() {
    info "Updating Spotify..."
    flatpak update -y --user "$_SPOTIFY_FLATPAK" 2>/dev/null || \
        sudo flatpak update -y --system "$_SPOTIFY_FLATPAK"
}

get_version_spotify() { _ver_from_flatpak "$_SPOTIFY_FLATPAK" || echo ""; }

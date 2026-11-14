#!/bin/bash
# Microsoft Teams installer functions
#
# Microsoft retired its own Linux Teams app at the end of 2022. This installs
# Teams for Linux, the open source (GPL-3.0) client that wraps the Teams web
# app: Flathub (com.github.IsmaelMartinez.teams_for_linux), or the distro
# package where a repository carries one. Not offered on Alpine.

# --- Microsoft Teams (Teams for Linux) ---

_TEAMS_FLATPAK="com.github.IsmaelMartinez.teams_for_linux"

check_microsoft_teams() { _check_standard "" teams-for-linux "$_TEAMS_FLATPAK"; }

install_microsoft_teams() {
    info "Installing Microsoft Teams (Teams for Linux)..."
    native_or_flatpak_install "$_TEAMS_FLATPAK" teams-for-linux || return 1
    info "Microsoft Teams (Teams for Linux) installed."
}

# The signed-in account and settings are kept.
uninstall_microsoft_teams() {
    info "Uninstalling Microsoft Teams (Teams for Linux)..."
    native_or_flatpak_uninstall "$_TEAMS_FLATPAK" teams-for-linux
}

update_microsoft_teams() {
    info "Updating Microsoft Teams (Teams for Linux)..."
    native_or_flatpak_update "$_TEAMS_FLATPAK" teams-for-linux
}

get_version_microsoft_teams() { native_or_flatpak_version "$_TEAMS_FLATPAK" teams-for-linux; }

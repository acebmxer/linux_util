#!/bin/bash
# Nextcloud Talk Desktop installer functions
#
# Talk Desktop is published only as a Flatpak on Flathub
# (com.nextcloud.talk.desktop); it is not packaged in distro repositories.

# --- Nextcloud Talk Desktop ---

_NEXTCLOUD_TALK_FLATPAK="com.nextcloud.talk.desktop"

check_nextcloud_talk() {
    flatpak_is_installed "$_NEXTCLOUD_TALK_FLATPAK"
}

install_nextcloud_talk() {
    info "Installing Nextcloud Talk Desktop..."
    ensure_tools
    if has_flatpak; then
        flatpak install -y flathub "$_NEXTCLOUD_TALK_FLATPAK" || {
            error "Failed to install Nextcloud Talk Desktop via Flatpak."
            return 1
        }
    else
        error "Nextcloud Talk Desktop is only available as a Flatpak. Install Flatpak first."
        return 1
    fi
    info "Nextcloud Talk Desktop installed."
}

uninstall_nextcloud_talk() {
    info "Uninstalling Nextcloud Talk Desktop..."
    if flatpak_is_installed "$_NEXTCLOUD_TALK_FLATPAK"; then
        flatpak uninstall -y "$_NEXTCLOUD_TALK_FLATPAK"
    fi
    rm -rf "$HOME/.var/app/$_NEXTCLOUD_TALK_FLATPAK"
}

update_nextcloud_talk() {
    info "Updating Nextcloud Talk Desktop..."
    if flatpak_is_installed "$_NEXTCLOUD_TALK_FLATPAK"; then
        flatpak update -y "$_NEXTCLOUD_TALK_FLATPAK"
    fi
}

get_version_nextcloud_talk() {
    _ver_from_flatpak "$_NEXTCLOUD_TALK_FLATPAK" || echo ""
}

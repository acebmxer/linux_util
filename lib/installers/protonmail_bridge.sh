#!/bin/bash
# Proton Mail Bridge installer functions

# --- Proton Mail Bridge ---
# Bridge is a local IMAP/SMTP gateway that decrypts Proton Mail so ordinary
# clients (Thunderbird, Evolution, KMail, Claws Mail, neomutt) can talk to it.
#
# Flatpak on every distro, deliberately. Proton publishes only version-pinned
# .deb/.rpm URLs with no "latest" endpoint or apt/dnf repo to track, so a native
# install would mean scraping a download page that no longer exposes the links.
# Flathub's ch.protonmail.protonmail-bridge is the one channel that both
# resolves to the current release and self-updates.

_PROTONMAIL_BRIDGE_FLATPAK="ch.protonmail.protonmail-bridge"

check_protonmail_bridge() {
    _check_standard protonmail-bridge protonmail-bridge "$_PROTONMAIL_BRIDGE_FLATPAK"
}

install_protonmail_bridge() {
    info "Installing Proton Mail Bridge..."
    ensure_tools
    if ! ensure_flatpak; then
        error "Proton Mail Bridge is distributed as a Flatpak here, but Flatpak could not be set up."
        return 1
    fi
    sudo flatpak install -y flathub "$_PROTONMAIL_BRIDGE_FLATPAK" || return 1
    info "Proton Mail Bridge installed."
    info "Bridge requires a paid Proton Mail plan — it will not accept a free account."
    info "It also needs a running secret service (gnome-keyring, kwallet, or pass)"
    info "to store your credentials; without one, Bridge will fail to start."
    info "Point your mail client at the local IMAP/SMTP ports Bridge reports after you sign in."
}

uninstall_protonmail_bridge() {
    info "Uninstalling Proton Mail Bridge..."
    if flatpak_is_installed "$_PROTONMAIL_BRIDGE_FLATPAK"; then
        # --delete-data also clears ~/.var/app/<id>, where the Flatpak keeps the
        # bridge database and account credentials.
        flatpak uninstall -y --delete-data "$_PROTONMAIL_BRIDGE_FLATPAK" || true
    fi
    # Only present if a native package was installed outside this script.
    rm -rf "$HOME/.config/protonmail"
    rm -rf "$HOME/.cache/protonmail"
}

update_protonmail_bridge() {
    info "Updating Proton Mail Bridge..."
    if flatpak_is_installed "$_PROTONMAIL_BRIDGE_FLATPAK"; then
        flatpak update -y "$_PROTONMAIL_BRIDGE_FLATPAK"
    else
        warn "Proton Mail Bridge Flatpak not found; nothing to update."
        return 1
    fi
}

get_version_protonmail_bridge() {
    _ver_from_flatpak "$_PROTONMAIL_BRIDGE_FLATPAK" || _ver_from_pkg protonmail-bridge || echo ""
}

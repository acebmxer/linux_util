#!/bin/bash
# Betterbird installer functions

# --- Betterbird ---
# Thunderbird fork carrying fixes and features upstream has not merged.
# No distro ships it: Arch gets the AUR binary package, everything else gets
# the official Flathub build. Upstream publishes only tarballs otherwise, and a
# tarball drop would not self-update.

_BETTERBIRD_FLATPAK="eu.betterbird.Betterbird"
_BETTERBIRD_AUR="betterbird-bin"

check_betterbird() {
    _check_standard betterbird "$_BETTERBIRD_AUR" "$_BETTERBIRD_FLATPAK"
}

install_betterbird() {
    info "Installing Betterbird..."
    ensure_tools
    case "$DISTRO_FAMILY" in
        arch)
            aur_ensure "$_BETTERBIRD_AUR" || return 1
            ;;
        *)
            if ! ensure_flatpak; then
                error "Betterbird is not in any distro repo and requires Flatpak here, but Flatpak could not be set up."
                return 1
            fi
            flatpak install -y flathub "$_BETTERBIRD_FLATPAK" || return 1
            ;;
    esac
    info "Betterbird installed. It reads a Thunderbird profile directly, so back up"
    info "~/.thunderbird before pointing it at an existing profile — Betterbird can"
    info "upgrade a profile in ways Thunderbird will not read back."
}

uninstall_betterbird() {
    info "Uninstalling Betterbird..."
    if flatpak_is_installed "$_BETTERBIRD_FLATPAK"; then
        flatpak uninstall -y --delete-data "$_BETTERBIRD_FLATPAK" || true
    fi
    if [[ "$DISTRO_FAMILY" == "arch" ]] && pkg_check_installed "$_BETTERBIRD_AUR"; then
        aur_remove "$_BETTERBIRD_AUR" || true
    fi
    # Not touching ~/.thunderbird: Betterbird shares that profile directory with
    # Thunderbird, so removing it would delete a still-installed client's mail.
    rm -rf "$HOME/.betterbird"
}

update_betterbird() {
    info "Updating Betterbird..."
    if flatpak_is_installed "$_BETTERBIRD_FLATPAK"; then
        flatpak update -y "$_BETTERBIRD_FLATPAK"
    elif [[ "$DISTRO_FAMILY" == "arch" ]]; then
        aur_ensure "$_BETTERBIRD_AUR"
    else
        warn "Betterbird not found via Flatpak; nothing to update."
        return 1
    fi
}

get_version_betterbird() {
    _ver_from_flatpak "$_BETTERBIRD_FLATPAK" || _ver_from_pkg "$_BETTERBIRD_AUR" || echo ""
}

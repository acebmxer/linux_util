#!/bin/bash
# paru (AUR helper) installer functions
#
# paru is a Rust-based AUR helper for Arch-family distributions, an alternative
# to yay. Arch family only.
# Project: https://github.com/Morganamilo/paru

# --- paru ---

check_paru() { _check_standard paru paru ""; }

install_paru() {
    info "Installing paru (AUR helper)..."
    if [[ "$DISTRO_FAMILY" != "arch" ]]; then
        error "paru is only supported on Arch-family distributions."
        return 1
    fi
    # EndeavourOS and some derivatives package paru directly; otherwise build
    # from the AUR. makepkg pulls in rust/cargo as a build dependency.
    if sudo pacman -S --noconfirm --needed paru 2>/dev/null; then
        info "paru installed from repository."
    elif aur_build paru; then
        info "paru built and installed from the AUR."
    else
        error "Failed to install paru."
        return 1
    fi
}

uninstall_paru() {
    info "Uninstalling paru..."
    sudo pacman -Rs --noconfirm paru 2>/dev/null || true
}

update_paru() {
    info "Updating paru..."
    sudo pacman -S --noconfirm paru 2>/dev/null \
        || paru -S --noconfirm paru 2>/dev/null \
        || aur_build paru
}

get_version_paru() {
    _ver_from_cmd paru --version || echo ""
}

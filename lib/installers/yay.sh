#!/bin/bash
# yay (AUR helper) installer functions
#
# yay is an AUR helper for Arch-family distributions. It is not installed by
# the project but is used by it (see lib/aur.sh and pkg_full_upgrade), so this
# installer lets users add it explicitly. Arch family only.
# Project: https://github.com/Jguer/yay

# --- yay ---

check_yay() { _check_standard yay yay ""; }

install_yay() {
    info "Installing yay (AUR helper)..."
    if [[ "$DISTRO_FAMILY" != "arch" ]]; then
        error "yay is only supported on Arch-family distributions."
        return 1
    fi
    # Some Arch derivatives (Manjaro, EndeavourOS) ship yay in their own repos.
    # Prefer that; otherwise build from the AUR with the shared aur_build helper.
    if sudo pacman -S --noconfirm --needed yay 2>/dev/null; then
        info "yay installed from repository."
    elif aur_build yay; then
        info "yay built and installed from the AUR."
    else
        error "Failed to install yay."
        return 1
    fi
}

uninstall_yay() {
    info "Uninstalling yay..."
    sudo pacman -Rs --noconfirm yay 2>/dev/null || true
}

update_yay() {
    info "Updating yay..."
    sudo pacman -S --noconfirm yay 2>/dev/null \
        || yay -S --noconfirm yay 2>/dev/null \
        || aur_build yay
}

get_version_yay() {
    _ver_from_cmd yay --version || echo ""
}

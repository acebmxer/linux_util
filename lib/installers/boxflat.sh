#!/bin/bash
# Boxflat — settings manager for Moza Racing sim-racing hardware (GTK4/libadwaita)

# --- Boxflat ---

check_boxflat() { _check_standard boxflat "" io.github.lawstorant.boxflat; }

install_boxflat() {
    info "Installing Boxflat..."
    # Flatpak is the default (and officially supported) distribution method.
    if has_flatpak; then
        flatpak install -y flathub io.github.lawstorant.boxflat || return 1
    elif [[ "$DISTRO_FAMILY" == "arch" ]]; then
        # Fall back to the AUR git package when Flatpak is unavailable on Arch.
        if has_aur_helper; then
            aur_install boxflat-git || return 1
        else
            aur_build boxflat-git || return 1
        fi
    else
        error "Boxflat is distributed via Flatpak — enable the 'Flatpak Setup' system task first."
        return 1
    fi
    info "Boxflat installed."
}

uninstall_boxflat() {
    info "Uninstalling Boxflat..."
    if flatpak_is_installed "io.github.lawstorant.boxflat"; then
        flatpak uninstall -y io.github.lawstorant.boxflat
    elif [[ "$DISTRO_FAMILY" == "arch" ]]; then
        aur_remove boxflat-git 2>/dev/null || \
            sudo pacman -Rs --noconfirm boxflat-git 2>/dev/null || true
    fi
}

update_boxflat() {
    info "Updating Boxflat..."
    if flatpak_is_installed "io.github.lawstorant.boxflat"; then
        flatpak update -y io.github.lawstorant.boxflat
    elif [[ "$DISTRO_FAMILY" == "arch" ]]; then
        aur_ensure boxflat-git
    fi
}

get_version_boxflat() {
    _ver_from_flatpak io.github.lawstorant.boxflat || _ver_from_cmd boxflat || echo ""
}

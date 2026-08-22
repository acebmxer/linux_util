#!/bin/bash
# Boxflat — settings manager for Moza Racing sim-racing hardware (GTK4/libadwaita)

# --- Boxflat ---

check_boxflat() { _check_standard boxflat "" io.github.lawstorant.boxflat; }

install_boxflat() {
    info "Installing Boxflat..."
    # Flatpak is the default (and officially supported) distribution method.
    if [[ "$DISTRO_FAMILY" == "arch" ]] && arch_repo_has boxflat-git; then
        # Distro repo build (CachyOS and friends) beats Flatpak: signed, no runtime.
        repo_or_aur boxflat-git || return 1
    elif has_flatpak; then
        flatpak install -y flathub io.github.lawstorant.boxflat || return 1
    elif [[ "$DISTRO_FAMILY" == "arch" ]]; then
        # Fall back to the AUR git package when Flatpak is unavailable on Arch.
        repo_or_aur boxflat-git || return 1
    else
        error "Boxflat is distributed via Flatpak — run 'Flatpak Setup' from the Package Managers category first."
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
        repo_or_aur boxflat-git
    fi
}

get_version_boxflat() {
    _ver_from_flatpak io.github.lawstorant.boxflat || _ver_from_cmd boxflat || echo ""
}

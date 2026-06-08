#!/bin/bash
# DistroShelf — a graphical manager for Distrobox containers (GTK4/libadwaita)

# --- DistroShelf ---

check_distroshelf() { _check_standard "" "" com.ranfdev.DistroShelf; }

install_distroshelf() {
    info "Installing DistroShelf..."
    if ! has_flatpak; then
        error "DistroShelf is distributed via Flatpak — enable the 'Flatpak Setup' system task first."
        return 1
    fi
    flatpak install -y flathub com.ranfdev.DistroShelf || return 1
    command -v distrobox &>/dev/null || \
        warn "DistroShelf is a front-end for Distrobox — install Distrobox too (same subcategory)."
    info "DistroShelf installed."
}

uninstall_distroshelf() {
    info "Uninstalling DistroShelf..."
    if flatpak_is_installed "com.ranfdev.DistroShelf"; then
        flatpak uninstall -y com.ranfdev.DistroShelf
    fi
}

update_distroshelf() {
    info "Updating DistroShelf..."
    if flatpak_is_installed "com.ranfdev.DistroShelf"; then
        flatpak update -y com.ranfdev.DistroShelf
    fi
}

get_version_distroshelf() {
    _ver_from_flatpak com.ranfdev.DistroShelf || echo ""
}

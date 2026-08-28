#!/bin/bash
# DistroShelf — a graphical manager for Distrobox containers (GTK4/libadwaita)

# --- DistroShelf ---

check_distroshelf() { _check_standard "" "" com.ranfdev.DistroShelf; }

install_distroshelf() {
    info "Installing DistroShelf..."
    if ! has_flatpak; then
        error "DistroShelf is distributed via Flatpak — run 'Flatpak Setup' from the Package Managers category first."
        return 1
    fi
    sudo flatpak install -y flathub com.ranfdev.DistroShelf || return 1
    _have_cmd distrobox || \
        warn "DistroShelf is a front-end for Distrobox — install Distrobox too (same subcategory)."
    info "DistroShelf installed."
}

uninstall_distroshelf() {
    info "Uninstalling DistroShelf..."
    if flatpak_is_installed "com.ranfdev.DistroShelf"; then
        flatpak uninstall -y --user com.ranfdev.DistroShelf 2>/dev/null || \
            sudo flatpak uninstall -y --system com.ranfdev.DistroShelf
    fi
}

update_distroshelf() {
    info "Updating DistroShelf..."
    if flatpak_is_installed "com.ranfdev.DistroShelf"; then
        flatpak update -y --user com.ranfdev.DistroShelf 2>/dev/null || \
            sudo flatpak update -y --system com.ranfdev.DistroShelf
    fi
}

get_version_distroshelf() {
    _ver_from_flatpak com.ranfdev.DistroShelf || echo ""
}

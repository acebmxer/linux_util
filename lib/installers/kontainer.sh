#!/bin/bash
# Kontainer — a Kirigami/QML graphical manager for Distrobox containers (KDE)

# --- Kontainer ---

check_kontainer() { _check_standard "" "" io.github.DenysMb.Kontainer; }

install_kontainer() {
    info "Installing Kontainer..."
    if ! has_flatpak; then
        error "Kontainer is distributed via Flatpak — run 'Flatpak Setup' from the Package Managers category first."
        return 1
    fi
    sudo flatpak install -y flathub io.github.DenysMb.Kontainer || return 1
    _have_cmd distrobox || \
        warn "Kontainer is a front-end for Distrobox — install Distrobox too (same subcategory)."
    info "Kontainer installed."
}

uninstall_kontainer() {
    info "Uninstalling Kontainer..."
    if flatpak_is_installed "io.github.DenysMb.Kontainer"; then
        flatpak uninstall -y --user io.github.DenysMb.Kontainer 2>/dev/null || \
            sudo flatpak uninstall -y --system io.github.DenysMb.Kontainer
    fi
}

update_kontainer() {
    info "Updating Kontainer..."
    if flatpak_is_installed "io.github.DenysMb.Kontainer"; then
        flatpak update -y --user io.github.DenysMb.Kontainer 2>/dev/null || \
            sudo flatpak update -y --system io.github.DenysMb.Kontainer
    fi
}

get_version_kontainer() {
    _ver_from_flatpak io.github.DenysMb.Kontainer || echo ""
}

#!/bin/bash
# BoxBuddy — a graphical front-end for Distrobox (GTK4/libadwaita)

# --- BoxBuddy ---

check_boxbuddy() { _check_standard boxbuddy "" io.github.dvlv.boxbuddyrs; }

install_boxbuddy() {
    info "Installing BoxBuddy..."
    if ! has_flatpak; then
        error "BoxBuddy is distributed via Flatpak — enable the 'Flatpak Setup' system task first."
        return 1
    fi
    flatpak install -y flathub io.github.dvlv.boxbuddyrs || return 1
    _have_cmd distrobox || \
        warn "BoxBuddy is a front-end for Distrobox — install Distrobox too (same subcategory)."
    info "BoxBuddy installed."
}

uninstall_boxbuddy() {
    info "Uninstalling BoxBuddy..."
    if flatpak_is_installed "io.github.dvlv.boxbuddyrs"; then
        flatpak uninstall -y io.github.dvlv.boxbuddyrs
    fi
}

update_boxbuddy() {
    info "Updating BoxBuddy..."
    if flatpak_is_installed "io.github.dvlv.boxbuddyrs"; then
        flatpak update -y io.github.dvlv.boxbuddyrs
    fi
}

get_version_boxbuddy() {
    _ver_from_flatpak io.github.dvlv.boxbuddyrs || echo ""
}

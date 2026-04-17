#!/bin/bash
# Duplicati installer functions (Flatpak, all distros)

check_duplicati() { _check_standard "" "" com.duplicati.Duplicati; }

install_duplicati() {
    info "Installing Duplicati..."
    ensure_tools
    if ! has_flatpak; then
        error "Duplicati requires Flatpak. Install Flatpak first via the 'Flatpak Setup' system task."
        return 1
    fi
    flatpak install -y flathub com.duplicati.Duplicati || return 1
    info "Duplicati installed."
}

uninstall_duplicati() {
    info "Uninstalling Duplicati..."
    if flatpak_is_installed "com.duplicati.Duplicati"; then
        flatpak uninstall -y com.duplicati.Duplicati
    fi
}

update_duplicati() {
    info "Updating Duplicati..."
    if flatpak_is_installed "com.duplicati.Duplicati"; then
        flatpak update -y com.duplicati.Duplicati
    fi
}

get_version_duplicati() {
    _ver_from_flatpak com.duplicati.Duplicati || echo ""
}

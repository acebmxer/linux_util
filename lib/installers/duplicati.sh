#!/bin/bash
# Duplicati installer functions (Flatpak, all distros)

check_duplicati() { _check_standard "" "" com.duplicati.Duplicati; }

install_duplicati() {
    info "Installing Duplicati..."
    ensure_tools
    if ! has_flatpak; then
        error "Duplicati requires Flatpak. Install Flatpak first via 'Flatpak Setup' in the Package Managers category."
        return 1
    fi
    sudo flatpak install -y flathub com.duplicati.Duplicati || return 1
    info "Duplicati installed."
}

uninstall_duplicati() {
    info "Uninstalling Duplicati..."
    if flatpak_is_installed "com.duplicati.Duplicati"; then
        flatpak uninstall -y --user com.duplicati.Duplicati 2>/dev/null || \
            sudo flatpak uninstall -y --system com.duplicati.Duplicati
    fi
}

update_duplicati() {
    info "Updating Duplicati..."
    if flatpak_is_installed "com.duplicati.Duplicati"; then
        flatpak update -y --user com.duplicati.Duplicati 2>/dev/null || \
            sudo flatpak update -y --system com.duplicati.Duplicati
    fi
}

get_version_duplicati() {
    _ver_from_flatpak com.duplicati.Duplicati || echo ""
}

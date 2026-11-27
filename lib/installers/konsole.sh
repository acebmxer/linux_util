#!/bin/bash
# Konsole terminal emulator installer functions
#
# KDE's terminal, with tabs, split views and profiles. In the distro
# repositories everywhere, Alpine included. Rocky/Alma 8 and 9 carry it in
# EPEL as konsole5; Rocky/Alma 10 in EPEL as konsole.

# --- Konsole ---

_konsole_pkg() {
    if [[ "${DISTRO_FAMILY:-}" == "rhel" && "${DISTRO_VERSION_ID%%.*}" -lt 10 ]]; then
        echo konsole5
    else
        echo konsole
    fi
}

check_konsole() { _check_standard konsole "$(_konsole_pkg)" ""; }

install_konsole() {
    info "Installing Konsole..."
    ensure_epel
    pkg_install "$(_konsole_pkg)" || return 1
    info "Konsole installed."
}

# Profiles and colour schemes in ~/.local/share/konsole are kept.
uninstall_konsole() {
    info "Uninstalling Konsole..."
    pkg_remove "$(_konsole_pkg)"
}

update_konsole() {
    info "Updating Konsole..."
    pkg_upgrade "$(_konsole_pkg)"
}

# The program is not run: konsole --version needs a display on some builds.
get_version_konsole() { _ver_from_pkg "$(_konsole_pkg)" || echo ""; }

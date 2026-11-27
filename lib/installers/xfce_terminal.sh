#!/bin/bash
# Xfce Terminal installer functions
#
# Xfce's light terminal with tabs and a drop-down mode. In the distro
# repositories everywhere except Rocky/Alma 10 (EPEL 10 has no Xfce), where it
# is not offered. EPEL on Rocky/Alma 8 and 9.

# --- Xfce Terminal ---

check_xfce_terminal() { _check_standard xfce4-terminal xfce4-terminal ""; }

install_xfce_terminal() {
    info "Installing Xfce Terminal..."
    ensure_epel
    pkg_install xfce4-terminal || return 1
    info "Xfce Terminal installed."
}

uninstall_xfce_terminal() {
    info "Uninstalling Xfce Terminal..."
    pkg_remove xfce4-terminal
}

update_xfce_terminal() {
    info "Updating Xfce Terminal..."
    pkg_upgrade xfce4-terminal
}

get_version_xfce_terminal() { _ver_from_pkg xfce4-terminal || echo ""; }

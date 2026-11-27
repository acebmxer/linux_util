#!/bin/bash
# Terminator terminal emulator installer functions
#
# Terminal that splits one window into a grid of terminals. In the distro
# repositories everywhere, Alpine included (EPEL on RHEL clones).

# --- Terminator ---

check_terminator() { _check_standard terminator terminator ""; }

install_terminator() {
    info "Installing Terminator..."
    ensure_epel
    pkg_install terminator || return 1
    info "Terminator installed."
}

# Layouts in ~/.config/terminator are kept.
uninstall_terminator() {
    info "Uninstalling Terminator..."
    pkg_remove terminator
}

update_terminator() {
    info "Updating Terminator..."
    pkg_upgrade terminator
}

get_version_terminator() { _ver_from_pkg terminator || echo ""; }

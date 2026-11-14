#!/bin/bash
# kitty terminal emulator installer functions
#
# GPU-accelerated terminal. In the distro repositories everywhere, Alpine
# included (EPEL on RHEL clones).

# --- kitty ---

check_kitty() { _check_standard kitty kitty ""; }

install_kitty() {
    info "Installing kitty..."
    ensure_epel
    pkg_install kitty || return 1
    info "kitty installed."
}

uninstall_kitty() {
    info "Uninstalling kitty..."
    pkg_remove kitty
}

update_kitty() {
    info "Updating kitty..."
    pkg_upgrade kitty
}

get_version_kitty() { _ver_from_pkg kitty || _ver_from_cmd kitty || echo ""; }

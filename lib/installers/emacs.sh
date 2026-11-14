#!/bin/bash
# Emacs installer functions
#
# GNU Emacs with its graphical window. The emacs package in every supported
# distro's repositories, Alpine included.

# --- Emacs ---

check_emacs() { _check_standard emacs emacs ""; }

install_emacs() {
    info "Installing Emacs..."
    pkg_install emacs || return 1
    info "Emacs installed."
}

uninstall_emacs() {
    info "Uninstalling Emacs..."
    pkg_remove emacs
}

update_emacs() {
    info "Updating Emacs..."
    pkg_upgrade emacs
}

get_version_emacs() { _ver_from_pkg emacs || _ver_from_cmd emacs || echo ""; }

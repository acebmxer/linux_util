#!/bin/bash
# htop installer functions
#
# htop: interactive process viewer with colours, tree view and mouse support.
# Every supported distro packages it, Alpine too (EPEL on RHEL clones).

# --- htop ---

check_htop() { _check_standard htop htop ""; }

install_htop() {
    info "Installing htop..."
    ensure_epel
    pkg_install htop || return 1
    info "htop installed."
}

uninstall_htop() {
    info "Uninstalling htop..."
    pkg_remove htop
}

update_htop() {
    info "Updating htop..."
    pkg_upgrade htop
}

get_version_htop() { _ver_from_pkg htop || _ver_from_cmd htop || echo ""; }

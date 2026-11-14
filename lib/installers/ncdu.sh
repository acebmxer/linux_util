#!/bin/bash
# ncdu installer functions
#
# ncdu: terminal disk-usage browser; shows which folders use the space.
# In the distro repositories everywhere (EPEL on RHEL clones), Alpine included.

# --- ncdu ---

check_ncdu() { _check_standard ncdu ncdu ""; }

install_ncdu() {
    info "Installing ncdu..."
    ensure_epel
    pkg_install ncdu || return 1
    info "ncdu installed."
}

uninstall_ncdu() {
    info "Uninstalling ncdu..."
    pkg_remove ncdu
}

update_ncdu() {
    info "Updating ncdu..."
    pkg_upgrade ncdu
}

# ncdu prints "ncdu 2.7" (two parts), so the package version is read first.
get_version_ncdu() { _ver_from_pkg ncdu || echo ""; }

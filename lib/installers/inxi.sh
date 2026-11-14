#!/bin/bash
# inxi installer functions
#
# inxi: prints a readable summary of the hardware and system (CPU, GPU, disks,
# network, sensors). In the distro repositories everywhere (EPEL on RHEL
# clones); EPEL 10 does not carry it, so it is not offered on Rocky/Alma 10.

# --- inxi ---

check_inxi() { _check_standard inxi inxi ""; }

install_inxi() {
    info "Installing inxi..."
    ensure_epel
    pkg_install inxi || return 1
    info "inxi installed. Try: inxi -Fxz"
}

uninstall_inxi() {
    info "Uninstalling inxi..."
    pkg_remove inxi
}

update_inxi() {
    info "Updating inxi..."
    pkg_upgrade inxi
}

get_version_inxi() { _ver_from_pkg inxi || _ver_from_cmd inxi || echo ""; }

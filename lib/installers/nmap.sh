#!/bin/bash
# nmap installer functions
#
# Network scanner: finds hosts and open ports. In every supported distro's
# repositories (Alpine included).

# --- nmap ---

check_nmap() { _check_standard nmap nmap ""; }

install_nmap() {
    info "Installing nmap..."
    pkg_install nmap || return 1
    info "nmap installed."
}

uninstall_nmap() {
    info "Uninstalling nmap..."
    pkg_remove nmap
}

update_nmap() {
    info "Updating nmap..."
    pkg_upgrade nmap
}

get_version_nmap() { _ver_from_pkg nmap || _ver_from_cmd nmap || echo ""; }

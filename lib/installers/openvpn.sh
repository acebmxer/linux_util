#!/bin/bash
# OpenVPN installer functions
#
# The OpenVPN client from the distro's own repositories on every family
# (RHEL clones take it from EPEL). Import a provider's .ovpn file with
# `sudo openvpn --config file.ovpn`, or add it in the desktop's network
# settings (the network-manager-openvpn plugin is a separate package).

# --- OpenVPN ---

check_openvpn() { _check_standard openvpn openvpn ""; }

install_openvpn() {
    info "Installing OpenVPN..."
    pkg_refresh
    ensure_epel
    pkg_install openvpn || return 1
    info "OpenVPN installed."
}

# Connection profiles (.ovpn files) and /etc/openvpn are left in place.
uninstall_openvpn() {
    info "Uninstalling OpenVPN..."
    pkg_remove openvpn
}

update_openvpn() {
    info "Updating OpenVPN..."
    pkg_upgrade openvpn
}

get_version_openvpn() { _ver_from_pkg openvpn || echo ""; }

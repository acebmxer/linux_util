#!/bin/bash
# Ghostty terminal emulator installer functions
#
# Fast GPU-accelerated terminal. Installed from the distro's own package, which
# exists on Arch, openSUSE Tumbleweed and Ubuntu 26.04 and newer. Upstream
# publishes no Linux packages of its own (the .deb and Copr builds linked from
# its site are made by third parties, unsigned), so where the repositories do
# not carry it the installer says so and changes nothing. Not offered on
# Fedora, RHEL clones or Alpine.

# --- Ghostty ---

check_ghostty() { _check_standard ghostty ghostty ""; }

install_ghostty() {
    info "Installing Ghostty..."
    pkg_refresh
    if ! pkg_in_repo ghostty; then
        error "Ghostty is not in the ${DISTRO_NAME:-system} repositories, and upstream publishes no Linux packages. Nothing was changed. See https://ghostty.org/docs/install/binary"
        return 1
    fi
    pkg_install ghostty || return 1
    info "Ghostty installed."
}

uninstall_ghostty() {
    info "Uninstalling Ghostty..."
    pkg_remove ghostty
}

update_ghostty() {
    info "Updating Ghostty..."
    pkg_upgrade ghostty
}

get_version_ghostty() { _ver_from_pkg ghostty || _ver_from_cmd ghostty || echo ""; }

#!/bin/bash
# Clonezilla installer functions
#
# Clonezilla is mostly known as a live boot disk. Its tools also come as a
# package, which this installs: the distro package on Debian, Ubuntu and Arch.
# Fedora, RHEL clones and openSUSE have no package, so it is not offered there
# (use Ventoy to boot the live ISO). Run it as root (sudo clonezilla) on disks
# that are not mounted; cloning the running system's own disk needs the live
# version.

# --- Clonezilla ---

check_clonezilla() { _check_standard clonezilla clonezilla ""; }

install_clonezilla() {
    info "Installing Clonezilla..."
    pkg_install clonezilla || return 1
    info "Clonezilla installed."
}

uninstall_clonezilla() {
    info "Uninstalling Clonezilla..."
    pkg_remove clonezilla
}

update_clonezilla() {
    info "Updating Clonezilla..."
    pkg_upgrade clonezilla
}

get_version_clonezilla() { _ver_from_pkg clonezilla || echo ""; }

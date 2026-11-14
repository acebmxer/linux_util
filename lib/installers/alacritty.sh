#!/bin/bash
# Alacritty terminal emulator installer functions
#
# GPU-accelerated terminal configured by a text file. In the repositories of
# Debian, Ubuntu 23.04 and newer, Fedora, Arch, openSUSE and Alpine.
# Rocky/Alma/RHEL and Ubuntu 22.04 have no package and upstream publishes no
# binary or Flatpak, so it is not offered there.

# --- Alacritty ---

check_alacritty() { _check_standard alacritty alacritty ""; }

install_alacritty() {
    info "Installing Alacritty..."
    pkg_refresh
    if ! pkg_in_repo alacritty; then
        error "Alacritty is not in the ${DISTRO_NAME:-system} repositories. Nothing was changed."
        return 1
    fi
    pkg_install alacritty || return 1
    info "Alacritty installed."
}

uninstall_alacritty() {
    info "Uninstalling Alacritty..."
    pkg_remove alacritty
}

update_alacritty() {
    info "Updating Alacritty..."
    pkg_upgrade alacritty
}

get_version_alacritty() { _ver_from_pkg alacritty || _ver_from_cmd alacritty || echo ""; }

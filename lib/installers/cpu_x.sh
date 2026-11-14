#!/bin/bash
# CPU-X installer functions
#
# CPU-Z-style window showing the CPU, motherboard, memory, GPU and system.
# Distro package where the repositories have one (Debian, Ubuntu, Fedora, Arch,
# openSUSE), otherwise Flathub (Rocky/Alma/RHEL). Alpine has no package, so it
# is not offered there.

# --- CPU-X ---

_CPUX_FLATPAK="io.github.thetumultuousunicornofdarkness.cpu-x"

check_cpu_x() { _check_standard cpu-x cpu-x "$_CPUX_FLATPAK"; }

install_cpu_x() {
    info "Installing CPU-X..."
    native_or_flatpak_install "$_CPUX_FLATPAK" cpu-x || return 1
    info "CPU-X installed."
}

uninstall_cpu_x() {
    info "Uninstalling CPU-X..."
    native_or_flatpak_uninstall "$_CPUX_FLATPAK" cpu-x
}

update_cpu_x() {
    info "Updating CPU-X..."
    native_or_flatpak_update "$_CPUX_FLATPAK" cpu-x
}

get_version_cpu_x() { native_or_flatpak_version "$_CPUX_FLATPAK" cpu-x; }

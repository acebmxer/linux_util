#!/bin/bash
# Podman Desktop installer functions
#
# Graphical manager for Podman containers, pods and Kubernetes. The distro
# package on Arch; everywhere else Flathub. It drives a Podman engine, which the
# Podman entry installs. Not offered on Alpine.

# --- Podman Desktop ---

check_podman_desktop() { _check_standard podman-desktop podman-desktop io.podman_desktop.PodmanDesktop; }

install_podman_desktop() {
    info "Installing Podman Desktop..."
    native_or_flatpak_install io.podman_desktop.PodmanDesktop podman-desktop || return 1
    info "Podman Desktop installed."
}

uninstall_podman_desktop() {
    info "Uninstalling Podman Desktop..."
    native_or_flatpak_uninstall io.podman_desktop.PodmanDesktop podman-desktop
}

update_podman_desktop() {
    info "Updating Podman Desktop..."
    native_or_flatpak_update io.podman_desktop.PodmanDesktop podman-desktop
}

get_version_podman_desktop() { native_or_flatpak_version io.podman_desktop.PodmanDesktop podman-desktop; }

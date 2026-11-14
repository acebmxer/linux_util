#!/bin/bash
# Kodi media center installer functions
# Debian/Ubuntu and Arch: the distro package. Fedora and RHEL clones: RPM Fusion
# Free. openSUSE has none in its own repositories, so it uses Flathub, as does
# any system where the package is not offered.

# --- Kodi ---

check_kodi() { _check_standard kodi kodi tv.kodi.Kodi; }

install_kodi() {
    info "Installing Kodi..."
    case "$DISTRO_FAMILY" in
        fedora)
            ensure_rpmfusion free || return 1
            ;;
        rhel)
            # Not fatal: without RPM Fusion Kodi comes from Flathub below.
            ensure_rpmfusion free || warn "RPM Fusion could not be enabled; Kodi will come from Flathub."
            ;;
    esac
    native_or_flatpak_install tv.kodi.Kodi kodi || return 1
    info "Kodi installed."
}

uninstall_kodi() {
    info "Uninstalling Kodi..."
    native_or_flatpak_uninstall tv.kodi.Kodi kodi
}

update_kodi() {
    info "Updating Kodi..."
    native_or_flatpak_update tv.kodi.Kodi kodi
}

get_version_kodi() { native_or_flatpak_version tv.kodi.Kodi kodi; }

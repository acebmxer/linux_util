#!/bin/bash
# KDiskMark disk benchmark installer functions

# --- KDiskMark ---

check_kdiskmark() { _check_standard kdiskmark kdiskmark io.github.jonmagon.kdiskmark; }

# Debian 12, Ubuntu 22.04, openSUSE Leap 15 and RHEL without EPEL do not
# package kdiskmark; those fall back to the Flathub build.
_install_kdiskmark_flatpak() {
    warn "kdiskmark not in repos. Falling back to Flatpak..."
    if ensure_flatpak; then
        sudo flatpak install -y flathub io.github.jonmagon.kdiskmark
        return $?
    fi
    error "KDiskMark requires Flatpak on this system."
    return 1
}

install_kdiskmark() {
    info "Installing KDiskMark..."
    case "$DISTRO_FAMILY" in
        debian)
            pkg_install kdiskmark 2>/dev/null || { _install_kdiskmark_flatpak || return 1; }
            ;;
        fedora)
            pkg_install kdiskmark
            ;;
        rhel)
            pkg_install epel-release 2>/dev/null || true
            pkg_install kdiskmark 2>/dev/null || { _install_kdiskmark_flatpak || return 1; }
            ;;
        arch)
            pkg_install kdiskmark
            ;;
        suse)
            pkg_install kdiskmark 2>/dev/null || { _install_kdiskmark_flatpak || return 1; }
            ;;
    esac
    info "KDiskMark installed."
}

uninstall_kdiskmark() {
    info "Uninstalling KDiskMark..."
    if flatpak_is_installed "io.github.jonmagon.kdiskmark"; then
        flatpak uninstall -y --user io.github.jonmagon.kdiskmark 2>/dev/null || \
            sudo flatpak uninstall -y --system io.github.jonmagon.kdiskmark
    else
        case "$DISTRO_FAMILY" in
            debian)      pkg_remove kdiskmark ;;
            fedora|rhel) pkg_remove kdiskmark ;;
            arch)        pkg_remove kdiskmark ;;
            suse)        pkg_remove kdiskmark ;;
        esac
    fi
}

update_kdiskmark() {
    info "Updating KDiskMark..."
    if flatpak_is_installed "io.github.jonmagon.kdiskmark"; then
        flatpak update -y --user io.github.jonmagon.kdiskmark 2>/dev/null || \
            sudo flatpak update -y --system io.github.jonmagon.kdiskmark
    else
        case "$DISTRO_FAMILY" in
            debian)      sudo apt-get install -y --only-upgrade kdiskmark ;;
            fedora|rhel) pkg_upgrade kdiskmark ;;
            arch)        pkg_upgrade kdiskmark ;;
            suse)        pkg_upgrade kdiskmark ;;
        esac
    fi
}

get_version_kdiskmark() {
    local v
    # Debian/Ubuntu's package version carries a "+ds" repack suffix (3.1.3+ds)
    if v=$(_ver_from_pkg kdiskmark); then
        printf '%s\n' "${v%%+*}"
    else
        _ver_from_flatpak io.github.jonmagon.kdiskmark || echo ""
    fi
}

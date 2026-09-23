#!/bin/bash
# Krusader installer functions

# --- Krusader ---

check_krusader() { _check_standard krusader krusader ""; }

install_krusader() {
    info "Installing Krusader..."
    case "$DISTRO_FAMILY" in
        debian)      pkg_install krusader ;;
        fedora)      pkg_install krusader ;;
        rhel)
            pkg_install epel-release 2>/dev/null || true
            pkg_install krusader 2>/dev/null || {
                warn "krusader not available in repos for this RHEL-based distro."
                return 1
            }
            ;;
        arch)        pkg_install krusader ;;
        suse)        pkg_install krusader ;;
    esac
    info "Krusader installed."
}

uninstall_krusader() {
    info "Uninstalling Krusader..."
    case "$DISTRO_FAMILY" in
        debian)      pkg_remove krusader ;;
        fedora|rhel) pkg_remove krusader ;;
        arch)        pkg_remove krusader ;;
        suse)        pkg_remove krusader ;;
    esac
}

update_krusader() {
    info "Updating Krusader..."
    case "$DISTRO_FAMILY" in
        debian)      sudo apt-get install -y --only-upgrade krusader ;;
        fedora|rhel) pkg_upgrade krusader ;;
        arch)        pkg_upgrade krusader ;;
        suse)        pkg_upgrade krusader ;;
    esac
}

get_version_krusader() {
    _ver_from_pkg krusader || echo ""
}

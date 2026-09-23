#!/bin/bash
# Podman rootless container engine installer functions

# --- Podman ---

check_podman() { _check_standard podman podman ""; }

install_podman() {
    info "Installing Podman..."
    ensure_tools
    case "$DISTRO_FAMILY" in
        debian)
            pkg_install podman
            ;;
        fedora)
            pkg_install podman
            ;;
        rhel)
            # podman is in the AppStream repository on RHEL/Rocky/Alma/CentOS
            pkg_install podman
            ;;
        arch)
            pkg_install podman
            ;;
        suse)
            pkg_install podman
            ;;
    esac
    info "Podman installed."
    info "Podman is a daemonless, rootless container engine compatible with Docker CLI syntax."
    info "Use 'podman run', 'podman build', etc. as you would with Docker."
}

uninstall_podman() {
    info "Uninstalling Podman..."
    case "$DISTRO_FAMILY" in
        debian)      pkg_remove podman ;;
        fedora|rhel) pkg_remove podman ;;
        arch)        pkg_remove podman ;;
        suse)        pkg_remove podman ;;
    esac
    rm -rf "$HOME/.config/containers" "$HOME/.local/share/containers"
}

update_podman() {
    info "Updating Podman..."
    case "$DISTRO_FAMILY" in
        debian)      sudo apt-get install -y --only-upgrade podman ;;
        fedora|rhel) pkg_upgrade podman ;;
        arch)        pkg_upgrade podman ;;
        suse)        pkg_upgrade podman ;;
    esac
}

get_version_podman() {
    _ver_from_cmd podman || _ver_from_pkg podman || echo ""
}

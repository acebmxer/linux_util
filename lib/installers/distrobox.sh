#!/bin/bash
# Distrobox — run any Linux distribution inside your terminal

# --- Distrobox ---

check_distrobox() { _check_standard distrobox distrobox ""; }

install_distrobox() {
    info "Installing Distrobox..."
    ensure_tools
    local ok=1
    case "$DISTRO_FAMILY" in
        debian)
            pkg_install distrobox && ok=0
            ;;
        fedora)
            pkg_install distrobox && ok=0
            ;;
        rhel)
            # distrobox lives in EPEL on RHEL/Rocky/Alma/CentOS
            pkg_install epel-release 2>/dev/null || true
            pkg_install distrobox && ok=0
            ;;
        arch)
            pkg_install distrobox && ok=0
            ;;
        suse)
            pkg_install distrobox && ok=0
            ;;
    esac

    # Fall back to the upstream installer (rootless, into ~/.local) when no
    # native package is available or the package install failed.
    if (( ok != 0 )); then
        warn "Native package unavailable — using the official Distrobox installer (rootless, ~/.local)."
        curl -fsSL https://raw.githubusercontent.com/89luca89/distrobox/main/install | sh -s -- --prefix "$HOME/.local" || {
            error "Distrobox installation failed."
            return 1
        }
    fi

    # Distrobox needs a container backend; the native package usually pulls one in.
    if ! _have_cmd podman && ! _have_cmd docker; then
        warn "Distrobox needs Podman or Docker — install one (see the Development tab) before creating boxes."
    fi
    info "Distrobox installed. Create your first box with:"
    info "  distrobox create --name mybox --image ubuntu:24.04"
    info "Graphical front-ends are available in this subcategory: BoxBuddy and DistroShelf."
}

uninstall_distrobox() {
    info "Uninstalling Distrobox..."
    case "$DISTRO_FAMILY" in
        debian)      pkg_remove distrobox 2>/dev/null || true ;;
        fedora|rhel) pkg_remove distrobox 2>/dev/null || true ;;
        arch)        pkg_remove distrobox 2>/dev/null || true ;;
        suse)        pkg_remove distrobox 2>/dev/null || true ;;
    esac
    # Remove a rootless (curl-installer) copy if present.
    rm -f "$HOME/.local/bin/distrobox"* 2>/dev/null || true
}

update_distrobox() {
    info "Updating Distrobox..."
    # Rootless install (no native package) — re-run the upstream installer.
    if [[ -f "$HOME/.local/bin/distrobox" ]] && ! pkg_check_installed distrobox; then
        curl -fsSL https://raw.githubusercontent.com/89luca89/distrobox/main/install | sh -s -- --prefix "$HOME/.local"
        return $?
    fi
    case "$DISTRO_FAMILY" in
        debian)      sudo apt-get install -y --only-upgrade distrobox ;;
        fedora|rhel) pkg_upgrade distrobox ;;
        arch)        pkg_upgrade distrobox ;;
        suse)        pkg_upgrade distrobox ;;
    esac
}

get_version_distrobox() {
    _ver_from_cmd distrobox version 2>/dev/null || _ver_from_cmd distrobox --version 2>/dev/null || _ver_from_pkg distrobox || echo ""
}

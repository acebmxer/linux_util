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
            sudo apt install -y distrobox && ok=0
            ;;
        fedora)
            sudo "$PKG_MGR" install -y distrobox && ok=0
            ;;
        rhel)
            # distrobox lives in EPEL on RHEL/Rocky/Alma/CentOS
            sudo "$PKG_MGR" install -y epel-release 2>/dev/null || true
            sudo "$PKG_MGR" install -y distrobox && ok=0
            ;;
        arch)
            sudo pacman -S --noconfirm distrobox && ok=0
            ;;
        suse)
            sudo zypper install -y distrobox && ok=0
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
    if ! command -v podman &>/dev/null && ! command -v docker &>/dev/null; then
        warn "Distrobox needs Podman or Docker — install one (see the Development tab) before creating boxes."
    fi
    info "Distrobox installed. Create your first box with:"
    info "  distrobox create --name mybox --image ubuntu:24.04"
    info "Graphical front-ends are available in this subcategory: BoxBuddy and DistroShelf."
}

uninstall_distrobox() {
    info "Uninstalling Distrobox..."
    case "$DISTRO_FAMILY" in
        debian)      sudo apt purge --autoremove -y distrobox 2>/dev/null || true ;;
        fedora|rhel) sudo "$PKG_MGR" remove -y distrobox 2>/dev/null || true ;;
        arch)        sudo pacman -Rs --noconfirm distrobox 2>/dev/null || true ;;
        suse)        sudo zypper remove -y distrobox 2>/dev/null || true ;;
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
        fedora|rhel) sudo "$PKG_MGR" upgrade -y distrobox ;;
        arch)        sudo pacman -S --noconfirm distrobox ;;
        suse)        sudo zypper update -y distrobox ;;
    esac
}

get_version_distrobox() {
    _ver_from_cmd distrobox version 2>/dev/null || _ver_from_cmd distrobox --version 2>/dev/null || _ver_from_pkg distrobox || echo ""
}

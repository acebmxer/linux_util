#!/bin/bash
# Toolbx — containerized command-line environments on Podman (containertoolbx.org)

# --- Toolbx ---

# openSUSE's "toolbox" package is a different program (openSUSE/microos-toolbox)
# that installs the same /usr/bin/toolbox command, so a toolbox binary there is
# never Toolbx. Toolbx is not registered on openSUSE at all (lib/installers.sh).
check_toolbx() {
    [[ "$DISTRO_FAMILY" == "suse" ]] && return 1
    _check_standard toolbox "" ""
}

install_toolbx() {
    info "Installing Toolbx..."
    ensure_tools
    case "$DISTRO_FAMILY" in
        debian)
            # Debian/Ubuntu package it as podman-toolbox
            pkg_install podman-toolbox || return 1
            ;;
        fedora|rhel|arch)
            # toolbox is in AppStream on RHEL/Rocky/Alma/CentOS, extra on Arch
            pkg_install toolbox || return 1
            ;;
        suse)
            error "Toolbx is not packaged for openSUSE (its 'toolbox' package is a different tool). Use Distrobox instead (same category)."
            return 1
            ;;
        *)
            error "Unsupported distribution for Toolbx."
            return 1
            ;;
    esac

    # Toolbx only runs on Podman; the native packages normally pull it in.
    _have_cmd podman || \
        warn "Toolbx needs Podman — install it from this category before creating a toolbox."
    info "Toolbx installed. Create and enter your first toolbox with:"
    info "  toolbox create"
    info "  toolbox enter"
}

uninstall_toolbx() {
    info "Uninstalling Toolbx..."
    # Toolboxes are ordinary Podman containers and are left in place.
    case "$DISTRO_FAMILY" in
        debian)           pkg_remove podman-toolbox 2>/dev/null || true ;;
        fedora|rhel|arch) pkg_remove toolbox 2>/dev/null || true ;;
    esac
}

update_toolbx() {
    info "Updating Toolbx..."
    case "$DISTRO_FAMILY" in
        debian)           sudo apt-get install -y --only-upgrade podman-toolbox ;;
        fedora|rhel|arch) pkg_upgrade toolbox ;;
    esac
}

get_version_toolbx() {
    # "toolbox version 0.3" — Toolbx versions are not always X.Y.Z (0.3,
    # 0.0.99.3), so _ver_from_cmd's semver match would miss or truncate them.
    local bin v
    bin=$(_native_command toolbox) || { echo ""; return 0; }
    v=$("$bin" --version 2>/dev/null | awk '{print $NF}')
    echo "$v"
}

#!/bin/bash
# Snap (snapd) installer functions
#
# Snap is Canonical's cross-distro, sandboxed package manager. It runs
# alongside the native package manager. Availability by family:
#   debian  — native package
#   fedora  — native package
#   rhel    — via EPEL
#   suse    — via the system:snappy OBS repo
#   arch    — via the AUR (snapd)
# Project: https://snapcraft.io

# --- Snap ---

check_snap() { _have_cmd snap; }

# Enable the snapd socket and create the /snap symlink classic snaps expect.
_snap_post_install() {
    sudo systemctl enable --now snapd.socket 2>/dev/null || true
    # AppArmor service exists on some distros (openSUSE, Arch) and is needed for confinement.
    sudo systemctl enable --now snapd.apparmor.service 2>/dev/null || true
    # Classic snaps require /snap; Ubuntu already has it, others need the symlink.
    if [[ ! -e /snap && -d /var/lib/snapd/snap ]]; then
        sudo ln -s /var/lib/snapd/snap /snap 2>/dev/null || true
    fi
}

install_snap() {
    info "Installing snapd..."
    ensure_tools
    case "$DISTRO_FAMILY" in
        debian)
            pkg_install snapd || { error "Failed to install snapd."; return 1; }
            ;;
        fedora)
            pkg_install snapd || { error "Failed to install snapd."; return 1; }
            ;;
        rhel)
            pkg_install epel-release 2>/dev/null || true
            pkg_install snapd || { error "Failed to install snapd."; return 1; }
            ;;
        suse)
            # snapd lives in the system:snappy OBS repo, which differs by product.
            local snappy_url
            if [[ "$DISTRO_ID" == "opensuse-tumbleweed" ]]; then
                snappy_url="https://download.opensuse.org/repositories/system:/snappy/openSUSE_Tumbleweed"
            else
                snappy_url="https://download.opensuse.org/repositories/system:/snappy/openSUSE_Leap_\$releasever"
            fi
            sudo zypper addrepo --refresh "$snappy_url" snappy 2>/dev/null || true
            sudo zypper --gpg-auto-import-keys refresh
            sudo zypper dup --from snappy -y 2>/dev/null || true
            pkg_install snapd || { error "Failed to install snapd."; return 1; }
            ;;
        arch)
            # snapd is not in the official Arch repos; install it from the AUR.
            repo_or_aur snapd || { error "Failed to install snapd from the AUR."; return 1; }
            ;;
        *)
            error "snapd is not supported on this distribution."
            return 1
            ;;
    esac
    _snap_post_install
    info "snapd installed. You may need to log out/in for snap paths to load. Try: snap install <package>"
}

uninstall_snap() {
    info "Uninstalling snapd..."
    warn "All installed snaps will be removed."
    sudo systemctl disable --now snapd.socket 2>/dev/null || true
    [[ -L /snap ]] && sudo rm -f /snap 2>/dev/null || true
    case "$DISTRO_FAMILY" in
        debian)      pkg_remove snapd 2>/dev/null || true ;;
        fedora|rhel) pkg_remove snapd 2>/dev/null || true ;;
        suse)        pkg_remove snapd 2>/dev/null || true
                     sudo zypper removerepo snappy 2>/dev/null || true ;;
        arch)        pkg_remove snapd 2>/dev/null || true ;;
    esac
}

update_snap() {
    info "Refreshing installed snaps..."
    sudo snap refresh
}

get_version_snap() {
    _run_native snap version 2>/dev/null | awk '/^snapd/{print $2; exit}' || echo ""
}

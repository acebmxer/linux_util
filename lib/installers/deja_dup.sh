#!/bin/bash
# Déjà Dup installer functions (not supported on RHEL family)

check_deja_dup() {
    _have_cmd deja-dup
}

install_deja_dup() {
    echo "Installing Déjà Dup..."
    case "$DISTRO_FAMILY" in
        debian)
            sudo apt-get install -y deja-dup || return 1
            ;;
        fedora)
            sudo dnf install -y deja-dup || return 1
            ;;
        arch)
            pkg_install deja-dup || return 1
            ;;
        suse)
            sudo zypper install -y deja-dup || return 1
            ;;
        rhel)
            warn "Déjà Dup is not available for RHEL-based systems."
            return 1
            ;;
        *)
            warn "Unsupported distribution for Déjà Dup."
            return 1
            ;;
    esac
    echo "Déjà Dup installed successfully."
}

uninstall_deja_dup() {
    echo "Uninstalling Déjà Dup..."
    case "$DISTRO_FAMILY" in
        debian)
            sudo apt-get remove -y deja-dup || true
            ;;
        fedora)
            sudo dnf remove -y deja-dup || true
            ;;
        arch)
            sudo pacman -Rs --noconfirm deja-dup 2>/dev/null || true
            ;;
        suse)
            sudo zypper remove -y deja-dup || true
            ;;
    esac
}

update_deja_dup() {
    echo "Updating Déjà Dup..."
    case "$DISTRO_FAMILY" in
        debian)
            sudo apt-get install --only-upgrade -y deja-dup || true
            ;;
        fedora)
            sudo dnf upgrade -y deja-dup || true
            ;;
        arch)
            pkg_upgrade deja-dup
            ;;
        suse)
            sudo zypper update -y deja-dup || true
            ;;
    esac
}

get_version_deja_dup() {
    _ver_from_cmd deja-dup || _ver_from_pkg deja-dup || echo ""
}

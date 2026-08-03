#!/bin/bash
# Kup Backup installer functions (KDE backup tool, not supported on RHEL family)
#
# Fedora has no official package — install comes from the zawertun/kde-kup Copr
# (package name there is kde-kup). Other distros ship it natively:
# Debian/Ubuntu as kup-backup, Arch and openSUSE as kup.

KUP_FEDORA_COPR="zawertun/kde-kup"

check_kup() {
    _have_cmd kup-daemon
}

install_kup() {
    echo "Installing Kup Backup..."
    case "$DISTRO_FAMILY" in
        debian)
            sudo apt-get install -y kup-backup || return 1
            ;;
        fedora)
            # Not in the official repos — enable the community Copr first
            sudo "$PKG_MGR" install -y 'dnf-command(copr)' 2>/dev/null || true
            sudo dnf copr enable -y "$KUP_FEDORA_COPR" || {
                error "Failed to enable the $KUP_FEDORA_COPR Copr."
                return 1
            }
            sudo dnf install -y kde-kup || return 1
            # bup enables Kup's incremental (versioned) backup mode
            sudo dnf install -y bup 2>/dev/null || \
                warn "Could not install 'bup' — incremental backups will be unavailable (synchronized folder mode still works)."
            ;;
        arch)
            pkg_install kup || return 1
            # bup is an optional dependency enabling incremental backups
            pkg_install bup 2>/dev/null || \
                warn "Could not install 'bup' — incremental backups will be unavailable (synchronized folder mode still works)."
            ;;
        suse)
            sudo zypper install -y kup || return 1
            ;;
        rhel)
            warn "Kup is not available for RHEL-based systems."
            return 1
            ;;
        *)
            warn "Unsupported distribution for Kup."
            return 1
            ;;
    esac
    echo "Kup installed successfully."
    echo "Configure backup plans in System Settings > Backups (or run 'kcmshell6 kcm_kup')."
}

uninstall_kup() {
    echo "Uninstalling Kup Backup..."
    case "$DISTRO_FAMILY" in
        debian)
            sudo apt-get remove -y kup-backup 2>/dev/null || true
            ;;
        fedora)
            sudo dnf remove -y kde-kup 2>/dev/null || true
            sudo dnf copr disable -y "$KUP_FEDORA_COPR" 2>/dev/null || true
            ;;
        arch)
            sudo pacman -Rs --noconfirm kup 2>/dev/null || true
            ;;
        suse)
            sudo zypper remove -y kup 2>/dev/null || true
            ;;
    esac
}

update_kup() {
    echo "Updating Kup Backup..."
    case "$DISTRO_FAMILY" in
        debian)
            sudo apt-get install --only-upgrade -y kup-backup || true
            ;;
        fedora)
            sudo dnf upgrade -y kde-kup || true
            ;;
        arch)
            pkg_upgrade kup
            ;;
        suse)
            sudo zypper update -y kup || true
            ;;
    esac
}

get_version_kup() {
    case "$DISTRO_FAMILY" in
        debian) _ver_from_pkg kup-backup || echo "" ;;
        fedora) _ver_from_pkg kde-kup || echo "" ;;
        *)      _ver_from_pkg kup || echo "" ;;
    esac
}

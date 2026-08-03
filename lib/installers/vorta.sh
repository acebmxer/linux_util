#!/bin/bash
# Vorta + BorgBackup installer functions

check_vorta() {
    _have_cmd vorta
}

install_vorta() {
    echo "Installing BorgBackup and Vorta..."
    case "$DISTRO_FAMILY" in
        debian)
            sudo apt-get install -y borgbackup vorta || return 1
            ;;
        fedora)
            sudo dnf install -y borgbackup vorta || return 1
            ;;
        arch)
            pkg_install borg vorta || return 1
            ;;
        suse)
            sudo zypper install -y borgbackup vorta || return 1
            ;;
        rhel)
            # borg is in EPEL; vorta is not packaged for RHEL
            if ! rpm -q epel-release &>/dev/null; then
                warn "EPEL repository is required for BorgBackup. Installing EPEL..."
                sudo dnf install -y epel-release || return 1
            fi
            sudo dnf install -y borgbackup || return 1
            warn "Vorta is not available in EPEL. Only BorgBackup (CLI) was installed."
            warn "You can use 'borg' from the terminal to manage backups."
            ;;
        *)
            warn "Unsupported distribution for Vorta."
            return 1
            ;;
    esac
    echo "Installation complete."
}

uninstall_vorta() {
    echo "Uninstalling Vorta and BorgBackup..."
    case "$DISTRO_FAMILY" in
        debian)
            sudo apt-get remove -y vorta borgbackup 2>/dev/null || true
            ;;
        fedora)
            sudo dnf remove -y vorta borgbackup 2>/dev/null || true
            ;;
        arch)
            sudo pacman -Rs --noconfirm vorta borg 2>/dev/null || true
            ;;
        suse)
            sudo zypper remove -y vorta borgbackup 2>/dev/null || true
            ;;
        rhel)
            sudo dnf remove -y borgbackup 2>/dev/null || true
            ;;
    esac
}

update_vorta() {
    echo "Updating Vorta and BorgBackup..."
    case "$DISTRO_FAMILY" in
        debian)
            sudo apt-get install --only-upgrade -y borgbackup vorta || true
            ;;
        fedora)
            sudo dnf upgrade -y borgbackup vorta || true
            ;;
        arch)
            pkg_upgrade borg vorta
            ;;
        suse)
            sudo zypper update -y borgbackup vorta || true
            ;;
        rhel)
            sudo dnf upgrade -y borgbackup || true
            ;;
    esac
}

get_version_vorta() {
    _ver_from_cmd vorta || _ver_from_pkg vorta || _ver_from_cmd borg || echo ""
}

#!/bin/bash
# ClamAV antivirus installer functions

# --- ClamAV ---

check_clamav() { _check_standard clamscan clamav ""; }

install_clamav() {
    info "Installing ClamAV..."
    ensure_tools
    case "$DISTRO_FAMILY" in
        debian)
            sudo apt install -y clamav clamav-daemon clamtk
            ;;
        fedora)
            sudo "$PKG_MGR" install -y clamav clamav-update clamd clamtk
            ;;
        rhel)
            sudo "$PKG_MGR" install -y epel-release 2>/dev/null || true
            sudo "$PKG_MGR" install -y clamav clamav-update clamd clamtk
            ;;
        arch)
            sudo pacman -S --noconfirm clamav clamtk
            ;;
        suse)
            sudo zypper install -y clamav clamtk
            ;;
    esac

    # Update virus definitions
    info "Updating ClamAV virus definitions..."
    sudo systemctl stop clamav-freshclam 2>/dev/null || \
        sudo systemctl stop clamav-daemon 2>/dev/null || true
    sudo freshclam 2>/dev/null || true

    # Enable freshclam update service and the scan daemon
    sudo systemctl enable --now clamav-freshclam 2>/dev/null || true
    case "$DISTRO_FAMILY" in
        debian)
            sudo systemctl enable --now clamav-daemon 2>/dev/null || true
            ;;
        arch)
            sudo systemctl enable --now clamav-daemon.service 2>/dev/null || true
            # Allow clamd to read user home directories
            sudo usermod -aG "$(id -gn)" clamav 2>/dev/null || true
            ;;
        fedora|rhel)
            sudo systemctl enable --now clamd@scan 2>/dev/null || \
                sudo systemctl enable --now clamd 2>/dev/null || true
            ;;
    esac

    info "ClamAV installed."
    info "Run 'clamscan -r /path/to/scan' to scan a directory."
    info "Run 'sudo freshclam' to update virus definitions manually."
}

uninstall_clamav() {
    info "Uninstalling ClamAV..."
    sudo systemctl stop clamav-freshclam clamav-daemon clamd 2>/dev/null || true
    sudo systemctl disable clamav-freshclam clamav-daemon clamd 2>/dev/null || true
    case "$DISTRO_FAMILY" in
        debian)
            sudo apt purge --autoremove -y clamav clamav-daemon clamav-freshclam clamtk
            ;;
        fedora|rhel)
            sudo "$PKG_MGR" remove -y clamav clamav-update clamd clamtk
            ;;
        arch)
            sudo pacman -Rs --noconfirm clamtk clamav
            ;;
        suse)
            sudo zypper remove -y clamtk clamav
            ;;
    esac
}

update_clamav() {
    info "Updating ClamAV and ClamTk..."
    case "$DISTRO_FAMILY" in
        debian)
            sudo apt-get install -y --only-upgrade clamav clamav-daemon
            # Install clamtk if missing, otherwise upgrade it
            sudo apt-get install -y clamtk
            ;;
        fedora|rhel)
            sudo "$PKG_MGR" upgrade -y clamav clamav-update
            sudo "$PKG_MGR" install -y clamtk
            ;;
        arch)
            sudo pacman -S --noconfirm clamav clamtk
            ;;
        suse)
            sudo zypper update -y clamav
            sudo zypper install -y clamtk
            ;;
    esac
    # Stop the update service before running freshclam manually to avoid log lock conflict
    sudo systemctl stop clamav-freshclam 2>/dev/null || true
    sudo freshclam 2>/dev/null || true
    sudo systemctl start clamav-freshclam 2>/dev/null || true
}

get_version_clamav() {
    _ver_from_cmd clamscan || _ver_from_pkg clamav || echo ""
}

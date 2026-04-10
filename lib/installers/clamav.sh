#!/bin/bash
# ClamAV antivirus installer functions

# --- ClamAV ---

check_clamav() { _check_standard clamscan clamav ""; }

install_clamav() {
    info "Installing ClamAV..."
    ensure_tools
    case "$DISTRO_FAMILY" in
        debian)
            sudo apt install -y clamav clamav-daemon
            ;;
        fedora)
            sudo "$PKG_MGR" install -y clamav clamav-update clamd
            ;;
        rhel)
            sudo "$PKG_MGR" install -y epel-release 2>/dev/null || true
            sudo "$PKG_MGR" install -y clamav clamav-update clamd
            ;;
        arch)
            sudo pacman -S --noconfirm clamav
            ;;
        suse)
            sudo zypper install -y clamav
            ;;
    esac

    # Update virus definitions
    info "Updating ClamAV virus definitions..."
    sudo systemctl stop clamav-freshclam 2>/dev/null || \
        sudo systemctl stop clamav-daemon 2>/dev/null || true
    sudo freshclam 2>/dev/null || true

    # Enable the freshclam update service
    sudo systemctl enable --now clamav-freshclam 2>/dev/null || true

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
            sudo apt purge --autoremove -y clamav clamav-daemon clamav-freshclam
            ;;
        fedora|rhel)
            sudo "$PKG_MGR" remove -y clamav clamav-update clamd
            ;;
        arch)
            sudo pacman -Rs --noconfirm clamav
            ;;
        suse)
            sudo zypper remove -y clamav
            ;;
    esac
}

update_clamav() {
    info "Updating ClamAV..."
    case "$DISTRO_FAMILY" in
        debian)      sudo apt-get install -y --only-upgrade clamav clamav-daemon ;;
        fedora|rhel) sudo "$PKG_MGR" upgrade -y clamav clamav-update ;;
        arch)        sudo pacman -S --noconfirm clamav ;;
        suse)        sudo zypper update -y clamav ;;
    esac
    sudo freshclam 2>/dev/null || true
}

get_version_clamav() {
    _ver_from_cmd clamscan || _ver_from_pkg clamav || echo ""
}

#!/bin/bash
# AnyDesk remote desktop installer functions

# --- AnyDesk ---

check_anydesk() { _check_standard anydesk anydesk "" anydesk-bin; }

install_anydesk() {
    info "Installing AnyDesk..."
    ensure_tools
    case "$DISTRO_FAMILY" in
        debian)
            # Official AnyDesk apt repository
            wget -qO - https://keys.anydesk.com/repos/DEB-GPG-KEY | \
                sudo gpg --dearmor -o /etc/apt/keyrings/anydesk.gpg
            echo "deb [signed-by=/etc/apt/keyrings/anydesk.gpg] http://deb.anydesk.com/ all main" | \
                sudo tee /etc/apt/sources.list.d/anydesk.list > /dev/null
            sudo apt update
            sudo apt install -y anydesk
            ;;
        fedora|rhel)
            # AnyDesk RPM repository
            sudo tee /etc/yum.repos.d/anydesk.repo > /dev/null <<'REPO'
[anydesk]
name=AnyDesk RHEL - stable
baseurl=http://rpm.anydesk.com/rhel/$releasever/$basearch/
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://keys.anydesk.com/repos/RPM-GPG-KEY
REPO
            sudo "$PKG_MGR" install -y anydesk
            ;;
        arch)
            # repos -> Flathub -> AUR (AUR is disabled by default).
            arch_install_ordered "anydesk-bin" "com.anydesk.Anydesk" "" "anydesk-bin"
            ;;
        suse)
            sudo zypper addrepo -f "https://rpm.anydesk.com/opensuse/anydesk.repo" anydesk 2>/dev/null || true
            sudo zypper refresh
            sudo zypper install -y anydesk 2>/dev/null || {
                error "AnyDesk installation failed on openSUSE. Check https://anydesk.com/en/downloads/linux for manual install."
                return 1
            }
            ;;
    esac
    info "AnyDesk installed."
}

uninstall_anydesk() {
    info "Uninstalling AnyDesk..."
    case "$DISTRO_FAMILY" in
        debian)
            sudo apt purge --autoremove -y anydesk
            sudo rm -f /etc/apt/sources.list.d/anydesk.list
            sudo rm -f /etc/apt/keyrings/anydesk.gpg
            ;;
        fedora|rhel)
            sudo "$PKG_MGR" remove -y anydesk
            sudo rm -f /etc/yum.repos.d/anydesk.repo
            ;;
        arch)
            aur_remove anydesk-bin 2>/dev/null || \
                sudo pacman -Rs --noconfirm anydesk 2>/dev/null || true
            ;;
        suse)
            sudo zypper remove -y anydesk
            sudo zypper removerepo anydesk 2>/dev/null || true
            ;;
    esac
    rm -rf "$HOME/.anydesk"
}

update_anydesk() {
    info "Updating AnyDesk..."
    case "$DISTRO_FAMILY" in
        debian)      sudo apt-get install -y --only-upgrade anydesk ;;
        fedora|rhel) sudo "$PKG_MGR" upgrade -y anydesk ;;
        arch)        repo_or_aur anydesk-bin ;;
        suse)        sudo zypper update -y anydesk ;;
    esac
}

get_version_anydesk() {
    _ver_from_cmd anydesk --version || _ver_from_pkg anydesk || echo ""
}

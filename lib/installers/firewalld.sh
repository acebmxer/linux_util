#!/bin/bash
# firewalld installer functions (daemon + firewall-config GUI)

# --- firewalld ---

check_firewalld() { _check_standard firewall-cmd firewalld ""; }

install_firewalld() {
    info "Installing firewalld..."
    # Only one firewall manager should own netfilter at a time
    if _have_cmd ufw && sudo ufw status 2>/dev/null | grep -q "Status: active"; then
        warn "UFW is active — disabling it so firewalld can manage the firewall."
        sudo ufw --force disable 2>/dev/null || true
        sudo systemctl disable ufw 2>/dev/null || true
    fi
    case "$DISTRO_FAMILY" in
        debian)
            sudo apt install -y firewalld
            ;;
        fedora|rhel)
            sudo "$PKG_MGR" install -y firewalld
            ;;
        arch)
            sudo pacman -S --noconfirm firewalld
            ;;
        suse)
            sudo zypper install -y firewalld
            ;;
    esac
    sudo systemctl enable --now firewalld
    info "firewalld installed and enabled. Manage it with firewall-cmd or the firewall-config GUI."
}

uninstall_firewalld() {
    info "Uninstalling firewalld..."
    sudo systemctl disable --now firewalld 2>/dev/null || true
    case "$DISTRO_FAMILY" in
        debian)      sudo apt purge --autoremove -y firewalld ;;
        fedora|rhel) sudo "$PKG_MGR" remove -y firewalld ;;
        arch)        sudo pacman -Rs --noconfirm firewalld ;;
        suse)        sudo zypper remove -y firewalld ;;
    esac
}

update_firewalld() {
    info "Updating firewalld..."
    case "$DISTRO_FAMILY" in
        debian)      sudo apt-get install -y --only-upgrade firewalld ;;
        fedora|rhel) sudo "$PKG_MGR" upgrade -y firewalld ;;
        arch)        sudo pacman -S --noconfirm firewalld ;;
        suse)        sudo zypper update -y firewalld ;;
    esac
}

get_version_firewalld() {
    _ver_from_pkg firewalld || echo ""
}

# --- firewall-config (GUI) ---

check_firewall_config() { _check_standard firewall-config firewall-config ""; }

install_firewall_config() {
    info "Installing firewall-config (graphical frontend for firewalld)..."
    # firewall-config is only a frontend — make sure firewalld itself is installed first
    if ! check_firewalld; then
        install_firewalld || return 1
    fi
    case "$DISTRO_FAMILY" in
        debian)
            sudo apt install -y firewall-config
            ;;
        fedora|rhel)
            sudo "$PKG_MGR" install -y firewall-config
            ;;
        arch)
            # firewall-config ships inside the firewalld package; gtk3 is its optional GUI dependency
            sudo pacman -S --noconfirm --needed gtk3
            ;;
        suse)
            sudo zypper install -y firewall-config
            ;;
    esac
    info "firewall-config installed."
}

uninstall_firewall_config() {
    info "Uninstalling firewall-config..."
    case "$DISTRO_FAMILY" in
        debian)      sudo apt purge --autoremove -y firewall-config ;;
        fedora|rhel) sudo "$PKG_MGR" remove -y firewall-config ;;
        arch)        warn "firewall-config is bundled with the firewalld package on Arch — uninstall firewalld to remove it." ;;
        suse)        sudo zypper remove -y firewall-config ;;
    esac
}

update_firewall_config() {
    info "Updating firewall-config..."
    case "$DISTRO_FAMILY" in
        debian)      sudo apt-get install -y --only-upgrade firewall-config ;;
        fedora|rhel) sudo "$PKG_MGR" upgrade -y firewall-config ;;
        arch)        sudo pacman -S --noconfirm firewalld ;;
        suse)        sudo zypper update -y firewall-config ;;
    esac
}

get_version_firewall_config() {
    _ver_from_pkg firewall-config || _ver_from_pkg firewalld || echo ""
}

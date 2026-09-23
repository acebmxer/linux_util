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
            pkg_install firewalld
            ;;
        fedora|rhel)
            pkg_install firewalld
            ;;
        arch)
            pkg_install firewalld
            ;;
        suse)
            pkg_install firewalld
            ;;
    esac
    sudo systemctl enable --now firewalld
    info "firewalld installed and enabled. Manage it with firewall-cmd or the firewall-config GUI."
}

uninstall_firewalld() {
    info "Uninstalling firewalld..."
    sudo systemctl disable --now firewalld 2>/dev/null || true
    case "$DISTRO_FAMILY" in
        debian)      pkg_remove firewalld ;;
        fedora|rhel) pkg_remove firewalld ;;
        arch)        pkg_remove firewalld ;;
        suse)        pkg_remove firewalld ;;
    esac
}

update_firewalld() {
    info "Updating firewalld..."
    case "$DISTRO_FAMILY" in
        debian)      sudo apt-get install -y --only-upgrade firewalld ;;
        fedora|rhel) pkg_upgrade firewalld ;;
        arch)        pkg_upgrade firewalld ;;
        suse)        pkg_upgrade firewalld ;;
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
            pkg_install firewall-config
            ;;
        fedora|rhel)
            pkg_install firewall-config
            ;;
        arch)
            # firewall-config ships inside the firewalld package; gtk3 is its optional GUI dependency
            pkg_install --needed gtk3
            ;;
        suse)
            pkg_install firewall-config
            ;;
    esac
    info "firewall-config installed."
}

uninstall_firewall_config() {
    info "Uninstalling firewall-config..."
    case "$DISTRO_FAMILY" in
        debian)      pkg_remove firewall-config ;;
        fedora|rhel) pkg_remove firewall-config ;;
        arch)        warn "firewall-config is bundled with the firewalld package on Arch — uninstall firewalld to remove it." ;;
        suse)        pkg_remove firewall-config ;;
    esac
}

update_firewall_config() {
    info "Updating firewall-config..."
    case "$DISTRO_FAMILY" in
        debian)      sudo apt-get install -y --only-upgrade firewall-config ;;
        fedora|rhel) pkg_upgrade firewall-config ;;
        arch)        pkg_upgrade firewalld ;;
        suse)        pkg_upgrade firewall-config ;;
    esac
}

get_version_firewall_config() {
    _ver_from_pkg firewall-config || _ver_from_pkg firewalld || echo ""
}

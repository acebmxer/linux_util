#!/bin/bash
# Cockpit installer functions
# Web-based server management console reachable at https://<host>:9090

# --- Cockpit ---
check_cockpit() {
    pkg_check_installed cockpit && return 0
    systemctl list-unit-files 2>/dev/null | grep -q '^cockpit\.socket'
}

# Open Cockpit's port (9090/tcp) in whichever firewall is active.
_cockpit_open_firewall() {
    if command -v ufw &>/dev/null && ufw status 2>/dev/null | grep -q "^Status: active"; then
        if [[ "${DRY_RUN:-false}" == "true" ]]; then
            info "[Dry run] Would run: sudo ufw allow 9090/tcp"
        else
            sudo ufw allow 9090/tcp && info "UFW: opened 9090/tcp"
        fi
    elif command -v firewall-cmd &>/dev/null && sudo firewall-cmd --state &>/dev/null; then
        if [[ "${DRY_RUN:-false}" == "true" ]]; then
            info "[Dry run] Would run: sudo firewall-cmd --permanent --add-service=cockpit && sudo firewall-cmd --reload"
        else
            sudo firewall-cmd --permanent --add-service=cockpit && \
                sudo firewall-cmd --reload && info "firewalld: opened cockpit service (9090/tcp)"
        fi
    fi
}

install_cockpit() {
    info "Installing Cockpit..."
    case "$DISTRO_FAMILY" in
        debian)
            sudo apt install -y cockpit
            ;;
        fedora|rhel)
            sudo "$PKG_MGR" install -y cockpit
            ;;
        arch)
            sudo pacman -S --noconfirm cockpit
            ;;
        suse)
            sudo zypper install -y cockpit
            ;;
    esac

    # Enable and start the management socket (activates cockpit on first connect)
    sudo systemctl enable --now cockpit.socket

    _cockpit_open_firewall

    info "Cockpit installed and started."
    info "Open the web console at https://$(hostname -I 2>/dev/null | awk '{print $1}'):9090"
    info "Log in with your system user account."
}

uninstall_cockpit() {
    info "Uninstalling Cockpit..."
    sudo systemctl disable --now cockpit.socket 2>/dev/null || true
    case "$DISTRO_FAMILY" in
        debian)
            sudo apt purge --autoremove -y 'cockpit*'
            sudo apt autoclean
            ;;
        fedora|rhel)
            sudo "$PKG_MGR" remove -y 'cockpit*'
            ;;
        arch)
            sudo pacman -Rs --noconfirm cockpit
            ;;
        suse)
            sudo zypper remove -y cockpit
            ;;
    esac
    info "Cockpit has been uninstalled."
}

update_cockpit() {
    info "Updating Cockpit..."
    case "$DISTRO_FAMILY" in
        debian)      sudo apt install -y --only-upgrade cockpit ;;
        fedora|rhel) sudo "$PKG_MGR" upgrade -y cockpit ;;
        arch)        sudo pacman -S --noconfirm cockpit ;;
        suse)        sudo zypper update -y cockpit ;;
    esac
}

get_version_cockpit() {
    _ver_from_pkg cockpit || echo ""
}

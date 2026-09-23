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
            pkg_install cockpit
            ;;
        fedora|rhel)
            pkg_install cockpit
            ;;
        arch)
            pkg_install cockpit
            ;;
        suse)
            pkg_install cockpit
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
            pkg_remove 'cockpit*'
            ;;
        fedora|rhel)
            pkg_remove 'cockpit*'
            ;;
        arch)
            pkg_remove cockpit
            ;;
        suse)
            pkg_remove cockpit
            ;;
    esac
    info "Cockpit has been uninstalled."
}

update_cockpit() {
    info "Updating Cockpit..."
    case "$DISTRO_FAMILY" in
        debian)      pkg_upgrade cockpit ;;
        fedora|rhel) pkg_upgrade cockpit ;;
        arch)        pkg_upgrade cockpit ;;
        suse)        pkg_upgrade cockpit ;;
    esac
}

get_version_cockpit() {
    _ver_from_pkg cockpit || echo ""
}

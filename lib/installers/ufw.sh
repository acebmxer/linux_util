#!/bin/bash
# UFW (Uncomplicated Firewall) installer functions

# --- UFW ---

check_ufw() {
    _have_cmd ufw && sudo ufw status &>/dev/null
}

install_ufw() {
    info "Installing UFW (Uncomplicated Firewall)..."
    ensure_tools
    case "$DISTRO_FAMILY" in
        debian)
            pkg_install ufw || return 1
            ;;
        fedora)
            pkg_install ufw || return 1
            ;;
        rhel)
            # ufw lives in EPEL on RHEL-based distros, not in the base repos
            pkg_install epel-release 2>/dev/null || true
            pkg_install ufw || return 1
            ;;
        arch)
            pkg_install ufw || return 1
            ;;
        suse)
            # Tumbleweed and Leap 16.0 ship ufw; Leap 15.6 and older do not
            pkg_install ufw 2>/dev/null || {
                warn "UFW is not available in this openSUSE version's repos (Leap 15.6 and older do not ship it)."
                warn "Install firewalld from the Firewalls category instead — it is the supported firewall here."
                return 1
            }
            ;;
    esac

    # Only one firewall manager should own netfilter at a time
    if systemctl is-active --quiet firewalld 2>/dev/null; then
        warn "firewalld is active — disabling it so UFW can manage the firewall."
        sudo systemctl disable --now firewalld 2>/dev/null || true
    fi

    # Apply sensible default rules and enable
    sudo ufw default deny incoming
    sudo ufw default allow outgoing
    sudo ufw allow ssh         # Keep SSH accessible
    sudo ufw --force enable
    # 'ufw enable' loads the rules itself but leaves ufw.service inactive, so
    # systemd's view stays out of sync until the next boot — start it as well
    sudo systemctl enable --now ufw 2>/dev/null || true

    info "UFW installed and enabled with default rules (deny incoming, allow outgoing, allow SSH)."
}

uninstall_ufw() {
    info "Uninstalling UFW..."
    sudo ufw --force disable 2>/dev/null || true
    sudo systemctl disable ufw 2>/dev/null || true
    case "$DISTRO_FAMILY" in
        debian)
            pkg_remove ufw gufw 2>/dev/null || true
            ;;
        fedora|rhel)
            pkg_remove ufw
            ;;
        arch)
            pkg_remove ufw gufw 2>/dev/null || sudo pacman -Rs --noconfirm ufw 2>/dev/null || true
            ;;
        suse)
            pkg_remove ufw 2>/dev/null || true
            ;;
    esac
}

update_ufw() {
    info "Updating UFW..."
    case "$DISTRO_FAMILY" in
        debian)  sudo apt-get install -y --only-upgrade ufw ;;
        fedora|rhel) pkg_upgrade ufw ;;
        arch)    pkg_upgrade ufw ;;
        suse)    pkg_upgrade ufw ;;
    esac
}

get_version_ufw() {
    _run_native ufw version 2>/dev/null | grep -oP '[0-9]+\.[0-9]+\.[0-9.]+' | head -1 || echo ""
}

#!/bin/bash
# UFW (Uncomplicated Firewall) installer functions

# --- UFW ---

check_ufw() {
    command -v ufw &>/dev/null && sudo ufw status &>/dev/null
}

install_ufw() {
    info "Installing UFW (Uncomplicated Firewall)..."
    ensure_tools
    case "$DISTRO_FAMILY" in
        debian)
            sudo apt install -y ufw
            # Install GUI frontend if a desktop environment is present
            if [[ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]]; then
                sudo apt install -y gufw 2>/dev/null || true
            fi
            ;;
        fedora)
            sudo "$PKG_MGR" install -y ufw
            ;;
        rhel)
            sudo "$PKG_MGR" install -y epel-release 2>/dev/null || true
            sudo "$PKG_MGR" install -y ufw
            ;;
        arch)
            sudo pacman -S --noconfirm ufw
            if [[ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]]; then
                sudo pacman -S --noconfirm gufw 2>/dev/null || true
            fi
            ;;
        suse)
            sudo zypper install -y ufw 2>/dev/null || {
                warn "UFW not available in default repos. Installing firewalld instead..."
                sudo zypper install -y firewalld
                sudo systemctl enable --now firewalld
                info "firewalld installed as alternative firewall management tool."
                return 0
            }
            ;;
    esac

    # Apply sensible default rules and enable
    sudo ufw default deny incoming
    sudo ufw default allow outgoing
    sudo ufw allow ssh         # Keep SSH accessible
    sudo ufw --force enable
    sudo systemctl enable ufw 2>/dev/null || true

    info "UFW installed and enabled with default rules (deny incoming, allow outgoing, allow SSH)."
}

uninstall_ufw() {
    info "Uninstalling UFW..."
    sudo ufw --force disable 2>/dev/null || true
    sudo systemctl disable ufw 2>/dev/null || true
    case "$DISTRO_FAMILY" in
        debian)
            sudo apt purge --autoremove -y ufw gufw 2>/dev/null || true
            ;;
        fedora|rhel)
            sudo "$PKG_MGR" remove -y ufw
            ;;
        arch)
            sudo pacman -Rs --noconfirm ufw gufw 2>/dev/null || sudo pacman -Rs --noconfirm ufw 2>/dev/null || true
            ;;
        suse)
            sudo zypper remove -y ufw 2>/dev/null || true
            ;;
    esac
}

update_ufw() {
    info "Updating UFW..."
    case "$DISTRO_FAMILY" in
        debian)  sudo apt-get install -y --only-upgrade ufw ;;
        fedora|rhel) sudo "$PKG_MGR" upgrade -y ufw ;;
        arch)    sudo pacman -S --noconfirm ufw ;;
        suse)    sudo zypper update -y ufw ;;
    esac
}

get_version_ufw() {
    ufw version 2>/dev/null | grep -oP '[0-9]+\.[0-9]+\.[0-9.]+' | head -1 || echo ""
}

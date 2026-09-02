#!/bin/bash
# Virt-Manager QEMU/KVM GUI installer functions

# --- Virt-Manager ---

check_virt_manager() { _check_standard virt-manager virt-manager ""; }

install_virt_manager() {
    info "Installing Virt-Manager (QEMU/KVM GUI)..."
    ensure_tools
    case "$DISTRO_FAMILY" in
        debian)
            sudo apt install -y virt-manager qemu-kvm libvirt-daemon-system \
                libvirt-clients bridge-utils virtinst \
                || { error "Package installation failed."; return 1; }
            ;;
        fedora)
            sudo "$PKG_MGR" install -y virt-manager qemu-kvm libvirt \
                libvirt-daemon libvirt-client virt-install \
                || { error "Package installation failed."; return 1; }
            ;;
        rhel)
            sudo "$PKG_MGR" install -y virt-manager qemu-kvm libvirt \
                libvirt-daemon libvirt-client virt-install \
                || { error "Package installation failed."; return 1; }
            ;;
        arch)
            # bridge-utils was dropped from the Arch repos; iproute2 (a base
            # dependency) provides the bridge tooling libvirt needs.
            sudo pacman -S --noconfirm virt-manager qemu-full libvirt \
                iptables-nft dnsmasq virt-viewer \
                || { error "Package installation failed."; return 1; }
            ;;
        suse)
            sudo zypper install -y virt-manager kvm libvirt libvirt-daemon \
                libvirt-daemon-driver-qemu \
                || { error "Package installation failed."; return 1; }
            ;;
    esac

    # Enable and start the libvirtd service
    sudo systemctl enable --now libvirtd 2>/dev/null || \
        sudo systemctl enable --now libvirt-daemon 2>/dev/null || true

    # Add the current user to the libvirt group for passwordless VM management.
    # The libvirt package creates the group via sysusers.d; apply it now in case
    # the entry has not been processed yet.
    if ! getent group libvirt >/dev/null 2>&1; then
        sudo systemd-sysusers 2>/dev/null || true
    fi
    local current_user="${SUDO_USER:-$USER}"
    if getent group libvirt >/dev/null 2>&1; then
        if ! id -nG "$current_user" 2>/dev/null | grep -qw libvirt; then
            sudo usermod -aG libvirt "$current_user"
            warn "Added $current_user to the 'libvirt' group. Log out and back in for group membership to take effect."
        fi
    else
        warn "The 'libvirt' group does not exist; skipped adding $current_user to it."
    fi

    info "Virt-Manager installed."
    info "Enable virtualization (VT-x/AMD-V) in your BIOS/UEFI if you haven't already."
}

uninstall_virt_manager() {
    info "Uninstalling Virt-Manager..."
    sudo systemctl stop libvirtd 2>/dev/null || true
    sudo systemctl disable libvirtd 2>/dev/null || true
    case "$DISTRO_FAMILY" in
        debian)
            sudo apt purge --autoremove -y virt-manager libvirt-daemon-system \
                libvirt-clients virtinst 2>/dev/null || true
            ;;
        fedora|rhel)
            sudo "$PKG_MGR" remove -y virt-manager libvirt libvirt-client 2>/dev/null || true
            ;;
        arch)
            sudo pacman -Rs --noconfirm virt-manager libvirt 2>/dev/null || true
            ;;
        suse)
            sudo zypper remove -y virt-manager libvirt 2>/dev/null || true
            ;;
    esac
}

update_virt_manager() {
    info "Updating Virt-Manager..."
    case "$DISTRO_FAMILY" in
        debian)      sudo apt-get install -y --only-upgrade virt-manager ;;
        fedora|rhel) sudo "$PKG_MGR" upgrade -y virt-manager ;;
        arch)        sudo pacman -S --noconfirm virt-manager ;;
        suse)        sudo zypper update -y virt-manager ;;
    esac
}

get_version_virt_manager() {
    _ver_from_cmd virt-manager --version || _ver_from_pkg virt-manager || echo ""
}

#!/bin/bash
# Ansible configuration management installer functions

# --- Ansible ---

check_ansible() { _check_standard ansible ansible ""; }

install_ansible() {
    info "Installing Ansible..."
    ensure_tools
    case "$DISTRO_FAMILY" in
        debian)
            sudo apt install -y ansible
            ;;
        fedora)
            sudo "$PKG_MGR" install -y ansible
            ;;
        rhel)
            # ansible-core is in AppStream; full ansible collection is in EPEL
            sudo "$PKG_MGR" install -y epel-release 2>/dev/null || true
            sudo "$PKG_MGR" install -y ansible
            ;;
        arch)
            sudo pacman -S --noconfirm ansible
            ;;
        suse)
            sudo zypper install -y ansible
            ;;
    esac
    info "Ansible installed."
    info "Run 'ansible --version' to verify and 'ansible-galaxy' to manage collections."
}

uninstall_ansible() {
    info "Uninstalling Ansible..."
    case "$DISTRO_FAMILY" in
        debian)      sudo apt purge --autoremove -y ansible ;;
        fedora|rhel) sudo "$PKG_MGR" remove -y ansible ;;
        arch)        sudo pacman -Rs --noconfirm ansible ;;
        suse)        sudo zypper remove -y ansible ;;
    esac
}

update_ansible() {
    info "Updating Ansible..."
    case "$DISTRO_FAMILY" in
        debian)      sudo apt-get install -y --only-upgrade ansible ;;
        fedora|rhel) sudo "$PKG_MGR" upgrade -y ansible ;;
        arch)        sudo pacman -S --noconfirm ansible ;;
        suse)        sudo zypper update -y ansible ;;
    esac
}

get_version_ansible() {
    _ver_from_cmd ansible || _ver_from_pkg ansible || echo ""
}

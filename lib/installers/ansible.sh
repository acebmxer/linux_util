#!/bin/bash
# Ansible configuration management installer functions

# --- Ansible ---

check_ansible() { _check_standard ansible ansible ""; }

install_ansible() {
    info "Installing Ansible..."
    ensure_tools
    case "$DISTRO_FAMILY" in
        debian)
            pkg_install ansible
            ;;
        fedora)
            pkg_install ansible
            ;;
        rhel)
            # ansible-core is in AppStream; full ansible collection is in EPEL
            pkg_install epel-release 2>/dev/null || true
            pkg_install ansible
            ;;
        arch)
            pkg_install ansible
            ;;
        suse)
            pkg_install ansible
            ;;
    esac
    info "Ansible installed."
    info "Run 'ansible --version' to verify and 'ansible-galaxy' to manage collections."
}

uninstall_ansible() {
    info "Uninstalling Ansible..."
    case "$DISTRO_FAMILY" in
        debian)      pkg_remove ansible ;;
        fedora|rhel) pkg_remove ansible ;;
        arch)        pkg_remove ansible ;;
        suse)        pkg_remove ansible ;;
    esac
}

update_ansible() {
    info "Updating Ansible..."
    case "$DISTRO_FAMILY" in
        debian)      sudo apt-get install -y --only-upgrade ansible ;;
        fedora|rhel) pkg_upgrade ansible ;;
        arch)        pkg_upgrade ansible ;;
        suse)        pkg_upgrade ansible ;;
    esac
}

get_version_ansible() {
    _ver_from_cmd ansible || _ver_from_pkg ansible || echo ""
}

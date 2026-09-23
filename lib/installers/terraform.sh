#!/bin/bash
# Terraform infrastructure-as-code tool installer functions

# --- Terraform ---

check_terraform() { _check_standard terraform terraform ""; }

install_terraform() {
    info "Installing Terraform..."
    ensure_tools
    case "$DISTRO_FAMILY" in
        debian)
            # Official HashiCorp apt repository
            wget -O- https://apt.releases.hashicorp.com/gpg | \
                sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
            echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(. /etc/os-release && echo "$VERSION_CODENAME") main" | \
                sudo tee /etc/apt/sources.list.d/hashicorp.list > /dev/null
            sudo apt update
            pkg_install terraform
            ;;
        fedora)
            pkg_install 'dnf-command(config-manager)' 2>/dev/null || true
            sudo "$PKG_MGR" config-manager --add-repo \
                https://rpm.releases.hashicorp.com/fedora/hashicorp.repo
            pkg_install terraform
            ;;
        rhel)
            pkg_install 'dnf-command(config-manager)' 2>/dev/null || true
            sudo "$PKG_MGR" config-manager --add-repo \
                https://rpm.releases.hashicorp.com/RHEL/hashicorp.repo
            pkg_install terraform
            ;;
        arch)
            repo_or_aur terraform
            ;;
        suse)
            sudo zypper addrepo https://rpm.releases.hashicorp.com/SLES/hashicorp.repo hashicorp 2>/dev/null || true
            sudo zypper refresh
            pkg_install terraform
            ;;
    esac
    info "Terraform installed."
}

uninstall_terraform() {
    info "Uninstalling Terraform..."
    case "$DISTRO_FAMILY" in
        debian)
            pkg_remove terraform
            sudo rm -f /etc/apt/sources.list.d/hashicorp.list
            sudo rm -f /usr/share/keyrings/hashicorp-archive-keyring.gpg
            ;;
        fedora|rhel)
            pkg_remove terraform
            sudo rm -f /etc/yum.repos.d/hashicorp.repo
            ;;
        arch)
            aur_remove terraform 2>/dev/null || \
                pkg_remove terraform 2>/dev/null || true
            ;;
        suse)
            pkg_remove terraform
            sudo zypper removerepo hashicorp 2>/dev/null || true
            ;;
    esac
}

update_terraform() {
    info "Updating Terraform..."
    case "$DISTRO_FAMILY" in
        debian)      sudo apt-get install -y --only-upgrade terraform ;;
        fedora|rhel) pkg_upgrade terraform ;;
        arch)        repo_or_aur terraform ;;
        suse)        pkg_upgrade terraform ;;
    esac
}

get_version_terraform() {
    _ver_from_cmd terraform version 2>/dev/null | grep -oP 'Terraform v\K[0-9]+\.[0-9]+\.[0-9]+' || \
        _ver_from_pkg terraform || echo ""
}

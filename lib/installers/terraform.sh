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
            sudo apt install -y terraform
            ;;
        fedora)
            sudo "$PKG_MGR" install -y 'dnf-command(config-manager)' 2>/dev/null || true
            sudo "$PKG_MGR" config-manager --add-repo \
                https://rpm.releases.hashicorp.com/fedora/hashicorp.repo
            sudo "$PKG_MGR" install -y terraform
            ;;
        rhel)
            sudo "$PKG_MGR" install -y 'dnf-command(config-manager)' 2>/dev/null || true
            sudo "$PKG_MGR" config-manager --add-repo \
                https://rpm.releases.hashicorp.com/RHEL/hashicorp.repo
            sudo "$PKG_MGR" install -y terraform
            ;;
        arch)
            aur_ensure terraform
            ;;
        suse)
            sudo zypper addrepo https://rpm.releases.hashicorp.com/SLES/hashicorp.repo hashicorp 2>/dev/null || true
            sudo zypper refresh
            sudo zypper install -y terraform
            ;;
    esac
    info "Terraform installed."
}

uninstall_terraform() {
    info "Uninstalling Terraform..."
    case "$DISTRO_FAMILY" in
        debian)
            sudo apt purge --autoremove -y terraform
            sudo rm -f /etc/apt/sources.list.d/hashicorp.list
            sudo rm -f /usr/share/keyrings/hashicorp-archive-keyring.gpg
            ;;
        fedora|rhel)
            sudo "$PKG_MGR" remove -y terraform
            sudo rm -f /etc/yum.repos.d/hashicorp.repo
            ;;
        arch)
            aur_remove terraform 2>/dev/null || \
                sudo pacman -Rs --noconfirm terraform 2>/dev/null || true
            ;;
        suse)
            sudo zypper remove -y terraform
            sudo zypper removerepo hashicorp 2>/dev/null || true
            ;;
    esac
}

update_terraform() {
    info "Updating Terraform..."
    case "$DISTRO_FAMILY" in
        debian)      sudo apt-get install -y --only-upgrade terraform ;;
        fedora|rhel) sudo "$PKG_MGR" upgrade -y terraform ;;
        arch)        aur_ensure terraform ;;
        suse)        sudo zypper update -y terraform ;;
    esac
}

get_version_terraform() {
    _ver_from_cmd terraform version 2>/dev/null | grep -oP 'Terraform v\K[0-9]+\.[0-9]+\.[0-9]+' || \
        _ver_from_pkg terraform || echo ""
}

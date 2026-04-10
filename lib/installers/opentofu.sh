#!/bin/bash
# OpenTofu (open-source Terraform fork) installer functions

# --- OpenTofu ---

check_opentofu() { _check_standard tofu opentofu ""; }

install_opentofu() {
    info "Installing OpenTofu..."
    ensure_tools
    case "$DISTRO_FAMILY" in
        debian)
            # Official OpenTofu apt repository via installer script
            curl --proto '=https' --tlsv1.2 -fsSL https://get.opentofu.org/install-opentofu.sh | \
                sudo bash -s -- --install-method deb
            ;;
        fedora|rhel)
            curl --proto '=https' --tlsv1.2 -fsSL https://get.opentofu.org/install-opentofu.sh | \
                sudo bash -s -- --install-method rpm
            ;;
        arch)
            aur_ensure opentofu
            ;;
        suse)
            curl --proto '=https' --tlsv1.2 -fsSL https://get.opentofu.org/install-opentofu.sh | \
                sudo bash -s -- --install-method standalone || {
                # Standalone installs to /usr/local/bin/tofu
                error "OpenTofu standalone install failed."
                return 1
            }
            ;;
    esac
    info "OpenTofu installed. Use 'tofu' command (drop-in Terraform replacement)."
}

uninstall_opentofu() {
    info "Uninstalling OpenTofu..."
    if [[ -f /usr/local/bin/tofu ]]; then
        sudo rm -f /usr/local/bin/tofu
    fi
    case "$DISTRO_FAMILY" in
        debian)
            sudo apt purge --autoremove -y opentofu 2>/dev/null || true
            sudo rm -f /etc/apt/sources.list.d/opentofu.list
            sudo rm -f /etc/apt/keyrings/opentofu-archive-keyring.gpg
            ;;
        fedora|rhel)
            sudo "$PKG_MGR" remove -y opentofu 2>/dev/null || true
            sudo rm -f /etc/yum.repos.d/opentofu.repo
            ;;
        arch)
            aur_remove opentofu 2>/dev/null || \
                sudo pacman -Rs --noconfirm opentofu 2>/dev/null || true
            ;;
        suse)
            sudo zypper remove -y opentofu 2>/dev/null || true
            ;;
    esac
}

update_opentofu() {
    info "Updating OpenTofu..."
    if [[ -f /usr/local/bin/tofu ]]; then
        install_opentofu
    else
        case "$DISTRO_FAMILY" in
            debian)      sudo apt-get install -y --only-upgrade opentofu ;;
            fedora|rhel) sudo "$PKG_MGR" upgrade -y opentofu ;;
            arch)        aur_ensure opentofu ;;
            suse)        sudo zypper update -y opentofu 2>/dev/null || install_opentofu ;;
        esac
    fi
}

get_version_opentofu() {
    _ver_from_cmd tofu version 2>/dev/null | grep -oP 'OpenTofu v\K[0-9]+\.[0-9]+\.[0-9]+' || \
        _ver_from_pkg opentofu || echo ""
}

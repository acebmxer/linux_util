#!/bin/bash
# Vivaldi Browser installer functions

# --- Vivaldi Browser ---
# Official repos: https://repo.vivaldi.com/archive/

check_vivaldi() {
    _have_cmd vivaldi-stable || _have_cmd vivaldi || \
        pkg_check_installed vivaldi-stable
}

install_vivaldi() {
    info "Installing Vivaldi Browser..."
    ensure_tools
    case "$DISTRO_FAMILY" in
        debian)
            _add_apt_repo \
                "https://repo.vivaldi.com/archive/linux_signing_key.pub" \
                "/usr/share/keyrings/vivaldi-keyring.gpg" \
                "deb [arch=amd64 signed-by=/usr/share/keyrings/vivaldi-keyring.gpg] https://repo.vivaldi.com/archive/deb/ stable main" \
                "/etc/apt/sources.list.d/vivaldi.list"
            pkg_install vivaldi-stable
            ;;
        fedora|rhel)
            sudo tee /etc/yum.repos.d/vivaldi.repo > /dev/null << 'EOF'
[vivaldi]
name=Vivaldi Browser
baseurl=https://repo.vivaldi.com/archive/rpm/x86_64
enabled=1
gpgcheck=1
gpgkey=https://repo.vivaldi.com/archive/linux_signing_key.pub
EOF
            sudo rpm --import https://repo.vivaldi.com/archive/linux_signing_key.pub
            pkg_install vivaldi-stable
            ;;
        arch)
            repo_or_aur vivaldi
            ;;
        suse)
            sudo rpm --import https://repo.vivaldi.com/archive/linux_signing_key.pub
            sudo zypper addrepo -f https://repo.vivaldi.com/archive/rpm/x86_64 vivaldi 2>/dev/null || true
            sudo zypper refresh
            pkg_install vivaldi-stable
            ;;
    esac
}

uninstall_vivaldi() {
    info "Uninstalling Vivaldi Browser..."
    case "$DISTRO_FAMILY" in
        debian)
            pkg_remove vivaldi-stable
            sudo rm -f /etc/apt/sources.list.d/vivaldi.list
            sudo rm -f /usr/share/keyrings/vivaldi-keyring.gpg
            ;;
        fedora|rhel)
            pkg_remove vivaldi-stable
            sudo rm -f /etc/yum.repos.d/vivaldi.repo
            ;;
        arch)
            aur_remove vivaldi 2>/dev/null || pkg_remove vivaldi 2>/dev/null || true
            ;;
        suse)
            pkg_remove vivaldi-stable
            sudo zypper removerepo vivaldi 2>/dev/null || true
            ;;
    esac
    rm -rf ~/.config/vivaldi
}

update_vivaldi() {
    info "Updating Vivaldi Browser..."
    case "$DISTRO_FAMILY" in
        debian)
            sudo apt update
            pkg_upgrade vivaldi-stable
            ;;
        arch)
            repo_or_aur vivaldi
            ;;
        *)
            pkg_upgrade vivaldi-stable
            ;;
    esac
}

get_version_vivaldi() {
    local cmd
    for cmd in vivaldi-stable vivaldi; do
        _have_cmd "$cmd" || continue
        _run_native "$cmd" --version 2>/dev/null | grep -oP 'Vivaldi\s+\K[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' && return
    done
    echo ""
}

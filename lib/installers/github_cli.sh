#!/bin/bash
# GitHub CLI (gh) installer functions

# --- GitHub CLI ---

check_github_cli() {
    _have_cmd gh
}

install_github_cli() {
    info "Installing GitHub CLI..."
    ensure_tools
    case "$DISTRO_FAMILY" in
        debian)
            _add_apt_repo \
                "https://cli.github.com/packages/githubcli-archive-keyring.gpg" \
                "/etc/apt/keyrings/githubcli-archive-keyring.gpg" \
                "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
                "/etc/apt/sources.list.d/github-cli.list"
            sudo apt install -y gh
            ;;
        fedora|rhel)
            sudo "$PKG_MGR" install -y 'dnf-command(config-manager)' 2>/dev/null || true
            sudo "$PKG_MGR" config-manager --add-repo https://cli.github.com/packages/rpm/gh-cli.repo
            sudo "$PKG_MGR" install -y gh
            ;;
        arch)
            sudo pacman -S --noconfirm github-cli
            ;;
        suse)
            sudo zypper addrepo https://cli.github.com/packages/rpm/gh-cli.repo gh-cli 2>/dev/null || true
            sudo zypper refresh
            sudo zypper install -y gh
            ;;
    esac
}

uninstall_github_cli() {
    info "Uninstalling GitHub CLI..."
    case "$DISTRO_FAMILY" in
        debian)
            sudo apt purge --autoremove -y gh
            sudo rm -f /etc/apt/sources.list.d/github-cli.list
            sudo rm -f /etc/apt/keyrings/githubcli-archive-keyring.gpg
            ;;
        fedora|rhel)
            sudo "$PKG_MGR" remove -y gh
            sudo rm -f /etc/yum.repos.d/gh-cli.repo
            ;;
        arch)
            sudo pacman -Rs --noconfirm github-cli
            ;;
        suse)
            sudo zypper remove -y gh
            sudo zypper removerepo gh-cli 2>/dev/null || true
            ;;
    esac
}

update_github_cli() {
    info "Updating GitHub CLI..."
    case "$DISTRO_FAMILY" in
        debian)
            sudo apt-get install -y --only-upgrade gh
            ;;
        fedora|rhel)
            sudo "$PKG_MGR" upgrade -y gh
            ;;
        arch)
            sudo pacman -S --noconfirm github-cli
            ;;
        suse)
            sudo zypper update -y gh
            ;;
    esac
}

get_version_github_cli() {
    _run_native gh --version 2>/dev/null | grep -oP 'gh version \K[0-9]+\.[0-9]+\.[0-9]+' || echo ""
}

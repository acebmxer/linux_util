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
            pkg_install gh
            ;;
        fedora|rhel)
            pkg_install 'dnf-command(config-manager)' 2>/dev/null || true
            sudo "$PKG_MGR" config-manager --add-repo https://cli.github.com/packages/rpm/gh-cli.repo
            pkg_install gh
            ;;
        arch)
            pkg_install github-cli
            ;;
        suse)
            sudo zypper addrepo https://cli.github.com/packages/rpm/gh-cli.repo gh-cli 2>/dev/null || true
            sudo zypper refresh
            pkg_install gh
            ;;
    esac
}

uninstall_github_cli() {
    info "Uninstalling GitHub CLI..."
    case "$DISTRO_FAMILY" in
        debian)
            pkg_remove gh
            sudo rm -f /etc/apt/sources.list.d/github-cli.list
            sudo rm -f /etc/apt/keyrings/githubcli-archive-keyring.gpg
            ;;
        fedora|rhel)
            pkg_remove gh
            sudo rm -f /etc/yum.repos.d/gh-cli.repo
            ;;
        arch)
            pkg_remove github-cli
            ;;
        suse)
            pkg_remove gh
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
            pkg_upgrade gh
            ;;
        arch)
            pkg_upgrade github-cli
            ;;
        suse)
            pkg_upgrade gh
            ;;
    esac
}

get_version_github_cli() {
    _run_native gh --version 2>/dev/null | grep -oP 'gh version \K[0-9]+\.[0-9]+\.[0-9]+' || echo ""
}

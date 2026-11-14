#!/bin/bash
# lazygit installer functions
#
# Terminal UI for git: stage hunks, resolve conflicts and browse history with the keyboard. The distro package where the repositories have one (Debian 13, Ubuntu 26.04, Fedora, Arch, openSUSE, Alpine); otherwise the GitHub release, SHA-256 checked, in /usr/local/bin.

# --- lazygit ---

_lazygit_REPO="jesseduffield/lazygit"
_lazygit_RE='lazygit_[0-9.]+_linux_@GOX@\.tar\.gz'

# Latest upstream version, for System Updates.
_lazygit_latest_version() { github_latest_tag "$_lazygit_REPO" | sed 's/^v//'; }

check_lazygit() { _check_standard lazygit lazygit "" || [[ -x /usr/local/bin/lazygit ]]; }

install_lazygit() {
    info "Installing lazygit..."
    native_or_github_install lazygit "$_lazygit_REPO" "$_lazygit_RE" lazygit || return 1
    info "lazygit installed."
}

uninstall_lazygit() {
    info "Uninstalling lazygit..."
    native_or_github_uninstall lazygit lazygit
}

update_lazygit() {
    info "Updating lazygit..."
    native_or_github_update lazygit "$_lazygit_REPO" "$_lazygit_RE" lazygit lazygit "$(get_version_lazygit)"
}

get_version_lazygit() { _ver_from_pkg lazygit || _ver_from_cmd lazygit --version || echo ""; }

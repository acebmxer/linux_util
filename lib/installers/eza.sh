#!/bin/bash
# eza installer functions
#
# ls replacement with colours, icons and git status. The distro package where the repositories have one (Debian 13, Ubuntu 26.04, Fedora, Arch, openSUSE, Alpine); otherwise the GitHub release, SHA-256 checked, in /usr/local/bin (x86_64 only: upstream builds no static aarch64 file).

# --- eza ---

_eza_REPO="eza-community/eza"
_eza_RE='eza_@GNU@-unknown-linux-musl\.tar\.gz'

# Latest upstream version, for System Updates.
_eza_latest_version() { github_latest_tag "$_eza_REPO" | sed 's/^v//'; }

check_eza() { _check_standard eza eza "" || [[ -x /usr/local/bin/eza ]]; }

install_eza() {
    info "Installing eza..."
    native_or_github_install eza "$_eza_REPO" "$_eza_RE" eza || return 1
    info "eza installed."
}

uninstall_eza() {
    info "Uninstalling eza..."
    native_or_github_uninstall eza eza
}

update_eza() {
    info "Updating eza..."
    native_or_github_update eza "$_eza_REPO" "$_eza_RE" eza eza "$(get_version_eza)"
}

get_version_eza() { _ver_from_pkg eza || _ver_from_cmd eza --version || echo ""; }

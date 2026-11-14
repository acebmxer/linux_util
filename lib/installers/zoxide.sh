#!/bin/bash
# zoxide installer functions
#
# Smarter cd: remembers the folders you use and jumps to them with z. The distro package where the repositories have one (every release except Rocky/Alma 10); otherwise the GitHub release, SHA-256 checked, in /usr/local/bin. Loaded from ~/.bashrc (and ~/.zshrc when it exists).

# --- zoxide ---

_zoxide_REPO="ajeetdsouza/zoxide"
_zoxide_RE='zoxide-[0-9.]+-@GNU@-unknown-linux-musl\.tar\.gz'

# Latest upstream version, for System Updates.
_zoxide_latest_version() { github_latest_tag "$_zoxide_REPO" | sed 's/^v//'; }

check_zoxide() { _check_standard zoxide zoxide "" || [[ -x /usr/local/bin/zoxide ]]; }

install_zoxide() {
    info "Installing zoxide..."
    native_or_github_install zoxide "$_zoxide_REPO" "$_zoxide_RE" zoxide || return 1
    # shellcheck disable=SC2016  # the rc file, not this script, expands these
    shell_init_setup zoxide \
        'if command -v zoxide >/dev/null 2>&1; then eval "$(zoxide init bash)"; fi' \
        'if command -v zoxide >/dev/null 2>&1; then eval "$(zoxide init zsh)"; fi'
    info "zoxide installed. Open a new terminal to use it."
}

uninstall_zoxide() {
    info "Uninstalling zoxide..."
    shell_init_remove zoxide
    native_or_github_uninstall zoxide zoxide
}

update_zoxide() {
    info "Updating zoxide..."
    native_or_github_update zoxide "$_zoxide_REPO" "$_zoxide_RE" zoxide zoxide "$(get_version_zoxide)"
}

get_version_zoxide() { _ver_from_pkg zoxide || _ver_from_cmd zoxide --version || echo ""; }

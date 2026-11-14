#!/bin/bash
# starship installer functions
#
# Fast, themeable shell prompt. The distro package where the repositories have one (Debian 13, Ubuntu 26.04, Arch, openSUSE, Alpine); otherwise the GitHub release, SHA-256 checked, in /usr/local/bin. Loaded from ~/.bashrc (and ~/.zshrc when it exists).

# --- starship ---

_starship_REPO="starship/starship"
_starship_RE='starship-@GNU@-unknown-linux-musl\.tar\.gz'

# Latest upstream version, for System Updates.
_starship_latest_version() { github_latest_tag "$_starship_REPO" | sed 's/^v//'; }

check_starship() { _check_standard starship starship "" || [[ -x /usr/local/bin/starship ]]; }

install_starship() {
    info "Installing starship..."
    native_or_github_install starship "$_starship_REPO" "$_starship_RE" starship || return 1
    # shellcheck disable=SC2016  # the rc file, not this script, expands these
    shell_init_setup starship \
        'if command -v starship >/dev/null 2>&1; then eval "$(starship init bash)"; fi' \
        'if command -v starship >/dev/null 2>&1; then eval "$(starship init zsh)"; fi'
    info "starship installed. Open a new terminal to use it."
}

uninstall_starship() {
    info "Uninstalling starship..."
    shell_init_remove starship
    native_or_github_uninstall starship starship
}

update_starship() {
    info "Updating starship..."
    native_or_github_update starship "$_starship_REPO" "$_starship_RE" starship starship "$(get_version_starship)"
}

get_version_starship() { _ver_from_pkg starship || _ver_from_cmd starship --version || echo ""; }

#!/bin/bash
# fzf installer functions
#
# Command-line fuzzy finder: filters any list as you type, and adds Ctrl+R /
# Ctrl+T / Alt+C to the shell. The fzf package in every supported distro's
# repositories, Alpine included (EPEL on RHEL clones). The key bindings are
# loaded from ~/.bashrc, and ~/.zshrc when it exists, through `fzf --bash` /
# `fzf --zsh` (fzf 0.48 and newer; on an older fzf the line does nothing).

# --- fzf ---

check_fzf() { _check_standard fzf fzf ""; }

install_fzf() {
    info "Installing fzf..."
    ensure_epel
    pkg_install fzf || return 1
    # shellcheck disable=SC2016  # the rc file, not this script, expands these
    shell_init_setup fzf \
        'if command -v fzf >/dev/null 2>&1; then eval "$(fzf --bash 2>/dev/null)"; fi' \
        'if command -v fzf >/dev/null 2>&1; then source <(fzf --zsh 2>/dev/null); fi'
    info "fzf installed. Open a new terminal for Ctrl+R and Ctrl+T."
}

uninstall_fzf() {
    info "Uninstalling fzf..."
    shell_init_remove fzf
    pkg_remove fzf
}

update_fzf() {
    info "Updating fzf..."
    pkg_upgrade fzf
}

get_version_fzf() { _ver_from_pkg fzf || _ver_from_cmd fzf || echo ""; }

#!/bin/bash
# Command-not-found auto-install prompt setup
# Enables interactive y/N install prompt when a missing command is typed.
# Bash: defines command_not_found_handle() — COMMAND_NOT_FOUND_INSTALL_PROMPT=1
#       is not reliably supported in Ubuntu 26.04+.
# Zsh:  defines command_not_found_handler() since the function name differs.

_CNF_BASH_BEGIN="# linux_util: command-not-found auto-install (bash) -- begin"
_CNF_BASH_END="# linux_util: command-not-found auto-install (bash) -- end"
_CNF_ZSH_BEGIN="# linux_util: command-not-found handler (zsh) -- begin"
_CNF_ZSH_END="# linux_util: command-not-found handler (zsh) -- end"

check_command_not_found() {
    grep -qF "$_CNF_BASH_BEGIN" ~/.bashrc 2>/dev/null
}

# _cnf_ensure_package installs the command-not-found package if missing and
# updates the lookup database so suggestions are available immediately.
_cnf_ensure_package() {
    if ! dpkg -l command-not-found &>/dev/null; then
        info "Installing command-not-found package..."
        sudo apt-get install -y command-not-found || { warn "Failed to install command-not-found"; return 1; }
    fi
    # Refresh the package-name database (best-effort; may take a moment)
    sudo apt-file update 2>/dev/null || true
    sudo update-command-not-found 2>/dev/null || true
    return 0
}

# _cnf_apply_bash writes the bash handler block into the given rc file (default: ~/.bashrc).
# Defines command_not_found_handle(), which overrides the system default to add
# an interactive y/N install prompt after showing package suggestions.
_cnf_apply_bash() {
    local rcfile="${1:-$HOME/.bashrc}"
    if grep -qF "$_CNF_BASH_BEGIN" "$rcfile" 2>/dev/null; then
        info "command-not-found bash block already present in ${rcfile}"
        return 0
    fi
    cat >> "$rcfile" << 'BASHRC_BLOCK'

# linux_util: command-not-found auto-install (bash) -- begin
command_not_found_handle() {
    local cmd="$1"
    shift
    # Capture the suggested package from command-not-found
    local cnf_output=""
    local suggested_pkg=""
    if [ -x /usr/lib/command-not-found ]; then
        cnf_output=$(/usr/lib/command-not-found -- "$cmd" 2>&1)
        echo "$cnf_output"
        # Extract first "sudo apt install <pkg>" suggestion
        suggested_pkg=$(echo "$cnf_output" | grep -oP '(?<=sudo apt install )\S+' | head -1)
    fi
    local install_pkg="${suggested_pkg:-$cmd}"
    # Prompt user to install the suggested package
    printf "Would you like to install '%s'? (y/N): " "$install_pkg"
    local reply
    read -r -n 1 reply < /dev/tty
    echo
    if [[ "$reply" =~ ^[Yy]$ ]]; then
        sudo apt install "$install_pkg" && "$cmd" "$@"
    else
        return 127
    fi
}
# linux_util: command-not-found auto-install (bash) -- end
BASHRC_BLOCK
    info "Added command-not-found auto-install block to ${rcfile}"
}

# _cnf_apply_zsh writes the zsh handler block into the given rc file.
# The handler shows Ubuntu package suggestions, then asks y/N and installs via apt.
# Silently skips if the rc file does not exist (zsh not yet installed).
_cnf_apply_zsh() {
    local rcfile="${1:-$HOME/.zshrc}"
    [[ -f "$rcfile" ]] || return 0
    if grep -qF "$_CNF_ZSH_BEGIN" "$rcfile" 2>/dev/null; then
        info "command-not-found zsh block already present in ${rcfile}"
        return 0
    fi
    cat >> "$rcfile" << 'ZSHRC_BLOCK'

# linux_util: command-not-found handler (zsh) -- begin
# Zsh ignores COMMAND_NOT_FOUND_INSTALL_PROMPT; define the handler directly.
command_not_found_handler() {
    local cmd="$1"
    shift
    # Capture the suggested package from command-not-found
    local cnf_output=""
    local suggested_pkg=""
    if [ -x /usr/lib/command-not-found ]; then
        cnf_output=$(/usr/lib/command-not-found -- "$cmd" 2>&1)
        echo "$cnf_output"
        suggested_pkg=$(echo "$cnf_output" | grep -oP '(?<=sudo apt install )\S+' | head -1)
    fi
    local install_pkg="${suggested_pkg:-$cmd}"
    # Prompt user to install the suggested package
    echo -n "Would you like to install '$install_pkg'? (y/N): "
    read -k 1 reply
    echo
    if [[ "$reply" =~ ^[Yy]$ ]]; then
        sudo apt install "$install_pkg" && "$cmd" "$@"
    else
        return 127
    fi
}
# linux_util: command-not-found handler (zsh) -- end
ZSHRC_BLOCK
    info "Added command-not-found handler to ${rcfile}"
}

# _cnf_remove_block removes a begin/end marker block from a file using exact
# string matching (awk), avoiding regex-escaping issues with BRE and sed.
_cnf_remove_block() {
    local rcfile="$1" begin_marker="$2" end_marker="$3"
    [[ -f "$rcfile" ]] || return 0
    if grep -qF "$begin_marker" "$rcfile" 2>/dev/null; then
        awk -v begin="$begin_marker" -v end="$end_marker" '
            $0 == begin { skip=1 }
            skip { if ($0 == end) { skip=0 } next }
            { print }
        ' "$rcfile" > "${rcfile}.tmp" && mv "${rcfile}.tmp" "$rcfile"
        info "Removed command-not-found block from ${rcfile}"
    fi
}

setup_command_not_found() {
    info "Setting up command-not-found auto-install prompt..."

    _cnf_ensure_package || return 1
    _cnf_apply_bash "$HOME/.bashrc"

    # Configure zsh if already present (e.g. dotfiles installed first).
    # Silently skipped when ~/.zshrc doesn't exist; use Update later once dotfiles are set up.
    if [[ -f "$HOME/.zshrc" ]]; then
        _cnf_apply_zsh "$HOME/.zshrc"
        info "command-not-found setup complete. Open a new terminal to activate."
    else
        info "command-not-found setup complete. Run 'source ~/.bashrc' or open a new terminal to activate."
    fi
    return 0
}

uninstall_command_not_found() {
    info "Removing command-not-found auto-install blocks from shell configs..."
    _cnf_remove_block "$HOME/.bashrc" "$_CNF_BASH_BEGIN" "$_CNF_BASH_END"
    _cnf_remove_block "$HOME/.zshrc"  "$_CNF_ZSH_BEGIN"  "$_CNF_ZSH_END"
    info "command-not-found blocks removed."
    return 0
}

update_command_not_found() {
    setup_command_not_found
}

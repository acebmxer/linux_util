#!/bin/bash
# NVM (Node Version Manager) installer functions

# --- NVM ---

_NVM_DIR="${NVM_DIR:-$HOME/.nvm}"

check_nvm() {
    [[ -f "$_NVM_DIR/nvm.sh" ]]
}

install_nvm() {
    info "Installing NVM (Node Version Manager)..."
    ensure_tools

    # Fetch the latest release tag from GitHub
    local nvm_version
    nvm_version=$(curl -fsSL "https://api.github.com/repos/nvm-sh/nvm/releases/latest" \
        | grep -oP '"tag_name"\s*:\s*"\K[^"]+')
    [[ -z "$nvm_version" ]] && nvm_version="v0.40.1"

    info "Installing NVM ${nvm_version}..."
    if ! curl -fsSL "https://raw.githubusercontent.com/nvm-sh/nvm/${nvm_version}/install.sh" | bash; then
        error "NVM installation script failed."
        return 1
    fi

    # Source NVM so we can immediately use it in this session
    # shellcheck disable=SC1090
    [[ -f "$_NVM_DIR/nvm.sh" ]] && source "$_NVM_DIR/nvm.sh"

    info "NVM ${nvm_version} installed."
    info "Run 'nvm install --lts' to install the latest LTS version of Node.js."
    info "Shell config (~/.bashrc / ~/.zshrc) has been updated automatically."
}

uninstall_nvm() {
    info "Uninstalling NVM..."

    # Deactivate nvm in current shell if loaded
    if command -v nvm &>/dev/null; then
        nvm deactivate 2>/dev/null || true
        nvm unload 2>/dev/null || true
    fi

    rm -rf "$_NVM_DIR"

    # Remove NVM lines from shell rc files
    local rc_file
    for rc_file in "$HOME/.bashrc" "$HOME/.zshrc" "$HOME/.profile" "$HOME/.bash_profile"; do
        [[ -f "$rc_file" ]] || continue
        # Remove the NVM init block (3-line block added by the installer)
        sed -i '/NVM_DIR/d;/nvm\.sh/d;/nvm bash_completion/d' "$rc_file" 2>/dev/null || true
    done

    info "NVM uninstalled. Node.js installations within ~/.nvm have been removed."
}

update_nvm() {
    info "Updating NVM..."
    local nvm_version
    nvm_version=$(curl -fsSL "https://api.github.com/repos/nvm-sh/nvm/releases/latest" \
        | grep -oP '"tag_name"\s*:\s*"\K[^"]+')
    [[ -z "$nvm_version" ]] && { error "Could not determine latest NVM version."; return 1; }

    if ! curl -fsSL "https://raw.githubusercontent.com/nvm-sh/nvm/${nvm_version}/install.sh" | bash; then
        error "NVM update script failed."
        return 1
    fi
    info "NVM updated to ${nvm_version}."
}

get_version_nvm() {
    if [[ -f "$_NVM_DIR/nvm.sh" ]]; then
        # shellcheck disable=SC1090
        source "$_NVM_DIR/nvm.sh" 2>/dev/null
        # nvm is a shell function from the sourced script, not a program on
        # PATH, so it is called directly.
        nvm --version 2>/dev/null || echo ""
    else
        echo ""
    fi
}

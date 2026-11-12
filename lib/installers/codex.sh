#!/bin/bash
# Codex (OpenAI's terminal coding agent) installer functions
#
# Installed from npm like Claude Code, so Node.js is installed first when
# missing (_ensure_nodejs lives in claude_code.sh; every installer file is
# sourced before any function runs).

# --- Codex ---

check_codex() {
    _have_cmd codex
}

# npm's exit code is not trusted: run the binary to prove it works.
_codex_verify() {
    if ! _run_native codex --version &>/dev/null; then
        error "Codex installed but the 'codex' command is not working."
        return 1
    fi
}

install_codex() {
    info "Installing Codex..."
    ensure_tools
    _ensure_nodejs || return 1
    sudo npm install -g @openai/codex || return 1
    _codex_verify
}

uninstall_codex() {
    info "Uninstalling Codex..."
    # Remove the npm package only; Node.js and ~/.codex (sign-in, settings)
    # are left in place.
    sudo npm uninstall -g @openai/codex
}

update_codex() {
    info "Updating Codex..."
    _ensure_nodejs || return 1
    # Re-installing the package always fetches the latest published version.
    sudo npm install -g @openai/codex || return 1
    _codex_verify
}

get_version_codex() {
    # "codex-cli 0.166.0"
    _run_native codex --version 2>/dev/null | grep -oP -m1 '[0-9]+\.[0-9]+\.[0-9]+[^ ]*' || echo ""
}

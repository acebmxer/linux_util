#!/bin/bash
# Hermes Agent (Nous Research terminal AI agent) installer functions
#
# Installed per user with upstream's own install script, which clones the agent
# to ~/.hermes/hermes-agent and publishes the `hermes` command in
# ~/.local/bin. Using upstream's paths means an existing hand install is
# detected and updated in place. Updates and removal go through the agent's own
# `hermes update` / `hermes uninstall`, so nothing here needs sudo.

# --- Hermes Agent ---

_HERMES_INSTALL_URL="https://hermes-agent.nousresearch.com/install.sh"
_HERMES_BIN="$HOME/.local/bin/hermes"

# Print the hermes command to run: the one on PATH, else upstream's own link
# (~/.local/bin is not on PATH in the session that ran the installer).
_hermes_cmd() {
    if _have_cmd hermes; then
        _native_command hermes
    elif [[ -x "$_HERMES_BIN" ]]; then
        echo "$_HERMES_BIN"
    else
        return 1
    fi
}

check_hermes_agent() {
    _hermes_cmd >/dev/null
}

install_hermes_agent() {
    info "Installing Hermes Agent..."
    ensure_tools

    local installer
    installer=$(mktemp "${TMPDIR:-/tmp}/hermes-install-XXXXXX.sh")
    CLEANUP_FILES+=("$installer")
    # No total time limit: download_file's curl branch stops at 30 seconds.
    if ! curl -fsSL --retry 2 -o "$installer" "$_HERMES_INSTALL_URL"; then
        error "Failed to download the Hermes Agent install script."
        return 1
    fi

    # The installer offers its setup wizard on a terminal. Skip it when nobody
    # can answer, or when auto_confirm asks for an unattended run.
    local -a args=()
    if [[ "${CFG_AUTO_CONFIRM:-false}" == "true" ]] || ! { : < /dev/tty; } 2>/dev/null; then
        args+=(--non-interactive)
    fi

    # stdin comes from the terminal (or /dev/null) so the installer never
    # consumes the menu's input.
    local stdin_src=/dev/null
    { : < /dev/tty; } 2>/dev/null && stdin_src=/dev/tty
    if ! bash "$installer" "${args[@]}" < "$stdin_src"; then
        error "Hermes Agent installation script failed."
        return 1
    fi

    if ! check_hermes_agent; then
        error "Hermes Agent installed but the 'hermes' command was not found."
        return 1
    fi
    info "Hermes Agent installed. Run 'hermes' to start (restart your shell if the command is not found)."
}

uninstall_hermes_agent() {
    info "Uninstalling Hermes Agent..."
    local hermes
    hermes=$(_hermes_cmd) || { error "Hermes Agent is not installed."; return 1; }
    # Removes the code and command; ~/.hermes (config, keys, sessions) is kept.
    "$hermes" uninstall --yes < /dev/null || return 1
    info "Your Hermes settings and data in ~/.hermes were kept."
}

update_hermes_agent() {
    info "Updating Hermes Agent..."
    local hermes
    if ! hermes=$(_hermes_cmd); then
        install_hermes_agent
        return
    fi
    "$hermes" update --yes < /dev/null
}

get_version_hermes_agent() {
    local hermes
    hermes=$(_hermes_cmd) || { echo ""; return 0; }
    # "Hermes Agent v0.22.6 (2026.9.24) · stable · local f0d94882e89a"
    "$hermes" --version 2>/dev/null | grep -oP -m1 'Hermes Agent v\K[0-9]+\.[0-9]+(\.[0-9]+)?' || echo ""
}

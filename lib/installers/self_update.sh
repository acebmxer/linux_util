#!/bin/bash
# Self-update script functions

self_update_script() {
    info "Checking for script updates..."
    if ! command -v git &>/dev/null; then
        warn "git is not installed; cannot self-update."
        return 1
    fi
    if [[ ! -d "${SCRIPT_DIR}/.git" ]]; then
        warn "Script directory is not a git repository; cannot self-update."
        return 1
    fi
    local before
    before=$(git -C "$SCRIPT_DIR" rev-parse HEAD 2>/dev/null)
    if ! git -C "$SCRIPT_DIR" pull --ff-only origin main; then
        warn "git pull failed. Ensure you have network access and no local uncommitted changes."
        return 1
    fi
    local after
    after=$(git -C "$SCRIPT_DIR" rev-parse HEAD 2>/dev/null)
    if [[ "$before" != "$after" ]]; then
        info "Script updated to $(git -C "$SCRIPT_DIR" rev-parse --short HEAD). Restarting..."
        # Clean up before re-exec (EXIT trap does not fire on exec)
        [[ -n "$SUDO_KEEPALIVE_PID" ]] && kill "$SUDO_KEEPALIVE_PID" 2>/dev/null || true
        exec bash "$SCRIPT_PATH" "${ORIGINAL_ARGS[@]}"
    else
        info "Script is already up to date."
    fi
    return 0
}

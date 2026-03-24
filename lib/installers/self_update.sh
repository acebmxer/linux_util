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
    # Ensure we're on main and up to date with origin
    git -C "$SCRIPT_DIR" fetch origin main 2>/dev/null || {
        warn "git fetch failed. Ensure you have network access."
        return 1
    }
    local before
    before=$(git -C "$SCRIPT_DIR" rev-parse HEAD 2>/dev/null)
    local pull_err
    if ! pull_err=$(git -C "$SCRIPT_DIR" pull --ff-only origin main 2>&1); then
        # Pull failed — likely untracked/modified files conflict with upstream
        # (common after switching branches). Warn the user before discarding
        # local changes, since reset --hard + clean -fd are destructive.
        warn "git pull failed: $pull_err"
        warn "Local modifications in ${SCRIPT_DIR} will be discarded to sync with origin/main."
        local _reset_confirm
        read -n 1 -rp "Reset to origin/main? Any local changes will be lost. (y/N) " _reset_confirm < /dev/tty
        echo
        if [[ ! "$_reset_confirm" =~ ^[Yy]$ ]]; then
            warn "Self-update aborted. Resolve git conflicts manually in ${SCRIPT_DIR}."
            return 1
        fi
        git -C "$SCRIPT_DIR" checkout main 2>/dev/null
        git -C "$SCRIPT_DIR" reset --hard origin/main 2>/dev/null
        # Clean any remaining untracked files that conflict with tracked files
        git -C "$SCRIPT_DIR" clean -fd 2>/dev/null
        if [[ "$(git -C "$SCRIPT_DIR" rev-parse HEAD 2>/dev/null)" == "$(git -C "$SCRIPT_DIR" rev-parse origin/main 2>/dev/null)" ]]; then
            info "Resolved by resetting to origin/main."
        else
            warn "Unable to auto-resolve. Manual intervention required."
            return 1
        fi
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

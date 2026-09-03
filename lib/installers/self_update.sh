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
    local channel="${CFG_UPDATE_CHANNEL:-main}"

    # A release tag in update_channel means "pin here". Check the tag out if we
    # are not already on it, then stop -- a pin gets no further updates until
    # the user changes the channel.
    if [[ "$channel" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        git -C "$SCRIPT_DIR" fetch --tags --quiet origin 2>/dev/null || true
        if ! git -C "$SCRIPT_DIR" rev-parse --verify --quiet "refs/tags/${channel}" >/dev/null; then
            warn "update_channel is pinned to ${channel}, but no such tag exists."
            warn "Check the tag name, or set update_channel to main or dev in linux_util.conf."
            return 1
        fi
        local _on_tag
        _on_tag=$(git -C "$SCRIPT_DIR" describe --tags --exact-match HEAD 2>/dev/null || echo "")
        if [[ "$_on_tag" == "$channel" ]]; then
            info "Pinned to ${channel} (update_channel); already there, skipping self-update."
        else
            info "Pinned to ${channel} (update_channel); checking out that release..."
            if ! git -C "$SCRIPT_DIR" checkout --quiet "$channel" 2>/dev/null; then
                warn "Could not check out ${channel}. Commit or stash local changes first."
                return 1
            fi
            info "Now pinned to ${channel}."
        fi
        local _newest
        _newest=$(git -C "$SCRIPT_DIR" tag --sort=-v:refname 2>/dev/null | head -1)
        if [[ -n "$_newest" && "$_newest" != "$channel" ]]; then
            info "A newer release is available: ${_newest}"
            info "To move up, set update_channel in linux_util.conf to ${_newest} (or to main)."
        fi
        return 0
    fi

    # Detect the current branch so updates track whichever branch was checked out
    local current_branch
    current_branch=$(git -C "$SCRIPT_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null)
    if [[ -z "$current_branch" || "$current_branch" == "HEAD" ]]; then
        # Detached HEAD — the user has intentionally checked out a tagged release
        # (e.g. `git checkout v1.0.0`) or a specific commit. Treat that as a pin
        # and skip the auto-pull; dragging them onto a branch tip would silently
        # undo the pin. Run from a branch (`git checkout main`) to resume updates.
        local pinned_ref
        pinned_ref=$(git -C "$SCRIPT_DIR" describe --tags --exact-match HEAD 2>/dev/null \
            || git -C "$SCRIPT_DIR" rev-parse --short HEAD 2>/dev/null || echo "unknown")
        info "Pinned to ${pinned_ref} (detached HEAD); skipping self-update."
        info "To resume rolling updates: git -C \"${SCRIPT_DIR}\" checkout ${channel}"
        info "(update_channel is '${channel}', but a manual checkout takes precedence.)"
        return 0
    fi
    # Channel names a branch: move onto it if the user is somewhere else.
    if [[ "$current_branch" != "$channel" ]]; then
        info "update_channel is '${channel}'; switching from '${current_branch}'..."
        git -C "$SCRIPT_DIR" fetch --quiet origin "$channel" 2>/dev/null || true
        if git -C "$SCRIPT_DIR" checkout --quiet "$channel" 2>/dev/null; then
            current_branch="$channel"
        else
            warn "Could not switch to '${channel}'. Staying on '${current_branch}'."
            warn "Commit or stash local changes, or set update_channel to '${current_branch}'."
        fi
    fi

    info "Current branch: $current_branch"
    git -C "$SCRIPT_DIR" fetch origin "$current_branch" 2>/dev/null || {
        warn "git fetch failed. Ensure you have network access."
        return 1
    }
    local before
    before=$(git -C "$SCRIPT_DIR" rev-parse HEAD 2>/dev/null)
    local pull_err
    if ! pull_err=$(git -C "$SCRIPT_DIR" pull --ff-only origin "$current_branch" 2>&1); then
        # Pull failed — likely untracked/modified files conflict with upstream
        # (common after switching branches). Warn the user before discarding
        # local changes, since reset --hard + clean -fd are destructive.
        warn "git pull failed: $pull_err"
        warn "Local modifications in ${SCRIPT_DIR} will be discarded to sync with origin/${current_branch}."
        local _reset_confirm
        while true; do
            read -n 1 -rp "Reset to origin/${current_branch}? Any local changes will be lost. (y/N) " _reset_confirm < /dev/tty
            echo
            [[ $'\e' == "$_reset_confirm" ]] && { read -r -n 10 -t 0.05 _ < /dev/tty 2>/dev/null || true; continue; }
            _reset_confirm="${_reset_confirm:-N}"
            case "$_reset_confirm" in
                y|Y) break ;;
                n|N)
                    warn "Self-update aborted. Resolve git conflicts manually in ${SCRIPT_DIR}."
                    return 1
                    ;;
                *) echo "  Please press Y or N." ;;
            esac
        done
        git -C "$SCRIPT_DIR" checkout "$current_branch" 2>/dev/null
        git -C "$SCRIPT_DIR" reset --hard "origin/$current_branch" 2>/dev/null
        # Clean any remaining untracked files that conflict with tracked files
        git -C "$SCRIPT_DIR" clean -fd 2>/dev/null
        if [[ "$(git -C "$SCRIPT_DIR" rev-parse HEAD 2>/dev/null)" == "$(git -C "$SCRIPT_DIR" rev-parse "origin/$current_branch" 2>/dev/null)" ]]; then
            info "Resolved by resetting to origin/$current_branch."
        else
            warn "Unable to auto-resolve. Manual intervention required."
            return 1
        fi
    fi
    local after
    after=$(git -C "$SCRIPT_DIR" rev-parse HEAD 2>/dev/null)
    if [[ "$before" != "$after" ]]; then
        info "Script updated to $(git -C "$SCRIPT_DIR" rev-parse --short HEAD) on branch '$current_branch'. Restarting..."
        # Clean up before re-exec (EXIT trap does not fire on exec)
        [[ -n "$SUDO_KEEPALIVE_PID" ]] && kill "$SUDO_KEEPALIVE_PID" 2>/dev/null || true
        exec bash "$SCRIPT_PATH" "${ORIGINAL_ARGS[@]}"
    else
        info "Script is already up to date."
    fi
    return 0
}

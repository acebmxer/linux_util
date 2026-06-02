#!/bin/bash

# ============================================================================
# Shared helper functions used across multiple installer scripts.
# This file is sourced first (underscore prefix sorts before letters).
# ============================================================================

# Prompt the user to confirm a potentially destructive step.
# Returns 0 (yes) only on an explicit y/yes; defaults to No on Enter or anything else.
_confirm_step() {
    local prompt="$1" reply=""
    read -rp "${YELLOW:-}${prompt} [y/N]: ${RESET:-}" reply < /dev/tty
    [[ "${reply,,}" =~ ^(y|yes)$ ]]
}

# Gate a repair flow on whether a read-only check found problems.
# $1 = non-empty when issues were detected (caller reports the specifics).
#   Issues found -> return 0 (proceed with repair).
#   No issues    -> ask "Continue anyway?"; return 1 (caller should stop) unless the user opts in.
_repair_gate() {
    [[ -n "$1" ]] && return 0
    _confirm_step "No issues found. Continue anyway?" && return 0
    info "Nothing to do — exiting."
    return 1
}

# True only when the system has actually flagged that a reboot is required.
# Repair-style tasks (repo/package fixes) use this so the orchestrator's reboot
# prompt is offered only when a real restart is pending — e.g. a kernel pulled in
# by a dependency repair — rather than after every successful run.
_reboot_required() {
    # Debian/Ubuntu marker dropped by update-notifier-common.
    [[ -f /var/run/reboot-required ]] && return 0
    # RHEL/Fedora: needs-restarting -r exits non-zero when a reboot is pending.
    if command -v needs-restarting >/dev/null 2>&1; then
        needs-restarting -r >/dev/null 2>&1 || return 0
    fi
    return 1
}

# Final return for a repair task that completed: surface a reboot prompt only
# when one is genuinely pending, otherwise report "no changes" (exit 3) so the
# orchestrator skips the reboot prompt and offers to reload the menu instead.
_repair_done() {
    _reboot_required && return 0
    return 3
}

# Parse a multi-select string (e.g. "1,3-5") into deduplicated indices (input order preserved).
# Prints one index per line; returns 1 on invalid input.
_parse_multi_selection() {
    local input="$1" max="$2"
    local -a indices=()
    local part start end i

    IFS=',' read -ra parts <<< "$input"
    for part in "${parts[@]}"; do
        part="${part// /}"
        [[ -z "$part" ]] && continue
        if [[ "$part" =~ ^([0-9]+)-([0-9]+)$ ]]; then
            start="${BASH_REMATCH[1]}"
            end="${BASH_REMATCH[2]}"
            if (( start < 1 || end > max || start > end )); then
                return 1
            fi
            for (( i=start; i<=end; i++ )); do
                indices+=("$i")
            done
        elif [[ "$part" =~ ^[0-9]+$ ]]; then
            if (( part < 1 || part > max )); then
                return 1
            fi
            indices+=("$part")
        else
            return 1
        fi
    done

    (( ${#indices[@]} == 0 )) && return 1
    # Deduplicate while preserving the user's input order
    printf '%s\n' "${indices[@]}" | awk '!seen[$0]++'
}

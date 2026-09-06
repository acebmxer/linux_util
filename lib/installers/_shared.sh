#!/bin/bash

# ============================================================================
# Shared helper functions used across multiple installer scripts.
# This file is sourced first (underscore prefix sorts before letters).
# ============================================================================

# Prompt the user to confirm a potentially destructive step.
# Returns 0 (yes) only on an explicit y/yes; defaults to No on Enter or anything else.
#
# Two cases answer without asking:
#   auto_confirm=true   -- the user has opted into unattended runs, so proceed.
#   no terminal         -- a piped or scripted run cannot answer, and the old
#                          behaviour (reading /dev/tty unconditionally) either
#                          failed the read and fell through to "No" by accident
#                          or blocked outright. Decline explicitly instead, so
#                          an unattended run never takes a destructive branch
#                          nobody approved.
_confirm_step() {
    local prompt="$1" reply=""

    if [[ "${CFG_AUTO_CONFIRM:-false}" == "true" ]]; then
        info "${prompt} [auto-confirmed]"
        return 0
    fi

    # Test that /dev/tty can actually be opened, not merely that it exists: a
    # detached session (setsid, cron, a systemd unit) still passes -r but errors
    # on open, which would leak a raw shell error before declining.
    if ! { : < /dev/tty; } 2>/dev/null; then
        warn "${prompt} -- declining, no terminal to ask on (set auto_confirm=true to proceed unattended)."
        return 1
    fi

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
    # Arch family: no marker file and no needs-restarting, so neither check above
    # can ever fire -- the script reported "No reboot needed" while the desktop
    # was showing a reboot notification for the very same upgrade. Detect it the
    # way the OS itself does, from the live system.
    _reboot_required_arch && return 0
    return 1
}

# Arch has no /var/run/reboot-required and ships no needs-restarting, so a
# pending restart has to be read off the running system. Two independent signals,
# either one sufficient:
#
#   1. The running kernel's module tree is gone. pacman deletes
#      /usr/lib/modules/<release> when it upgrades the kernel package, so its
#      absence means the running kernel is no longer the installed one -- and
#      module loading for the running kernel is already broken.
#   2. Running processes still map files that have been replaced on disk. A
#      library upgraded underneath a running process keeps the old inode mapped
#      and shows in /proc/<pid>/maps as "(deleted)"; the new code is not in use
#      until that process restarts. This is what fires for an ordinary library
#      upgrade (openssl, curl, util-linux, mesa, wireplumber) where the kernel
#      never changed.
#
# Both read only /proc and the filesystem: no sudo, no package-manager call, so
# this is safe to run at the end of every batch. Only /usr paths count -- a
# process holding a deleted temp file or a browser's shm segment is not a system
# upgrade and must not trigger a reboot prompt.
_reboot_required_arch() {
    [[ "${DISTRO_FAMILY:-}" == "arch" ]] || return 1

    # 1. Running kernel replaced on disk.
    local _kver
    _kver="$(uname -r 2>/dev/null)"
    if [[ -n "$_kver" ]] && [[ -d /usr/lib/modules || -d /lib/modules ]]; then
        if [[ ! -d "/usr/lib/modules/${_kver}" && ! -d "/lib/modules/${_kver}" ]]; then
            return 0
        fi
    fi

    # 2. Stale system libraries or binaries still mapped by a running process.
    # Assigned, not piped into grep -q: the caller runs under `set -o pipefail`,
    # and grep -q exits on the first match, which SIGPIPEs the sort feeding it --
    # so the pipeline reported failure exactly when files WERE found, and the
    # check silently inverted itself inside the real script while passing in a
    # harness without pipefail.
    local _stale
    _stale="$(_reboot_stale_files)"
    [[ -n "$_stale" ]] && return 0

    return 1
}

# Print the distinct system files that have been replaced on disk but are still
# mapped by a running process, one per line (empty when there are none). Used for
# the detection above and to tell the user what actually needs the restart.
_reboot_stale_files() {
    # Most processes map nothing stale, so the inner grep fails for nearly every
    # maps file. Under the caller's `set -o pipefail` those failures would become
    # the pipeline's status, so the greps are contained in a subshell whose own
    # status is discarded and only the collected output is piped onward. Returns
    # 0 with output when stale files exist, 1 when there are none.
    local _out
    _out="$(
        for _maps in /proc/[0-9]*/maps; do
            # A maps line is: address perms offset dev inode path. Only
            # file-backed mappings under /usr count, and only those replaced.
            grep -hE '^[^ ]+ [^ ]+ [^ ]+ [^ ]+ [0-9]+ +/usr/(lib|lib32|bin|sbin)/.*\(deleted\)$' \
                "$_maps" 2>/dev/null || true
        done | sed -E 's/^([^ ]+ ){5} *//; s/ \(deleted\)$//' | sort -u
    )"
    [[ -n "$_out" ]] || return 1
    printf '%s\n' "$_out"
}

# Final return for a repair task that completed: surface a reboot prompt only
# when one is genuinely pending, otherwise report "no changes" (exit 3) so the
# orchestrator skips the reboot prompt and offers to reload the menu instead.
_repair_done() {
    _reboot_required && return 0
    return 3
}

# Map the stale files above back to the packages that own them, comma-separated
# on one line, for the "Triggered by:" notice. A single upgrade can leave thirty
# stale paths (wireplumber alone contributes twenty modules), so listing files
# would bury the answer; the package names are what the user recognises. Falls
# back to nothing when the package manager cannot be queried -- the warning above
# still stands on its own.
_reboot_stale_packages() {
    local _files
    _files="$(_reboot_stale_files)"
    [[ -n "$_files" ]] || return 0

    case "${PKG_MGR:-}" in
        pacman) ;;
        *) return 0 ;;
    esac

    # A file that was REPLACED is often unowned under its old name: pacman knows
    # the package's current path, so a versioned soname bumped by the upgrade
    # (libgpgme.so.45.1.2 -> .46.0.0, libgallium-26.2.1 -> 26.2.2) resolves to
    # nothing. Ask about each path, and when that fails retry the unversioned
    # soname in the same directory, which the new package does own.
    local _f _owner _base _alt
    {
        while IFS= read -r _f; do
            [[ -n "$_f" ]] || continue
            if _owner="$(pacman -Qoq "$_f" 2>/dev/null)" && [[ -n "$_owner" ]]; then
                printf '%s\n' "$_owner"
                continue
            fi
            # libfoo.so.1.2.3 -> libfoo.so ; libfoo-1.2.3-arch1.so -> unchanged
            _base="${_f##*/}"
            _alt="${_f%/*}/${_base%%.so.*}.so"
            [[ "$_alt" != "$_f" && -e "$_alt" ]] || continue
            _owner="$(pacman -Qoq "$_alt" 2>/dev/null)" || continue
            [[ -n "$_owner" ]] && printf '%s\n' "$_owner"
        done <<< "$_files"
    } | sort -u | paste -sd, - | sed 's/,/, /g'
}

# Prompt for a desktop-environment install tier (Minimal / Standard / Full).
# $1 = DE display name, used in the prompt text only (e.g. "KDE Plasma").
# Echoes one of: minimal | standard | full  (capture with $(...)).
# All prompt output goes to stderr so it doesn't pollute the captured value.
# Defaults to "standard" on empty input, EOF, or when no terminal is attached.
_prompt_de_tier() {
    local de="$1" reply=""
    {
        printf '\n%sSelect a %s installation type:%s\n' "${BOLD:-}" "$de" "${RESET:-}"
        printf '  1) Minimal/Core   — base desktop only, fewest packages\n'
        printf '  2) Standard       — desktop plus common applications (Recommended)\n'
        printf '  3) Full Suite     — every default %s application\n\n' "$de"
        printf '%sEnter choice [1-3] (default 2): %s' "${YELLOW:-}" "${RESET:-}"
    } >&2
    # Prompt is emitted above (to stderr) rather than via `read -rp`, because the
    # 2>/dev/null needed to silence a missing-/dev/tty error would also hide read's
    # own prompt, leaving a blank line that looks like a hang.
    read -r reply < /dev/tty 2>/dev/null || reply=""
    case "$reply" in
        1) echo "minimal" ;;
        3) echo "full" ;;
        *) echo "standard" ;;
    esac
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

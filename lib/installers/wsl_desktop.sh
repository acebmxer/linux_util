#!/bin/bash
# WSL Desktop — install a full desktop environment inside a WSL distro and
# display it through WSLg (the GUI support built into WSL on Windows 11 and
# recent Windows 10 updates; no separate X server or RDP setup needed).
#
# This is a picker, not its own installer: it lists whichever "Desktop
# Environments" utilities are actually registered for this distro (the same
# per-distro availability checks in installers.sh already apply) and delegates
# straight to that utility's own install_* function. There is no separate
# WSL-specific install path to maintain — one DE installer, reused here.

# ── Version / status ──────────────────────────────────────────────────────────
# Not a single on/off state (any number of DEs could be installed), so this
# always reports empty like the other picker-style system tasks.
get_version_wsl_desktop() { :; }

# _wsl_desktop_candidates prints the display-environment utility names
# available on this distro, one per line, in registration order.
_wsl_desktop_candidates() {
    local name
    for name in "${UTILITIES[@]}"; do
        [[ "${UTILITY_CATEGORY[$name]:-}" == "Desktop Environments" ]] && printf '%s\n' "$name"
    done
}

# ── Main interactive function ─────────────────────────────────────────────────
setup_wsl_desktop() {
    if ! is_wsl; then
        warn "This machine is not running under WSL — nothing to do."
        echo "  WSL Desktop installs a desktop environment inside a WSL distro for use"
        echo "  with WSLg. On a native Linux install, use the Desktop Environments"
        echo "  category instead."
        return 0
    fi

    echo ""
    echo "${BOLD:-}${CYAN:-}════════════════════════════════════════════════════════════════${RESET:-}"
    echo "${BOLD:-}${CYAN:-}  WSL Desktop                                                     ${RESET:-}"
    echo "${BOLD:-}${CYAN:-}════════════════════════════════════════════════════════════════${RESET:-}"
    echo ""

    local -a candidates
    mapfile -t candidates < <(_wsl_desktop_candidates)
    if [[ ${#candidates[@]} -eq 0 ]]; then
        warn "No desktop environments are available for this distro."
        return 1
    fi

    {
        printf '  Choose a desktop environment to install:\n\n'
        local i=1 name status
        for name in "${candidates[@]}"; do
            status=""
            "${CHECK_FUNCS[$name]}" >/dev/null 2>&1 && status=" (already installed)"
            printf '  %2d)  %s%s\n' "$i" "$name" "$status"
            (( i++ ))
        done
        printf '   0)  Cancel\n\n'
    } > /dev/tty

    local choice
    while true; do
        read -rp "Select [0-${#candidates[@]}]: " choice < /dev/tty
        [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 0 && choice <= ${#candidates[@]} )) && break
        printf '%sInvalid selection.%s\n' "${RED:-}" "${RESET:-}" > /dev/tty
    done
    [[ "$choice" == "0" ]] && { info "Cancelled."; return 2; }

    local de_name="${candidates[$((choice - 1))]}"
    info "Installing ${de_name}..."
    "${INSTALL_FUNCS[$de_name]}"
    local rc=$?
    (( rc != 0 )) && return $rc

    echo ""
    if [[ -n "${WAYLAND_DISPLAY:-}" || -n "${DISPLAY:-}" ]]; then
        info "${de_name} installed. Log out of this WSL session and back in (or run 'wsl --shutdown' from Windows and reopen the distro) to start it through WSLg."
    else
        warn "${de_name} installed, but no WSLg display was detected in this session (\$WAYLAND_DISPLAY / \$DISPLAY are unset)."
        echo "  WSLg ships with WSL on Windows 11 and recent Windows 10 builds. If it is"
        echo "  missing, run 'wsl --update' from an elevated Windows prompt, then restart"
        echo "  the distro ('wsl --shutdown' from Windows, then reopen it)."
    fi
    return 0
}

# ── Lifecycle stubs ───────────────────────────────────────────────────────────
check_wsl_desktop()     { return 1; }
uninstall_wsl_desktop() { return 0; }
update_wsl_desktop()    { setup_wsl_desktop; }

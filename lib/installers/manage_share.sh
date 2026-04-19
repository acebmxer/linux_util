#!/bin/bash
# Manage Share — top-level menu that lets the user choose to update or unmount
# an existing linux_util-managed mount. Delegates entirely to setup_update_mount
# and setup_unmount_share, which are defined in their respective files.

# ── Version / status ──────────────────────────────────────────────────────────
get_version_manage_share() {
    local count=0
    if [[ -f /etc/fstab ]]; then
        count=$(grep -cE '^# linux_util:(nfs|smb|mount) ' /etc/fstab 2>/dev/null || true)
    fi
    [[ "$count" -gt 0 ]] && echo "${count} linux_util-managed mount(s)"
}

# ── Main interactive function ─────────────────────────────────────────────────
setup_manage_share() {
    echo ""
    echo "${BOLD:-}${CYAN:-}════════════════════════════════════════════════════════════════${RESET:-}"
    echo "${BOLD:-}${CYAN:-}  Manage Share                                                   ${RESET:-}"
    echo "${BOLD:-}${CYAN:-}════════════════════════════════════════════════════════════════${RESET:-}"
    echo ""

    {
        printf '  What would you like to do?\n\n'
        printf '  1)  Update a mount\n'
        printf '  2)  Unmount a share\n'
        printf '  0)  Cancel\n\n'
    } > /dev/tty

    local action_choice
    while true; do
        read -rp "Select [0-2]: " action_choice < /dev/tty
        [[ "$action_choice" =~ ^[0-2]$ ]] && break
        printf '%sInvalid selection.%s\n' "${RED:-}" "${RESET:-}" > /dev/tty
    done

    case "$action_choice" in
        1) setup_update_mount ;;
        2) setup_unmount_share ;;
        0) info "Cancelled."; return 0 ;;
    esac
}

# ── Lifecycle stubs ───────────────────────────────────────────────────────────
check_manage_share()     { return 1; }
uninstall_manage_share() { return 0; }
update_manage_share()    { setup_manage_share; }

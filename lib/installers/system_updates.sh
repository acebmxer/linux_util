#!/bin/bash
# System Updates functions

# --- System Updates ---
setup_system_updates() {
    info "Running system updates..."
    local _snap_before
    _snap_before=$(pkg_snapshot)
    pkg_refresh_interactive
    pkg_full_upgrade_interactive
    pkg_cleanup_thorough_interactive
    info "System updates completed."
    local _snap_after
    _snap_after=$(pkg_snapshot)
    if [[ "$_snap_before" == "$_snap_after" ]]; then
        info "No package changes were made."
        return 3
    fi
    return 0
}

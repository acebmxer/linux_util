#!/bin/bash
# System Updates functions

# --- System Updates ---
setup_system_updates() {
    info "Running system updates..."
    pkg_refresh_interactive
    pkg_full_upgrade_interactive
    pkg_cleanup_thorough_interactive
    info "System updates completed."
    return 0
}

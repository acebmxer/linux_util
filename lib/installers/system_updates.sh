#!/bin/bash
# System Updates functions

# --- System Updates ---
setup_system_updates() {
    info "Running system updates..."
    pkg_refresh
    pkg_full_upgrade
    pkg_cleanup_thorough
    info "System updates completed."
    return 0
}

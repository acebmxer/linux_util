#!/bin/bash
# Full System Upgrade/Update functions

# --- Full System Upgrade/Update ---
setup_full_update() {
    info "Starting full system upgrade/update..."
    local _snap_before
    _snap_before=$(pkg_snapshot)

    # Step 1: Refresh repos
    pkg_refresh_interactive

    # Step 2: Check for distro version upgrade
    local target_version=""
    local upgrade_available=1
    if target_version=$(pkg_check_upgrade_available); then
        upgrade_available=0
    fi

    if [[ $upgrade_available -eq 0 && -n "$target_version" ]]; then
        # Determine LTS/normal labels for current and target versions
        # Ubuntu/Kubuntu LTS: XX.04 where XX is even
        local current_label="" target_label=""
        if [[ "$DISTRO_ID" == "ubuntu" || "$DISTRO_ID" == "kubuntu" ]]; then
            local cur_year cur_month
            cur_year=$(echo "$DISTRO_VERSION_ID" | cut -d. -f1)
            cur_month=$(echo "$DISTRO_VERSION_ID" | cut -d. -f2)
            if (( cur_month == 4 && cur_year % 2 == 0 )); then
                current_label=" (LTS)"
            fi
            # Target version may include text like "24.04 LTS" from do-release-upgrade
            # or just "25.10" from meta-release fallback
            local tgt_ver_num="${target_version%% *}"  # strip any trailing text
            local tgt_year tgt_month
            tgt_year=$(echo "$tgt_ver_num" | cut -d. -f1)
            tgt_month=$(echo "$tgt_ver_num" | cut -d. -f2)
            if [[ -n "$tgt_year" && -n "$tgt_month" ]] && (( tgt_month == 4 && tgt_year % 2 == 0 )); then
                # Only add LTS label if not already present in the string
                if [[ "$target_version" != *"LTS"* ]]; then
                    target_label=" (LTS)"
                fi
            else
                target_label=" (non-LTS)"
            fi

        fi

        # Display confirmation prompt
        echo ""
        echo ""
        echo "  *** A distribution upgrade is available ***"
        echo ""
        echo "  Current: ${DISTRO_NAME} ${DISTRO_VERSION_ID}${current_label}"
        echo "  Target:  ${target_version}${target_label}"
        echo ""
        echo "  The upgrade tool will determine the path automatically."
        echo "  A reboot may be required afterward. If intermediate steps are needed,"
        echo "  re-run this script after each reboot to continue."
        echo ""
        echo "  This is a major operation and may take some time."
        # Extra note for RHEL family — leapp preupgrade will run first
        if [[ "$DISTRO_FAMILY" == "rhel" ]]; then
            echo "  A leapp preupgrade check will run first to identify any blockers."
        fi
        echo ""
        local confirm=""
        read -rp "Continue with distribution upgrade? (y/N): " confirm < /dev/tty
        if [[ "$confirm" =~ ^[Yy]$ ]]; then
            local upgrade_rc=0
            pkg_distro_upgrade "$target_version" || upgrade_rc=$?

            if (( upgrade_rc == 0 )); then
                info "Distribution upgrade completed. Running cleanup..."
                pkg_cleanup_thorough_interactive
                info "Full system upgrade completed."
                return 0
            fi

            # Return code 2: no upgrade available on the selected track
            # (e.g., user chose LTS but no next LTS release exists yet).
            # Fall through to standard package updates without a warning.
            if (( upgrade_rc != 2 )); then
                # If a reboot is required (updates were applied but system needs restart),
                # don't fall through to redundant package updates — just exit cleanly.
                local reboot_needed=false
                if [[ -f /var/run/reboot-required ]]; then
                    reboot_needed=true
                elif command -v needs-restarting &>/dev/null && ! needs-restarting -r &>/dev/null; then
                    reboot_needed=true
                fi

                if [[ "$reboot_needed" == "true" ]]; then
                    info "System updates were applied. Please reboot and re-run to continue the distribution upgrade."
                    return 0
                fi

                warn "Distribution upgrade failed. Falling back to package updates..."
            fi
        else
            info "Distribution upgrade skipped by user."
        fi
    else
        info "No distribution version upgrade available."
    fi

    # Fallback: standard package update
    info "Performing package updates..."
    pkg_full_upgrade_interactive
    pkg_cleanup_thorough_interactive
    info "System update completed."
    local _snap_after
    _snap_after=$(pkg_snapshot)
    if [[ "$_snap_before" == "$_snap_after" ]]; then
        info "No package changes were made."
        return 3
    fi
    return 0
}

#!/bin/bash
# Full System Upgrade/Update functions

# --- Full System Upgrade/Update ---
setup_full_update() {
    info "Starting full system upgrade/update..."

    # Step 1: Refresh repos
    pkg_refresh

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
        local upgrade_path=""
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

            # Build sequential upgrade path for non-LTS targets
            # Ubuntu upgrades one release at a time: XX.04 → XX.10 → (XX+1).04 → ...
            if [[ -n "$tgt_year" && -n "$tgt_month" && "$tgt_ver_num" != "$DISTRO_VERSION_ID" ]]; then
                local path_steps=()
                local step_year="$cur_year" step_month="$cur_month"
                while true; do
                    # Compute next version: .04 → .10, .10 → (year+1).04
                    if (( step_month == 4 )); then
                        step_month=10
                    else
                        step_year=$(( step_year + 1 ))
                        step_month=4
                    fi
                    local next_ver
                    next_ver=$(printf "%d.%02d" "$step_year" "$step_month")
                    # Label each step
                    local step_label=""
                    if (( step_month == 4 && step_year % 2 == 0 )); then
                        step_label=" (LTS)"
                    fi
                    path_steps+=("${next_ver}${step_label}")
                    if [[ "$next_ver" == "$tgt_ver_num" ]]; then
                        break
                    fi
                    # Safety: stop after 20 steps to avoid infinite loop
                    if (( ${#path_steps[@]} >= 20 )); then
                        break
                    fi
                done
                # Only show path if there are intermediate steps (more than 1 step)
                if (( ${#path_steps[@]} > 1 )); then
                    upgrade_path="${DISTRO_VERSION_ID}${current_label}"
                    for step in "${path_steps[@]}"; do
                        upgrade_path+=" → ${step}"
                    done
                fi
            fi
        fi

        # Display confirmation prompt
        echo ""
        echo ""
        echo "  *** A distribution upgrade is available ***"
        echo ""
        echo "  Current: ${DISTRO_NAME} ${DISTRO_VERSION_ID}${current_label}"
        echo "  Target:  ${target_version}${target_label}"
        if [[ -n "$upgrade_path" ]]; then
            echo ""
            echo "  Upgrade path: ${upgrade_path}"
            echo "  Each step requires a reboot. Re-run this script after each reboot"
            echo "  to continue to the next version."
        fi
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
                pkg_cleanup_thorough
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
    pkg_full_upgrade
    pkg_cleanup_thorough
    info "System update completed."
    return 0
}

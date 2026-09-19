#!/bin/bash
# Full System Upgrade functions

# --- Full System Upgrade ---
setup_full_upgrade() {
    if _system_updates_has_arch_update; then
        local _cmd
        _cmd=$(_system_updates_arch_update_cmd)
        info "Deferring to ${_cmd} for a complete Arch-family update..."
        info "(Includes Arch news, AUR, Flatpak, orphan removal, cache cleanup, kernel/service checks)"
        echo ""
        local _snap_before _snap_after
        _snap_before=$(pkg_snapshot)
        "$_cmd"
        local _rc=$?
        _snap_after=$(pkg_snapshot)
        [[ "$_snap_before" == "$_snap_after" ]] && return 3
        return $_rc
    fi

    info "Starting full system upgrade..."

    # Step 1: Refresh repos
    pkg_refresh_interactive

    # Step 2: Check for distro version upgrade
    PKG_ALLOW_PRERELEASE_UPGRADE="$CFG_ALLOW_PRERELEASE_UPGRADE"
    local target_version=""
    local upgrade_available=1
    if target_version=$(pkg_check_upgrade_available); then
        upgrade_available=0
    fi

    local is_prerelease_target=false
    [[ "$target_version" == *" (Beta)"* || "$target_version" == *" (Devel)"* ]] && is_prerelease_target=true

    if [[ $upgrade_available -eq 0 && -n "$target_version" ]]; then
        # Determine LTS/normal labels for current and target versions
        # Ubuntu/Kubuntu LTS: XX.04 where XX is even
        # Skipped entirely for a beta/devel target -- that's its own track,
        # an LTS/non-LTS label on it would be meaningless noise.
        local current_label="" target_label=""
        if [[ "$is_prerelease_target" != true && ( "$DISTRO_ID" == "ubuntu" || "$DISTRO_ID" == "kubuntu" ) ]]; then
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
        if [[ "$is_prerelease_target" == true ]]; then
            echo "  *** A PRE-RELEASE (beta/devel) version upgrade is available ***"
        else
            echo "  *** A distribution upgrade is available ***"
        fi
        echo ""
        echo "  Current: ${DISTRO_NAME} ${DISTRO_VERSION_ID}${current_label}"
        echo "  Target:  ${target_version}${target_label}"
        echo ""
        if [[ "$is_prerelease_target" == true ]]; then
            echo "  This is an early/beta release, not the final version. Expect:"
            echo "    - Possible instability or missing package updates from third-party"
            echo "      repos (e.g. Docker, browser vendors) until the final release ships"
            echo "    - A higher chance of needing to reinstall or roll back"
            echo "    - Less community support for issues specific to this release"
            echo ""
        fi
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
        while true; do
            read -rp "Continue with distribution upgrade? (y/N): " confirm < /dev/tty
            case "${confirm,,}" in
                y|yes)
                    local upgrade_rc=0
                    pkg_distro_upgrade "$target_version" || upgrade_rc=$?

                    if (( upgrade_rc == 0 )); then
                        info "Distribution upgrade completed. Running cleanup..."
                        pkg_cleanup_thorough_interactive
                        info "Full system upgrade completed."
                        return 0
                    fi

                    if (( upgrade_rc == 2 )); then
                        # No upgrade available on the selected track (e.g. user
                        # chose LTS but no next LTS release exists yet) --
                        # pkg_distro_upgrade already reported why. Nothing to do.
                        return 3
                    fi

                    # A reboot mid-upgrade is expected, not a failure -- the
                    # upgrade continues on the next run after the user reboots.
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

                    error "Distribution upgrade failed."
                    return 1
                    ;;
                n|no|'')
                    info "Distribution upgrade skipped by user."
                    return 2
                    ;;
                *) echo "  Please enter Y or N." ;;
            esac
        done
    else
        info "No distribution version upgrade available. Run \"System Updates\" for regular package updates."
        return 3
    fi
}

# --- Version/status for Full System Upgrade ---
# Returns the next available distro version for display in the menu.
# Shows nothing when no upgrade is available.
_FULL_UPGRADE_CACHE=""
_FULL_UPGRADE_CHECKED=false
get_version_full_upgrade() {
    # Cache the result so the (potentially slow) network check runs only once
    if [[ "$_FULL_UPGRADE_CHECKED" == true ]]; then
        [[ -n "$_FULL_UPGRADE_CACHE" ]] && echo "$_FULL_UPGRADE_CACHE"
        return 0
    fi
    _FULL_UPGRADE_CHECKED=true

    PKG_ALLOW_PRERELEASE_UPGRADE="$CFG_ALLOW_PRERELEASE_UPGRADE"
    local target_version=""
    target_version=$(pkg_check_upgrade_available 2>/dev/null) || { return 0; }
    [[ -z "$target_version" ]] && return 0

    # Build display string with LTS/non-LTS label for Ubuntu-family.
    # Skipped for a beta/devel target -- the (Beta)/(Devel) label already
    # embedded in target_version says everything that needs saying.
    local label=""
    if [[ "$target_version" != *" (Beta)"* && "$target_version" != *" (Devel)"* ]]; then
        case "$DISTRO_ID" in
            ubuntu|kubuntu|pop|neon)
                local tgt_num="${target_version%% *}"  # strip trailing text like "LTS"
                local tgt_year tgt_month
                tgt_year=$(echo "$tgt_num" | cut -d. -f1)
                tgt_month=$(echo "$tgt_num" | cut -d. -f2)
                if [[ -n "$tgt_year" && -n "$tgt_month" ]] && (( tgt_month == 4 && tgt_year % 2 == 0 )); then
                    [[ "$target_version" != *"LTS"* ]] && label=" LTS"
                fi
                ;;
        esac
    fi

    _FULL_UPGRADE_CACHE="↑ ${target_version}${label} available"
    echo "$_FULL_UPGRADE_CACHE"
}

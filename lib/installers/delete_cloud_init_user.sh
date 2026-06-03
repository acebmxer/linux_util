#!/bin/bash
# Delete Default Cloud-Init User — remove the stock account(s) that cloud/VM
# images ship with, along with the home directory.
#
# Action-style system task: always listed in the menu. The status column shows
# "Cloud Init user found" while one of the known accounts still exists, and goes
# blank once it has been removed (or never existed).
#
# Known default cloud-init accounts (matches the four distros requested):
#   ubuntu, debian, centos, alpine
#
# Detection is by account presence rather than by DISTRO_ID so the task behaves
# correctly on Ubuntu derivatives too (e.g. Kubuntu/Neon, whose DISTRO_ID is not
# literally "ubuntu" but whose images still ship the "ubuntu" user).
#
# Removal command:
#   deluser --remove-home   on systems that provide deluser (Debian/Ubuntu, Alpine)
#   userdel --remove        elsewhere (CentOS/RHEL family has no deluser)

# Stock accounts cloud/VM images ship with, across the supported distros.
_CLOUD_INIT_USERS=(ubuntu debian centos alpine)

# Print the known cloud-init accounts that currently exist (one per line).
_existing_cloud_init_users() {
    local u
    for u in "${_CLOUD_INIT_USERS[@]}"; do
        id "$u" &>/dev/null && printf '%s\n' "$u"
    done
}

# Status line for the menu: present only while a default cloud-init account
# still exists; blank otherwise.
get_version_delete_cloud_init_user() {
    [[ -n "$(_existing_cloud_init_users)" ]] && printf 'Cloud Init user found'
}

delete_cloud_init_user() {
    local -a users
    mapfile -t users < <(_existing_cloud_init_users)

    if (( ${#users[@]} == 0 )); then
        info "No default cloud-init user found — nothing to do."
        return 3
    fi

    local current="${SUDO_USER:-$USER}"
    local user rc removed=0 skipped=0

    for user in "${users[@]}"; do
        # Never delete the account this run is operating under — doing so would
        # pull the home directory out from beneath the active session.
        if [[ "$user" == "$current" ]]; then
            warn "Skipping '${user}': it is the account you are currently logged in as."
            warn "Log in as a different sudo-capable user to remove it."
            (( skipped += 1 ))
            continue
        fi

        warn "This permanently deletes user '${user}' and removes its home directory."
        if ! _confirm_step "Delete cloud-init user '${user}'?"; then
            info "Skipped '${user}'."
            (( skipped += 1 ))
            continue
        fi

        # deluser/userdel refuse (or leave orphans) while the account has live
        # sessions or processes; clear them first.
        if pgrep -u "$user" >/dev/null 2>&1; then
            info "Terminating processes owned by '${user}'..."
            sudo pkill -KILL -u "$user" 2>/dev/null || true
            sleep 1
        fi

        if command -v deluser >/dev/null 2>&1; then
            info "Deleting user '${user}' (deluser --remove-home)..."
            sudo deluser --remove-home "$user"; rc=$?
        else
            info "Deleting user '${user}' (userdel --remove)..."
            sudo userdel --remove "$user"; rc=$?
        fi

        if (( rc != 0 )); then
            error "Failed to delete user '${user}' (exit ${rc})."
            return 1
        fi
        info "User '${user}' and its home directory have been removed."
        (( removed += 1 ))
    done

    # Exit 3 = success with no reboot needed (and covers the all-skipped case).
    return 3
}

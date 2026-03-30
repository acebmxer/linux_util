#!/bin/bash
# Enable RDP — unified installer for xrdp and krdp
#
# xrdp:  traditional RDP server, X11-based, broad distro support
# krdp:  KDE-native RDP server, Wayland-based (KDE Plasma 6+, recommended for Kubuntu 26.04+)
#
# Note: running both simultaneously is not supported — they would conflict on port 3389.
# xrdp functions live in xrdp.sh and are called directly by this dispatcher.

# --- krdp helpers ---

# Return list of human users (UID 1000-59999, real home dir, valid shell)
_krdp_human_users() {
    while IFS=: read -r username _ uid _ _ homedir shell; do
        [[ "$uid" -ge 1000 && "$uid" -lt 60000 ]] || continue
        [[ "$shell" == */false || "$shell" == */nologin ]] && continue
        [[ -d "$homedir" ]] || continue
        echo "$username"
    done < /etc/passwd
}

# Prompt user to select from the list of human accounts.
# Prints the chosen username to stdout only; all UI output goes to stderr.
# Returns 2 if the user skips/cancels.
_krdp_prompt_user() {
    local -a users=()
    mapfile -t users < <(_krdp_human_users)

    if [[ ${#users[@]} -eq 0 ]]; then
        warn "No human users found — skipping user configuration." >&2
        return 2
    fi

    echo "" >&2
    echo "${BOLD}${CYAN}Which user should be able to connect via RDP?${RESET}" >&2
    echo "${DIM}(They will log in using their normal system password)${RESET}" >&2
    echo "" >&2
    for i in "${!users[@]}"; do
        printf "  %d) %s\n" "$((i + 1))" "${users[$i]}" >&2
    done
    echo "" >&2

    local choice
    while true; do
        read -rp "Choice [1-${#users[@]}, or q to skip]: " choice < /dev/tty
        [[ "$choice" == "q" || "$choice" == "Q" ]] && return 2
        if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#users[@]} )); then
            echo "${users[$((choice - 1))]}"   # only the username goes to stdout
            return 0
        fi
        echo "  Please enter a number between 1 and ${#users[@]}, or q to skip." >&2
    done
}

# Enable the plasma-krdp systemd user service for a given user, headlessly.
# Sets up linger so it survives reboots without requiring a local login.
_krdp_enable_service() {
    local rdp_user="$1"
    local rdp_uid
    rdp_uid=$(id -u "$rdp_user")
    local xdg_runtime="/run/user/${rdp_uid}"
    local rdp_home
    rdp_home=$(getent passwd "$rdp_user" | cut -d: -f6)

    # Write krdprc — tells krdp which system account to authenticate against.
    # The RDP client connects using this username + the account's system password (PAM).
    info "Writing krdp config for ${rdp_user}..."
    run_as_root mkdir -p "${rdp_home}/.config"
    run_as_root tee "${rdp_home}/.config/krdprc" > /dev/null << EOF
[General]
enabled=true
username=${rdp_user}
EOF
    run_as_root chown "${rdp_user}:${rdp_user}" "${rdp_home}/.config/krdprc"
    run_as_root chmod 600 "${rdp_home}/.config/krdprc"

    # Enable linger so the user's systemd instance starts at boot without a local login
    info "Enabling linger for ${rdp_user} (allows service to run without local login)..."
    run_as_root loginctl enable-linger "$rdp_user"

    # Ensure the user's systemd runtime dir exists (linger may take a moment)
    if [[ ! -d "$xdg_runtime" ]]; then
        info "Starting user@${rdp_uid} systemd instance..."
        run_as_root systemctl start "user@${rdp_uid}.service" || true
        sleep 2
    fi

    # Enable and start plasma-krdp as the target user
    info "Enabling app-org.kde.krdpserver.service for ${rdp_user}..."
    if sudo -u "$rdp_user" \
            XDG_RUNTIME_DIR="$xdg_runtime" \
            DBUS_SESSION_BUS_ADDRESS="unix:path=${xdg_runtime}/bus" \
            systemctl --user enable --now app-org.kde.krdpserver.service; then
        info "krdp is running for ${rdp_user}."
        info "Connect via RDP using username '${rdp_user}' and their system password."
    else
        warn "Service enable failed — ${rdp_user} may need to enable it via System Settings > Remote Desktop."
    fi
}

# Disable the plasma-krdp service and linger for a given user
_krdp_disable_service() {
    local rdp_user="$1"
    local rdp_uid
    rdp_uid=$(id -u "$rdp_user" 2>/dev/null) || return 0
    local xdg_runtime="/run/user/${rdp_uid}"

    info "Disabling krdp service for ${rdp_user}..."
    sudo -u "$rdp_user" \
        XDG_RUNTIME_DIR="$xdg_runtime" \
        DBUS_SESSION_BUS_ADDRESS="unix:path=${xdg_runtime}/bus" \
        systemctl --user disable --now app-org.kde.krdpserver.service 2>/dev/null || true

    run_as_root loginctl disable-linger "$rdp_user" 2>/dev/null || true
}

# --- krdp ---

check_krdp() {
    pkg_check_installed krdp
}

install_krdp() {
    info "Installing krdp..."
    ensure_tools

    case "$DISTRO_FAMILY" in
        debian)
            run_as_root apt-get update
            run_as_root apt-get install -y krdp
            ;;
        arch)
            run_as_root pacman -S --noconfirm krdp
            ;;
        *)
            error "krdp is not available for ${DISTRO_ID}. Try xrdp instead."
            return 1
            ;;
    esac

    local rdp_user
    rdp_user=$(_krdp_prompt_user) || {
        info "krdp installed. To configure later, re-run and select Enable RDP."
        return 0
    }

    _krdp_enable_service "$rdp_user"
    return 0
}

uninstall_krdp() {
    info "Uninstalling krdp..."

    # Disable service + linger for any user that has a krdprc config
    while IFS=: read -r username _ uid _ _ homedir _; do
        [[ "$uid" -ge 1000 && "$uid" -lt 60000 ]] || continue
        [[ -f "${homedir}/.config/krdprc" ]] || continue
        _krdp_disable_service "$username"
        run_as_root rm -f "${homedir}/.config/krdprc"
    done < /etc/passwd

    case "$DISTRO_FAMILY" in
        debian)
            run_as_root apt purge --autoremove -y krdp
            ;;
        arch)
            run_as_root pacman -Rs --noconfirm krdp 2>/dev/null || true
            ;;
        *)
            error "krdp uninstall not supported for ${DISTRO_ID}"
            return 1
            ;;
    esac

    info "krdp has been uninstalled."
}

update_krdp() {
    info "Updating krdp..."
    case "$DISTRO_FAMILY" in
        debian)
            run_as_root apt-get update
            run_as_root apt-get upgrade -y krdp
            ;;
        arch)
            run_as_root pacman -S --noconfirm krdp
            ;;
    esac
}

get_version_krdp() {
    dpkg-query -W -f='${Version}' krdp 2>/dev/null | grep -oP '[0-9]+\.[0-9]+[0-9.]*' | head -1 \
        || pacman -Q krdp 2>/dev/null | awk '{print $2}' \
        || echo ""
}

# --- Enable RDP (unified dispatcher) ---

check_enable_rdp() {
    check_xrdp || check_krdp
}

install_enable_rdp() {
    echo ""
    echo "${BOLD}${CYAN}Select RDP Server to Install:${RESET}"
    echo ""
    echo "  1) xrdp  — traditional, X11-based, works on most distros"
    echo "  2) krdp  — KDE-native, Wayland-based (recommended for KDE Plasma 6 / Kubuntu 26.04+)"
    echo ""

    local choice
    while true; do
        read -rp "Choice [1-2, or q to cancel]: " choice < /dev/tty
        case "$choice" in
            1) install_xrdp; return $? ;;
            2) install_krdp; return $? ;;
            q|Q) return 2 ;;
            *) echo "Please enter 1, 2, or q to cancel." ;;
        esac
    done
}

uninstall_enable_rdp() {
    local removed=false
    if check_xrdp; then
        uninstall_xrdp && removed=true
    fi
    if check_krdp; then
        uninstall_krdp && removed=true
    fi
    if [[ "$removed" == "false" ]]; then
        info "No RDP server found to uninstall."
    fi
}

update_enable_rdp() {
    if check_xrdp; then
        update_xrdp
    fi
    if check_krdp; then
        update_krdp
    fi
}

get_version_enable_rdp() {
    if check_xrdp; then
        local v
        v=$(get_version_xrdp)
        echo "xrdp${v:+ v${v}}"
    elif check_krdp; then
        local v
        v=$(get_version_krdp)
        echo "krdp${v:+ v${v}}"
    fi
}

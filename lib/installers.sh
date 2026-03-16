#!/bin/bash

# ============================================================================
# Linux Utilities - Installers Module
# Provides installation, uninstallation, update, and version check functions
# for all utilities and system setup tasks
# ============================================================================

get_version_landscape_motd() {
    pkg_get_version landscape-client | grep -oE '^[0-9]+\.[0-9]+\.[0-9]+' || echo ""
}

check_landscape_motd() {
    pkg_check_installed landscape-client
}

setup_local_motd() {
    info "Installing/Updating Landscape Client and configuring Local MOTD..."

    run_as_root "add-apt-repository -y ppa:landscape/self-hosted-beta 2>/dev/null || true"
    run_as_root "apt-get update && apt-get install -y --no-install-recommends landscape-client" || {
        warn "Failed to install landscape-client"
        return 1
    }

    local motd_code='# Display MOTD for ZSH
if [ -f /etc/update-motd.d/00-header ]; then
    /etc/update-motd.d/00-header
fi
if [ -f /etc/update-motd.d/10-help-text ]; then
    /etc/update-motd.d/10-help-text
fi
if [ -f /etc/update-motd.d/50-motd-news ]; then
    /etc/update-motd.d/50-motd-news
fi
if [ -f /etc/update-motd.d/85-fwupd ]; then
    /etc/update-motd.d/85-fwupd
fi
if [ -f /etc/update-motd.d/90-updates-available ]; then
    /etc/update-motd.d/90-updates-available
fi
if [ -f /etc/update-motd.d/91-contract-ua-esm-status ]; then
    /etc/update-motd.d/91-contract-ua-esm-status
fi
if [ -f /etc/update-motd.d/91-release-upgrade ]; then
    /etc/update-motd.d/91-release-upgrade
fi
if [ -f /etc/update-motd.d/95-hwe-eol ]; then
    /etc/update-motd.d/95-hwe-eol
fi
if [ -f /etc/update-motd.d/98-fsck-at-reboot ]; then
    /etc/update-motd.d/98-fsck-at-reboot
fi
if [ -f /etc/update-motd.d/98-reboot-required ]; then
    /etc/update-motd.d/98-reboot-required
fi'

    if [[ -f "${HOME}/.bashrc" ]]; then
        if ! grep -q "Display MOTD for ZSH" "${HOME}/.bashrc"; then
            echo "" >> "${HOME}/.bashrc"
            echo "$motd_code" >> "${HOME}/.bashrc"
            info "Added MOTD display code to ~/.bashrc"
        else
            info "MOTD code already present in ~/.bashrc"
        fi
    fi

    if [[ -f "${HOME}/.zshrc" ]]; then
        if ! grep -q "Display MOTD for ZSH" "${HOME}/.zshrc"; then
            echo "" >> "${HOME}/.zshrc"
            echo "$motd_code" >> "${HOME}/.zshrc"
            info "Added MOTD display code to ~/.zshrc"
        else
            info "MOTD code already present in ~/.zshrc"
        fi
    fi

    info "Local MOTD configuration complete."
}

uninstall_landscape_motd() {
    info "Uninstalling Landscape Client and removing MOTD configuration..."
    run_as_root "apt-get remove -y landscape-client" || warn "Failed to uninstall landscape-client"

    if [[ -f "${HOME}/.bashrc" ]]; then
        sed -i '/^# Display MOTD for ZSH/,/^fi$/d' "${HOME}/.bashrc"
        info "Removed MOTD code from ~/.bashrc"
    fi

    if [[ -f "${HOME}/.zshrc" ]]; then
        sed -i '/^# Display MOTD for ZSH/,/^fi$/d' "${HOME}/.zshrc"
        info "Removed MOTD code from ~/.zshrc"
    fi

    info "Local MOTD configuration removed."
}

update_landscape_motd() {
    info "Updating Landscape Client..."
    run_as_root "apt-get update && apt-get upgrade -y landscape-client" || warn "Failed to update landscape-client"
    info "Landscape Client updated."
}

self_update_script() {
    info "Checking for script updates..."
    if ! command -v git &>/dev/null; then
        warn "git is not installed; cannot self-update."
        return 1
    fi
    if [[ ! -d "${SCRIPT_DIR}/.git" ]]; then
        warn "Script directory is not a git repository; cannot self-update."
        return 1
    fi
    local before
    before=$(git -C "$SCRIPT_DIR" rev-parse HEAD 2>/dev/null)
    if ! git -C "$SCRIPT_DIR" pull --ff-only origin main; then
        warn "git pull failed. Ensure you have network access and no local uncommitted changes."
        return 1
    fi
    local after
    after=$(git -C "$SCRIPT_DIR" rev-parse HEAD 2>/dev/null)
    if [[ "$before" != "$after" ]]; then
        info "Script updated to $(git -C "$SCRIPT_DIR" rev-parse --short HEAD). Restarting..."
        # Clean up before re-exec (EXIT trap does not fire on exec)
        [[ -n "$SUDO_KEEPALIVE_PID" ]] && kill "$SUDO_KEEPALIVE_PID" 2>/dev/null || true
        exec bash "$SCRIPT_PATH" "${ORIGINAL_ARGS[@]}"
    else
        info "Script is already up to date."
    fi
    return 0
}

# --- Installable Utilities ---
# ALPHABETICAL ORDER CRITICAL: Utilities appear A-Z in menu (lines 1253+)
#
# WHEN ADDING A NEW UTILITY, FOLLOW THIS CHECKLIST:
# ┌─ Step 1: Choose alphabetically correct position (between similar names)
# ├─ Step 2: Write register_utility line with these requirements:
# │  • register_utility "Display Name" install_fn check_fn uninstall_fn update_fn [get_version_fn]
# │  • Display Name must be unique and human-readable
# │  • All function names must follow pattern: {verb}_{utility_slug}
# │    (Examples: install_brave, check_docker, get_version_qbittorrent)
# │  • version_fn is OPTIONAL—only provide if you implement get_version_X function
# │
# ├─ Step 3: Implement required functions (place after System Tasks section)
# │  REQUIRED (4 functions):
# │    ├─ install_utility_name() — main installation logic
# │    ├─ check_utility_name() — returns 0 if installed, 1 if missing
# │    ├─ uninstall_utility_name() — remove utility and cleanup
# │    └─ update_utility_name() — update to latest version
# │
# │  OPTIONAL (1 function):
# │    └─ get_version_utility_name() — outputs version string only (no labels)
# │       IF provided, register it as 6th parameter (see register_utility call)
# │       Version function MUST output clean version string: "X.Y.Z" or timestamp
# │       Test it by running: ./linux_util.sh; then check "(vX.Y.Z)" in menu
# │
# ├─ Step 4: Test menu rendering
# │  $ ./linux_util.sh
# │  ├─ Verify new utility appears in correct alphabetical position
# │  ├─ If has version_fn: verify "(vX.Y.Z)" displays in menu
# │  ├─ If no version_fn: verify "(installed)" shows when utility is present
# │  └─ Verify checkbox selection/deselection works (SPACE key)
# │
# └─ Step 5: Test functionality
#    ├─ Test with --dry-run flag (./linux_util.sh --dry-run)
#    ├─ Select utility and press ENTER to verify install() function works
#    ├─ Verify check_utility_name() correctly detects installed state
#    └─ Test uninstall and update functions
#
# EXAMPLE: Adding "FooBar Tool" utility
#   1. Find correct position: Between "Docker" and "Dotfiles"
#   2. Add registration: register_utility "FooBar Tool" install_foobar_tool check_foobar_tool ...
#   3. Implement functions: install_foobar_tool(), check_foobar_tool(), etc.
#   4. Optional: add get_version_foobar_tool() to show version in menu
#   5. Test it shows in menu in correct position with correct status

# --- System Tasks (must be registered before utilities) ---
register_utility "Full System Upgrade/Update" setup_full_update check_always_false noop_function setup_full_update
register_utility "KDE Desktop"        install_kde             check_kde             uninstall_kde             update_kde                get_version_kde
register_utility "NVIDIA Drivers"     install_nvidia_drivers  check_nvidia_drivers  uninstall_nvidia_drivers  update_nvidia_drivers     get_version_nvidia_drivers
register_utility "System Updates"     setup_system_updates    check_always_false    noop_function             setup_system_updates
register_utility "XEN Guest Utilities" setup_xen_guest_utilities check_xen_guest_utilities noop_function setup_xen_guest_utilities get_version_xen_guest_utilities

# Landscape MOTD (Ubuntu, Kubuntu, KDE Neon)
if [[ "$DISTRO_ID" == "ubuntu" ]] || [[ "$DISTRO_ID" == "kubuntu" ]] || [[ "$DISTRO_ID" == "neon" ]]; then
    register_utility "Local MOTD"    setup_local_motd        check_landscape_motd  uninstall_landscape_motd  update_landscape_motd     get_version_landscape_motd
fi

# Update SYSTEM_TASK_COUNT dynamically based on actual registrations
SYSTEM_TASK_COUNT=${#UTILITIES[@]}

# --- Utilities (alphabetical order) ---
register_utility "Bitwarden Client"    install_bitwarden       check_bitwarden       uninstall_bitwarden       update_bitwarden          get_version_bitwarden
register_utility "Brave Browser"       install_brave           check_brave           uninstall_brave           update_brave              get_version_brave
register_utility "Devolutions RDM"     install_devolutions_rdm check_devolutions_rdm uninstall_devolutions_rdm update_devolutions_rdm    get_version_devolutions_rdm
register_utility "Docker"              setup_install_docker    check_docker          uninstall_docker          update_docker             get_version_docker
register_utility "Dotfiles"            setup_install_dotfiles  check_dotfiles        noop_function             setup_install_dotfiles
register_utility "Joplin Client"       install_joplin          check_joplin          uninstall_joplin          update_joplin             get_version_joplin
register_utility "LibreOffice"         install_libreoffice     check_libreoffice     uninstall_libreoffice     update_libreoffice        get_version_libreoffice
register_utility "OpenSSH Server"      install_openssh_server  check_openssh_server  uninstall_openssh_server  update_openssh_server     get_version_openssh_server
register_utility "PIA VPN"             install_pia_vpn         check_pia_vpn         uninstall_pia_vpn         update_pia_vpn            get_version_pia_vpn
register_utility "QBittorrent"         install_qbittorrent     check_qbittorrent     uninstall_qbittorrent     update_qbittorrent        get_version_qbittorrent
register_utility "Steam App"           install_steam           check_steam           uninstall_steam           update_steam              get_version_steam
register_utility "Syncthing"           install_syncthing       check_syncthing       uninstall_syncthing       update_syncthing          get_version_syncthing
register_utility "Termius SSH Client"  install_termius         check_termius         uninstall_termius         update_termius            get_version_termius
register_utility "Timeshift"           install_timeshift       check_timeshift       uninstall_timeshift       update_timeshift          get_version_timeshift
register_utility "Visual Studio Code"  install_vscode          check_vscode          uninstall_vscode          update_vscode             get_version_vscode

# --- Helper Functions for System Tasks ---
noop_function() {
    return 0
}

check_always_false() {
    return 1
}

# --- Utility Check Functions ---
check_dotfiles() {
    [[ -d ~/dotfiles ]] && [[ -f ~/.zshrc ]]
}

setup_install_dotfiles() {
    info "Installing dotfiles..."

    if [[ "$DISTRO_ID" == "fedora" || "$DISTRO_ID" == "rhel" || "$DISTRO_ID" == "centos" || "$DISTRO_ID" == "rocky" || "$DISTRO_ID" == "almalinux" ]]; then
        warn "Dotfiles installation not supported for Fedora-based distros."
        return 1
    fi

    info "Starting as regular user"
    rm -rf ~/dotfiles
    info "Previous dotfiles folder was removed."
    git clone https://github.com/flipsidecreations/dotfiles.git ~/dotfiles || { warn "Failed to clone dotfiles"; return 1; }
    (
        cd ~/dotfiles || exit 1
        ./install.sh
    ) || { warn "Dotfiles install.sh failed"; return 1; }
    chsh -s /bin/zsh || warn "Failed to change shell to zsh for current user."

    info "Installing dotfiles for root..."
    sudo -s <<'EOF'
info() { printf '\e[32m[INFO]\e[0m %s\n' "$*"; }
warn() { printf '\e[33m[WARN]\e[0m %s\n' "$*"; }
info "Now running as root"
rm -rf ~/dotfiles
git clone https://github.com/flipsidecreations/dotfiles.git ~/dotfiles || exit 0
cd ~/dotfiles || exit 0
./install.sh
if command -v chsh &> /dev/null; then
    chsh -s /bin/zsh || warn "Failed to change shell to zsh for root."
else
    warn "chsh command not found for root. Run 'chsh -s /bin/zsh' manually after installing util-linux-user package."
fi
EOF
    info "Back to regular user."

    info "Dotfiles installation completed."
    return 0
}

# --- XEN Guest Utilities ---
check_xen_guest_utilities() {
    pkg_check_installed xe-guest-utilities || pkg_check_installed xen-guest-agent || pkg_check_installed xe-guest-utilities-latest
}

get_version_xen_guest_utilities() {
    local ver=""
    if pkg_check_installed xe-guest-utilities; then
        ver=$(pkg_get_version xe-guest-utilities)
    elif pkg_check_installed xen-guest-agent; then
        ver=$(pkg_get_version xen-guest-agent)
    elif pkg_check_installed xe-guest-utilities-latest; then
        ver=$(pkg_get_version xe-guest-utilities-latest)
    fi
    # Strip epoch and distro suffix
    [[ -n "$ver" ]] && echo "$ver" | sed 's/^[0-9]*://; s/-.*//'
}

setup_xen_guest_utilities() {
    info "Installing/Updating XEN Guest Utilities..."

    # Primary method: ISO installation (per XCP-NG docs)
    # https://docs.xcp-ng.org/vms/#linux-guest-tools

    # Check for existing installations and optionally remove them
    if pkg_check_installed xe-guest-utilities; then
        local ver
        ver=$(pkg_get_version xe-guest-utilities)
        info "xe-guest-utilities is installed, version $ver."
        read -n 1 -rp "Would you like to uninstall existing xe-guest-utilities (v$ver) before installing new tools? [y/N] " ans
        echo
        case "$ans" in
            y|Y)
                info "Uninstalling existing xe-guest-utilities..."
                pkg_remove xe-guest-utilities || warn "Failed to remove xe-guest-utilities."
                ;;
            *)
                info "Keeping existing xe-guest-utilities."
                ;;
        esac
    fi

    if pkg_check_installed xen-guest-agent; then
        local ver
        ver=$(pkg_get_version xen-guest-agent)
        info "xen-guest-agent is installed, version $ver."
        read -n 1 -rp "Would you like to uninstall existing xen-guest-agent (v$ver) before installing new tools? [y/N] " ans
        echo
        case "$ans" in
            y|Y)
                info "Uninstalling existing xen-guest-agent..."
                pkg_remove xen-guest-agent || warn "Failed to remove xen-guest-agent."
                ;;
            *)
                info "Keeping existing xen-guest-agent."
                ;;
        esac
    fi

    # Mount the guest tools ISO (per XCP-NG docs: mount /dev/cdrom /mnt)
    local MOUNT_POINT="/mnt"
    if ! mountpoint -q "${MOUNT_POINT}"; then
        info "Attempting to mount guest tools ISO..."
        if ! sudo mount /dev/cdrom "${MOUNT_POINT}"; then
            warn "Could not mount /dev/cdrom to ${MOUNT_POINT}."
            warn "Please ensure the XCP-NG guest tools ISO is inserted in the VM's CD drive."
            echo ""
            read -n 1 -rp "Would you like to retry mounting? [y/N] " retry_ans
            echo
            if [[ "$retry_ans" =~ ^[Yy]$ ]]; then
                if ! sudo mount /dev/cdrom "${MOUNT_POINT}"; then
                    warn "Mount failed again. Falling back to repository installation..."
                    _install_from_repository
                    return $?
                fi
            else
                info "Falling back to repository installation..."
                _install_from_repository
                return $?
            fi
        fi
    fi

    if [[ -f "${MOUNT_POINT}/Linux/install.sh" ]]; then
        info "Running XCP-NG installer script from ISO..."

        # The install.sh script auto-detects Debian, CentOS, RHEL, SLES, and Ubuntu.
        # For derived distros, force detection with: -d $DISTRO -m $MAJOR_VERSION
        # See: https://docs.xcp-ng.org/vms/#linux-guest-tools
        local install_flags=""
        local major_ver="${DISTRO_VERSION_ID%%.*}"

        case "$DISTRO_FAMILY" in
            debian)
                # The ISO installer only recognises "ubuntu" and "debian" by name.
                # Ubuntu derivatives (KDE Neon, Kubuntu, etc.) must be forced to
                # install as ubuntu so the installer doesn't reject them.
                case "$DISTRO_ID" in
                    ubuntu|debian)
                        install_flags=""
                        ;;
                    *)
                        install_flags="-d ubuntu -m ${major_ver}"
                        ;;
                esac
                ;;
            rhel)
                # RHEL derivatives need explicit distro flags
                install_flags="-d rhel -m ${major_ver}"
                ;;
            fedora)
                install_flags="-d fedora -m ${major_ver}"
                ;;
            *)
                # For unsupported distros, try without flags first
                warn "Distro '${DISTRO_NAME}' may not be recognized by the ISO installer."
                warn "Attempting install without distro flags. If it fails, manual extraction may be needed."
                ;;
        esac

        [[ -n "$install_flags" ]] && info "Using installer flags: ${install_flags}"

        # Run the installer (per docs: bash /mnt/Linux/install.sh)
        if sudo bash "${MOUNT_POINT}/Linux/install.sh" ${install_flags}; then
            # Per XCP-NG docs: no reboot needed (old message from kernel module era)
            sudo umount /dev/cdrom 2>/dev/null || warn "Failed to unmount ${MOUNT_POINT}"
            if _verify_xen_services; then
                info "XCP-NG Guest Tools installed and services are running."
            else
                warn "XCP-NG Guest Tools installed but services may not be running correctly."
            fi
            return 0
        else
            warn "ISO installer failed. Attempting manual extraction..."
            # For unsupported distros: extract xe-guest-utilities tgz from ISO
            _install_from_iso_tgz "${MOUNT_POINT}"
            local result=$?
            sudo umount /dev/cdrom 2>/dev/null || warn "Failed to unmount ${MOUNT_POINT}"
            if [[ $result -ne 0 ]]; then
                warn "Manual extraction failed. Falling back to repository installation..."
                _install_from_repository
                return $?
            fi
            return 0
        fi
    else
        warn "Installer script not found at ${MOUNT_POINT}/Linux/install.sh."
        sudo umount /dev/cdrom 2>/dev/null || true
        info "Falling back to repository installation..."
        _install_from_repository
        return $?
    fi
}

# Extract xe-guest-utilities tgz from the ISO for unsupported distros.
# Per XCP-NG docs: extract the xe-guest-utilities_*_all.tgz archive,
# copy contents to /etc and /usr, and use the included systemd unit file.
_install_from_iso_tgz() {
    local mount_point="$1"
    local tgz_file
    tgz_file=$(find "${mount_point}/Linux/" -name 'xe-guest-utilities_*_all.tgz' 2>/dev/null | head -1)

    if [[ -z "$tgz_file" ]]; then
        warn "No xe-guest-utilities tgz archive found on ISO."
        return 1
    fi

    info "Extracting ${tgz_file}..."
    local tmp_dir
    tmp_dir=$(mktemp -d /tmp/xen-guest-tools-XXXXXX)
    CLEANUP_FILES+=("$tmp_dir")

    if ! tar -xzf "$tgz_file" -C "$tmp_dir"; then
        warn "Failed to extract tgz archive."
        return 1
    fi

    # Copy extracted files to system directories
    if [[ -d "${tmp_dir}/etc" ]]; then
        sudo cp -a "${tmp_dir}/etc/." /etc/ || warn "Failed to copy /etc files"
    fi
    if [[ -d "${tmp_dir}/usr" ]]; then
        sudo cp -a "${tmp_dir}/usr/." /usr/ || warn "Failed to copy /usr files"
    fi

    # Enable and start the service
    if [[ -f /etc/systemd/system/xe-linux-distribution.service ]] || \
       [[ -f /usr/lib/systemd/system/xe-linux-distribution.service ]]; then
        sudo systemctl daemon-reload
        sudo systemctl enable xe-linux-distribution || warn "Failed to enable xe-linux-distribution"
        sudo systemctl start xe-linux-distribution || warn "Failed to start xe-linux-distribution"
        if _verify_xen_services; then
            info "XEN Guest Utilities installed via manual extraction and services are running."
        else
            warn "XEN Guest Utilities installed via manual extraction but services may not be running correctly."
        fi
    elif [[ -f /etc/init.d/xe-linux-distribution ]]; then
        sudo /etc/init.d/xe-linux-distribution start || warn "Failed to start xe-linux-distribution"
        info "XEN Guest Utilities installed via manual extraction (init.d)."
        warn "Cannot verify init.d service status automatically."
    else
        warn "No systemd unit or init script found. Service may need manual configuration."
    fi

    return 0
}

# Verify that the xe-linux-distribution service is running after installation.
_verify_xen_services() {
    local svc="xe-linux-distribution"
    local max_attempts=6
    local wait_seconds=5

    info "Verifying ${svc} service started..."
    local attempt=0
    while (( attempt < max_attempts )); do
        if systemctl is-active --quiet "${svc}"; then
            info "${svc} service is running."
            return 0
        fi
        (( attempt++ ))
        if (( attempt < max_attempts )); then
            sleep "$wait_seconds"
        fi
    done

    warn "${svc} service failed to start within $(( max_attempts * wait_seconds )) seconds."
    warn "Service status:"
    systemctl status "${svc}" --no-pager 2>&1 | head -20
    return 1
}

# Helper function: Install XEN utilities from repository (fallback method)
_install_from_repository() {
    info "Attempting repository installation..."

    case "$DISTRO_FAMILY" in
        debian)
            info "Installing xe-guest-utilities via apt..."
            if run_as_root "apt-get update && apt-get install -y xe-guest-utilities"; then
                if _verify_xen_services; then
                    info "XEN Guest Utilities installed and services are running."
                else
                    warn "XEN Guest Utilities installed but services may not be running correctly."
                fi
                return 0
            fi
            return 1
            ;;

        fedora|rhel)
            run_as_root "yum install -y epel-release" 2>/dev/null || true
            info "Installing xe-guest-utilities via yum..."
            if run_as_root "yum install -y xe-guest-utilities-latest" 2>/dev/null || \
               run_as_root "yum install -y xe-guest-utilities"; then
                run_as_root "systemctl enable xe-linux-distribution" || warn "Failed to enable xe-linux-distribution"
                run_as_root "systemctl start xe-linux-distribution" || warn "Failed to start xe-linux-distribution"
                if _verify_xen_services; then
                    info "XEN Guest Utilities installed and services are running."
                else
                    warn "XEN Guest Utilities installed but services may not be running correctly."
                fi
                return 0
            fi
            return 1
            ;;

        arch)
            info "Installing xe-guest-utilities via pacman..."
            if run_as_root "pacman -S --noconfirm xe-guest-utilities"; then
                if _verify_xen_services; then
                    info "XEN Guest Utilities installed and services are running."
                else
                    warn "XEN Guest Utilities installed but services may not be running correctly."
                fi
                return 0
            fi
            return 1
            ;;

        suse)
            info "Installing xe-guest-utilities via zypper..."
            if run_as_root "zypper install -y xe-guest-utilities"; then
                if _verify_xen_services; then
                    info "XEN Guest Utilities installed and services are running."
                else
                    warn "XEN Guest Utilities installed but services may not be running correctly."
                fi
                return 0
            fi
            return 1
            ;;

        alpine)
            info "Installing xe-guest-utilities via apk..."
            if run_as_root "apk add -X http://dl-cdn.alpinelinux.org/alpine/edge/community xe-guest-utilities"; then
                if _verify_xen_services; then
                    info "XEN Guest Utilities installed and services are running."
                else
                    warn "XEN Guest Utilities installed but services may not be running correctly."
                fi
                return 0
            fi
            return 1
            ;;

        *)
            error "Repository installation not supported for ${DISTRO_NAME}"
            return 1
            ;;
    esac
}

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
        echo "  This is a major operation and may take some time."
        # Extra note for RHEL family — leapp preupgrade will run first
        if [[ "$DISTRO_FAMILY" == "rhel" ]]; then
            echo "  A leapp preupgrade check will run first to identify any blockers."
        fi
        echo ""
        local confirm=""
        read -rp "Continue with distribution upgrade? (y/N): " confirm
        if [[ "$confirm" =~ ^[Yy]$ ]]; then
            if pkg_distro_upgrade "$target_version"; then
                info "Distribution upgrade completed. Running cleanup..."
                pkg_cleanup_thorough
                info "Full system upgrade completed."
                return 0
            fi

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

# --- System Updates ---
setup_system_updates() {
    info "Running system updates..."
    pkg_refresh
    pkg_full_upgrade
    pkg_cleanup_thorough
    info "System updates completed."
    return 0
}

# --- KDE Desktop ---
check_kde() {
    command -v plasmashell &>/dev/null || \
        pkg_check_installed plasma-desktop || \
        pkg_check_installed kde-plasma-desktop || \
        pkg_check_installed kde-full || \
        pkg_check_installed plasma-meta
}

get_version_kde() {
    # NOTE: Do NOT run 'plasmashell --version' here — even with QT_QPA_PLATFORM=offscreen,
    # it can crash the running plasmashell instance via D-Bus singleton conflicts (Plasma 6).
    local version=""
    # Try kf6-config (Plasma 6) or kf5-config (Plasma 5)
    if command -v kf6-config &>/dev/null; then
        version=$(kf6-config --version 2>/dev/null | grep -oP 'KDE Frameworks: \K[0-9.]+' | head -1)
    elif command -v kf5-config &>/dev/null; then
        version=$(kf5-config --version 2>/dev/null | grep -oP 'KDE Frameworks: \K[0-9.]+' | head -1)
    fi
    if [[ -n "$version" ]]; then
        echo "$version"
    else
        # Fallback: try to get version from package manager
        # Strip epoch (e.g. "4:") and distro suffix (e.g. "-0zneon+24.04+...")
        local pkg_ver
        pkg_ver=$(pkg_get_version plasma-desktop 2>/dev/null || pkg_get_version kde-plasma-desktop 2>/dev/null || echo "")
        echo "$pkg_ver" | sed 's/^[0-9]*://; s/-.*//'
    fi
}

install_kde() {
    setup_install_kde
}

uninstall_kde() {
    echo "Uninstalling KDE Desktop..."
    case "$DISTRO_FAMILY" in
        debian)
            sudo apt remove -y kde-full kde-plasma-desktop plasma-desktop sddm
            sudo apt autoremove -y
            ;;
        fedora|rhel)
            sudo "$PKG_MGR" group remove -y @kde-desktop-environment || \
                sudo "$PKG_MGR" group remove -y 'KDE Plasma Workspaces'
            sudo "$PKG_MGR" autoremove -y
            ;;
        arch)
            sudo pacman -Rs --noconfirm plasma-meta kde-applications-meta sddm 2>/dev/null || true
            ;;
        suse)
            sudo zypper remove -y -t pattern kde kde_plasma
            ;;
    esac
    echo "KDE Desktop uninstalled. You may need to install another desktop environment."
}

update_kde() {
    echo "Updating KDE Desktop..."
    case "$DISTRO_FAMILY" in
        debian)
            sudo apt update
            sudo apt upgrade -y kde-full plasma-desktop
            ;;
        fedora|rhel)
            if ! sudo "$PKG_MGR" group update -y @kde-desktop-environment 2>/dev/null && \
               ! sudo "$PKG_MGR" group update -y 'KDE Plasma Workspaces' 2>/dev/null; then
                # Fallback: update individual packages if group update fails
                echo "Group update not available, updating individual KDE packages..."
                sudo "$PKG_MGR" upgrade -y plasma-desktop plasma-workspace sddm \
                    plasma-nm plasma-pa plasma-systemmonitor kdeplasma-addons \
                    bluedevil breeze-gtk kscreen kinfocenter kwrited \
                    konsole dolphin kate ark gwenview okular spectacle \
                    kde-settings-plasma kde-gtk-config xdg-desktop-portal-kde
            fi
            ;;
        arch)
            sudo pacman -Syu --noconfirm plasma-meta kde-applications-meta
            ;;
        suse)
            sudo zypper update -y -t pattern kde kde_plasma
            ;;
    esac
}

setup_install_kde() {
    info "Installing KDE Desktop..."
    ensure_tools

    case "$PKG_MGR" in
        apt)
            run_as_root "apt-get update"
            info "Installing KDE Full Desktop Environment..."
            run_as_root "apt-get install -y kde-full sddm" || {
                error "Failed to install KDE Full Desktop Environment"
                return 1
            }
            info "Enabling display manager..."
            run_as_root "systemctl enable sddm" || warn "Failed to enable sddm"
            run_as_root "systemctl start sddm" || warn "Failed to start sddm"
            ;;

        dnf|yum)
            info "Installing KDE Full Desktop Environment..."
            if ! run_as_root "$PKG_MGR groupinstall -y 'KDE Plasma Workspaces'" 2>/dev/null && \
               ! run_as_root "$PKG_MGR group install -y @kde-desktop-environment" 2>/dev/null; then
                info "Group install not available, installing KDE packages individually..."
                run_as_root "$PKG_MGR install -y epel-release" 2>/dev/null || true
                run_as_root "crb enable" 2>/dev/null || run_as_root "$PKG_MGR config-manager --set-enabled crb" 2>/dev/null || true
                run_as_root "$PKG_MGR install -y plasma-desktop plasma-workspace sddm \
                    plasma-nm plasma-pa plasma-systemmonitor kdeplasma-addons plasma-thunderbolt \
                    bluedevil breeze-gtk kscreen kinfocenter kwrited \
                    konsole dolphin kate ark gwenview okular spectacle \
                    kde-settings-plasma kde-gtk-config xdg-desktop-portal-kde \
                    phonon-qt5-backend-gstreamer" || {
                    error "Failed to install KDE Full Desktop Environment packages"
                    return 1
                }
            fi
            info "Enabling display manager..."
            run_as_root "systemctl enable sddm" || run_as_root "systemctl set-default graphical.target"
            run_as_root "systemctl start sddm" || warn "Failed to start sddm"
            ;;

        zypper)
            info "Installing KDE Full Desktop Environment..."
            run_as_root "zypper install -y -t pattern kde kde_plasma kde_utilities kde_imaging kde_multimedia kde_office kde_games" || {
                error "Failed to install KDE Full Desktop Environment"
                return 1
            }
            info "Enabling display manager..."
            run_as_root "systemctl enable sddm" || run_as_root "systemctl set-default graphical.target"
            run_as_root "systemctl start sddm" || warn "Failed to start sddm"
            ;;

        pacman)
            info "Installing KDE Full Desktop Environment..."
            run_as_root "pacman -S --noconfirm plasma-meta kde-applications-meta sddm" || {
                error "Failed to install KDE Full Desktop Environment"
                return 1
            }
            info "Enabling display manager..."
            run_as_root "systemctl enable sddm"
            run_as_root "systemctl start sddm" || warn "Failed to start sddm"
            ;;

        *)
            error "KDE installation not fully supported for ${DISTRO_ID}"
            return 1
            ;;
    esac

    info "KDE Desktop installed successfully. Reboot to start using KDE."
    return 0
}

# --- NVIDIA Drivers & Toolkit ---
check_nvidia_drivers() {
    command -v nvidia-smi &>/dev/null || lsmod | grep -q "^nvidia"
}
get_version_nvidia_drivers() {
    nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null | head -1 || echo ""
}

install_nvtop_package() {
    echo "Installing nvtop..."
    case "$PKG_MGR" in
        apt)
            sudo apt-get update
            sudo apt-get install -y nvtop
            ;;
        dnf|yum)
            sudo "$PKG_MGR" install -y nvtop
            ;;
        pacman)
            sudo pacman -S --noconfirm nvtop
            ;;
        zypper)
            sudo zypper install -y nvtop
            ;;
    esac
}

install_nvidia_container_toolkit() {
    echo "Installing NVIDIA Container Toolkit for Docker..."
    case "$DISTRO_FAMILY" in
        debian)
            ensure_tools
            curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | \
                sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
            curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
                sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
                sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list >/dev/null
            sudo apt-get update
            sudo apt-get install -y nvidia-container-toolkit
            ;;
        fedora|rhel)
            ensure_tools
            curl -s -L https://nvidia.github.io/libnvidia-container/gpgkey | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
            curl -s -L https://nvidia.github.io/libnvidia-container/stable/rpm/nvidia-container-toolkit.repo | \
                sudo tee /etc/yum.repos.d/nvidia-container-toolkit.repo >/dev/null
            sudo "$PKG_MGR" makecache
            sudo "$PKG_MGR" install -y nvidia-container-toolkit
            ;;
        arch)
            pkg_install nvidia-container-toolkit
            ;;
        suse)
            curl -s -L https://nvidia.github.io/libnvidia-container/gpgkey | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
            curl -s -L https://nvidia.github.io/libnvidia-container/stable/rpm/nvidia-container-toolkit.repo | \
                sudo tee /etc/zypp/repos.d/nvidia-container-toolkit.repo >/dev/null
            sudo zypper refresh
            sudo zypper install -y nvidia-container-toolkit
            ;;
        *)
            warn "NVIDIA Container Toolkit installation not implemented for ${DISTRO_NAME}."
            return 1
            ;;
    esac
}

# --- NVIDIA i386 / 32-bit library helpers ---

# Save the selected NVIDIA driver version to a persistent config file so that
# other installers (e.g. Steam) can reference it later.
save_nvidia_driver_version() {
    local version="$1"
    mkdir -p "$(dirname "$NVIDIA_VERSION_FILE")"
    echo "$version" > "$NVIDIA_VERSION_FILE"
}

# Return the saved NVIDIA driver version, falling back to package detection.
get_nvidia_installed_version() {
    if [[ -f "$NVIDIA_VERSION_FILE" ]]; then
        cat "$NVIDIA_VERSION_FILE"
        return 0
    fi
    # Fallback: detect from installed packages
    case "$DISTRO_FAMILY" in
        debian)
            dpkg -l 'nvidia-driver-*' 2>/dev/null | grep '^ii' | \
                grep -oP 'nvidia-driver-\K[0-9]+' | sort -rn | head -1
            ;;
        *)
            echo ""
            ;;
    esac
}

# Return 0 if the matching NVIDIA 32-bit libraries are already installed.
check_nvidia_i386_libs() {
    local driver_version
    driver_version=$(get_nvidia_installed_version)
    [[ -z "$driver_version" ]] && return 1

    case "$DISTRO_FAMILY" in
        debian)
            dpkg -l "libnvidia-gl-${driver_version}:i386" 2>/dev/null | grep -q '^ii'
            ;;
        fedora|rhel)
            rpm -q nvidia-driver-libs.i686 &>/dev/null || \
                rpm -q xorg-x11-drv-nvidia-470xx-libs.i686 &>/dev/null || \
                rpm -q xorg-x11-drv-nvidia-390xx-libs.i686 &>/dev/null
            ;;
        arch)
            pacman -Qi lib32-nvidia-utils &>/dev/null
            ;;
        suse)
            rpm -q nvidia-32bit &>/dev/null
            ;;
        *)
            return 1
            ;;
    esac
}

# Install the NVIDIA 32-bit libraries that match the installed driver version.
# An explicit version can be passed as $1; otherwise the saved version is used.
install_nvidia_i386_libs() {
    local driver_version="${1:-}"
    if [[ -z "$driver_version" ]]; then
        driver_version=$(get_nvidia_installed_version)
    fi

    if [[ -z "$driver_version" ]]; then
        warn "Cannot determine NVIDIA driver version for 32-bit library installation."
        return 1
    fi

    echo "Installing NVIDIA 32-bit libraries (version ${driver_version})..."
    case "$DISTRO_FAMILY" in
        debian)
            sudo dpkg --add-architecture i386
            sudo apt update

            # Show currently installed NVIDIA driver to confirm version
            echo "Installed NVIDIA driver packages:"
            dpkg -l | grep nvidia-driver || echo "  (none found)"

            echo "Installing libnvidia-gl-${driver_version}:i386..."
            if ! sudo apt install -y "libnvidia-gl-${driver_version}:i386"; then
                echo ""
                echo "⚠  libnvidia-gl-${driver_version}:i386 is unavailable via apt."
                echo "Alternative: manually extract 32-bit libraries from the NVIDIA installer."
                echo ""
                echo "  1. Download the driver .run file from NVIDIA's website:"
                echo "     https://www.nvidia.com/en-us/drivers/"
                echo "     (e.g. NVIDIA-Linux-x86_64-${driver_version}.run)"
                echo ""
                echo "  2. Extract the installer:"
                echo "     sudo ./NVIDIA-Linux-x86_64-${driver_version}.run -x"
                echo ""
                echo "  3. Copy 32-bit libraries to /usr/lib32:"
                echo "     sudo cp NVIDIA-Linux-x86_64-${driver_version}/32/*.so* /usr/lib32/"
                echo "     sudo ldconfig"
                echo ""
                warn "32-bit library installation incomplete. Use the manual method above if needed."
                return 1
            fi
            ;;
        fedora|rhel)
            case "$driver_version" in
                470xx)
                    sudo "$PKG_MGR" install -y xorg-x11-drv-nvidia-470xx-libs.i686
                    ;;
                390xx)
                    sudo "$PKG_MGR" install -y xorg-x11-drv-nvidia-390xx-libs.i686
                    ;;
                *)
                    sudo "$PKG_MGR" install -y nvidia-driver-libs.i686
                    ;;
            esac
            ;;
        arch)
            sudo pacman -S --noconfirm lib32-nvidia-utils
            ;;
        suse)
            if [[ "$driver_version" =~ ^G0[0-9]$ ]]; then
                sudo zypper install -y "nvidia-${driver_version}-32bit" 2>/dev/null || \
                    sudo zypper install -y nvidia-32bit 2>/dev/null || true
            else
                sudo zypper install -y "libnvidia-gl${driver_version}-32bit" 2>/dev/null || \
                    sudo zypper install -y nvidia-32bit 2>/dev/null || true
            fi
            ;;
        *)
            warn "NVIDIA 32-bit library installation not implemented for ${DISTRO_NAME}."
            return 1
            ;;
    esac
}

install_nvidia_drivers() {
    echo "Installing NVIDIA drivers..."
    ensure_tools

    local driver_version=""
    local -a available_drivers=()

    # Detect available NVIDIA drivers based on distribution
    case "$DISTRO_FAMILY" in
        debian)
            echo "Detecting available NVIDIA drivers..."
            pkg_refresh >/dev/null 2>&1
            
            if [[ "$DISTRO_ID" == "ubuntu" ]]; then
                command -v ubuntu-drivers &>/dev/null || sudo apt-get install -y ubuntu-drivers-common
                mapfile -t available_drivers < <(ubuntu-drivers list --gpgpu 2>/dev/null | grep -oP 'nvidia-driver-\K[0-9]+' | sort -rn | uniq)
            else
                # Debian and derivatives
                mapfile -t available_drivers < <(apt-cache search '^nvidia-driver-[0-9]+$' 2>/dev/null | grep -oP 'nvidia-driver-\K[0-9]+' | sort -rn | uniq)
            fi
            ;;
        fedora|rhel)
            echo "Detecting available NVIDIA drivers..."
            
            # Check if RPM Fusion (nonfree) is enabled
            if ! dnf repolist 2>/dev/null | grep -qi 'rpmfusion.*nonfree'; then
                echo ""
                echo "[!] RPM Fusion (nonfree) repository is required for NVIDIA drivers on Fedora/RHEL."
                echo ""
                read -rp "Would you like to enable RPM Fusion repositories now? (y/N): " enable_rpmfusion
                
                if [[ "$enable_rpmfusion" =~ ^[Yy]$ ]]; then
                    echo "Enabling RPM Fusion repositories..."
                    if [[ "$DISTRO_ID" == "fedora" ]]; then
                        sudo "$PKG_MGR" install -y \
                            "https://download1.rpmfusion.org/free/fedora/rpmfusion-free-release-${DISTRO_VERSION_ID}.noarch.rpm" \
                            "https://download1.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-${DISTRO_VERSION_ID}.noarch.rpm"
                    else
                        # RHEL/CentOS
                        sudo "$PKG_MGR" install -y \
                            "https://download1.rpmfusion.org/free/el/rpmfusion-free-release-${DISTRO_VERSION_ID}.noarch.rpm" \
                            "https://download1.rpmfusion.org/nonfree/el/rpmfusion-nonfree-release-${DISTRO_VERSION_ID}.noarch.rpm"
                    fi
                    pkg_refresh >/dev/null 2>&1
                else
                    warn "RPM Fusion is required for NVIDIA drivers. Installation cancelled."
                    return 1
                fi
            fi
            
            pkg_refresh >/dev/null 2>&1
            
            # Check for available NVIDIA driver packages
            # Main driver: akmod-nvidia (latest, recommended)
            if $PKG_MGR list available akmod-nvidia &>/dev/null; then
                available_drivers+=("latest")
            fi
            
            # Legacy drivers
            if $PKG_MGR list available xorg-x11-drv-nvidia-470xx &>/dev/null; then
                available_drivers+=("470xx")
            fi
            
            if $PKG_MGR list available xorg-x11-drv-nvidia-390xx &>/dev/null; then
                available_drivers+=("390xx")
            fi
            
            # Also check for any kmod-nvidia versioned packages
            local kmod_versions
            mapfile -t kmod_versions < <($PKG_MGR list available 'kmod-nvidia-*' 2>/dev/null | grep -oP 'kmod-nvidia-\K[0-9]+' | sort -rn | uniq)
            available_drivers+=("${kmod_versions[@]}")
            ;;
        arch)
            echo "Detecting available NVIDIA drivers..."
            # Arch typically has nvidia (latest), nvidia-lts, nvidia-dkms
            available_drivers=("latest" "dkms" "lts")
            ;;
        suse)
            echo "Detecting available NVIDIA drivers..."
            pkg_refresh >/dev/null 2>&1
            
            mapfile -t available_drivers < <(zypper search -s nvidia-driver 2>/dev/null | grep -oP 'nvidia-driver-\K[0-9]+' | sort -rn | uniq)
            
            # Check for G06/G05 packages (openSUSE naming)
            if zypper search -s nvidia-computeG06 &>/dev/null; then
                available_drivers+=("G06")
            fi
            if zypper search -s nvidia-computeG05 &>/dev/null; then
                available_drivers+=("G05")
            fi
            ;;
        *)
            warn "NVIDIA driver detection not implemented for ${DISTRO_NAME}."
            return 1
            ;;
    esac

    # Display available drivers and let user select
    if [[ ${#available_drivers[@]} -eq 0 ]]; then
        warn "No NVIDIA drivers found in repositories. Please check your repository configuration."
        return 1
    fi

    echo ""
    echo "Available NVIDIA driver versions:"
    echo "────────────────────────────────────────────────────────────────"
    for i in "${!available_drivers[@]}"; do
        echo "  $((i+1)). ${available_drivers[$i]}"
    done
    echo "  0. Cancel"
    echo "────────────────────────────────────────────────────────────────"
    
    local choice
    read -rp "Select driver version to install (1-${#available_drivers[@]}, or 0 to cancel): " choice
    
    if [[ "$choice" == "0" ]] || [[ -z "$choice" ]]; then
        warn "Installation cancelled."
        return 1
    fi
    
    if [[ "$choice" =~ ^[0-9]+$ ]] && [[ "$choice" -ge 1 ]] && [[ "$choice" -le ${#available_drivers[@]} ]]; then
        driver_version="${available_drivers[$((choice-1))]}"
        echo "Selected driver version: $driver_version"
        # Persist the chosen version so other installers (e.g. Steam) can reference it
        save_nvidia_driver_version "$driver_version"
    else
        warn "Invalid selection. Cancelling installation."
        return 1
    fi

    # Install the selected driver
    case "$DISTRO_FAMILY" in
        debian)
            sudo apt-get update
            sudo apt-get install -y "nvidia-driver-${driver_version}"
            ;;
        fedora|rhel)
            case "$driver_version" in
                latest)
                    echo "Installing latest NVIDIA driver (akmod-nvidia)..."
                    sudo "$PKG_MGR" install -y akmod-nvidia xorg-x11-drv-nvidia-cuda
                    ;;
                470xx)
                    echo "Installing legacy NVIDIA 470 driver..."
                    sudo "$PKG_MGR" install -y xorg-x11-drv-nvidia-470xx akmod-nvidia-470xx
                    ;;
                390xx)
                    echo "Installing legacy NVIDIA 390 driver..."
                    sudo "$PKG_MGR" install -y xorg-x11-drv-nvidia-390xx akmod-nvidia-390xx
                    ;;
                [0-9]*)
                    echo "Installing NVIDIA driver version ${driver_version}..."
                    sudo "$PKG_MGR" install -y "kmod-nvidia-${driver_version}"
                    ;;
                *)
                    warn "Unknown driver version: ${driver_version}"
                    return 1
                    ;;
            esac
            ;;
        arch)
            case "$driver_version" in
                latest)
                    sudo pacman -S --noconfirm nvidia nvidia-utils
                    ;;
                dkms)
                    sudo pacman -S --noconfirm nvidia-dkms nvidia-utils
                    ;;
                lts)
                    sudo pacman -S --noconfirm nvidia-lts nvidia-utils
                    ;;
            esac
            ;;
        suse)
            if [[ "$driver_version" =~ ^G0[0-9]$ ]]; then
                sudo zypper install -y "nvidia-compute${driver_version}"
            else
                sudo zypper install -y "nvidia-driver-${driver_version}"
            fi
            ;;
    esac

    # Install matching 32-bit libraries (required by Steam and other 32-bit apps)
    install_nvidia_i386_libs "$driver_version"

    install_nvtop_package

    if check_docker; then
        install_nvidia_container_toolkit || warn "Failed to install NVIDIA Container Toolkit."
    else
        info "Docker not detected. Skipping NVIDIA Container Toolkit installation."
    fi
}

uninstall_nvidia_drivers() {
    echo "Uninstalling NVIDIA drivers..."
    case "$PKG_MGR" in
        apt)
            sudo apt-get remove -y 'nvidia-driver-*' nvtop
            sudo apt-get autoremove -y
            ;;
        dnf|yum)
            sudo "$PKG_MGR" remove -y nvidia* nvtop
            ;;
        pacman)
            sudo pacman -Rs --noconfirm nvidia nvidia-utils nvtop 2>/dev/null || true
            ;;
        zypper)
            sudo zypper remove -y nvidia* nvtop
            ;;
    esac
}

update_nvidia_drivers() {
    install_nvidia_drivers
}

# --- Bitwarden Client ---

check_bitwarden() {
    command -v bitwarden &>/dev/null || \
        (has_snap && snap list bitwarden &>/dev/null) || \
        (has_flatpak && flatpak list 2>/dev/null | grep -qi bitwarden) || \
        pkg_check_installed bitwarden-bin || \
        pkg_check_installed bitwarden
}
install_bitwarden() {
    echo "Installing Bitwarden Client..."
    case "$DISTRO_FAMILY" in
        debian)
            ensure_tools
            local tmp_deb
            tmp_deb=$(mktemp /tmp/bitwarden-XXXXXX.deb)
            CLEANUP_FILES+=("$tmp_deb")
            if ! wget -qO "$tmp_deb" "https://vault.bitwarden.com/download/?app=desktop&platform=linux&variant=deb"; then
                echo "Error: Failed to download Bitwarden .deb."
                rm -f "$tmp_deb"
                return 1
            fi
            # Try installing; if deps are missing, fix them and retry
            if ! sudo dpkg -i "$tmp_deb"; then
                sudo apt-get install -f -y || true
                if ! sudo dpkg -i "$tmp_deb"; then
                    echo "Error: Failed to install Bitwarden .deb."
                    rm -f "$tmp_deb"
                    return 1
                fi
            fi
            rm -f "$tmp_deb"
            ;;
        fedora|rhel)
            ensure_tools
            local tmp_rpm
            tmp_rpm=$(mktemp /tmp/bitwarden-XXXXXX.rpm)
            CLEANUP_FILES+=("$tmp_rpm")
            if ! wget -qO "$tmp_rpm" "https://vault.bitwarden.com/download/?app=desktop&platform=linux&variant=rpm"; then
                echo "Error: Failed to download Bitwarden .rpm."
                rm -f "$tmp_rpm"
                return 1
            fi
            if ! sudo "$PKG_MGR" install -y "$tmp_rpm"; then
                echo "Error: Failed to install Bitwarden .rpm."
                rm -f "$tmp_rpm"
                return 1
            fi
            rm -f "$tmp_rpm"
            ;;
        arch)
            if has_aur_helper; then
                aur_install bitwarden-bin
            else
                aur_build bitwarden-bin
            fi
            ;;
        *)
            if has_snap; then
                sudo snap install bitwarden
            elif has_flatpak; then
                flatpak install -y flathub com.bitwarden.desktop
            else
                echo "Error: snap or flatpak is required to install Bitwarden."
                return 1
            fi
            ;;
    esac
}
uninstall_bitwarden() {
    echo "Uninstalling Bitwarden Client..."
    if has_snap && snap list bitwarden &>/dev/null; then
        sudo snap remove bitwarden
    elif has_flatpak && flatpak list 2>/dev/null | grep -qi bitwarden; then
        flatpak uninstall -y com.bitwarden.desktop
    elif pkg_check_installed bitwarden-bin; then
        pkg_remove bitwarden-bin
    elif pkg_check_installed bitwarden; then
        pkg_remove bitwarden
    else
        echo "Bitwarden installation not found."
        return 1
    fi
}
update_bitwarden() {
    echo "Updating Bitwarden Client..."
    if has_snap && snap list bitwarden &>/dev/null; then
        sudo snap refresh bitwarden
    elif has_flatpak && flatpak list 2>/dev/null | grep -qi bitwarden; then
        flatpak update -y com.bitwarden.desktop
    elif [[ "$DISTRO_FAMILY" == "debian" ]]; then
        install_bitwarden
    elif [[ "$DISTRO_FAMILY" == "fedora" || "$DISTRO_FAMILY" == "rhel" ]]; then
        install_bitwarden
    elif pkg_check_installed bitwarden-bin; then
        if has_aur_helper; then
            aur_upgrade bitwarden-bin
        else
            install_bitwarden
        fi
    elif pkg_check_installed bitwarden; then
        pkg_upgrade bitwarden
    else
        echo "Bitwarden installation not found."
        return 1
    fi
}
get_version_bitwarden() {
    if has_snap && snap list bitwarden &>/dev/null; then
        snap list bitwarden 2>/dev/null | awk 'NR==2{print $2}'
    elif has_flatpak && flatpak list 2>/dev/null | grep -qi bitwarden; then
        flatpak list 2>/dev/null | grep -i bitwarden | awk -F'\t' '{print $3}'
    elif pkg_check_installed bitwarden-bin; then
        pkg_get_version bitwarden-bin | sed 's/^[0-9]*://; s/-.*//'
    elif pkg_check_installed bitwarden; then
        pkg_get_version bitwarden | sed 's/^[0-9]*://; s/-.*//'
    else
        echo ""
    fi
}

# --- Brave Browser ---

check_brave() {
    command -v brave-browser &>/dev/null || pkg_check_installed brave-browser
}
install_brave() {
    echo "Installing Brave Browser..."
    ensure_tools
    case "$DISTRO_FAMILY" in
        debian)
            sudo curl -fsSLo /usr/share/keyrings/brave-browser-archive-keyring.gpg \
                https://brave-browser-apt-release.s3.brave.com/brave-browser-archive-keyring.gpg
            echo "deb [signed-by=/usr/share/keyrings/brave-browser-archive-keyring.gpg] https://brave-browser-apt-release.s3.brave.com/ stable main" | \
                sudo tee /etc/apt/sources.list.d/brave-browser-release.list > /dev/null
            sudo apt update
            sudo apt install -y brave-browser
            ;;
        fedora|rhel)
            sudo "$PKG_MGR" install -y dnf-plugins-core 2>/dev/null || true
            sudo curl -fsSLo /etc/yum.repos.d/brave-browser.repo https://brave-browser-rpm-release.s3.brave.com/brave-browser.repo
            sudo rpm --import https://brave-browser-rpm-release.s3.brave.com/brave-core.asc
            sudo "$PKG_MGR" install -y brave-browser
            ;;
        arch)
            if has_aur_helper; then
                aur_install brave-bin
            else
                aur_build brave-bin
            fi
            ;;
        suse)
            sudo rpm --import https://brave-browser-rpm-release.s3.brave.com/brave-core.asc
            sudo zypper addrepo -f https://brave-browser-rpm-release.s3.brave.com/brave-browser.repo brave-browser 2>/dev/null || true
            sudo zypper refresh
            sudo zypper install -y brave-browser
            ;;
    esac
}
uninstall_brave() {
    echo "Uninstalling Brave Browser..."
    case "$DISTRO_FAMILY" in
        debian)
            sudo apt remove -y brave-browser
            sudo rm -f /etc/apt/sources.list.d/brave-browser-release.list
            sudo rm -f /usr/share/keyrings/brave-browser-archive-keyring.gpg
            ;;
        fedora|rhel)
            sudo "$PKG_MGR" remove -y brave-browser
            sudo rm -f /etc/yum.repos.d/brave-browser.repo
            ;;
        arch)
            aur_remove brave-bin 2>/dev/null || pkg_remove brave-browser 2>/dev/null || true
            ;;
        suse)
            sudo zypper remove -y brave-browser
            sudo zypper removerepo brave-browser 2>/dev/null || true
            ;;
    esac
}
update_brave() {
    echo "Updating Brave Browser..."
    case "$DISTRO_FAMILY" in
        debian)
            sudo apt update
            sudo apt upgrade -y brave-browser
            ;;
        arch)
            if has_aur_helper; then
                aur_upgrade brave-bin
            else
                aur_build brave-bin
            fi
            ;;
        *)
            pkg_upgrade brave-browser
            ;;
    esac
}
get_version_brave() {
    brave-browser --version 2>/dev/null | grep -oP 'Brave Browser \K[0-9]+\.[0-9]+\.[0-9]+' || echo ""
}

# --- Joplin Client ---

# Detect and export the desktop environment for AppImage installers (Joplin, etc.)
detect_and_export_desktop_env() {
    local desktop_env=""
    if [[ -n "${XDG_CURRENT_DESKTOP:-}" ]]; then
        desktop_env="$XDG_CURRENT_DESKTOP"
    elif command -v plasmashell &>/dev/null; then
        desktop_env="KDE"
    elif command -v gnome-shell &>/dev/null; then
        desktop_env="GNOME"
    elif command -v xfce4-session &>/dev/null; then
        desktop_env="XFCE"
    elif command -v cinnamon &>/dev/null; then
        desktop_env="X-Cinnamon"
    fi
    if [[ -n "$desktop_env" ]]; then
        export XDG_CURRENT_DESKTOP="$desktop_env"
    fi
}

check_joplin() {
    [[ -f ~/.joplin/Joplin.AppImage ]] || command -v joplin &>/dev/null
}
install_joplin() {
    echo "Installing Joplin Client..."
    detect_and_export_desktop_env

    # Download and run installer script
    local install_script
    install_script=$(wget -qO- https://raw.githubusercontent.com/laurent22/joplin/dev/Joplin_install_and_update.sh) || {
        echo "Error: Failed to download Joplin installer script."
        return 1
    }
    
    if [[ -z "$install_script" ]]; then
        echo "Error: Downloaded installer script is empty."
        return 1
    fi
    
    echo "$install_script" | bash || {
        echo "Error: Joplin installation script failed."
        return 1
    }

    # Ubuntu 24.04+ restricts unprivileged user namespaces via AppArmor,
    # which breaks Electron-based AppImages like Joplin (causes SIGTRAP crash).
    if [[ "$DISTRO_ID" == "ubuntu" ]] && [[ "${DISTRO_VERSION_ID%%.*}" -ge 24 ]]; then
        local sysctl_file="/etc/sysctl.d/99-appimage-userns.conf"
        local sysctl_key="kernel.apparmor_restrict_unprivileged_userns"
        if [[ "$(sysctl -n "$sysctl_key" 2>/dev/null)" == "1" ]]; then
            echo "Configuring system to allow AppImage user namespaces (required for Joplin on Ubuntu 24.04+)..."
            echo "${sysctl_key}=0" | sudo tee "$sysctl_file" >/dev/null
            sudo sysctl --system >/dev/null 2>&1
            echo "AppImage user namespace restriction disabled."
        fi
    fi
}
uninstall_joplin() {
    echo "Uninstalling Joplin Client..."
    rm -rf ~/.joplin
    rm -f ~/.local/share/applications/joplin.desktop
    rm -f ~/.local/share/applications/appimagekit-joplin.desktop
    rm -f ~/.local/share/icons/hicolor/*/apps/joplin.png
    rm -f ~/.local/share/icons/hicolor/*/apps/appimagekit-joplin.png
    rm -f ~/.local/bin/joplin
    command -v update-desktop-database &>/dev/null && update-desktop-database ~/.local/share/applications || true
    command -v gtk-update-icon-cache &>/dev/null && gtk-update-icon-cache ~/.local/share/icons/hicolor || true
}
update_joplin() {
    echo "Updating Joplin Client..."
    detect_and_export_desktop_env
    wget -O - https://raw.githubusercontent.com/laurent22/joplin/dev/Joplin_install_and_update.sh | bash
}
get_version_joplin() {
    # NOTE: Do NOT run the AppImage with --version — it opens a GUI error dialog.
    local version=""
    local config_home="${XDG_CONFIG_HOME:-$HOME/.config}"

    # 1. Try config file paths (created after Joplin's first launch)
    #    Use awk instead of grep -oP for portability (no PCRE/libpcre2 dependency)
    local pkg_json
    for pkg_json in "$config_home/joplin-desktop/package.json" "$config_home/joplin/package.json"; do
        if [[ -f "$pkg_json" ]]; then
            version=$(awk -F'"' '/"version"/{print $4; exit}' "$pkg_json" 2>/dev/null)
            [[ -n "$version" ]] && echo "$version" && return 0
        fi
    done

    # 2. Extract version from the AppImage's embedded metadata
    local appimage="$HOME/.joplin/Joplin.AppImage"
    if [[ -f "$appimage" ]]; then
        local tmpdir
        tmpdir=$(mktemp -d)

        # Try resources/app/package.json (Electron apps without asar packaging)
        if (cd "$tmpdir" && timeout 10 "$appimage" --appimage-extract "resources/app/package.json") &>/dev/null; then
            version=$(awk -F'"' '/"version"/{print $4; exit}' "$tmpdir/squashfs-root/resources/app/package.json" 2>/dev/null)
            if [[ -n "$version" ]]; then
                rm -rf "$tmpdir"
                echo "$version"
                return 0
            fi
        fi

        # Try the embedded .desktop file for X-AppImage-Version (works with asar-packed apps)
        if (cd "$tmpdir" && timeout 10 "$appimage" --appimage-extract "*.desktop") &>/dev/null; then
            version=$(grep -h 'X-AppImage-Version=' "$tmpdir"/squashfs-root/*.desktop 2>/dev/null | head -1 | cut -d= -f2)
            if [[ -n "$version" ]]; then
                rm -rf "$tmpdir"
                echo "$version"
                return 0
            fi
        fi

        rm -rf "$tmpdir"
    fi

    echo ""
}

# --- LibreOffice ---

check_libreoffice() {
    command -v libreoffice &>/dev/null || \
        command -v soffice &>/dev/null || \
        compgen -G "/opt/libreoffice*/program/soffice" &>/dev/null || \
        pkg_check_installed libreoffice || \
        pkg_check_installed libreoffice-common || \
        pkg_check_installed libreoffice-fresh || \
        pkg_check_installed libreoffice-still || \
        dpkg -l 'libreoffice[0-9]*' 2>/dev/null | grep -q "^ii" || \
        (has_flatpak && flatpak list 2>/dev/null | grep -qi libreoffice)
}
_libreoffice_install_from_site() {
    # Download and install LibreOffice .deb packages directly from the official site.
    # Usage: _libreoffice_install_from_site
    ensure_tools
    local lo_version arch_dir arch_file tmp_dir
    lo_version=$(wget -qO- "https://download.documentfoundation.org/libreoffice/stable/" \
        | grep -oP 'href="\K[0-9]+\.[0-9]+\.[0-9]+' | sort -V | tail -1)
    if [[ -z "$lo_version" ]]; then
        echo "Error: Could not determine latest LibreOffice version."
        return 1
    fi
    echo "Latest LibreOffice version: $lo_version"
    case "$(uname -m)" in
        x86_64)  arch_dir="x86_64"; arch_file="x86-64" ;;
        aarch64) arch_dir="aarch64"; arch_file="aarch64" ;;
        *)
            echo "Error: Unsupported architecture $(uname -m) for direct download."
            return 1
            ;;
    esac
    local url="https://download.documentfoundation.org/libreoffice/stable/${lo_version}/deb/${arch_dir}/LibreOffice_${lo_version}_Linux_${arch_file}_deb.tar.gz"
    tmp_dir=$(mktemp -d /tmp/libreoffice-install-XXXXXX)
    CLEANUP_FILES+=("$tmp_dir")
    echo "Downloading LibreOffice ${lo_version}..."
    if ! wget -q --show-progress -O "$tmp_dir/libreoffice.tar.gz" "$url"; then
        echo "Error: Failed to download LibreOffice from $url"
        rm -rf "$tmp_dir"
        return 1
    fi
    echo "Extracting..."
    tar -xzf "$tmp_dir/libreoffice.tar.gz" -C "$tmp_dir"
    local deb_dir
    deb_dir=$(find "$tmp_dir" -type d -name "DEBS" | head -1)
    if [[ -z "$deb_dir" ]]; then
        echo "Error: Could not find DEBS directory in archive."
        rm -rf "$tmp_dir"
        return 1
    fi
    echo "Installing .deb packages..."
    if ! sudo dpkg -i "$deb_dir"/*.deb; then
        sudo apt-get install -f -y || true
        if ! sudo dpkg -i "$deb_dir"/*.deb; then
            echo "Error: Failed to install LibreOffice .deb packages."
            rm -rf "$tmp_dir"
            return 1
        fi
    fi
    rm -rf "$tmp_dir"
    echo "LibreOffice ${lo_version} installed successfully."
}
install_libreoffice() {
    echo "Installing LibreOffice..."
    case "$DISTRO_FAMILY" in
        debian)
            _libreoffice_install_from_site
            ;;
        fedora|rhel)
            sudo "$PKG_MGR" check-update >/dev/null 2>&1 || true
            sudo "$PKG_MGR" install -y libreoffice
            ;;
        arch)
            sudo pacman -S --noconfirm libreoffice-fresh
            ;;
        suse)
            sudo zypper install -y libreoffice
            ;;
        *)
            if has_flatpak; then
                flatpak install -y flathub org.libreoffice.LibreOffice
            else
                echo "Error: Unsupported distribution and flatpak is not available."
                return 1
            fi
            ;;
    esac
}
uninstall_libreoffice() {
    echo "Uninstalling LibreOffice..."
    case "$DISTRO_FAMILY" in
        debian)
            sudo apt remove -y libreoffice*
            sudo apt autoremove -y
            ;;
        fedora|rhel)
            sudo "$PKG_MGR" remove -y libreoffice*
            sudo "$PKG_MGR" autoremove -y
            ;;
        arch)
            sudo pacman -Rs --noconfirm libreoffice-fresh 2>/dev/null || \
                sudo pacman -Rs --noconfirm libreoffice-still 2>/dev/null || true
            ;;
        suse)
            sudo zypper remove -y libreoffice
            ;;
        *)
            if has_flatpak && flatpak list 2>/dev/null | grep -qi libreoffice; then
                flatpak uninstall -y org.libreoffice.LibreOffice
            fi
            ;;
    esac
    echo "LibreOffice has been uninstalled."
}
update_libreoffice() {
    echo "Updating LibreOffice..."
    case "$DISTRO_FAMILY" in
        debian)
            _libreoffice_install_from_site
            ;;
        fedora|rhel)
            # Check if libreoffice is installed, if not install it instead of upgrading
            if pkg_check_installed libreoffice; then
                sudo "$PKG_MGR" upgrade -y libreoffice
            else
                install_libreoffice
            fi
            ;;
        arch)
            sudo pacman -S --noconfirm libreoffice-fresh
            ;;
        suse)
            sudo zypper update -y libreoffice
            ;;
        *)
            if has_flatpak && flatpak list 2>/dev/null | grep -qi libreoffice; then
                flatpak update -y org.libreoffice.LibreOffice
            fi
            ;;
    esac
}
get_version_libreoffice() {
    local lo_bin
    lo_bin=$(command -v libreoffice 2>/dev/null || command -v soffice 2>/dev/null || \
        compgen -G "/opt/libreoffice*/program/soffice" 2>/dev/null | sort -V | tail -1)
    [[ -n "$lo_bin" ]] && "$lo_bin" --version 2>/dev/null | grep -oP 'LibreOffice \K[0-9]+\.[0-9]+\.[0-9]+(\.[0-9]+)?' || echo ""
}

# --- Termius SSH Client ---

check_termius() {
    command -v termius &>/dev/null || \
        command -v termius-app &>/dev/null || \
        pkg_check_installed termius || \
        pkg_check_installed termius-app || \
        (has_snap && snap list termius-app &>/dev/null) || \
        (has_flatpak && flatpak list 2>/dev/null | grep -qi termius)
}
install_termius() {
    echo "Installing Termius SSH Client..."
    case "$DISTRO_FAMILY" in
        debian)
            local tmp_deb
            tmp_deb=$(mktemp /tmp/termius-XXXXXX.deb)
            CLEANUP_FILES+=("$tmp_deb")
            wget -q https://www.termius.com/download/linux/Termius.deb -O "$tmp_deb"
            sudo apt install -y "$tmp_deb"
            rm -f "$tmp_deb"
            ;;
        arch)
            if has_aur_helper; then
                aur_install termius
            else
                aur_build termius
            fi
            ;;
        *)
            if has_snap; then
                sudo snap install termius-app
            elif has_flatpak; then
                # Ensure flathub remote is properly configured
                if ! flatpak remotes | grep -q flathub; then
                    echo "Adding flathub remote..."
                    sudo flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
                fi
                sudo flatpak install -y flathub com.termius.Termius
            else
                echo "Error: snap or flatpak is required to install Termius on ${DISTRO_NAME}."
                return 1
            fi
            ;;
    esac
}
uninstall_termius() {
    echo "Uninstalling Termius SSH Client..."
    if pkg_check_installed termius; then
        pkg_remove termius
    elif pkg_check_installed termius-app; then
        pkg_remove termius-app
    elif has_snap && snap list termius-app &>/dev/null; then
        sudo snap remove termius-app
    elif has_flatpak && flatpak list 2>/dev/null | grep -qi termius; then
        flatpak uninstall -y com.termius.Termius
    else
        echo "Termius installation not found."
        return 1
    fi
}
update_termius() {
    echo "Updating Termius SSH Client..."
    case "$DISTRO_FAMILY" in
        debian)
            local tmp_deb
            tmp_deb=$(mktemp /tmp/termius-XXXXXX.deb)
            CLEANUP_FILES+=("$tmp_deb")
            wget -q https://www.termius.com/download/linux/Termius.deb -O "$tmp_deb"
            sudo apt install -y "$tmp_deb"
            rm -f "$tmp_deb"
            ;;
        arch)
            if has_aur_helper; then
                aur_upgrade termius
            else
                aur_build termius
            fi
            ;;
        *)
            if has_snap && snap list termius-app &>/dev/null; then
                sudo snap refresh termius-app
            elif has_flatpak && flatpak list 2>/dev/null | grep -qi termius; then
                flatpak update -y com.termius.Termius
            else
                echo "Termius installation not found or no supported update method."
                return 1
            fi
            ;;
    esac
}
get_version_termius() {
    if pkg_check_installed termius; then
        pkg_get_version termius | sed 's/^[0-9]*://; s/-.*//'
    elif pkg_check_installed termius-app; then
        pkg_get_version termius-app | sed 's/^[0-9]*://; s/-.*//'
    elif has_snap && snap list termius-app &>/dev/null; then
        snap list termius-app 2>/dev/null | awk 'NR==2{print $2}'
    elif has_flatpak && flatpak list 2>/dev/null | grep -qi termius; then
        flatpak list 2>/dev/null | grep -i termius | awk -F'\t' '{print $3}'
    else
        echo ""
    fi
}

# --- Devolutions RDM ---

check_devolutions_rdm() {
    command -v remotedesktopmanager &>/dev/null || pkg_check_installed RemoteDesktopManager || pkg_check_installed remotedesktopmanager || pkg_check_installed remote-desktop-manager
}
install_devolutions_rdm() {
    echo "Installing Devolutions RDM..."
    ensure_tools
    case "$DISTRO_FAMILY" in
        debian)
            # Ubuntu/Debian repository setup
            echo "Setting up Cloudsmith repository for Remote Desktop Manager..."

            # KDE Neon has ID=neon which Cloudsmith's setup.deb.sh doesn't recognise.
            # Manually add the Ubuntu-based repo using the upstream Ubuntu codename.
            if [[ "$DISTRO_ID" == "neon" ]]; then
                local ubuntu_codename="${DISTRO_VERSION_CODENAME}"
                # Fallback: read from KDE Neon's upstream release file
                if [[ -z "$ubuntu_codename" && -f /etc/upstream-release/lsb-release ]]; then
                    ubuntu_codename=$(grep -oP '(?<=DISTRIB_CODENAME=).+' /etc/upstream-release/lsb-release)
                fi
                ubuntu_codename="${ubuntu_codename:-noble}"
                echo "KDE Neon detected (Ubuntu ${ubuntu_codename} base). Configuring repository manually..."
                curl -1sLf 'https://dl.cloudsmith.io/public/devolutions/rdm/gpg.FE7407ECB26FD2FE.key' | \
                    sudo gpg --dearmor -o /usr/share/keyrings/devolutions-rdm.gpg
                echo "deb [signed-by=/usr/share/keyrings/devolutions-rdm.gpg] https://dl.cloudsmith.io/public/devolutions/rdm/deb/ubuntu ${ubuntu_codename} main" | \
                    sudo tee /etc/apt/sources.list.d/devolutions-rdm.list > /dev/null
            else
                curl -1sLf 'https://dl.cloudsmith.io/public/devolutions/rdm/setup.deb.sh' | sudo -E bash
            fi

            # Install required packages for repository management
            sudo apt-get install -y apt-transport-https 2>/dev/null || true

            # Update package lists and install Remote Desktop Manager
            sudo apt-get update
            sudo apt-get install -y remotedesktopmanager
            ;;
        fedora|rhel)
            # Fedora/RHEL repository setup
            echo "Setting up Cloudsmith repository for Remote Desktop Manager..."
            
            # Ensure required tools
            sudo "$PKG_MGR" install -y dnf-plugins-core pygpgme 2>/dev/null || true
            
            # Import GPG key
            sudo rpm --import 'https://dl.cloudsmith.io/public/devolutions/rdm/gpg.FE7407ECB26FD2FE.key'
            
            # Add repository
            curl -1sLf "https://dl.cloudsmith.io/public/devolutions/rdm/config.rpm.txt?distro=${DISTRO_ID}&codename=${DISTRO_VERSION_ID}" | \
                sudo tee /etc/yum.repos.d/devolutions-rdm.repo > /dev/null
            
            # Update repository cache and install
            sudo "$PKG_MGR" makecache -y
            sudo "$PKG_MGR" install -y RemoteDesktopManager
            ;;
        arch)
            # Arch-based distributions using AUR
            if has_aur_helper; then
                echo "Installing from AUR..."
                aur_install remote-desktop-manager
            else
                aur_build remote-desktop-manager
            fi
            ;;
        suse)
            # openSUSE support via Flatpak or snap (as direct repos may not be available)
            if has_flatpak; then
                echo "Installing via Flatpak..."
                flatpak install -y flathub com.devolutions.RemoteDesktopManager
            elif has_snap; then
                echo "Installing via Snap..."
                sudo snap install remote-desktop-manager
            else
                echo "Error: Flatpak or Snap is required to install Remote Desktop Manager on this distribution."
                echo "Please install flatpak or snap first."
                return 1
            fi
            ;;
        *)
            # Fallback to Flatpak or Snap
            if has_flatpak; then
                echo "Installing via Flatpak..."
                flatpak install -y flathub com.devolutions.RemoteDesktopManager
            elif has_snap; then
                echo "Installing via Snap..."
                sudo snap install remote-desktop-manager
            else
                echo "Error: No compatible installation method found for this distribution."
                return 1
            fi
            ;;
    esac
}
uninstall_devolutions_rdm() {
    echo "Uninstalling Devolutions RDM..."
    case "$DISTRO_FAMILY" in
        debian|fedora|rhel)
            pkg_remove RemoteDesktopManager 2>/dev/null || pkg_remove remotedesktopmanager 2>/dev/null || pkg_remove remote-desktop-manager 2>/dev/null || true
            # Clean up repository configuration for Debian
            if [[ "$DISTRO_FAMILY" == "debian" ]]; then
                sudo rm -f /etc/apt/sources.list.d/devolutions-rdm.list
            fi
            # Clean up repository configuration for RHEL/Fedora
            if [[ "$DISTRO_FAMILY" == "fedora" ]] || [[ "$DISTRO_FAMILY" == "rhel" ]]; then
                sudo rm -f /etc/yum.repos.d/devolutions-rdm.repo
            fi
            ;;
        arch)
            aur_remove remote-desktop-manager 2>/dev/null || pkg_remove remote-desktop-manager 2>/dev/null || true
            ;;
        *)
            if has_flatpak && flatpak list 2>/dev/null | grep -qi "remote.*desktop.*manager\|RemoteDesktopManager"; then
                flatpak uninstall -y com.devolutions.RemoteDesktopManager || true
            elif has_snap && snap list 2>/dev/null | grep -qi "remote-desktop-manager"; then
                sudo snap remove remote-desktop-manager || true
            else
                pkg_remove remotedesktopmanager 2>/dev/null || pkg_remove remote-desktop-manager 2>/dev/null || true
            fi
            ;;
    esac
}
update_devolutions_rdm() {
    echo "Updating Devolutions RDM..."
    case "$DISTRO_FAMILY" in
        debian)
            sudo apt update
            sudo apt install --only-upgrade -y remotedesktopmanager
            ;;
        fedora|rhel)
            sudo "$PKG_MGR" upgrade -y RemoteDesktopManager
            ;;
        arch)
            if has_aur_helper; then
                aur_upgrade remote-desktop-manager
            else
                echo "Error: An AUR helper (yay/paru) is required."
                return 1
            fi
            ;;
        *)
            if has_flatpak && flatpak list 2>/dev/null | grep -qi "remote.*desktop.*manager\|RemoteDesktopManager"; then
                flatpak update -y com.devolutions.RemoteDesktopManager
            elif has_snap && snap list 2>/dev/null | grep -qi "remote-desktop-manager"; then
                sudo snap refresh remote-desktop-manager
            else
                pkg_upgrade remotedesktopmanager 2>/dev/null || true
            fi
            ;;
    esac
}
get_version_devolutions_rdm() {
    if pkg_check_installed RemoteDesktopManager; then
        pkg_get_version RemoteDesktopManager | sed 's/^[0-9]*://; s/-.*//'
    elif pkg_check_installed remotedesktopmanager; then
        pkg_get_version remotedesktopmanager | sed 's/^[0-9]*://; s/-.*//'
    elif pkg_check_installed remote-desktop-manager; then
        pkg_get_version remote-desktop-manager | sed 's/^[0-9]*://; s/-.*//'
    else
        echo ""
    fi
}

# --- Steam App ---

check_steam() {
    command -v steam &>/dev/null || \
        pkg_check_installed steam-installer || \
        pkg_check_installed steam-launcher || \
        (has_flatpak && flatpak list 2>/dev/null | grep -qi "com.valvesoftware.Steam")
}

# Helper function to ensure contrib component is enabled for Debian
ensure_debian_contrib() {
    if [[ "$DISTRO_FAMILY" != "debian" ]]; then
        return 0
    fi

    local _contrib_found=false

    # Check traditional sources.list format
    if [[ -f /etc/apt/sources.list ]] && \
       grep -qE "^deb .*debian.* main" /etc/apt/sources.list 2>/dev/null; then
        if grep -E "^deb .*debian.* main" /etc/apt/sources.list | grep -q "contrib"; then
            _contrib_found=true
        else
            echo "Steam requires the 'contrib' component in Debian repositories."
            echo "Enabling 'contrib' component in /etc/apt/sources.list..."
            sudo cp /etc/apt/sources.list "/etc/apt/sources.list.backup-$(date +%Y%m%d-%H%M%S)"
            sudo sed -i 's/^\(deb .*debian.* main\)\(.*\)/\1 contrib\2/' /etc/apt/sources.list
            # Deduplicate 'contrib' if it appeared twice
            sudo sed -i 's/contrib contrib/contrib/g' /etc/apt/sources.list
            _contrib_found=true
        fi
    fi

    # Check DEB822 format (.sources files, Debian 12+)
    local _sources_file
    for _sources_file in /etc/apt/sources.list.d/*.sources; do
        [[ -f "$_sources_file" ]] || continue
        if grep -qP '^Components:.*\bmain\b' "$_sources_file" 2>/dev/null; then
            if grep -qP '^Components:.*\bcontrib\b' "$_sources_file" 2>/dev/null; then
                _contrib_found=true
            else
                echo "Adding 'contrib' component to $(basename "$_sources_file")..."
                sudo cp "$_sources_file" "${_sources_file}.backup-$(date +%Y%m%d-%H%M%S)"
                sudo sed -i 's/^\(Components:.*main\)/\1 contrib/' "$_sources_file"
                _contrib_found=true
            fi
        fi
    done

    if [[ "$_contrib_found" == "true" ]]; then
        echo "'contrib' component enabled. Updating package lists..."
        sudo apt update
    fi
}

# Helper function to detect mixed repository issues
detect_debian_repo_mix() {
    if [[ "$DISTRO_FAMILY" != "debian" ]]; then
        return 0
    fi
    
    local has_stable=false
    local has_testing=false
    local has_unstable=false
    
    # Check for different Debian releases in sources.list
    if grep -qE "^deb .*(bookworm|bullseye|buster)" /etc/apt/sources.list /etc/apt/sources.list.d/*.list 2>/dev/null; then
        has_stable=true
    fi
    if grep -qE "^deb .*(trixie|testing)" /etc/apt/sources.list /etc/apt/sources.list.d/*.list 2>/dev/null; then
        has_testing=true
    fi
    if grep -qE "^deb .*(sid|unstable)" /etc/apt/sources.list /etc/apt/sources.list.d/*.list 2>/dev/null; then
        has_unstable=true
    fi
    
    local mix_count=0
    $has_stable && ((mix_count++))
    $has_testing && ((mix_count++))
    $has_unstable && ((mix_count++))
    
    if [[ $mix_count -gt 1 ]]; then
        echo "⚠️  WARNING: Mixed Debian repositories detected!"
        echo "Your system has multiple Debian releases configured:"
        $has_stable && echo "  - Stable (Bookworm/Bullseye)"
        $has_testing && echo "  - Testing (Trixie)"
        $has_unstable && echo "  - Unstable (Sid)"
        echo "This can cause package version conflicts and dependency issues."
        echo "Consider using a single Debian release for better stability."
        echo ""
        return 1
    fi
    return 0
}
install_steam() {
    echo "Installing Steam..."

    # Steam requires NVIDIA 32-bit GL libraries to launch on NVIDIA systems.
    # Check whether they are present and install them if not.
    if check_nvidia_drivers; then
        if check_nvidia_i386_libs; then
            echo "NVIDIA 32-bit libraries already installed."
        else
            echo "NVIDIA drivers detected. Installing required 32-bit libraries for Steam..."
            install_nvidia_i386_libs || warn "Failed to install NVIDIA 32-bit libraries. Steam may not function correctly."
        fi
    fi

    case "$DISTRO_FAMILY" in
        debian)
            # Enable 32-bit architecture support
            sudo dpkg --add-architecture i386
            sudo apt update

            if [[ "$DISTRO_ID" == "ubuntu" ]]; then
                # Ubuntu / Kubuntu: install Steam via the multiverse repository
                echo "Enabling multiverse repository..."
                sudo add-apt-repository multiverse -y
                sudo apt update
                echo "Installing Steam..."
                if ! sudo apt install -y steam; then
                    echo "Error: Steam installation failed."
                    return 1
                fi
            else
                # Debian and other derivatives: download the official .deb installer
                echo "Downloading Steam installer from store.steampowered.com..."
                local steam_deb="/tmp/steam_latest.deb"
                if ! wget -O "$steam_deb" "https://cdn.akamai.steamstatic.com/client/installer/steam.deb"; then
                    echo "Error: Failed to download Steam installer."
                    rm -f "$steam_deb"
                    return 1
                fi

                # Install Steam - prompts will be shown for user to accept/decline
                echo "Installing Steam (follow any on-screen prompts)..."
                sudo apt install -y "$steam_deb"
                local install_result=$?
                rm -f "$steam_deb"

                if [[ $install_result -ne 0 ]]; then
                    echo "Error: Steam installation failed."
                    return 1
                fi
            fi
            ;;
        fedora)
            if ! rpm -q rpmfusion-nonfree-release &>/dev/null; then
                echo "Enabling RPM Fusion repositories (required for Steam)..."
                if ! sudo "$PKG_MGR" install -y \
                    "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm" \
                    "https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm"; then
                    echo "Error: Failed to enable RPM Fusion repositories."
                    return 1
                fi
                sudo "$PKG_MGR" makecache
            fi
            echo "Installing Steam from RPM Fusion..."
            if ! sudo "$PKG_MGR" install -y steam; then
                echo "Error: Failed to install Steam."
                return 1
            fi
            
            # Install graphics libraries for better compatibility
            echo "Installing graphics libraries (Vulkan, Mesa)..."
            sudo "$PKG_MGR" install -y mesa-vulkan-drivers vulkan-loader 2>/dev/null || true
            ;;
        rhel)
            echo "Steam is not officially available for RHEL-based distributions."
            if has_flatpak; then
                echo "Installing via Flatpak..."
                flatpak install -y flathub com.valvesoftware.Steam
            else
                echo "Consider installing Flatpak: https://flatpak.org/setup/"
                return 1
            fi
            ;;
        arch)
            if ! grep -q "^\[multilib\]" /etc/pacman.conf; then
                echo "Enabling multilib repository (required for 32-bit support)..."
                sudo bash -c 'echo -e "\n[multilib]\nInclude = /etc/pacman.d/mirrorlist" >> /etc/pacman.conf'
                sudo pacman -Sy
            fi
            echo "Installing Steam..."
            if ! sudo pacman -S --noconfirm steam; then
                echo "Error: Failed to install Steam."
                return 1
            fi
            
            # Install 32-bit graphics libraries for better compatibility
            echo "Installing 32-bit graphics libraries (Vulkan, Mesa)..."
            sudo pacman -S --noconfirm lib32-mesa lib32-vulkan-icd-loader lib32-vulkan-intel \
                lib32-vulkan-radeon lib32-nvidia-utils 2>/dev/null || true
            ;;
        suse)
            echo "Installing Steam..."
            if ! sudo zypper install -y steam; then
                echo "Error: Failed to install Steam."
                return 1
            fi
            
            # Install graphics libraries for better compatibility
            echo "Installing graphics libraries (Vulkan, Mesa)..."
            sudo zypper install -y libvulkan1 libvulkan1-32bit \
                Mesa-libGL1 Mesa-libGL1-32bit 2>/dev/null || true
            ;;
    esac
}
uninstall_steam() {
    echo "Uninstalling Steam..."
    if has_flatpak && flatpak list 2>/dev/null | grep -qi "com.valvesoftware.Steam"; then
        flatpak uninstall -y com.valvesoftware.Steam
    else
        case "$DISTRO_FAMILY" in
            debian) sudo apt remove -y steam steam-installer steam-launcher ;;
            *)      pkg_remove steam 2>/dev/null || true ;;
        esac
    fi
}
update_steam() {
    echo "Updating Steam..."
    if has_flatpak && flatpak list 2>/dev/null | grep -qi "com.valvesoftware.Steam"; then
        flatpak update -y com.valvesoftware.Steam
    else
        case "$DISTRO_FAMILY" in
            debian)
                sudo apt update
                sudo apt upgrade -y steam
                ;;
            *)
                pkg_upgrade steam
                ;;
        esac
    fi
}
get_version_steam() {
    if has_flatpak && flatpak list 2>/dev/null | grep -qi "com.valvesoftware.Steam"; then
        flatpak list 2>/dev/null | grep -i "com.valvesoftware.Steam" | awk -F'\t' '{print $3}'
    elif pkg_check_installed steam-installer; then
        pkg_get_version steam-installer | sed 's/^[0-9]*://; s/-.*//'
    elif pkg_check_installed steam-launcher; then
        pkg_get_version steam-launcher | sed 's/^[0-9]*://; s/-.*//'
    elif pkg_check_installed steam; then
        pkg_get_version steam | sed 's/^[0-9]*://; s/-.*//'
    else
        echo ""
    fi
}

# --- Timeshift ---

check_timeshift() {
    command -v timeshift &>/dev/null
}

install_timeshift() {
    echo "Installing Timeshift..."
    case "$DISTRO_FAMILY" in
        debian)
            sudo apt install timeshift -y
            ;;
        fedora|rhel)
            sudo "$PKG_MGR" install -y timeshift
            ;;
        arch)
            sudo pacman -S --noconfirm timeshift
            ;;
        suse)
            sudo zypper install -y timeshift
            ;;
        *)
            warn "Timeshift installation not implemented for ${DISTRO_NAME}."
            return 1
            ;;
    esac
    echo "Timeshift installed successfully."
}

uninstall_timeshift() {
    echo "Uninstalling Timeshift..."
    case "$DISTRO_FAMILY" in
        debian)
            sudo apt remove -y timeshift
            sudo apt autoremove -y
            ;;
        fedora|rhel)
            sudo "$PKG_MGR" remove -y timeshift
            ;;
        arch)
            sudo pacman -Rs --noconfirm timeshift
            ;;
        suse)
            sudo zypper remove -y timeshift
            ;;
    esac
}

update_timeshift() {
    echo "Updating Timeshift..."
    case "$DISTRO_FAMILY" in
        debian)
            sudo apt update && sudo apt upgrade -y timeshift
            ;;
        *)
            pkg_upgrade timeshift
            ;;
    esac
}
get_version_timeshift() {
    # Try to extract version from timeshift --version output
    local version
    version=$(timeshift --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -1)
    if [[ -n "$version" ]]; then
        echo "$version"
    else
        # Fallback: try package manager
        pkg_get_version timeshift 2>/dev/null | sed 's/^[0-9]*://; s/-.*//' || echo ""
    fi
}

# --- Visual Studio Code ---

check_vscode() {
    command -v code &>/dev/null || pkg_check_installed code
}
install_vscode() {
    echo "Installing Visual Studio Code..."
    ensure_tools
    case "$DISTRO_FAMILY" in
        debian)
            wget -qO- https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor > /tmp/packages.microsoft.gpg
            sudo install -D -o root -g root -m 644 /tmp/packages.microsoft.gpg /etc/apt/keyrings/packages.microsoft.gpg
            echo "deb [arch=amd64,arm64,armhf signed-by=/etc/apt/keyrings/packages.microsoft.gpg] https://packages.microsoft.com/repos/code stable main" | \
                sudo tee /etc/apt/sources.list.d/vscode.list > /dev/null
            rm -f /tmp/packages.microsoft.gpg
            sudo apt update
            sudo apt install -y code
            ;;
        fedora|rhel)
            sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc
            printf "[code]\nname=Visual Studio Code\nbaseurl=https://packages.microsoft.com/yumrepos/vscode\nenabled=1\ngpgcheck=1\ngpgkey=https://packages.microsoft.com/keys/microsoft.asc\n" | \
                sudo tee /etc/yum.repos.d/vscode.repo > /dev/null
            sudo "$PKG_MGR" install -y code
            ;;
        arch)
            if has_aur_helper; then
                aur_install visual-studio-code-bin
            else
                aur_build visual-studio-code-bin
            fi
            ;;
        suse)
            sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc
            printf "[code]\nname=Visual Studio Code\nbaseurl=https://packages.microsoft.com/yumrepos/vscode\nenabled=1\ntype=rpm-md\ngpgcheck=1\ngpgkey=https://packages.microsoft.com/keys/microsoft.asc\n" | \
                sudo tee /etc/zypp/repos.d/vscode.repo > /dev/null
            sudo zypper refresh
            sudo zypper install -y code
            ;;
    esac
}
uninstall_vscode() {
    echo "Uninstalling Visual Studio Code..."
    case "$DISTRO_FAMILY" in
        debian)
            sudo apt remove -y code
            sudo rm -f /etc/apt/sources.list.d/vscode.list
            sudo rm -f /etc/apt/keyrings/packages.microsoft.gpg
            ;;
        fedora|rhel)
            sudo "$PKG_MGR" remove -y code
            sudo rm -f /etc/yum.repos.d/vscode.repo
            ;;
        arch)
            aur_remove visual-studio-code-bin 2>/dev/null || pkg_remove code 2>/dev/null || true
            ;;
        suse)
            sudo zypper remove -y code
            sudo rm -f /etc/zypp/repos.d/vscode.repo
            ;;
    esac
}
update_vscode() {
    echo "Updating Visual Studio Code..."
    case "$DISTRO_FAMILY" in
        debian)
            sudo apt update
            sudo apt upgrade -y code
            ;;
        arch)
            if has_aur_helper; then
                aur_upgrade visual-studio-code-bin
            else
                aur_build visual-studio-code-bin
            fi
            ;;
        *)
            pkg_upgrade code
            ;;
    esac
}
get_version_vscode() {
    code --version 2>/dev/null | head -1 || echo ""
}

# --- Syncthing ---

check_syncthing() {
    command -v syncthing &>/dev/null || pkg_check_installed syncthing
}

install_syncthing() {
    echo "Installing Syncthing..."
    ensure_tools
    case "$DISTRO_FAMILY" in
        debian)
            # Add the Syncthing PGP key
            sudo mkdir -p /etc/apt/keyrings
            sudo curl -L -o /etc/apt/keyrings/syncthing-archive-keyring.gpg https://syncthing.net/release-key.gpg

            # Add the Syncthing repository
            echo "deb [signed-by=/etc/apt/keyrings/syncthing-archive-keyring.gpg] https://apt.syncthing.net/ syncthing stable" | \
                sudo tee /etc/apt/sources.list.d/syncthing.list > /dev/null

            # Update and install
            sudo apt update
            sudo apt install -y syncthing
            ;;
        fedora|rhel)
            # Install from official Fedora repos (Syncthing is included by default)
            sudo "$PKG_MGR" install -y syncthing
            ;;
        arch)
            # Syncthing is available in the community repository
            sudo pacman -S --noconfirm syncthing
            ;;
        suse)
            # Install from official repository
            sudo zypper install -y syncthing
            ;;
    esac

    # Enable and start the user service (all distros)
    systemctl --user enable syncthing.service
    systemctl --user start syncthing.service

    echo ""
    echo "Syncthing installed successfully!"
    echo "Service has been enabled and started."
    echo "Access the web GUI at: http://127.0.0.1:8384"
}

uninstall_syncthing() {
    echo "Uninstalling Syncthing..."
    
    # Stop and disable the service if running
    systemctl --user stop syncthing.service 2>/dev/null || true
    systemctl --user disable syncthing.service 2>/dev/null || true
    
    case "$DISTRO_FAMILY" in
        debian)
            sudo apt remove -y syncthing
            sudo rm -f /etc/apt/sources.list.d/syncthing.list
            sudo rm -f /etc/apt/keyrings/syncthing-archive-keyring.gpg
            ;;
        fedora|rhel)
            sudo "$PKG_MGR" remove -y syncthing
            sudo rm -f /etc/yum.repos.d/syncthing.repo
            ;;
        arch)
            sudo pacman -Rs --noconfirm syncthing
            ;;
        suse)
            sudo zypper remove -y syncthing
            ;;
    esac
    
    echo "Syncthing has been uninstalled."
    echo "Note: Your Syncthing configuration and data (~/.config/syncthing) have been preserved."
    echo "To remove them manually, run: rm -rf ~/.config/syncthing"
}

update_syncthing() {
    echo "Updating Syncthing..."
    case "$DISTRO_FAMILY" in
        debian)
            sudo apt update
            sudo apt upgrade -y syncthing
            ;;
        fedora|rhel)
            sudo "$PKG_MGR" upgrade -y syncthing
            ;;
        arch)
            sudo pacman -S --noconfirm syncthing
            ;;
        suse)
            sudo zypper update -y syncthing
            ;;
    esac
}
get_version_syncthing() {
    syncthing --version 2>/dev/null | awk '{print $2}' | sed 's/^v//' || echo ""
}

# --- OpenSSH Server ---
check_openssh_server() {
    pkg_check_installed openssh-server || \
        systemctl is-active --quiet ssh 2>/dev/null || \
        systemctl is-active --quiet sshd 2>/dev/null
}

install_openssh_server() {
    echo "Installing OpenSSH Server..."
    case "$DISTRO_FAMILY" in
        debian)
            sudo apt install openssh-server -y
            sudo systemctl enable ssh
            sudo systemctl start ssh
            ;;
        fedora|rhel)
            sudo "$PKG_MGR" install -y openssh-server
            sudo systemctl enable sshd
            sudo systemctl start sshd
            ;;
        arch)
            sudo pacman -S --noconfirm openssh
            sudo systemctl enable sshd
            sudo systemctl start sshd
            ;;
        suse)
            sudo zypper install -y openssh
            sudo systemctl enable sshd
            sudo systemctl start sshd
            ;;
    esac
    echo "OpenSSH Server installed and started."
}

uninstall_openssh_server() {
    echo "Uninstalling OpenSSH Server..."
    sudo systemctl stop ssh 2>/dev/null || sudo systemctl stop sshd 2>/dev/null || true
    sudo systemctl disable ssh 2>/dev/null || sudo systemctl disable sshd 2>/dev/null || true
    case "$DISTRO_FAMILY" in
        debian)
            sudo apt remove -y openssh-server
            sudo apt autoremove -y
            ;;
        fedora|rhel)
            sudo "$PKG_MGR" remove -y openssh-server
            ;;
        arch)
            sudo pacman -Rs --noconfirm openssh
            ;;
        suse)
            sudo zypper remove -y openssh
            ;;
    esac
    echo "OpenSSH Server has been uninstalled."
}

update_openssh_server() {
    echo "Updating OpenSSH Server..."
    case "$DISTRO_FAMILY" in
        debian)
            sudo apt update
            sudo apt upgrade -y openssh-server
            ;;
        fedora|rhel)
            sudo "$PKG_MGR" upgrade -y openssh-server
            ;;
        arch)
            sudo pacman -S --noconfirm openssh
            ;;
        suse)
            sudo zypper update -y openssh
            ;;
    esac
}
get_version_openssh_server() {
    ssh -V 2>&1 | grep -oP 'OpenSSH_\K[^\s,]+' || echo ""
}

# --- PIA VPN ---

check_pia_vpn() {
    command -v piactl &>/dev/null || \
        [[ -x /opt/piavpn/bin/piactl ]] || \
        pkg_check_installed privateinternetaccess
}

install_pia_vpn() {
    echo "Installing PIA VPN..."
    ensure_tools
    case "$DISTRO_FAMILY" in
        debian)
            _pia_install_via_run || return 1
            ;;
        fedora|rhel)
            _pia_install_via_run || return 1
            ;;
        arch)
            # Install from AUR
            if has_aur_helper; then
                aur_install privateinternetaccess-bin
            else
                echo "Installing from AUR requires an AUR helper (yay/paru). Please install one first."
                return 1
            fi
            ;;
        suse)
            # For openSUSE, try Flatpak as primary method
            if has_flatpak; then
                flatpak install -y flathub com.privateinternetaccess.PIA
            else
                echo "PIA is not available in default openSUSE repositories."
                echo "Please install Flatpak and use: flatpak install flathub com.privateinternetaccess.PIA"
                return 1
            fi
            ;;
    esac
    echo "PIA VPN installed successfully."
}

# Download and install PIA VPN from the official website.
_pia_install_via_run() {
    local pia_installer pia_url
    pia_installer=$(mktemp /tmp/pia-XXXXXX.run)
    CLEANUP_FILES+=("$pia_installer")
    # Scrape the current x64 .run download URL from the PIA website
    pia_url=$(curl -fsSL "https://www.privateinternetaccess.com/download/linux-vpn" | \
        grep -oE 'https://[^"]+pia-linux-[0-9][^"]*\.run' | head -1)
    if [[ -z "$pia_url" ]]; then
        echo "Error: Failed to get PIA VPN download URL from website."
        rm -f "$pia_installer"
        return 1
    fi
    if ! wget -qO "$pia_installer" "$pia_url"; then
        echo "Error: Failed to download PIA VPN installer. Check network connectivity."
        rm -f "$pia_installer"
        return 1
    fi
    chmod +x "$pia_installer"
    if ! "$pia_installer" --accept --quiet; then
        echo "Error: Failed to install PIA VPN."
        rm -f "$pia_installer"
        return 1
    fi
    rm -f "$pia_installer"
}

uninstall_pia_vpn() {
    echo "Uninstalling PIA VPN..."
    case "$DISTRO_FAMILY" in
        debian)
            sudo apt remove -y privateinternetaccess
            sudo rm -f /etc/apt/sources.list.d/pia.list
            sudo rm -f /usr/share/keyrings/pia-archive-keyring.gpg
            ;;
        fedora|rhel)
            sudo "$PKG_MGR" remove -y privateinternetaccess
            ;;
        arch)
            sudo pacman -Rs --noconfirm privateinternetaccess-bin 2>/dev/null || \
            sudo pacman -Rs --noconfirm privateinternetaccess 2>/dev/null || true
            ;;
        suse)
            flatpak uninstall -y com.privateinternetaccess.PIA 2>/dev/null || true
            ;;
    esac
    echo "PIA VPN has been uninstalled."
}

update_pia_vpn() {
    echo "Updating PIA VPN..."
    case "$DISTRO_FAMILY" in
        debian|fedora|rhel)
            _pia_install_via_run || return 1
            ;;
        arch)
            sudo pacman -S --noconfirm privateinternetaccess-bin 2>/dev/null || \
            sudo pacman -S --noconfirm privateinternetaccess 2>/dev/null || true
            ;;
        suse)
            flatpak update -y com.privateinternetaccess.PIA 2>/dev/null || true
            ;;
    esac
}

get_version_pia_vpn() {
    piactl --version 2>/dev/null || echo ""
}

# --- QBittorrent ---
check_qbittorrent() {
    command -v qbittorrent &>/dev/null || pkg_check_installed qbittorrent
}

install_qbittorrent() {
    echo "Installing QBittorrent..."
    ensure_tools
    case "$DISTRO_FAMILY" in
        debian)
            sudo apt update
            sudo apt install -y qbittorrent
            ;;
        fedora|rhel)
            sudo "$PKG_MGR" install -y qbittorrent
            ;;
        arch)
            sudo pacman -S --noconfirm qbittorrent
            ;;
        suse)
            if has_flatpak; then
                flatpak install -y flathub org.qbittorrent.qBittorrent
            else
                sudo zypper install -y qbittorrent
            fi
            ;;
    esac
    echo "QBittorrent installed successfully."
}

uninstall_qbittorrent() {
    echo "Uninstalling QBittorrent..."
    case "$DISTRO_FAMILY" in
        debian)
            sudo apt remove -y qbittorrent
            ;;
        fedora|rhel)
            sudo "$PKG_MGR" remove -y qbittorrent
            ;;
        arch)
            sudo pacman -Rs --noconfirm qbittorrent 2>/dev/null || true
            ;;
        suse)
            flatpak uninstall -y org.qbittorrent.qBittorrent 2>/dev/null || \
            sudo zypper remove -y qbittorrent 2>/dev/null || true
            ;;
    esac
    echo "QBittorrent has been uninstalled."
}

update_qbittorrent() {
    echo "Updating QBittorrent..."
    case "$DISTRO_FAMILY" in
        debian)
            sudo apt update
            sudo apt upgrade -y qbittorrent
            ;;
        fedora|rhel)
            sudo "$PKG_MGR" upgrade -y qbittorrent
            ;;
        arch)
            sudo pacman -S --noconfirm qbittorrent
            ;;
        suse)
            flatpak update -y org.qbittorrent.qBittorrent 2>/dev/null || \
            sudo zypper update -y qbittorrent 2>/dev/null || true
            ;;
    esac
}

get_version_qbittorrent() {
    pkg_get_version qbittorrent | sed 's/^[0-9]*://; s/-.*//' || echo ""
}

# --- Docker (utility version) ---
setup_install_docker() {
    info "Installing Docker..."
    ensure_tools

    case "$PKG_MGR" in
        apt)
            run_as_root "apt-get update"
            run_as_root "apt-get install -y apt-transport-https ca-certificates curl gnupg"

            if [[ "$DISTRO_ID" == "ubuntu" || "$DISTRO_ID" == "linuxmint" || "$DISTRO_ID" == "pop" || "$DISTRO_ID" == "neon" ]]; then
                run_as_root "apt-get install -y software-properties-common"
            fi

            local docker_dist="$DISTRO_ID"
            local docker_codename="${DISTRO_VERSION_CODENAME:-stable}"
            if [[ "$DISTRO_ID" == "linuxmint" || "$DISTRO_ID" == "pop" || "$DISTRO_ID" == "neon" ]]; then
                docker_dist="ubuntu"
                if [[ "$DISTRO_ID" == "neon" && -z "$docker_codename" ]] || [[ "$DISTRO_ID" == "neon" ]]; then
                    if [[ -f /etc/upstream-release/lsb-release ]]; then
                        docker_codename=$(grep -oP '(?<=DISTRIB_CODENAME=).+' /etc/upstream-release/lsb-release)
                    fi
                    docker_codename="${docker_codename:-noble}"
                fi
            fi

            run_as_root "curl -fsSL https://download.docker.com/linux/${docker_dist}/gpg | gpg --yes --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg"
            run_as_root "chmod 644 /usr/share/keyrings/docker-archive-keyring.gpg"
            echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/${docker_dist} ${docker_codename} stable" | \
                sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
            run_as_root "apt-get update"
            run_as_root "apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin"
            ;;

        dnf|yum)
            run_as_root "$PKG_MGR install -y dnf-plugins-core 2>/dev/null || $PKG_MGR install -y yum-utils"

            local docker_repo
            [[ "$DISTRO_ID" == "fedora" ]] && docker_repo="https://download.docker.com/linux/fedora/docker-ce.repo" || docker_repo="https://download.docker.com/linux/centos/docker-ce.repo"

            run_as_root "curl -fsSLo /etc/yum.repos.d/docker-ce.repo ${docker_repo}"
            run_as_root "$PKG_MGR install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin"
            run_as_root "systemctl start docker"
            run_as_root "systemctl enable docker"
            ;;

        zypper)
            run_as_root "zypper install -y docker docker-compose"
            run_as_root "systemctl start docker"
            run_as_root "systemctl enable docker"
            ;;

        pacman)
            run_as_root "pacman -S --noconfirm docker docker-compose docker-buildx"
            run_as_root "systemctl enable --now containerd.service"
            run_as_root "systemctl enable --now docker.service"
            ;;

        *)
            error "Docker installation not fully supported for ${DISTRO_ID}"
            return 1
            ;;
    esac

    run_as_root "groupadd docker 2>/dev/null || true"
    run_as_root "usermod -aG docker ${USER}"

    info "Docker installed successfully. You may need to log out and back in for group membership to take effect."

    sudo docker version &>/dev/null && info "Docker verification complete."

    return 0
}

check_docker() {
    command -v docker &>/dev/null && docker --version &>/dev/null
}
uninstall_docker() {
    echo "Uninstalling Docker..."
    sudo systemctl stop docker 2>/dev/null || true
    sudo systemctl disable docker 2>/dev/null || true
    case "$DISTRO_FAMILY" in
        debian)
            sudo apt remove -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
            sudo rm -f /etc/apt/sources.list.d/docker.list
            sudo rm -f /usr/share/keyrings/docker-archive-keyring.gpg
            sudo rm -f /etc/apt/keyrings/docker.gpg
            ;;
        fedora|rhel)
            sudo "$PKG_MGR" remove -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
            ;;
        arch)
            sudo pacman -Rs --noconfirm docker docker-compose docker-buildx 2>/dev/null || true
            ;;
        suse)
            sudo zypper remove -y docker docker-compose docker-buildx
            ;;
    esac
}
update_docker() {
    echo "Updating Docker..."
    case "$DISTRO_FAMILY" in
        debian)
            sudo apt update
            sudo apt upgrade -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
            ;;
        fedora|rhel)
            sudo "$PKG_MGR" upgrade -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
            ;;
        arch)
            sudo pacman -S --noconfirm docker docker-compose docker-buildx
            ;;
        suse)
            sudo zypper update -y docker docker-compose docker-buildx
            ;;
    esac
}
get_version_docker() {
    docker --version 2>/dev/null | grep -oP 'Docker version \K[0-9]+\.[0-9]+\.[0-9]+' || echo ""
}


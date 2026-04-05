#!/bin/bash
# Enable Num Lock at boot — configures the system to activate Num Lock
# automatically on all virtual consoles and the display manager login screen.
#
# Strategy (applied in order of detection):
#   1. SDDM   — /etc/sddm.conf.d/numlock.conf  [General] Numlock=on
#   2. GDM    — /etc/gdm3/PostLogin/ or /etc/gdm/PostLogin/ script using numlockx
#   3. LightDM — /etc/lightdm/lightdm.conf.d/numlock.conf greeter-setup-script
#   4. TTY    — systemd service using setleds on /dev/tty{1..6}

readonly _NUMLOCK_SYSTEMD_UNIT="numlock.service"
readonly _NUMLOCK_SYSTEMD_PATH="/etc/systemd/system/${_NUMLOCK_SYSTEMD_UNIT}"
readonly _NUMLOCK_SDDM_CONF="/etc/sddm.conf.d/numlock.conf"
readonly _NUMLOCK_LIGHTDM_CONF="/etc/lightdm/lightdm.conf.d/50-numlock.conf"

# --- Detect active display manager ---
_detect_display_manager() {
    local dm=""
    # systemctl-based detection (most reliable on systemd systems)
    if command -v systemctl &>/dev/null; then
        dm=$(basename "$(readlink -f /etc/systemd/system/display-manager.service 2>/dev/null)" .service 2>/dev/null)
    fi
    # Fallback: check running processes
    if [[ -z "$dm" ]]; then
        if pgrep -x sddm &>/dev/null; then
            dm="sddm"
        elif pgrep -x gdm &>/dev/null || pgrep -x gdm3 &>/dev/null; then
            dm="gdm"
        elif pgrep -x lightdm &>/dev/null; then
            dm="lightdm"
        fi
    fi
    echo "$dm"
}

# --- GDM PostLogin path (varies by distro) ---
_gdm_postlogin_dir() {
    if [[ -d /etc/gdm3/PostLogin ]]; then
        echo "/etc/gdm3/PostLogin"
    elif [[ -d /etc/gdm/PostLogin ]]; then
        echo "/etc/gdm/PostLogin"
    else
        echo ""
    fi
}

# --- Check ---
check_numlock_boot() {
    # TTY systemd service
    if systemctl is-enabled "${_NUMLOCK_SYSTEMD_UNIT}" &>/dev/null; then
        return 0
    fi
    # SDDM config
    if [[ -f "$_NUMLOCK_SDDM_CONF" ]]; then
        return 0
    fi
    # LightDM config
    if [[ -f "$_NUMLOCK_LIGHTDM_CONF" ]]; then
        return 0
    fi
    # GDM PostLogin script
    local gdm_dir
    gdm_dir=$(_gdm_postlogin_dir)
    if [[ -n "$gdm_dir" && -f "${gdm_dir}/numlock" ]]; then
        return 0
    fi
    return 1
}

# --- Install ---
install_numlock_boot() {
    info "Enabling Num Lock at boot..."

    local dm
    dm=$(_detect_display_manager)

    # 1. Display manager configuration
    case "$dm" in
        sddm)
            info "Configuring SDDM to enable Num Lock on login screen..."
            run_as_root mkdir -p /etc/sddm.conf.d
            run_as_root tee "$_NUMLOCK_SDDM_CONF" >/dev/null <<'EOF'
[General]
Numlock=on
EOF
            ;;
        gdm|gdm3)
            info "Configuring GDM to enable Num Lock on login screen..."
            # GDM uses a PostLogin script with numlockx
            _install_numlockx
            local gdm_dir
            gdm_dir=$(_gdm_postlogin_dir)
            if [[ -z "$gdm_dir" ]]; then
                # Create the directory (gdm3 is the Debian/Ubuntu path)
                gdm_dir="/etc/gdm3/PostLogin"
                run_as_root mkdir -p "$gdm_dir"
            fi
            run_as_root tee "${gdm_dir}/numlock" >/dev/null <<'SCRIPT'
#!/bin/sh
/usr/bin/numlockx on
SCRIPT
            run_as_root chmod 755 "${gdm_dir}/numlock"
            ;;
        lightdm)
            info "Configuring LightDM to enable Num Lock on login screen..."
            _install_numlockx
            run_as_root mkdir -p /etc/lightdm/lightdm.conf.d
            run_as_root tee "$_NUMLOCK_LIGHTDM_CONF" >/dev/null <<'EOF'
[Seat:*]
greeter-setup-script=/usr/bin/numlockx on
EOF
            ;;
        *)
            info "No known display manager detected; skipping DM-level configuration."
            ;;
    esac

    # 2. TTY consoles — systemd service with setleds (works regardless of DM)
    if command -v systemctl &>/dev/null; then
        info "Creating systemd service to enable Num Lock on TTY consoles..."
        run_as_root tee "$_NUMLOCK_SYSTEMD_PATH" >/dev/null <<'UNIT'
[Unit]
Description=Enable NumLock on TTY consoles at boot
DefaultDependencies=no
After=systemd-vconsole-setup.service

[Service]
Type=oneshot
ExecStart=/bin/bash -c 'for tty in /dev/tty{1..6}; do [ -e "$tty" ] && /usr/bin/setleds -D +num < "$tty" 2>/dev/null; done'

[Install]
WantedBy=multi-user.target
UNIT
        run_as_root systemctl daemon-reload
        run_as_root systemctl enable "${_NUMLOCK_SYSTEMD_UNIT}"
    fi

    info "Num Lock at boot has been enabled."
    return 0
}

# --- Helper: install numlockx if not present ---
_install_numlockx() {
    if command -v numlockx &>/dev/null; then
        return 0
    fi
    info "Installing numlockx..."
    case "$DISTRO_FAMILY" in
        debian)  run_as_root apt-get update && run_as_root apt-get install -y numlockx ;;
        fedora)  run_as_root "$PKG_MGR" install -y numlockx ;;
        rhel)    run_as_root "$PKG_MGR" install -y numlockx ;;
        arch)    run_as_root pacman -S --noconfirm numlockx ;;
        suse)    run_as_root zypper install -y numlockx ;;
        *)       warn "Cannot auto-install numlockx on ${DISTRO_ID}. Install it manually." ;;
    esac
}

# --- Uninstall ---
uninstall_numlock_boot() {
    info "Disabling Num Lock at boot..."

    # Remove systemd service
    if systemctl is-enabled "${_NUMLOCK_SYSTEMD_UNIT}" &>/dev/null; then
        run_as_root systemctl disable "${_NUMLOCK_SYSTEMD_UNIT}"
    fi
    if [[ -f "$_NUMLOCK_SYSTEMD_PATH" ]]; then
        run_as_root rm -f "$_NUMLOCK_SYSTEMD_PATH"
        run_as_root systemctl daemon-reload
    fi

    # Remove SDDM config
    if [[ -f "$_NUMLOCK_SDDM_CONF" ]]; then
        run_as_root rm -f "$_NUMLOCK_SDDM_CONF"
    fi

    # Remove LightDM config
    if [[ -f "$_NUMLOCK_LIGHTDM_CONF" ]]; then
        run_as_root rm -f "$_NUMLOCK_LIGHTDM_CONF"
    fi

    # Remove GDM PostLogin script
    local gdm_dir
    gdm_dir=$(_gdm_postlogin_dir)
    if [[ -n "$gdm_dir" && -f "${gdm_dir}/numlock" ]]; then
        run_as_root rm -f "${gdm_dir}/numlock"
    fi

    info "Num Lock at boot has been disabled."
    return 0
}

# --- Update (re-apply configuration) ---
update_numlock_boot() {
    install_numlock_boot
}

# --- Version (returns "Enabled" instead of a version number) ---
get_version_numlock_boot() {
    echo "Enabled"
}

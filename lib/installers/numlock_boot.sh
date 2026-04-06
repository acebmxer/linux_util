#!/bin/bash
# Enable Num Lock at boot — configures the system to activate Num Lock
# automatically on virtual consoles, the DM login screen, and graphical sessions.
#
# Strategy (layers, all applied):
#   1. KDE system config    — /etc/xdg/kcminputrc  NumLock=0 (Wayland + X11, read by KWin)
#   2. /etc/xprofile        — numlockx on at X11 session start (non-KDE DEs)
#   3. DM-specific config   — SDDM / GDM / LightDM greeter config
#   4. vconsole.conf        — NUMLOCK=yes for TTY consoles (systemd >= 253)

readonly _NUMLOCK_SYSTEMD_UNIT="numlock.service"
readonly _NUMLOCK_SYSTEMD_PATH="/etc/systemd/system/${_NUMLOCK_SYSTEMD_UNIT}"
readonly _NUMLOCK_SDDM_CONF="/etc/sddm.conf.d/numlock.conf"
readonly _NUMLOCK_LIGHTDM_CONF="/etc/lightdm/lightdm.conf.d/50-numlock.conf"
readonly _NUMLOCK_XPROFILE="/etc/xprofile"
readonly _NUMLOCK_XPROFILE_MARKER="linux_util numlock"
# KDE system-level config read by KWin on both X11 and Wayland startup.
# /etc/xdg/kdedefaults/ is the lowest-priority factory fallback and is NOT
# read by KWin — the system config path (/etc/xdg/) is what KWin actually uses.
readonly _NUMLOCK_KDE_CONF="/etc/xdg/kcminputrc"
readonly _NUMLOCK_KDE_DEFAULTS_STALE="/etc/xdg/kdedefaults/kcminputrc"

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
    # KDE system config (covers both X11 and Wayland KDE sessions via KWin)
    if [[ -f "$_NUMLOCK_KDE_CONF" ]] && grep -q '^NumLock=0' "$_NUMLOCK_KDE_CONF"; then
        return 0
    fi
    # /etc/xprofile X11 session hook
    if [[ -f "$_NUMLOCK_XPROFILE" ]] && grep -q "# BEGIN ${_NUMLOCK_XPROFILE_MARKER}" "$_NUMLOCK_XPROFILE"; then
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

# --- Helper: add/replace numlockx call in /etc/xprofile ---
# Uses begin/end markers so we can cleanly remove it on uninstall.
_configure_xprofile() {
    local begin_marker="# BEGIN ${_NUMLOCK_XPROFILE_MARKER}"
    local end_marker="# END ${_NUMLOCK_XPROFILE_MARKER}"

    # Remove any previous marker block first
    if [[ -f "$_NUMLOCK_XPROFILE" ]] && grep -q "$begin_marker" "$_NUMLOCK_XPROFILE"; then
        run_as_root sed -i "/^${begin_marker}$/,/^${end_marker}$/d" "$_NUMLOCK_XPROFILE"
    fi

    # Append the block
    printf '\n%s\n%s\n%s\n' \
        "$begin_marker" \
        'command -v numlockx >/dev/null 2>&1 && numlockx on' \
        "$end_marker" \
        | run_as_root tee -a "$_NUMLOCK_XPROFILE" >/dev/null
}

# --- Install ---
install_numlock_boot() {
    info "Enabling Num Lock at boot..."

    # numlockx is needed for the X11 session hook on all DMs
    _install_numlockx

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

    # 2. X11 session hook — runs numlockx when the user's graphical session starts.
    # /etc/xprofile is sourced by SDDM/LightDM Xsession scripts for X11 sessions.
    # NOTE: This has no effect on Wayland sessions; the KDE global default (below)
    # covers Wayland.
    info "Configuring /etc/xprofile to enable Num Lock on X11 session start..."
    _configure_xprofile

    # 3. KDE system config — KWin reads this at Wayland compositor startup and the
    # KDE keyboard KCM reads it for X11 sessions.  Value 0 = Turn On.
    # NOTE: /etc/xdg/kcminputrc is the system-level KConfig file; it is in KWin's
    # config search path.  /etc/xdg/kdedefaults/ is NOT — it is the lowest-priority
    # factory fallback and is never read by KWin directly.
    info "Configuring KDE system config to enable Num Lock on session start..."
    run_as_root mkdir -p "$(dirname "$_NUMLOCK_KDE_CONF")"
    if [[ -f "$_NUMLOCK_KDE_CONF" ]] && grep -q '^NumLock=' "$_NUMLOCK_KDE_CONF"; then
        run_as_root sed -i 's/^NumLock=.*/NumLock=0/' "$_NUMLOCK_KDE_CONF"
    elif [[ -f "$_NUMLOCK_KDE_CONF" ]] && grep -q '^\[Keyboard\]' "$_NUMLOCK_KDE_CONF"; then
        run_as_root sed -i '/^\[Keyboard\]/a NumLock=0' "$_NUMLOCK_KDE_CONF"
    else
        printf '\n[Keyboard]\nNumLock=0\n' | run_as_root tee -a "$_NUMLOCK_KDE_CONF" >/dev/null
    fi

    # Clean up stale kdedefaults file written by a previous version of this script.
    if [[ -f "$_NUMLOCK_KDE_DEFAULTS_STALE" ]]; then
        run_as_root sed -i '/^NumLock=/d' "$_NUMLOCK_KDE_DEFAULTS_STALE"
    fi

    # 4. TTY consoles via /etc/vconsole.conf (systemd >= 253).
    # systemd-vconsole-setup reads this before the display manager starts.
    # Leading newline prevents corruption if the existing file lacks a trailing newline.
    local vconsole_conf="/etc/vconsole.conf"
    if [[ -f "$vconsole_conf" ]] && grep -q '^NUMLOCK=' "$vconsole_conf"; then
        run_as_root sed -i 's/^NUMLOCK=.*/NUMLOCK=yes/' "$vconsole_conf"
    else
        printf '\nNUMLOCK=yes\n' | run_as_root tee -a "$vconsole_conf" >/dev/null
    fi

    # Clean up any old setleds service written by a previous version of this script.
    # setleds only sets the keyboard LED without changing the modifier key state,
    # which caused the LED to appear on while numbers still did not work.
    if [[ -f "$_NUMLOCK_SYSTEMD_PATH" ]]; then
        run_as_root systemctl stop    "${_NUMLOCK_SYSTEMD_UNIT}" 2>/dev/null || true
        run_as_root systemctl disable "${_NUMLOCK_SYSTEMD_UNIT}" 2>/dev/null || true
        run_as_root rm -f "$_NUMLOCK_SYSTEMD_PATH"
        run_as_root rm -f "/etc/systemd/system/multi-user.target.wants/${_NUMLOCK_SYSTEMD_UNIT}"
        run_as_root systemctl daemon-reload 2>/dev/null || true
    fi

    info "Num Lock at boot has been enabled."
    return 0
}

# --- Helper: install numlockx if not present ---
# Always called during install to ensure numlockx is available for xprofile hook.
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

    # Remove systemd service — unconditional; ignore errors so partial installs
    # (e.g. service file exists but was never enabled) still clean up fully.
    run_as_root systemctl stop   "${_NUMLOCK_SYSTEMD_UNIT}" 2>/dev/null || true
    run_as_root systemctl disable "${_NUMLOCK_SYSTEMD_UNIT}" 2>/dev/null || true
    run_as_root rm -f "$_NUMLOCK_SYSTEMD_PATH"
    run_as_root rm -f "/etc/systemd/system/multi-user.target.wants/${_NUMLOCK_SYSTEMD_UNIT}"
    run_as_root systemctl daemon-reload 2>/dev/null || true

    # Remove NUMLOCK entry from /etc/vconsole.conf
    if [[ -f /etc/vconsole.conf ]]; then
        run_as_root sed -i '/^NUMLOCK=/d' /etc/vconsole.conf
    fi

    # Remove NumLock from KDE system config
    if [[ -f "$_NUMLOCK_KDE_CONF" ]]; then
        run_as_root sed -i '/^NumLock=/d' "$_NUMLOCK_KDE_CONF"
    fi
    # Remove any stale kdedefaults entry from previous script versions
    if [[ -f "$_NUMLOCK_KDE_DEFAULTS_STALE" ]]; then
        run_as_root sed -i '/^NumLock=/d' "$_NUMLOCK_KDE_DEFAULTS_STALE"
    fi

    # Remove /etc/xprofile marker block
    if [[ -f "$_NUMLOCK_XPROFILE" ]] && grep -q "# BEGIN ${_NUMLOCK_XPROFILE_MARKER}" "$_NUMLOCK_XPROFILE"; then
        run_as_root sed -i "/^# BEGIN ${_NUMLOCK_XPROFILE_MARKER}$/,/^# END ${_NUMLOCK_XPROFILE_MARKER}$/d" "$_NUMLOCK_XPROFILE"
    fi

    # Remove SDDM config
    run_as_root rm -f "$_NUMLOCK_SDDM_CONF"

    # Remove LightDM config
    run_as_root rm -f "$_NUMLOCK_LIGHTDM_CONF"

    # Remove GDM PostLogin script
    local gdm_dir
    gdm_dir=$(_gdm_postlogin_dir)
    [[ -n "$gdm_dir" ]] && run_as_root rm -f "${gdm_dir}/numlock"

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

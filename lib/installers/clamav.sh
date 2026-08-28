#!/bin/bash
# ClamAV antivirus installer functions

# --- ClamAV ---

# ClamUI — GTK4/libadwaita front-end, MIT, distributed on Flathub. It bundles no
# scanner of its own: the Flatpak reaches the host's clamscan/freshclam through
# flatpak-spawn --host, so the engine below is a hard requirement, not an extra.
CLAMUI_FLATPAK_ID="io.github.linx_systems.ClamUI"

# Which front-end(s) install_clamav should lay down: clamui | clamtk | both.
# Set by _select_clamav_ui, which asks before anything is installed.
CLAMAV_UI_CHOICE="clamui"

check_clamav() { _check_standard clamscan clamav ""; }

# Ask which GUI to install, defaulting to ClamUI. Asked up front so the rest of
# the install runs unattended rather than stopping for input part-way through.
#
# Arch never asks: clamtk is AUR-only there, so ClamUI is the only option.
# Neither does a run with no terminal to read from (profiles install unattended),
# which takes the default instead of hanging on /dev/tty.
_select_clamav_ui() {
    CLAMAV_UI_CHOICE="clamui"

    if [[ "$DISTRO_FAMILY" == "arch" ]]; then
        info "GUI: ClamUI (ClamTk is AUR-only on Arch, so it is not offered)."
        return 0
    fi

    # Opening it is the only honest test: /dev/tty exists as a device node even
    # when the process has no controlling terminal, so -e passes and the read
    # then fails with "No such device or address" after the menu is on screen.
    if ! (exec < /dev/tty) 2>/dev/null; then
        info "No terminal to prompt on — installing the default GUI, ClamUI."
        return 0
    fi

    echo ""
    echo "Which ClamAV front-end would you like?"
    echo ""
    echo "  1) ClamUI  — GTK4/libadwaita, actively developed, installed from Flathub (default)"
    echo "  2) ClamTk  — older Perl/GTK front-end, from your distro's repositories"
    echo "  3) Both"
    echo ""

    local ui_choice=""
    while [[ "$ui_choice" != "1" && "$ui_choice" != "2" && "$ui_choice" != "3" ]]; do
        read -rp "Choose [1/2/3] (default: 1): " ui_choice < /dev/tty || ui_choice="1"
        [[ -z "$ui_choice" ]] && ui_choice="1"
    done

    case "$ui_choice" in
        1) CLAMAV_UI_CHOICE="clamui" ;;
        2) CLAMAV_UI_CHOICE="clamtk" ;;
        3) CLAMAV_UI_CHOICE="both"   ;;
    esac
}

install_clamav() {
    info "Installing ClamAV..."
    _select_clamav_ui
    ensure_tools

    # Engine only. The front-end is installed separately below, so a GUI that is
    # unavailable or declined can never take the scanner down with it — which is
    # exactly what clamtk did on Arch, where it is an AUR package.
    case "$DISTRO_FAMILY" in
        debian)
            sudo apt install -y clamav clamav-daemon
            ;;
        fedora)
            sudo "$PKG_MGR" install -y clamav clamav-update clamd
            ;;
        rhel)
            sudo "$PKG_MGR" install -y epel-release 2>/dev/null || true
            sudo "$PKG_MGR" install -y clamav clamav-update clamd
            ;;
        arch)
            sudo pacman -S --noconfirm clamav
            ;;
        suse)
            sudo zypper install -y clamav
            ;;
    esac

    # Update virus definitions
    info "Updating ClamAV virus definitions..."
    sudo systemctl stop clamav-freshclam 2>/dev/null || \
        sudo systemctl stop clamav-daemon 2>/dev/null || true
    sudo freshclam 2>/dev/null || true

    # Enable freshclam update service and the scan daemon
    sudo systemctl enable --now clamav-freshclam 2>/dev/null || true
    case "$DISTRO_FAMILY" in
        debian)
            sudo systemctl enable --now clamav-daemon 2>/dev/null || true
            ;;
        arch)
            sudo systemctl enable --now clamav-daemon.service 2>/dev/null || true
            # Allow clamd to read user home directories
            sudo usermod -aG "$(id -gn)" clamav 2>/dev/null || true
            ;;
        fedora|rhel)
            _configure_clamd_socket
            if sudo systemctl enable --now clamd@scan 2>/dev/null; then
                _verify_clamd clamd@scan
            elif sudo systemctl enable --now clamd 2>/dev/null; then
                _verify_clamd clamd
            else
                warn "Could not enable the clamd daemon. On-demand scanning with 'clamscan' still works."
            fi
            ;;
    esac

    _install_clamav_ui

    info "ClamAV installed."
    info "Run 'clamscan -r /path/to/scan' to scan a directory."
    info "Run 'sudo freshclam' to update virus definitions manually."
}

# Fedora and RHEL ship /etc/clamd.d/scan.conf with every socket line commented
# out, so clamd exits at once with "Please define server type (local and/or
# TCP)": the unit enables cleanly and then dies on every restart until systemd
# gives up. Define the local socket the packaged unit and its tmpfiles entry
# (/run/clamd.scan) already expect.
_configure_clamd_socket() {
    local conf="/etc/clamd.d/scan.conf"
    [[ -f "$conf" ]] || return 0

    # A socket the admin already defined wins — never rewrite a working config.
    grep -qE '^[[:space:]]*(LocalSocket|TCPSocket)[[:space:]]' "$conf" && return 0

    info "Defining clamd's local socket in $conf..."
    # First match only: the stock file carries the commented line twice, and one
    # definition is all clamd needs.
    sudo sed -i '0,/^#LocalSocket /s//LocalSocket /' "$conf"

    # Some rebuilds keep upstream's "Example" line, which clamd treats as a
    # refusal to run until an admin has actually read the file.
    sudo sed -i 's/^[[:space:]]*Example[[:space:]]*$/#Example/' "$conf"
}

# Report what the daemon is actually doing rather than assuming "enable --now"
# worked. A clamd that enables and then dies used to be silent: the failure went
# to /dev/null and the install claimed success.
_verify_clamd() {
    local unit="$1"
    systemctl is-active --quiet "$unit" 2>/dev/null && return 0

    warn "$unit is enabled but is not running."
    local _why
    _why=$(journalctl -u "$unit" -p err -n 1 --no-pager -o cat 2>/dev/null | tail -1)
    [[ -n "$_why" ]] && warn "  $_why"
    warn "  Check with: systemctl status $unit"
    warn "  On-demand scanning with 'clamscan' is unaffected."
}

# Lay down whichever front-end(s) _select_clamav_ui settled on.
_install_clamav_ui() {
    case "$CLAMAV_UI_CHOICE" in
        clamtk|both)
            info "Installing ClamTk..."
            if pkg_install clamtk; then
                _configure_clamtk_prefs
            else
                warn "ClamTk install failed."
                # Asking for ClamTk alone and getting nothing leaves no GUI at
                # all, so fall back to the default rather than silently skipping.
                [[ "$CLAMAV_UI_CHOICE" == "clamtk" ]] && {
                    warn "Falling back to ClamUI."
                    _install_clamui
                }
            fi
            ;;
    esac

    case "$CLAMAV_UI_CHOICE" in
        clamui|both) _install_clamui ;;
    esac
}

# Install the ClamUI front-end from Flathub. Never fatal: the engine and the
# clamscan CLI are already in place by the time this runs, so a machine without
# a usable Flatpak still ends up with a working ClamAV.
_install_clamui() {
    if flatpak_is_installed "$CLAMUI_FLATPAK_ID"; then
        info "ClamUI already installed."
        return 0
    fi

    info "Installing ClamUI (graphical front-end)..."
    if ! ensure_flatpak; then
        warn "ClamUI needs Flatpak and it could not be set up — skipping the GUI."
        warn "ClamAV itself is installed; scan with 'clamscan -r /path/to/scan'."
        return 0
    fi

    # sudo, not bare flatpak: ensure_flatpak adds flathub as a SYSTEM remote.
    if sudo flatpak install -y flathub "$CLAMUI_FLATPAK_ID"; then
        info "ClamUI installed — launch it from your app menu, or run"
        info "  flatpak run $CLAMUI_FLATPAK_ID"
    else
        warn "ClamUI install failed. ClamAV itself is installed and usable."
    fi
}

# ClamTk ships only where the distro packages it, so this is a no-op elsewhere
# (Arch, and anywhere the package install above did not take).
_configure_clamtk_prefs() {
    _have_cmd clamtk || return 0

    local prefs_dir="$HOME/.config/clamtk"
    local prefs="$prefs_dir/prefs"
    mkdir -p "$prefs_dir"

    if [[ ! -f "$prefs" ]]; then
        cat > "$prefs" <<'EOF'
Thorough=0
TruncateLog=1
Update=shared
Mounted=0
SizeLimit=0
Whitelist=
HTTPProxy=0
DupeDB=1
LastInfection=Never
Recursive=1
Heuristic=0
ScanHidden=1
GUICheck=1
EOF
    else
        sed -i 's/^Recursive=.*/Recursive=1/' "$prefs"
        sed -i 's/^ScanHidden=.*/ScanHidden=1/' "$prefs"
    fi
}

uninstall_clamav() {
    info "Uninstalling ClamAV..."
    sudo systemctl stop clamav-freshclam clamav-daemon clamd 2>/dev/null || true
    sudo systemctl disable clamav-freshclam clamav-daemon clamd 2>/dev/null || true

    if flatpak_is_installed "$CLAMUI_FLATPAK_ID"; then
        flatpak uninstall -y "$CLAMUI_FLATPAK_ID" 2>/dev/null || \
            sudo flatpak uninstall -y "$CLAMUI_FLATPAK_ID" 2>/dev/null || true
    fi

    case "$DISTRO_FAMILY" in
        debian)
            sudo apt purge --autoremove -y clamav clamav-daemon clamav-freshclam clamtk
            ;;
        fedora|rhel)
            sudo "$PKG_MGR" remove -y clamav clamav-update clamd clamtk
            ;;
        arch)
            sudo pacman -Rs --noconfirm clamav
            ;;
        suse)
            sudo zypper remove -y clamtk clamav
            ;;
    esac
}

update_clamav() {
    info "Updating ClamAV..."
    case "$DISTRO_FAMILY" in
        debian)
            sudo apt-get install -y --only-upgrade clamav clamav-daemon
            ;;
        fedora|rhel)
            sudo "$PKG_MGR" upgrade -y clamav clamav-update
            ;;
        arch)
            sudo pacman -S --noconfirm clamav
            ;;
        suse)
            sudo zypper update -y clamav
            ;;
    esac

    # Update whichever front-end is actually present. An update must not install
    # the other one behind the user's back — the choice was made at install time,
    # and an update is not the place to re-ask.
    local _have_ui=false

    if _have_cmd clamtk; then
        _have_ui=true
        info "Updating ClamTk..."
        pkg_install clamtk || warn "ClamTk update failed."
    fi

    if flatpak_is_installed "$CLAMUI_FLATPAK_ID"; then
        _have_ui=true
        info "Updating ClamUI..."
        flatpak update -y "$CLAMUI_FLATPAK_ID" 2>/dev/null || \
            sudo flatpak update -y "$CLAMUI_FLATPAK_ID" 2>/dev/null || true
    fi

    # No GUI at all — an install that predates ClamUI, or one whose front-end was
    # removed by hand. Lay down the default so the update leaves a usable desktop app.
    [[ "$_have_ui" == "false" ]] && _install_clamui

    # Stop the update service before running freshclam manually to avoid log lock conflict
    sudo systemctl stop clamav-freshclam 2>/dev/null || true
    sudo freshclam 2>/dev/null || true
    sudo systemctl start clamav-freshclam 2>/dev/null || true
}

get_version_clamav() {
    _ver_from_cmd clamscan || _ver_from_pkg clamav || echo ""
}

#!/bin/bash
# Unattended Upgrades — installs updates automatically in the background.
#
# Debian/Ubuntu: the unattended-upgrades package, set up through its debconf
# dialog. Fedora and RHEL clones (issue #95): dnf's own "automatic" package
# (dnf5-plugin-automatic on dnf5, dnf-automatic on dnf4). That package only
# downloads updates until apply_updates is "yes", so install sets it in
# /etc/dnf/automatic.conf and turns on the daily systemd timer.
#
# The ini editing reuses Parallel Downloads' helpers (_pardl_value,
# _pardl_set_awk, _pardl_install_file in parallel_downloads.sh); do not add a
# third copy.

# dnf automatic's settings file (a function so tests can point it elsewhere).
_uu_dnf_conf() { printf '%s\n' /etc/dnf/automatic.conf; }

# Fedora / RHEL family (dnf)?
_uu_dnf() { [[ "$PKG_MGR" == "dnf" || "$PKG_MGR" == "yum" ]]; }

# Is the running dnf version 5? ("dnf5 version 5.x" vs "4.x" on dnf4.) The
# output is captured first: a pipe into head/grep -q kills dnf with SIGPIPE,
# which pipefail then reports as "not dnf5" at random.
_uu_dnf5() {
    local out
    out=$(dnf --version 2>/dev/null) || true
    [[ "$out" == dnf5* ]]
}

_uu_dnf_pkg() {
    if _uu_dnf5; then printf '%s\n' dnf5-plugin-automatic; else printf '%s\n' dnf-automatic; fi
}

_uu_dnf_timer() {
    if _uu_dnf5; then printf '%s\n' dnf5-automatic.timer; else printf '%s\n' dnf-automatic.timer; fi
}

# Is the daily timer enabled? Without systemd there is no timer to check.
_uu_dnf_timer_enabled() {
    has_systemd || return 0
    systemctl is-enabled --quiet "$(_uu_dnf_timer)" 2>/dev/null
}

# Set apply_updates to yes/no in dnf automatic's settings file (backed up
# first; the file is created if missing, as on dnf5).
_uu_dnf_set_apply() {
    local value="$1" conf tmp rc
    conf=$(_uu_dnf_conf)
    info "Setting apply_updates = ${value} in ${conf}..."
    tmp="$(mktemp)" || { error "Failed to create a temporary file."; return 1; }
    if [[ -f "$conf" ]]; then
        _pardl_set_awk commands "apply_updates = ${value}" apply_updates < "$conf" > "$tmp"
    else
        _pardl_set_awk commands "apply_updates = ${value}" apply_updates < /dev/null > "$tmp"
    fi
    _pardl_install_file "$tmp" "$conf"
    rc=$?
    rm -f -- "$tmp"
    return "$rc"
}

_install_unattended_upgrades_dnf() {
    local pkg timer
    pkg=$(_uu_dnf_pkg)
    timer=$(_uu_dnf_timer)

    info "Installing ${pkg}..."
    pkg_install "$pkg" || { error "Failed to install ${pkg}."; return 1; }

    # The package downloads updates but does not install them (apply_updates =
    # no). On dnf5 the file does not exist yet: it is where overrides go, the
    # defaults stay in /usr/share/dnf5/dnf5-plugins/automatic.conf.
    _uu_dnf_set_apply yes || return 1

    if has_systemd; then
        info "Turning on the daily update timer (${timer})..."
        svc_enable_now "$timer" || { error "Failed to enable ${timer}."; return 1; }
    else
        warn "systemd is not running here, so the daily timer (${timer}) was not turned on."
    fi
    info "Updates will now install automatically once a day. Reboots stay manual."
}

_uninstall_unattended_upgrades_dnf() {
    local pkg timer
    pkg=$(_uu_dnf_pkg)
    timer=$(_uu_dnf_timer)
    if has_systemd; then
        info "Turning off the daily update timer (${timer})..."
        svc_disable_now "$timer" 2>/dev/null || true
    fi
    # The settings file can outlive the package (rpm keeps an edited one), so
    # put the setting back first: a later reinstall must not install updates
    # on its own.
    if [[ -f "$(_uu_dnf_conf)" ]]; then
        _uu_dnf_set_apply no || return 1
    fi
    info "Removing ${pkg}..."
    pkg_remove "$pkg"
}

install_unattended_upgrades() {
    if _uu_dnf; then
        _install_unattended_upgrades_dnf
        return
    fi
    info "Configuring unattended-upgrades..."
    sudo dpkg-reconfigure -plow unattended-upgrades
    info "Unattended upgrades configuration complete."
}

check_unattended_upgrades() {
    if _uu_dnf; then
        # Installed AND actually applying updates on a timer: the package alone
        # only downloads them.
        pkg_check_installed "$(_uu_dnf_pkg)" || return 1
        [[ "$(_pardl_value "$(_uu_dnf_conf)" commands apply_updates)" == "yes" ]] || return 1
        _uu_dnf_timer_enabled
        return
    fi
    dpkg -l unattended-upgrades 2>/dev/null | grep -q '^ii'
}

uninstall_unattended_upgrades() {
    if _uu_dnf; then
        _uninstall_unattended_upgrades_dnf
        return
    fi
    info "Removing unattended-upgrades..."
    pkg_remove unattended-upgrades
}

update_unattended_upgrades() {
    if _uu_dnf; then
        info "Updating $(_uu_dnf_pkg)..."
        pkg_upgrade "$(_uu_dnf_pkg)"
        return
    fi
    info "Updating unattended-upgrades..."
    sudo apt-get install -y --only-upgrade unattended-upgrades
}

get_version_unattended_upgrades() {
    if _uu_dnf; then
        # rpm prints "package X is not installed" on stdout, so only print on success.
        local v
        v=$(rpm -q --queryformat '%{VERSION}' "$(_uu_dnf_pkg)" 2>/dev/null) && printf '%s\n' "$v"
        return 0
    fi
    dpkg-query -W -f='${Version}' unattended-upgrades 2>/dev/null | grep -oP '[0-9]+\.[0-9.]+' | head -1 || echo ""
}

# Open the unattended-upgrades config file in an editor so the user can choose
# which update origins auto-install, blacklist packages, and set auto-reboot /
# notification behavior. Action-style task: registered only when the package
# (and thus this file) is installed. Uses $EDITOR, falling back to nano, and
# reconnects to the terminal so it works when launched from the menu.
configure_unattended_upgrades() {
    local conf="/etc/apt/apt.conf.d/50unattended-upgrades" editor="${EDITOR:-nano}"
    if _uu_dnf; then
        conf=$(_uu_dnf_conf)
        # Fedora Server may ship without nano; vi is always there.
        [[ -n "${EDITOR:-}" ]] || command -v nano &>/dev/null || editor=vi
        if _uu_dnf5; then
            info "On dnf5 this file only holds your changes. Every option and its default is listed in /usr/share/dnf5/dnf5-plugins/automatic.conf."
        fi
    fi
    if [[ ! -f "$conf" ]]; then
        warn "Config file not found: ${conf}"
        if _uu_dnf; then
            warn "Install Unattended Upgrades first."
        else
            warn "Install the unattended-upgrades package first."
        fi
        return 1
    fi
    info "Opening ${conf} in ${editor} (edited as root via sudo)..."
    sudo "$editor" "$conf" < /dev/tty > /dev/tty 2>&1
    info "Finished editing ${conf}."
}

#!/bin/bash
# xrdp installer functions

# --- xrdp ---
check_xrdp() {
    pkg_check_installed xrdp || \
        systemctl is-active --quiet xrdp 2>/dev/null
}

# Group whose members get the polkit exemption below. Debian keeps network
# control in netdev; the rpm, Arch and SUSE families have no netdev group and
# use wheel for the same purpose.
_xrdp_network_group() {
    local grp preferred
    case "$DISTRO_FAMILY" in
        debian) preferred="netdev" ;;
        *)      preferred="wheel" ;;
    esac
    for grp in "$preferred" netdev wheel; do
        if getent group "$grp" >/dev/null 2>&1; then
            echo "$grp"
            return 0
        fi
    done
    return 1
}

# An RDP session has no local seat, so polkit skips the allow_active and
# allow_inactive tiers of an action's .policy defaults and falls through to
# allow_any — auth_admin for org.freedesktop.NetworkManager.network-control.
# The plasma-nm applet fires that action at every login, so the user gets a
# password prompt for something that is a silent "yes" on a console login.
# This is not distro-specific: Fedora's stock NetworkManager rule does not help
# either, because it gates its wheel exemption on subject.local, which is false
# over RDP.
#
# The rule keys on subject.active — true for an xrdp session — so the exemption
# only covers the live desktop session, not detached SSH, cron or daemon
# processes owned by a member of the same group.
_xrdp_install_polkit_rule() {
    local grp
    if ! grp=$(_xrdp_network_group); then
        warn "No netdev or wheel group found — skipping the NetworkManager polkit rule."
        return 0
    fi

    info "Configuring polkit to allow network management in RDP sessions (group: ${grp})..."
    run_as_root tee /etc/polkit-1/rules.d/50-xrdp-networkmanager.rules > /dev/null << EOF
// Installed by linux_util with xrdp.
// RDP sessions have no local seat, so polkit falls through to the allow_any
// tier of the NetworkManager actions and prompts for a password. Gated on
// subject.active so only the live session qualifies — not background processes
// owned by a ${grp} member.
polkit.addRule(function(action, subject) {
    if (action.id.indexOf("org.freedesktop.NetworkManager.") === 0 &&
        subject.isInGroup("${grp}") && subject.active) {
        return polkit.Result.YES;
    }
});
EOF

    # polkit reloads rules.d on its own, but a HUP makes the rule effective
    # without waiting for the inotify watch to fire.
    run_as_root systemctl reload polkit 2>/dev/null || true

    local _rdp_user="${SUDO_USER:-${USER}}"
    [[ -z "$_rdp_user" || "$_rdp_user" == "root" ]] && return 0

    if [[ "$grp" == "netdev" ]]; then
        # netdev conveys network control only, so joining it is safe to automate.
        info "Adding ${_rdp_user} to netdev group for RDP network access..."
        run_as_root usermod -aG netdev "$_rdp_user"
    elif ! id -nG "$_rdp_user" 2>/dev/null | tr ' ' '\n' | grep -qx "$grp"; then
        # wheel conveys sudo on these families — never add anyone to it silently.
        warn "${_rdp_user} is not in the ${grp} group, so the polkit rule will not apply."
        warn "To opt in: sudo usermod -aG ${grp} ${_rdp_user}  (note: ${grp} also grants sudo)."
    fi
}

# True when pam_kwallet5.so is installed somewhere the PAM stack can load it.
_xrdp_kwallet_module_present() {
    local p
    for p in /usr/lib64/security/pam_kwallet5.so /usr/lib/security/pam_kwallet5.so \
             /usr/lib/*/security/pam_kwallet5.so /lib/*/security/pam_kwallet5.so; do
        [[ -e "$p" ]] && return 0
    done
    return 1
}

# KDE over xrdp has no display manager behind it, so nothing hands the login
# password to kwalletd and the wallet prompts at every session start. Debian
# needs no help here: libpam-kwallet5 ships a pam-auth-update profile that lands
# in common-auth/common-session, which xrdp-sesman includes. The rpm, Arch and
# SUSE families have no such mechanism, so the lines have to be added by hand.
#
# Editing a PAM stack can lock users out of RDP, so this is prompted rather than
# automatic, backed up first, and uses "optional" so a failing module never
# blocks authentication.
_xrdp_configure_kwallet_pam() {
    local pam_file="/etc/pam.d/xrdp-sesman"

    case "$DISTRO_FAMILY" in
        fedora|rhel|arch|suse) ;;
        *) return 0 ;;
    esac
    [[ -f "$pam_file" ]] || return 0
    command -v plasmashell >/dev/null 2>&1 || return 0

    if grep -q "pam_kwallet" "$pam_file"; then
        info "KDE Wallet is already wired into the xrdp PAM stack."
        return 0
    fi

    echo ""
    info "KDE detected. Over RDP there is no display manager to unlock KDE Wallet,"
    info "so kwalletd asks for the wallet password at every login."
    if ! _confirm_step "Add pam_kwallet5 to ${pam_file} so the wallet unlocks automatically?"; then
        info "Skipping the KDE Wallet PAM change."
        return 0
    fi

    if ! _xrdp_kwallet_module_present; then
        local pkg
        case "$DISTRO_FAMILY" in
            fedora|rhel) pkg="pam-kwallet" ;;
            arch)        pkg="kwallet-pam" ;;
            suse)        pkg="kwallet-pam" ;;
        esac
        info "Installing ${pkg}..."
        case "$DISTRO_FAMILY" in
            fedora|rhel) run_as_root "$PKG_MGR" install -y "$pkg" 2>/dev/null || true ;;
            arch)        run_as_root pacman -S --noconfirm "$pkg" 2>/dev/null || true ;;
            suse)        run_as_root zypper install -y "$pkg" 2>/dev/null || true ;;
        esac
        if ! _xrdp_kwallet_module_present; then
            warn "pam_kwallet5.so is not installed — leaving ${pam_file} untouched."
            return 0
        fi
    fi

    # The auth line must come after the stack's own auth include so the password
    # has already been collected; the session line goes last so kwalletd starts
    # in the fully set-up session.
    local tmp ok=true
    tmp=$(mktemp) || return 0
    awk '
        { line[NR] = $0 }
        /^[[:space:]]*auth[[:space:]]/    { last_auth = NR }
        /^[[:space:]]*session[[:space:]]/ { last_session = NR }
        END {
            if (last_auth == 0 || last_session == 0) exit 1
            for (i = 1; i <= NR; i++) {
                print line[i]
                if (i == last_auth) {
                    print "# linux_util: hand the RDP login password to kwalletd so KDE Wallet"
                    print "# unlocks at session start. Requires the wallet password to match."
                    print "auth       optional     pam_kwallet5.so"
                }
                if (i == last_session)
                    print "session    optional     pam_kwallet5.so auto_start"
            }
        }
    ' "$pam_file" > "$tmp" || ok=false

    if [[ "$ok" != "true" ]] || [[ ! -s "$tmp" ]] || ! grep -q "pam_kwallet5" "$tmp"; then
        rm -f "$tmp"
        warn "Could not parse ${pam_file} — leaving it untouched."
        return 0
    fi

    local backup="${pam_file}.bak.$(date +%Y%m%d-%H%M%S)"
    run_as_root cp -a "$pam_file" "$backup"
    run_as_root install -o root -g root -m 0644 "$tmp" "$pam_file"
    rm -f "$tmp"

    info "KDE Wallet PAM integration added. Backup: ${backup}"
    warn "This only works if the kdewallet password matches your login password."
    warn "If it still prompts, change the wallet password to match in KWalletManager."
    warn "To roll back: sudo cp -a ${backup} ${pam_file}"
}

install_xrdp() {
    info "Installing xrdp..."
    ensure_tools

    case "$DISTRO_FAMILY" in
        debian)
            run_as_root apt-get update
            run_as_root apt-get install -y xrdp

            # Kubuntu 26.04+ ships without X11 by default — install KDE X11 packages
            if [[ "$DISTRO_ID" == "kubuntu" ]] && dpkg --compare-versions "${DISTRO_VERSION_ID}" ge "26.04" 2>/dev/null; then
                info "Kubuntu ${DISTRO_VERSION_ID} detected — installing KDE X11 session packages..."
                run_as_root apt-get install -y kwin-x11 plasma-session-x11

                info "Configuring xrdp to launch KDE Plasma X11 session..."
                run_as_root sed -i '/^test -x \/etc\/X11\/Xsession/d; /^exec \/bin\/sh \/etc\/X11\/Xsession/d' /etc/xrdp/startwm.sh
                echo "exec /usr/bin/startplasma-x11" | run_as_root tee -a /etc/xrdp/startwm.sh > /dev/null

                info "Granting xrdp access to SSL certificates..."
                run_as_root adduser xrdp ssl-cert
            fi

            run_as_root systemctl enable xrdp
            run_as_root systemctl restart xrdp
            ;;
        fedora)
            # Unlike Debian, Fedora's xrdp package does not pull in xorgxrdp —
            # the Xorg backend sesman launches for each session. Without it
            # logins fail with "X server could not be started". xrdp-selinux
            # is only a weak dep, so install it explicitly too.
            run_as_root "$PKG_MGR" install -y xrdp xorgxrdp xrdp-selinux

            # Fedora KDE ships Wayland-only: /usr/share/xsessions is empty and
            # startplasma-x11 is absent, so xrdp's Xsession chain finds nothing
            # to exec and the session dies immediately after login.
            if [[ ! -x /usr/bin/startplasma-x11 ]] && command -v plasmashell >/dev/null 2>&1; then
                info "KDE detected without an X11 session — installing Plasma X11 packages..."
                run_as_root "$PKG_MGR" install -y plasma-workspace-x11 kwin-x11
            fi

            run_as_root firewall-cmd --add-port=3389/tcp --permanent 2>/dev/null || true
            run_as_root firewall-cmd --reload 2>/dev/null || true

            run_as_root systemctl enable xrdp
            run_as_root systemctl start xrdp
            ;;
        rhel)
            # xrdp is in EPEL, not the base RHEL/Alma/Rocky repos
            run_as_root "$PKG_MGR" install -y epel-release 2>/dev/null || true
            # EPEL packages xorgxrdp separately as well — see fedora branch
            run_as_root "$PKG_MGR" install -y xrdp xorgxrdp
            run_as_root systemctl enable xrdp
            run_as_root systemctl start xrdp
            ;;
        arch)
            run_as_root pacman -S --noconfirm xrdp
            run_as_root systemctl enable xrdp
            run_as_root systemctl start xrdp
            ;;
        suse)
            run_as_root zypper install -y xrdp
            run_as_root systemctl enable xrdp
            run_as_root systemctl start xrdp
            ;;
        *)
            error "xrdp installation not supported for ${DISTRO_ID}"
            return 1
            ;;
    esac

    # Session-level fixes that apply to every family: the seatless-session
    # polkit problem and, on KDE, the missing wallet unlock.
    _xrdp_install_polkit_rule
    _xrdp_configure_kwallet_pam

    info "xrdp installed and started."
    return 0
}

uninstall_xrdp() {
    info "Uninstalling xrdp..."
    run_as_root systemctl stop xrdp 2>/dev/null || true
    run_as_root systemctl disable xrdp 2>/dev/null || true

    case "$DISTRO_FAMILY" in
        debian)
            run_as_root apt purge --autoremove -y xrdp
            # Clean up Kubuntu 26.04+ KDE X11 additions if present
            if [[ "$DISTRO_ID" == "kubuntu" ]] && dpkg --compare-versions "${DISTRO_VERSION_ID}" ge "26.04" 2>/dev/null; then
                run_as_root apt purge --autoremove -y kwin-x11 plasma-session-x11
            fi
            run_as_root_sh "apt autoclean"
            ;;
        fedora|rhel)
            run_as_root "$PKG_MGR" remove -y xrdp
            ;;
        arch)
            run_as_root pacman -Rs --noconfirm xrdp 2>/dev/null || true
            ;;
        suse)
            run_as_root zypper remove -y xrdp
            ;;
    esac

    # The polkit rule is installed on every family, so remove it on every family.
    # The pam_kwallet5 lines are left alone: the package manager removes
    # /etc/pam.d/xrdp-sesman with xrdp, and a timestamped backup sits beside it.
    run_as_root rm -f /etc/polkit-1/rules.d/50-xrdp-networkmanager.rules

    info "xrdp has been uninstalled."
}

update_xrdp() {
    info "Updating xrdp..."
    case "$DISTRO_FAMILY" in
        debian)
            run_as_root apt-get update
            run_as_root apt-get install -y --only-upgrade xrdp
            ;;
        fedora|rhel)
            run_as_root "$PKG_MGR" upgrade -y xrdp
            ;;
        arch)
            run_as_root pacman -S --noconfirm xrdp
            ;;
        suse)
            run_as_root zypper update -y xrdp
            ;;
    esac
    run_as_root systemctl restart xrdp
}

get_version_xrdp() {
    xrdp --version 2>&1 | grep -oP '[0-9]+\.[0-9]+[0-9.]*' | head -1 || echo ""
}

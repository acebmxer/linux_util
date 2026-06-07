#!/bin/bash
# xrdp installer functions

# --- xrdp ---
check_xrdp() {
    pkg_check_installed xrdp || \
        systemctl is-active --quiet xrdp 2>/dev/null
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

                # RDP sessions are treated as inactive by logind, which causes
                # polkit to prompt for a password on NetworkManager actions.
                # Fix: grant netdev group members network control without prompting,
                # then add the current user to netdev.
                info "Configuring polkit to allow network management in RDP sessions..."
                run_as_root tee /etc/polkit-1/rules.d/50-xrdp-networkmanager.rules > /dev/null << 'EOF'
polkit.addRule(function(action, subject) {
    if (action.id.indexOf("org.freedesktop.NetworkManager.") === 0 &&
        subject.isInGroup("netdev")) {
        return polkit.Result.YES;
    }
});
EOF
                local _rdp_user="${SUDO_USER:-${USER}}"
                if [[ -n "$_rdp_user" && "$_rdp_user" != "root" ]]; then
                    info "Adding ${_rdp_user} to netdev group for RDP network access..."
                    run_as_root usermod -aG netdev "$_rdp_user"
                fi
            fi

            run_as_root systemctl enable xrdp
            run_as_root systemctl restart xrdp
            ;;
        fedora)
            run_as_root "$PKG_MGR" install -y xrdp
            run_as_root systemctl enable xrdp
            run_as_root systemctl start xrdp
            ;;
        rhel)
            # xrdp is in EPEL, not the base RHEL/Alma/Rocky repos
            run_as_root "$PKG_MGR" install -y epel-release 2>/dev/null || true
            run_as_root "$PKG_MGR" install -y xrdp
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
                run_as_root rm -f /etc/polkit-1/rules.d/50-xrdp-networkmanager.rules
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

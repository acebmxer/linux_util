#!/bin/bash
# Timeshift installer functions

# --- Timeshift ---

check_timeshift() {
    command -v timeshift &>/dev/null
}

install_timeshift() {
    echo "Installing Timeshift..."
    case "$DISTRO_FAMILY" in
        arch)
            # On CachyOS, snapper and cachyos-snapper-support conflict with timeshift.
            # Prompt the user to remove them before proceeding.
            if pkg_check_installed snapper || pkg_check_installed cachyos-snapper-support; then
                warn "Snapper is installed and is not compatible with TimeShift."
                warn "CachyOS ships Snapper as its default snapshot solution."
                echo ""
                while true; do
                    read -n 1 -rp "Would you like to remove Snapper to install TimeShift? [y/N] " snapper_ans
                    echo ""
                    [[ $'\e' == "$snapper_ans" ]] && { read -r -n 10 -t 0.05 _ < /dev/tty 2>/dev/null || true; continue; }
                    snapper_ans="${snapper_ans:-N}"
                    case "$snapper_ans" in
                        y|Y)
                            echo "Removing Snapper..."
                            # Stop and disable snapper timers/services before removal to prevent
                            # stale snapper command errors from btrfs-assistant or running timers.
                            sudo systemctl stop snapper-timeline.timer snapper-cleanup.timer snapper-boot.service 2>/dev/null || true
                            sudo systemctl disable snapper-timeline.timer snapper-cleanup.timer snapper-boot.service 2>/dev/null || true
                            sudo pacman -R --noconfirm snapper || true
                            sudo pacman -Rsn --noconfirm cachyos-snapper-support btrfs-assistant 2>/dev/null || true
                            echo "Snapper successfully uninstalled. Now installing TimeShift..."
                            break
                            ;;
                        n|N)
                            warn "Skipping TimeShift installation. Snapper was not removed."
                            return 2
                            ;;
                        *) echo "  Please press Y or N." ;;
                    esac
                done
            fi
            pkg_install timeshift || return 1
            ;;
        debian)
            sudo apt install timeshift -y || return 1
            ;;
        fedora)
            sudo "$PKG_MGR" install -y timeshift || return 1
            ;;
        rhel)
            # Timeshift is in EPEL, not the base RHEL/Alma/Rocky repos
            sudo "$PKG_MGR" install -y epel-release 2>/dev/null || true
            sudo "$PKG_MGR" install -y timeshift || return 1
            ;;
        suse)
            sudo zypper install -y timeshift || return 1
            ;;
        *)
            warn "Timeshift installation not implemented for ${DISTRO_NAME}."
            warn "Supported distros: Debian/Ubuntu, Fedora, RHEL/Alma/Rocky, Arch/Manjaro, openSUSE."
            warn "Install manually: https://github.com/teejee2008/timeshift"
            return 1
            ;;
    esac
    echo "Timeshift installed successfully."

    # Initialize snapshot support now that Timeshift is available,
    # so the user can configure the backup device immediately.
    timeshift_init

    # Offer to take an initial snapshot right after setup.
    # Having a restore point before any further installations is the whole
    # point of running "Run Me First", so this prompt appears automatically.
    # The snapshot is optional — pressing N skips it without any side-effects.
    # Skipped in dry-run mode since no actual installation occurred.
    if [[ "${TIMESHIFT_AVAILABLE:-false}" == "true" && "${DRY_RUN:-false}" == "false" ]]; then
        echo ""
        while true; do
            read -n 1 -rp "Create an initial Timeshift snapshot now? [Y/n] " _ts_snap_now < /dev/tty
            echo ""
            [[ $'\e' == "$_ts_snap_now" ]] && { read -r -n 10 -t 0.05 _ < /dev/tty 2>/dev/null || true; continue; }
            _ts_snap_now="${_ts_snap_now:-Y}"
            case "$_ts_snap_now" in
                y|Y)
                    setup_create_snapshot
                    # Refresh the cached snapshot timestamp shown in the left panel
                    _timeshift_cache_last_snapshot
                    break
                    ;;
                n|N)
                    echo "Skipping initial snapshot. You can create one later via 'Create Snapshot'."
                    break
                    ;;
                *) echo "  Please press Y or N." ;;
            esac
        done
    fi
}

uninstall_timeshift() {
    echo "Uninstalling Timeshift..."
    case "$DISTRO_FAMILY" in
        debian)
            sudo apt purge --autoremove -y timeshift
            sudo apt autoclean
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
    rm -rf ~/.config/timeshift
    rm -rf ~/.timeshift
}

update_timeshift() {
    echo "Updating Timeshift..."
    case "$DISTRO_FAMILY" in
        debian)
            sudo apt-get install -y --only-upgrade timeshift
            ;;
        *)
            pkg_upgrade timeshift
            ;;
    esac
}
get_version_timeshift() {
    _ver_from_cmd timeshift || _ver_from_pkg timeshift || echo ""
}

#!/bin/bash
# Snapper installer functions (Arch, openSUSE, Debian/Ubuntu, Fedora)

# --- Snapper ---

check_snapper() {
    _have_cmd snapper
}

install_snapper() {
    echo "Installing Snapper..."

    # Check for Timeshift on all distros — running both is not recommended as
    # they may snapshot overlapping data. Prompt to uninstall first.
    if command -v timeshift &>/dev/null || pkg_check_installed timeshift; then
        echo ""
        warn "Timeshift is already installed on this system."
        echo "  Running both Timeshift and Snapper is not recommended — they may"
        echo "  snapshot the same data, wasting disk space and causing confusion."
        echo "  It is strongly advised to use only one snapshot tool at a time."
        echo ""
        while true; do
            read -n 1 -rp "Uninstall Timeshift and continue installing Snapper? [y/N] " _ts_remove
            echo ""
            [[ $'\e' == "$_ts_remove" ]] && { read -r -n 10 -t 0.05 _ < /dev/tty 2>/dev/null || true; continue; }
            _ts_remove="${_ts_remove:-N}"
            case "$_ts_remove" in
                y|Y)
                    echo "Uninstalling Timeshift..."
                    uninstall_timeshift
                    echo "Timeshift removed. Continuing with Snapper installation..."
                    echo ""
                    break
                    ;;
                n|N)
                    warn "Skipping Snapper installation. Timeshift was not removed."
                    return 2
                    ;;
                *) echo "  Please press Y or N." ;;
            esac
        done
    fi

    case "$DISTRO_FAMILY" in
        arch)
            pkg_install snapper || return 1
            ;;
        suse)
            # openSUSE ships snapper-zypp-plugin for automatic pre/post snapshots
            sudo zypper install -y snapper snapper-zypp-plugin || return 1
            ;;
        debian)
            sudo apt install -y snapper || return 1
            ;;
        fedora)
            sudo "$PKG_MGR" install -y snapper || return 1
            ;;
        *)
            warn "Snapper installation not supported for ${DISTRO_NAME}."
            warn "Supported distros: Arch/Manjaro, openSUSE, Debian/Ubuntu, Fedora."
            return 1
            ;;
    esac

    # Create a default root config if one doesn't exist.
    # Track whether auto-configuration succeeded so we know whether to offer
    # an initial snapshot (a snapshot will fail without a working config).
    local _snapper_configured=false
    if ! _snapper_has_config; then
        echo "Creating Snapper root configuration..."
        if _is_btrfs_root; then
            if sudo snapper -c root create-config /; then
                _snapper_configured=true
            else
                warn "Could not create Snapper root config automatically."
                warn "Set up Snapper manually: sudo snapper -c root create-config /"
            fi
        else
            warn "Root filesystem is not btrfs — Snapper root config was not created automatically."
            warn "Set up Snapper manually for your filesystem type (e.g. LVM, ext4)."
            warn "Once configured, you can create snapshots via 'Create Snapshot (Snapper)'."
        fi
    else
        _snapper_configured=true
    fi

    echo "Snapper installed successfully."

    # Re-initialize snapshot support so Snapper becomes active immediately
    timeshift_init

    # Offer GUI frontends available for this distro that are not already installed.
    # Snapper GUI: GTK interface for Snapper (Debian/Arch only).
    # Btrfs Assistant: Qt tool for btrfs filesystem management + Snapper integration (Debian/Arch/Fedora/openSUSE).
    if [[ "${DRY_RUN:-false}" == "false" ]]; then
        local _has_snapper_gui=false
        local _has_btrfs_assistant=false
        [[ "$DISTRO_FAMILY" == "debian" || "$DISTRO_FAMILY" == "arch" ]] && _has_snapper_gui=true
        [[ "$DISTRO_FAMILY" == "debian" || "$DISTRO_FAMILY" == "arch" || "$DISTRO_FAMILY" == "fedora" || "$DISTRO_FAMILY" == "suse" ]] && _has_btrfs_assistant=true

        if [[ "$_has_snapper_gui" == "true" ]] && ! check_snapper_gui; then
            echo ""
            while true; do
                read -n 1 -rp "Would you like to also install Snapper GUI? (GTK interface for Snapper) [Y/n] " _gui_now < /dev/tty
                echo ""
                [[ $'\e' == "$_gui_now" ]] && { read -r -n 10 -t 0.05 _ < /dev/tty 2>/dev/null || true; continue; }
                _gui_now="${_gui_now:-Y}"
                case "$_gui_now" in
                    y|Y) install_snapper_gui; break ;;
                    n|N) echo "Skipping Snapper GUI. You can install it later from the menu."; break ;;
                    *) echo "  Please press Y or N." ;;
                esac
            done
        fi

        if [[ "$_has_btrfs_assistant" == "true" ]] && ! check_btrfs_assistant; then
            echo ""
            while true; do
                read -n 1 -rp "Would you like to also install Btrfs Assistant? (Qt GUI for btrfs filesystem management) [Y/n] " _btrfs_now < /dev/tty
                echo ""
                [[ $'\e' == "$_btrfs_now" ]] && { read -r -n 10 -t 0.05 _ < /dev/tty 2>/dev/null || true; continue; }
                _btrfs_now="${_btrfs_now:-Y}"
                case "$_btrfs_now" in
                    y|Y) install_btrfs_assistant; break ;;
                    n|N) echo "Skipping Btrfs Assistant. You can install it later from the menu."; break ;;
                    *) echo "  Please press Y or N." ;;
                esac
            done
        fi
    fi

    # Only offer an initial snapshot if Snapper was successfully configured.
    # Skipping this when manual setup is needed avoids a guaranteed failure.
    if [[ "$_snapper_configured" == "true" && "${DRY_RUN:-false}" == "false" ]]; then
        echo ""
        while true; do
            read -n 1 -rp "Create an initial Snapper snapshot now? [Y/n] " _snap_now < /dev/tty
            echo ""
            [[ $'\e' == "$_snap_now" ]] && { read -r -n 10 -t 0.05 _ < /dev/tty 2>/dev/null || true; continue; }
            _snap_now="${_snap_now:-Y}"
            case "$_snap_now" in
                y|Y)
                    setup_create_snapshot
                    _snapper_cache_last_snapshot
                    break
                    ;;
                n|N)
                    echo "Skipping initial snapshot. You can create one later via 'Create Snapshot (Snapper)'."
                    break
                    ;;
                *) echo "  Please press Y or N." ;;
            esac
        done
    fi
}

uninstall_snapper() {
    echo "Uninstalling Snapper..."
    case "$DISTRO_FAMILY" in
        arch)
            sudo systemctl stop snapper-timeline.timer snapper-cleanup.timer snapper-boot.service 2>/dev/null || true
            sudo systemctl disable snapper-timeline.timer snapper-cleanup.timer snapper-boot.service 2>/dev/null || true
            sudo pacman -Rs --noconfirm snapper || true
            ;;
        suse)
            sudo zypper remove -y snapper snapper-zypp-plugin || true
            ;;
        debian)
            sudo systemctl stop snapper-timeline.timer snapper-cleanup.timer 2>/dev/null || true
            sudo systemctl disable snapper-timeline.timer snapper-cleanup.timer 2>/dev/null || true
            sudo apt purge --autoremove -y snapper
            sudo apt autoclean
            ;;
        fedora)
            sudo systemctl stop snapper-timeline.timer snapper-cleanup.timer 2>/dev/null || true
            sudo systemctl disable snapper-timeline.timer snapper-cleanup.timer 2>/dev/null || true
            sudo "$PKG_MGR" remove -y snapper
            ;;
    esac
}

update_snapper() {
    echo "Updating Snapper..."
    case "$DISTRO_FAMILY" in
        arch)
            pkg_upgrade snapper
            ;;
        suse)
            sudo zypper update -y snapper snapper-zypp-plugin || true
            ;;
        debian)
            sudo apt-get install -y --only-upgrade snapper
            ;;
        fedora)
            pkg_upgrade snapper
            ;;
    esac
}

get_version_snapper() {
    _ver_from_cmd snapper || _ver_from_pkg snapper || echo ""
}

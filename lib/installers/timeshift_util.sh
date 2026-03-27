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
                read -n 1 -rp "Would you like to remove Snapper to install TimeShift? [y/N] " snapper_ans
                echo ""
                if [[ "$snapper_ans" =~ ^[Yy]$ ]]; then
                    echo "Removing Snapper..."
                    # Stop and disable snapper timers/services before removal to prevent
                    # stale snapper command errors from btrfs-assistant or running timers.
                    sudo systemctl stop snapper-timeline.timer snapper-cleanup.timer snapper-boot.service 2>/dev/null || true
                    sudo systemctl disable snapper-timeline.timer snapper-cleanup.timer snapper-boot.service 2>/dev/null || true
                    sudo pacman -R --noconfirm snapper || true
                    sudo pacman -Rsn --noconfirm cachyos-snapper-support btrfs-assistant 2>/dev/null || true
                    echo "Snapper successfully uninstalled. Now installing TimeShift..."
                else
                    warn "Skipping TimeShift installation. Snapper was not removed."
                    return 2
                fi
            fi
            pkg_install timeshift || return 1
            ;;
        debian)
            sudo apt install timeshift -y || return 1
            ;;
        fedora|rhel)
            sudo "$PKG_MGR" install -y timeshift || return 1
            ;;
        suse)
            sudo zypper install -y timeshift || return 1
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

#!/bin/bash
# Snapper installer functions (Arch and openSUSE only)

# --- Snapper ---

check_snapper() {
    command -v snapper &>/dev/null
}

install_snapper() {
    echo "Installing Snapper..."
    case "$DISTRO_FAMILY" in
        arch)
            # Timeshift conflicts with Snapper on Arch/CachyOS — prompt to remove it.
            if pkg_check_installed timeshift; then
                warn "Timeshift is installed and conflicts with Snapper on Arch-based systems."
                echo ""
                while true; do
                    read -n 1 -rp "Would you like to remove Timeshift to install Snapper? [y/N] " snapper_ans
                    echo ""
                    [[ $'\e' == "$snapper_ans" ]] && { read -r -n 10 -t 0.05 _ < /dev/tty 2>/dev/null || true; continue; }
                    snapper_ans="${snapper_ans:-N}"
                    case "$snapper_ans" in
                        y|Y)
                            echo "Removing Timeshift..."
                            sudo pacman -Rs --noconfirm timeshift || true
                            echo "Timeshift removed. Now installing Snapper..."
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
            pkg_install snapper || return 1
            ;;
        suse)
            # openSUSE ships snapper-zypp-plugin for automatic pre/post snapshots
            sudo zypper install -y snapper snapper-zypp-plugin || return 1
            ;;
        *)
            warn "Snapper is only supported on Arch-based and openSUSE systems."
            return 1
            ;;
    esac

    # Create a default root config if one doesn't exist
    if ! _snapper_has_config; then
        echo "Creating Snapper root configuration..."
        if _is_btrfs_root; then
            sudo snapper -c root create-config / || {
                warn "Could not create Snapper root config. You may need to set it up manually."
            }
        else
            warn "Root filesystem is not btrfs — Snapper root config was not created automatically."
            warn "Set up Snapper manually for your filesystem type."
        fi
    fi

    echo "Snapper installed successfully."

    # Re-initialize snapshot support so Snapper becomes active immediately
    timeshift_init
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
    esac
}

get_version_snapper() {
    _ver_from_cmd snapper || _ver_from_pkg snapper || echo ""
}

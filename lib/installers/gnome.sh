#!/bin/bash
# GNOME Desktop installer functions

# --- GNOME Desktop ---
check_gnome() {
    command -v gnome-shell &>/dev/null || \
        pkg_check_installed gnome-shell || \
        pkg_check_installed gnome || \
        pkg_check_installed gnome-desktop
}

get_version_gnome() {
    local version=""
    if command -v gnome-shell &>/dev/null; then
        version=$(gnome-shell --version 2>/dev/null | grep -oP '[0-9]+\.[0-9.]+' | head -1)
    fi
    if [[ -n "$version" ]]; then
        echo "$version"
    else
        local pkg_ver
        pkg_ver=$(pkg_get_version gnome-shell 2>/dev/null || echo "")
        echo "$pkg_ver" | sed 's/^[0-9]*://; s/-.*//'
    fi
}

install_gnome() {
    setup_install_gnome
}

uninstall_gnome() {
    echo "Uninstalling GNOME Desktop..."
    case "$DISTRO_FAMILY" in
        debian)
            sudo apt purge --autoremove -y gnome gnome-shell gnome-session gdm3
            sudo apt autoclean
            ;;
        fedora|rhel)
            sudo "$PKG_MGR" group remove -y @gnome-desktop 2>/dev/null || \
                sudo "$PKG_MGR" group remove -y 'GNOME Desktop Environment' 2>/dev/null || true
            sudo "$PKG_MGR" autoremove -y
            ;;
        arch)
            sudo pacman -Rs --noconfirm gnome gnome-extra gdm 2>/dev/null || true
            ;;
        suse)
            sudo zypper remove -y -t pattern gnome gnome_basis
            ;;
    esac
    rm -rf ~/.config/gnome* ~/.config/dconf ~/.local/share/gnome* 2>/dev/null || true
    echo "GNOME Desktop uninstalled. You may need to install another desktop environment."
}

update_gnome() {
    echo "Updating GNOME Desktop..."
    case "$DISTRO_FAMILY" in
        debian)
            sudo apt update
            sudo apt upgrade -y gnome gnome-shell
            ;;
        fedora|rhel)
            sudo "$PKG_MGR" group update -y @gnome-desktop 2>/dev/null || \
                sudo "$PKG_MGR" upgrade -y gnome-shell gnome-session gdm
            ;;
        arch)
            sudo pacman -Syu --noconfirm gnome gnome-extra
            ;;
        suse)
            sudo zypper update -y -t pattern gnome gnome_basis
            ;;
    esac
}

setup_install_gnome() {
    info "Installing GNOME Desktop..."
    ensure_tools

    case "$PKG_MGR" in
        apt)
            run_as_root apt-get update
            info "Installing GNOME Desktop Environment..."
            run_as_root apt-get install -y gnome gdm3 || {
                # Fallback: minimal install
                run_as_root apt-get install -y gnome-shell gnome-session gnome-terminal \
                    nautilus gdm3 gnome-control-center gnome-tweaks || {
                    error "Failed to install GNOME Desktop Environment"
                    return 1
                }
            }
            info "Enabling display manager..."
            run_as_root systemctl enable gdm3 2>/dev/null || \
                run_as_root systemctl enable gdm || warn "Failed to enable gdm"
            run_as_root systemctl start gdm3 2>/dev/null || \
                run_as_root systemctl start gdm || warn "Failed to start gdm"
            ;;

        dnf|yum)
            info "Installing GNOME Desktop Environment..."
            if ! run_as_root "$PKG_MGR" group install -y 'GNOME Desktop Environment' 2>/dev/null && \
               ! run_as_root "$PKG_MGR" group install -y @gnome-desktop 2>/dev/null; then
                info "Group install not available, installing GNOME packages individually..."
                run_as_root "$PKG_MGR" install -y gnome-shell gnome-session gdm \
                    gnome-terminal nautilus gnome-control-center gnome-tweaks \
                    gnome-software gnome-text-editor xdg-desktop-portal-gnome || {
                    error "Failed to install GNOME Desktop Environment packages"
                    return 1
                }
            fi
            info "Enabling display manager..."
            run_as_root systemctl enable gdm || run_as_root systemctl set-default graphical.target
            run_as_root systemctl start gdm || warn "Failed to start gdm"
            ;;

        zypper)
            info "Installing GNOME Desktop Environment..."
            run_as_root zypper install -y -t pattern gnome gnome_basis gnome_utilities \
                gnome_imaging gnome_multimedia gnome_admin || {
                error "Failed to install GNOME Desktop Environment"
                return 1
            }
            info "Enabling display manager..."
            run_as_root systemctl enable gdm || run_as_root systemctl set-default graphical.target
            run_as_root systemctl start gdm || warn "Failed to start gdm"
            ;;

        pacman)
            info "Installing GNOME Desktop Environment..."
            run_as_root pacman -S --noconfirm gnome gnome-extra gdm || {
                error "Failed to install GNOME Desktop Environment"
                return 1
            }
            info "Enabling display manager..."
            run_as_root systemctl enable gdm
            run_as_root systemctl start gdm || warn "Failed to start gdm"
            ;;

        *)
            error "GNOME installation not fully supported for ${DISTRO_ID}"
            return 1
            ;;
    esac

    info "GNOME Desktop installed successfully. Reboot to start using GNOME."
    return 0
}

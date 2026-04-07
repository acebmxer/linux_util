#!/bin/bash
# MATE Desktop installer functions

# --- MATE Desktop ---
check_mate() {
    command -v mate-session &>/dev/null || \
        pkg_check_installed mate-desktop || \
        pkg_check_installed mate-desktop-environment || \
        pkg_check_installed mate
}

get_version_mate() {
    local version=""
    if command -v mate-panel &>/dev/null; then
        version=$(mate-panel --version 2>/dev/null | grep -oP '[0-9]+\.[0-9.]+' | head -1)
    fi
    if [[ -n "$version" ]]; then
        echo "$version"
    else
        local pkg_ver
        pkg_ver=$(pkg_get_version mate-desktop 2>/dev/null || \
                  pkg_get_version mate-panel 2>/dev/null || echo "")
        echo "$pkg_ver" | sed 's/^[0-9]*://; s/-.*//'
    fi
}

install_mate() {
    setup_install_mate
}

uninstall_mate() {
    echo "Uninstalling MATE Desktop..."
    case "$DISTRO_FAMILY" in
        debian)
            sudo apt purge --autoremove -y mate-desktop-environment \
                mate-desktop-environment-core mate-desktop lightdm
            sudo apt autoclean
            ;;
        fedora|rhel)
            sudo "$PKG_MGR" group remove -y @mate-desktop 2>/dev/null || \
                sudo "$PKG_MGR" group remove -y 'MATE Desktop' 2>/dev/null || true
            sudo "$PKG_MGR" autoremove -y
            ;;
        arch)
            sudo pacman -Rs --noconfirm mate mate-extra \
                lightdm lightdm-gtk-greeter 2>/dev/null || true
            ;;
        suse)
            sudo zypper remove -y -t pattern mate || true
            ;;
    esac
    rm -rf ~/.config/mate ~/.mate 2>/dev/null || true
    echo "MATE Desktop uninstalled. You may need to install another desktop environment."
}

update_mate() {
    echo "Updating MATE Desktop..."
    case "$DISTRO_FAMILY" in
        debian)
            sudo apt update
            sudo apt upgrade -y mate-desktop-environment mate-desktop-environment-core
            ;;
        fedora|rhel)
            sudo "$PKG_MGR" group update -y @mate-desktop 2>/dev/null || \
                sudo "$PKG_MGR" upgrade -y mate-desktop mate-panel mate-session-manager
            ;;
        arch)
            sudo pacman -Syu --noconfirm mate mate-extra
            ;;
        suse)
            sudo zypper update -y -t pattern mate
            ;;
    esac
}

setup_install_mate() {
    info "Installing MATE Desktop..."
    ensure_tools

    case "$PKG_MGR" in
        apt)
            run_as_root apt-get update
            info "Installing MATE Desktop Environment..."
            run_as_root apt-get install -y mate-desktop-environment-core \
                mate-desktop-environment lightdm lightdm-gtk-greeter || {
                error "Failed to install MATE Desktop Environment"
                return 1
            }
            info "Enabling display manager..."
            run_as_root systemctl enable lightdm || warn "Failed to enable lightdm"
            run_as_root systemctl start lightdm || warn "Failed to start lightdm"
            ;;

        dnf|yum)
            info "Installing MATE Desktop Environment..."
            if ! run_as_root "$PKG_MGR" group install -y 'MATE Desktop' 2>/dev/null && \
               ! run_as_root "$PKG_MGR" group install -y @mate-desktop 2>/dev/null; then
                info "Group install not available, installing MATE packages individually..."
                run_as_root "$PKG_MGR" install -y mate-desktop mate-session-manager \
                    mate-panel mate-control-center mate-terminal caja \
                    mate-screensaver mate-media lightdm lightdm-gtk || {
                    error "Failed to install MATE Desktop Environment packages"
                    return 1
                }
            fi
            info "Enabling display manager..."
            run_as_root systemctl enable lightdm 2>/dev/null || \
                run_as_root systemctl set-default graphical.target
            run_as_root systemctl start lightdm || warn "Failed to start lightdm"
            ;;

        zypper)
            info "Installing MATE Desktop Environment..."
            run_as_root zypper install -y -t pattern mate 2>/dev/null || \
                run_as_root zypper install -y mate-desktop mate-panel \
                    mate-session-manager caja lightdm lightdm-gtk-greeter || {
                error "Failed to install MATE Desktop Environment"
                return 1
            }
            info "Enabling display manager..."
            run_as_root systemctl enable lightdm 2>/dev/null || \
                run_as_root systemctl set-default graphical.target
            run_as_root systemctl start lightdm || warn "Failed to start lightdm"
            ;;

        pacman)
            info "Installing MATE Desktop Environment..."
            run_as_root pacman -S --noconfirm mate mate-extra \
                lightdm lightdm-gtk-greeter || {
                error "Failed to install MATE Desktop Environment"
                return 1
            }
            info "Enabling display manager..."
            run_as_root systemctl enable lightdm
            run_as_root systemctl start lightdm || warn "Failed to start lightdm"
            ;;

        *)
            error "MATE installation not fully supported for ${DISTRO_ID}"
            return 1
            ;;
    esac

    info "MATE Desktop installed successfully. Reboot to start using MATE."
    return 0
}

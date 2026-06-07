#!/bin/bash
# Xfce Desktop installer functions

# --- Xfce Desktop ---
check_xfce() {
    command -v xfce4-session &>/dev/null || \
        pkg_check_installed xfce4 || \
        pkg_check_installed xfce4-session
}

get_version_xfce() {
    local version=""
    if command -v xfce4-session &>/dev/null; then
        version=$(xfce4-session --version 2>/dev/null | grep -oP '[0-9]+\.[0-9.]+' | head -1)
    fi
    if [[ -n "$version" ]]; then
        echo "$version"
    else
        local pkg_ver
        pkg_ver=$(pkg_get_version xfce4-session 2>/dev/null || pkg_get_version xfce4 2>/dev/null || echo "")
        echo "$pkg_ver" | sed 's/^[0-9]*://; s/-.*//'
    fi
}

install_xfce() {
    setup_install_xfce
}

uninstall_xfce() {
    echo "Uninstalling Xfce Desktop..."
    case "$DISTRO_FAMILY" in
        debian)
            sudo apt purge --autoremove -y xfce4 xfce4-goodies xfwm4 \
                xfdesktop4 xfce4-panel lightdm
            sudo apt autoclean
            ;;
        fedora|rhel)
            sudo "$PKG_MGR" group remove -y @xfce-desktop-environment 2>/dev/null || \
                sudo "$PKG_MGR" group remove -y 'Xfce Desktop' 2>/dev/null || true
            sudo "$PKG_MGR" autoremove -y
            ;;
        arch)
            sudo pacman -Rs --noconfirm xfce4 xfce4-goodies lightdm \
                lightdm-gtk-greeter 2>/dev/null || true
            ;;
        suse)
            sudo zypper remove -y -t pattern xfce
            ;;
    esac
    rm -rf ~/.config/xfce4* ~/.config/Thunar 2>/dev/null || true
    echo "Xfce Desktop uninstalled. You may need to install another desktop environment."
}

update_xfce() {
    echo "Updating Xfce Desktop..."
    case "$DISTRO_FAMILY" in
        debian)
            sudo apt update
            sudo apt install -y --only-upgrade xfce4 xfce4-goodies
            ;;
        fedora|rhel)
            sudo "$PKG_MGR" group update -y @xfce-desktop-environment 2>/dev/null || \
                sudo "$PKG_MGR" upgrade -y xfce4-session xfwm4 xfdesktop xfce4-panel
            ;;
        arch)
            sudo pacman -Syu --noconfirm xfce4 xfce4-goodies
            ;;
        suse)
            sudo zypper update -y -t pattern xfce
            ;;
    esac
}

setup_install_xfce() {
    info "Installing Xfce Desktop..."
    ensure_tools

    local tier
    tier=$(_prompt_de_tier "Xfce")

    case "$PKG_MGR" in
        apt)
            run_as_root apt-get update
            case "$tier" in
                minimal)
                    info "Installing Xfce (Minimal/Core)..."
                    run_as_root apt-get install -y xfce4 lightdm lightdm-gtk-greeter || {
                        error "Failed to install Xfce (Minimal/Core)"
                        return 1
                    }
                    ;;
                full)
                    info "Installing Xfce (Full Suite)..."
                    # xubuntu-desktop on Ubuntu; fall back to xfce4 + goodies on Debian.
                    run_as_root apt-get install -y xubuntu-desktop lightdm || \
                    run_as_root apt-get install -y xfce4 xfce4-goodies lightdm lightdm-gtk-greeter || {
                        error "Failed to install Xfce (Full Suite)"
                        return 1
                    }
                    ;;
                *)
                    info "Installing Xfce (Standard)..."
                    run_as_root apt-get install -y xfce4 xfce4-goodies lightdm \
                        lightdm-gtk-greeter || {
                        error "Failed to install Xfce (Standard)"
                        return 1
                    }
                    ;;
            esac
            info "Enabling display manager..."
            run_as_root systemctl enable lightdm || warn "Failed to enable lightdm"
            run_as_root systemctl start lightdm || warn "Failed to start lightdm"
            ;;

        dnf|yum)
            case "$tier" in
                minimal)
                    info "Installing Xfce (Minimal/Core)..."
                    run_as_root "$PKG_MGR" install -y xfce4-session xfwm4 xfdesktop \
                        xfce4-panel xfce4-terminal thunar xfce4-settings \
                        lightdm lightdm-gtk || {
                        error "Failed to install Xfce (Minimal/Core)"
                        return 1
                    }
                    ;;
                full)
                    info "Installing Xfce (Full Suite)..."
                    if ! run_as_root "$PKG_MGR" group install -y 'Xfce Desktop' 2>/dev/null && \
                       ! run_as_root "$PKG_MGR" group install -y @xfce-desktop-environment 2>/dev/null; then
                        run_as_root "$PKG_MGR" install -y xfce4-session xfwm4 xfdesktop \
                            xfce4-panel xfce4-terminal thunar xfce4-appfinder \
                            xfce4-settings xfce4-notifyd xfce4-screensaver \
                            lightdm lightdm-gtk || {
                            error "Failed to install Xfce (Full Suite) packages"
                            return 1
                        }
                    fi
                    # Extra Xfce plugins and applications (best-effort).
                    run_as_root "$PKG_MGR" group install -y 'Xfce Applications' @xfce-apps 2>/dev/null || true
                    run_as_root "$PKG_MGR" install -y xfce4-whiskermenu-plugin \
                        xfce4-pulseaudio-plugin xfce4-clipman-plugin xfce4-screenshooter \
                        xfce4-taskmanager mousepad ristretto 2>/dev/null || true
                    ;;
                *)
                    info "Installing Xfce (Standard)..."
                    if ! run_as_root "$PKG_MGR" group install -y 'Xfce Desktop' 2>/dev/null && \
                       ! run_as_root "$PKG_MGR" group install -y @xfce-desktop-environment 2>/dev/null; then
                        info "Group install not available, installing Xfce packages individually..."
                        run_as_root "$PKG_MGR" install -y xfce4-session xfwm4 xfdesktop \
                            xfce4-panel xfce4-terminal thunar xfce4-appfinder \
                            xfce4-settings xfce4-notifyd xfce4-screensaver \
                            lightdm lightdm-gtk || {
                            error "Failed to install Xfce (Standard) packages"
                            return 1
                        }
                    fi
                    ;;
            esac
            info "Enabling display manager..."
            run_as_root systemctl enable lightdm 2>/dev/null || \
                run_as_root systemctl set-default graphical.target
            run_as_root systemctl start lightdm || warn "Failed to start lightdm"
            ;;

        zypper)
            case "$tier" in
                minimal)
                    info "Installing Xfce (Minimal/Core)..."
                    run_as_root zypper install -y -t pattern xfce_basis || {
                        error "Failed to install Xfce (Minimal/Core)"
                        return 1
                    }
                    ;;
                full)
                    info "Installing Xfce (Full Suite)..."
                    run_as_root zypper install -y -t pattern xfce xfce_basis || {
                        error "Failed to install Xfce (Full Suite)"
                        return 1
                    }
                    run_as_root zypper install -y -t pattern xfce_office 2>/dev/null || true
                    ;;
                *)
                    info "Installing Xfce (Standard)..."
                    run_as_root zypper install -y -t pattern xfce xfce_basis || {
                        error "Failed to install Xfce (Standard)"
                        return 1
                    }
                    ;;
            esac
            info "Enabling display manager..."
            run_as_root systemctl enable lightdm 2>/dev/null || \
                run_as_root systemctl set-default graphical.target
            run_as_root systemctl start lightdm || warn "Failed to start lightdm"
            ;;

        pacman)
            case "$tier" in
                minimal)
                    info "Installing Xfce (Minimal/Core)..."
                    run_as_root pacman -S --noconfirm xfce4 lightdm lightdm-gtk-greeter || {
                        error "Failed to install Xfce (Minimal/Core)"
                        return 1
                    }
                    ;;
                *)
                    # Arch's xfce4-goodies group covers the standard and full sets alike.
                    info "Installing Xfce ($([[ $tier == full ]] && echo 'Full Suite' || echo 'Standard'))..."
                    run_as_root pacman -S --noconfirm xfce4 xfce4-goodies \
                        lightdm lightdm-gtk-greeter || {
                        error "Failed to install Xfce Desktop Environment"
                        return 1
                    }
                    ;;
            esac
            info "Enabling display manager..."
            run_as_root systemctl enable lightdm
            run_as_root systemctl start lightdm || warn "Failed to start lightdm"
            ;;

        *)
            error "Xfce installation not fully supported for ${DISTRO_ID}"
            return 1
            ;;
    esac

    info "Xfce Desktop installed successfully. Reboot to start using Xfce."
    return 0
}

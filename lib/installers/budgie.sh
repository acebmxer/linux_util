#!/bin/bash
# Budgie Desktop installer functions

# --- Budgie Desktop ---
check_budgie() {
    command -v budgie-session &>/dev/null || \
        pkg_check_installed budgie-desktop
}

get_version_budgie() {
    local version=""
    # budgie-desktop --version outputs via GTK, not usable headlessly; use pkg instead
    version=$(pkg_get_version budgie-desktop 2>/dev/null || echo "")
    echo "$version" | sed 's/^[0-9]*://; s/-.*//'
}

install_budgie() {
    setup_install_budgie
}

uninstall_budgie() {
    echo "Uninstalling Budgie Desktop..."
    case "$DISTRO_FAMILY" in
        debian)
            sudo apt purge --autoremove -y ubuntu-budgie-desktop budgie-desktop \
                budgie-core budgie-indicator-applet lightdm
            sudo apt autoclean
            ;;
        fedora|rhel)
            sudo "$PKG_MGR" remove -y budgie-desktop budgie-session \
                budgie-backgrounds budgie-desktop-libs
            sudo "$PKG_MGR" autoremove -y
            ;;
        arch)
            sudo pacman -Rs --noconfirm budgie-desktop budgie-desktop-services \
                budgie-desktop-view 2>/dev/null || true
            ;;
        suse)
            sudo zypper remove -y budgie-desktop budgie-session
            ;;
    esac
    rm -rf ~/.config/budgie-* ~/.local/share/budgie-* 2>/dev/null || true
    echo "Budgie Desktop uninstalled. You may need to install another desktop environment."
}

update_budgie() {
    echo "Updating Budgie Desktop..."
    case "$DISTRO_FAMILY" in
        debian)
            sudo apt update
            sudo apt upgrade -y budgie-desktop ubuntu-budgie-desktop 2>/dev/null || \
                sudo apt upgrade -y budgie-desktop
            ;;
        fedora|rhel)
            sudo "$PKG_MGR" upgrade -y budgie-desktop budgie-session budgie-desktop-libs
            ;;
        arch)
            sudo pacman -Syu --noconfirm budgie-desktop budgie-desktop-services \
                budgie-desktop-view
            ;;
        suse)
            sudo zypper update -y budgie-desktop
            ;;
    esac
}

setup_install_budgie() {
    info "Installing Budgie Desktop..."
    ensure_tools

    local tier
    tier=$(_prompt_de_tier "Budgie")

    case "$PKG_MGR" in
        apt)
            run_as_root apt-get update
            case "$tier" in
                minimal)
                    info "Installing Budgie (Minimal/Core)..."
                    run_as_root apt-get install -y budgie-desktop lightdm lightdm-gtk-greeter || {
                        error "Failed to install Budgie (Minimal/Core)"
                        return 1
                    }
                    ;;
                full)
                    info "Installing Budgie (Full Suite)..."
                    # Ubuntu ships the ubuntu-budgie-desktop metapackage; Debian uses budgie-desktop
                    if run_as_root apt-get install -y ubuntu-budgie-desktop lightdm 2>/dev/null; then
                        : # Ubuntu meta installed
                    else
                        run_as_root apt-get install -y budgie-desktop budgie-core \
                            budgie-indicator-applet lightdm lightdm-gtk-greeter || {
                            error "Failed to install Budgie (Full Suite)"
                            return 1
                        }
                    fi
                    ;;
                *)
                    info "Installing Budgie (Standard)..."
                    run_as_root apt-get install -y budgie-desktop budgie-core lightdm \
                        lightdm-gtk-greeter || {
                        error "Failed to install Budgie (Standard)"
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
                    info "Installing Budgie (Minimal/Core)..."
                    run_as_root "$PKG_MGR" install -y budgie-desktop budgie-session \
                        lightdm lightdm-gtk || {
                        error "Failed to install Budgie (Minimal/Core)"
                        return 1
                    }
                    ;;
                full)
                    info "Installing Budgie (Full Suite)..."
                    run_as_root "$PKG_MGR" install -y budgie-desktop budgie-session \
                        budgie-backgrounds budgie-desktop-libs \
                        lightdm lightdm-gtk || {
                        error "Failed to install Budgie (Full Suite)"
                        return 1
                    }
                    run_as_root "$PKG_MGR" install -y budgie-control-center nemo \
                        gnome-terminal gnome-calculator 2>/dev/null || true
                    ;;
                *)
                    info "Installing Budgie (Standard)..."
                    run_as_root "$PKG_MGR" install -y budgie-desktop budgie-session \
                        budgie-backgrounds budgie-desktop-libs \
                        lightdm lightdm-gtk || {
                        error "Failed to install Budgie Desktop Environment"
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
                    info "Installing Budgie (Minimal/Core)..."
                    run_as_root pacman -S --noconfirm budgie-desktop sddm || {
                        error "Failed to install Budgie (Minimal/Core)"
                        return 1
                    }
                    ;;
                full)
                    info "Installing Budgie (Full Suite)..."
                    run_as_root pacman -S --noconfirm budgie-desktop budgie-desktop-services \
                        budgie-desktop-view sddm || {
                        error "Failed to install Budgie (Full Suite)"
                        return 1
                    }
                    run_as_root pacman -S --noconfirm --needed budgie-control-center nemo \
                        gnome-terminal 2>/dev/null || true
                    ;;
                *)
                    info "Installing Budgie (Standard)..."
                    run_as_root pacman -S --noconfirm budgie-desktop budgie-desktop-services \
                        budgie-desktop-view sddm || {
                        error "Failed to install Budgie Desktop Environment"
                        return 1
                    }
                    ;;
            esac
            info "Enabling display manager..."
            run_as_root systemctl enable sddm
            run_as_root systemctl start sddm || warn "Failed to start sddm"
            ;;

        zypper)
            case "$tier" in
                full)
                    info "Installing Budgie (Full Suite)..."
                    run_as_root zypper install -y budgie-desktop lightdm lightdm-gtk-greeter || {
                        error "Failed to install Budgie (Full Suite)"
                        return 1
                    }
                    run_as_root zypper install -y budgie-control-center nemo gnome-terminal 2>/dev/null || true
                    ;;
                *)
                    # openSUSE ships Budgie as a single set; minimal and standard are identical.
                    info "Installing Budgie ($([[ $tier == minimal ]] && echo 'Minimal/Core' || echo 'Standard'))..."
                    run_as_root zypper install -y budgie-desktop lightdm lightdm-gtk-greeter || {
                        error "Failed to install Budgie Desktop Environment"
                        return 1
                    }
                    ;;
            esac
            info "Enabling display manager..."
            run_as_root systemctl enable lightdm 2>/dev/null || \
                run_as_root systemctl set-default graphical.target
            run_as_root systemctl start lightdm || warn "Failed to start lightdm"
            ;;

        *)
            error "Budgie installation not fully supported for ${DISTRO_ID}"
            return 1
            ;;
    esac

    info "Budgie Desktop installed successfully. Reboot to start using Budgie."
    return 0
}

#!/bin/bash
# Cinnamon Desktop installer functions

# --- Cinnamon Desktop ---
check_cinnamon() {
    command -v cinnamon &>/dev/null || \
        pkg_check_installed cinnamon || \
        pkg_check_installed cinnamon-desktop-environment
}

get_version_cinnamon() {
    local version=""
    if command -v cinnamon &>/dev/null; then
        version=$(cinnamon --version 2>/dev/null | grep -oP '[0-9]+\.[0-9.]+' | head -1)
    fi
    if [[ -n "$version" ]]; then
        echo "$version"
    else
        local pkg_ver
        pkg_ver=$(pkg_get_version cinnamon 2>/dev/null || echo "")
        echo "$pkg_ver" | sed 's/^[0-9]*://; s/-.*//'
    fi
}

install_cinnamon() {
    setup_install_cinnamon
}

uninstall_cinnamon() {
    echo "Uninstalling Cinnamon Desktop..."
    case "$DISTRO_FAMILY" in
        debian)
            sudo apt purge --autoremove -y cinnamon cinnamon-core \
                cinnamon-desktop-environment lightdm
            sudo apt autoclean
            ;;
        fedora|rhel)
            sudo "$PKG_MGR" group remove -y @cinnamon-desktop 2>/dev/null || \
                sudo "$PKG_MGR" group remove -y 'Cinnamon Desktop' 2>/dev/null || true
            sudo "$PKG_MGR" autoremove -y
            ;;
        arch)
            sudo pacman -Rs --noconfirm cinnamon lightdm \
                lightdm-gtk-greeter 2>/dev/null || true
            ;;
        suse)
            sudo zypper remove -y cinnamon cinnamon-gschemas 2>/dev/null || true
            ;;
    esac
    rm -rf ~/.config/cinnamon* ~/.cinnamon 2>/dev/null || true
    echo "Cinnamon Desktop uninstalled. You may need to install another desktop environment."
}

update_cinnamon() {
    echo "Updating Cinnamon Desktop..."
    case "$DISTRO_FAMILY" in
        debian)
            sudo apt update
            sudo apt upgrade -y cinnamon cinnamon-core
            ;;
        fedora|rhel)
            sudo "$PKG_MGR" group update -y @cinnamon-desktop 2>/dev/null || \
                sudo "$PKG_MGR" upgrade -y cinnamon cinnamon-control-center
            ;;
        arch)
            sudo pacman -Syu --noconfirm cinnamon
            ;;
        suse)
            sudo zypper update -y cinnamon cinnamon-gschemas
            ;;
    esac
}

setup_install_cinnamon() {
    info "Installing Cinnamon Desktop..."
    ensure_tools

    local tier
    tier=$(_prompt_de_tier "Cinnamon")

    case "$PKG_MGR" in
        apt)
            run_as_root apt-get update
            case "$tier" in
                minimal)
                    info "Installing Cinnamon (Minimal/Core)..."
                    run_as_root apt-get install -y cinnamon-core lightdm lightdm-gtk-greeter || {
                        run_as_root apt-get install -y cinnamon nemo lightdm lightdm-gtk-greeter || {
                            error "Failed to install Cinnamon (Minimal/Core)"
                            return 1
                        }
                    }
                    ;;
                full)
                    info "Installing Cinnamon (Full Suite)..."
                    run_as_root apt-get install -y cinnamon-desktop-environment lightdm || {
                        run_as_root apt-get install -y cinnamon cinnamon-core \
                            nemo lightdm lightdm-settings slick-greeter || {
                            error "Failed to install Cinnamon (Full Suite)"
                            return 1
                        }
                    }
                    ;;
                *)
                    info "Installing Cinnamon (Standard)..."
                    run_as_root apt-get install -y cinnamon nemo lightdm lightdm-gtk-greeter || {
                        run_as_root apt-get install -y cinnamon cinnamon-core \
                            nemo lightdm lightdm-settings slick-greeter || {
                            error "Failed to install Cinnamon (Standard)"
                            return 1
                        }
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
                    info "Installing Cinnamon (Minimal/Core)..."
                    run_as_root "$PKG_MGR" install -y cinnamon nemo \
                        cinnamon-control-center lightdm lightdm-gtk || {
                        error "Failed to install Cinnamon (Minimal/Core)"
                        return 1
                    }
                    ;;
                full)
                    info "Installing Cinnamon (Full Suite)..."
                    if ! run_as_root "$PKG_MGR" group install -y 'Cinnamon Desktop' 2>/dev/null && \
                       ! run_as_root "$PKG_MGR" group install -y @cinnamon-desktop 2>/dev/null; then
                        run_as_root "$PKG_MGR" install -y cinnamon cinnamon-screensaver \
                            nemo nemo-fileroller cinnamon-control-center \
                            lightdm lightdm-gtk || {
                            error "Failed to install Cinnamon (Full Suite) packages"
                            return 1
                        }
                    fi
                    run_as_root "$PKG_MGR" install -y nemo-preview nemo-image-converter \
                        gnome-terminal gnome-calculator 2>/dev/null || true
                    ;;
                *)
                    info "Installing Cinnamon (Standard)..."
                    if ! run_as_root "$PKG_MGR" group install -y 'Cinnamon Desktop' 2>/dev/null && \
                       ! run_as_root "$PKG_MGR" group install -y @cinnamon-desktop 2>/dev/null; then
                        info "Group install not available, installing Cinnamon packages individually..."
                        run_as_root "$PKG_MGR" install -y cinnamon cinnamon-screensaver \
                            nemo nemo-fileroller cinnamon-control-center \
                            lightdm lightdm-gtk || {
                            error "Failed to install Cinnamon (Standard) packages"
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
                    info "Installing Cinnamon (Minimal/Core)..."
                    run_as_root zypper install -y cinnamon cinnamon-gschemas \
                        nemo lightdm lightdm-gtk-greeter 2>/dev/null || {
                        error "Failed to install Cinnamon (Minimal/Core)"
                        return 1
                    }
                    ;;
                full)
                    info "Installing Cinnamon (Full Suite)..."
                    run_as_root zypper install -y cinnamon cinnamon-gschemas \
                        nemo lightdm lightdm-slick-greeter 2>/dev/null || {
                        error "Failed to install Cinnamon (Full Suite)"
                        return 1
                    }
                    run_as_root zypper install -y nemo-extensions cinnamon-screensaver \
                        gnome-terminal 2>/dev/null || true
                    ;;
                *)
                    info "Installing Cinnamon (Standard)..."
                    run_as_root zypper install -y cinnamon cinnamon-gschemas \
                        nemo lightdm lightdm-slick-greeter 2>/dev/null || {
                        error "Failed to install Cinnamon (Standard)"
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
                    info "Installing Cinnamon (Minimal/Core)..."
                    run_as_root pacman -S --noconfirm cinnamon lightdm lightdm-gtk-greeter || {
                        error "Failed to install Cinnamon (Minimal/Core)"
                        return 1
                    }
                    ;;
                full)
                    info "Installing Cinnamon (Full Suite)..."
                    run_as_root pacman -S --noconfirm cinnamon nemo nemo-fileroller \
                        cinnamon-translations gnome-terminal lightdm lightdm-gtk-greeter || {
                        error "Failed to install Cinnamon (Full Suite)"
                        return 1
                    }
                    ;;
                *)
                    info "Installing Cinnamon (Standard)..."
                    run_as_root pacman -S --noconfirm cinnamon nemo \
                        lightdm lightdm-gtk-greeter || {
                        error "Failed to install Cinnamon (Standard)"
                        return 1
                    }
                    ;;
            esac
            info "Enabling display manager..."
            run_as_root systemctl enable lightdm
            run_as_root systemctl start lightdm || warn "Failed to start lightdm"
            ;;

        *)
            error "Cinnamon installation not fully supported for ${DISTRO_ID}"
            return 1
            ;;
    esac

    info "Cinnamon Desktop installed successfully. Reboot to start using Cinnamon."
    return 0
}

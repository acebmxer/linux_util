#!/bin/bash
# MATE Desktop installer functions

# --- MATE Desktop ---
check_mate() {
    _have_cmd mate-session || \
        pkg_check_installed mate-desktop || \
        pkg_check_installed mate-desktop-environment || \
        pkg_check_installed mate
}

get_version_mate() {
    local version=""
    if _have_cmd mate-panel; then
        version=$(_run_native mate-panel --version 2>/dev/null | grep -oP '[0-9]+\.[0-9.]+' | head -1)
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
            sudo apt install -y --only-upgrade mate-desktop-environment mate-desktop-environment-core
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

    local tier
    tier=$(_prompt_de_tier "MATE")

    case "$PKG_MGR" in
        apt)
            run_as_root apt-get update
            case "$tier" in
                minimal)
                    info "Installing MATE (Minimal/Core)..."
                    run_as_root apt-get install -y mate-desktop-environment-core \
                        lightdm lightdm-gtk-greeter || {
                        error "Failed to install MATE (Minimal/Core)"
                        return 1
                    }
                    ;;
                full)
                    info "Installing MATE (Full Suite)..."
                    # ubuntu-mate-desktop on Ubuntu; fall back to the extras meta on Debian.
                    run_as_root apt-get install -y ubuntu-mate-desktop lightdm || \
                    run_as_root apt-get install -y mate-desktop-environment-extras \
                        lightdm lightdm-gtk-greeter || {
                        error "Failed to install MATE (Full Suite)"
                        return 1
                    }
                    ;;
                *)
                    info "Installing MATE (Standard)..."
                    run_as_root apt-get install -y mate-desktop-environment-core \
                        mate-desktop-environment lightdm lightdm-gtk-greeter || {
                        error "Failed to install MATE (Standard)"
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
                    info "Installing MATE (Minimal/Core)..."
                    run_as_root "$PKG_MGR" install -y mate-desktop mate-session-manager \
                        mate-panel mate-control-center mate-terminal caja \
                        lightdm lightdm-gtk || {
                        error "Failed to install MATE (Minimal/Core)"
                        return 1
                    }
                    ;;
                full)
                    info "Installing MATE (Full Suite)..."
                    if ! run_as_root "$PKG_MGR" group install -y 'MATE Desktop' 2>/dev/null && \
                       ! run_as_root "$PKG_MGR" group install -y @mate-desktop 2>/dev/null; then
                        run_as_root "$PKG_MGR" install -y mate-desktop mate-session-manager \
                            mate-panel mate-control-center mate-terminal caja \
                            mate-screensaver mate-media lightdm lightdm-gtk || {
                            error "Failed to install MATE (Full Suite) packages"
                            return 1
                        }
                    fi
                    run_as_root "$PKG_MGR" group install -y 'MATE Applications' @mate-applications 2>/dev/null || true
                    run_as_root "$PKG_MGR" install -y mate-applets mate-utils \
                        mate-calc atril eom pluma engrampa caja-extensions 2>/dev/null || true
                    ;;
                *)
                    info "Installing MATE (Standard)..."
                    if ! run_as_root "$PKG_MGR" group install -y 'MATE Desktop' 2>/dev/null && \
                       ! run_as_root "$PKG_MGR" group install -y @mate-desktop 2>/dev/null; then
                        info "Group install not available, installing MATE packages individually..."
                        run_as_root "$PKG_MGR" install -y mate-desktop mate-session-manager \
                            mate-panel mate-control-center mate-terminal caja \
                            mate-screensaver mate-media lightdm lightdm-gtk || {
                            error "Failed to install MATE (Standard) packages"
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
                    info "Installing MATE (Minimal/Core)..."
                    run_as_root zypper install -y -t pattern mate_basis 2>/dev/null || \
                        run_as_root zypper install -y mate-desktop mate-panel \
                            mate-session-manager caja lightdm lightdm-gtk-greeter || {
                        error "Failed to install MATE (Minimal/Core)"
                        return 1
                    }
                    ;;
                full)
                    info "Installing MATE (Full Suite)..."
                    run_as_root zypper install -y -t pattern mate 2>/dev/null || \
                        run_as_root zypper install -y mate-desktop mate-panel \
                            mate-session-manager caja lightdm lightdm-gtk-greeter || {
                        error "Failed to install MATE (Full Suite)"
                        return 1
                    }
                    run_as_root zypper install -y mate-applets mate-utils mate-calc \
                        atril eom pluma engrampa 2>/dev/null || true
                    ;;
                *)
                    info "Installing MATE (Standard)..."
                    run_as_root zypper install -y -t pattern mate 2>/dev/null || \
                        run_as_root zypper install -y mate-desktop mate-panel \
                            mate-session-manager caja lightdm lightdm-gtk-greeter || {
                        error "Failed to install MATE (Standard)"
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
                    info "Installing MATE (Minimal/Core)..."
                    run_as_root pacman -S --noconfirm mate lightdm lightdm-gtk-greeter || {
                        error "Failed to install MATE (Minimal/Core)"
                        return 1
                    }
                    ;;
                *)
                    # Arch ships MATE as the 'mate' and 'mate-extra' groups (standard + full alike).
                    info "Installing MATE ($([[ $tier == full ]] && echo 'Full Suite' || echo 'Standard'))..."
                    run_as_root pacman -S --noconfirm mate mate-extra \
                        lightdm lightdm-gtk-greeter || {
                        error "Failed to install MATE Desktop Environment"
                        return 1
                    }
                    ;;
            esac
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

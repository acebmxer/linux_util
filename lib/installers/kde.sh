#!/bin/bash
# KDE Desktop installer functions

# --- KDE Desktop ---
check_kde() {
    command -v plasmashell &>/dev/null || \
        pkg_check_installed plasma-desktop || \
        pkg_check_installed kde-plasma-desktop || \
        pkg_check_installed kde-full || \
        pkg_check_installed plasma-meta
}

get_version_kde() {
    # NOTE: Do NOT run 'plasmashell --version' here — even with QT_QPA_PLATFORM=offscreen,
    # it can crash the running plasmashell instance via D-Bus singleton conflicts (Plasma 6).
    local version=""
    # Try kf6-config (Plasma 6) or kf5-config (Plasma 5)
    if command -v kf6-config &>/dev/null; then
        version=$(kf6-config --version 2>/dev/null | grep -oP 'KDE Frameworks: \K[0-9.]+' | head -1)
    elif command -v kf5-config &>/dev/null; then
        version=$(kf5-config --version 2>/dev/null | grep -oP 'KDE Frameworks: \K[0-9.]+' | head -1)
    fi
    if [[ -n "$version" ]]; then
        echo "$version"
    else
        # Fallback: try to get version from package manager
        # Strip epoch (e.g. "4:") and distro suffix (e.g. "-0zneon+24.04+...")
        local pkg_ver
        pkg_ver=$(pkg_get_version plasma-desktop 2>/dev/null || pkg_get_version kde-plasma-desktop 2>/dev/null || echo "")
        echo "$pkg_ver" | sed 's/^[0-9]*://; s/-.*//'
    fi
}

install_kde() {
    setup_install_kde
}

uninstall_kde() {
    echo "Uninstalling KDE Desktop..."
    case "$DISTRO_FAMILY" in
        debian)
            sudo apt purge --autoremove -y kde-full kde-plasma-desktop plasma-desktop sddm
            sudo apt autoclean
            ;;
        fedora|rhel)
            sudo "$PKG_MGR" group remove -y @kde-desktop-environment || \
                sudo "$PKG_MGR" group remove -y 'KDE Plasma Workspaces'
            sudo "$PKG_MGR" autoremove -y
            ;;
        arch)
            sudo pacman -Rs --noconfirm plasma-meta kde-applications-meta sddm 2>/dev/null || true
            ;;
        suse)
            sudo zypper remove -y -t pattern kde kde_plasma
            ;;
    esac
    rm -rf ~/.config/kde*
    rm -rf ~/.kde*
    echo "KDE Desktop uninstalled. You may need to install another desktop environment."
}

update_kde() {
    echo "Updating KDE Desktop..."
    case "$DISTRO_FAMILY" in
        debian)
            sudo apt update
            sudo apt upgrade -y kde-full plasma-desktop
            ;;
        fedora|rhel)
            if ! sudo "$PKG_MGR" group update -y @kde-desktop-environment 2>/dev/null && \
               ! sudo "$PKG_MGR" group update -y 'KDE Plasma Workspaces' 2>/dev/null; then
                # Fallback: update individual packages if group update fails
                echo "Group update not available, updating individual KDE packages..."
                sudo "$PKG_MGR" upgrade -y plasma-desktop plasma-workspace sddm \
                    plasma-nm plasma-pa plasma-systemmonitor kdeplasma-addons \
                    bluedevil breeze-gtk kscreen kinfocenter kwrited \
                    konsole dolphin kate ark gwenview okular spectacle \
                    kde-settings-plasma kde-gtk-config xdg-desktop-portal-kde
            fi
            ;;
        arch)
            sudo pacman -Syu --noconfirm plasma-meta kde-applications-meta
            ;;
        suse)
            sudo zypper update -y -t pattern kde kde_plasma
            ;;
    esac
}

setup_install_kde() {
    info "Installing KDE Plasma Desktop..."
    ensure_tools

    local tier
    tier=$(_prompt_de_tier "KDE Plasma")

    case "$PKG_MGR" in
        apt)
            run_as_root apt-get update
            case "$tier" in
                minimal)
                    info "Installing KDE Plasma (Minimal/Core)..."
                    # plasma-desktop ships only the X11 session; plasma-workspace-wayland
                    # adds kwin-wayland and the Plasma (Wayland) SDDM session entry.
                    run_as_root apt-get install -y plasma-desktop plasma-workspace-wayland sddm || {
                        error "Failed to install KDE Plasma (Minimal/Core)"
                        return 1
                    }
                    ;;
                full)
                    info "Installing KDE Plasma (Full Suite)..."
                    # kubuntu-desktop on Ubuntu; fall back to kde-full on Debian.
                    run_as_root apt-get install -y kubuntu-desktop sddm || \
                    run_as_root apt-get install -y kde-full sddm || {
                        error "Failed to install KDE Plasma (Full Suite)"
                        return 1
                    }
                    ;;
                *)
                    info "Installing KDE Plasma (Standard)..."
                    run_as_root apt-get install -y kde-standard sddm || {
                        error "Failed to install KDE Plasma (Standard)"
                        return 1
                    }
                    ;;
            esac
            info "Enabling display manager..."
            run_as_root systemctl enable sddm || warn "Failed to enable sddm"
            run_as_root systemctl start sddm || warn "Failed to start sddm"
            ;;

        dnf|yum)
            # EPEL / CRB are needed on RHEL clones for the Plasma packages.
            run_as_root "$PKG_MGR" install -y epel-release 2>/dev/null || true
            run_as_root crb enable 2>/dev/null || run_as_root "$PKG_MGR" config-manager --set-enabled crb 2>/dev/null || true
            case "$tier" in
                minimal)
                    info "Installing KDE Plasma (Minimal/Core)..."
                    run_as_root "$PKG_MGR" install -y plasma-desktop plasma-workspace plasma-workspace-wayland sddm \
                        kscreen plasma-nm kde-settings-plasma xdg-desktop-portal-kde || {
                        error "Failed to install KDE Plasma (Minimal/Core)"
                        return 1
                    }
                    ;;
                full)
                    info "Installing KDE Plasma (Full Suite)..."
                    if ! run_as_root "$PKG_MGR" group install -y 'KDE Plasma Workspaces' 'KDE Applications' 'KDE Multimedia Support' 2>/dev/null && \
                       ! run_as_root "$PKG_MGR" group install -y @kde-desktop-environment @kde-apps @kde-media 2>/dev/null; then
                        info "Group install not available, installing KDE packages individually..."
                        run_as_root "$PKG_MGR" install -y plasma-desktop plasma-workspace sddm \
                            plasma-nm plasma-pa plasma-systemmonitor kdeplasma-addons plasma-thunderbolt \
                            bluedevil breeze-gtk kscreen kinfocenter kwrited \
                            konsole dolphin kate ark gwenview okular spectacle \
                            kde-settings-plasma kde-gtk-config xdg-desktop-portal-kde \
                            phonon-qt5-backend-gstreamer || {
                            error "Failed to install KDE Plasma (Full Suite) packages"
                            return 1
                        }
                    fi
                    ;;
                *)
                    info "Installing KDE Plasma (Standard)..."
                    if ! run_as_root "$PKG_MGR" group install -y 'KDE Plasma Workspaces' 2>/dev/null && \
                       ! run_as_root "$PKG_MGR" group install -y @kde-desktop-environment 2>/dev/null; then
                        info "Group install not available, installing KDE packages individually..."
                        run_as_root "$PKG_MGR" install -y plasma-desktop plasma-workspace sddm \
                            plasma-nm plasma-pa plasma-systemmonitor kdeplasma-addons \
                            bluedevil breeze-gtk kscreen kinfocenter \
                            konsole dolphin kate ark gwenview okular spectacle \
                            kde-settings-plasma kde-gtk-config xdg-desktop-portal-kde || {
                            error "Failed to install KDE Plasma (Standard) packages"
                            return 1
                        }
                    fi
                    ;;
            esac
            info "Enabling display manager..."
            run_as_root systemctl enable sddm || run_as_root systemctl set-default graphical.target
            run_as_root systemctl start sddm || warn "Failed to start sddm"
            ;;

        zypper)
            case "$tier" in
                minimal)
                    info "Installing KDE Plasma (Minimal/Core)..."
                    run_as_root zypper install -y -t pattern kde_plasma || {
                        error "Failed to install KDE Plasma (Minimal/Core)"
                        return 1
                    }
                    ;;
                full)
                    info "Installing KDE Plasma (Full Suite)..."
                    run_as_root zypper install -y -t pattern kde kde_plasma kde_utilities kde_imaging kde_multimedia kde_office kde_games || {
                        error "Failed to install KDE Plasma (Full Suite)"
                        return 1
                    }
                    ;;
                *)
                    info "Installing KDE Plasma (Standard)..."
                    run_as_root zypper install -y -t pattern kde kde_plasma || {
                        error "Failed to install KDE Plasma (Standard)"
                        return 1
                    }
                    ;;
            esac
            info "Enabling display manager..."
            run_as_root systemctl enable sddm || run_as_root systemctl set-default graphical.target
            run_as_root systemctl start sddm || warn "Failed to start sddm"
            ;;

        pacman)
            case "$tier" in
                minimal)
                    info "Installing KDE Plasma (Minimal/Core)..."
                    run_as_root pacman -S --noconfirm plasma-desktop sddm || {
                        error "Failed to install KDE Plasma (Minimal/Core)"
                        return 1
                    }
                    ;;
                full)
                    info "Installing KDE Plasma (Full Suite)..."
                    run_as_root pacman -S --noconfirm plasma-meta kde-applications-meta sddm || {
                        error "Failed to install KDE Plasma (Full Suite)"
                        return 1
                    }
                    ;;
                *)
                    info "Installing KDE Plasma (Standard)..."
                    run_as_root pacman -S --noconfirm plasma-meta sddm || {
                        error "Failed to install KDE Plasma (Standard)"
                        return 1
                    }
                    ;;
            esac
            info "Enabling display manager..."
            run_as_root systemctl enable sddm
            run_as_root systemctl start sddm || warn "Failed to start sddm"
            ;;

        *)
            error "KDE installation not fully supported for ${DISTRO_ID}"
            return 1
            ;;
    esac

    info "KDE Plasma Desktop installed successfully. Reboot to start using KDE."
    return 0
}

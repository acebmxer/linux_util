#!/bin/bash
# Deepin Desktop Environment (DDE) installer functions
#
# Availability: Fedora (official repos), Arch (official extra repo),
#               openSUSE Tumbleweed (community OBS: X11:Deepin:Factory).
# NOT available on: Debian/Ubuntu family (no official packages; only an
#   unmaintained PPA that conflicts with GDM), RHEL family (no EPEL coverage),
#   openSUSE Leap / SLES (only the old DDE v20 base package, not a full session).
# Registration in installers.sh is gated to hide on those unsupported distros.

# --- Deepin Desktop ---
check_deepin() {
    _have_cmd startdde || \
        _have_cmd dde-session || \
        pkg_check_installed deepin-session || \
        pkg_check_installed deepin-desktop-base
}

get_version_deepin() {
    local version=""
    version=$(pkg_get_version deepin-session 2>/dev/null || \
              pkg_get_version deepin-desktop-base 2>/dev/null || echo "")
    echo "$version" | sed 's/^[0-9]*://; s/-.*//'
}

install_deepin() {
    setup_install_deepin
}

uninstall_deepin() {
    echo "Uninstalling Deepin Desktop..."
    case "$DISTRO_FAMILY" in
        fedora|rhel)
            sudo "$PKG_MGR" remove -y deepin-session deepin-shell deepin-kwin \
                deepin-control-center deepin-desktop-base deepin-launcher \
                deepin-dock deepin-file-manager deepin-display-manager
            sudo "$PKG_MGR" autoremove -y
            ;;
        arch)
            sudo pacman -Rs --noconfirm deepin deepin-extra sddm 2>/dev/null || true
            ;;
        suse)
            # Remove OBS repo and packages
            sudo zypper removerepo X11:Deepin 2>/dev/null || true
            sudo zypper remove -y deepin-session deepin-desktop-base \
                deepin-kwin deepin-control-center 2>/dev/null || true
            ;;
    esac
    rm -rf ~/.config/deepin* ~/.local/share/deepin* 2>/dev/null || true
    echo "Deepin Desktop uninstalled. You may need to install another desktop environment."
}

update_deepin() {
    echo "Updating Deepin Desktop..."
    case "$DISTRO_FAMILY" in
        fedora|rhel)
            sudo "$PKG_MGR" upgrade -y deepin-session deepin-shell deepin-kwin \
                deepin-control-center deepin-desktop-base
            ;;
        arch)
            sudo pacman -Syu --noconfirm deepin deepin-extra
            ;;
        suse)
            sudo zypper refresh X11:Deepin 2>/dev/null || true
            sudo zypper update -y -t pattern deepin 2>/dev/null || \
                sudo zypper update -y deepin-session deepin-kwin deepin-control-center
            ;;
    esac
}

setup_install_deepin() {
    info "Installing Deepin Desktop (DDE)..."
    ensure_tools

    case "$PKG_MGR" in
        dnf|yum)
            info "Installing Deepin Desktop Environment..."
            # Fedora ships deepin packages in main repos but not as a complete group.
            # Try the group first; fall back to known package list.
            if ! run_as_root "$PKG_MGR" group install -y 'Deepin Desktop' 2>/dev/null && \
               ! run_as_root "$PKG_MGR" group install -y @deepin-desktop 2>/dev/null; then
                info "Group install not available, installing Deepin packages individually..."
                run_as_root "$PKG_MGR" install -y \
                    deepin-session deepin-shell deepin-kwin deepin-control-center \
                    deepin-desktop-base deepin-launcher deepin-dock \
                    deepin-file-manager deepin-terminal \
                    lightdm deepin-display-manager || {
                    error "Failed to install Deepin Desktop Environment packages"
                    return 1
                }
            fi
            info "Enabling display manager..."
            run_as_root systemctl enable lightdm 2>/dev/null || \
                run_as_root systemctl set-default graphical.target
            run_as_root systemctl start lightdm || warn "Failed to start lightdm"
            ;;

        pacman)
            info "Installing Deepin Desktop Environment..."
            # deepin and deepin-extra are official groups in Arch's extra repo
            run_as_root pacman -S --noconfirm deepin deepin-extra sddm || {
                error "Failed to install Deepin Desktop Environment"
                return 1
            }
            info "Enabling display manager..."
            run_as_root systemctl enable sddm
            run_as_root systemctl start sddm || warn "Failed to start sddm"
            ;;

        zypper)
            # openSUSE Tumbleweed only — add the community OBS repo if not already present
            info "Adding Deepin OBS community repository..."
            if ! zypper repos 2>/dev/null | grep -q 'X11:Deepin'; then
                run_as_root zypper addrepo --refresh \
                    "https://download.opensuse.org/repositories/X11:Deepin:Factory/openSUSE_Tumbleweed/" \
                    "X11:Deepin" || {
                    error "Failed to add Deepin OBS repository"
                    return 1
                }
                run_as_root zypper --gpg-auto-import-keys refresh X11:Deepin || {
                    error "Failed to refresh Deepin OBS repository"
                    return 1
                }
            fi
            info "Installing Deepin Desktop Environment..."
            run_as_root zypper install -y --from X11:Deepin -t pattern deepin 2>/dev/null || \
                run_as_root zypper install -y --from X11:Deepin \
                    deepin-session deepin-kwin deepin-control-center \
                    deepin-desktop-base deepin-file-manager sddm || {
                error "Failed to install Deepin Desktop Environment"
                return 1
            }
            info "Enabling display manager..."
            run_as_root systemctl enable sddm 2>/dev/null || \
                run_as_root systemctl set-default graphical.target
            run_as_root systemctl start sddm || warn "Failed to start sddm"
            ;;

        *)
            error "Deepin Desktop installation not supported for ${DISTRO_ID}"
            return 1
            ;;
    esac

    info "Deepin Desktop installed successfully. Reboot to start using DDE."
    return 0
}

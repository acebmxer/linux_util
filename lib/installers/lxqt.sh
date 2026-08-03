#!/bin/bash
# LXQt Desktop installer functions

# --- LXQt Desktop ---
check_lxqt() {
    _have_cmd lxqt-session || \
        pkg_check_installed lxqt-session
}

get_version_lxqt() {
    local version=""
    if _have_cmd lxqt-session; then
        version=$(_run_native lxqt-session --version 2>/dev/null | grep -oP '[0-9]+\.[0-9.]+' | head -1)
    fi
    if [[ -n "$version" ]]; then
        echo "$version"
    else
        local pkg_ver
        pkg_ver=$(pkg_get_version lxqt-session 2>/dev/null || echo "")
        echo "$pkg_ver" | sed 's/^[0-9]*://; s/-.*//'
    fi
}

install_lxqt() {
    setup_install_lxqt
}

uninstall_lxqt() {
    echo "Uninstalling LXQt Desktop..."
    case "$DISTRO_FAMILY" in
        debian)
            sudo apt purge --autoremove -y task-lxqt-desktop lubuntu-desktop \
                lxqt lxqt-session sddm
            sudo apt autoclean
            ;;
        fedora|rhel)
            sudo "$PKG_MGR" group remove -y @lxqt 2>/dev/null || \
                sudo "$PKG_MGR" remove -y lxqt-session lxqt-panel pcmanfm-qt
            sudo "$PKG_MGR" autoremove -y
            ;;
        arch)
            sudo pacman -Rs --noconfirm lxqt sddm 2>/dev/null || true
            ;;
        suse)
            sudo zypper remove -y lxqt-session lxqt-panel sddm
            ;;
    esac
    rm -rf ~/.config/lxqt 2>/dev/null || true
    echo "LXQt Desktop uninstalled. You may need to install another desktop environment."
}

update_lxqt() {
    echo "Updating LXQt Desktop..."
    case "$DISTRO_FAMILY" in
        debian)
            sudo apt update
            sudo apt install -y --only-upgrade lxqt lxqt-session
            ;;
        fedora|rhel)
            sudo "$PKG_MGR" group update -y @lxqt 2>/dev/null || \
                sudo "$PKG_MGR" upgrade -y lxqt-session lxqt-panel
            ;;
        arch)
            sudo pacman -Syu --noconfirm lxqt
            ;;
        suse)
            sudo zypper update -y lxqt-session lxqt-panel
            ;;
    esac
}

setup_install_lxqt() {
    info "Installing LXQt Desktop..."
    ensure_tools

    local tier
    tier=$(_prompt_de_tier "LXQt")

    case "$PKG_MGR" in
        apt)
            run_as_root apt-get update
            case "$tier" in
                minimal)
                    info "Installing LXQt (Minimal/Core)..."
                    run_as_root apt-get install -y lxqt-core sddm 2>/dev/null || \
                    run_as_root apt-get install -y lxqt-session lxqt-panel lxqt-runner \
                        lxqt-config pcmanfm-qt sddm || {
                        error "Failed to install LXQt (Minimal/Core)"
                        return 1
                    }
                    ;;
                full)
                    info "Installing LXQt (Full Suite)..."
                    # lubuntu-desktop on Ubuntu; fall back to the lxqt meta on Debian.
                    if run_as_root apt-get install -y lubuntu-desktop 2>/dev/null; then
                        : # Ubuntu/Lubuntu meta installed
                    elif run_as_root apt-get install -y lxqt sddm 2>/dev/null; then
                        : # Debian lxqt meta installed
                    else
                        run_as_root apt-get install -y lxqt-session lxqt-panel lxqt-runner \
                            lxqt-config pcmanfm-qt qterminal lximage-qt sddm || {
                            error "Failed to install LXQt (Full Suite)"
                            return 1
                        }
                    fi
                    ;;
                *)
                    info "Installing LXQt (Standard)..."
                    # Ubuntu/Lubuntu: use lubuntu-desktop meta; Debian: task-lxqt-desktop
                    if run_as_root apt-get install -y task-lxqt-desktop sddm 2>/dev/null; then
                        : # Debian task package installed
                    elif run_as_root apt-get install -y lubuntu-desktop 2>/dev/null; then
                        : # Ubuntu/Lubuntu meta installed
                    else
                        run_as_root apt-get install -y lxqt-session lxqt-panel lxqt-runner \
                            lxqt-config pcmanfm-qt qterminal lximage-qt sddm || {
                            error "Failed to install LXQt (Standard)"
                            return 1
                        }
                    fi
                    ;;
            esac
            info "Enabling display manager..."
            run_as_root systemctl enable sddm || warn "Failed to enable sddm"
            run_as_root systemctl start sddm || warn "Failed to start sddm"
            ;;

        dnf|yum)
            case "$tier" in
                minimal)
                    info "Installing LXQt (Minimal/Core)..."
                    run_as_root "$PKG_MGR" install -y lxqt-session lxqt-panel \
                        lxqt-runner lxqt-config pcmanfm-qt lxqt-notificationd sddm || {
                        error "Failed to install LXQt (Minimal/Core)"
                        return 1
                    }
                    ;;
                full)
                    info "Installing LXQt (Full Suite)..."
                    if ! run_as_root "$PKG_MGR" group install -y @lxqt 2>/dev/null && \
                       ! run_as_root "$PKG_MGR" group install -y 'LXQt Desktop' 2>/dev/null; then
                        run_as_root "$PKG_MGR" install -y lxqt-session lxqt-panel \
                            lxqt-runner lxqt-config pcmanfm-qt qterminal \
                            lxqt-notificationd sddm || {
                            error "Failed to install LXQt (Full Suite) packages"
                            return 1
                        }
                    fi
                    run_as_root "$PKG_MGR" install -y lximage-qt lxqt-archiver featherpad \
                        screengrab pavucontrol-qt qps 2>/dev/null || true
                    ;;
                *)
                    info "Installing LXQt (Standard)..."
                    if ! run_as_root "$PKG_MGR" group install -y @lxqt 2>/dev/null && \
                       ! run_as_root "$PKG_MGR" group install -y 'LXQt Desktop' 2>/dev/null; then
                        info "Group install not available, installing LXQt packages individually..."
                        run_as_root "$PKG_MGR" install -y lxqt-session lxqt-panel \
                            lxqt-runner lxqt-config pcmanfm-qt qterminal \
                            lxqt-notificationd sddm || {
                            error "Failed to install LXQt (Standard) packages"
                            return 1
                        }
                    fi
                    ;;
            esac
            info "Enabling display manager..."
            run_as_root systemctl enable sddm 2>/dev/null || \
                run_as_root systemctl set-default graphical.target
            run_as_root systemctl start sddm || warn "Failed to start sddm"
            ;;

        pacman)
            case "$tier" in
                minimal)
                    info "Installing LXQt (Minimal/Core)..."
                    run_as_root pacman -S --noconfirm lxqt-session lxqt-panel \
                        lxqt-runner lxqt-config pcmanfm-qt sddm || {
                        error "Failed to install LXQt (Minimal/Core)"
                        return 1
                    }
                    ;;
                full)
                    info "Installing LXQt (Full Suite)..."
                    # lxqt is an official package group in the extra repo
                    run_as_root pacman -S --noconfirm lxqt sddm || {
                        error "Failed to install LXQt (Full Suite)"
                        return 1
                    }
                    run_as_root pacman -S --noconfirm --needed featherpad qterminal \
                        screengrab lximage-qt pavucontrol-qt 2>/dev/null || true
                    ;;
                *)
                    info "Installing LXQt (Standard)..."
                    # lxqt is an official package group in the extra repo
                    run_as_root pacman -S --noconfirm lxqt sddm || {
                        error "Failed to install LXQt (Standard)"
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
                minimal)
                    info "Installing LXQt (Minimal/Core)..."
                    run_as_root zypper install -y lxqt-session lxqt-panel lxqt-runner \
                        lxqt-config pcmanfm-qt sddm || {
                        error "Failed to install LXQt (Minimal/Core)"
                        return 1
                    }
                    ;;
                full)
                    info "Installing LXQt (Full Suite)..."
                    run_as_root zypper install -y lxqt-session lxqt-panel lxqt-runner \
                        lxqt-config pcmanfm-qt qterminal sddm || {
                        error "Failed to install LXQt (Full Suite)"
                        return 1
                    }
                    run_as_root zypper install -y lximage-qt lxqt-archiver screengrab \
                        featherpad pavucontrol-qt 2>/dev/null || true
                    ;;
                *)
                    info "Installing LXQt (Standard)..."
                    run_as_root zypper install -y lxqt-session lxqt-panel lxqt-runner \
                        lxqt-config pcmanfm-qt qterminal sddm || {
                        error "Failed to install LXQt (Standard)"
                        return 1
                    }
                    ;;
            esac
            info "Enabling display manager..."
            run_as_root systemctl enable sddm 2>/dev/null || \
                run_as_root systemctl set-default graphical.target
            run_as_root systemctl start sddm || warn "Failed to start sddm"
            ;;

        *)
            error "LXQt installation not fully supported for ${DISTRO_ID}"
            return 1
            ;;
    esac

    info "LXQt Desktop installed successfully. Reboot to start using LXQt."
    return 0
}

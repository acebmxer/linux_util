#!/bin/bash
# LXQt Desktop installer functions

# --- LXQt Desktop ---
check_lxqt() {
    command -v lxqt-session &>/dev/null || \
        pkg_check_installed lxqt-session
}

get_version_lxqt() {
    local version=""
    if command -v lxqt-session &>/dev/null; then
        version=$(lxqt-session --version 2>/dev/null | grep -oP '[0-9]+\.[0-9.]+' | head -1)
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
            sudo apt upgrade -y lxqt lxqt-session
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

    case "$PKG_MGR" in
        apt)
            run_as_root apt-get update
            info "Installing LXQt Desktop Environment..."
            # Ubuntu/Lubuntu: use lubuntu-desktop meta; Debian: task-lxqt-desktop
            if run_as_root apt-get install -y task-lxqt-desktop sddm 2>/dev/null; then
                : # Debian task package installed
            elif run_as_root apt-get install -y lubuntu-desktop 2>/dev/null; then
                : # Ubuntu/Lubuntu meta installed
            else
                run_as_root apt-get install -y lxqt-session lxqt-panel lxqt-runner \
                    lxqt-config pcmanfm-qt qterminal lximage-qt sddm || {
                    error "Failed to install LXQt Desktop Environment"
                    return 1
                }
            fi
            info "Enabling display manager..."
            run_as_root systemctl enable sddm || warn "Failed to enable sddm"
            run_as_root systemctl start sddm || warn "Failed to start sddm"
            ;;

        dnf|yum)
            info "Installing LXQt Desktop Environment..."
            if ! run_as_root "$PKG_MGR" group install -y @lxqt 2>/dev/null && \
               ! run_as_root "$PKG_MGR" group install -y 'LXQt Desktop' 2>/dev/null; then
                info "Group install not available, installing LXQt packages individually..."
                run_as_root "$PKG_MGR" install -y lxqt-session lxqt-panel \
                    lxqt-runner lxqt-config pcmanfm-qt qterminal \
                    lxqt-notificationd sddm || {
                    error "Failed to install LXQt Desktop Environment packages"
                    return 1
                }
            fi
            info "Enabling display manager..."
            run_as_root systemctl enable sddm 2>/dev/null || \
                run_as_root systemctl set-default graphical.target
            run_as_root systemctl start sddm || warn "Failed to start sddm"
            ;;

        pacman)
            info "Installing LXQt Desktop Environment..."
            # lxqt is an official package group in the extra repo
            run_as_root pacman -S --noconfirm lxqt sddm || {
                error "Failed to install LXQt Desktop Environment"
                return 1
            }
            info "Enabling display manager..."
            run_as_root systemctl enable sddm
            run_as_root systemctl start sddm || warn "Failed to start sddm"
            ;;

        zypper)
            info "Installing LXQt Desktop Environment..."
            run_as_root zypper install -y lxqt-session lxqt-panel lxqt-runner \
                lxqt-config pcmanfm-qt qterminal sddm || {
                error "Failed to install LXQt Desktop Environment"
                return 1
            }
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

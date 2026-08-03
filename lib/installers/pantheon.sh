#!/bin/bash
# Pantheon Desktop installer functions
#
# Availability: Arch (official extra repo), openSUSE Tumbleweed (Factory pattern).
# NOT available on: Debian/Ubuntu family, Fedora, RHEL family,
#                   openSUSE Leap/SLES, elementary OS (Pantheon is already installed).
# Registration in installers.sh uses an allowlist to restrict to supported distros.

# --- Pantheon Desktop ---
check_pantheon() {
    _have_cmd gala || \
        pkg_check_installed gala || \
        pkg_check_installed pantheon
}

get_version_pantheon() {
    local version=""
    version=$(pkg_get_version gala 2>/dev/null || \
              pkg_get_version wingpanel 2>/dev/null || echo "")
    echo "$version" | sed 's/^[0-9]*://; s/-.*//'
}

install_pantheon() {
    setup_install_pantheon
}

uninstall_pantheon() {
    echo "Uninstalling Pantheon Desktop..."
    case "$DISTRO_FAMILY" in
        arch)
            sudo pacman -Rs --noconfirm pantheon lightdm-pantheon-greeter 2>/dev/null || \
                sudo pacman -Rs --noconfirm gala wingpanel switchboard \
                    pantheon-session io.elementary.greeter 2>/dev/null || true
            ;;
        suse)
            sudo zypper remove -y -t pattern pantheon 2>/dev/null || \
                sudo zypper remove -y gala wingpanel switchboard sddm 2>/dev/null || true
            ;;
    esac
    rm -rf ~/.config/pantheon ~/.local/share/io.elementary.* 2>/dev/null || true
    echo "Pantheon Desktop uninstalled. You may need to install another desktop environment."
}

update_pantheon() {
    echo "Updating Pantheon Desktop..."
    case "$DISTRO_FAMILY" in
        arch)
            sudo pacman -Syu --noconfirm pantheon 2>/dev/null || \
                sudo pacman -Syu --noconfirm gala wingpanel switchboard
            ;;
        suse)
            sudo zypper update -y -t pattern pantheon 2>/dev/null || \
                sudo zypper update -y gala wingpanel switchboard
            ;;
    esac
}

setup_install_pantheon() {
    info "Installing Pantheon Desktop..."
    ensure_tools

    case "$PKG_MGR" in
        pacman)
            info "Installing Pantheon Desktop Environment..."
            # pantheon is an official group in Arch's extra repo.
            # lightdm-pantheon-greeter is the io.elementary.greeter package.
            run_as_root pacman -S --noconfirm pantheon lightdm lightdm-pantheon-greeter || {
                # Fallback: install core components individually
                run_as_root pacman -S --noconfirm gala wingpanel switchboard \
                    pantheon-session pantheon-terminal pantheon-files \
                    lightdm lightdm-pantheon-greeter || {
                    error "Failed to install Pantheon Desktop Environment"
                    return 1
                }
            }
            # Configure LightDM to use the Pantheon greeter
            if [[ -f /etc/lightdm/lightdm.conf ]]; then
                sudo sed -i 's/^#\?greeter-session=.*/greeter-session=io.elementary.greeter/' \
                    /etc/lightdm/lightdm.conf
            fi
            info "Enabling display manager..."
            run_as_root systemctl enable lightdm
            run_as_root systemctl start lightdm || warn "Failed to start lightdm"
            ;;

        zypper)
            # openSUSE Tumbleweed only — patterns-pantheon-pantheon is in Factory
            info "Installing Pantheon Desktop Environment..."
            run_as_root zypper install -y -t pattern pantheon || {
                error "Failed to install Pantheon Desktop Environment"
                return 1
            }
            info "Enabling display manager..."
            run_as_root systemctl enable lightdm 2>/dev/null || \
                run_as_root systemctl set-default graphical.target
            run_as_root systemctl start lightdm || warn "Failed to start lightdm"
            ;;

        *)
            error "Pantheon Desktop installation is only supported on Arch Linux and openSUSE Tumbleweed."
            return 1
            ;;
    esac

    info "Pantheon Desktop installed successfully. Reboot to start using Pantheon."
    return 0
}

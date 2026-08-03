#!/bin/bash
# COSMIC Desktop installer functions
# COSMIC is the new Rust-based desktop environment by System76

# --- COSMIC Desktop ---
check_cosmic() {
    _have_cmd cosmic-session || \
        pkg_check_installed cosmic-session || \
        pkg_check_installed cosmic
}

get_version_cosmic() {
    local version=""
    # Try to get version from package manager first (most reliable method)
    version=$(pkg_get_version cosmic-session 2>/dev/null || echo "")
    if [[ -n "$version" ]]; then
        echo "$version" | sed 's/^[0-9]*://; s/-.*//'
        return
    fi
    # Fallback: check cosmic-comp or cosmic package
    version=$(pkg_get_version cosmic-comp 2>/dev/null || pkg_get_version cosmic 2>/dev/null || echo "")
    echo "$version" | sed 's/^[0-9]*://; s/-.*//'
}

install_cosmic() {
    setup_install_cosmic
}

uninstall_cosmic() {
    echo "Uninstalling COSMIC Desktop..."
    case "$DISTRO_FAMILY" in
        debian)
            sudo apt purge --autoremove -y cosmic-session cosmic-greeter \
                cosmic-comp cosmic-panel cosmic-applets cosmic-settings || true
            sudo apt autoclean
            ;;
        fedora|rhel)
            sudo "$PKG_MGR" group remove -y @cosmic-desktop 2>/dev/null || \
                sudo "$PKG_MGR" remove -y cosmic-session cosmic-comp cosmic-greeter 2>/dev/null || true
            sudo "$PKG_MGR" autoremove -y
            ;;
        arch)
            sudo pacman -Rs --noconfirm cosmic 2>/dev/null || \
                sudo pacman -Rs --noconfirm cosmic-session cosmic-comp cosmic-panel 2>/dev/null || true
            ;;
        suse)
            sudo zypper remove -y cosmic-session cosmic-comp cosmic-greeter 2>/dev/null || true
            ;;
    esac
    rm -rf ~/.config/cosmic* 2>/dev/null || true
    echo "COSMIC Desktop uninstalled. You may need to install another desktop environment."
}

update_cosmic() {
    echo "Updating COSMIC Desktop..."
    case "$DISTRO_FAMILY" in
        debian)
            sudo apt update
            sudo apt install -y --only-upgrade cosmic-session cosmic-comp cosmic-panel \
                cosmic-applets cosmic-settings cosmic-greeter 2>/dev/null || true
            ;;
        fedora|rhel)
            sudo "$PKG_MGR" group update -y @cosmic-desktop 2>/dev/null || \
                sudo "$PKG_MGR" upgrade -y cosmic-session cosmic-comp cosmic-greeter 2>/dev/null || true
            ;;
        arch)
            sudo pacman -Syu --noconfirm cosmic 2>/dev/null || true
            ;;
        suse)
            sudo zypper update -y cosmic-session cosmic-comp 2>/dev/null || true
            ;;
    esac
}

setup_install_cosmic() {
    info "Installing COSMIC Desktop..."
    ensure_tools

    case "$PKG_MGR" in
        apt)
            run_as_root apt-get update
            info "Installing COSMIC Desktop Environment..."
            # Ubuntu 24.10+ / Debian Trixie: cosmic-session is in the repos
            if run_as_root apt-get install -y cosmic-session cosmic-greeter 2>/dev/null; then
                info "Enabling COSMIC greeter..."
                run_as_root systemctl enable cosmic-greeter 2>/dev/null || \
                    warn "cosmic-greeter service not found; a reboot may be required to switch DMs"
            else
                # Fallback: Try adding System76 PPA on Ubuntu
                if command -v add-apt-repository &>/dev/null && \
                   [[ "$DISTRO_ID" == "ubuntu" || "$DISTRO_ID" == "kubuntu" ]]; then
                    warn "cosmic-session not found in default repos, trying System76 PPA..."
                    run_as_root add-apt-repository -y ppa:system76-dev/cosmic-epoch 2>/dev/null || \
                        run_as_root add-apt-repository -y ppa:system76-dev/stable 2>/dev/null || {
                        error "Failed to add COSMIC PPA"
                        return 1
                    }
                    run_as_root apt-get update
                    run_as_root apt-get install -y cosmic-session cosmic-greeter || {
                        error "Failed to install COSMIC Desktop Environment"
                        return 1
                    }
                    run_as_root systemctl enable cosmic-greeter 2>/dev/null || true
                else
                    error "COSMIC is not available in your current repositories."
                    error "It requires Ubuntu 24.10+ or Debian Trixie/Sid."
                    return 1
                fi
            fi
            ;;

        dnf|yum)
            info "Installing COSMIC Desktop Environment..."
            # Fedora 42+ ships cosmic-session in the repos
            if run_as_root "$PKG_MGR" group install -y @cosmic-desktop 2>/dev/null || \
               run_as_root "$PKG_MGR" install -y cosmic-session cosmic-comp \
                   cosmic-panel cosmic-applets cosmic-settings cosmic-greeter 2>/dev/null; then
                info "Enabling COSMIC greeter..."
                run_as_root systemctl enable cosmic-greeter 2>/dev/null || \
                    run_as_root systemctl set-default graphical.target
            else
                error "COSMIC Desktop not found. It requires Fedora 42 or newer."
                return 1
            fi
            ;;

        zypper)
            info "Installing COSMIC Desktop Environment..."
            if run_as_root zypper install -y cosmic-session cosmic-comp \
                cosmic-panel cosmic-settings cosmic-greeter 2>/dev/null; then
                run_as_root systemctl enable cosmic-greeter 2>/dev/null || \
                    run_as_root systemctl set-default graphical.target
            else
                error "COSMIC Desktop packages not found in openSUSE repositories."
                return 1
            fi
            ;;

        pacman)
            info "Installing COSMIC Desktop Environment..."
            # COSMIC is in Arch extra repo since late 2024
            run_as_root pacman -S --noconfirm cosmic 2>/dev/null || \
                run_as_root pacman -S --noconfirm cosmic-session cosmic-comp \
                    cosmic-panel cosmic-applets cosmic-settings || {
                error "Failed to install COSMIC Desktop Environment"
                return 1
            }
            info "Enabling COSMIC greeter..."
            run_as_root systemctl enable cosmic-greeter 2>/dev/null || \
                warn "cosmic-greeter not available; configure a display manager manually"
            ;;

        *)
            error "COSMIC installation not fully supported for ${DISTRO_ID}"
            return 1
            ;;
    esac

    info "COSMIC Desktop installed successfully. Reboot to start using COSMIC."
    return 0
}

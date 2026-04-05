#!/bin/bash
# Signal Desktop installer functions

# --- Signal Desktop ---

check_signal() {
    command -v signal-desktop &>/dev/null || \
        pkg_check_installed signal-desktop || \
        (has_flatpak && flatpak list 2>/dev/null | grep -qi "org.signal.Signal")
}

install_signal() {
    info "Installing Signal Desktop..."
    ensure_tools
    case "$DISTRO_FAMILY" in
        debian)
            # Official Signal apt repository
            sudo mkdir -p /etc/apt/keyrings
            wget -qO- https://updates.signal.org/desktop/apt/keys.asc | \
                gpg --dearmor | \
                sudo tee /etc/apt/keyrings/signal-desktop-keyring.gpg > /dev/null
            echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/signal-desktop-keyring.gpg] https://updates.signal.org/desktop/apt xenial main" | \
                sudo tee /etc/apt/sources.list.d/signal-xenial.list > /dev/null
            sudo apt update
            sudo apt install -y signal-desktop
            ;;
        fedora|rhel|suse)
            if has_flatpak; then
                flatpak install -y flathub org.signal.Signal
            else
                error "Signal requires Flatpak on this system. Install Flatpak first."
                return 1
            fi
            ;;
        arch)
            if has_aur_helper; then
                aur_install signal-desktop
            else
                aur_build signal-desktop
            fi
            ;;
    esac
    info "Signal Desktop installed."
}

uninstall_signal() {
    info "Uninstalling Signal Desktop..."
    if has_flatpak && flatpak list 2>/dev/null | grep -qi "org.signal.Signal"; then
        flatpak uninstall -y org.signal.Signal
    else
        case "$DISTRO_FAMILY" in
            debian)
                sudo apt purge --autoremove -y signal-desktop
                sudo rm -f /etc/apt/sources.list.d/signal-xenial.list
                sudo rm -f /etc/apt/keyrings/signal-desktop-keyring.gpg
                ;;
            arch)
                aur_remove signal-desktop 2>/dev/null || \
                    sudo pacman -Rs --noconfirm signal-desktop 2>/dev/null || true
                ;;
        esac
    fi
    rm -rf "$HOME/.config/Signal"
}

update_signal() {
    info "Updating Signal Desktop..."
    if has_flatpak && flatpak list 2>/dev/null | grep -qi "org.signal.Signal"; then
        flatpak update -y org.signal.Signal
    else
        case "$DISTRO_FAMILY" in
            debian)   sudo apt update && sudo apt upgrade -y signal-desktop ;;
            arch)
                if has_aur_helper; then
                    aur_upgrade signal-desktop
                else
                    aur_build signal-desktop
                fi
                ;;
        esac
    fi
}

get_version_signal() {
    signal-desktop --version 2>/dev/null | grep -oP '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || \
    (has_flatpak && flatpak list 2>/dev/null | grep -i "org.signal.Signal" | awk -F'\t' '{print $3}') || \
    pkg_get_version signal-desktop 2>/dev/null | sed 's/-.*//' || \
    echo ""
}

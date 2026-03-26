#!/bin/bash
# Feral Gamemode installer functions

# --- Feral Gamemode ---
check_gamemode() {
    command -v gamemoded &>/dev/null || pkg_check_installed gamemode
}

install_gamemode() {
    echo "Installing Feral Gamemode..."
    ensure_tools
    case "$DISTRO_FAMILY" in
        debian)
            sudo apt update
            sudo apt install -y gamemode
            ;;
        fedora)
            sudo "$PKG_MGR" install -y gamemode
            ;;
        rhel)
            echo "Feral Gamemode is not available in standard RHEL repositories."
            echo "Consider building from source: https://github.com/feralinteractive/gamemode"
            return 1
            ;;
        arch)
            sudo pacman -S --noconfirm gamemode lib32-gamemode
            ;;
        suse)
            sudo zypper install -y gamemode
            ;;
    esac
    echo "Feral Gamemode installed successfully."
}

uninstall_gamemode() {
    echo "Uninstalling Feral Gamemode..."
    case "$DISTRO_FAMILY" in
        debian)
            sudo apt purge --autoremove -y gamemode
            sudo apt autoclean
            ;;
        fedora|rhel)
            sudo "$PKG_MGR" remove -y gamemode
            ;;
        arch)
            sudo pacman -Rs --noconfirm lib32-gamemode 2>/dev/null || true
            sudo pacman -Rs --noconfirm gamemode 2>/dev/null || true
            ;;
        suse)
            sudo zypper remove -y gamemode 2>/dev/null || true
            ;;
    esac
    rm -f ~/.config/gamemode.ini
    echo "Feral Gamemode has been uninstalled."
}

update_gamemode() {
    echo "Updating Feral Gamemode..."
    case "$DISTRO_FAMILY" in
        debian)
            sudo apt update
            sudo apt upgrade -y gamemode
            ;;
        fedora|rhel)
            sudo "$PKG_MGR" upgrade -y gamemode
            ;;
        arch)
            sudo pacman -S --noconfirm gamemode lib32-gamemode
            ;;
        suse)
            sudo zypper update -y gamemode
            ;;
    esac
}

get_version_gamemode() {
    local ver
    ver=$(gamemoded --version 2>/dev/null | grep -oP '[0-9]+\.[0-9]+[^\s]*' | head -1)
    if [[ -n "$ver" ]]; then
        echo "$ver"
    else
        pkg_get_version gamemode | sed 's/^[0-9]*://; s/-.*//' || echo ""
    fi
}

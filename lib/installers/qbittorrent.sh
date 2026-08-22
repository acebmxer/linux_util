#!/bin/bash
# QBittorrent installer functions

# --- QBittorrent ---
check_qbittorrent() { _check_standard qbittorrent qbittorrent ""; }

install_qbittorrent() {
    echo "Installing QBittorrent..."
    ensure_tools
    case "$DISTRO_FAMILY" in
        debian)
            sudo apt update
            sudo apt install -y qbittorrent
            ;;
        fedora)
            sudo "$PKG_MGR" install -y qbittorrent
            ;;
        rhel)
            # qbittorrent is in EPEL, not the base RHEL/Alma/Rocky repos
            sudo "$PKG_MGR" install -y epel-release 2>/dev/null || true
            sudo "$PKG_MGR" install -y qbittorrent
            ;;
        arch)
            sudo pacman -S --noconfirm qbittorrent
            ;;
        suse)
            if has_flatpak; then
                sudo flatpak install -y flathub org.qbittorrent.qBittorrent
            else
                sudo zypper install -y qbittorrent
            fi
            ;;
    esac
    echo "QBittorrent installed successfully."
}

uninstall_qbittorrent() {
    echo "Uninstalling QBittorrent..."
    case "$DISTRO_FAMILY" in
        debian)
            sudo apt purge --autoremove -y qbittorrent
            sudo apt autoclean
            ;;
        fedora|rhel)
            sudo "$PKG_MGR" remove -y qbittorrent
            ;;
        arch)
            sudo pacman -Rs --noconfirm qbittorrent 2>/dev/null || true
            ;;
        suse)
            flatpak uninstall -y org.qbittorrent.qBittorrent 2>/dev/null || \
            sudo zypper remove -y qbittorrent 2>/dev/null || true
            ;;
    esac
    rm -rf ~/.config/qBittorrent
    rm -rf ~/.qBittorrent
    echo "QBittorrent has been uninstalled."
}

update_qbittorrent() {
    echo "Updating QBittorrent..."
    case "$DISTRO_FAMILY" in
        debian)
            sudo apt update
            sudo apt install -y --only-upgrade qbittorrent
            ;;
        fedora|rhel)
            sudo "$PKG_MGR" upgrade -y qbittorrent
            ;;
        arch)
            sudo pacman -S --noconfirm qbittorrent
            ;;
        suse)
            flatpak update -y org.qbittorrent.qBittorrent 2>/dev/null || \
            sudo zypper update -y qbittorrent 2>/dev/null || true
            ;;
    esac
}

get_version_qbittorrent() {
    _ver_from_pkg qbittorrent || echo ""
}

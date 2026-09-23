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
            pkg_install qbittorrent
            ;;
        fedora)
            pkg_install qbittorrent
            ;;
        rhel)
            # qbittorrent is in EPEL, not the base RHEL/Alma/Rocky repos
            pkg_install epel-release 2>/dev/null || true
            pkg_install qbittorrent
            ;;
        arch)
            pkg_install qbittorrent
            ;;
        suse)
            if has_flatpak; then
                sudo flatpak install -y flathub org.qbittorrent.qBittorrent
            else
                pkg_install qbittorrent
            fi
            ;;
    esac
    echo "QBittorrent installed successfully."
}

uninstall_qbittorrent() {
    echo "Uninstalling QBittorrent..."
    case "$DISTRO_FAMILY" in
        debian)
            pkg_remove qbittorrent
            ;;
        fedora|rhel)
            pkg_remove qbittorrent
            ;;
        arch)
            pkg_remove qbittorrent 2>/dev/null || true
            ;;
        suse)
            flatpak uninstall -y org.qbittorrent.qBittorrent 2>/dev/null || \
            pkg_remove qbittorrent 2>/dev/null || true
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
            pkg_upgrade qbittorrent
            ;;
        fedora|rhel)
            pkg_upgrade qbittorrent
            ;;
        arch)
            pkg_upgrade qbittorrent
            ;;
        suse)
            flatpak update -y org.qbittorrent.qBittorrent 2>/dev/null || \
            pkg_upgrade qbittorrent 2>/dev/null || true
            ;;
    esac
}

get_version_qbittorrent() {
    _ver_from_pkg qbittorrent || echo ""
}

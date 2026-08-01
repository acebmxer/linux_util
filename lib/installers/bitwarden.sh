#!/bin/bash
# Bitwarden Client installer functions

# --- Bitwarden Client ---

check_bitwarden() {
    command -v bitwarden &>/dev/null || \
        (has_snap && snap list bitwarden &>/dev/null) || \
        (flatpak_is_installed bitwarden) || \
        pkg_check_installed bitwarden-bin || \
        pkg_check_installed bitwarden
}
install_bitwarden() {
    echo "Installing Bitwarden Client..."
    case "$DISTRO_FAMILY" in
        debian)
            ensure_tools
            local tmp_deb
            tmp_deb=$(mktemp /tmp/bitwarden-XXXXXX.deb)
            CLEANUP_FILES+=("$tmp_deb")
            if ! wget -qO "$tmp_deb" "https://vault.bitwarden.com/download/?app=desktop&platform=linux&variant=deb"; then
                echo "Error: Failed to download Bitwarden .deb."
                rm -f "$tmp_deb"
                return 1
            fi
            verify_download "$tmp_deb" "deb" "Bitwarden" || return 1
            # Try installing; if deps are missing, fix them and retry
            if ! sudo dpkg -i "$tmp_deb"; then
                sudo apt-get install -f -y || true
                if ! sudo dpkg -i "$tmp_deb"; then
                    echo "Error: Failed to install Bitwarden .deb."
                    rm -f "$tmp_deb"
                    return 1
                fi
            fi
            rm -f "$tmp_deb"
            ;;
        fedora|rhel)
            ensure_tools
            local tmp_rpm
            tmp_rpm=$(mktemp /tmp/bitwarden-XXXXXX.rpm)
            CLEANUP_FILES+=("$tmp_rpm")
            if ! wget -qO "$tmp_rpm" "https://vault.bitwarden.com/download/?app=desktop&platform=linux&variant=rpm"; then
                echo "Error: Failed to download Bitwarden .rpm."
                rm -f "$tmp_rpm"
                return 1
            fi
            verify_download "$tmp_rpm" "rpm" "Bitwarden" || return 1
            if ! sudo "$PKG_MGR" install -y "$tmp_rpm"; then
                echo "Error: Failed to install Bitwarden .rpm."
                rm -f "$tmp_rpm"
                return 1
            fi
            rm -f "$tmp_rpm"
            ;;
        arch)
            # extra/bitwarden is the official build; bitwarden-bin is the AUR fallback
            sudo pacman -S --noconfirm --needed bitwarden 2>/dev/null || aur_ensure bitwarden-bin
            ;;
        *)
            if has_snap; then
                sudo snap install bitwarden
            elif ensure_flatpak; then
                flatpak install -y flathub com.bitwarden.desktop
            else
                echo "Error: snap or flatpak is required to install Bitwarden."
                return 1
            fi
            ;;
    esac
}
uninstall_bitwarden() {
    echo "Uninstalling Bitwarden Client..."
    if has_snap && snap list bitwarden &>/dev/null; then
        sudo snap remove bitwarden
    elif flatpak_is_installed bitwarden; then
        flatpak uninstall -y com.bitwarden.desktop
    elif pkg_check_installed bitwarden-bin; then
        pkg_remove bitwarden-bin
    elif pkg_check_installed bitwarden; then
        pkg_remove bitwarden
    else
        echo "Bitwarden installation not found."
    fi
    rm -rf ~/.config/Bitwarden
    rm -rf ~/.bitwarden
}
update_bitwarden() {
    echo "Updating Bitwarden Client..."
    if has_snap && snap list bitwarden &>/dev/null; then
        sudo snap refresh bitwarden
    elif flatpak_is_installed bitwarden; then
        flatpak update -y com.bitwarden.desktop
    elif [[ "$DISTRO_FAMILY" == "debian" ]]; then
        install_bitwarden
    elif [[ "$DISTRO_FAMILY" == "fedora" || "$DISTRO_FAMILY" == "rhel" ]]; then
        install_bitwarden
    elif pkg_check_installed bitwarden-bin; then
        if has_aur_helper; then
            aur_upgrade bitwarden-bin
        else
            install_bitwarden
        fi
    elif pkg_check_installed bitwarden; then
        pkg_upgrade bitwarden
    else
        echo "Bitwarden installation not found."
        return 1
    fi
}
get_version_bitwarden() {
    if _ver_from_snap bitwarden; then
        return
    elif flatpak_is_installed bitwarden; then
        _ver_from_flatpak bitwarden
    elif pkg_check_installed bitwarden-bin; then
        pkg_get_version bitwarden-bin | sed 's/^[0-9]*://; s/-.*//'
    elif pkg_check_installed bitwarden; then
        pkg_get_version bitwarden | sed 's/^[0-9]*://; s/-.*//'
    else
        echo ""
    fi
}

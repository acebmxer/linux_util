#!/bin/bash
# Termius SSH Client installer functions

# --- Termius SSH Client ---

check_termius() {
    command -v termius &>/dev/null || \
        command -v termius-app &>/dev/null || \
        pkg_check_installed termius || \
        pkg_check_installed termius-app || \
        (has_snap && snap list termius-app &>/dev/null) || \
        (has_flatpak && flatpak list 2>/dev/null | grep -qi termius)
}
install_termius() {
    echo "Installing Termius SSH Client..."
    case "$DISTRO_FAMILY" in
        debian)
            local tmp_deb
            tmp_deb=$(mktemp /tmp/termius-XXXXXX.deb)
            CLEANUP_FILES+=("$tmp_deb")
            wget -q https://www.termius.com/download/linux/Termius.deb -O "$tmp_deb"
            sudo apt install -y "$tmp_deb"
            rm -f "$tmp_deb"
            ;;
        arch)
            if has_aur_helper; then
                aur_install termius
            else
                aur_build termius
            fi
            ;;
        *)
            if has_snap; then
                sudo snap install termius-app
            elif has_flatpak; then
                # Ensure flathub remote is properly configured
                if ! flatpak remotes | grep -q flathub; then
                    echo "Adding flathub remote..."
                    sudo flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
                fi
                sudo flatpak install -y flathub com.termius.Termius
            else
                echo "Error: snap or flatpak is required to install Termius on ${DISTRO_NAME}."
                return 1
            fi
            ;;
    esac
}
uninstall_termius() {
    echo "Uninstalling Termius SSH Client..."
    if pkg_check_installed termius; then
        pkg_remove termius
    elif pkg_check_installed termius-app; then
        pkg_remove termius-app
    elif has_snap && snap list termius-app &>/dev/null; then
        sudo snap remove termius-app
    elif has_flatpak && flatpak list 2>/dev/null | grep -qi termius; then
        flatpak uninstall -y com.termius.Termius
    else
        echo "Termius installation not found."
        return 1
    fi
}
update_termius() {
    echo "Updating Termius SSH Client..."
    case "$DISTRO_FAMILY" in
        debian)
            local tmp_deb
            tmp_deb=$(mktemp /tmp/termius-XXXXXX.deb)
            CLEANUP_FILES+=("$tmp_deb")
            wget -q https://www.termius.com/download/linux/Termius.deb -O "$tmp_deb"
            sudo apt install -y "$tmp_deb"
            rm -f "$tmp_deb"
            ;;
        arch)
            if has_aur_helper; then
                aur_upgrade termius
            else
                aur_build termius
            fi
            ;;
        *)
            if has_snap && snap list termius-app &>/dev/null; then
                sudo snap refresh termius-app
            elif has_flatpak && flatpak list 2>/dev/null | grep -qi termius; then
                flatpak update -y com.termius.Termius
            else
                echo "Termius installation not found or no supported update method."
                return 1
            fi
            ;;
    esac
}
get_version_termius() {
    if pkg_check_installed termius; then
        pkg_get_version termius | sed 's/^[0-9]*://; s/-.*//'
    elif pkg_check_installed termius-app; then
        pkg_get_version termius-app | sed 's/^[0-9]*://; s/-.*//'
    elif has_snap && snap list termius-app &>/dev/null; then
        snap list termius-app 2>/dev/null | awk 'NR==2{print $2}'
    elif has_flatpak && flatpak list 2>/dev/null | grep -qi termius; then
        flatpak list 2>/dev/null | grep -i termius | awk -F'\t' '{print $3}'
    else
        echo ""
    fi
}

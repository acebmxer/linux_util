#!/bin/bash
# OnlyOffice Desktop Editors installer functions
# Official docs: https://helpcenter.onlyoffice.com/installation/desktop-install-ubuntu.aspx

# --- OnlyOffice Desktop Editors ---

check_onlyoffice() { _check_standard onlyoffice-desktopeditors onlyoffice-desktopeditors org.onlyoffice.desktopeditors; }

install_onlyoffice() {
    info "Installing OnlyOffice Desktop Editors..."
    ensure_tools
    case "$DISTRO_FAMILY" in
        debian)
            sudo gpg --no-default-keyring \
                --keyring gnupg-ring:/usr/share/keyrings/onlyoffice.gpg \
                --keyserver hkp://keyserver.ubuntu.com:80 \
                --recv-keys CB2DE8E5
            sudo chmod 644 /usr/share/keyrings/onlyoffice.gpg
            echo "deb [signed-by=/usr/share/keyrings/onlyoffice.gpg] https://download.onlyoffice.com/repo/debian squeeze main" | \
                sudo tee /etc/apt/sources.list.d/onlyoffice.list > /dev/null
            sudo apt update
            sudo apt install -y onlyoffice-desktopeditors
            ;;
        fedora|rhel)
            if has_flatpak; then
                flatpak install -y flathub org.onlyoffice.desktopeditors
            else
                echo "Error: No supported installation method for this distribution. Install flatpak and retry."
                return 1
            fi
            ;;
        arch)
            flatpak_or_aur org.onlyoffice.desktopeditors onlyoffice-bin
            ;;
        suse)
            if has_flatpak; then
                flatpak install -y flathub org.onlyoffice.desktopeditors
            else
                echo "Error: No supported installation method for this distribution. Install flatpak and retry."
                return 1
            fi
            ;;
        *)
            if has_flatpak; then
                flatpak install -y flathub org.onlyoffice.desktopeditors
            else
                echo "Error: Unsupported distribution and flatpak is not available."
                return 1
            fi
            ;;
    esac
}

uninstall_onlyoffice() {
    info "Uninstalling OnlyOffice Desktop Editors..."
    case "$DISTRO_FAMILY" in
        debian)
            sudo apt purge --autoremove -y onlyoffice-desktopeditors
            sudo apt autoclean
            sudo rm -f /etc/apt/sources.list.d/onlyoffice.list
            sudo rm -f /usr/share/keyrings/onlyoffice.gpg
            ;;
        fedora|rhel)
            if flatpak_is_installed "org.onlyoffice.desktopeditors"; then
                flatpak uninstall -y org.onlyoffice.desktopeditors
            else
                sudo "$PKG_MGR" remove -y onlyoffice-desktopeditors 2>/dev/null || true
            fi
            ;;
        arch)
            if flatpak_is_installed "org.onlyoffice.desktopeditors"; then
                flatpak uninstall -y org.onlyoffice.desktopeditors
            else
                aur_remove onlyoffice-bin 2>/dev/null || pkg_remove onlyoffice-desktopeditors 2>/dev/null || true
            fi
            ;;
        suse)
            if flatpak_is_installed "org.onlyoffice.desktopeditors"; then
                flatpak uninstall -y org.onlyoffice.desktopeditors
            else
                sudo zypper remove -y onlyoffice-desktopeditors 2>/dev/null || true
            fi
            ;;
        *)
            if flatpak_is_installed "org.onlyoffice.desktopeditors"; then
                flatpak uninstall -y org.onlyoffice.desktopeditors
            fi
            ;;
    esac
    rm -rf ~/.local/share/onlyoffice
    rm -rf ~/.config/onlyoffice
    echo "OnlyOffice Desktop Editors has been uninstalled."
}

update_onlyoffice() {
    info "Updating OnlyOffice Desktop Editors..."
    case "$DISTRO_FAMILY" in
        debian)
            sudo apt update
            sudo apt install -y --only-upgrade onlyoffice-desktopeditors
            ;;
        arch)
            if flatpak_is_installed "org.onlyoffice.desktopeditors"; then
                flatpak update -y org.onlyoffice.desktopeditors
            else
                repo_or_aur onlyoffice-bin
            fi
            ;;
        *)
            if flatpak_is_installed "org.onlyoffice.desktopeditors"; then
                flatpak update -y org.onlyoffice.desktopeditors
            else
                pkg_upgrade onlyoffice-desktopeditors
            fi
            ;;
    esac
}

get_version_onlyoffice() {
    if pkg_check_installed onlyoffice-desktopeditors; then
        dpkg -l onlyoffice-desktopeditors 2>/dev/null | \
            awk '/^ii/ { print $3 }' | grep -oP '^[0-9]+\.[0-9]+\.[0-9]+' | head -1
        return
    fi
    if flatpak_is_installed "org.onlyoffice.desktopeditors"; then
        flatpak list --app 2>/dev/null | grep -i "onlyoffice" | \
            grep -oP '\t[0-9]+\.[0-9]+\.[0-9]+' | tr -d '\t' | head -1
        return
    fi
    echo ""
}

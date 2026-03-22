#!/bin/bash
# Visual Studio Code installer functions

# --- Visual Studio Code ---

check_vscode() {
    command -v code &>/dev/null || pkg_check_installed code
}
install_vscode() {
    echo "Installing Visual Studio Code..."
    ensure_tools
    case "$DISTRO_FAMILY" in
        debian)
            wget -qO- https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor > /tmp/packages.microsoft.gpg
            sudo install -D -o root -g root -m 644 /tmp/packages.microsoft.gpg /etc/apt/keyrings/packages.microsoft.gpg
            echo "deb [arch=amd64,arm64,armhf signed-by=/etc/apt/keyrings/packages.microsoft.gpg] https://packages.microsoft.com/repos/code stable main" | \
                sudo tee /etc/apt/sources.list.d/vscode.list > /dev/null
            rm -f /tmp/packages.microsoft.gpg
            sudo apt update
            sudo apt install -y code
            ;;
        fedora|rhel)
            sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc
            printf "[code]\nname=Visual Studio Code\nbaseurl=https://packages.microsoft.com/yumrepos/vscode\nenabled=1\ngpgcheck=1\ngpgkey=https://packages.microsoft.com/keys/microsoft.asc\n" | \
                sudo tee /etc/yum.repos.d/vscode.repo > /dev/null
            sudo "$PKG_MGR" install -y code
            ;;
        arch)
            if has_aur_helper; then
                aur_install visual-studio-code-bin
            else
                aur_build visual-studio-code-bin
            fi
            ;;
        suse)
            sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc
            printf "[code]\nname=Visual Studio Code\nbaseurl=https://packages.microsoft.com/yumrepos/vscode\nenabled=1\ntype=rpm-md\ngpgcheck=1\ngpgkey=https://packages.microsoft.com/keys/microsoft.asc\n" | \
                sudo tee /etc/zypp/repos.d/vscode.repo > /dev/null
            sudo zypper refresh
            sudo zypper install -y code
            ;;
    esac
}
uninstall_vscode() {
    echo "Uninstalling Visual Studio Code..."
    case "$DISTRO_FAMILY" in
        debian)
            sudo apt remove -y code
            sudo rm -f /etc/apt/sources.list.d/vscode.list
            sudo rm -f /etc/apt/keyrings/packages.microsoft.gpg
            ;;
        fedora|rhel)
            sudo "$PKG_MGR" remove -y code
            sudo rm -f /etc/yum.repos.d/vscode.repo
            ;;
        arch)
            aur_remove visual-studio-code-bin 2>/dev/null || pkg_remove code 2>/dev/null || true
            ;;
        suse)
            sudo zypper remove -y code
            sudo rm -f /etc/zypp/repos.d/vscode.repo
            ;;
    esac
}
update_vscode() {
    echo "Updating Visual Studio Code..."
    case "$DISTRO_FAMILY" in
        debian)
            sudo apt update
            sudo apt upgrade -y code
            ;;
        arch)
            if has_aur_helper; then
                aur_upgrade visual-studio-code-bin
            else
                aur_build visual-studio-code-bin
            fi
            ;;
        *)
            pkg_upgrade code
            ;;
    esac
}
get_version_vscode() {
    code --version 2>/dev/null | head -1 || echo ""
}

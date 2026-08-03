#!/bin/bash
# Visual Studio Code installer functions

# --- Visual Studio Code ---

check_vscode() { _check_standard code code ""; }
install_vscode() {
    echo "Installing Visual Studio Code..."
    ensure_tools
    case "$DISTRO_FAMILY" in
        debian)
            local gpg_tmp
            gpg_tmp=$(mktemp /tmp/vscode-gpg-XXXXXX)
            CLEANUP_FILES+=("$gpg_tmp")
            wget -qO- https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor > "$gpg_tmp"
            sudo install -D -o root -g root -m 644 "$gpg_tmp" /etc/apt/keyrings/packages.microsoft.gpg
            echo "deb [arch=amd64,arm64,armhf signed-by=/etc/apt/keyrings/packages.microsoft.gpg] https://packages.microsoft.com/repos/code stable main" | \
                sudo tee /etc/apt/sources.list.d/vscode.list > /dev/null
            rm -f "$gpg_tmp"
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
            aur_ensure visual-studio-code-bin
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
            sudo apt purge --autoremove -y code
            sudo apt autoclean
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
    rm -rf ~/.config/Code
    rm -rf ~/.vscode
}
update_vscode() {
    echo "Updating Visual Studio Code..."
    case "$DISTRO_FAMILY" in
        debian)
            sudo apt update
            sudo apt install -y --only-upgrade code
            ;;
        arch)
            aur_ensure visual-studio-code-bin
            ;;
        *)
            pkg_upgrade code
            ;;
    esac
}
get_version_vscode() {
    _run_native code --version 2>/dev/null | head -1 || echo ""
}

#!/bin/bash
# Brave Browser installer functions

# --- Brave Browser ---

check_brave() {
    command -v brave-browser &>/dev/null || pkg_check_installed brave-browser
}
install_brave() {
    echo "Installing Brave Browser..."
    ensure_tools
    case "$DISTRO_FAMILY" in
        debian)
            sudo curl -fsSLo /usr/share/keyrings/brave-browser-archive-keyring.gpg \
                https://brave-browser-apt-release.s3.brave.com/brave-browser-archive-keyring.gpg
            echo "deb [signed-by=/usr/share/keyrings/brave-browser-archive-keyring.gpg] https://brave-browser-apt-release.s3.brave.com/ stable main" | \
                sudo tee /etc/apt/sources.list.d/brave-browser-release.list > /dev/null
            sudo apt update
            sudo apt install -y brave-browser
            ;;
        fedora|rhel)
            sudo "$PKG_MGR" install -y dnf-plugins-core 2>/dev/null || true
            sudo curl -fsSLo /etc/yum.repos.d/brave-browser.repo https://brave-browser-rpm-release.s3.brave.com/brave-browser.repo
            sudo rpm --import https://brave-browser-rpm-release.s3.brave.com/brave-core.asc
            sudo "$PKG_MGR" install -y brave-browser
            ;;
        arch)
            if has_aur_helper; then
                aur_install brave-bin
            else
                aur_build brave-bin
            fi
            ;;
        suse)
            sudo rpm --import https://brave-browser-rpm-release.s3.brave.com/brave-core.asc
            sudo zypper addrepo -f https://brave-browser-rpm-release.s3.brave.com/brave-browser.repo brave-browser 2>/dev/null || true
            sudo zypper refresh
            sudo zypper install -y brave-browser
            ;;
    esac
}
uninstall_brave() {
    echo "Uninstalling Brave Browser..."
    case "$DISTRO_FAMILY" in
        debian)
            sudo apt purge --autoremove -y brave-browser
            sudo apt autoclean
            sudo rm -f /etc/apt/sources.list.d/brave-browser-release.list
            sudo rm -f /usr/share/keyrings/brave-browser-archive-keyring.gpg
            ;;
        fedora|rhel)
            sudo "$PKG_MGR" remove -y brave-browser
            sudo rm -f /etc/yum.repos.d/brave-browser.repo
            ;;
        arch)
            aur_remove brave-bin 2>/dev/null || pkg_remove brave-browser 2>/dev/null || true
            ;;
        suse)
            sudo zypper remove -y brave-browser
            sudo zypper removerepo brave-browser 2>/dev/null || true
            ;;
    esac
    rm -rf ~/.config/BraveSoftware
    rm -rf ~/.brave
}
update_brave() {
    echo "Updating Brave Browser..."
    case "$DISTRO_FAMILY" in
        debian)
            sudo apt update
            sudo apt upgrade -y brave-browser
            ;;
        arch)
            if has_aur_helper; then
                aur_upgrade brave-bin
            else
                aur_build brave-bin
            fi
            ;;
        *)
            pkg_upgrade brave-browser
            ;;
    esac
}
get_version_brave() {
    local cmd
    for cmd in brave-browser brave; do
        local out
        out=$("$cmd" --version 2>/dev/null) && \
            grep -oP 'Brave Browser \K[0-9]+\.[0-9]+\.[0-9]+' <<< "$out" && return
    done
    echo ""
}

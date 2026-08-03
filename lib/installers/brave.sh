#!/bin/bash
# Brave Browser installer functions

# --- Brave Browser ---

check_brave() { _check_standard brave-browser brave-browser ""; }
install_brave() {
    info "Installing Brave Browser..."
    ensure_tools
    case "$DISTRO_FAMILY" in
        debian)
            _add_apt_repo \
                "https://brave-browser-apt-release.s3.brave.com/brave-browser-archive-keyring.gpg" \
                "/usr/share/keyrings/brave-browser-archive-keyring.gpg" \
                "deb [signed-by=/usr/share/keyrings/brave-browser-archive-keyring.gpg] https://brave-browser-apt-release.s3.brave.com/ stable main" \
                "/etc/apt/sources.list.d/brave-browser-release.list"
            sudo apt install -y brave-browser
            ;;
        fedora|rhel)
            sudo "$PKG_MGR" install -y dnf-plugins-core 2>/dev/null || true
            sudo curl -fsSLo /etc/yum.repos.d/brave-browser.repo https://brave-browser-rpm-release.s3.brave.com/brave-browser.repo
            sudo rpm --import https://brave-browser-rpm-release.s3.brave.com/brave-core.asc
            sudo "$PKG_MGR" install -y brave-browser
            ;;
        arch)
            aur_ensure brave-bin
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
    info "Uninstalling Brave Browser..."
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
    info "Updating Brave Browser..."
    case "$DISTRO_FAMILY" in
        debian)
            sudo apt update
            sudo apt install -y --only-upgrade brave-browser
            ;;
        arch)
            aur_ensure brave-bin
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
        out=$(_run_native "$cmd" --version 2>/dev/null) && \
            grep -oP 'Brave Browser \K[0-9]+\.[0-9]+\.[0-9]+' <<< "$out" && return
    done
    echo ""
}

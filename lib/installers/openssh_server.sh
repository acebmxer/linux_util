#!/bin/bash
# OpenSSH Server installer functions

# --- OpenSSH Server ---
check_openssh_server() {
    pkg_check_installed openssh-server || \
        systemctl is-active --quiet ssh 2>/dev/null || \
        systemctl is-active --quiet sshd 2>/dev/null
}

install_openssh_server() {
    echo "Installing OpenSSH Server..."
    case "$DISTRO_FAMILY" in
        debian)
            sudo apt install openssh-server -y
            sudo systemctl enable ssh
            sudo systemctl start ssh
            ;;
        fedora|rhel)
            sudo "$PKG_MGR" install -y openssh-server
            sudo systemctl enable sshd
            sudo systemctl start sshd
            ;;
        arch)
            sudo pacman -S --noconfirm openssh
            sudo systemctl enable sshd
            sudo systemctl start sshd
            ;;
        suse)
            sudo zypper install -y openssh
            sudo systemctl enable sshd
            sudo systemctl start sshd
            ;;
    esac
    echo "OpenSSH Server installed and started."
}

uninstall_openssh_server() {
    echo "Uninstalling OpenSSH Server..."
    sudo systemctl stop ssh 2>/dev/null || sudo systemctl stop sshd 2>/dev/null || true
    sudo systemctl disable ssh 2>/dev/null || sudo systemctl disable sshd 2>/dev/null || true
    case "$DISTRO_FAMILY" in
        debian)
            sudo apt purge --autoremove -y openssh-server
            sudo apt autoclean
            ;;
        fedora|rhel)
            sudo "$PKG_MGR" remove -y openssh-server
            ;;
        arch)
            sudo pacman -Rs --noconfirm openssh
            ;;
        suse)
            sudo zypper remove -y openssh
            ;;
    esac
    echo "OpenSSH Server has been uninstalled."
}

update_openssh_server() {
    echo "Updating OpenSSH Server..."
    case "$DISTRO_FAMILY" in
        debian)
            sudo apt update
            sudo apt install -y --only-upgrade openssh-server
            ;;
        fedora|rhel)
            sudo "$PKG_MGR" upgrade -y openssh-server
            ;;
        arch)
            sudo pacman -S --noconfirm openssh
            ;;
        suse)
            sudo zypper update -y openssh
            ;;
    esac
}
get_version_openssh_server() {
    _run_native ssh -V 2>&1 | grep -oP 'OpenSSH_\K[^\s,]+' || echo ""
}

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
            pkg_install openssh-server
            sudo systemctl enable ssh
            sudo systemctl start ssh
            ;;
        fedora|rhel)
            pkg_install openssh-server
            sudo systemctl enable sshd
            sudo systemctl start sshd
            ;;
        arch)
            pkg_install openssh
            sudo systemctl enable sshd
            sudo systemctl start sshd
            ;;
        suse)
            pkg_install openssh
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
            pkg_remove openssh-server
            ;;
        fedora|rhel)
            pkg_remove openssh-server
            ;;
        arch)
            pkg_remove openssh
            ;;
        suse)
            pkg_remove openssh
            ;;
    esac
    echo "OpenSSH Server has been uninstalled."
}

update_openssh_server() {
    echo "Updating OpenSSH Server..."
    case "$DISTRO_FAMILY" in
        debian)
            sudo apt update
            pkg_upgrade openssh-server
            ;;
        fedora|rhel)
            pkg_upgrade openssh-server
            ;;
        arch)
            pkg_upgrade openssh
            ;;
        suse)
            pkg_upgrade openssh
            ;;
    esac
}
get_version_openssh_server() {
    _run_native ssh -V 2>&1 | grep -oP 'OpenSSH_\K[^\s,]+' || echo ""
}

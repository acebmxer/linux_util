#!/bin/bash
# fail2ban installer functions

install_fail2ban() {
    info "Installing fail2ban..."
    sudo apt install -y fail2ban
    sudo systemctl enable --now fail2ban
    info "fail2ban installed and enabled."
}

check_fail2ban() {
    command -v fail2ban-client &>/dev/null
}

uninstall_fail2ban() {
    info "Removing fail2ban..."
    sudo systemctl disable --now fail2ban 2>/dev/null || true
    sudo apt purge --autoremove -y fail2ban
}

update_fail2ban() {
    info "Updating fail2ban..."
    sudo apt-get install -y --only-upgrade fail2ban
}

get_version_fail2ban() {
    fail2ban-client --version 2>/dev/null | grep -oP '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo ""
}

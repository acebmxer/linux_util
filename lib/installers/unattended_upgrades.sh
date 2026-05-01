#!/bin/bash
# Unattended Upgrades configuration functions

install_unattended_upgrades() {
    info "Configuring unattended-upgrades..."
    sudo dpkg-reconfigure -plow unattended-upgrades
    info "Unattended upgrades configuration complete."
}

check_unattended_upgrades() {
    dpkg -l unattended-upgrades 2>/dev/null | grep -q '^ii'
}

uninstall_unattended_upgrades() {
    info "Removing unattended-upgrades..."
    sudo apt purge --autoremove -y unattended-upgrades
}

update_unattended_upgrades() {
    info "Updating unattended-upgrades..."
    sudo apt-get install -y --only-upgrade unattended-upgrades
}

get_version_unattended_upgrades() {
    dpkg-query -W -f='${Version}' unattended-upgrades 2>/dev/null | grep -oP '[0-9]+\.[0-9.]+' | head -1 || echo ""
}

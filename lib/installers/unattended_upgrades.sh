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

# Open the unattended-upgrades config file in an editor so the user can choose
# which update origins auto-install, blacklist packages, and set auto-reboot /
# notification behavior. Action-style task: registered only when the package
# (and thus this file) is installed. Uses $EDITOR, falling back to nano, and
# reconnects to the terminal so it works when launched from the menu.
configure_unattended_upgrades() {
    local conf="/etc/apt/apt.conf.d/50unattended-upgrades"
    if [[ ! -f "$conf" ]]; then
        warn "Config file not found: ${conf}"
        warn "Install the unattended-upgrades package first."
        return 1
    fi
    info "Opening ${conf} in ${EDITOR:-nano} (edited as root via sudo)..."
    sudo "${EDITOR:-nano}" "$conf" < /dev/tty > /dev/tty 2>&1
    info "Finished editing ${conf}."
}

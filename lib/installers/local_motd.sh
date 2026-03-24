#!/bin/bash
# Local MOTD (Landscape Client) installer functions

get_version_landscape_motd() {
    pkg_get_version landscape-client | grep -oE '^[0-9]+\.[0-9]+\.[0-9]+' || echo ""
}

check_landscape_motd() {
    pkg_check_installed landscape-client
}

setup_local_motd() {
    info "Installing/Updating Landscape Client and configuring Local MOTD..."

    run_as_root "add-apt-repository -y ppa:landscape/self-hosted-beta 2>/dev/null || true"
    run_as_root "apt-get update && apt-get install -y --no-install-recommends landscape-client" || {
        warn "Failed to install landscape-client"
        return 1
    }

    local motd_code='# BEGIN linux_util MOTD display
if [ -f /etc/update-motd.d/00-header ]; then
    /etc/update-motd.d/00-header
fi
if [ -f /etc/update-motd.d/10-help-text ]; then
    /etc/update-motd.d/10-help-text
fi
if [ -f /etc/update-motd.d/50-motd-news ]; then
    /etc/update-motd.d/50-motd-news
fi
if [ -f /etc/update-motd.d/85-fwupd ]; then
    /etc/update-motd.d/85-fwupd
fi
if [ -f /etc/update-motd.d/90-updates-available ]; then
    /etc/update-motd.d/90-updates-available
fi
if [ -f /etc/update-motd.d/91-contract-ua-esm-status ]; then
    /etc/update-motd.d/91-contract-ua-esm-status
fi
if [ -f /etc/update-motd.d/91-release-upgrade ]; then
    /etc/update-motd.d/91-release-upgrade
fi
if [ -f /etc/update-motd.d/95-hwe-eol ]; then
    /etc/update-motd.d/95-hwe-eol
fi
if [ -f /etc/update-motd.d/98-fsck-at-reboot ]; then
    /etc/update-motd.d/98-fsck-at-reboot
fi
if [ -f /etc/update-motd.d/98-reboot-required ]; then
    /etc/update-motd.d/98-reboot-required
fi
# END linux_util MOTD display'

    if [[ -f "${HOME}/.bashrc" ]]; then
        # Remove legacy MOTD block (pre-v2 marker) if present
        sed -i '/^# Display MOTD for ZSH$/,/^fi$/d' "${HOME}/.bashrc"
        if ! grep -q "BEGIN linux_util MOTD display" "${HOME}/.bashrc"; then
            echo "" >> "${HOME}/.bashrc"
            echo "$motd_code" >> "${HOME}/.bashrc"
            info "Added MOTD display code to ~/.bashrc"
        else
            info "MOTD code already present in ~/.bashrc"
        fi
    fi

    if [[ -f "${HOME}/.zshrc" ]]; then
        # Remove legacy MOTD block (pre-v2 marker) if present
        sed -i '/^# Display MOTD for ZSH$/,/^fi$/d' "${HOME}/.zshrc"
        if ! grep -q "BEGIN linux_util MOTD display" "${HOME}/.zshrc"; then
            echo "" >> "${HOME}/.zshrc"
            echo "$motd_code" >> "${HOME}/.zshrc"
            info "Added MOTD display code to ~/.zshrc"
        else
            info "MOTD code already present in ~/.zshrc"
        fi
    fi

    info "Local MOTD configuration complete."
}

uninstall_landscape_motd() {
    info "Uninstalling Landscape Client and removing MOTD configuration..."
    run_as_root "apt-get purge --autoremove -y landscape-client" || warn "Failed to uninstall landscape-client"
    run_as_root "apt-get autoclean"

    if [[ -f "${HOME}/.bashrc" ]]; then
        # Remove current markers
        sed -i '/^# BEGIN linux_util MOTD display$/,/^# END linux_util MOTD display$/d' "${HOME}/.bashrc"
        # Remove legacy markers (pre-v2)
        sed -i '/^# Display MOTD for ZSH$/,/^fi$/d' "${HOME}/.bashrc"
        info "Removed MOTD code from ~/.bashrc"
    fi

    if [[ -f "${HOME}/.zshrc" ]]; then
        # Remove current markers
        sed -i '/^# BEGIN linux_util MOTD display$/,/^# END linux_util MOTD display$/d' "${HOME}/.zshrc"
        # Remove legacy markers (pre-v2)
        sed -i '/^# Display MOTD for ZSH$/,/^fi$/d' "${HOME}/.zshrc"
        info "Removed MOTD code from ~/.zshrc"
    fi

    rm -rf ~/.config/landscape
    rm -rf ~/.landscape
    info "Local MOTD configuration removed."
}

update_landscape_motd() {
    info "Updating Landscape Client..."
    run_as_root "apt-get update && apt-get upgrade -y landscape-client" || warn "Failed to update landscape-client"
    info "Landscape Client updated."
}

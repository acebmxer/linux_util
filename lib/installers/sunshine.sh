#!/bin/bash
# Sunshine installer functions
#
# Self-hosted game-streaming server for Moonlight clients. No distro packages
# it, and its own release packages are built per distro release, so every
# family uses Sunshine's Flathub listing. Sunshine's Flatpak needs one extra
# step, which its own page documents: additional-install.sh installs the user
# service and, through polkit, the uinput/uhid rules that let it create virtual
# keyboards and gamepads. That step needs a graphical session (the polkit
# prompt), so without one the command is printed instead. Not offered on Alpine.

# --- Sunshine ---

_SUNSHINE_FLATPAK="dev.lizardbyte.app.Sunshine"
_SUNSHINE_UDEV="/etc/udev/rules.d/60-sunshine.rules"
_SUNSHINE_MODULES="/etc/modules-load.d/60-sunshine.conf"
_SUNSHINE_SERVICE="$HOME/.config/systemd/user/app-dev.lizardbyte.app.Sunshine.service"

check_sunshine() { _check_standard "" "" "$_SUNSHINE_FLATPAK"; }

install_sunshine() {
    info "Installing Sunshine..."
    flatpak_install_flathub "$_SUNSHINE_FLATPAK" || return 1
    local cmd="flatpak run --command=additional-install.sh ${_SUNSHINE_FLATPAK}"
    if [[ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]] && command -v pkexec &>/dev/null; then
        info "Setting up Sunshine's virtual input rules (a password prompt appears)..."
        $cmd || warn "Sunshine's input setup did not finish. Run it again with: ${cmd}"
    else
        warn "Sunshine needs one more step, from a desktop session: ${cmd}"
    fi
    info "Sunshine installed. Its web page is https://localhost:47990 (the certificate is self-signed)."
}

# Removes what Sunshine's setup step wrote, then the app. Its settings and
# pairings in ~/.var/app/${_SUNSHINE_FLATPAK} are kept.
uninstall_sunshine() {
    info "Uninstalling Sunshine..."
    systemctl --user disable --now app-dev.lizardbyte.app.Sunshine 2>/dev/null || true
    rm -f "$_SUNSHINE_SERVICE"
    if [[ -e "$_SUNSHINE_UDEV" || -e "$_SUNSHINE_MODULES" ]]; then
        sudo rm -f "$_SUNSHINE_UDEV" "$_SUNSHINE_MODULES"
        sudo udevadm control --reload-rules 2>/dev/null || true
    fi
    flatpak uninstall -y --user "$_SUNSHINE_FLATPAK" 2>/dev/null || \
        sudo flatpak uninstall -y --system "$_SUNSHINE_FLATPAK"
}

update_sunshine() {
    info "Updating Sunshine..."
    flatpak update -y --user "$_SUNSHINE_FLATPAK" 2>/dev/null || \
        sudo flatpak update -y --system "$_SUNSHINE_FLATPAK"
}

get_version_sunshine() { _ver_from_flatpak "$_SUNSHINE_FLATPAK" || echo ""; }

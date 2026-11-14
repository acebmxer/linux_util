#!/bin/bash
# WhatsApp installer functions
#
# WhatsApp publishes no desktop app for Linux. This installs ZapZap, an open
# source (GPL-3.0) desktop client that wraps WhatsApp Web: the distro package on
# openSUSE, Flathub (com.rtosta.zapzap) everywhere else. Not offered on Alpine.

# --- WhatsApp (ZapZap) ---

check_whatsapp() { _check_standard "" zapzap com.rtosta.zapzap; }

install_whatsapp() {
    info "Installing WhatsApp (ZapZap)..."
    native_or_flatpak_install com.rtosta.zapzap zapzap || return 1
    info "WhatsApp (ZapZap) installed."
}

# The linked WhatsApp session and settings are kept.
uninstall_whatsapp() {
    info "Uninstalling WhatsApp (ZapZap)..."
    native_or_flatpak_uninstall com.rtosta.zapzap zapzap
}

update_whatsapp() {
    info "Updating WhatsApp (ZapZap)..."
    native_or_flatpak_update com.rtosta.zapzap zapzap
}

get_version_whatsapp() { native_or_flatpak_version com.rtosta.zapzap zapzap; }

#!/bin/bash
# Xournal++ handwritten notes installer functions
# Distro package where the repositories have one, otherwise Flathub
# (native_or_flatpak_* in _shared.sh).

# --- Xournal++ ---

check_xournalpp() { _check_standard xournalpp xournalpp com.github.xournalpp.xournalpp; }

install_xournalpp() {
    info "Installing Xournal++..."
    native_or_flatpak_install com.github.xournalpp.xournalpp xournalpp || return 1
    info "Xournal++ installed."
}

uninstall_xournalpp() {
    info "Uninstalling Xournal++..."
    native_or_flatpak_uninstall com.github.xournalpp.xournalpp xournalpp
}

update_xournalpp() {
    info "Updating Xournal++..."
    native_or_flatpak_update com.github.xournalpp.xournalpp xournalpp
}

get_version_xournalpp() { native_or_flatpak_version com.github.xournalpp.xournalpp xournalpp; }

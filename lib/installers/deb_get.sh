#!/bin/bash
# deb-get installer functions
#
# deb-get provides apt-get-like management of .deb packages published in
# third-party repositories or as direct downloads. Debian/Ubuntu family only.
# Project: https://github.com/wimpysworld/deb-get

# --- deb-get ---

check_deb_get() { _check_standard deb-get deb-get ""; }

install_deb_get() {
    info "Installing deb-get..."
    if [[ "$DISTRO_FAMILY" != "debian" ]]; then
        error "deb-get is only supported on Debian/Ubuntu-family distributions."
        return 1
    fi
    ensure_tools
    # deb-get's own installer needs lsb-release and a few base tools.
    sudo apt-get install -y curl lsb-release wget 2>/dev/null || true

    # The upstream installer downloads deb-get and installs it as a .deb,
    # so it ends up tracked by dpkg/apt like any other package.
    if ! curl -fsSL "https://raw.githubusercontent.com/wimpysworld/deb-get/main/deb-get" \
            | sudo -E bash -s install deb-get; then
        error "deb-get installation failed."
        return 1
    fi
    info "deb-get installed. Try: deb-get list   |   deb-get install <app>"
}

uninstall_deb_get() {
    info "Uninstalling deb-get..."
    # deb-get can cleanly remove itself; fall back to apt if that fails.
    sudo deb-get uninstall deb-get 2>/dev/null \
        || sudo apt purge --autoremove -y deb-get 2>/dev/null \
        || true
    warn "Apps installed via deb-get were not removed. Remove them first with 'deb-get remove <app>' if needed."
}

update_deb_get() {
    info "Updating deb-get..."
    # 'deb-get update' refreshes its cache; the tool upgrades itself via apt.
    sudo deb-get update 2>/dev/null || true
    sudo apt-get install -y --only-upgrade deb-get 2>/dev/null || install_deb_get
}

get_version_deb_get() {
    _ver_from_cmd deb-get version || _ver_from_pkg deb-get || echo ""
}

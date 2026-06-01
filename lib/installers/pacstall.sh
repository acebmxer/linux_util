#!/bin/bash
# Pacstall installer functions
#
# Pacstall is "the AUR for Ubuntu/Debian": packages are defined by pacscripts
# (analogous to Arch PKGBUILDs) that build or fetch upstream software not
# available in the official apt repositories. Debian/Ubuntu family only.
# Project: https://github.com/pacstall/pacstall

# --- Pacstall ---

check_pacstall() { _check_standard pacstall "" ""; }

install_pacstall() {
    info "Installing Pacstall..."
    if [[ "$DISTRO_FAMILY" != "debian" ]]; then
        error "Pacstall is only supported on Debian/Ubuntu-family distributions."
        return 1
    fi
    ensure_tools
    # Official one-line installer (curl with wget fallback, per upstream docs).
    if ! sudo bash -c "$(curl -fsSL https://pacstall.dev/q/install || wget -q https://pacstall.dev/q/install -O -)"; then
        error "Pacstall installation failed."
        return 1
    fi
    info "Pacstall installed. Try: pacstall -S <package>   |   pacstall -U  (refresh)"
}

uninstall_pacstall() {
    info "Uninstalling Pacstall..."
    warn "Packages installed via Pacstall were not removed. Remove them first with 'pacstall -R <pkg>' if needed."
    # Official uninstall script; fall back to manual file removal.
    if ! sudo bash -c "$(curl -fsSL https://pacstall.dev/q/uninstall || wget -q https://pacstall.dev/q/uninstall -O -)" 2>/dev/null; then
        sudo rm -f /bin/pacstall /usr/bin/pacstall 2>/dev/null || true
        sudo rm -rf /usr/share/pacstall /var/cache/pacstall /var/log/pacstall 2>/dev/null || true
    fi
}

update_pacstall() {
    info "Updating Pacstall..."
    # 'pacstall -U' (no args) updates Pacstall itself and its repo metadata.
    pacstall -U 2>/dev/null || install_pacstall
}

get_version_pacstall() {
    _ver_from_cmd pacstall --version || echo ""
}

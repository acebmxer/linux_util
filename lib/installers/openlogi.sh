#!/bin/bash
# OpenLogi installer functions
# Local-first alternative to Logitech Options+ — button remapping, DPI,
# SmartShift, and Logitech webcam controls over HID++/UVC.
# https://github.com/AprilNEA/OpenLogi

# --- OpenLogi ---

_OPENLOGI_API_LATEST="https://api.github.com/repos/AprilNEA/OpenLogi/releases/latest"

check_openlogi() { _check_standard openlogi openlogi ""; }

# Print the download URL of the latest release asset for $1 (deb|rpm|pkg.tar.zst).
#
# Upstream publishes only numbered releases with a full Linux asset set, so the
# /releases/latest endpoint is safe to use directly. The pattern is anchored on
# the extension: every asset has a .minisig sibling that would otherwise match.
_openlogi_asset_url() {
    local ext="$1" arch
    case "$(uname -m)" in
        x86_64)        arch="amd64" ;;
        aarch64|arm64) arch="arm64" ;;
        *)
            error "Unsupported architecture for OpenLogi: $(uname -m)"
            return 1
            ;;
    esac

    # A no-match is reported by the caller as "no asset", distinct from the
    # unsupported-architecture failure above, so grep's status is dropped here.
    curl -fsSL "$_OPENLOGI_API_LATEST" \
        | grep -oP '"browser_download_url"\s*:\s*"\K[^"]+' \
        | grep -m1 -E "linux-${arch}\.${ext//./\\.}$" || true
}

# Install upstream's own package for this distro family ($1 = deb|rpm|pkg.tar.zst).
# OpenLogi is in no distro's repositories; the packages carry the CLI, the GUI,
# the agent, and the udev rules that grant device access without root.
_openlogi_install_pkg() {
    local ext="$1" url tmpfile
    url=$(_openlogi_asset_url "$ext") || return 1
    if [[ -z "$url" ]]; then
        error "Could not find an OpenLogi .${ext} release asset."
        return 1
    fi

    tmpfile=$(mktemp "/tmp/openlogi-XXXXXX.${ext}")
    CLEANUP_FILES+=("$tmpfile")
    info "Downloading OpenLogi from: $url"
    wget -qO "$tmpfile" "$url" || { error "Failed to download OpenLogi .${ext}."; return 1; }
    verify_download "$tmpfile" "$ext" "OpenLogi" || return 1
    github_verify_checksum "$_OPENLOGI_API_LATEST" "$(basename "$url")" "$tmpfile" || return 1
    pkg_install_local "$tmpfile"
}

# The packages ship openlogi-agent.service as a *user* unit and deliberately
# leave it disabled — it has to be enabled per user, not system-wide. Without
# it the GUI opens but no device is ever driven, so enable it here.
#
# There is nothing to enable when no systemd user manager is reachable (a
# container, an SSH session with no lingering user instance, a non-systemd
# init), so print the command instead of failing the install over it.
_openlogi_enable_agent() {
    if ! systemctl --user show-environment &>/dev/null; then
        warn "No systemd user session detected — enable the agent after logging in:"
        warn "  systemctl --user enable --now openlogi-agent.service"
        return 0
    fi
    systemctl --user enable --now openlogi-agent.service \
        || warn "Failed to enable openlogi-agent.service; start it manually with 'systemctl --user enable --now openlogi-agent.service'."
}

# Only one program can own a Logitech receiver's HID++ channel at a time, so a
# running Solaar or Logi Options+ leaves OpenLogi seeing devices it cannot talk to.
_openlogi_warn_conflicts() {
    local proc
    for proc in solaar logioptionsplus_updater; do
        if pgrep -x "$proc" &>/dev/null; then
            warn "${proc} is running — quit it before using OpenLogi; the two fight over HID++ access."
        fi
    done
}

install_openlogi() {
    info "Installing OpenLogi..."
    ensure_tools

    case "$DISTRO_FAMILY" in
        debian)
            _openlogi_install_pkg deb || return 1
            ;;
        fedora|rhel|suse)
            # Unsigned upstream RPM — pkg_install_local hands zypper the
            # --allow-unsigned-rpm it needs.
            _openlogi_install_pkg rpm || return 1
            ;;
        arch)
            # Upstream builds a real pacman package, so Arch needs no AUR route.
            _openlogi_install_pkg pkg.tar.zst || return 1
            ;;
        *)
            warn "OpenLogi installation not implemented for ${DISTRO_NAME}."
            warn "Supported distros: Debian/Ubuntu, Fedora/RHEL, openSUSE, Arch/Manjaro."
            return 1
            ;;
    esac

    _openlogi_enable_agent
    _openlogi_warn_conflicts

    info "OpenLogi installed."
    info "Open it from the application menu, or run 'openlogi list' to see connected devices."
    info "Settings live in ~/.config/openlogi/config.toml."
}

uninstall_openlogi() {
    info "Uninstalling OpenLogi..."

    # Stop the agent before the binary it runs disappears.
    if systemctl --user show-environment &>/dev/null; then
        systemctl --user disable --now openlogi-agent.service 2>/dev/null || true
    fi

    case "$DISTRO_FAMILY" in
        debian)
            sudo apt purge --autoremove -y openlogi 2>/dev/null || true
            ;;
        fedora|rhel|suse)
            sudo "$PKG_MGR" remove -y openlogi 2>/dev/null || true
            ;;
        arch)
            sudo pacman -Rs --noconfirm openlogi 2>/dev/null || true
            ;;
    esac

    # The GUI's "launch at login" setting writes its own copy of the unit into
    # the user's config, pointing at the binary just removed. The packaged unit
    # goes with the package; this one has to be cleaned up by hand.
    rm -f "$HOME/.config/systemd/user/openlogi-agent.service"
    systemctl --user daemon-reload 2>/dev/null || true

    # Device bindings, profiles, and the GUI's rolling config backups.
    rm -rf "$HOME/.config/openlogi"

    info "OpenLogi has been uninstalled."
}

update_openlogi() {
    info "Updating OpenLogi..."
    case "$DISTRO_FAMILY" in
        debian)            _openlogi_install_pkg deb          || return 1 ;;
        fedora|rhel|suse)  _openlogi_install_pkg rpm          || return 1 ;;
        arch)              _openlogi_install_pkg pkg.tar.zst  || return 1 ;;
        *)                 install_openlogi; return ;;
    esac
    # A package upgrade replaces the binary under the running agent.
    if systemctl --user show-environment &>/dev/null; then
        systemctl --user try-restart openlogi-agent.service 2>/dev/null || true
    fi
}

get_version_openlogi() {
    _ver_from_pkg openlogi \
        || _ver_from_cmd openlogi \
        || echo ""
}

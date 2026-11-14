#!/bin/bash
# zram installer functions
#
# Compressed swap in RAM: the machine can hold more before it slows down, with
# no swap partition. Debian and Ubuntu use zram-tools (service zramswap, half
# of RAM, set in /etc/default/zramswap). Fedora, RHEL clones, Arch and openSUSE
# use zram-generator; when no zram-generator config exists anywhere (Fedora
# ships one) this writes /etc/systemd/zram-generator.conf with half of RAM, at
# most 4 GiB, compressed with zstd. Needs systemd, so it is not offered on
# Alpine.

# --- zram ---

_ZRAM_CONF="/etc/systemd/zram-generator.conf"
_ZRAM_MARK="# Written by linux_util"

_zram_pkg() { [[ "$DISTRO_FAMILY" == "debian" ]] && echo zram-tools || echo zram-generator; }

# Whether any zram-generator configuration exists, ours or the distro's.
_zram_has_config() {
    local f
    for f in /etc/systemd/zram-generator.conf /usr/lib/systemd/zram-generator.conf \
             /etc/systemd/zram-generator.conf.d/*.conf /usr/lib/systemd/zram-generator.conf.d/*.conf; do
        [[ -f "$f" ]] && return 0
    done
    return 1
}

check_zram() { pkg_check_installed "$(_zram_pkg)"; }

install_zram() {
    info "Installing zram..."
    local pkg
    pkg=$(_zram_pkg)
    pkg_install "$pkg" || return 1
    if [[ "$DISTRO_FAMILY" == "debian" ]]; then
        svc_enable_now zramswap || warn "Could not start zramswap; it will start at the next boot."
    else
        if ! _zram_has_config; then
            info "Writing ${_ZRAM_CONF} (half of RAM, at most 4 GiB, zstd)."
            printf '%s\n[zram0]\nzram-size = min(ram / 2, 4096)\ncompression-algorithm = zstd\n' "$_ZRAM_MARK" \
                | sudo tee "$_ZRAM_CONF" >/dev/null || return 1
        fi
        # The generator makes its units on a daemon reload.
        sudo systemctl daemon-reload
        sudo systemctl start systemd-zram-setup@zram0.service \
            || warn "Could not start zram0 now; it will start at the next boot."
    fi
    info "zram installed. Show it with: zramctl"
}

uninstall_zram() {
    info "Uninstalling zram..."
    if [[ "$DISTRO_FAMILY" == "debian" ]]; then
        svc_disable_now zramswap 2>/dev/null || true
    else
        sudo systemctl stop systemd-zram-setup@zram0.service 2>/dev/null || true
        # Only a file this installer wrote is removed.
        [[ -f "$_ZRAM_CONF" ]] && grep -qxF "$_ZRAM_MARK" "$_ZRAM_CONF" && sudo rm -f "$_ZRAM_CONF"
    fi
    pkg_remove "$(_zram_pkg)"
}

update_zram() {
    info "Updating zram..."
    pkg_upgrade "$(_zram_pkg)"
}

get_version_zram() { _ver_from_pkg "$(_zram_pkg)" || echo ""; }

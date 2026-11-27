#!/bin/bash
# auto-cpufreq installer functions
#
# Adjusts CPU speed and power use to the battery and load, with a background
# service. No distro repository carries it (the AUR does, used on Arch only
# when AUR support is on). Elsewhere the installer downloads the release's
# source archive from GitHub over HTTPS and runs upstream's own installer
# (auto-cpufreq-installer --install), which puts it in /opt/auto-cpufreq with
# its Python parts from PyPI, then installs the service with
# `auto-cpufreq --install`. Upstream publishes no checksum or signature for
# releases. It cannot run beside TLP; needs systemd, so it is not offered on
# Alpine, and upstream's installer fails on openSUSE Leap (it asks for Python
# packages Leap does not have) and the program needs Python 3.10, which Rocky/Alma
# 8 and 9 do not ship, so it is not offered on either.

# --- auto-cpufreq ---

_ACF_API="https://api.github.com/repos/AdnanHodzic/auto-cpufreq/releases/latest"
_ACF_ROOT="/opt/auto-cpufreq"
# Written when the service is installed; present only while it is.
_ACF_DAEMON_REMOVER="/usr/local/bin/auto-cpufreq-remove"

# Latest release version without the leading v, e.g. 3.2.0.
_acf_latest_version() {
    curl -fsSL --max-time 15 "$_ACF_API" 2>/dev/null \
        | grep -oP '"tag_name"\s*:\s*"v?\K[0-9.]+' | head -1
}

check_auto_cpufreq() {
    [[ -e "${_ACF_ROOT}/current" ]] && return 0
    _check_standard auto-cpufreq auto-cpufreq ""
}

# Download release $1 and unpack it; sets the variable named by $2 to the source
# directory (removed on exit). Nothing on the system is touched.
_acf_fetch_source() {
    local ver="$1"
    local -n _acf_src="$2"
    local tmp
    ensure_tools
    tmp=$(mktemp -d) || return 1
    CLEANUP_FILES+=("$tmp")
    info "Downloading auto-cpufreq ${ver} from GitHub..."
    curl -fsSL --max-time 120 \
        "https://github.com/AdnanHodzic/auto-cpufreq/archive/refs/tags/v${ver}.tar.gz" \
        -o "${tmp}/src.tar.gz" || { error "Could not download auto-cpufreq ${ver}."; rm -rf "$tmp"; return 1; }
    mkdir "${tmp}/src" && tar -xzf "${tmp}/src.tar.gz" -C "${tmp}/src" --strip-components=1 \
        || { error "Could not unpack the auto-cpufreq download."; rm -rf "$tmp"; return 1; }
    _acf_src="${tmp}/src"
}

# Put release $1 in place and start its service. Upstream's installer refuses to
# run while the service is installed, so a running install is stopped first --
# but only AFTER the release has been downloaded and unpacked, so a failed
# download leaves the running service alone, and if the installer itself fails
# the service is put back.
_acf_deploy() {
    local ver="$1" src had_daemon=false
    _acf_fetch_source "$ver" src || return 1
    if [[ -e "$_ACF_DAEMON_REMOVER" ]]; then
        had_daemon=true
        sudo auto-cpufreq --remove || { error "Could not stop the auto-cpufreq service for the update."; return 1; }
    fi
    if ! sudo bash "${src}/auto-cpufreq-installer" --install; then
        error "The auto-cpufreq installer failed."
        if [[ "$had_daemon" == true ]]; then
            if sudo auto-cpufreq --install; then
                warn "The previous auto-cpufreq service was started again."
            else
                warn "The auto-cpufreq service is not running; run 'sudo auto-cpufreq --install' to start it."
            fi
        fi
        return 1
    fi
    sudo auto-cpufreq --install || warn "Could not install the auto-cpufreq service; run 'sudo auto-cpufreq --install' later."
}

install_auto_cpufreq() {
    info "Installing auto-cpufreq..."
    if pkg_check_installed tlp; then
        error "TLP is installed, and the two fight over the same CPU settings. Uninstall TLP first."
        return 1
    fi
    if [[ "$DISTRO_FAMILY" == "arch" ]]; then
        repo_or_aur auto-cpufreq || return 1
        svc_enable_now auto-cpufreq || warn "Could not start the auto-cpufreq service; it will start at the next boot."
        info "auto-cpufreq installed."
        return 0
    fi
    local ver
    ver=$(_acf_latest_version)
    [[ -n "$ver" ]] || { error "Could not read the latest auto-cpufreq version from GitHub."; return 1; }
    _acf_deploy "$ver" || return 1
    info "auto-cpufreq ${ver} installed. Watch it with: auto-cpufreq --stats"
}

uninstall_auto_cpufreq() {
    info "Uninstalling auto-cpufreq..."
    if [[ -e "${_ACF_ROOT}/current" ]]; then
        # Upstream order: the service first, then the program.
        sudo auto-cpufreq --remove 2>/dev/null || true
        local tmp ver
        ver=$(_acf_latest_version)
        [[ -n "$ver" ]] || { error "Could not read the auto-cpufreq version from GitHub to run its remover."; return 1; }
        _acf_fetch_source "$ver" tmp || return 1
        sudo bash "${tmp}/auto-cpufreq-installer" --remove
        return $?
    fi
    svc_disable_now auto-cpufreq 2>/dev/null || true
    pkg_remove auto-cpufreq
}

update_auto_cpufreq() {
    info "Updating auto-cpufreq..."
    if [[ -e "${_ACF_ROOT}/current" ]]; then
        local ver cur
        ver=$(_acf_latest_version)
        [[ -n "$ver" ]] || { error "Could not read the latest auto-cpufreq version from GitHub."; return 1; }
        cur=$(get_version_auto_cpufreq)
        if [[ -n "$cur" && "$cur" == "$ver" ]]; then
            info "auto-cpufreq is already at the latest version (${cur})."
            return 0
        fi
        _acf_deploy "$ver"
    elif [[ "$DISTRO_FAMILY" == "arch" ]]; then
        repo_or_aur auto-cpufreq
    else
        error "auto-cpufreq is not installed."
        return 1
    fi
}

# --version prints the distro and kernel first, so the line that names
# auto-cpufreq is picked out: "auto-cpufreq version: 3.2.0 (git: ...)".
get_version_auto_cpufreq() {
    local v
    v=$(_run_native auto-cpufreq --version 2>/dev/null | sed -n 's/^auto-cpufreq version: \([0-9][0-9.]*\).*/\1/p' | head -1)
    printf '%s\n' "$v"
}

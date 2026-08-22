#!/bin/bash
# LocalSend installer functions
# Open-source AirDrop alternative — transfers files between devices on the
# local network over port 53317, with no internet connection or account.

# --- LocalSend ---

check_localsend() {
    # The .deb symlinks /usr/bin/localsend_app; the AUR package uses /usr/bin/localsend.
    _have_cmd localsend_app && return 0
    _have_cmd localsend     && return 0
    pkg_check_installed localsend     && return 0
    pkg_check_installed localsend-bin && return 0
    flatpak_is_installed "org.localsend.localsend_app"
}

# Print the download URL of the newest release asset matching $1 (an ERE).
#
# The GitHub "latest" release is not usable on its own here: LocalSend ships
# Android-only hotfix releases (v1.18.1 carries no Linux assets at all), so the
# newest release with a Linux build is sometimes one or more releases back. The
# releases list is returned newest-first, so the first match is the right one.
_localsend_asset_url() {
    local pattern="$1"
    curl -fsSL "https://api.github.com/repos/localsend/localsend/releases?per_page=15" \
        | grep -oP '"browser_download_url"\s*:\s*"\K[^"]+' \
        | grep -m1 -E "$pattern"
}

_localsend_install_deb() {
    local pattern url tmpfile tag
    case "$(uname -m)" in
        x86_64)        pattern='linux-x86-64\.deb$' ;;
        aarch64|arm64) pattern='linux-arm-64\.deb$' ;;
        *)
            error "Unsupported architecture for LocalSend: $(uname -m)"
            return 1
            ;;
    esac

    url=$(_localsend_asset_url "$pattern")
    if [[ -z "$url" ]]; then
        error "Could not find a LocalSend .deb release asset."
        return 1
    fi

    tmpfile=$(mktemp /tmp/localsend-XXXXXX.deb)
    CLEANUP_FILES+=("$tmpfile")
    wget -qO "$tmpfile" "$url" || { error "Failed to download LocalSend .deb."; return 1; }
    verify_download "$tmpfile" "deb" "LocalSend" || return 1
    # Checksums are looked up per release tag, not from /releases/latest, for the
    # same reason _localsend_asset_url walks the list.
    tag=$(basename "$(dirname "$url")")
    github_verify_checksum \
        "https://api.github.com/repos/localsend/localsend/releases/tags/${tag}" \
        "$(basename "$url")" "$tmpfile" || return 1
    sudo apt install -y "$tmpfile"
}

# Which firewall is active, if any: echoes "ufw", "firewalld", or nothing.
_localsend_active_firewall() {
    if command -v ufw &>/dev/null && ufw status 2>/dev/null | grep -q "^Status: active"; then
        echo "ufw"
    elif command -v firewall-cmd &>/dev/null && sudo firewall-cmd --state &>/dev/null; then
        echo "firewalld"
    fi
}

# LocalSend announces itself over UDP multicast on port 53317 and transfers
# files over TCP 53317. With a firewall active and that port closed the app
# starts fine but no other device on the LAN can discover or reach it, so offer
# to open it rather than leaving the user to debug a silent failure.
_localsend_open_firewall() {
    local fw
    fw=$(_localsend_active_firewall)
    [[ -z "$fw" ]] && return 0

    # A non-interactive run has nobody to ask; say what is needed and move on
    # rather than failing on a /dev/tty that isn't there.
    if [[ ! -w /dev/tty ]]; then
        warn "${fw} is active — open 53317/tcp and 53317/udp for LocalSend to be discoverable."
        return 0
    fi

    {
        printf '\n'
        printf '  %s firewall is active. LocalSend needs:\n' "$fw"
        printf '    53317/tcp  (file transfers)\n'
        printf '    53317/udp  (device discovery)\n\n'
    } > /dev/tty

    _confirm_step "  Open these ports in ${fw}?" || {
        info "Skipped — other devices will not discover this machine until port 53317 is open."
        return 0
    }

    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        info "[Dry run] Would open 53317/tcp and 53317/udp in ${fw}"
        return 0
    fi

    case "$fw" in
        ufw)
            sudo ufw allow 53317/tcp && info "UFW: opened 53317/tcp"
            sudo ufw allow 53317/udp && info "UFW: opened 53317/udp"
            ;;
        firewalld)
            sudo firewall-cmd --permanent --add-port=53317/tcp --add-port=53317/udp && \
                sudo firewall-cmd --reload && info "firewalld: opened 53317/tcp and 53317/udp"
            ;;
    esac
}

# Drop the rules added above. Each removal is guarded on the rule actually being
# present, so an uninstall never touches a firewall the installer never changed.
_localsend_close_firewall() {
    local fw
    fw=$(_localsend_active_firewall)
    [[ -z "$fw" ]] && return 0

    case "$fw" in
        ufw)
            ufw status 2>/dev/null | grep -q "53317" || return 0
            if [[ "${DRY_RUN:-false}" == "true" ]]; then
                info "[Dry run] Would remove the UFW rules for 53317"
                return 0
            fi
            sudo ufw delete allow 53317/tcp 2>/dev/null && info "UFW: removed 53317/tcp"
            sudo ufw delete allow 53317/udp 2>/dev/null && info "UFW: removed 53317/udp"
            ;;
        firewalld)
            sudo firewall-cmd --permanent --query-port=53317/tcp &>/dev/null || return 0
            if [[ "${DRY_RUN:-false}" == "true" ]]; then
                info "[Dry run] Would remove the firewalld rules for 53317"
                return 0
            fi
            sudo firewall-cmd --permanent --remove-port=53317/tcp --remove-port=53317/udp && \
                sudo firewall-cmd --reload && info "firewalld: removed 53317/tcp and 53317/udp"
            ;;
    esac
}

install_localsend() {
    info "Installing LocalSend..."
    ensure_tools
    case "$DISTRO_FAMILY" in
        debian)
            _localsend_install_deb || return 1
            ;;
        fedora|rhel|suse)
            # Upstream publishes no .rpm and LocalSend is in no RPM distro's
            # repos, so Flathub is the only supported route on these families.
            ensure_flatpak || {
                error "Flatpak is required to install LocalSend on ${DISTRO_NAME} (upstream publishes no .rpm)."
                return 1
            }
            sudo flatpak install -y flathub org.localsend.localsend_app || return 1
            ;;
        arch)
            # Not in the official Arch repos — Flathub first, AUR as fallback.
            flatpak_or_aur org.localsend.localsend_app localsend-bin || return 1
            ;;
        *)
            warn "LocalSend installation not implemented for ${DISTRO_NAME}."
            warn "Supported distros: Debian/Ubuntu, Fedora/RHEL, Arch/Manjaro, openSUSE."
            return 1
            ;;
    esac

    _localsend_open_firewall

    info "LocalSend installed."
    info "Open it from the application menu — devices running LocalSend on the same network appear automatically."
}

uninstall_localsend() {
    info "Uninstalling LocalSend..."

    if flatpak_is_installed "org.localsend.localsend_app"; then
        flatpak uninstall -y org.localsend.localsend_app
    fi

    case "$DISTRO_FAMILY" in
        debian)
            sudo apt purge --autoremove -y localsend 2>/dev/null || true
            sudo apt autoclean
            ;;
        arch)
            aur_remove localsend-bin 2>/dev/null || \
                sudo pacman -Rs --noconfirm localsend-bin 2>/dev/null || true
            ;;
    esac

    _localsend_close_firewall

    # App settings (device alias, theme, saved favourites). Received files live
    # in ~/Downloads and are left alone.
    rm -rf "$HOME/.local/share/org.localsend.localsend_app"

    info "LocalSend has been uninstalled."
}

update_localsend() {
    info "Updating LocalSend..."
    if flatpak_is_installed "org.localsend.localsend_app"; then
        flatpak update -y org.localsend.localsend_app
        return
    fi
    case "$DISTRO_FAMILY" in
        debian) _localsend_install_deb ;;
        arch)   repo_or_aur localsend-bin ;;
        *)      install_localsend ;;
    esac
}

get_version_localsend() {
    local v
    v=$(_ver_from_pkg localsend \
        || _ver_from_pkg localsend-bin \
        || _ver_from_flatpak org.localsend.localsend_app) || { echo ""; return 0; }
    # The .deb reports a build-tagged version like "1.18.0+60" — trim it.
    printf '%s\n' "${v%%+*}"
}

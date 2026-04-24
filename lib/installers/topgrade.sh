#!/bin/bash
# Topgrade installer functions
#
# Topgrade runs all configured updaters (apt/dnf/pacman, flatpak, snap, cargo,
# pip, brew, etc.) in sequence from a single command.
#
# BAZZITE NOTE: Bazzite ships Topgrade as part of its core update stack and
# invokes it via `ujust update`. We detect this and skip installation, only
# offering config management so the user can deploy a profile-appropriate
# topgrade.toml without overwriting Bazzite's own config.

# Canonical config path (respects XDG_CONFIG_HOME)
_topgrade_config_dir() {
    echo "${XDG_CONFIG_HOME:-$HOME/.config}/topgrade"
}

_topgrade_config_file() {
    echo "$(_topgrade_config_dir)/topgrade.toml"
}

# True when running on Bazzite (topgrade is pre-installed, don't touch the binary)
_topgrade_is_bazzite() {
    [[ "${DISTRO_ID:-}" == "bazzite" ]] || \
    grep -qi "bazzite" /etc/os-release 2>/dev/null
}

# ─── Check ───────────────────────────────────────────────────────────────────

check_topgrade() {
    command -v topgrade &>/dev/null
}

# ─── Install ─────────────────────────────────────────────────────────────────

install_topgrade() {
    if _topgrade_is_bazzite; then
        info "Bazzite detected — Topgrade is pre-installed (invoked via 'ujust update')."
        info "Skipping binary installation; proceeding to config setup."
        _topgrade_config_setup
        return 0
    fi

    info "Installing Topgrade..."
    case "$DISTRO_FAMILY" in
        arch)
            # topgrade is in the AUR; use the configured AUR helper
            aur_install topgrade
            ;;
        *)
            # All other distros: install the pre-built binary from GitHub releases
            _topgrade_install_binary || return 1
            ;;
    esac

    _topgrade_config_setup
    info "Topgrade installed."
}

# Download and install the latest pre-built Topgrade release from GitHub.
# Prefers the native .deb on Debian-family distros; falls back to the musl
# tarball on all other distros.
# Release asset naming (as of v17+):
#   tarball:  topgrade-v<VER>-<ARCH>-unknown-linux-musl.tar.gz
#   deb:      topgrade_<VER>_<DEB_ARCH>.deb
_topgrade_install_binary() {
    local arch
    arch=$(uname -m)
    local api_url="https://api.github.com/repos/topgrade-rs/topgrade/releases/latest"

    # Fetch the full release JSON once and reuse it
    local release_json
    release_json=$(curl -fsSL "$api_url") || {
        error "Topgrade: failed to fetch release info from GitHub."
        return 1
    }

    # Prefer .deb on Debian-family distros
    if [[ "${DISTRO_FAMILY:-}" == "debian" ]]; then
        local deb_arch
        case "$arch" in
            x86_64)  deb_arch="amd64" ;;
            aarch64) deb_arch="arm64" ;;
            armv7l)  deb_arch="armhf" ;;
            *)
                warn "Topgrade: no .deb for ${arch}, falling back to tarball."
                deb_arch=""
                ;;
        esac

        if [[ -n "$deb_arch" ]]; then
            local deb_url
            deb_url=$(echo "$release_json" \
                | grep -oP '"browser_download_url"\s*:\s*"\K[^"]+topgrade_[^"]+_'"${deb_arch}"'\.deb(?=")' \
                | head -1)

            if [[ -n "$deb_url" ]]; then
                local tmpfile
                tmpfile=$(mktemp /tmp/topgrade-XXXXXX.deb)
                CLEANUP_FILES+=("$tmpfile")
                info "Downloading Topgrade .deb from GitHub..."
                curl -fsSL -o "$tmpfile" "$deb_url" || { error "Download failed."; return 1; }
                verify_download "$tmpfile" "deb" "Topgrade" || return 1
                sudo dpkg -i "$tmpfile" || { error "dpkg install failed."; return 1; }
                return 0
            fi
        fi
    fi

    # Tarball fallback for all other distros (musl static binary)
    local asset_arch
    case "$arch" in
        x86_64)  asset_arch="x86_64" ;;
        aarch64) asset_arch="aarch64" ;;
        *)
            error "Topgrade: unsupported architecture for tarball install: ${arch}"
            return 1
            ;;
    esac

    local download_url
    download_url=$(echo "$release_json" \
        | grep -oP '"browser_download_url"\s*:\s*"\K[^"]+topgrade-v[^"]+'"${asset_arch}"'-unknown-linux-musl\.tar\.gz(?=")' \
        | head -1)

    if [[ -z "$download_url" ]]; then
        error "Topgrade: could not find a release asset for ${asset_arch}."
        return 1
    fi

    local tmpfile
    tmpfile=$(mktemp /tmp/topgrade-XXXXXX.tar.gz)
    CLEANUP_FILES+=("$tmpfile")

    info "Downloading Topgrade from GitHub..."
    curl -fsSL -o "$tmpfile" "$download_url" || { error "Download failed."; return 1; }
    verify_download "$tmpfile" "tar.gz" "Topgrade" || return 1

    local tmpdir
    tmpdir=$(mktemp -d)
    tar -xzf "$tmpfile" -C "$tmpdir"

    sudo install -Dm 755 "${tmpdir}/topgrade" /usr/local/bin/topgrade || {
        error "Failed to install Topgrade binary."
        rm -rf "$tmpdir"
        return 1
    }
    rm -rf "$tmpdir"
}

# ─── Config setup ────────────────────────────────────────────────────────────

# Interactively offer config template selection and deploy to ~/.config/topgrade/topgrade.toml.
_topgrade_config_setup() {
    local config_dir config_file
    config_dir=$(_topgrade_config_dir)
    config_file=$(_topgrade_config_file)

    local templates_dir="${SCRIPT_DIR}/lib/templates/topgrade"

    # If no templates exist, nothing to offer
    if [[ ! -d "$templates_dir" ]]; then
        return 0
    fi

    # If a config already exists, ask before overwriting
    if [[ -f "$config_file" ]]; then
        local overwrite=""
        echo ""
        echo "  A Topgrade config already exists at: ${config_file}"
        read -rp "  Replace it with a preset template? (y/N): " overwrite < /dev/tty
        [[ "$overwrite" =~ ^[Yy]$ ]] || return 0
    fi

    # Build a menu from available templates
    local -a templates=()
    local -a template_labels=()
    while IFS= read -r -d '' f; do
        local basename
        basename=$(basename "$f" .toml)
        templates+=("$f")
        template_labels+=("$basename")
    done < <(find "$templates_dir" -maxdepth 1 -name "*.toml" -print0 | sort -z)

    if [[ ${#templates[@]} -eq 0 ]]; then
        return 0
    fi

    echo ""
    echo "  Select a Topgrade config template:"
    local i
    for (( i=0; i<${#templates[@]}; i++ )); do
        printf "    %d) %s\n" $(( i + 1 )) "${template_labels[$i]}"
    done
    printf "    %d) %s\n" $(( ${#templates[@]} + 1 )) "Skip / keep existing config"
    echo ""

    local choice=""
    read -rp "  Choice [1-$(( ${#templates[@]} + 1 ))]: " choice < /dev/tty

    if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#templates[@]} )); then
        local chosen="${templates[$(( choice - 1 ))]}"
        mkdir -p "$config_dir"

        # Back up existing config before overwriting
        if [[ -f "$config_file" ]]; then
            local backup="${config_file}.bak.$(date +%Y%m%d_%H%M%S)"
            cp "$config_file" "$backup"
            info "Existing config backed up to: ${backup}"
        fi

        cp "$chosen" "$config_file"
        info "Topgrade config installed: ${template_labels[$(( choice - 1 ))]}"
        info "Edit ${config_file} to customise."
    else
        info "Config template skipped."
    fi
}

# ─── Uninstall ───────────────────────────────────────────────────────────────

uninstall_topgrade() {
    if _topgrade_is_bazzite; then
        info "Bazzite: Topgrade is a system component and will not be removed."
        info "To remove the config only, delete: $(_topgrade_config_file)"
        return 0
    fi

    info "Uninstalling Topgrade..."
    case "$DISTRO_FAMILY" in
        arch)
            if command -v yay &>/dev/null; then
                yay -Rs --noconfirm topgrade 2>/dev/null || true
            elif command -v paru &>/dev/null; then
                paru -Rs --noconfirm topgrade 2>/dev/null || true
            fi
            ;;
        *)
            sudo rm -f /usr/local/bin/topgrade
            ;;
    esac

    local config_file
    config_file=$(_topgrade_config_file)
    if [[ -f "$config_file" ]]; then
        local remove_cfg=""
        echo ""
        read -rp "  Remove Topgrade config at ${config_file}? (y/N): " remove_cfg < /dev/tty
        if [[ "$remove_cfg" =~ ^[Yy]$ ]]; then
            rm -f "$config_file"
            info "Config removed."
        else
            info "Config preserved at: ${config_file}"
        fi
    fi

    info "Topgrade uninstalled."
}

# ─── Update ──────────────────────────────────────────────────────────────────

update_topgrade() {
    if _topgrade_is_bazzite; then
        info "Bazzite: use 'ujust update' to update Topgrade alongside the system."
        return 0
    fi

    info "Updating Topgrade..."
    case "$DISTRO_FAMILY" in
        arch)
            aur_install topgrade
            ;;
        *)
            _topgrade_install_binary || return 1
            ;;
    esac
    info "Topgrade updated."

    local config_file
    config_file=$(_topgrade_config_file)
    if [[ -f "$config_file" ]]; then
        local replace_cfg=""
        echo ""
        read -rp "  Replace existing Topgrade config with a fresh template? (y/N): " replace_cfg < /dev/tty
        if [[ "$replace_cfg" =~ ^[Yy]$ ]]; then
            _topgrade_config_setup
        else
            info "Config unchanged: ${config_file}"
        fi
    else
        _topgrade_config_setup
    fi
}

# ─── Version ─────────────────────────────────────────────────────────────────

get_version_topgrade() {
    if _topgrade_is_bazzite; then
        # Bazzite: emit the installed binary version with a note
        local v
        v=$(topgrade --version 2>/dev/null | grep -oP '\d+\.\d+\.\d+' | head -1)
        [[ -n "$v" ]] && echo "${v} (built-in)" || echo "built-in"
        return 0
    fi
    _ver_from_cmd topgrade || echo ""
}

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

# Download and install the latest pre-built Topgrade binary from GitHub releases.
_topgrade_install_binary() {
    local arch
    arch=$(uname -m)
    local api_url="https://api.github.com/repos/topgrade-rs/topgrade/releases/latest"

    # Map uname -m to the naming convention used in release assets
    local asset_arch
    case "$arch" in
        x86_64)  asset_arch="x86_64" ;;
        aarch64) asset_arch="aarch64" ;;
        armv7l)  asset_arch="armv7" ;;
        *)
            error "Topgrade: unsupported architecture: ${arch}"
            return 1
            ;;
    esac

    local download_url
    download_url=$(curl -fsSL "$api_url" \
        | grep -oP '"browser_download_url"\s*:\s*"\K[^"]+topgrade-v[^"]+'"${asset_arch}"'-unknown-linux-musl\.tar\.gz"' \
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

    info "Topgrade binary removed. Config at $(_topgrade_config_file) preserved."
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

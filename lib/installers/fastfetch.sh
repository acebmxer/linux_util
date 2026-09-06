#!/bin/bash
# Fastfetch installer functions

# --- Fastfetch ---

check_fastfetch() { _check_standard fastfetch fastfetch ""; }

_fastfetch_latest_url() {
    local ext="$1"
    curl -fsSL "https://api.github.com/repos/fastfetch-cli/fastfetch/releases/latest" \
        | grep -oP '"browser_download_url"\s*:\s*"\K[^"]+linux-amd64\.'"$ext"'(?=")' | head -1
}

# Bring an existing auto-run line up to date. Earlier versions wrote it without
# the guards below, so it fired twice on a connect that creates a tmux session:
# once here on the login shell, then again from the auto-attach block. Rewrites
# only the line directly following our own marker, and is a no-op once the line
# already matches, so a re-run does not churn the file.
#
# Two separate conditions are needed. -z $TMUX suppresses it for shells started
# *inside* tmux (new windows and panes). _LU_TMUX_AUTOATTACH suppresses it on the
# login shell that is about to hand off to tmux -- there $TMUX is still empty, so
# that check alone does not catch it.
_fastfetch_refresh_rc_line() {
    local rc="$1" marker="$2" line="$3"
    grep -qF "$marker" "$rc" 2>/dev/null || return 1
    grep -qF "$line" <(grep -A1 -F "$marker" "$rc") && return 1
    local tmp
    tmp=$(mktemp) || return 1
    awk -v m="$marker" -v repl="$line" '
        prev == m && $0 ~ /fastfetch/ { print repl; prev = $0; next }
        { print; prev = $0 }
    ' "$rc" > "$tmp" && cat "$tmp" > "$rc"
    rm -f "$tmp"
    return 0
}

_fastfetch_configure_shells() {
    local marker="# linux_util:fastfetch"

    # bash
    if command -v bash &>/dev/null; then
        if [[ -f "$HOME/.bashrc" ]]; then
            local rc="$HOME/.bashrc"
            if ! grep -qF "$marker" "$rc" 2>/dev/null; then
                printf '\n%s\n[[ $- == *i* && -z $TMUX && -z $_LU_TMUX_AUTOATTACH ]] && fastfetch\n' "$marker" >> "$rc"
                info "Added fastfetch auto-run to $rc"
            elif _fastfetch_refresh_rc_line "$rc" "$marker" '[[ $- == *i* && -z $TMUX && -z $_LU_TMUX_AUTOATTACH ]] && fastfetch'; then
                info "Updated fastfetch auto-run in $rc so it does not double up inside tmux"
            else
                info "Fastfetch auto-run already configured in $rc"
            fi
        elif [[ -L "$HOME/.bashrc" ]]; then
            info "~/.bashrc is a broken symlink — skipping fastfetch auto-run for bash"
        else
            info "bash installed but ~/.bashrc not found — skipping fastfetch auto-run for bash"
        fi
    fi

    # zsh
    if command -v zsh &>/dev/null; then
        local rc="$HOME/.zshrc"
        if ! grep -qF "$marker" "$rc" 2>/dev/null; then
            local p10k_prompt="# Enable Powerlevel10k instant prompt"
            if grep -qF "$p10k_prompt" "$rc" 2>/dev/null; then
                # Insert before p10k instant prompt block so fastfetch output
                # isn't captured by p10k's terminal takeover
                sed -i "/${p10k_prompt}/i ${marker}\n[[ \$- == *i* \&\& -z \$TMUX \&\& -z \$_LU_TMUX_AUTOATTACH ]] \&\& fastfetch\n" "$rc"
            else
                printf '\n%s\n[[ $- == *i* && -z $TMUX && -z $_LU_TMUX_AUTOATTACH ]] && fastfetch\n' "$marker" >> "$rc"
            fi
            info "Added fastfetch auto-run to $rc"
        elif _fastfetch_refresh_rc_line "$rc" "$marker" '[[ $- == *i* && -z $TMUX && -z $_LU_TMUX_AUTOATTACH ]] && fastfetch'; then
            info "Updated fastfetch auto-run in $rc so it does not double up inside tmux"
        else
            info "Fastfetch auto-run already configured in $rc"
        fi
    fi

    # fish
    if command -v fish &>/dev/null; then
        local rc="$HOME/.config/fish/config.fish"
        mkdir -p "$(dirname "$rc")"
        if ! grep -qF "$marker" "$rc" 2>/dev/null; then
            printf '\n%s\nstatus is-interactive; and fastfetch\n' "$marker" >> "$rc"
            info "Added fastfetch auto-run to $rc"
        else
            info "Fastfetch auto-run already configured in $rc"
        fi
    fi

    # tcsh
    if command -v tcsh &>/dev/null && [[ -f "$HOME/.tcshrc" ]]; then
        local rc="$HOME/.tcshrc"
        if ! grep -qF "$marker" "$rc" 2>/dev/null; then
            printf '\n%s\nif ($?prompt) fastfetch\n' "$marker" >> "$rc"
            info "Added fastfetch auto-run to $rc"
        else
            info "Fastfetch auto-run already configured in $rc"
        fi
    fi

    # xonsh
    if command -v xonsh &>/dev/null && [[ -f "$HOME/.xonshrc" ]]; then
        local rc="$HOME/.xonshrc"
        if ! grep -qF "$marker" "$rc" 2>/dev/null; then
            printf '\n%s\n$(fastfetch)\n' "$marker" >> "$rc"
            info "Added fastfetch auto-run to $rc"
        else
            info "Fastfetch auto-run already configured in $rc"
        fi
    fi

    # elvish
    if command -v elvish &>/dev/null; then
        local rc="$HOME/.config/elvish/rc.elv"
        mkdir -p "$(dirname "$rc")"
        if ! grep -qF "$marker" "$rc" 2>/dev/null; then
            printf '\n%s\nfastfetch\n' "$marker" >> "$rc"
            info "Added fastfetch auto-run to $rc"
        else
            info "Fastfetch auto-run already configured in $rc"
        fi
    fi

    # nushell
    if command -v nu &>/dev/null; then
        local nu_config
        nu_config=$(nu -c '$nu.config-path' 2>/dev/null)
        if [[ -n "$nu_config" && -f "$nu_config" ]]; then
            if ! grep -qF "$marker" "$nu_config" 2>/dev/null; then
                printf '\n%s\nfastfetch\n' "$marker" >> "$nu_config"
                info "Added fastfetch auto-run to $nu_config"
            else
                info "Fastfetch auto-run already configured in $nu_config"
            fi
        fi
    fi
}


_fastfetch_deconfigure_shells() {
    local marker="# linux_util:fastfetch"
    local rc
    local nu_config

    # Determine nushell config path if available
    if command -v nu &>/dev/null; then
        nu_config=$(nu -c '$nu.config-path' 2>/dev/null)
    fi

    for rc in "$HOME/.bashrc" "$HOME/.zshrc" "$HOME/.config/fish/config.fish" \
              "$HOME/.tcshrc" "$HOME/.xonshrc" "$HOME/.config/elvish/rc.elv" \
              ${nu_config:+"$nu_config"}; do
        [[ -f "$rc" ]] || continue
        if grep -qF "$marker" "$rc"; then
            sed -i '/^# linux_util:fastfetch$/{N;d}' "$rc"
            info "Removed fastfetch auto-run from $rc"
        fi
    done
}

install_fastfetch() {
    info "Installing Fastfetch..."
    ensure_tools
    case "$DISTRO_FAMILY" in
        debian)
            # Available in Ubuntu 23.10+ and Debian 13+ natively; use .deb for older versions
            if sudo apt install -y fastfetch 2>/dev/null; then
                : # installed from repo
            else
                info "Installing Fastfetch from GitHub release..."
                local url
                url=$(_fastfetch_latest_url "deb")
                if [[ -z "$url" ]]; then
                    error "Could not find Fastfetch .deb release."
                    return 1
                fi
                local tmpfile
                tmpfile=$(mktemp /tmp/fastfetch-XXXXXX.deb)
                CLEANUP_FILES+=("$tmpfile")
                wget -qO "$tmpfile" "$url" || { error "Failed to download Fastfetch .deb."; return 1; }
                verify_download "$tmpfile" "deb" "Fastfetch" || return 1
                github_verify_checksum "https://api.github.com/repos/fastfetch-cli/fastfetch/releases/latest" \
                    "$(basename "$url")" "$tmpfile" || return 1
                sudo apt install -y "$tmpfile"
            fi
            ;;
        fedora)
            sudo "$PKG_MGR" install -y fastfetch
            ;;
        rhel)
            sudo "$PKG_MGR" install -y epel-release 2>/dev/null || true
            sudo "$PKG_MGR" install -y fastfetch 2>/dev/null || {
                info "Installing Fastfetch from GitHub release..."
                local url
                url=$(_fastfetch_latest_url "rpm")
                [[ -z "$url" ]] && { error "Could not find Fastfetch .rpm release."; return 1; }
                local tmpfile
                tmpfile=$(mktemp /tmp/fastfetch-XXXXXX.rpm)
                CLEANUP_FILES+=("$tmpfile")
                wget -qO "$tmpfile" "$url" || { error "Failed to download Fastfetch .rpm."; return 1; }
                verify_download "$tmpfile" "rpm" "Fastfetch" || return 1
                github_verify_checksum "https://api.github.com/repos/fastfetch-cli/fastfetch/releases/latest" \
                    "$(basename "$url")" "$tmpfile" || return 1
                sudo "$PKG_MGR" install -y "$tmpfile"
            }
            ;;
        arch)
            sudo pacman -S --noconfirm fastfetch
            ;;
        suse)
            sudo zypper install -y fastfetch 2>/dev/null || {
                info "Installing Fastfetch from GitHub release..."
                local url
                url=$(_fastfetch_latest_url "rpm")
                [[ -z "$url" ]] && { error "Could not find Fastfetch .rpm release."; return 1; }
                local tmpfile
                tmpfile=$(mktemp /tmp/fastfetch-XXXXXX.rpm)
                CLEANUP_FILES+=("$tmpfile")
                wget -qO "$tmpfile" "$url" || { error "Failed to download Fastfetch .rpm."; return 1; }
                verify_download "$tmpfile" "rpm" "Fastfetch" || return 1
                github_verify_checksum "https://api.github.com/repos/fastfetch-cli/fastfetch/releases/latest" \
                    "$(basename "$url")" "$tmpfile" || return 1
                sudo zypper install -y "$tmpfile"
            }
            ;;
    esac
    _fastfetch_configure_shells
    info "Fastfetch installed."
}

uninstall_fastfetch() {
    info "Uninstalling Fastfetch..."
    case "$DISTRO_FAMILY" in
        debian)  sudo apt purge --autoremove -y fastfetch 2>/dev/null || sudo dpkg -r fastfetch 2>/dev/null || true ;;
        fedora|rhel) sudo "$PKG_MGR" remove -y fastfetch ;;
        arch)    sudo pacman -Rs --noconfirm fastfetch ;;
        suse)    sudo zypper remove -y fastfetch ;;
    esac
    _fastfetch_deconfigure_shells
    rm -rf "$HOME/.config/fastfetch"
}

update_fastfetch() {
    info "Updating Fastfetch..."
    case "$DISTRO_FAMILY" in
        debian)
            sudo apt-get install -y --only-upgrade fastfetch 2>/dev/null || install_fastfetch
            ;;
        fedora|rhel) sudo "$PKG_MGR" upgrade -y fastfetch 2>/dev/null || install_fastfetch ;;
        arch)    sudo pacman -S --noconfirm fastfetch ;;
        suse)    sudo zypper update -y fastfetch 2>/dev/null || install_fastfetch ;;
    esac
    _fastfetch_configure_shells
}

get_version_fastfetch() {
    _ver_from_cmd fastfetch || echo ""
}

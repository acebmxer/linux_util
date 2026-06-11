#!/bin/bash
# Zsh + Oh My Zsh installer functions

_OMZ_DIR="$HOME/.oh-my-zsh"
_P10K_THEME_DIR="${ZSH_CUSTOM:-$_OMZ_DIR/custom}/themes/powerlevel10k"

check_zsh_setup() {
    command -v zsh &>/dev/null && [[ -d "$_OMZ_DIR" ]]
}

_zsh_setup_apply_omz_theme() {
    local theme="$1"
    [[ -f "$HOME/.zshrc" ]] || return
    if grep -q '^ZSH_THEME=' "$HOME/.zshrc"; then
        sed -i "s|^ZSH_THEME=.*|ZSH_THEME=\"${theme}\"|" "$HOME/.zshrc"
    else
        printf '\nZSH_THEME="%s"\n' "$theme" >> "$HOME/.zshrc"
    fi
    info "Set Zsh theme to '${theme}'"
}

_zsh_setup_configure_plugins() {
    [[ -f "$HOME/.zshrc" ]] || return
    if ! grep -q "zsh-autosuggestions" "$HOME/.zshrc"; then
        sed -i 's/^plugins=(\(.*\))/plugins=(\1 zsh-autosuggestions)/' "$HOME/.zshrc"
        info "Added zsh-autosuggestions to plugins in ~/.zshrc"
    else
        info "zsh-autosuggestions already in plugins in ~/.zshrc"
    fi
    if ! grep -q "zsh-syntax-highlighting" "$HOME/.zshrc"; then
        sed -i 's/^plugins=(\(.*\))/plugins=(\1 zsh-syntax-highlighting)/' "$HOME/.zshrc"
        info "Added zsh-syntax-highlighting to plugins in ~/.zshrc"
    else
        info "zsh-syntax-highlighting already in plugins in ~/.zshrc"
    fi
}

_zsh_setup_remove_legacy_starship() {
    local marker="# linux_util:zsh_setup"
    local rc

    for rc in "$HOME/.zshrc" "$HOME/.bashrc" "$HOME/.config/fish/config.fish" \
              "$HOME/.tcshrc" "$HOME/.xonshrc" "$HOME/.config/elvish/rc.elv"; do
        [[ -f "$rc" ]] || continue
        if grep -qF "$marker" "$rc"; then
            sed -i '/^# linux_util:zsh_setup$/{N;d}' "$rc"
            info "Removed legacy Starship init from $rc"
        fi
    done

    if command -v nu &>/dev/null; then
        local nu_config
        nu_config=$(nu -c '$nu.data-dir' 2>/dev/null)
        local nu_file="${nu_config}/vendor/autoload/starship.nu"
        if [[ -f "$nu_file" ]]; then
            rm -f "$nu_file"
            info "Removed legacy Starship init from $nu_file"
        fi
    fi
}

_zsh_setup_deconfigure_shells() {
    _zsh_setup_remove_legacy_starship
    if [[ -f "$HOME/.zshrc" ]]; then
        sed -i 's/ zsh-autosuggestions//g; s/ zsh-syntax-highlighting//g' "$HOME/.zshrc"
        info "Removed custom plugins from ~/.zshrc"
    fi
}

_zsh_setup_install_p10k() {
    if [[ ! -d "$_P10K_THEME_DIR" ]]; then
        info "Installing Powerlevel10k..."
        git clone --depth=1 https://github.com/romkatv/powerlevel10k.git \
            "$_P10K_THEME_DIR" 2>/dev/null || { warn "Could not install Powerlevel10k."; return 1; }
    fi
}

_zsh_setup_remove_p10k_zshrc() {
    [[ -f "$HOME/.zshrc" ]] || return
    local tmpfile
    tmpfile=$(mktemp)

    # Remove instant prompt block (comment header + if/fi block + trailing blank line)
    awk '
      /^# Enable Powerlevel10k instant prompt/ { in_block=1 }
      in_block && /^fi$/ { in_block=0; drop_blank=1; next }
      drop_blank && /^[[:space:]]*$/ { drop_blank=0; next }
      in_block { next }
      { print }
    ' "$HOME/.zshrc" > "$tmpfile" && mv "$tmpfile" "$HOME/.zshrc"

    # Remove p10k source line
    tmpfile=$(mktemp)
    grep -v 'source ~/.p10k.zsh' "$HOME/.zshrc" > "$tmpfile" && mv "$tmpfile" "$HOME/.zshrc"
}

_zsh_setup_ensure_p10k_zshrc() {
    [[ -f "$HOME/.zshrc" ]] || return

    # Add instant prompt block at the top of .zshrc (needed for POWERLEVEL9K_INSTANT_PROMPT=verbose)
    if ! grep -qF 'Enable Powerlevel10k instant prompt' "$HOME/.zshrc"; then
        local tmpblock tmpfile
        tmpblock=$(mktemp)
        tmpfile=$(mktemp)
        cat > "$tmpblock" << 'EOF'
# Enable Powerlevel10k instant prompt. Should stay close to the top of ~/.zshrc.
# Initialization code that may require console input (password prompts, [y/n]
# confirmations, etc.) must go above this block; everything else may go below.
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

EOF
        cat "$tmpblock" "$HOME/.zshrc" > "$tmpfile" && mv "$tmpfile" "$HOME/.zshrc"
        rm -f "$tmpblock"
        info "Added Powerlevel10k instant prompt block to ~/.zshrc"
    fi

    # Add source line at the bottom of .zshrc so p10k config is applied on shell start
    if ! grep -qF 'source ~/.p10k.zsh' "$HOME/.zshrc"; then
        printf '\n[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh\n' >> "$HOME/.zshrc"
        info "Added p10k source line to ~/.zshrc"
    fi
}

_zsh_setup_select_theme() {
    # Resolve template dir relative to this file so it works regardless of SCRIPT_DIR
    local installer_dir
    installer_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local templates_dir="${installer_dir}/../templates/zsh"

    echo ""
    echo "${BOLD}${CYAN}Select a Zsh Theme:${RESET}"
    echo ""
    echo "  ${BOLD}Powerlevel10k${RESET}  (external, highly customizable — requires a Nerd Font)"
    echo "   1)  Custom config   — time on left, rainbow, large icons  ${DIM}← recommended${RESET}"
    echo "   2)  Wizard          — interactive step-by-step setup on first launch"
    echo ""
    echo "  ${BOLD}Built-in Oh My Zsh Themes${RESET}"
    printf "   %-4s %-15s %s\n" "3)"  "agnoster"     "${BOLD}${BLUE}❯${RESET} ${CYAN}user@host${RESET} ${BOLD}~/project${RESET} ${YELLOW}git:(${GREEN}main${YELLOW})${RESET} ${RED}✗${RESET}"
    printf "   %-4s %-15s %s\n" "4)"  "robbyrussell" "${GREEN}➜${RESET}  ${CYAN}~/project${RESET} ${BLUE}git:(${RED}main${BLUE})${RESET} ${RED}✗${RESET}  ${DIM}(OMZ default)${RESET}"
    printf "   %-4s %-15s %s\n" "5)"  "ys"           "${BOLD}#${RESET} ${GREEN}user${RESET} @ ${BOLD}${YELLOW}host${RESET} in ${BOLD}${BLUE}~/project${RESET} on ${CYAN}git:${YELLOW}main${RESET}"
    printf "   %-4s %-15s %s\n" "6)"  "af-magic"     "${DIM}---${RESET} ${CYAN}user@host${RESET} ${BOLD}~/project${RESET} | ${YELLOW}git:(main)${RESET}"
    printf "   %-4s %-15s %s\n" "7)"  "bira"         "${BLUE}╭─${RESET} ${GREEN}user${RESET} @ ${YELLOW}host${RESET} ${BOLD}${CYAN}~/project${RESET} ${MAGENTA}‹main›${RESET}"
    printf "   %-4s %-15s %s\n" "8)"  "bureau"       "${BOLD}${CYAN}user@host${RESET} ${YELLOW}[main]${RESET} ${GREEN}○${RESET}"
    printf "   %-4s %-15s %s\n" "9)"  "dst"          "${GREEN}user@host${RESET} ${BLUE}~/project${RESET} ${YELLOW}main${RESET} ${GREEN}○${RESET}"
    printf "   %-4s %-15s %s\n" "10)" "refined"      "${DIM}user@host${RESET} ${BOLD}${BLUE}~/project${RESET} ${YELLOW}‹main›${RESET}"
    printf "   %-4s %-15s %s\n" "11)" "steeef"       "${MAGENTA}user@host${RESET} ${CYAN}~/project${RESET} ${YELLOW}(main)${RESET}"
    printf "   %-4s %-15s %s\n" "12)" "jonathan"     "${DIM}───${RESET} ${GREEN}user${RESET} @ ${YELLOW}host${RESET} ${BOLD}~/project${RESET}  ${MAGENTA}git:(main)${RESET}"
    echo ""
    echo "  (q) Skip — keep current theme"
    echo ""

    local choice
    while true; do
        read -rp "  Choice [1-12, or q to skip]: " choice < /dev/tty
        case "$choice" in
            1)
                _zsh_setup_install_p10k || return 1
                local p10k_template="${templates_dir}/p10k.zsh"
                if [[ ! -f "$p10k_template" ]]; then
                    error "Bundled p10k config not found at ${p10k_template}. Cannot apply custom theme."
                    return 1
                fi
                cp "$p10k_template" "$HOME/.p10k.zsh" || { error "Failed to copy p10k config to ~/.p10k.zsh"; return 1; }
                _zsh_setup_apply_omz_theme "powerlevel10k/powerlevel10k"
                _zsh_setup_remove_p10k_zshrc
                _zsh_setup_ensure_p10k_zshrc
                info "Theme set: Powerlevel10k custom config (time on left)"
                log_info "Theme selected: Powerlevel10k custom config (time on left)"
                break ;;
            2)
                _zsh_setup_install_p10k || return 1
                _zsh_setup_remove_p10k_zshrc
                _zsh_setup_apply_omz_theme "powerlevel10k/powerlevel10k"
                rm -f "$HOME/.p10k.zsh"
                info "Theme selected: Powerlevel10k wizard (will run on next terminal launch)"
                log_info "Theme selected: Powerlevel10k wizard"
                break ;;
            3)  _zsh_setup_remove_p10k_zshrc; rm -f "$HOME/.p10k.zsh"; _zsh_setup_apply_omz_theme "agnoster";     break ;;
            4)  _zsh_setup_remove_p10k_zshrc; rm -f "$HOME/.p10k.zsh"; _zsh_setup_apply_omz_theme "robbyrussell"; break ;;
            5)  _zsh_setup_remove_p10k_zshrc; rm -f "$HOME/.p10k.zsh"; _zsh_setup_apply_omz_theme "ys";           break ;;
            6)  _zsh_setup_remove_p10k_zshrc; rm -f "$HOME/.p10k.zsh"; _zsh_setup_apply_omz_theme "af-magic";     break ;;
            7)  _zsh_setup_remove_p10k_zshrc; rm -f "$HOME/.p10k.zsh"; _zsh_setup_apply_omz_theme "bira";         break ;;
            8)  _zsh_setup_remove_p10k_zshrc; rm -f "$HOME/.p10k.zsh"; _zsh_setup_apply_omz_theme "bureau";       break ;;
            9)  _zsh_setup_remove_p10k_zshrc; rm -f "$HOME/.p10k.zsh"; _zsh_setup_apply_omz_theme "dst";          break ;;
            10) _zsh_setup_remove_p10k_zshrc; rm -f "$HOME/.p10k.zsh"; _zsh_setup_apply_omz_theme "refined";      break ;;
            11) _zsh_setup_remove_p10k_zshrc; rm -f "$HOME/.p10k.zsh"; _zsh_setup_apply_omz_theme "steeef";       break ;;
            12) _zsh_setup_remove_p10k_zshrc; rm -f "$HOME/.p10k.zsh"; _zsh_setup_apply_omz_theme "jonathan";     break ;;
            q|Q) info "Skipping theme selection."; break ;;
            *) echo "  Please enter 1-12 or q to skip." ;;
        esac
    done
}

install_zsh_setup() {
    info "Installing Zsh + Oh My Zsh..."
    ensure_tools

    # 1. Install Zsh
    if ! command -v zsh &>/dev/null; then
        case "$DISTRO_FAMILY" in
            debian)      sudo apt install -y zsh ;;
            fedora|rhel) sudo "$PKG_MGR" install -y zsh ;;
            arch)        sudo pacman -S --noconfirm zsh ;;
            suse)        sudo zypper install -y zsh ;;
        esac
    fi

    # 2. Install Oh My Zsh (unattended — skip chsh, no auto-launch)
    if [[ ! -d "$_OMZ_DIR" ]]; then
        info "Installing Oh My Zsh..."
        RUNZSH=no CHSH=no KEEP_ZSHRC=yes \
            sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" || {
            error "Oh My Zsh installation failed."
            return 1
        }
    else
        info "Oh My Zsh is already installed. Skipping."
    fi

    # 3. Install popular Zsh plugins
    local custom_dir="${ZSH_CUSTOM:-$_OMZ_DIR/custom}"

    if [[ ! -d "$custom_dir/plugins/zsh-autosuggestions" ]]; then
        git clone --depth=1 https://github.com/zsh-users/zsh-autosuggestions \
            "$custom_dir/plugins/zsh-autosuggestions" 2>/dev/null || true
    fi

    if [[ ! -d "$custom_dir/plugins/zsh-syntax-highlighting" ]]; then
        git clone --depth=1 https://github.com/zsh-users/zsh-syntax-highlighting \
            "$custom_dir/plugins/zsh-syntax-highlighting" 2>/dev/null || true
    fi

    # 4. Remove legacy Starship integration from older linux_util installs
    _zsh_setup_remove_legacy_starship

    # 5. Configure plugins in ~/.zshrc
    _zsh_setup_configure_plugins

    # 6. Select and apply a theme
    _zsh_setup_select_theme

    # 7. Set Zsh as the default shell
    local zsh_path
    zsh_path=$(command -v zsh)
    if [[ "$SHELL" != "$zsh_path" ]]; then
        info "Setting Zsh as the default shell for ${USER}..."
        grep -qF "$zsh_path" /etc/shells || echo "$zsh_path" | sudo tee -a /etc/shells > /dev/null
        chsh -s "$zsh_path" || warn "Could not change default shell. Run: chsh -s $zsh_path"
    fi

    info "Zsh + Oh My Zsh installed. Log out and back in for new terminals to use Zsh, or run 'zsh' to start it now."
}

uninstall_zsh_setup() {
    info "Uninstalling Zsh + Oh My Zsh..."

    _zsh_setup_deconfigure_shells

    rm -f "$HOME/.p10k.zsh"
    rm -rf "$_P10K_THEME_DIR"

    # Remove Oh My Zsh (pipe 'y' to bypass interactive confirmation prompt)
    if [[ -f "$_OMZ_DIR/tools/uninstall.sh" ]]; then
        echo "y" | env ZSH="$_OMZ_DIR" sh "$_OMZ_DIR/tools/uninstall.sh" --keep-zshrc 2>/dev/null || true
    fi
    rm -rf "$_OMZ_DIR"

    # Restore default shell to bash
    local bash_path
    bash_path=$(command -v bash)
    if [[ "$SHELL" != "$bash_path" ]]; then
        chsh -s "$bash_path" || warn "Could not restore shell to bash. Run: chsh -s $bash_path"
    fi

    case "$DISTRO_FAMILY" in
        debian)      sudo apt purge --autoremove -y zsh 2>/dev/null || true ;;
        fedora|rhel) sudo "$PKG_MGR" remove -y zsh 2>/dev/null || true ;;
        arch)        sudo pacman -Rs --noconfirm zsh 2>/dev/null || true ;;
        suse)        sudo zypper remove -y zsh 2>/dev/null || true ;;
    esac

    info "Zsh setup removed. Default shell set to bash (takes effect after you log out and back in)."
}

update_zsh_setup() {
    info "Updating Oh My Zsh..."

    if [[ -f "$_OMZ_DIR/tools/upgrade.sh" ]]; then
        env ZSH="$_OMZ_DIR" zsh "$_OMZ_DIR/tools/upgrade.sh" || true
    fi

    # Update plugins
    local custom_dir="${ZSH_CUSTOM:-$_OMZ_DIR/custom}"
    local plugin_dir
    for plugin_dir in "$custom_dir/plugins/"*/; do
        [[ -d "$plugin_dir/.git" ]] && git -C "$plugin_dir" pull --ff-only 2>/dev/null || true
    done

    # Update Powerlevel10k if installed
    if [[ -d "$_P10K_THEME_DIR/.git" ]]; then
        git -C "$_P10K_THEME_DIR" pull --ff-only 2>/dev/null || true
        info "Powerlevel10k updated."
    fi

    _zsh_setup_remove_legacy_starship
    _zsh_setup_configure_plugins

    echo ""
    while true; do
        read -rp "  Would you like to change your theme? [y/N]: " change_theme < /dev/tty
        case "${change_theme,,}" in
            y|yes) _zsh_setup_select_theme; break ;;
            n|no|'') break ;;
            *) echo "  Please enter Y or N." ;;
        esac
    done

    info "Zsh setup updated."
}

get_version_zsh_setup() {
    local zsh_ver
    zsh_ver=$(zsh --version 2>/dev/null | grep -oP '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
    if [[ -n "$zsh_ver" ]]; then
        echo "zsh ${zsh_ver}"
    else
        echo ""
    fi
}

#!/bin/bash
# Zsh + Oh My Zsh + Starship installer functions

# --- Zsh + Oh My Zsh ---

_OMZ_DIR="${ZSH:-$HOME/.oh-my-zsh}"

check_zsh_setup() {
    command -v zsh &>/dev/null && [[ -d "$_OMZ_DIR" ]]
}

_zsh_setup_configure_shells() {
    local marker="# linux_util:zsh_setup"

    # Ensure our OMZ plugins are in ~/.zshrc plugins=() line
    if [[ -f "$HOME/.zshrc" ]]; then
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
    fi

    # Starship init — zsh
    if command -v starship &>/dev/null && [[ -f "$HOME/.zshrc" ]]; then
        if ! grep -qF "$marker" "$HOME/.zshrc" 2>/dev/null; then
            printf '\n%s\neval "$(starship init zsh)"\n' "$marker" >> "$HOME/.zshrc"
            info "Added Starship init to ~/.zshrc"
        else
            info "Starship init already configured in ~/.zshrc"
        fi
    fi

    # Starship init — bash
    if command -v starship &>/dev/null && command -v bash &>/dev/null; then
        if [[ -f "$HOME/.bashrc" ]]; then
            local rc="$HOME/.bashrc"
            if ! grep -qF "$marker" "$rc" 2>/dev/null; then
                printf '\n%s\neval "$(starship init bash)"\n' "$marker" >> "$rc"
                info "Added Starship init to $rc"
            else
                info "Starship init already configured in $rc"
            fi
        elif [[ -L "$HOME/.bashrc" ]]; then
            info "~/.bashrc is a broken symlink — skipping Starship init for bash"
        else
            info "bash installed but ~/.bashrc not found — skipping Starship init for bash"
        fi
    fi

    # Starship init — fish
    if command -v starship &>/dev/null && command -v fish &>/dev/null; then
        local rc="$HOME/.config/fish/config.fish"
        mkdir -p "$(dirname "$rc")"
        if ! grep -qF "$marker" "$rc" 2>/dev/null; then
            printf '\n%s\nstarship init fish | source\n' "$marker" >> "$rc"
            info "Added Starship init to $rc"
        else
            info "Starship init already configured in $rc"
        fi
    fi

    # Starship init — tcsh
    if command -v starship &>/dev/null && command -v tcsh &>/dev/null && [[ -f "$HOME/.tcshrc" ]]; then
        local rc="$HOME/.tcshrc"
        if ! grep -qF "$marker" "$rc" 2>/dev/null; then
            printf '\n%s\neval \`starship init tcsh\`\n' "$marker" >> "$rc"
            info "Added Starship init to $rc"
        else
            info "Starship init already configured in $rc"
        fi
    fi

    # Starship init — xonsh
    if command -v starship &>/dev/null && command -v xonsh &>/dev/null && [[ -f "$HOME/.xonshrc" ]]; then
        local rc="$HOME/.xonshrc"
        if ! grep -qF "$marker" "$rc" 2>/dev/null; then
            printf '\n%s\nexecx($(starship init xonsh))\n' "$marker" >> "$rc"
            info "Added Starship init to $rc"
        else
            info "Starship init already configured in $rc"
        fi
    fi

    # Starship init — elvish
    if command -v starship &>/dev/null && command -v elvish &>/dev/null; then
        local rc="$HOME/.config/elvish/rc.elv"
        mkdir -p "$(dirname "$rc")"
        if ! grep -qF "$marker" "$rc" 2>/dev/null; then
            printf '\n%s\neval (starship init elvish)\n' "$marker" >> "$rc"
            info "Added Starship init to $rc"
        else
            info "Starship init already configured in $rc"
        fi
    fi

    # Starship init — nushell
    if command -v starship &>/dev/null && command -v nu &>/dev/null; then
        local nu_config
        nu_config=$(nu -c '$nu.data-dir' 2>/dev/null)
        if [[ -n "$nu_config" ]]; then
            local nu_autoload="$nu_config/vendor/autoload"
            mkdir -p "$nu_autoload"
            local nu_file="$nu_autoload/starship.nu"
            if [[ ! -f "$nu_file" ]]; then
                starship init nu | nu --stdin -c 'save -f ("'"$nu_file"'")' 2>/dev/null || \
                    starship init nu > "$nu_file"
                info "Added Starship init to $nu_file"
            else
                info "Starship init already configured in $nu_file"
            fi
        fi
    fi
}

_zsh_setup_deconfigure_shells() {
    local marker="# linux_util:zsh_setup"
    local rc

    # Remove Starship init marker+line from all shell RCs
    for rc in "$HOME/.zshrc" "$HOME/.bashrc" "$HOME/.config/fish/config.fish" \
              "$HOME/.tcshrc" "$HOME/.xonshrc" "$HOME/.config/elvish/rc.elv"; do
        [[ -f "$rc" ]] || continue
        if grep -qF "$marker" "$rc"; then
            sed -i '/^# linux_util:zsh_setup$/{N;d}' "$rc"
            info "Removed Starship init from $rc"
        fi
    done

    # Remove nushell starship autoload file
    if command -v nu &>/dev/null; then
        local nu_config
        nu_config=$(nu -c '$nu.data-dir' 2>/dev/null)
        local nu_file="${nu_config}/vendor/autoload/starship.nu"
        if [[ -f "$nu_file" ]]; then
            rm -f "$nu_file"
            info "Removed Starship init from $nu_file"
        fi
    fi

    # Remove our plugins from the plugins=() line in ~/.zshrc
    if [[ -f "$HOME/.zshrc" ]]; then
        sed -i 's/ zsh-autosuggestions//g; s/ zsh-syntax-highlighting//g' "$HOME/.zshrc"
        info "Removed custom plugins from ~/.zshrc"
    fi
}

install_zsh_setup() {
    info "Installing Zsh + Oh My Zsh + Starship..."
    ensure_tools

    # 1. Install Zsh
    if ! command -v zsh &>/dev/null; then
        case "$DISTRO_FAMILY" in
            debian)  sudo apt install -y zsh ;;
            fedora|rhel) sudo "$PKG_MGR" install -y zsh ;;
            arch)    sudo pacman -S --noconfirm zsh ;;
            suse)    sudo zypper install -y zsh ;;
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

    # zsh-autosuggestions
    if [[ ! -d "$custom_dir/plugins/zsh-autosuggestions" ]]; then
        git clone --depth=1 https://github.com/zsh-users/zsh-autosuggestions \
            "$custom_dir/plugins/zsh-autosuggestions" 2>/dev/null || true
    fi

    # zsh-syntax-highlighting
    if [[ ! -d "$custom_dir/plugins/zsh-syntax-highlighting" ]]; then
        git clone --depth=1 https://github.com/zsh-users/zsh-syntax-highlighting \
            "$custom_dir/plugins/zsh-syntax-highlighting" 2>/dev/null || true
    fi

    # 4. Install Starship prompt
    if ! command -v starship &>/dev/null; then
        info "Installing Starship prompt..."
        curl -fsSL https://starship.rs/install.sh | sh -s -- --yes || \
            warn "Starship installation failed. You can install it later from starship.rs."
    fi

    # 5. Set Zsh as the default shell
    local zsh_path
    zsh_path=$(command -v zsh)
    if [[ "$SHELL" != "$zsh_path" ]]; then
        info "Setting Zsh as the default shell for ${USER}..."
        # Ensure zsh is in /etc/shells
        grep -qF "$zsh_path" /etc/shells || echo "$zsh_path" | sudo tee -a /etc/shells > /dev/null
        chsh -s "$zsh_path" || warn "Could not change default shell. Run: chsh -s $zsh_path"
    fi

    _zsh_setup_configure_shells
    info "Zsh + Oh My Zsh + Starship installed. Open a new terminal or run 'zsh' to start using it."
}

uninstall_zsh_setup() {
    info "Uninstalling Zsh + Oh My Zsh + Starship..."

    _zsh_setup_deconfigure_shells

    # Remove Oh My Zsh (pipe 'y' to bypass interactive confirmation prompt)
    if [[ -f "$_OMZ_DIR/tools/uninstall.sh" ]]; then
        echo "y" | env ZSH="$_OMZ_DIR" sh "$_OMZ_DIR/tools/uninstall.sh" --keep-zshrc 2>/dev/null || true
    fi
    rm -rf "$_OMZ_DIR"

    # Remove Starship
    if command -v starship &>/dev/null; then
        sudo rm -f "$(command -v starship)"
    fi
    rm -f "$HOME/.config/starship.toml"

    # Restore default shell to bash
    local bash_path
    bash_path=$(command -v bash)
    if [[ "$SHELL" != "$bash_path" ]]; then
        chsh -s "$bash_path" || warn "Could not restore shell to bash. Run: chsh -s $bash_path"
    fi

    # Remove Zsh package (optional — only if nothing else uses it)
    case "$DISTRO_FAMILY" in
        debian)  sudo apt purge --autoremove -y zsh 2>/dev/null || true ;;
        fedora|rhel) sudo "$PKG_MGR" remove -y zsh 2>/dev/null || true ;;
        arch)    sudo pacman -Rs --noconfirm zsh 2>/dev/null || true ;;
        suse)    sudo zypper remove -y zsh 2>/dev/null || true ;;
    esac

    info "Zsh setup removed. Default shell restored to bash."
}

update_zsh_setup() {
    info "Updating Oh My Zsh + Starship..."

    # Update Oh My Zsh
    if [[ -f "$_OMZ_DIR/tools/upgrade.sh" ]]; then
        env ZSH="$_OMZ_DIR" zsh "$_OMZ_DIR/tools/upgrade.sh" || true
    fi

    # Update plugins
    local custom_dir="${ZSH_CUSTOM:-$_OMZ_DIR/custom}"
    local plugin_dir
    for plugin_dir in "$custom_dir/plugins/"*/; do
        [[ -d "$plugin_dir/.git" ]] && git -C "$plugin_dir" pull --ff-only 2>/dev/null || true
    done

    # Update Starship
    if command -v starship &>/dev/null; then
        curl -fsSL https://starship.rs/install.sh | sh -s -- --yes || true
    fi

    _zsh_setup_configure_shells
    info "Zsh setup updated."
}

get_version_zsh_setup() {
    local zsh_ver starship_ver
    zsh_ver=$(zsh --version 2>/dev/null | grep -oP '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
    starship_ver=$(starship --version 2>/dev/null | grep -oP '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
    if [[ -n "$zsh_ver" && -n "$starship_ver" ]]; then
        echo "zsh ${zsh_ver} / starship ${starship_ver}"
    elif [[ -n "$zsh_ver" ]]; then
        echo "zsh ${zsh_ver}"
    else
        echo ""
    fi
}

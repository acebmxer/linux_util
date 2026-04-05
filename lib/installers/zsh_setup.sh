#!/bin/bash
# Zsh + Oh My Zsh + Starship installer functions

# --- Zsh + Oh My Zsh ---

_OMZ_DIR="${ZSH:-$HOME/.oh-my-zsh}"

check_zsh_setup() {
    command -v zsh &>/dev/null && [[ -d "$_OMZ_DIR" ]]
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

    info "Zsh + Oh My Zsh + Starship installed."
    info "Plugins enabled: zsh-autosuggestions, zsh-syntax-highlighting."
    info "Add them to your ~/.zshrc plugins list: plugins=(git zsh-autosuggestions zsh-syntax-highlighting)"
    info "Add 'eval \"\$(starship init zsh)\"' to ~/.zshrc to enable Starship."
    info "Open a new terminal or run 'zsh' to start using it."
}

uninstall_zsh_setup() {
    info "Uninstalling Zsh + Oh My Zsh + Starship..."

    # Remove Oh My Zsh
    if [[ -f "$_OMZ_DIR/tools/uninstall.sh" ]]; then
        env ZSH="$_OMZ_DIR" sh "$_OMZ_DIR/tools/uninstall.sh" --keep-zshrc 2>/dev/null || true
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

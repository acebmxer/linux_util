#!/bin/bash
# pyenv Python version manager installer functions

# --- pyenv ---

_PYENV_DIR="${PYENV_ROOT:-$HOME/.pyenv}"

check_pyenv() {
    _have_cmd pyenv || [[ -f "$_PYENV_DIR/bin/pyenv" ]]
}

install_pyenv() {
    info "Installing pyenv..."
    ensure_tools

    # Install build dependencies needed to compile Python versions
    info "Installing Python build dependencies..."
    case "$DISTRO_FAMILY" in
        debian)
            sudo apt install -y make build-essential libssl-dev zlib1g-dev \
                libbz2-dev libreadline-dev libsqlite3-dev wget curl llvm \
                libncursesw5-dev xz-utils tk-dev libxml2-dev libxmlsec1-dev \
                libffi-dev liblzma-dev git
            ;;
        fedora|rhel)
            sudo "$PKG_MGR" install -y make gcc zlib-devel bzip2 bzip2-devel \
                readline-devel sqlite sqlite-devel openssl-devel tk-devel \
                libffi-devel xz-devel git
            ;;
        arch)
            sudo pacman -S --noconfirm base-devel openssl zlib xz tk git
            ;;
        suse)
            sudo zypper install -y gcc make zlib-devel bzip2 libbz2-devel \
                readline-devel sqlite3-devel openssl-devel tk-devel libffi-devel git
            ;;
    esac

    if [[ -d "$_PYENV_DIR/.git" ]]; then
        info "pyenv directory already exists. Updating..."
        git -C "$_PYENV_DIR" pull --quiet
    else
        git clone https://github.com/pyenv/pyenv.git "$_PYENV_DIR"
    fi

    # Build optional dynamic bash extension for speed
    ( cd "$_PYENV_DIR" && src/configure 2>/dev/null && make -C src 2>/dev/null ) || true

    # Inject pyenv init into shell RC files
    local _init_block='
# pyenv
export PYENV_ROOT="$HOME/.pyenv"
[[ -d "$PYENV_ROOT/bin" ]] && export PATH="$PYENV_ROOT/bin:$PATH"
eval "$(pyenv init -)"'

    for rc in "$HOME/.bashrc" "$HOME/.zshrc"; do
        [[ -f "$rc" ]] || continue
        if ! grep -q 'PYENV_ROOT' "$rc"; then
            echo "$_init_block" >> "$rc"
        fi
    done

    info "pyenv installed."
    info "Restart your shell or run: source ~/.bashrc"
    info "Then use 'pyenv install <version>' to install Python versions."
}

uninstall_pyenv() {
    info "Uninstalling pyenv..."
    rm -rf "$_PYENV_DIR"
    for rc in "$HOME/.bashrc" "$HOME/.zshrc" "$HOME/.profile"; do
        [[ -f "$rc" ]] || continue
        sed -i '/# pyenv/d;/PYENV_ROOT/d;/pyenv init/d' "$rc" 2>/dev/null || true
    done
    info "pyenv uninstalled."
}

update_pyenv() {
    info "Updating pyenv..."
    if [[ -d "$_PYENV_DIR/.git" ]]; then
        git -C "$_PYENV_DIR" pull
        ( cd "$_PYENV_DIR" && src/configure 2>/dev/null && make -C src 2>/dev/null ) || true
        info "pyenv updated."
    else
        install_pyenv
    fi
}

get_version_pyenv() {
    if _have_cmd pyenv; then
        _run_native pyenv --version 2>/dev/null | grep -oP 'pyenv \K[0-9]+\.[0-9]+\.[0-9]+' || echo ""
    elif [[ -f "$_PYENV_DIR/bin/pyenv" ]]; then
        "$_PYENV_DIR/bin/pyenv" --version 2>/dev/null | grep -oP 'pyenv \K[0-9]+\.[0-9]+\.[0-9]+' || echo ""
    else
        echo ""
    fi
}

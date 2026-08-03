#!/bin/bash
# Rustup — Rust toolchain installer functions

# --- Rustup ---

_RUSTUP_HOME="${RUSTUP_HOME:-$HOME/.rustup}"
_CARGO_HOME="${CARGO_HOME:-$HOME/.cargo}"

check_rustup() {
    _have_cmd rustup || [[ -f "$_CARGO_HOME/bin/rustup" ]]
}

install_rustup() {
    info "Installing Rust via rustup..."
    ensure_tools
    # The official rustup installer script
    if ! curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --no-modify-path; then
        error "rustup installation script failed."
        return 1
    fi
    # Source cargo env for the current session
    # shellcheck disable=SC1091
    [[ -f "$_CARGO_HOME/env" ]] && source "$_CARGO_HOME/env" 2>/dev/null || true
    info "Rust toolchain installed."
    info "Run 'source ~/.cargo/env' or restart your shell to use rustc/cargo."
    info "Use 'rustup update' to keep the toolchain current."
}

uninstall_rustup() {
    info "Uninstalling Rust toolchain..."
    local _rustup_bin="$_CARGO_HOME/bin/rustup"
    if command -v rustup &>/dev/null; then
        rustup self uninstall -y
    elif [[ -f "$_rustup_bin" ]]; then
        "$_rustup_bin" self uninstall -y
    else
        # Manual cleanup if rustup binary is gone but directories remain
        rm -rf "$_RUSTUP_HOME" "$_CARGO_HOME"
        for rc in "$HOME/.bashrc" "$HOME/.zshrc" "$HOME/.profile" "$HOME/.bash_profile"; do
            [[ -f "$rc" ]] || continue
            sed -i '/\.cargo\/env/d;/CARGO_HOME/d;/RUSTUP_HOME/d' "$rc" 2>/dev/null || true
        done
    fi
    info "Rust toolchain uninstalled."
}

update_rustup() {
    info "Updating Rust toolchain..."
    local _rustup_bin="$_CARGO_HOME/bin/rustup"
    if command -v rustup &>/dev/null; then
        rustup update
    elif [[ -f "$_rustup_bin" ]]; then
        "$_rustup_bin" update
    else
        install_rustup
    fi
}

get_version_rustup() {
    local _rustup_bin="$_CARGO_HOME/bin/rustup"
    if _have_cmd rustup; then
        _run_native rustup --version 2>/dev/null | grep -oP 'rustup \K[0-9]+\.[0-9]+\.[0-9]+' || echo ""
    elif [[ -f "$_rustup_bin" ]]; then
        "$_rustup_bin" --version 2>/dev/null | grep -oP 'rustup \K[0-9]+\.[0-9]+\.[0-9]+' || echo ""
    else
        echo ""
    fi
}

#!/bin/bash
# JetBrains Toolbox installer functions

# --- JetBrains Toolbox ---

_JB_TOOLBOX_BIN="$HOME/.local/share/JetBrains/Toolbox/bin/jetbrains-toolbox"

check_jetbrains_toolbox() {
    command -v jetbrains-toolbox &>/dev/null || [[ -f "$_JB_TOOLBOX_BIN" ]]
}

install_jetbrains_toolbox() {
    info "Installing JetBrains Toolbox..."
    ensure_tools

    # Fetch latest download URL from JetBrains data API
    local api_url="https://data.services.jetbrains.com/products/releases?code=TBA&latest=true&type=release"
    local download_url
    download_url=$(curl -fsSL "$api_url" | grep -oP '"linux"\s*:\s*\{[^}]*"link"\s*:\s*"\K[^"]+' | head -1)

    if [[ -z "$download_url" ]]; then
        # Fallback: scrape the toolbox download page
        download_url=$(curl -fsSL "https://www.jetbrains.com/toolbox-app/download/download-thanks.html?platform=linux" \
            | grep -oP 'https://download\.jetbrains\.com/toolbox/jetbrains-toolbox-[^"]+\.tar\.gz' | head -1)
    fi

    if [[ -z "$download_url" ]]; then
        error "Failed to retrieve JetBrains Toolbox download URL."
        return 1
    fi

    local tmpfile
    tmpfile=$(mktemp /tmp/jetbrains-toolbox-XXXXXX.tar.gz)
    CLEANUP_FILES+=("$tmpfile")

    info "Downloading JetBrains Toolbox..."
    if ! wget -qO "$tmpfile" "$download_url"; then
        error "Failed to download JetBrains Toolbox."
        return 1
    fi
    verify_download "$tmpfile" "tar.gz" "JetBrains Toolbox" || return 1

    local tmpdir
    tmpdir=$(mktemp -d)
    tar -xzf "$tmpfile" -C "$tmpdir"

    local toolbox_bin
    toolbox_bin=$(find "$tmpdir" -name "jetbrains-toolbox" -type f | head -1)
    if [[ -z "$toolbox_bin" ]]; then
        rm -rf "$tmpdir"
        error "Could not locate jetbrains-toolbox binary in archive."
        return 1
    fi

    mkdir -p "$(dirname "$_JB_TOOLBOX_BIN")"
    cp "$toolbox_bin" "$_JB_TOOLBOX_BIN"
    chmod +x "$_JB_TOOLBOX_BIN"
    rm -rf "$tmpdir"

    # Create symlink on PATH
    mkdir -p "$HOME/.local/bin"
    ln -sf "$_JB_TOOLBOX_BIN" "$HOME/.local/bin/jetbrains-toolbox"

    # Launch Toolbox once so it registers itself (runs in background)
    nohup "$_JB_TOOLBOX_BIN" &>/dev/null &
    info "JetBrains Toolbox installed. It will launch shortly to complete setup."
}

uninstall_jetbrains_toolbox() {
    info "Uninstalling JetBrains Toolbox..."
    # Kill running instance
    pkill -f "jetbrains-toolbox" 2>/dev/null || true
    rm -f "$HOME/.local/bin/jetbrains-toolbox"
    rm -rf "$HOME/.local/share/JetBrains/Toolbox"
    rm -f "$HOME/.local/share/applications/jetbrains-toolbox.desktop"
    rm -rf "$HOME/.config/JetBrains/Toolbox"
    info "JetBrains Toolbox uninstalled. Installed IDEs were not removed."
}

update_jetbrains_toolbox() {
    info "Updating JetBrains Toolbox..."
    # Toolbox updates itself; just re-run the installer to force an update
    install_jetbrains_toolbox
}

get_version_jetbrains_toolbox() {
    if [[ -f "$_JB_TOOLBOX_BIN" ]]; then
        "$_JB_TOOLBOX_BIN" --version 2>/dev/null | grep -oP '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo ""
    else
        echo ""
    fi
}

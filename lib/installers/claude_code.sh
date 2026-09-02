#!/bin/bash
# Claude Code (Anthropic CLI) installer functions

# --- Claude Code ---

# Ensure Node.js (and npm) are installed, installing them if absent.
# For Debian/Ubuntu the NodeSource Node 20 LTS repo is used to guarantee
# a recent enough version (Claude Code requires Node 18+).
_ensure_nodejs() {
    if command -v node &>/dev/null && command -v npm &>/dev/null; then
        return 0
    fi

    echo "Node.js not found. Installing Node.js..."

    case "$DISTRO_FAMILY" in
        debian)
            # Use NodeSource for Node 20 LTS to ensure a modern enough version.
            local nodesource_tmp
            nodesource_tmp=$(mktemp /tmp/nodesource-setup-XXXXXX.sh)
            CLEANUP_FILES+=("$nodesource_tmp")
            if ! curl -fsSL https://deb.nodesource.com/setup_24.x -o "$nodesource_tmp"; then
                echo "Error: Failed to download NodeSource setup script."
                return 1
            fi
            sudo bash "$nodesource_tmp"
            sudo apt install -y nodejs
            # Ubuntu packages the binary as 'nodejs'; create a 'node' symlink if needed.
            if ! command -v node &>/dev/null && command -v nodejs &>/dev/null; then
                sudo ln -sf "$(command -v nodejs)" /usr/local/bin/node
            fi
            # npm is a separate package on some Ubuntu/Kubuntu releases.
            if ! command -v npm &>/dev/null; then
                sudo apt install -y npm
            fi
            ;;
        fedora|rhel)
            sudo "$PKG_MGR" install -y nodejs npm
            ;;
        arch)
            sudo pacman -S --noconfirm nodejs npm
            ;;
        suse)
            sudo zypper install -y nodejs npm
            ;;
        *)
            echo "Error: Unsupported distro family '${DISTRO_FAMILY}' for Node.js installation."
            return 1
            ;;
    esac

    if ! command -v node &>/dev/null || ! command -v npm &>/dev/null; then
        echo "Error: Node.js installation failed — 'node' or 'npm' not found after install."
        return 1
    fi

    echo "Node.js $(node --version) installed successfully."
    return 0
}

check_claude_code() {
    _have_cmd claude
}

# Install the npm package and make sure the native binary is actually in place.
#
# npm 12 blocks package lifecycle scripts by default (supply-chain hardening),
# so @anthropic-ai/claude-code's postinstall never runs. That postinstall is what
# replaces the small bin/claude.exe placeholder with the real native binary, so
# without it `claude` only prints "claude native binary not installed" — while
# npm itself still exits 0, leaving the install looking successful.
#
# Running install.cjs directly afterwards is version-agnostic: it is a no-op on
# npm versions that already ran the postinstall, and repairs the install on npm
# 12+. This is deliberately not gated on npm version or distro, since distros
# adopt npm 12 at different times.
_claude_code_finish_install() {
    local pkg_dir
    pkg_dir="$(npm root -g 2>/dev/null)/@anthropic-ai/claude-code"

    if [[ -f "$pkg_dir/install.cjs" ]]; then
        sudo node "$pkg_dir/install.cjs" || true
    fi

    # Verify the binary really works rather than trusting npm's exit code.
    if ! _run_native claude --version &>/dev/null; then
        echo "Error: Claude Code installed but the 'claude' command is not working."
        echo "  Try: sudo node ${pkg_dir}/install.cjs"
        return 1
    fi

    return 0
}

install_claude_code() {
    echo "Installing Claude Code..."
    ensure_tools
    _ensure_nodejs || return 1
    sudo npm install -g @anthropic-ai/claude-code || return 1
    _claude_code_finish_install
}

uninstall_claude_code() {
    echo "Uninstalling Claude Code..."
    # Remove the Claude Code npm package only; Node.js is left in place
    # because the user may have other projects that depend on it.
    sudo npm uninstall -g @anthropic-ai/claude-code
}

update_claude_code() {
    echo "Updating Claude Code..."
    _ensure_nodejs || return 1
    # Re-installing the package via npm always fetches the latest published version.
    sudo npm install -g @anthropic-ai/claude-code || return 1
    _claude_code_finish_install
}


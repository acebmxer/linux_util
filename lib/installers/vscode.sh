#!/bin/bash
# Visual Studio Code installer functions
#
# Microsoft publishes no pacman repository -- packages.microsoft.com serves apt
# and yum repos only, and their Linux docs send Arch users to the AUR, which
# this tool keeps disabled. They DO publish a distro-agnostic x64 tarball, and
# that tarball is exactly what the AUR's visual-studio-code-bin repackages, so
# the Arch path fetches it straight from the vendor instead of going through an
# unreviewed PKGBUILD. Installed per-user under ~/.local: no root needed, and
# VS Code keeps its state in ~/.config/Code and ~/.vscode either way.
#
# The endpoint publishes no checksum or signature alongside the tarball (the AUR
# PKGBUILD does not verify one either) -- HTTPS to the vendor is the guarantee,
# same as the Termius and Zen Browser upstream paths.

# --- Visual Studio Code ---

_VSCODE_TARBALL_URL="https://update.code.visualstudio.com/latest/linux-x64/stable"
_VSCODE_DIR="$HOME/.local/share/vscode"
_VSCODE_WRAPPER="$HOME/.local/bin/code"
_VSCODE_DESKTOP="$HOME/.local/share/applications/code.desktop"
_VSCODE_ICON="$HOME/.local/share/icons/hicolor/512x512/apps/vscode.png"

check_vscode() {
    [[ -x "$_VSCODE_DIR/bin/code" ]] && return 0
    _check_standard code code "" visual-studio-code-bin
}

# Install the official Microsoft tarball per-user. Used as the upstream-binary
# tier of arch_install_ordered, so it runs only after the repos and Flathub have
# been tried and before the (disabled) AUR tier.
# Latest stable version Microsoft publishes for linux-x64. The update API returns
# JSON carrying productVersion; one small request, no download.
_vscode_latest_version() {
    curl -fsSL --max-time 15 \
        "https://update.code.visualstudio.com/api/update/linux-x64/stable/latest" 2>/dev/null \
        | grep -oP '"productVersion"\s*:\s*"\K[^"]+' | head -1
}

_vscode_install_tarball() {
    local tmpdir tmptar
    # Nothing to do when the installed tree is already the published build.
    # The tarball is ~330 MB, so re-fetching an identical build on every update
    # run is the whole cost of the operation for no result. An unknown version
    # (offline, API changed) falls through and installs, so a genuine update is
    # never skipped on the strength of a failed lookup.
    if [[ "${VSCODE_FORCE_REINSTALL:-0}" != "1" && -d "$_VSCODE_DIR" ]]; then
        local _cmp=0
        upstream_update_available "Visual Studio Code" || _cmp=$?
        if (( _cmp == 1 )); then
            info "Visual Studio Code is already at the latest version ($(get_version_vscode)); nothing to download."
            return 0
        fi
    fi
    tmpdir=$(mktemp -d /tmp/vscode-XXXXXX) || return 1
    CLEANUP_FILES+=("$tmpdir")
    tmptar="$tmpdir/vscode.tar.gz"

    # ~330 MB, so download_file's 30s curl timeout is far too short (see the
    # same note in the OCCT installer). -sS keeps the progress meter out of the
    # menu UI while still printing real errors.
    info "Downloading Visual Studio Code from Microsoft (large download, please be patient)..."
    if ! curl -fsSL --max-time 1800 --retry 2 -o "$tmptar" "$_VSCODE_TARBALL_URL"; then
        error "Failed to download the Visual Studio Code tarball."
        return 1
    fi
    verify_download "$tmptar" "tar.gz" "Visual Studio Code" || return 1

    mkdir -p "$tmpdir/payload"
    tar -xzf "$tmptar" -C "$tmpdir/payload" || {
        error "Failed to extract the Visual Studio Code tarball."
        return 1
    }

    # The archive holds one top-level directory (VSCode-linux-x64). Match it by
    # shape rather than by name so a rename upstream does not break the install.
    local src
    src=$(find "$tmpdir/payload" -mindepth 1 -maxdepth 1 -type d | head -1)
    if [[ -z "$src" || ! -x "$src/bin/code" ]]; then
        error "Unpacked Visual Studio Code payload is missing bin/code."
        return 1
    fi

    # Replace the tree wholesale so no file from an older build survives an
    # update. Safe to delete: user data and extensions live in ~/.config/Code
    # and ~/.vscode, never inside the install directory.
    rm -rf "$_VSCODE_DIR"
    mkdir -p "$(dirname "$_VSCODE_DIR")" "$HOME/.local/bin" \
             "$HOME/.local/share/applications" "$(dirname "$_VSCODE_ICON")"
    mv "$src" "$_VSCODE_DIR" || {
        error "Failed to install Visual Studio Code to ${_VSCODE_DIR}."
        return 1
    }

    ln -sfn "$_VSCODE_DIR/bin/code" "$_VSCODE_WRAPPER"
    cp "$_VSCODE_DIR/resources/app/resources/linux/code.png" "$_VSCODE_ICON" 2>/dev/null || true

    cat > "$_VSCODE_DESKTOP" <<EOF
[Desktop Entry]
Type=Application
Name=Visual Studio Code
GenericName=Text Editor
Comment=Code Editing. Redefined.
Exec=$_VSCODE_WRAPPER %F
Icon=vscode
Terminal=false
StartupNotify=true
StartupWMClass=Code
Categories=TextEditor;Development;IDE;
MimeType=text/plain;inode/directory;
Keywords=vscode;
EOF
    refresh_desktop_caches
    info "Visual Studio Code installed to ${_VSCODE_DIR}. Ensure ~/.local/bin is in your PATH."
}

# Remove a tarball install. Returns 1 when there was nothing to remove, so the
# caller can tell the difference between "cleaned up" and "not installed here".
_vscode_remove_tarball() {
    [[ -d "$_VSCODE_DIR" ]] || return 1
    rm -rf "$_VSCODE_DIR"
    rm -f "$_VSCODE_WRAPPER" "$_VSCODE_DESKTOP" "$_VSCODE_ICON"
    refresh_desktop_caches
    return 0
}
install_vscode() {
    echo "Installing Visual Studio Code..."
    ensure_tools
    case "$DISTRO_FAMILY" in
        debian)
            local gpg_tmp
            gpg_tmp=$(mktemp /tmp/vscode-gpg-XXXXXX)
            CLEANUP_FILES+=("$gpg_tmp")
            wget -qO- https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor > "$gpg_tmp"
            sudo install -D -o root -g root -m 644 "$gpg_tmp" /etc/apt/keyrings/packages.microsoft.gpg
            echo "deb [arch=amd64,arm64,armhf signed-by=/etc/apt/keyrings/packages.microsoft.gpg] https://packages.microsoft.com/repos/code stable main" | \
                sudo tee /etc/apt/sources.list.d/vscode.list > /dev/null
            rm -f "$gpg_tmp"
            sudo apt update
            sudo apt install -y code
            ;;
        fedora|rhel)
            sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc
            printf "[code]\nname=Visual Studio Code\nbaseurl=https://packages.microsoft.com/yumrepos/vscode\nenabled=1\ngpgcheck=1\ngpgkey=https://packages.microsoft.com/keys/microsoft.asc\n" | \
                sudo tee /etc/yum.repos.d/vscode.repo > /dev/null
            sudo "$PKG_MGR" install -y code
            ;;
        arch)
            # repos -> Flathub -> Microsoft's own tarball -> AUR (disabled by default).
            arch_install_ordered "visual-studio-code-bin" "com.visualstudio.code" \
                "_vscode_install_tarball" "visual-studio-code-bin"
            ;;
        suse)
            sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc
            printf "[code]\nname=Visual Studio Code\nbaseurl=https://packages.microsoft.com/yumrepos/vscode\nenabled=1\ntype=rpm-md\ngpgcheck=1\ngpgkey=https://packages.microsoft.com/keys/microsoft.asc\n" | \
                sudo tee /etc/zypp/repos.d/vscode.repo > /dev/null
            sudo zypper refresh
            sudo zypper install -y code
            ;;
    esac
}
uninstall_vscode() {
    echo "Uninstalling Visual Studio Code..."
    case "$DISTRO_FAMILY" in
        debian)
            sudo apt purge --autoremove -y code
            sudo apt autoclean
            sudo rm -f /etc/apt/sources.list.d/vscode.list
            sudo rm -f /etc/apt/keyrings/packages.microsoft.gpg
            ;;
        fedora|rhel)
            sudo "$PKG_MGR" remove -y code
            sudo rm -f /etc/yum.repos.d/vscode.repo
            ;;
        arch)
            # The tarball copy and a packaged copy are independent -- clear both,
            # and only reach for the package managers when a package is present
            # so a tarball-only install does not print removal errors.
            local removed_tarball=0
            _vscode_remove_tarball && removed_tarball=1
            if pkg_check_installed visual-studio-code-bin || pkg_check_installed code; then
                aur_remove visual-studio-code-bin 2>/dev/null || pkg_remove code 2>/dev/null || true
            elif (( ! removed_tarball )); then
                echo "Visual Studio Code installation not found."
            fi
            ;;
        suse)
            sudo zypper remove -y code
            sudo rm -f /etc/zypp/repos.d/vscode.repo
            ;;
    esac
    rm -rf ~/.config/Code
    rm -rf ~/.vscode
}
update_vscode() {
    echo "Updating Visual Studio Code..."
    case "$DISTRO_FAMILY" in
        debian)
            sudo apt update
            sudo apt install -y --only-upgrade code
            ;;
        arch)
            # repos -> Flathub -> Microsoft's own tarball -> AUR (disabled by default).
            arch_install_ordered "visual-studio-code-bin" "com.visualstudio.code" \
                "_vscode_install_tarball" "visual-studio-code-bin"
            ;;
        *)
            pkg_upgrade code
            ;;
    esac
}
get_version_vscode() {
    # Read the tarball copy's metadata directly: ~/.local/bin may not be on PATH,
    # and package.json is authoritative for the build that is actually installed.
    local v=""
    if [[ -f "$_VSCODE_DIR/resources/app/package.json" ]]; then
        v=$(grep -oP '"version"\s*:\s*"\K[^"]+' "$_VSCODE_DIR/resources/app/package.json" | head -1)
        [[ -n "$v" ]] && { printf '%s\n' "$v"; return 0; }
    fi
    _run_native code --version 2>/dev/null | head -1 || echo ""
}

#!/bin/bash
# VSCodium installer functions
#
# VSCodium is the community build of Microsoft's vscode source with the
# telemetry, branding, and proprietary-marketplace bits removed. It installs
# alongside Visual Studio Code without conflict -- different binary (codium),
# different config (~/.config/VSCodium), different extension dir
# (~/.vscode-oss) -- so both may be registered at once.
#
# The .deb/.rpm repos are the ones vscodium.com points at: built and signed by
# the paulcarroty repo project, served from download.vscodium.com (an alias for
# the same paulcarroty.gitlab.io pages site named in its README). The rpm side
# publishes a detached repomd signature, so repo_gpgcheck is on as well.
#
# There is no official Arch repository package -- vscodium-bin lives in the AUR,
# which this tool keeps disabled -- so Arch follows the same tiering as the VS
# Code installer and falls back to the project's own GitHub release tarball,
# which is exactly what vscodium-bin repackages. Unlike Microsoft's tarball,
# VSCodium's unpacks flat (no top-level directory), so it is extracted straight
# into the install path. It ships .sha256 sidecars, so unlike the VS Code
# tarball this download is checksum-verified.

# --- VSCodium ---

_VSCODIUM_API="https://api.github.com/repos/VSCodium/vscodium/releases/latest"
_VSCODIUM_KEY_URL="https://gitlab.com/paulcarroty/vscodium-deb-rpm-repo/raw/master/pub.gpg"
_VSCODIUM_RPM_BASEURL="https://download.vscodium.com/rpms/"
_VSCODIUM_DIR="$HOME/.local/share/vscodium"
_VSCODIUM_WRAPPER="$HOME/.local/bin/codium"
_VSCODIUM_DESKTOP="$HOME/.local/share/applications/codium.desktop"
_VSCODIUM_ICON="$HOME/.local/share/icons/hicolor/512x512/apps/vscodium.png"

check_vscodium() {
    [[ -x "$_VSCODIUM_DIR/bin/codium" ]] && return 0
    _check_standard codium codium com.vscodium.codium vscodium-bin
}

# Write the rpm-md repo definition used by dnf and zypper. $1 is the file to
# write; $2 adds the type= line zypper wants and dnf ignores.
_vscodium_write_rpm_repo() {
    local dest="$1" extra="${2:-}"
    printf "[vscodium]\nname=VSCodium\nbaseurl=%s\nenabled=1\n%sgpgcheck=1\nrepo_gpgcheck=1\ngpgkey=%s\nmetadata_expire=1h\n" \
        "$_VSCODIUM_RPM_BASEURL" "$extra" "$_VSCODIUM_KEY_URL" | \
        sudo tee "$dest" > /dev/null
}

# Install the project's own release tarball per-user. Used as the
# upstream-binary tier of arch_install_ordered, so it runs only after the repos
# and Flathub have been tried and before the (disabled) AUR tier.
_vscodium_install_tarball() {
    local release_json version asset url tmpdir tmptar

    release_json=$(curl -fsSL "$_VSCODIUM_API" 2>/dev/null) || {
        error "Failed to query the VSCodium release API."
        return 1
    }
    version=$(printf '%s' "$release_json" | grep -oP '"tag_name"\s*:\s*"\K[^"]+' | head -1)
    if [[ -z "$version" ]]; then
        error "Could not determine the latest VSCodium version."
        return 1
    fi
    asset="VSCodium-linux-x64-${version}.tar.gz"
    url="https://github.com/VSCodium/vscodium/releases/download/${version}/${asset}"

    tmpdir=$(mktemp -d /tmp/vscodium-XXXXXX) || return 1
    CLEANUP_FILES+=("$tmpdir")
    tmptar="$tmpdir/$asset"

    # ~150 MB, so download_file's 30s curl timeout is far too short (see the
    # same note in the VS Code installer). -sS keeps the progress meter out of
    # the menu UI while still printing real errors.
    info "Downloading VSCodium ${version} (large download, please be patient)..."
    if ! curl -fsSL --max-time 1800 --retry 2 -o "$tmptar" "$url"; then
        error "Failed to download the VSCodium tarball."
        return 1
    fi
    verify_download "$tmptar" "tar.gz" "VSCodium" || return 1
    github_verify_checksum "$_VSCODIUM_API" "$asset" "$tmptar" || return 1

    # The archive has no top-level directory -- bin/, resources/ and the codium
    # launcher sit at the root -- so extract into a staging dir that becomes the
    # install tree as-is.
    mkdir -p "$tmpdir/payload"
    tar -xzf "$tmptar" -C "$tmpdir/payload" || {
        error "Failed to extract the VSCodium tarball."
        return 1
    }
    if [[ ! -x "$tmpdir/payload/bin/codium" ]]; then
        error "Unpacked VSCodium payload is missing bin/codium."
        return 1
    fi

    # Replace the tree wholesale so no file from an older build survives an
    # update. Safe to delete: user data and extensions live in ~/.config/VSCodium
    # and ~/.vscode-oss, never inside the install directory.
    rm -rf "$_VSCODIUM_DIR"
    mkdir -p "$(dirname "$_VSCODIUM_DIR")" "$HOME/.local/bin" \
             "$HOME/.local/share/applications" "$(dirname "$_VSCODIUM_ICON")"
    mv "$tmpdir/payload" "$_VSCODIUM_DIR" || {
        error "Failed to install VSCodium to ${_VSCODIUM_DIR}."
        return 1
    }

    ln -sfn "$_VSCODIUM_DIR/bin/codium" "$_VSCODIUM_WRAPPER"
    cp "$_VSCODIUM_DIR/resources/app/resources/linux/code.png" "$_VSCODIUM_ICON" 2>/dev/null || true

    cat > "$_VSCODIUM_DESKTOP" <<EOF
[Desktop Entry]
Type=Application
Name=VSCodium
GenericName=Text Editor
Comment=Code Editing. Redefined.
Exec=$_VSCODIUM_WRAPPER %F
Icon=vscodium
Terminal=false
StartupNotify=true
StartupWMClass=VSCodium
Categories=TextEditor;Development;IDE;
MimeType=text/plain;inode/directory;
Keywords=vscodium;codium;
EOF
    refresh_desktop_caches
    info "VSCodium installed to ${_VSCODIUM_DIR}. Ensure ~/.local/bin is in your PATH."
}

# Remove a tarball install. Returns 1 when there was nothing to remove, so the
# caller can tell the difference between "cleaned up" and "not installed here".
_vscodium_remove_tarball() {
    [[ -d "$_VSCODIUM_DIR" ]] || return 1
    rm -rf "$_VSCODIUM_DIR"
    rm -f "$_VSCODIUM_WRAPPER" "$_VSCODIUM_DESKTOP" "$_VSCODIUM_ICON"
    refresh_desktop_caches
    return 0
}

install_vscodium() {
    echo "Installing VSCodium..."
    ensure_tools
    case "$DISTRO_FAMILY" in
        debian)
            local gpg_tmp
            gpg_tmp=$(mktemp /tmp/vscodium-gpg-XXXXXX)
            CLEANUP_FILES+=("$gpg_tmp")
            wget -qO- "$_VSCODIUM_KEY_URL" | gpg --dearmor > "$gpg_tmp"
            sudo install -D -o root -g root -m 644 "$gpg_tmp" /usr/share/keyrings/vscodium-archive-keyring.gpg
            echo "deb [arch=amd64,arm64 signed-by=/usr/share/keyrings/vscodium-archive-keyring.gpg] https://download.vscodium.com/debs vscodium main" | \
                sudo tee /etc/apt/sources.list.d/vscodium.list > /dev/null
            rm -f "$gpg_tmp"
            sudo apt update
            sudo apt install -y codium
            ;;
        fedora|rhel)
            sudo rpm --import "$_VSCODIUM_KEY_URL"
            _vscodium_write_rpm_repo /etc/yum.repos.d/vscodium.repo
            sudo "$PKG_MGR" install -y codium
            ;;
        arch)
            # repos -> Flathub -> VSCodium's own tarball -> AUR (disabled by default).
            arch_install_ordered "vscodium-bin" "com.vscodium.codium" \
                "_vscodium_install_tarball" "vscodium-bin"
            ;;
        suse)
            sudo rpm --import "$_VSCODIUM_KEY_URL"
            _vscodium_write_rpm_repo /etc/zypp/repos.d/vscodium.repo $'type=rpm-md\n'
            sudo zypper refresh
            sudo zypper install -y codium
            ;;
    esac
}

uninstall_vscodium() {
    echo "Uninstalling VSCodium..."
    case "$DISTRO_FAMILY" in
        debian)
            sudo apt purge --autoremove -y codium
            sudo apt autoclean
            sudo rm -f /etc/apt/sources.list.d/vscodium.list
            sudo rm -f /usr/share/keyrings/vscodium-archive-keyring.gpg
            ;;
        fedora|rhel)
            sudo "$PKG_MGR" remove -y codium
            sudo rm -f /etc/yum.repos.d/vscodium.repo
            ;;
        arch)
            # The tarball copy and a packaged copy are independent -- clear both,
            # and only reach for the package managers when a package is present
            # so a tarball-only install does not print removal errors.
            local removed_tarball=0
            _vscodium_remove_tarball && removed_tarball=1
            if pkg_check_installed vscodium-bin || pkg_check_installed codium; then
                aur_remove vscodium-bin 2>/dev/null || pkg_remove codium 2>/dev/null || true
            elif (( ! removed_tarball )); then
                echo "VSCodium installation not found."
            fi
            ;;
        suse)
            sudo zypper remove -y codium
            sudo rm -f /etc/zypp/repos.d/vscodium.repo
            ;;
    esac
    rm -rf ~/.config/VSCodium
    rm -rf ~/.vscode-oss
}

update_vscodium() {
    echo "Updating VSCodium..."
    case "$DISTRO_FAMILY" in
        debian)
            sudo apt update
            sudo apt install -y --only-upgrade codium
            ;;
        arch)
            # repos -> Flathub -> VSCodium's own tarball -> AUR (disabled by default).
            arch_install_ordered "vscodium-bin" "com.vscodium.codium" \
                "_vscodium_install_tarball" "vscodium-bin"
            ;;
        *)
            pkg_upgrade codium
            ;;
    esac
}

get_version_vscodium() {
    # Read the tarball copy's metadata directly: ~/.local/bin may not be on PATH,
    # and package.json is authoritative for the build that is actually installed.
    local v=""
    if [[ -f "$_VSCODIUM_DIR/resources/app/package.json" ]]; then
        v=$(grep -oP '"version"\s*:\s*"\K[^"]+' "$_VSCODIUM_DIR/resources/app/package.json" | head -1)
        [[ -n "$v" ]] && { printf '%s\n' "$v"; return 0; }
    fi
    _run_native codium --version 2>/dev/null | head -1 || echo ""
}

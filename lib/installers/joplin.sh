#!/bin/bash
# Joplin Client installer functions

# --- Joplin Client ---

# Detect and export the desktop environment for AppImage installers (Joplin, etc.)
detect_and_export_desktop_env() {
    local desktop_env=""
    if [[ -n "${XDG_CURRENT_DESKTOP:-}" ]]; then
        desktop_env="$XDG_CURRENT_DESKTOP"
    elif command -v plasmashell &>/dev/null; then
        desktop_env="KDE"
    elif command -v gnome-shell &>/dev/null; then
        desktop_env="GNOME"
    elif command -v xfce4-session &>/dev/null; then
        desktop_env="XFCE"
    elif command -v cinnamon &>/dev/null; then
        desktop_env="X-Cinnamon"
    fi
    if [[ -n "$desktop_env" ]]; then
        export XDG_CURRENT_DESKTOP="$desktop_env"
    fi
}

check_joplin() {
    [[ -f ~/.joplin/Joplin.AppImage ]] || command -v joplin &>/dev/null
}
install_joplin() {
    info "Installing Joplin Client..."
    detect_and_export_desktop_env

    # Joplin ships as an AppImage which requires FUSE2. The package name differs
    # by distro family. Install it pre-emptively so the upstream installer doesn't
    # abort with "Can't get libfuse2 on system".
    case "$DISTRO_FAMILY" in
        arch)
            if ! pkg_check_installed fuse2; then
                info "Installing fuse2 (required for AppImage support)..."
                pkg_install fuse2
            fi
            ;;
        debian)
            # Ubuntu 22.04 uses libfuse2; Ubuntu 24.04+ renamed it libfuse2t64
            local fuse2_pkg="libfuse2"
            if [[ "$DISTRO_ID" == "ubuntu" ]] && [[ "${DISTRO_VERSION_ID%%.*}" -ge 24 ]]; then
                fuse2_pkg="libfuse2t64"
            fi
            if ! pkg_check_installed "$fuse2_pkg"; then
                info "Installing ${fuse2_pkg} (required for AppImage support)..."
                pkg_install "$fuse2_pkg"
            fi
            ;;
        fedora|rhel)
            # `fuse` only ships the fusermount utilities and does NOT depend on
            # `fuse-libs`, which provides libfuse.so.2 — the AppImage runtime
            # needs both, so check and install each individually.
            local fuse_pkg
            for fuse_pkg in fuse fuse-libs; do
                if ! pkg_check_installed "$fuse_pkg"; then
                    info "Installing ${fuse_pkg} (required for AppImage support)..."
                    pkg_install "$fuse_pkg"
                fi
            done
            ;;
        suse)
            # Same split as Fedora: `fuse` has the utilities, `libfuse2` the library.
            local fuse_pkg
            for fuse_pkg in fuse libfuse2; do
                if ! pkg_check_installed "$fuse_pkg"; then
                    info "Installing ${fuse_pkg} (required for AppImage support)..."
                    pkg_install "$fuse_pkg"
                fi
            done
            ;;
    esac

    # Download and run installer script
    local install_script
    install_script=$(wget -qO- https://raw.githubusercontent.com/laurent22/joplin/dev/Joplin_install_and_update.sh) || {
        error "Failed to download Joplin installer script."
        return 1
    }

    if [[ -z "$install_script" ]]; then
        error "Downloaded installer script is empty."
        return 1
    fi

    echo "$install_script" | bash || {
        error "Joplin installation script failed."
        return 1
    }

    # Some distros (Ubuntu 24.04+, KDE Neon, Kubuntu, etc.) restrict unprivileged
    # user namespaces via AppArmor, which breaks Electron-based AppImages like
    # Joplin (causes SIGTRAP crash). Disable the restriction if it is active.
    local sysctl_file="/etc/sysctl.d/99-appimage-userns.conf"
    local sysctl_key="kernel.apparmor_restrict_unprivileged_userns"
    if [[ "$(sysctl -n "$sysctl_key" 2>/dev/null)" == "1" ]]; then
        info "Configuring system to allow AppImage user namespaces (required for Joplin)..."
        echo "${sysctl_key}=0" | sudo tee "$sysctl_file" >/dev/null
        sudo sysctl --system >/dev/null 2>&1
        info "AppImage user namespace restriction disabled."
    fi

    # The upstream script writes the .desktop entry and icon itself
    refresh_desktop_caches
}
uninstall_joplin() {
    info "Uninstalling Joplin Client..."
    rm -rf ~/.joplin
    rm -f ~/.local/share/applications/joplin.desktop
    rm -f ~/.local/share/applications/appimagekit-joplin.desktop
    rm -f ~/.local/share/icons/hicolor/*/apps/joplin.png
    rm -f ~/.local/share/icons/hicolor/*/apps/appimagekit-joplin.png
    rm -f ~/.local/bin/joplin
    rm -rf ~/.config/joplin-desktop
    rm -rf ~/.config/joplin
    refresh_desktop_caches
}
update_joplin() {
    info "Updating Joplin Client..."
    detect_and_export_desktop_env

    local tmpfile
    tmpfile=$(mktemp /tmp/joplin-update-XXXXXX.sh)
    CLEANUP_FILES+=("$tmpfile")

    if ! wget -qO "$tmpfile" https://raw.githubusercontent.com/laurent22/joplin/dev/Joplin_install_and_update.sh; then
        error "Failed to download Joplin update script."
        rm -f "$tmpfile"
        return 1
    fi

    if [[ ! -s "$tmpfile" ]]; then
        error "Downloaded update script is empty."
        rm -f "$tmpfile"
        return 1
    fi

    bash "$tmpfile" || {
        error "Joplin update script failed."
        return 1
    }
}
get_version_joplin() {
    # NOTE: Do NOT run the AppImage with --version — it opens a GUI error dialog.
    local version=""
    local config_home="${XDG_CONFIG_HOME:-$HOME/.config}"

    # 1. Try config file paths (created after Joplin's first launch)
    #    Use awk instead of grep -oP for portability (no PCRE/libpcre2 dependency)
    local pkg_json
    for pkg_json in "$config_home/joplin-desktop/package.json" "$config_home/joplin/package.json"; do
        if [[ -f "$pkg_json" ]]; then
            version=$(awk -F'"' '/"version"/{print $4; exit}' "$pkg_json" 2>/dev/null)
            [[ -n "$version" ]] && echo "$version" && return 0
        fi
    done

    # 2. Extract version from the AppImage's embedded metadata
    local appimage="$HOME/.joplin/Joplin.AppImage"
    if [[ -f "$appimage" ]]; then
        local tmpdir
        tmpdir=$(mktemp -d)
        trap "rm -rf '$tmpdir'" RETURN

        # Try resources/app/package.json (Electron apps without asar packaging)
        if (cd "$tmpdir" && timeout 10 "$appimage" --appimage-extract "resources/app/package.json") &>/dev/null; then
            version=$(awk -F'"' '/"version"/{print $4; exit}' "$tmpdir/squashfs-root/resources/app/package.json" 2>/dev/null)
            if [[ -n "$version" ]]; then
                echo "$version"
                return 0
            fi
        fi

        # Try the embedded .desktop file for X-AppImage-Version (works with asar-packed apps)
        if (cd "$tmpdir" && timeout 10 "$appimage" --appimage-extract "*.desktop") &>/dev/null; then
            version=$(grep -h 'X-AppImage-Version=' "$tmpdir"/squashfs-root/*.desktop 2>/dev/null | head -1 | cut -d= -f2)
            if [[ -n "$version" ]]; then
                echo "$version"
                return 0
            fi
        fi
    fi

    echo ""
}

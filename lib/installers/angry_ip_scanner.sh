#!/bin/bash
# Angry IP Scanner installer functions
#
# Arch has no repo package: ipscan lives only in the AUR, which this tool keeps
# disabled. Upstream also publishes a self-contained JAR alongside the .deb and
# .rpm, so the Arch path installs that instead — no AUR, no packaging. The
# linux64 JAR carries its own SWT/GTK natives and needs nothing but a JRE.

# --- Angry IP Scanner ---

_IPSCAN_REPO_API="https://api.github.com/repos/angryip/ipscan/releases/latest"
_IPSCAN_DIR="$HOME/.local/share/angry-ip-scanner"
_IPSCAN_JAR="$_IPSCAN_DIR/ipscan.jar"
_IPSCAN_ICON="$_IPSCAN_DIR/icon128.png"
_IPSCAN_VERSION_FILE="$_IPSCAN_DIR/version"
_IPSCAN_WRAPPER="$HOME/.local/bin/ipscan"
_IPSCAN_DESKTOP="$HOME/.local/share/applications/ipscan.desktop"

check_angry_ip_scanner() {
    [[ -f "$_IPSCAN_JAR" ]] && return 0
    _check_standard ipscan ipscan ""
}

_angry_ip_latest_url() {
    local pattern="$1"
    curl -fsSL "$_IPSCAN_REPO_API" \
        | grep -oP '"browser_download_url"\s*:\s*"\K[^"]+'"$pattern" | head -1
}

# Install the upstream JAR per-user: no root, no AUR, no distro packaging.
# The JAR's class files target Java 17, so a newer JRE is required than some
# distros ship by default — pull one in when java is missing or too old.
_angry_ip_install_jar() {
    local url
    url=$(_angry_ip_latest_url '\-linux64\-[0-9.]+\.jar')
    if [[ -z "$url" ]]; then
        error "Could not find the Angry IP Scanner JAR release URL."
        return 1
    fi

    _angry_ip_ensure_java || return 1

    local tmpdir tmpfile
    tmpdir=$(mktemp -d /tmp/ipscan-XXXXXX)
    CLEANUP_FILES+=("$tmpdir")
    tmpfile="$tmpdir/ipscan.jar"

    wget -qO "$tmpfile" "$url" || { error "Failed to download the Angry IP Scanner JAR."; return 1; }
    verify_download "$tmpfile" "jar" "Angry IP Scanner" || return 1
    github_verify_checksum "$_IPSCAN_REPO_API" "$(basename "$url")" "$tmpfile" || return 1

    mkdir -p "$_IPSCAN_DIR" "$HOME/.local/bin" "$HOME/.local/share/applications"
    mv "$tmpfile" "$_IPSCAN_JAR" || { error "Failed to install the JAR to ${_IPSCAN_JAR}."; return 1; }

    # The JAR is the only thing upstream ships on this path — pull the menu icon
    # out of it. Not fatal: the entry just falls back to a generic icon.
    if command -v unzip &>/dev/null; then
        unzip -p "$_IPSCAN_JAR" images/icon128.png > "$_IPSCAN_ICON" 2>/dev/null || rm -f "$_IPSCAN_ICON"
    fi

    basename "$url" | grep -oP '[0-9]+\.[0-9]+\.[0-9]+' | head -1 > "$_IPSCAN_VERSION_FILE"

    cat > "$_IPSCAN_WRAPPER" <<EOF
#!/bin/bash
exec java -jar "$_IPSCAN_JAR" "\$@"
EOF
    chmod +x "$_IPSCAN_WRAPPER"

    {
        echo "[Desktop Entry]"
        echo "Type=Application"
        echo "Name=Angry IP Scanner"
        echo "Comment=Fast and friendly network scanner"
        echo "Exec=$_IPSCAN_WRAPPER"
        [[ -s "$_IPSCAN_ICON" ]] && echo "Icon=$_IPSCAN_ICON"
        echo "Terminal=false"
        echo "Categories=Network;System;Utility;"
    } > "$_IPSCAN_DESKTOP"
    refresh_desktop_caches

    info "Angry IP Scanner installed to ${_IPSCAN_DIR}. Launch it from your application menu or run 'ipscan'."
}

# The JAR needs a Java 17+ runtime. Install one from the distro's repos when the
# system has no java at all, or one too old to load the class files.
_angry_ip_ensure_java() {
    local major=""
    if command -v java &>/dev/null; then
        major=$(java -version 2>&1 | grep -oP '(?<=version ")[0-9]+' | head -1)
        [[ -n "$major" && "$major" -ge 17 ]] && return 0
        info "Java ${major:-unknown} found, but Angry IP Scanner needs 17 or newer."
    fi

    local jre_pkg
    case "$PKG_MGR" in
        pacman)  jre_pkg="jre-openjdk" ;;
        apt)     jre_pkg="default-jre" ;;
        dnf|yum) jre_pkg="java-latest-openjdk" ;;
        zypper)  jre_pkg="java-17-openjdk" ;;
        *)       error "No known JRE package for ${PKG_MGR}; install Java 17+ and retry."; return 1 ;;
    esac

    info "Installing ${jre_pkg} (required to run Angry IP Scanner)..."
    pkg_install "$jre_pkg" || { error "Failed to install ${jre_pkg}."; return 1; }
    command -v java &>/dev/null || { error "Java is still not on PATH after installing ${jre_pkg}."; return 1; }
}

install_angry_ip_scanner() {
    info "Installing Angry IP Scanner..."
    ensure_tools
    case "$DISTRO_FAMILY" in
        debian)
            local url tmpfile
            url=$(_angry_ip_latest_url '_amd64\.deb')
            if [[ -z "$url" ]]; then
                error "Could not find Angry IP Scanner .deb release URL."
                return 1
            fi
            tmpfile=$(mktemp /tmp/ipscan-XXXXXX.deb)
            CLEANUP_FILES+=("$tmpfile")
            wget -qO "$tmpfile" "$url" || { error "Failed to download Angry IP Scanner .deb."; return 1; }
            verify_download "$tmpfile" "deb" "Angry IP Scanner" || return 1
            github_verify_checksum "https://api.github.com/repos/angryip/ipscan/releases/latest" \
                "$(basename "$url")" "$tmpfile" || return 1
            sudo apt install -y "$tmpfile"
            ;;
        fedora|rhel)
            local url tmpfile
            url=$(_angry_ip_latest_url '\.x86_64\.rpm')
            if [[ -z "$url" ]]; then
                error "Could not find Angry IP Scanner .rpm release URL."
                return 1
            fi
            tmpfile=$(mktemp /tmp/ipscan-XXXXXX.rpm)
            CLEANUP_FILES+=("$tmpfile")
            wget -qO "$tmpfile" "$url" || { error "Failed to download Angry IP Scanner .rpm."; return 1; }
            verify_download "$tmpfile" "rpm" "Angry IP Scanner" || return 1
            github_verify_checksum "https://api.github.com/repos/angryip/ipscan/releases/latest" \
                "$(basename "$url")" "$tmpfile" || return 1
            sudo "$PKG_MGR" install -y "$tmpfile"
            ;;
        arch)
            # Nothing in the Arch repos; the JAR avoids the AUR entirely.
            _angry_ip_install_jar || return 1
            ;;
        suse)
            local url tmpfile
            url=$(_angry_ip_latest_url '\.x86_64\.rpm')
            if [[ -z "$url" ]]; then
                error "Could not find Angry IP Scanner .rpm release URL."
                return 1
            fi
            tmpfile=$(mktemp /tmp/ipscan-XXXXXX.rpm)
            CLEANUP_FILES+=("$tmpfile")
            wget -qO "$tmpfile" "$url" || { error "Failed to download Angry IP Scanner .rpm."; return 1; }
            verify_download "$tmpfile" "rpm" "Angry IP Scanner" || return 1
            github_verify_checksum "https://api.github.com/repos/angryip/ipscan/releases/latest" \
                "$(basename "$url")" "$tmpfile" || return 1
            sudo zypper install -y "$tmpfile"
            ;;
    esac
    info "Angry IP Scanner installed."
}

uninstall_angry_ip_scanner() {
    info "Uninstalling Angry IP Scanner..."
    case "$DISTRO_FAMILY" in
        debian)  sudo apt purge --autoremove -y ipscan ;;
        fedora|rhel) sudo "$PKG_MGR" remove -y ipscan ;;
        # Remove the per-user JAR install, then any older package-based copy.
        # angryipscanner is an older AUR name; aur_remove drops to pacman -Rs
        # when no AUR helper is present.
        arch)    rm -f "$_IPSCAN_JAR" "$_IPSCAN_ICON" "$_IPSCAN_VERSION_FILE" \
                       "$_IPSCAN_WRAPPER" "$_IPSCAN_DESKTOP"
                 rmdir "$_IPSCAN_DIR" 2>/dev/null || true
                 refresh_desktop_caches
                 aur_remove ipscan 2>/dev/null || aur_remove angryipscanner 2>/dev/null || true ;;
        suse)    sudo zypper remove -y ipscan 2>/dev/null || true ;;
    esac
    rm -rf "$HOME/.ipscan"
}

update_angry_ip_scanner() {
    info "Updating Angry IP Scanner..."
    case "$DISTRO_FAMILY" in
        debian|fedora|rhel|suse) install_angry_ip_scanner ;;
        arch) _angry_ip_install_jar ;;
    esac
}

get_version_angry_ip_scanner() {
    # The JAR install records its version at install time; the JAR itself only
    # reports one by opening a window.
    [[ -s "$_IPSCAN_VERSION_FILE" ]] && { cat "$_IPSCAN_VERSION_FILE"; return 0; }
    _ver_from_pkg ipscan || echo ""
}

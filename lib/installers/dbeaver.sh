#!/bin/bash
# DBeaver Community Edition installer functions

# --- DBeaver ---

check_dbeaver() { _check_standard dbeaver dbeaver-ce ""; }

install_dbeaver() {
    info "Installing DBeaver Community Edition..."
    ensure_tools
    case "$DISTRO_FAMILY" in
        debian)
            local tmpfile
            tmpfile=$(mktemp /tmp/dbeaver-XXXXXX.deb)
            CLEANUP_FILES+=("$tmpfile")
            if ! wget -qO "$tmpfile" "https://dbeaver.io/files/dbeaver-ce_latest_amd64.deb"; then
                error "Failed to download DBeaver .deb package."
                return 1
            fi
            verify_download "$tmpfile" "deb" "DBeaver" || return 1
            pkg_install "$tmpfile"
            ;;
        fedora|rhel)
            local tmpfile
            tmpfile=$(mktemp /tmp/dbeaver-XXXXXX.rpm)
            CLEANUP_FILES+=("$tmpfile")
            if ! wget -qO "$tmpfile" "https://dbeaver.io/files/dbeaver-ce_latest_x86_64.rpm"; then
                error "Failed to download DBeaver .rpm package."
                return 1
            fi
            verify_download "$tmpfile" "rpm" "DBeaver" || return 1
            pkg_install "$tmpfile"
            ;;
        arch)
            repo_or_aur dbeaver
            ;;
        suse)
            local tmpfile
            tmpfile=$(mktemp /tmp/dbeaver-XXXXXX.rpm)
            CLEANUP_FILES+=("$tmpfile")
            if ! wget -qO "$tmpfile" "https://dbeaver.io/files/dbeaver-ce_latest_x86_64.rpm"; then
                error "Failed to download DBeaver .rpm package."
                return 1
            fi
            verify_download "$tmpfile" "rpm" "DBeaver" || return 1
            pkg_install "$tmpfile"
            ;;
    esac
    info "DBeaver Community Edition installed."
}

uninstall_dbeaver() {
    info "Uninstalling DBeaver..."
    case "$DISTRO_FAMILY" in
        debian)
            pkg_remove dbeaver-ce
            ;;
        fedora|rhel)
            pkg_remove dbeaver-ce
            ;;
        arch)
            pkg_remove dbeaver 2>/dev/null || true
            ;;
        suse)
            pkg_remove dbeaver-ce
            ;;
    esac
    rm -rf "$HOME/.local/share/DBeaverData"
    rm -rf "$HOME/.dbeaver"
}

update_dbeaver() {
    info "Updating DBeaver..."
    case "$DISTRO_FAMILY" in
        debian)
            # Re-download latest .deb
            install_dbeaver
            ;;
        fedora|rhel)
            install_dbeaver
            ;;
        arch)
            repo_or_aur dbeaver
            ;;
        suse)
            install_dbeaver
            ;;
    esac
}

get_version_dbeaver() {
    # Do NOT call dbeaver --version — Java GUI apps launch a full window.
    _ver_from_pkg dbeaver-ce || echo ""
}

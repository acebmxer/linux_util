#!/bin/bash
# UniFi Endpoint (UniFi Identity VPN client) installer functions

# --- UniFi Endpoint ---

# Ubiquiti publishes no "latest" download endpoint or checksums file — each
# release gets fresh UUID-tagged URLs announced on the community releases page:
# https://community.ui.com/releases/UniFi-Endpoint-Linux-1-0-0/49903a99-f238-4b94-9a00-a80d067c5513
# Bump the version, URLs, and checksums together when a new release ships.
UNIFI_ENDPOINT_VERSION="1.0.0-12"
UNIFI_ENDPOINT_DEB_URL="https://fw-download.ubnt.com/data/unifi-endpoint-desktop-app-deb/d559-linux-1.0.0-12-494047dd-0692-43bc-bbe8-550a3117cda2.deb"
UNIFI_ENDPOINT_DEB_SHA256="d58167c19134273358925c4fa37add5fba26fa1be4b8268933dda259d31a459f"
UNIFI_ENDPOINT_RPM_URL="https://fw-download.ubnt.com/data/unifi-endpoint-desktop-app-rpm/5ac6-linux-1.0.0-12-c75f43b1-fcf4-4784-935f-7c9495b908ed.rpm"
UNIFI_ENDPOINT_RPM_SHA256="413ce17d7e13fd1f6c14749967689085acfc865e7005b323d56ab97d8c3324f0"

# The package installs no binary on PATH (GUI app under /usr/lib/UniFi-Endpoint).
check_unifi_endpoint() { _check_standard "" unifi-endpoint ""; }

install_unifi_endpoint() {
    info "Installing UniFi Endpoint ${UNIFI_ENDPOINT_VERSION}..."
    if [[ "$(uname -m)" != "x86_64" ]]; then
        error "UniFi Endpoint is only published for x86_64 (found $(uname -m))."
        return 1
    fi
    ensure_tools
    case "$DISTRO_FAMILY" in
        debian)
            local tmpfile
            tmpfile=$(mktemp /tmp/unifi-endpoint-XXXXXX.deb)
            CLEANUP_FILES+=("$tmpfile")
            wget -qO "$tmpfile" "$UNIFI_ENDPOINT_DEB_URL" || { error "Failed to download UniFi Endpoint .deb."; return 1; }
            verify_download "$tmpfile" "deb" "UniFi Endpoint" || return 1
            verify_sha256 "$tmpfile" "$UNIFI_ENDPOINT_DEB_SHA256" "UniFi Endpoint .deb" || return 1
            sudo apt install -y "$tmpfile"
            ;;
        fedora|rhel|suse)
            local tmpfile
            tmpfile=$(mktemp /tmp/unifi-endpoint-XXXXXX.rpm)
            CLEANUP_FILES+=("$tmpfile")
            wget -qO "$tmpfile" "$UNIFI_ENDPOINT_RPM_URL" || { error "Failed to download UniFi Endpoint .rpm."; return 1; }
            verify_download "$tmpfile" "rpm" "UniFi Endpoint" || return 1
            verify_sha256 "$tmpfile" "$UNIFI_ENDPOINT_RPM_SHA256" "UniFi Endpoint .rpm" || return 1
            if [[ "$DISTRO_FAMILY" == "suse" ]]; then
                sudo zypper install -y --allow-unsigned-rpm "$tmpfile"
            else
                sudo "$PKG_MGR" install -y "$tmpfile"
            fi
            ;;
        arch)
            error "Ubiquiti only publishes .deb/.rpm packages and no AUR package exists for UniFi Endpoint."
            return 1
            ;;
    esac
    info "UniFi Endpoint installed. Launch it from the application menu to sign in."
    info "If your workspace uses SSL inspection, add yourself to the cert-management group:"
    info "  sudo usermod -aG unifi-endpoint \$USER"
}

uninstall_unifi_endpoint() {
    info "Uninstalling UniFi Endpoint..."
    case "$DISTRO_FAMILY" in
        debian)
            # purge (not just remove) also deletes any workspace CA certificates
            # the app installed into the system trust store.
            sudo apt purge --autoremove -y unifi-endpoint
            ;;
        fedora|rhel)
            sudo "$PKG_MGR" remove -y unifi-endpoint
            ;;
        suse)
            sudo zypper remove -y unifi-endpoint
            ;;
    esac
}

update_unifi_endpoint() {
    info "Updating UniFi Endpoint..."
    # No update channel — reinstalls the pinned release (no-op if already current).
    install_unifi_endpoint
}

get_version_unifi_endpoint() {
    _ver_from_pkg unifi-endpoint || echo ""
}

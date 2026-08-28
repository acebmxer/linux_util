#!/bin/bash
# WPS Office installer functions
# Official download: https://linux.wps.com/

# --- WPS Office ---

# linux.wps.com now 301s to https://www.wps.com/office/linux/, a Nuxt SPA whose
# HTML carries no package links at all -- the old scrape for an href ending in
# _amd64.deb matched nothing and every direct install failed with "Could not
# determine WPS Office download URL". The Deb/RPM buttons are wired up in
# JavaScript, so the current release is read out of the page's entry bundle
# instead (see _wps_scrape_release).
#
# Packages live under a per-build directory on this CDN and carry an .XA suffix:
#   .../linux/11723/wps-office_11.1.0.11723.XA_amd64.deb
#   .../linux/11723/wps-office-11.1.0.11723.XA-1.x86_64.rpm
# The wps-linux-personal.wpscdn.cn URLs also hardcoded in that bundle are the
# China-personal CDN and answer 403 from outside it, so they are not used here.
_WPS_DL_BASE="https://wdl1.pcfg.cache.wpscdn.com/wpsdl/wpsoffice/download/linux"
_WPS_DEB_URL_RE='https://wdl1\.pcfg\.cache\.wpscdn\.com/wpsdl/wpsoffice/download/linux/[0-9]+/wps-office_[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+\.XA_amd64\.deb'

# Last build confirmed present on the CDN, used when the scrape comes up empty.
# WPS ships Linux builds rarely -- 11.1.0.11698 stood for years before 11723 --
# so a pin is a reasonable safety net rather than a stale-version trap.
_WPS_PINNED_VERSION="11.1.0.11723"
_WPS_PINNED_BUILD="11723"

check_wps_office() { _check_standard wps wps-office com.wps.Office; }

# Print "<version> <build>" for the current Linux release, or fail with no
# output. The bundle filename is content-hashed and changes on every site
# rebuild, so the entry <script type="module"> is read out of the page rather
# than hardcoded.
_wps_scrape_release() {
    local page chunks chunk body match version build
    page=$(curl -fsSL "https://linux.wps.com/") || return 1
    chunks=$(printf '%s\n' "$page" \
        | grep -oE '<script[^>]+type="module"[^>]+src="[^"]+\.js"' \
        | grep -oE 'https://[^"]+\.js') || return 1

    while read -r chunk; do
        [[ -n "$chunk" ]] || continue
        body=$(curl -fsSL "$chunk") || continue
        match=$(printf '%s\n' "$body" | grep -oE "$_WPS_DEB_URL_RE") || continue
        match="${match%%$'\n'*}"
        version=$(printf '%s\n' "$match" | grep -oP 'wps-office_\K[0-9.]+(?=\.XA_amd64\.deb)')
        build=$(printf '%s\n' "$match" | grep -oP '/linux/\K[0-9]+(?=/)')
        [[ -n "$version" && -n "$build" ]] || continue
        printf '%s %s\n' "$version" "$build"
        return 0
    done <<< "$chunks"
    return 1
}

# Print the download URL for $1 (deb|rpm) at version $2, build $3.
_wps_pkg_url() {
    case "$1" in
        deb) printf '%s/%s/wps-office_%s.XA_amd64.deb\n'    "$_WPS_DL_BASE" "$3" "$2" ;;
        rpm) printf '%s/%s/wps-office-%s.XA-1.x86_64.rpm\n' "$_WPS_DL_BASE" "$3" "$2" ;;
        *)   return 1 ;;
    esac
}

# True when the URL answers a successful HEAD. Guards against a scraped build
# whose .rpm was never published, and against the pin going away upstream.
_wps_url_ok() {
    curl -fsSI -o /dev/null -m 30 "$1" 2>/dev/null
}

# The package's postinst calls xdg-icon-resource but declares no dependency on
# xdg-utils -- an upstream packaging bug. A desktop install usually has it
# already, but on a minimal or server system the script dies with
# "xdg-icon-resource: command not found" (exit 127) and leaves the package
# half-configured (`iF` in dpkg -l), which apt then trips over on every
# subsequent run. Installing it up front is best-effort: if it is unavailable
# the install still proceeds and simply hits the upstream failure.
_wps_ensure_xdg_utils() {
    command -v xdg-icon-resource &>/dev/null && return 0
    info "Installing xdg-utils (required by the WPS Office post-install script)..."
    pkg_install xdg-utils || warn "Could not install xdg-utils — the WPS post-install step may fail."
}

# Download and install WPS Office .deb or .rpm from the official CDN.
# Usage: _wps_install_from_site <deb|rpm>
_wps_install_from_site() {
    local pkg_type="$1"  # "deb" or "rpm"
    ensure_tools

    # Upstream publishes x86_64 packages only. The _arm64.deb name this
    # installer used to build for aarch64 has never existed on the CDN.
    if [[ "$(uname -m)" != "x86_64" ]]; then
        if has_flatpak; then
            info "WPS Office ships x86_64 packages only — installing the Flatpak instead."
            sudo flatpak install -y flathub com.wps.Office
            return
        fi
        error "WPS Office provides x86_64 packages only, and flatpak is not available."
        return 1
    fi

    local release version build download_url
    if release=$(_wps_scrape_release); then
        version="${release%% *}"
        build="${release##* }"
    else
        warn "Could not read the current WPS Office release from the download page."
        warn "Falling back to the pinned build ${_WPS_PINNED_VERSION}."
        version="$_WPS_PINNED_VERSION"
        build="$_WPS_PINNED_BUILD"
    fi

    download_url=$(_wps_pkg_url "$pkg_type" "$version" "$build") || return 1
    if ! _wps_url_ok "$download_url"; then
        # A scraped build with no matching package for this format: retry the
        # pin before giving up, since it is known to carry both deb and rpm.
        if [[ "$version" != "$_WPS_PINNED_VERSION" ]]; then
            warn "WPS Office ${version} has no .${pkg_type} on the CDN — trying ${_WPS_PINNED_VERSION}."
            version="$_WPS_PINNED_VERSION"
            build="$_WPS_PINNED_BUILD"
            download_url=$(_wps_pkg_url "$pkg_type" "$version" "$build") || return 1
        fi
        if ! _wps_url_ok "$download_url"; then
            error "Could not find a WPS Office .${pkg_type} to download."
            error "Check https://www.wps.com/office/linux/ — the download layout may have changed."
            return 1
        fi
    fi
    info "Found WPS Office ${version}."
    _wps_ensure_xdg_utils

    local tmp_dir pkg_file
    tmp_dir=$(mktemp -d /tmp/wps-office-install-XXXXXX)
    CLEANUP_FILES+=("$tmp_dir")
    pkg_file="${tmp_dir}/wps-office.${pkg_type}"

    # ~320 MB, so the progress bar is worth keeping.
    echo "Downloading WPS Office from ${download_url}..."
    if ! wget -q --show-progress -O "$pkg_file" "$download_url"; then
        echo "Error: Failed to download WPS Office."
        rm -rf "$tmp_dir"
        return 1
    fi
    verify_download "$pkg_file" "$pkg_type" "WPS Office" || { rm -rf "$tmp_dir"; return 1; }

    # pkg_install_local hands the file to apt/dnf, which resolve the package's
    # dependencies. The hand-rolled commands this replaces did not: `dpkg -i`
    # cannot pull the dozen libraries the package needs, and `dnf localinstall`
    # was removed in dnf5 (Fedora 41+), so the rpm branch fell through to a bare
    # `rpm -i` that aborts on unresolved dependencies -- an outright failure on
    # any current Fedora.
    pkg_install_local "$pkg_file" || { rm -rf "$tmp_dir"; return 1; }

    rm -rf "$tmp_dir"
    echo "WPS Office installed successfully."
}

# Upstream's .rpm predates payload digests, so rpm 6 (current Fedora) refuses it
# outright -- dnf resolves all 24 dependencies, then aborts the transaction with
# "package wps-office-... does not verify: no digest". There is no bypass short
# of lowering %_pkgverify_level system-wide, the same wall the Stacer installer
# hit. Flathub carries the same upstream build, so the Flatpak is the working
# path here; the .rpm is kept as a fallback for older rpm releases (RHEL and
# derivatives) that still accept it.
_wps_install_rpm_family() {
    if has_flatpak; then
        info "Installing the WPS Office Flatpak — upstream's .rpm carries no payload digest and rpm 6 rejects it."
        sudo flatpak install -y flathub com.wps.Office
        return
    fi
    warn "flatpak is not available; falling back to upstream's .rpm."
    warn "If it aborts with \"does not verify: no digest\", install flatpak and retry."
    _wps_install_from_site "rpm"
}

install_wps_office() {
    info "Installing WPS Office..."
    case "$DISTRO_FAMILY" in
        debian)
            _wps_install_from_site "deb"
            ;;
        fedora|rhel)
            _wps_install_rpm_family
            ;;
        arch)
            flatpak_or_aur com.wps.Office wps-office
            ;;
        suse)
            if has_flatpak; then
                sudo flatpak install -y flathub com.wps.Office
            else
                echo "Error: No supported installation method for openSUSE. Install flatpak and retry."
                return 1
            fi
            ;;
        *)
            if has_flatpak; then
                sudo flatpak install -y flathub com.wps.Office
            else
                echo "Error: Unsupported distribution and flatpak is not available."
                return 1
            fi
            ;;
    esac
}

uninstall_wps_office() {
    info "Uninstalling WPS Office..."
    case "$DISTRO_FAMILY" in
        debian)
            sudo apt purge --autoremove -y wps-office
            sudo apt autoclean
            ;;
        fedora|rhel)
            # Now that Fedora installs the Flatpak, uninstall has to look there
            # too, or an installed WPS Office survives its own removal.
            if flatpak_is_installed "com.wps.Office"; then
                flatpak uninstall -y --user com.wps.Office 2>/dev/null || \
                    sudo flatpak uninstall -y --system com.wps.Office
            else
                sudo "$PKG_MGR" remove -y wps-office
            fi
            ;;
        arch)
            if flatpak_is_installed "com.wps.Office"; then
                flatpak uninstall -y --user com.wps.Office 2>/dev/null || \
                    sudo flatpak uninstall -y --system com.wps.Office
            else
                aur_remove wps-office 2>/dev/null || pkg_remove wps-office 2>/dev/null || true
            fi
            ;;
        suse)
            if flatpak_is_installed "com.wps.Office"; then
                flatpak uninstall -y --user com.wps.Office 2>/dev/null || \
                    sudo flatpak uninstall -y --system com.wps.Office
            else
                sudo zypper remove -y wps-office 2>/dev/null || true
            fi
            ;;
        *)
            if flatpak_is_installed "com.wps.Office"; then
                flatpak uninstall -y --user com.wps.Office 2>/dev/null || \
                    sudo flatpak uninstall -y --system com.wps.Office
            fi
            ;;
    esac
    rm -rf ~/.local/share/kingsoft
    rm -rf ~/.config/Kingsoft
    echo "WPS Office has been uninstalled."
}

update_wps_office() {
    info "Updating WPS Office..."
    case "$DISTRO_FAMILY" in
        debian)
            # WPS Office has no apt repo; re-download latest .deb
            _wps_install_from_site "deb"
            ;;
        fedora|rhel)
            if flatpak_is_installed "com.wps.Office"; then
                flatpak update -y --user com.wps.Office 2>/dev/null || \
                    sudo flatpak update -y --system com.wps.Office
            else
                _wps_install_rpm_family
            fi
            ;;
        arch)
            if flatpak_is_installed "com.wps.Office"; then
                flatpak update -y --user com.wps.Office 2>/dev/null || \
                    sudo flatpak update -y --system com.wps.Office
            else
                repo_or_aur wps-office
            fi
            ;;
        *)
            if flatpak_is_installed "com.wps.Office"; then
                flatpak update -y --user com.wps.Office 2>/dev/null || \
                    sudo flatpak update -y --system com.wps.Office
            fi
            ;;
    esac
}

# The package-manager query goes through _ver_from_pkg rather than dpkg, which
# only exists on Debian — on Fedora and openSUSE the old dpkg call produced
# nothing, so an installed WPS Office showed no version at all.
get_version_wps_office() {
    _ver_from_pkg wps-office \
        || _ver_from_flatpak com.wps.Office \
        || echo ""
}

#!/bin/bash
# Brave Origin installer functions
#
# Brave Origin is a separate, streamlined build of Brave. It ships from the same
# APT/RPM repositories and uses the same signing key as Brave Browser, but as a
# distinct package (brave-origin / AUR brave-origin-bin) with its own
# brave-origin binary. Because the repo and keyring are shared with
# "Brave Browser", uninstall here removes only the package — never the shared
# repo/keyring files, which a coexisting Brave Browser install still needs.

# --- Brave Origin ---

check_brave_origin() { _check_standard brave-origin brave-origin "" brave-origin-bin; }
install_brave_origin() {
    info "Installing Brave Origin..."
    ensure_tools
    case "$DISTRO_FAMILY" in
        debian)
            _add_apt_repo \
                "https://brave-browser-apt-release.s3.brave.com/brave-browser-archive-keyring.gpg" \
                "/usr/share/keyrings/brave-browser-archive-keyring.gpg" \
                "deb [signed-by=/usr/share/keyrings/brave-browser-archive-keyring.gpg] https://brave-browser-apt-release.s3.brave.com/ stable main" \
                "/etc/apt/sources.list.d/brave-browser-release.list"
            pkg_install brave-origin
            ;;
        fedora|rhel)
            pkg_install dnf-plugins-core 2>/dev/null || true
            sudo curl -fsSLo /etc/yum.repos.d/brave-browser.repo https://brave-browser-rpm-release.s3.brave.com/brave-browser.repo
            sudo rpm --import https://brave-browser-rpm-release.s3.brave.com/brave-core.asc
            pkg_install brave-origin
            ;;
        arch)
            repo_or_aur brave-origin-bin
            ;;
        suse)
            sudo rpm --import https://brave-browser-rpm-release.s3.brave.com/brave-core.asc
            sudo zypper addrepo -f https://brave-browser-rpm-release.s3.brave.com/brave-browser.repo brave-browser 2>/dev/null || true
            sudo zypper refresh
            pkg_install brave-origin
            ;;
    esac
}
uninstall_brave_origin() {
    info "Uninstalling Brave Origin..."
    # Note: the APT/RPM repo and signing keyring are shared with Brave Browser,
    # so they are intentionally left in place here.
    case "$DISTRO_FAMILY" in
        debian)
            pkg_remove brave-origin
            ;;
        fedora|rhel)
            pkg_remove brave-origin
            ;;
        arch)
            aur_remove brave-origin-bin 2>/dev/null || pkg_remove brave-origin 2>/dev/null || true
            ;;
        suse)
            pkg_remove brave-origin
            ;;
    esac
    rm -rf ~/.config/BraveSoftware/Brave-Origin
}
update_brave_origin() {
    info "Updating Brave Origin..."
    case "$DISTRO_FAMILY" in
        debian)
            sudo apt update
            pkg_upgrade brave-origin
            ;;
        arch)
            repo_or_aur brave-origin-bin
            ;;
        *)
            pkg_upgrade brave-origin
            ;;
    esac
}
get_version_brave_origin() {
    local out
    out=$(_run_native brave-origin --version 2>/dev/null) && \
        grep -oP 'Brave (Origin|Browser) \K[0-9]+\.[0-9]+\.[0-9]+' <<< "$out" && return
    echo ""
}

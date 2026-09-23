#!/bin/bash
# Google Chrome installer functions

# --- Google Chrome ---

check_google_chrome() {
    _have_cmd google-chrome-stable || _have_cmd google-chrome || \
        pkg_check_installed google-chrome-stable || \
        pkg_check_installed google-chrome
}

install_google_chrome() {
    info "Installing Google Chrome..."
    ensure_tools
    case "$DISTRO_FAMILY" in
        debian)
            _add_apt_repo \
                "https://dl.google.com/linux/linux_signing_key.pub" \
                "/usr/share/keyrings/google-chrome-keyring.gpg" \
                "deb [arch=amd64 signed-by=/usr/share/keyrings/google-chrome-keyring.gpg] https://dl.google.com/linux/chrome/deb/ stable main" \
                "/etc/apt/sources.list.d/google-chrome.list"
            pkg_install google-chrome-stable
            ;;
        fedora|rhel)
            sudo tee /etc/yum.repos.d/google-chrome.repo > /dev/null << 'EOF'
[google-chrome]
name=Google Chrome
baseurl=https://dl.google.com/linux/chrome/rpm/stable/x86_64
enabled=1
gpgcheck=1
gpgkey=https://dl.google.com/linux/linux_signing_key.pub
EOF
            pkg_install google-chrome-stable
            ;;
        arch)
            # repos -> Flathub -> AUR (AUR is disabled by default).
            arch_install_ordered "google-chrome" "com.google.Chrome" "" "google-chrome"
            ;;
        suse)
            sudo rpm --import https://dl.google.com/linux/linux_signing_key.pub
            sudo zypper addrepo -f https://dl.google.com/linux/chrome/rpm/stable/x86_64 google-chrome 2>/dev/null || true
            sudo zypper refresh
            pkg_install google-chrome-stable
            ;;
    esac
}

uninstall_google_chrome() {
    info "Uninstalling Google Chrome..."
    case "$DISTRO_FAMILY" in
        debian)
            pkg_remove google-chrome-stable
            sudo rm -f /etc/apt/sources.list.d/google-chrome.list
            sudo rm -f /usr/share/keyrings/google-chrome-keyring.gpg
            ;;
        fedora|rhel)
            pkg_remove google-chrome-stable
            sudo rm -f /etc/yum.repos.d/google-chrome.repo
            ;;
        arch)
            aur_remove google-chrome 2>/dev/null || pkg_remove google-chrome 2>/dev/null || true
            ;;
        suse)
            pkg_remove google-chrome-stable
            sudo zypper removerepo google-chrome 2>/dev/null || true
            ;;
    esac
    rm -rf ~/.config/google-chrome
}

update_google_chrome() {
    info "Updating Google Chrome..."
    case "$DISTRO_FAMILY" in
        debian)
            sudo apt update
            pkg_upgrade google-chrome-stable
            ;;
        arch)
            # repos -> Flathub -> AUR (AUR is disabled by default).
            arch_install_ordered "google-chrome" "com.google.Chrome" "" "google-chrome"
            ;;
        *)
            pkg_upgrade google-chrome-stable
            ;;
    esac
}

get_version_google_chrome() {
    local cmd
    for cmd in google-chrome-stable google-chrome; do
        _have_cmd "$cmd" || continue
        _run_native "$cmd" --version 2>/dev/null | grep -oP 'Google Chrome \K[0-9]+\.[0-9]+\.[0-9]+(\.[0-9]+)?' && return
    done
    echo ""
}

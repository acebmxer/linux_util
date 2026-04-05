#!/bin/bash
# Google Chrome installer functions

# --- Google Chrome ---

check_google_chrome() {
    command -v google-chrome-stable &>/dev/null || command -v google-chrome &>/dev/null || \
        pkg_check_installed google-chrome-stable
}

install_google_chrome() {
    info "Installing Google Chrome..."
    ensure_tools
    case "$DISTRO_FAMILY" in
        debian)
            sudo install -d -m 0755 /usr/share/keyrings
            sudo curl -fsSL "https://dl.google.com/linux/linux_signing_key.pub" | \
                sudo gpg --dearmor -o /usr/share/keyrings/google-chrome-keyring.gpg
            echo "deb [arch=amd64 signed-by=/usr/share/keyrings/google-chrome-keyring.gpg] https://dl.google.com/linux/chrome/deb/ stable main" | \
                sudo tee /etc/apt/sources.list.d/google-chrome.list > /dev/null
            sudo apt update
            sudo apt install -y google-chrome-stable
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
            sudo "$PKG_MGR" install -y google-chrome-stable
            ;;
        arch)
            if has_aur_helper; then
                aur_install google-chrome
            else
                aur_build google-chrome
            fi
            ;;
        suse)
            sudo rpm --import https://dl.google.com/linux/linux_signing_key.pub
            sudo zypper addrepo -f https://dl.google.com/linux/chrome/rpm/stable/x86_64 google-chrome 2>/dev/null || true
            sudo zypper refresh
            sudo zypper install -y google-chrome-stable
            ;;
    esac
}

uninstall_google_chrome() {
    info "Uninstalling Google Chrome..."
    case "$DISTRO_FAMILY" in
        debian)
            sudo apt purge --autoremove -y google-chrome-stable
            sudo apt autoclean
            sudo rm -f /etc/apt/sources.list.d/google-chrome.list
            sudo rm -f /usr/share/keyrings/google-chrome-keyring.gpg
            ;;
        fedora|rhel)
            sudo "$PKG_MGR" remove -y google-chrome-stable
            sudo rm -f /etc/yum.repos.d/google-chrome.repo
            ;;
        arch)
            aur_remove google-chrome 2>/dev/null || pkg_remove google-chrome 2>/dev/null || true
            ;;
        suse)
            sudo zypper remove -y google-chrome-stable
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
            sudo apt upgrade -y google-chrome-stable
            ;;
        arch)
            if has_aur_helper; then
                aur_upgrade google-chrome
            else
                aur_build google-chrome
            fi
            ;;
        *)
            pkg_upgrade google-chrome-stable
            ;;
    esac
}

get_version_google_chrome() {
    local cmd
    for cmd in google-chrome-stable google-chrome; do
        command -v "$cmd" &>/dev/null || continue
        "$cmd" --version 2>/dev/null | grep -oP 'Google Chrome \K[0-9]+\.[0-9]+\.[0-9]+(\.[0-9]+)?' && return
    done
    echo ""
}

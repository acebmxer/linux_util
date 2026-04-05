#!/bin/bash
# ProtonUp-Qt installer functions

# --- ProtonUp-Qt ---

check_protonup_qt() {
    command -v protonup-qt &>/dev/null || \
        (has_flatpak && flatpak list 2>/dev/null | grep -qi "net.davidotek.pupgui2")
}

install_protonup_qt() {
    info "Installing ProtonUp-Qt..."
    ensure_tools
    case "$DISTRO_FAMILY" in
        arch)
            if has_aur_helper; then
                aur_install protonup-qt
            else
                aur_build protonup-qt
            fi
            ;;
        *)
            # Flatpak is the primary distribution method on all other distros
            if has_flatpak; then
                flatpak install -y flathub net.davidotek.pupgui2
            else
                error "ProtonUp-Qt requires Flatpak on this system. Install Flatpak first."
                return 1
            fi
            ;;
    esac
    info "ProtonUp-Qt installed."
}

uninstall_protonup_qt() {
    info "Uninstalling ProtonUp-Qt..."
    if has_flatpak && flatpak list 2>/dev/null | grep -qi "net.davidotek.pupgui2"; then
        flatpak uninstall -y net.davidotek.pupgui2
    else
        case "$DISTRO_FAMILY" in
            arch)
                aur_remove protonup-qt 2>/dev/null || \
                    sudo pacman -Rs --noconfirm protonup-qt 2>/dev/null || true
                ;;
        esac
    fi
}

update_protonup_qt() {
    info "Updating ProtonUp-Qt..."
    if has_flatpak && flatpak list 2>/dev/null | grep -qi "net.davidotek.pupgui2"; then
        flatpak update -y net.davidotek.pupgui2
    else
        case "$DISTRO_FAMILY" in
            arch)
                if has_aur_helper; then
                    aur_upgrade protonup-qt
                else
                    aur_build protonup-qt
                fi
                ;;
        esac
    fi
}

get_version_protonup_qt() {
    protonup-qt --version 2>/dev/null | grep -oP '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || \
    (has_flatpak && flatpak list 2>/dev/null | grep -i "net.davidotek.pupgui2" | awk -F'\t' '{print $3}') || \
    echo ""
}

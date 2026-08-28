#!/bin/bash
# ProtonUp-Qt installer functions

# --- ProtonUp-Qt ---

check_protonup_qt() { _check_standard protonup-qt "" net.davidotek.pupgui2; }

install_protonup_qt() {
    info "Installing ProtonUp-Qt..."
    ensure_tools
    case "$DISTRO_FAMILY" in
        arch)
            flatpak_or_aur net.davidotek.pupgui2 protonup-qt
            ;;
        *)
            # Flatpak is the primary distribution method on all other distros
            if has_flatpak; then
                sudo flatpak install -y flathub net.davidotek.pupgui2
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
    if flatpak_is_installed "net.davidotek.pupgui2"; then
        flatpak uninstall -y --user net.davidotek.pupgui2 2>/dev/null || \
            sudo flatpak uninstall -y --system net.davidotek.pupgui2
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
    if flatpak_is_installed "net.davidotek.pupgui2"; then
        flatpak update -y --user net.davidotek.pupgui2 2>/dev/null || \
            sudo flatpak update -y --system net.davidotek.pupgui2
    else
        case "$DISTRO_FAMILY" in
            arch)
                repo_or_aur protonup-qt
                ;;
        esac
    fi
}

get_version_protonup_qt() {
    _ver_from_cmd protonup-qt || _ver_from_flatpak net.davidotek.pupgui2 || echo ""
}

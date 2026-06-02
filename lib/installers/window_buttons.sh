#!/bin/bash
# Window Button Layout — ensures window title bars show minimize, maximize and
# close buttons.
#
# Why this exists: on GNOME (and notably under WSLg, where Ubuntu's GTK apps run
# through a GNOME-style compositor) the default window-manager button layout
# omits minimize/maximize, so GTK apps like Remmina, Nautilus and Files show only
# a close button. The window-manager preference below restores all three.
#
# This is a per-USER setting (written to dconf/xfconf), so it must run as the
# regular user — never under sudo. The main script already refuses to run as
# root, so the calling environment is correct and we invoke gsettings/xfconf
# directly (no privilege-drop shim needed).
#
# The setting is read by the window manager / compositor, not the toolkit. On
# GNOME/Mutter the org.gnome.desktop.wm.preferences key applies to every window
# it decorates. KDE/KWin ignores this key entirely (it reads kwinrc) and already
# shows all three buttons by default, so KDE is intentionally skipped.

# detect_window_button_de echoes a normalized desktop-environment token used to
# pick the right command: gnome | cinnamon | mate | xfce | kde | unknown.
# Detection is best-effort: the XDG_CURRENT_DESKTOP / DESKTOP_SESSION hints are
# checked first, then a fallback probes for the relevant gsettings schema or the
# xfconf-query binary.
detect_window_button_de() {
    local hint="${XDG_CURRENT_DESKTOP:-}${DESKTOP_SESSION:+:${DESKTOP_SESSION}}"
    # Lower-case for case-insensitive matching (bash 4+, already required).
    hint="${hint,,}"

    case "$hint" in
        *kde*|*plasma*)          printf 'kde';      return 0 ;;
        *cinnamon*)              printf 'cinnamon'; return 0 ;;
        *mate*)                  printf 'mate';     return 0 ;;
        *xfce*)                  printf 'xfce';     return 0 ;;
        *gnome*|*unity*|*budgie*|*ubuntu*) printf 'gnome'; return 0 ;;
    esac

    # No usable hint (common under WSLg, which may leave these vars empty) —
    # probe for an available mechanism. Prefer the GNOME schema since that is
    # the WSLg case this task primarily targets.
    if command -v gsettings >/dev/null 2>&1; then
        if gsettings list-schemas 2>/dev/null | grep -q '^org\.gnome\.desktop\.wm\.preferences$'; then
            printf 'gnome'; return 0
        fi
        if gsettings list-schemas 2>/dev/null | grep -q '^org\.cinnamon\.desktop\.wm\.preferences$'; then
            printf 'cinnamon'; return 0
        fi
        if gsettings list-schemas 2>/dev/null | grep -q '^org\.mate\.Marco\.general$'; then
            printf 'mate'; return 0
        fi
    fi
    if command -v xfconf-query >/dev/null 2>&1; then
        printf 'xfce'; return 0
    fi

    printf 'unknown'
    return 0
}

install_window_buttons() {
    # A GUI/session bus is required for these settings to take effect. Under bare
    # WSL (no WSLg) there is no session bus, so warn rather than fail obscurely.
    if [[ -z "${DBUS_SESSION_BUS_ADDRESS:-}" ]] \
       && [[ -z "${WAYLAND_DISPLAY:-}" ]] \
       && [[ -z "${DISPLAY:-}" ]]; then
        warn "No graphical session detected (no D-Bus/Wayland/X display)."
        echo "  This setting only applies to a desktop session. If you are on bare"
        echo "  WSL without WSLg, there are no app windows to decorate. Re-run this"
        echo "  from inside a graphical session (WSLg, or a native desktop)."
        return 0
    fi

    local de
    de="$(detect_window_button_de)"

    case "$de" in
        gnome)
            info "Setting GNOME window buttons to minimize, maximize, close..."
            if gsettings set org.gnome.desktop.wm.preferences button-layout \
                   ":minimize,maximize,close"; then
                info "Done. GTK apps (e.g. Remmina, Nautilus, Files) will now show all three buttons."
                echo "  Note: Qt/KDE apps such as Konsole are unaffected — they do not read this key."
            else
                error "Failed to set the GNOME button layout (is the org.gnome.desktop.wm.preferences schema present?)."
                return 1
            fi
            ;;
        cinnamon)
            info "Setting Cinnamon window buttons to minimize, maximize, close..."
            if gsettings set org.cinnamon.desktop.wm.preferences button-layout \
                   ":minimize,maximize,close"; then
                info "Done."
            else
                error "Failed to set the Cinnamon button layout."
                return 1
            fi
            ;;
        mate)
            info "Setting MATE (Marco) window buttons to minimize, maximize, close..."
            # MATE's Marco expects a "menu:..." style layout; place the window
            # menu on the left and the three buttons on the right.
            if gsettings set org.mate.Marco.general button-layout \
                   "menu:minimize,maximize,close"; then
                info "Done."
            else
                error "Failed to set the MATE button layout."
                return 1
            fi
            ;;
        xfce)
            info "Setting Xfce (xfwm4) window buttons to minimize, maximize, close..."
            # xfwm4 button_layout uses single-letter codes: O=menu, S=stick,
            # H=hide(minimize), M=maximize, C=close, T=title, | separates
            # left|right groups. "O|HMC" = menu on the left; hide, maximize,
            # close on the right.
            if xfconf-query -c xfwm4 -p /general/button_layout -s "O|HMC"; then
                info "Done."
            else
                error "Failed to set the Xfce button layout (is xfconf-query / xfwm4 available?)."
                return 1
            fi
            ;;
        kde)
            info "KDE Plasma already shows minimize, maximize and close by default — nothing to do."
            echo "  KWin ignores the GNOME button-layout key; adjust buttons via"
            echo "  System Settings > Window Management > Window Decorations if needed."
            ;;
        *)
            warn "Could not determine the desktop environment — no button-layout change made."
            echo "  Supported here: GNOME, Cinnamon, MATE, Xfce. KDE needs no change."
            ;;
    esac

    return 0
}

uninstall_window_buttons() {
    # Nothing to remove — this is a one-shot preference change, not an install.
    return 0
}

update_window_buttons() {
    install_window_buttons
}

# get_version_window_buttons reports the detected desktop environment so the menu
# info column shows useful context (e.g. "GNOME") rather than a version string.
get_version_window_buttons() {
    local de
    de="$(detect_window_button_de)"
    case "$de" in
        gnome)    printf 'GNOME' ;;
        cinnamon) printf 'Cinnamon' ;;
        mate)     printf 'MATE' ;;
        xfce)     printf 'Xfce' ;;
        kde)      printf 'KDE (no change needed)' ;;
        *)        printf 'unknown DE' ;;
    esac
    return 0
}

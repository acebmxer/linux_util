#!/bin/bash
# Fix Monitor Layout at Login — applies current Plasma monitor settings to the
# SDDM login screen so multi-monitor layout is correct before login.
#
# The user must open System Settings > Colors & Themes > Login Screen (SDDM)
# and click "Apply Plasma Settings". This task launches that settings panel.

install_fix_monitor_login() {
    info "Opening SDDM login screen settings..."
    echo
    echo "  In the Login Screen (SDDM) settings panel that opens:"
    echo "    1. Click 'Apply Plasma Settings' (top-right of the panel)"
    echo "    2. A confirmation dialog will appear — click 'Apply'"
    echo "    3. Enter your password when prompted"
    echo "    4. Close the panel when done"
    echo

    # Resolve the KCM module name by checking for the plugin file, avoiding the
    # fallback where kcmshell picks up /usr/bin/sddm instead of the KCM module.
    local kcm_module=""
    if find /usr/lib /usr/share/plasma /usr/share/kservices5 \
            -name "kcm_sddm*" 2>/dev/null | grep -q .; then
        kcm_module="kcm_sddm"
    elif find /usr/share/kservices5 /usr/share/plasma \
            -name "sddm.desktop" 2>/dev/null | grep -q .; then
        kcm_module="sddm"
    fi

    local launched=false
    if [[ -n "$kcm_module" ]]; then
        if command -v kcmshell6 &>/dev/null; then
            kcmshell6 "$kcm_module" &>/dev/null &
            launched=true
        elif command -v kcmshell5 &>/dev/null; then
            kcmshell5 "$kcm_module" &>/dev/null &
            launched=true
        fi
    fi

    if ! $launched; then
        warn "Could not find the SDDM KCM module (is sddm-kcm / plasma-workspace installed?)."
        echo "  Open System Settings > Colors & Themes > Login Screen (SDDM) manually"
        echo "  and click 'Apply Plasma Settings'."
    fi

    echo "Press Enter when you have applied the settings..."
    read -r < /dev/tty
    info "Monitor layout fix applied."
}

uninstall_fix_monitor_login() {
    return 0
}

update_fix_monitor_login() {
    install_fix_monitor_login
}

get_version_fix_monitor_login() {
    return 0
}

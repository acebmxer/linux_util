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
    echo "    1. Click 'Apply Plasma Settings'"
    echo "    2. Enter your password if prompted"
    echo "    3. Close the panel when done"
    echo

    # Launch SDDM KCM module (KDE Plasma 6 first, fall back to Plasma 5)
    if command -v kcmshell6 &>/dev/null; then
        kcmshell6 sddm &>/dev/null &
    elif command -v kcmshell5 &>/dev/null; then
        kcmshell5 sddm &>/dev/null &
    else
        warn "Could not find kcmshell6 or kcmshell5."
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

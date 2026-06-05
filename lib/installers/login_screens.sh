#!/bin/bash
# Login Screens — display managers (the login screen itself) and login themes,
# offered as standalone building blocks so a headless system can assemble a GUI
# piece by piece (DE/WM -> display manager -> login theme).
#
# Two groups are registered from this file:
#   Display Managers : SDDM, GDM, LightDM, ly, LXDM  (install + optionally make active)
#   Login Themes     : SDDM themes (Breeze, Sugar Candy, Astronaut) + LightDM Slick greeter
#
# IMPORTANT: only one display manager may be enabled at a time — two enabled DMs
# race for the VT and break graphical boot. _set_active_dm() disables every other
# known DM before enabling the chosen one. Installs never `systemctl start` a DM
# (that would kill the current session over SSH); they enable it and ask for a
# reboot instead.

# ----------------------------------------------------------------------------
# Shared helpers
# ----------------------------------------------------------------------------

# All display-manager systemd units we know about (used to enforce one-at-a-time).
_KNOWN_DM_SERVICES=(gdm gdm3 sddm lightdm lxdm ly)

# Print the basename of the unit that /etc/systemd/system/display-manager.service
# currently points at (e.g. "sddm.service"), or nothing if no DM is active.
_active_dm_service() {
    local link
    link="$(readlink -f /etc/systemd/system/display-manager.service 2>/dev/null)" || return 0
    [[ -n "$link" ]] && basename "$link"
}

# Make $1 (a bare service name, e.g. "sddm") the active login screen: disable any
# other known DM, ensure the system boots to graphical, then enable this one.
_set_active_dm() {
    local svc="$1" other
    for other in "${_KNOWN_DM_SERVICES[@]}"; do
        [[ "$other" == "$svc" ]] && continue
        run_as_root systemctl disable "${other}.service" >/dev/null 2>&1 || true
    done
    run_as_root systemctl set-default graphical.target >/dev/null 2>&1 || true
    if run_as_root systemctl enable "${svc}.service" >/dev/null 2>&1; then
        info "Enabled ${svc} as the active login screen."
        return 0
    fi
    warn "Could not enable ${svc}.service — enable it manually with: sudo systemctl enable ${svc}"
    return 1
}

# Shared install flow for a display manager.
#   $1 = display label   $2 = bare service name   $3.. = package(s) to install
# Installs the package(s), then enables the DM automatically when none is active,
# or asks before replacing an existing active DM.
_install_dm() {
    local label="$1" service="$2"; shift 2
    local pkgs=("$@")

    info "Installing ${label} login screen..."
    ensure_tools
    if ! pkg_install "${pkgs[@]}"; then
        error "Failed to install ${label} (package may be unavailable on ${DISTRO_ID})."
        return 1
    fi

    local current; current="$(_active_dm_service)"
    if [[ -z "$current" ]]; then
        info "No active login screen detected — enabling ${label}."
        _set_active_dm "$service"
    elif [[ "$current" == "${service}.service" ]]; then
        info "${label} is already the active login screen."
        run_as_root systemctl set-default graphical.target >/dev/null 2>&1 || true
    else
        echo
        if _confirm_step "Make ${label} the active login screen now (replaces ${current%.service})?"; then
            _set_active_dm "$service"
        else
            info "${label} installed but left inactive. Current login screen: ${current%.service}."
        fi
    fi

    info "${label} setup complete. Reboot to use it."
    return 0
}

# Common uninstall: remove package(s) and drop the DM from the enabled set.
#   $1 = display label   $2 = bare service name   $3.. = package(s) to remove
_uninstall_dm() {
    local label="$1" service="$2"; shift 2
    if [[ "$(_active_dm_service)" == "${service}.service" ]]; then
        warn "${label} is the active login screen. Install or enable another display"
        warn "manager first, or you may boot to a black screen."
        _confirm_step "Remove ${label} anyway?" || { info "Aborted."; return 0; }
    fi
    run_as_root systemctl disable "${service}.service" >/dev/null 2>&1 || true
    pkg_remove "$@" || warn "Package removal reported an error."
    info "${label} removed."
    return 0
}

# Echo "<version> (active)" / "<version>" / "active" for the DM status column.
#   $1 = package name   $2 = bare service name
_dm_version() {
    local pkg="$1" svc="$2" ver active=""
    ver="$(pkg_get_version "$pkg" 2>/dev/null | sed 's/^[0-9]*://; s/-.*//')"
    [[ "$(_active_dm_service)" == "${svc}.service" ]] && active=" (active)"
    if [[ -n "$ver" ]]; then
        echo "${ver}${active}"
    elif [[ -n "$active" ]]; then
        echo "active"
    fi
}

# The GDM package/service is named gdm3 on Debian/Ubuntu, gdm everywhere else.
_gdm_name() { [[ "$PKG_MGR" == "apt" ]] && echo "gdm3" || echo "gdm"; }

# ----------------------------------------------------------------------------
# Display manager: SDDM
# ----------------------------------------------------------------------------
install_dm_sddm()   { _install_dm "SDDM" "sddm" sddm; }
check_dm_sddm()     { command -v sddm &>/dev/null || pkg_check_installed sddm; }
uninstall_dm_sddm() { _uninstall_dm "SDDM" "sddm" sddm; }
update_dm_sddm()    { pkg_upgrade sddm; }
get_version_dm_sddm() { _dm_version sddm sddm; }

# ----------------------------------------------------------------------------
# Display manager: GDM (GNOME) — gdm3 on Debian/Ubuntu
# ----------------------------------------------------------------------------
install_dm_gdm()   { local n; n="$(_gdm_name)"; _install_dm "GDM" "$n" "$n"; }
check_dm_gdm()     { pkg_check_installed "$(_gdm_name)"; }
uninstall_dm_gdm() { local n; n="$(_gdm_name)"; _uninstall_dm "GDM" "$n" "$n"; }
update_dm_gdm()    { pkg_upgrade "$(_gdm_name)"; }
get_version_dm_gdm() { local n; n="$(_gdm_name)"; _dm_version "$n" "$n"; }

# ----------------------------------------------------------------------------
# Display manager: LightDM (+ GTK greeter so a login form actually renders)
# ----------------------------------------------------------------------------
install_dm_lightdm() {
    local greeter
    case "$PKG_MGR" in
        apt)     greeter="lightdm-gtk-greeter" ;;
        dnf|yum) greeter="lightdm-gtk" ;;
        *)       greeter="lightdm-gtk-greeter" ;;
    esac
    _install_dm "LightDM" "lightdm" lightdm "$greeter"
}
check_dm_lightdm()     { command -v lightdm &>/dev/null || pkg_check_installed lightdm; }
uninstall_dm_lightdm() { _uninstall_dm "LightDM" "lightdm" lightdm; }
update_dm_lightdm()    { pkg_upgrade lightdm; }
get_version_dm_lightdm() { _dm_version lightdm lightdm; }

# ----------------------------------------------------------------------------
# Display manager: ly (lightweight TUI login). Packaged on Arch and openSUSE;
# elsewhere the package may be absent — the install fails cleanly if so.
# ----------------------------------------------------------------------------
install_dm_ly()   { _install_dm "ly" "ly" ly; }
check_dm_ly()     { command -v ly &>/dev/null || pkg_check_installed ly; }
uninstall_dm_ly() { _uninstall_dm "ly" "ly" ly; }
update_dm_ly()    { pkg_upgrade ly; }
get_version_dm_ly() { _dm_version ly ly; }

# ----------------------------------------------------------------------------
# Display manager: LXDM (lightweight GTK login)
# ----------------------------------------------------------------------------
install_dm_lxdm()   { _install_dm "LXDM" "lxdm" lxdm; }
check_dm_lxdm()     { command -v lxdm &>/dev/null || pkg_check_installed lxdm; }
uninstall_dm_lxdm() { _uninstall_dm "LXDM" "lxdm" lxdm; }
update_dm_lxdm()    { pkg_upgrade lxdm; }
get_version_dm_lxdm() { _dm_version lxdm lxdm; }

# ----------------------------------------------------------------------------
# SDDM theme helpers
# ----------------------------------------------------------------------------
SDDM_THEMES_DIR="/usr/share/sddm/themes"

# Write the drop-in that selects the active SDDM theme. Numbered 90- so it sorts
# after distro drop-ins (e.g. Kubuntu ships /etc/sddm.conf.d/20-kubuntu.conf,
# which we must override to actually change the login theme).
_set_sddm_theme() {
    local theme="$1"
    run_as_root mkdir -p /etc/sddm.conf.d
    printf '[Theme]\nCurrent=%s\n' "$theme" | run_as_root tee /etc/sddm.conf.d/90-linux_util-theme.conf >/dev/null
    info "SDDM login theme set to '${theme}'."
    _dedupe_ubuntu_sddm_theme
}

# Echo the currently configured SDDM theme name (last Current= wins).
_sddm_active_theme() {
    grep -rhoP '^\s*Current\s*=\s*\K\S+' \
        /etc/sddm.conf /etc/sddm.conf.d/ /usr/lib/sddm/sddm.conf.d/ 2>/dev/null | tail -1
}

# Ubuntu registers its SDDM theme packages (sddm-theme-breeze, sddm-theme-maya, …)
# under the `sddm-ubuntu-theme` update-alternatives group, which creates
# /usr/share/sddm/themes/ubuntu-theme as a symlink to the highest-priority theme.
# KDE's SDDM KCM then lists that symlink as a *second* tile for whatever real theme
# it resolves to (e.g. Breeze appears twice). Drop the alternatives group so each
# theme shows once. Guarded: apt-only, a no-op if the symlink is absent, and never
# removed while SDDM is actually configured to use "ubuntu-theme" (removing it then
# would leave the login screen pointing at a missing theme).
_dedupe_ubuntu_sddm_theme() {
    [[ "$PKG_MGR" == "apt" ]] || return 0
    [[ -L /usr/share/sddm/themes/ubuntu-theme ]] || return 0
    [[ "$(_sddm_active_theme)" == "ubuntu-theme" ]] && return 0
    if run_as_root update-alternatives --remove-all sddm-ubuntu-theme >/dev/null 2>&1; then
        info "Removed Ubuntu's duplicate 'ubuntu-theme' alternative (it showed the active theme twice in the SDDM theme list)."
    fi
}

# Remove our theme drop-in (reverts SDDM to the distro default theme).
_clear_sddm_theme_override() {
    run_as_root rm -f /etc/sddm.conf.d/90-linux_util-theme.conf 2>/dev/null || true
}

# Best-effort Qt5 QtQuick runtime for community SDDM themes (Sugar Candy renders
# blank without these). Astronaut is Qt6-only and uses _install_sddm_qml_deps_qt6
# instead. Non-fatal if a name is missing.
_install_sddm_qml_deps() {
    case "$PKG_MGR" in
        apt)     pkg_install qml-module-qtquick-controls2 qml-module-qtgraphicaleffects \
                             qml-module-qtquick-layouts qml-module-qtquick-window2 ;;
        dnf|yum) pkg_install qt5-qtquickcontrols2 qt5-qtgraphicaleffects ;;
        pacman)  pkg_install qt5-quickcontrols2 qt5-graphicaleffects ;;
        zypper)  pkg_install libqt5-qtquickcontrols2 libqt5-qtgraphicaleffects ;;
    esac || warn "Some QtQuick dependencies may be missing; the theme could render blank."
}

# True when this system's SDDM is built against Qt6. The SDDM daemon and the
# greeter that renders QtQuick themes share the same Qt build, so the daemon's
# linkage is a reliable proxy; a dedicated sddm-greeter-qt6 binary (shipped by
# some distros) is an extra positive signal. Qt6 matters because newer community
# themes (e.g. Astronaut) import Qt6-only QML modules — a Qt5 greeter rejects
# them with "Library import requires a version".
_sddm_is_qt6() {
    command -v sddm-greeter-qt6 &>/dev/null && return 0
    local bin
    for bin in "$(command -v sddm 2>/dev/null)" /usr/bin/sddm /usr/sbin/sddm; do
        [[ -x "$bin" ]] && ldd "$bin" 2>/dev/null | grep -q 'libQt6Core' && return 0
    done
    return 1
}

# Best-effort Qt6 QtQuick runtime for the Astronaut theme (upstream master is
# Qt6-only: it imports QtQuick.Effects and QtMultimedia without versions). Each
# package is installed on its own because apt/dnf/pacman/zypper all abort the
# whole batch on a single unknown name, and these module names vary by distro.
_install_sddm_qml_deps_qt6() {
    local pkgs=() p
    case "$PKG_MGR" in
        apt)     pkgs=(qml6-module-qtquick-controls qml6-module-qtquick-layouts
                       qml6-module-qtquick-effects qml6-module-qtquick-window
                       qml6-module-qtmultimedia qml6-module-qtquick-virtualkeyboard
                       libqt6svg6) ;;
        dnf|yum) pkgs=(qt6-qtdeclarative qt6-qtsvg qt6-qtmultimedia
                       qt6-qtvirtualkeyboard) ;;
        pacman)  pkgs=(qt6-declarative qt6-svg qt6-multimedia qt6-virtualkeyboard) ;;
        zypper)  pkgs=(libQt6Svg6 qt6-multimedia-imports qt6-quickcontrols2-imports
                       qt6-virtualkeyboard-imports) ;;
    esac
    for p in "${pkgs[@]}"; do
        pkg_install "$p" >/dev/null 2>&1 || \
            warn "Optional Qt6 module '${p}' unavailable; the theme may render incomplete."
    done
}

# Download a community SDDM theme tarball and install it into the themes dir.
#   $1 = label   $2 = theme dir name   $3 = tarball URL
#   $4 = QML runtime generation: "qt5" (default) or "qt6"
_install_sddm_community_theme() {
    local label="$1" dir="$2" url="$3" qt_gen="${4:-qt5}"
    if [[ ! -d "$SDDM_THEMES_DIR" ]]; then
        error "SDDM is not installed. Install the SDDM login screen first (Login Screens > SDDM)."
        return 1
    fi
    ensure_tools
    check_internet || true
    info "Installing ${label} SDDM theme..."
    if [[ "$qt_gen" == "qt6" ]]; then
        _install_sddm_qml_deps_qt6
    else
        _install_sddm_qml_deps
    fi

    local tmp; tmp="$(mktemp -d)"
    if ! download_file "$url" "${tmp}/theme.tar.gz"; then
        error "Failed to download ${label} theme."
        rm -rf "$tmp"; return 1
    fi
    if ! tar -xzf "${tmp}/theme.tar.gz" -C "$tmp"; then
        error "Failed to extract ${label} theme archive."
        rm -rf "$tmp"; return 1
    fi
    local src; src="$(find "$tmp" -mindepth 1 -maxdepth 1 -type d | head -1)"
    if [[ -z "$src" ]]; then
        error "Unexpected archive layout for ${label}."
        rm -rf "$tmp"; return 1
    fi

    run_as_root rm -rf "${SDDM_THEMES_DIR:?}/${dir}"
    if ! run_as_root cp -rT "$src" "${SDDM_THEMES_DIR}/${dir}"; then
        error "Failed to install ${label} theme files."
        rm -rf "$tmp"; return 1
    fi
    rm -rf "$tmp"
    _set_sddm_theme "$dir"
    info "${label} installed and set as the SDDM login theme."
    return 0
}

_uninstall_sddm_community_theme() {
    local label="$1" dir="$2"
    [[ "$(_sddm_active_theme)" == "$dir" ]] && _clear_sddm_theme_override
    run_as_root rm -rf "${SDDM_THEMES_DIR:?}/${dir}"
    info "${label} theme removed."
    return 0
}

# ----------------------------------------------------------------------------
# SDDM theme: Breeze (the upstream KDE default; ships with Plasma)
# ----------------------------------------------------------------------------
install_sddmtheme_breeze() {
    if [[ ! -d "$SDDM_THEMES_DIR" ]]; then
        error "SDDM is not installed. Install the SDDM login screen first (Login Screens > SDDM)."
        return 1
    fi
    # On Debian/Ubuntu the theme ships as a small standalone package; elsewhere it
    # comes with Plasma, so we only pull it where it exists on its own.
    [[ "$PKG_MGR" == "apt" ]] && { pkg_install sddm-theme-breeze || true; }
    if [[ ! -d "${SDDM_THEMES_DIR}/breeze" ]]; then
        error "Breeze theme files not found. Breeze is part of KDE Plasma — install the"
        error "KDE Desktop (or its breeze components) to get it."
        return 1
    fi
    _set_sddm_theme "breeze"
    info "Breeze set as the SDDM login theme."
    return 0
}
check_sddmtheme_breeze()     { [[ -d "${SDDM_THEMES_DIR}/breeze" ]]; }
uninstall_sddmtheme_breeze() {
    # Breeze files are shared with Plasma — only drop our override, never the files.
    [[ "$(_sddm_active_theme)" == "breeze" ]] && _clear_sddm_theme_override
    info "Reverted SDDM theme override (Breeze files left in place)."
    return 0
}
update_sddmtheme_breeze()    { install_sddmtheme_breeze; }
get_version_sddmtheme_breeze() { [[ "$(_sddm_active_theme)" == "breeze" ]] && echo "active" || true; }

# ----------------------------------------------------------------------------
# SDDM theme: Sugar Candy (popular QtQuick theme)
# ----------------------------------------------------------------------------
# The original MarianArlt/sddm-sugar-candy repo (and account) was deleted from
# GitHub, so its tarball 404s permanently. Kangie/sddm-sugar-candy is the stable
# GPL-3.0 mirror (archived/read-only, which is fine — the theme is feature-frozen).
_SUGAR_CANDY_URL="https://github.com/Kangie/sddm-sugar-candy/archive/refs/heads/master.tar.gz"
install_sddmtheme_sugar_candy()   { _install_sddm_community_theme "Sugar Candy" "sugar-candy" "$_SUGAR_CANDY_URL"; }
check_sddmtheme_sugar_candy()     { [[ -d "${SDDM_THEMES_DIR}/sugar-candy" ]]; }
uninstall_sddmtheme_sugar_candy() { _uninstall_sddm_community_theme "Sugar Candy" "sugar-candy"; }
update_sddmtheme_sugar_candy()    { install_sddmtheme_sugar_candy; }
get_version_sddmtheme_sugar_candy() { [[ "$(_sddm_active_theme)" == "sugar-candy" ]] && echo "active" || true; }

# ----------------------------------------------------------------------------
# SDDM theme: Astronaut (QtQuick theme bundle)
# ----------------------------------------------------------------------------
# Upstream master is Qt6-only (qt6 >= 6.8; Main.qml imports QtQuick.Effects and
# QtMultimedia, both Qt6) with no Qt5 branch or release to fall back to. On a Qt5
# SDDM the greeter shows "Library import requires a version", so refuse there and
# point at Sugar Candy (the Qt5-compatible option) rather than activating a theme
# that can only render as that red error screen.
_ASTRONAUT_URL="https://github.com/Keyitdev/sddm-astronaut-theme/archive/refs/heads/master.tar.gz"
install_sddmtheme_astronaut() {
    if [[ ! -d "$SDDM_THEMES_DIR" ]]; then
        error "SDDM is not installed. Install the SDDM login screen first (Login Screens > SDDM)."
        return 1
    fi
    if ! _sddm_is_qt6; then
        error "The Astronaut theme requires an SDDM built with Qt6, but this system's SDDM"
        error "is Qt5. Its Main.qml imports Qt6-only modules (QtQuick.Effects, QtMultimedia),"
        error "so a Qt5 login screen rejects it with 'Library import requires a version'."
        error "Use the Sugar Candy theme instead (Qt5-compatible), or move to a distro"
        error "release whose SDDM is built on Qt6."
        return 1
    fi
    _install_sddm_community_theme "Astronaut" "sddm-astronaut-theme" "$_ASTRONAUT_URL" qt6
}
check_sddmtheme_astronaut()     { [[ -d "${SDDM_THEMES_DIR}/sddm-astronaut-theme" ]]; }
uninstall_sddmtheme_astronaut() { _uninstall_sddm_community_theme "Astronaut" "sddm-astronaut-theme"; }
update_sddmtheme_astronaut()    { install_sddmtheme_astronaut; }
get_version_sddmtheme_astronaut() { [[ "$(_sddm_active_theme)" == "sddm-astronaut-theme" ]] && echo "active" || true; }

# ----------------------------------------------------------------------------
# LightDM theme: Slick Greeter (themeable GTK greeter used by Mint)
# ----------------------------------------------------------------------------
install_lightdmtheme_slick() {
    if ! check_dm_lightdm; then
        error "LightDM is not installed. Install the LightDM login screen first (Login Screens > LightDM)."
        return 1
    fi
    info "Installing the Slick greeter for LightDM..."
    if ! pkg_install slick-greeter; then
        error "slick-greeter is not packaged for ${DISTRO_ID}. Try lightdm-gtk-greeter instead."
        return 1
    fi
    run_as_root mkdir -p /etc/lightdm/lightdm.conf.d
    printf '[Seat:*]\ngreeter-session=slick-greeter\n' \
        | run_as_root tee /etc/lightdm/lightdm.conf.d/90-linux_util-slick.conf >/dev/null
    info "Slick greeter installed and selected for LightDM."
    info "Customise it via /etc/lightdm/slick-greeter.conf (background, theme, icons)."
    return 0
}
check_lightdmtheme_slick()     { command -v slick-greeter &>/dev/null || pkg_check_installed slick-greeter; }
uninstall_lightdmtheme_slick() {
    run_as_root rm -f /etc/lightdm/lightdm.conf.d/90-linux_util-slick.conf 2>/dev/null || true
    pkg_remove slick-greeter || warn "Package removal reported an error."
    info "Slick greeter removed. LightDM will fall back to its default greeter."
    return 0
}
update_lightdmtheme_slick()    { pkg_upgrade slick-greeter; }
get_version_lightdmtheme_slick() {
    pkg_get_version slick-greeter 2>/dev/null | sed 's/^[0-9]*://; s/-.*//'
}

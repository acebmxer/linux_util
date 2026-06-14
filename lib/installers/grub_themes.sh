#!/bin/bash
# GRUB Themes — community boot-menu themes for the GRUB bootloader.
#
# Each entry installs a theme into GRUB's themes directory, points
# /etc/default/grub at its theme.txt (GRUB_THEME=), and regenerates grub.cfg.
# Themes are only meaningful when GRUB is the active bootloader, so every
# installer refuses to run until the GRUB bootloader itself is present.
#
# Themes offered:
#   Distro GRUB Themes  — AdisonCavani/distro-grub-themes  (per-distro logo themes)
#   vinceliuice GRUB    — vinceliuice/grub2-themes          (tela/vimix/stylish/...)
#   Catppuccin GRUB     — catppuccin/grub                   (mocha/macchiato/...)
#   HyperFluent GRUB    — Coopydood/HyperFluent-GRUB-Theme  (sleek per-distro theme)

# ----------------------------------------------------------------------------
# Shared helpers
# ----------------------------------------------------------------------------

# GRUB's data dir is /boot/grub on Debian/Arch and /boot/grub2 on RHEL/Fedora/SUSE.
# Pick whichever exists; fall back to the distro-family convention.
_grub_dir() {
    if   [[ -d /boot/grub  ]]; then echo /boot/grub
    elif [[ -d /boot/grub2 ]]; then echo /boot/grub2
    elif [[ "$DISTRO_FAMILY" =~ ^(fedora|rhel|suse)$ ]]; then echo /boot/grub2
    else echo /boot/grub
    fi
}
_grub_themes_dir() { echo "$(_grub_dir)/themes"; }
_grub_cfg_path()   { echo "$(_grub_dir)/grub.cfg"; }

# Refuse to theme a GRUB that isn't installed (reuses check_grub from grub.sh).
_grub_themes_require_grub() {
    if ! check_grub; then
        error "GRUB is not installed. Install the GRUB bootloader first (Bootloaders > GRUB)."
        return 1
    fi
    return 0
}

# Regenerate grub.cfg using whichever generator this distro ships.
_grub_regenerate() {
    if command -v update-grub &>/dev/null; then
        run_as_root update-grub
    elif command -v grub2-mkconfig &>/dev/null; then
        run_as_root grub2-mkconfig -o "$(_grub_cfg_path)"
    elif command -v grub-mkconfig &>/dev/null; then
        run_as_root grub-mkconfig -o "$(_grub_cfg_path)"
    else
        warn "No grub-mkconfig/update-grub found — regenerate your GRUB config manually."
        return 1
    fi
}

# Echo the theme.txt path currently set via GRUB_THEME= in /etc/default/grub.
_grub_active_theme() {
    [[ -f /etc/default/grub ]] || return 0
    local line
    line="$(grep -E '^[[:space:]]*GRUB_THEME=' /etc/default/grub 2>/dev/null | tail -1)"
    [[ -z "$line" ]] && return 0
    line="${line#*=}"
    line="${line%\"}"; line="${line#\"}"
    line="${line%\'}"; line="${line#\'}"
    printf '%s' "$line"
}

# Point GRUB at a theme.txt and regenerate the config.
#   $1 = absolute path to the theme.txt to activate
_grub_set_theme() {
    local theme_txt="$1" def=/etc/default/grub
    run_as_root touch "$def"
    # Drop any existing GRUB_THEME line (active or commented), then append ours.
    run_as_root sed -i -E '/^[[:space:]]*#?[[:space:]]*GRUB_THEME=/d' "$def"
    printf 'GRUB_THEME="%s"\n' "$theme_txt" | run_as_root tee -a "$def" >/dev/null
    # Graphical themes need gfxterm output; a console-only terminal hides them.
    if grep -qE '^[[:space:]]*GRUB_TERMINAL(_OUTPUT)?[[:space:]]*=.*console' "$def"; then
        run_as_root sed -i -E \
            's/^([[:space:]]*GRUB_TERMINAL(_OUTPUT)?[[:space:]]*=.*console.*)$/#\1  # disabled by linux_util: console terminal hides graphical GRUB themes/' \
            "$def"
        warn "Commented out a console-only GRUB_TERMINAL setting so the theme can render."
    fi
    info "Set GRUB_THEME to ${theme_txt}."
    _grub_regenerate
}

# Remove the GRUB_THEME setting (reverts GRUB to its default text menu) and regenerate.
_grub_clear_theme() {
    [[ -f /etc/default/grub ]] && \
        run_as_root sed -i -E '/^[[:space:]]*GRUB_THEME=/d' /etc/default/grub
    _grub_regenerate
}

# Copy a ready-made theme directory into the GRUB themes dir under a fixed name
# and activate it. The source dir must contain a theme.txt.
#   $1 = label   $2 = source dir   $3 = installed dir name (under themes/)
_grub_install_local_theme() {
    local label="$1" src="$2" name="$3"
    local themes_dir; themes_dir="$(_grub_themes_dir)"
    if [[ -z "$src" || ! -f "$src/theme.txt" ]]; then
        error "${label}: theme.txt not found in the downloaded archive (upstream layout changed)."
        return 1
    fi
    run_as_root mkdir -p "$themes_dir"
    run_as_root rm -rf "${themes_dir:?}/${name}"
    if ! run_as_root cp -rT "$src" "${themes_dir}/${name}"; then
        error "${label}: failed to copy theme files into ${themes_dir}."
        return 1
    fi
    _grub_set_theme "${themes_dir}/${name}/theme.txt"
    info "${label} installed and set as the GRUB theme. Reboot to see it."
    return 0
}

# Common uninstall: revert the override if this theme is active, drop its files.
#   $1 = label   $2 = installed dir name (under themes/)
_grub_uninstall_theme() {
    local label="$1" name="$2"
    local themes_dir; themes_dir="$(_grub_themes_dir)"
    local cleared=0
    if [[ "$(_grub_active_theme)" == *"/${name}/"* ]]; then
        _grub_clear_theme   # regenerates grub.cfg
        cleared=1
    fi
    run_as_root rm -rf "${themes_dir:?}/${name}"
    (( cleared == 0 )) && _grub_regenerate
    info "${label} removed; GRUB theme reverted to the default."
    return 0
}

# Status string for the menu: "active" when this theme is the current GRUB_THEME.
#   $1 = installed dir name (under themes/)
_grub_theme_status() {
    [[ "$(_grub_active_theme)" == *"/${1}/"* ]] && echo "active" || true
}

# List installed theme directories: every subdir of the themes dir that holds a
# theme.txt. Echoes one absolute directory path (no trailing slash) per line.
_grub_list_installed_themes() {
    local themes_dir; themes_dir="$(_grub_themes_dir)"
    [[ -d "$themes_dir" ]] || return 0
    local d
    for d in "$themes_dir"/*/; do
        [[ -f "${d}theme.txt" ]] || continue
        printf '%s\n' "${d%/}"
    done
}

# Download a GitHub repo tarball, trying each candidate branch, and extract it.
# On success sets _GRUB_SRC to the extracted top-level directory.
#   $1 = label   $2 = owner/repo   $3 = tmp dir   $4.. = branches to try
_GRUB_SRC=""
_grub_download_repo() {
    local label="$1" repo="$2" tmp="$3"; shift 3
    local branches=("$@") b ok=1
    _GRUB_SRC=""
    check_internet || true
    for b in "${branches[@]}"; do
        # retries=1 so the 404 fall-through to the next branch stays quick.
        if download_file "https://github.com/${repo}/archive/refs/heads/${b}.tar.gz" "${tmp}/repo.tar.gz" 1; then
            ok=0; break
        fi
    done
    if (( ok != 0 )); then
        error "${label}: could not download from GitHub (${repo}). Check your connection."
        return 1
    fi
    if ! tar -xzf "${tmp}/repo.tar.gz" -C "$tmp"; then
        error "${label}: failed to extract the downloaded archive."
        return 1
    fi
    _GRUB_SRC="$(find "$tmp" -mindepth 1 -maxdepth 1 -type d | head -1)"
    [[ -n "$_GRUB_SRC" ]] || { error "${label}: unexpected archive layout."; return 1; }
    return 0
}

# ----------------------------------------------------------------------------
# Distro GRUB Themes (AdisonCavani/distro-grub-themes)
# A collection of per-distro logo themes shipped as individual .tar archives
# under themes/. We pick the archive matching the running distro, falling back
# to the first available so an install always produces something usable.
# ----------------------------------------------------------------------------
install_grubtheme_distro() {
    _grub_themes_require_grub || return 1
    ensure_tools
    local tmp; tmp="$(mktemp -d)"
    if ! _grub_download_repo "Distro GRUB Themes" "AdisonCavani/distro-grub-themes" "$tmp" master main; then
        rm -rf "$tmp"; return 1
    fi

    local tdir="$_GRUB_SRC/themes" tar=""
    local -a candidates=("$DISTRO_ID" "$DISTRO_FAMILY")
    case "$DISTRO_ID" in
        pop)                         candidates+=("pop-os") ;;
        opensuse*|suse|sles)         candidates+=("opensuse") ;;
        rhel|rocky|almalinux|centos) candidates+=("centos" "redhat") ;;
    esac
    local c
    for c in "${candidates[@]}"; do
        [[ -n "$c" && -f "$tdir/$c.tar" ]] && { tar="$tdir/$c.tar"; break; }
    done
    [[ -z "$tar" ]] && tar="$(find "$tdir" -maxdepth 1 -name '*.tar' 2>/dev/null | sort | head -1)"
    if [[ -z "$tar" ]]; then
        error "Distro GRUB Themes: no theme archives found in the repository."
        rm -rf "$tmp"; return 1
    fi

    info "Installing GRUB theme '$(basename "$tar" .tar)' from distro-grub-themes..."
    local ex="$tmp/extract"; mkdir -p "$ex"
    if ! tar -xf "$tar" -C "$ex"; then
        error "Distro GRUB Themes: failed to extract '$(basename "$tar")'."
        rm -rf "$tmp"; return 1
    fi
    # Locate the dir holding theme.txt: archives may be flat (theme.txt at the
    # top level alongside an icons/ subdir) or nest the theme one level down.
    local tt; tt="$(find "$ex" -name theme.txt 2>/dev/null | sort | head -1)"
    local src="${tt%/theme.txt}"
    _grub_install_local_theme "Distro GRUB Themes" "$src" "distro-grub-theme"
    local rc=$?
    rm -rf "$tmp"
    return $rc
}
check_grubtheme_distro()      { [[ -d "$(_grub_themes_dir)/distro-grub-theme" ]]; }
uninstall_grubtheme_distro()  { _grub_uninstall_theme "Distro GRUB Themes" "distro-grub-theme"; }
update_grubtheme_distro()     { install_grubtheme_distro; }
get_version_grubtheme_distro(){ _grub_theme_status "distro-grub-theme"; }

# ----------------------------------------------------------------------------
# vinceliuice GRUB Themes (vinceliuice/grub2-themes)
# Ships an install.sh that assembles the theme (from shared assets), copies it
# to the themes dir, edits /etc/default/grub, and regenerates the config itself.
# We run it with a sensible default variant; other variants are vimix, stylish,
# whitesur and slaze (rerun install.sh -t <name> to switch).
# ----------------------------------------------------------------------------
install_grubtheme_vinceliuice() {
    _grub_themes_require_grub || return 1
    ensure_tools
    local tmp; tmp="$(mktemp -d)"
    if ! _grub_download_repo "vinceliuice GRUB Themes" "vinceliuice/grub2-themes" "$tmp" master main; then
        rm -rf "$tmp"; return 1
    fi
    if [[ ! -f "$_GRUB_SRC/install.sh" ]]; then
        error "vinceliuice GRUB Themes: install.sh not found (upstream layout changed)."
        rm -rf "$tmp"; return 1
    fi
    info "Installing the 'tela' variant via the vinceliuice grub2-themes installer..."
    info "(Other variants: vimix, stylish, whitesur, slaze — rerun install.sh -t <name> to switch.)"
    if ! run_as_root bash "$_GRUB_SRC/install.sh" -t tela -s 1080p; then
        error "vinceliuice GRUB Themes: the upstream installer reported an error."
        rm -rf "$tmp"; return 1
    fi
    rm -rf "$tmp"
    info "vinceliuice 'tela' theme installed. Reboot to see it."
    return 0
}
check_grubtheme_vinceliuice() {
    [[ -d "$(_grub_themes_dir)/tela" ]] || [[ "$(_grub_active_theme)" == *"/tela/"* ]]
}
uninstall_grubtheme_vinceliuice()  { _grub_uninstall_theme "vinceliuice GRUB Themes" "tela"; }
update_grubtheme_vinceliuice()     { install_grubtheme_vinceliuice; }
get_version_grubtheme_vinceliuice(){ _grub_theme_status "tela"; }

# ----------------------------------------------------------------------------
# Catppuccin GRUB Theme (catppuccin/grub)
# Ready-made theme dirs live under src/catppuccin-<flavor>-grub-theme. We install
# the 'mocha' flavor by default; latte/frappe/macchiato are in the same src/ dir.
# ----------------------------------------------------------------------------
install_grubtheme_catppuccin() {
    _grub_themes_require_grub || return 1
    ensure_tools
    local flavor="mocha"
    local tmp; tmp="$(mktemp -d)"
    if ! _grub_download_repo "Catppuccin GRUB Theme" "catppuccin/grub" "$tmp" main master; then
        rm -rf "$tmp"; return 1
    fi
    local src="$_GRUB_SRC/src/catppuccin-${flavor}-grub-theme"
    if [[ ! -f "$src/theme.txt" ]]; then
        # Fall back to the first flavor present if the layout/name shifts.
        src="$(find "$_GRUB_SRC/src" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort | head -1)"
    fi
    info "Installing the Catppuccin (${flavor}) GRUB theme..."
    info "(Other flavors: latte, frappe, macchiato — in the repo's src/ directory.)"
    _grub_install_local_theme "Catppuccin GRUB Theme" "$src" "catppuccin-grub"
    local rc=$?
    rm -rf "$tmp"
    return $rc
}
check_grubtheme_catppuccin()      { [[ -d "$(_grub_themes_dir)/catppuccin-grub" ]]; }
uninstall_grubtheme_catppuccin()  { _grub_uninstall_theme "Catppuccin GRUB Theme" "catppuccin-grub"; }
update_grubtheme_catppuccin()     { install_grubtheme_catppuccin; }
get_version_grubtheme_catppuccin(){ _grub_theme_status "catppuccin-grub"; }

# ----------------------------------------------------------------------------
# HyperFluent GRUB Theme (Coopydood/HyperFluent-GRUB-Theme)
# A sleek modern theme with per-distro variants kept in top-level folders, each
# a ready theme dir with a theme.txt. We pick the variant matching the running
# distro, then a generic one, then any folder that has a theme.txt.
# ----------------------------------------------------------------------------
install_grubtheme_hyperfluent() {
    _grub_themes_require_grub || return 1
    ensure_tools
    local tmp; tmp="$(mktemp -d)"
    if ! _grub_download_repo "HyperFluent GRUB Theme" "Coopydood/HyperFluent-GRUB-Theme" "$tmp" main master; then
        rm -rf "$tmp"; return 1
    fi
    local src="" c
    local -a candidates=("$DISTRO_ID" "$DISTRO_FAMILY" "hyperfluent" "arch")
    for c in "${candidates[@]}"; do
        [[ -n "$c" && -f "$_GRUB_SRC/$c/theme.txt" ]] && { src="$_GRUB_SRC/$c"; break; }
    done
    if [[ -z "$src" ]]; then
        src="$(find "$_GRUB_SRC" -mindepth 2 -maxdepth 2 -name theme.txt -printf '%h\n' 2>/dev/null | sort | head -1)"
    fi
    if [[ -z "$src" ]]; then
        error "HyperFluent GRUB Theme: no theme.txt found in the repository."
        rm -rf "$tmp"; return 1
    fi
    info "Installing the HyperFluent GRUB theme ('$(basename "$src")' variant)..."
    _grub_install_local_theme "HyperFluent GRUB Theme" "$src" "hyperfluent"
    local rc=$?
    rm -rf "$tmp"
    return $rc
}
check_grubtheme_hyperfluent()      { [[ -d "$(_grub_themes_dir)/hyperfluent" ]]; }
uninstall_grubtheme_hyperfluent()  { _grub_uninstall_theme "HyperFluent GRUB Theme" "hyperfluent"; }
update_grubtheme_hyperfluent()     { install_grubtheme_hyperfluent; }
get_version_grubtheme_hyperfluent(){ _grub_theme_status "hyperfluent"; }

# ----------------------------------------------------------------------------
# GRUB Theme Selector
# GRUB only ever renders the single theme that GRUB_THEME= points at, with no
# native runtime picker. This action lists the themes already installed under
# the GRUB themes dir (plus the stock no-theme menu), marks the active one, and
# switches GRUB_THEME= to the chosen entry — no re-download needed. Switching
# is just _grub_set_theme/_grub_clear_theme, which also regenerate grub.cfg.
# ----------------------------------------------------------------------------
install_grubtheme_selector() {
    _grub_themes_require_grub || return 1

    echo ""
    echo "${BOLD}${CYAN}════════════════════════════════════════════════════════════════${RESET}"
    echo "${BOLD}${CYAN}  GRUB Theme Selector                                           ${RESET}"
    echo "${BOLD}${CYAN}════════════════════════════════════════════════════════════════${RESET}"
    echo ""

    local active; active="$(_grub_active_theme)"
    local -a dirs=()
    local d
    while IFS= read -r d; do
        [[ -n "$d" ]] && dirs+=("$d")
    done < <(_grub_list_installed_themes)

    if [[ -n "$active" ]]; then
        echo "  Current theme: ${BOLD}$(basename "$(dirname "$active")")${RESET}"
    else
        echo "  Current theme: ${BOLD}default GRUB menu (no theme)${RESET}"
    fi
    echo ""

    if (( ${#dirs[@]} == 0 )); then
        warn "No GRUB themes are installed under $(_grub_themes_dir)."
        info "Install one from the GRUB Themes menu first."
        # Still let the user revert to the stock menu if a stale GRUB_THEME is set.
        [[ -z "$active" ]] && return 0
    fi

    echo "  Available themes:"
    echo ""
    # Option 1 is always the stock no-theme menu; installed themes follow.
    local def_tag=""
    [[ -z "$active" ]] && def_tag=" ${GREEN}(active)${RESET}"
    echo "    1) Default GRUB menu (no theme)${def_tag}"
    local i
    for ((i = 0; i < ${#dirs[@]}; i++)); do
        local tag=""
        [[ "$active" == "${dirs[$i]}/theme.txt" ]] && tag=" ${GREEN}(active)${RESET}"
        echo "    $((i + 2))) $(basename "${dirs[$i]}")${tag}"
    done
    echo ""
    echo "    0) Cancel"
    echo ""

    local total=$(( ${#dirs[@]} + 1 ))
    local choice
    while true; do
        read -rp "  Select theme to activate [0-${total}]: " choice < /dev/tty
        [[ "$choice" == "0" ]] && { echo "${YELLOW}  Cancelled.${RESET}"; return 2; }
        if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= total )); then break; fi
        echo "${RED}  Invalid selection.${RESET}"
    done

    echo ""
    if (( choice == 1 )); then
        if [[ -z "$active" ]]; then
            info "The default GRUB menu is already active. No changes made."
            return 0
        fi
        _grub_clear_theme
        info "Reverted to the default GRUB menu. Reboot to see it."
        return 0
    fi

    local chosen="${dirs[$((choice - 2))]}"
    if [[ "$active" == "${chosen}/theme.txt" ]]; then
        info "$(basename "$chosen") is already the active theme. No changes made."
        return 0
    fi
    _grub_set_theme "${chosen}/theme.txt"
    info "$(basename "$chosen") set as the GRUB theme. Reboot to see it."
    return 0
}

# Run-action: never "installed", so it always shows as a runnable entry; the
# status column reflects the active theme via get_version below.
update_grubtheme_selector()      { install_grubtheme_selector; }
get_version_grubtheme_selector() {
    local active; active="$(_grub_active_theme)"
    if [[ -n "$active" ]]; then
        basename "$(dirname "$active")"
    else
        echo "default menu"
    fi
}

#!/bin/bash
# Linux Apps on Windows — install a desktop environment's applications, without
# the desktop itself, inside a WSL distro so they run as ordinary windows on the
# Windows desktop through WSLg (the GUI support built into WSL on Windows 11 and
# recent Windows 10 updates; no separate X server or RDP setup needed).
#
# The goal is Windows as the host and Linux as where the work happens: file
# manager, editor, terminal, image and document viewers from whichever desktop
# environment you prefer, pinned and launched like any other Windows app, with
# no session, compositor or display manager involved.
#
# Installing a whole desktop session is deliberately NOT offered here. WSLg
# displays individual windows, not a session, so a full desktop needs RDP and
# ends up as a box you look into — the opposite of apps that feel native. Each
# desktop environment already has its own entry under Desktop Environments for
# anyone who does want the whole thing.
#
# The DE list is not hardcoded: it lists whichever "Desktop Environments"
# utilities are actually registered for this distro (the same per-distro
# availability checks in installers.sh already apply), so this supports every
# distro and desktop the project supports rather than a favoured pair.
#
# The applications-only package sets live here rather than in each DE's own
# installer, deliberately: they exist only for WSL, and keeping them local means
# this feature cannot alter the behaviour of a bare-metal desktop install.

# ── Version / status ──────────────────────────────────────────────────────────
# Not a single on/off state (any number of DEs could be installed), so this
# always reports empty like the other picker-style system tasks.
get_version_wsl_apps() { :; }

# check_wsl_apps reports "installed" only when an applications-only install
# has been recorded and at least one of those packages is still present. That is
# the only thing this utility owns and the only thing its uninstall can remove,
# so it is the only thing that should make the menu offer one.
#
# A desktop session installed from the Desktop Environments category deliberately
# does NOT count here: it belongs to that desktop's own entry, which already
# reports and uninstalls it. Counting it twice would offer two uninstalls for one
# thing, one of which would not work.
check_wsl_apps() {
    local state_dir pkg f
    for state_dir in "$(_wsl_apps_state_dir)" "$(_wsl_apps_legacy_state_dir)"; do
        [[ -d "$state_dir" ]] || continue
        for f in "$state_dir"/*.pkgs; do
            [[ -f "$f" ]] || continue
            while IFS= read -r pkg; do
                [[ -z "$pkg" ]] && continue
                pkg_check_installed "$pkg" && return 0
            done < "$f"
        done
    done
    return 1
}

# _wsl_apps_candidates prints the display-environment utility names
# available on this distro, one per line, in registration order.
_wsl_apps_candidates() {
    local name
    for name in "${UTILITIES[@]}"; do
        [[ "$name" == "Linux Apps on Windows" ]] && continue
        [[ "${UTILITY_CATEGORY[$name]:-}" == "Desktop Environments" ]] && printf '%s\n' "$name"
    done
}

# ── Applications-only package sets ────────────────────────────────────────────
# _wsl_apps_app_packages <utility name> prints the applications to install
# for that DE on this distro, space separated, or nothing if the DE has no
# applications-only set (COSMIC, for instance, ships no separate app suite yet).
#
# Package names are keyed on $PKG_MGR rather than the distro family, matching
# how the DE installers themselves branch.
#
# These are applications only: nothing here pulls in a session, a compositor or
# a display manager as a *direct* dependency. Qt/GTK and the DE's own libraries
# still arrive as ordinary dependencies, which is unavoidable and expected.
_wsl_apps_app_packages() {
    local de="$1"

    case "$de" in
        "KDE Desktop")
            case "$PKG_MGR" in
                # Debian/Ubuntu name the screenshot tool kde-spectacle; everyone
                # else ships it as plain spectacle. Verified on Ubuntu 24.04:
                # 'spectacle' does not exist there.
                apt)            printf 'dolphin konsole kate ark gwenview okular kde-spectacle' ;;
                dnf|yum|pacman|zypper)
                    printf 'dolphin konsole kate ark gwenview okular spectacle' ;;
            esac
            ;;
        "GNOME Desktop")
            case "$PKG_MGR" in
                apt)            printf 'nautilus gnome-terminal file-roller eog evince gnome-text-editor' ;;
                dnf|yum)        printf 'nautilus gnome-terminal file-roller eog evince gnome-text-editor' ;;
                pacman)         printf 'nautilus gnome-terminal file-roller eog evince gnome-text-editor' ;;
                zypper)         printf 'nautilus gnome-terminal file-roller eog evince' ;;
            esac
            ;;
        "Xfce Desktop")
            case "$PKG_MGR" in
                apt|dnf|yum|pacman|zypper)
                    printf 'thunar xfce4-terminal mousepad xarchiver ristretto atril' ;;
            esac
            ;;
        "MATE Desktop")
            case "$PKG_MGR" in
                apt|dnf|yum|pacman|zypper)
                    printf 'caja mate-terminal pluma engrampa eom atril mate-calc' ;;
            esac
            ;;
        "Cinnamon Desktop")
            # Cinnamon's own X-Apps (xed, xviewer, xreader) are Linux Mint
            # packages and are not in Debian/Ubuntu/Fedora/Arch archives —
            # verified absent on Ubuntu 24.04 — so use the GNOME applications
            # Cinnamon is built on everywhere instead.
            case "$PKG_MGR" in
                apt|dnf|yum|pacman)
                    printf 'nemo gnome-terminal file-roller eog evince gnome-text-editor' ;;
                zypper)         printf 'nemo gnome-terminal file-roller eog evince' ;;
            esac
            ;;
        "LXQt Desktop")
            case "$PKG_MGR" in
                apt|dnf|yum|pacman|zypper)
                    printf 'pcmanfm-qt qterminal featherpad lxqt-archiver lximage-qt' ;;
            esac
            ;;
        "Budgie Desktop")
            # Budgie ships no application suite of its own — it uses GNOME's,
            # plus Nemo as its file manager.
            case "$PKG_MGR" in
                apt)            printf 'nemo gnome-terminal file-roller eog evince gnome-text-editor' ;;
                dnf|yum)        printf 'nemo gnome-terminal file-roller eog evince gnome-text-editor' ;;
                pacman)         printf 'nemo gnome-terminal file-roller eog evince gnome-text-editor' ;;
                zypper)         printf 'nemo gnome-terminal file-roller eog evince' ;;
            esac
            ;;
        "Deepin Desktop")
            case "$PKG_MGR" in
                apt)            printf 'dde-file-manager deepin-terminal deepin-editor deepin-image-viewer deepin-calculator' ;;
                # Fedora packages only part of the Deepin application set: its
                # file manager (dde-file-manager) and editor (deepin-editor) are
                # not in the repos — verified absent on Fedora 43 — so they are
                # left out rather than listed and skipped on every run.
                dnf|yum)        printf 'deepin-terminal deepin-image-viewer deepin-calculator' ;;
                pacman)         printf 'dde-file-manager deepin-terminal deepin-editor deepin-image-viewer deepin-calculator' ;;
                zypper)         printf 'dde-file-manager deepin-terminal deepin-editor deepin-image-viewer' ;;
            esac
            ;;
        "Pantheon Desktop")
            case "$PKG_MGR" in
                apt)            printf 'io.elementary.files io.elementary.terminal io.elementary.code' ;;
                pacman)         printf 'pantheon-files elementary-terminal elementary-code' ;;
                zypper)         printf 'pantheon-files elementary-terminal' ;;
            esac
            ;;
        "COSMIC Desktop")
            # COSMIC's applications are not separable from the session yet:
            # cosmic-files / cosmic-term / cosmic-edit are packaged only where
            # the whole desktop is. Deliberately empty — the caller reports this
            # as "no applications-only set" rather than installing nothing.
            : ;;
    esac
}

# _wsl_apps_install_apps installs an applications-only package set. Missing
# packages are not fatal: package availability varies widely across distro
# versions, and a set that is half-available is still worth having. Installing
# one at a time is slower than one transaction, but a single unavailable package
# would otherwise abort the entire set.
# Where apps-only installs record what they added, so uninstall removes exactly
# those packages and nothing else. One file per desktop environment, each line a
# package name. Per-user under $HOME/.config (the convention the other installers
# here use) rather than a system path, because the file is bookkeeping for this
# user's choices, not system state.
_wsl_apps_state_dir() { printf '%s/.config/linux_util/wsl_apps' "$HOME"; }

# _wsl_apps_legacy_state_dir — where this utility recorded installs when it was
# called "WSL Desktop". Read-only and never written to: an install made before
# the rename must still be removable by uninstall, or those packages become
# orphaned with no record of what put them there.
_wsl_apps_legacy_state_dir() { printf '%s/.config/linux_util/wsl_desktop' "$HOME"; }

# _wsl_apps_state_file <utility name> — one file per DE, name slugified.
_wsl_apps_state_file() {
    local slug="${1// /_}"
    slug="${slug//\//_}"
    printf '%s/%s.pkgs' "$(_wsl_apps_state_dir)" "${slug,,}"
}

_wsl_apps_install_apps() {
    local de="$1" pkgs="" pkg
    # added[] is what THIS run installed — the only packages uninstall may
    # remove. Packages already present beforehand go in installed[] for the
    # summary but never in added[]: they were not ours to install, so they are
    # not ours to remove.
    local -a wanted=() installed=() failed=() added=()

    pkgs=$(_wsl_apps_app_packages "$de")
    if [[ -z "$pkgs" ]]; then
        error "${de} has no applications-only package set for ${DISTRO_ID}."
        echo "  Its applications are not packaged separately from the desktop session."
        echo "  Choose Full desktop instead, or pick a different desktop environment."
        return 1
    fi

    read -ra wanted <<< "$pkgs"

    info "Installing ${de} applications (${#wanted[@]} packages, no desktop session)..."
    ensure_tools

    case "$PKG_MGR" in
        apt)    run_as_root apt-get update ;;
        zypper) run_as_root zypper refresh || true ;;
    esac

    # Packages are installed one at a time so an unavailable one is skipped
    # rather than aborting the whole set. The package manager's own output is
    # left visible, as in every other installer here — these are large
    # downloads, and a silent multi-minute wait looks like a hang.
    local n=0
    for pkg in "${wanted[@]}"; do
        (( n++ ))
        if pkg_check_installed "$pkg"; then
            installed+=("$pkg")
            info "[${n}/${#wanted[@]}] ${pkg} is already installed — skipping."
            continue
        fi
        info "[${n}/${#wanted[@]}] Installing ${pkg}..."
        case "$PKG_MGR" in
            apt)      run_as_root apt-get install -y "$pkg" ;;
            dnf|yum)  run_as_root "$PKG_MGR" install -y "$pkg" ;;
            pacman)   run_as_root pacman -S --noconfirm --needed "$pkg" ;;
            zypper)   run_as_root zypper install -y "$pkg" ;;
            *)        error "Applications-only install is not supported for ${DISTRO_ID}"
                      return 1 ;;
        esac
        if pkg_check_installed "$pkg"; then
            installed+=("$pkg")
            added+=("$pkg")
        else
            failed+=("$pkg")
            warn "[${n}/${#wanted[@]}] ${pkg} is not available on ${DISTRO_ID} — skipped."
        fi
    done

    if [[ ${#installed[@]} -eq 0 ]]; then
        error "None of the ${de} application packages could be installed."
        echo "  Tried: ${wanted[*]}"
        return 1
    fi

    # Record what this run added, so uninstall can remove exactly that. Appended,
    # not overwritten: re-running after a partial install must not lose the
    # earlier record. Failure to write is a warning, not an error — the packages
    # are installed either way, only the uninstall record is lost.
    if [[ ${#added[@]} -gt 0 ]]; then
        local _state_file
        _state_file="$(_wsl_apps_state_file "$de")"
        if mkdir -p "$(_wsl_apps_state_dir)" 2>/dev/null; then
            printf '%s\n' "${added[@]}" >> "$_state_file" 2>/dev/null \
                || warn "Could not record installed packages in ${_state_file}; uninstall will not know about them."
        else
            warn "Could not create $(_wsl_apps_state_dir); uninstall will not know what was installed."
        fi
    fi

    info "Installed ${#installed[@]} of ${#wanted[@]} packages: ${installed[*]}"
    if [[ ${#added[@]} -lt ${#installed[@]} ]]; then
        info "$(( ${#installed[@]} - ${#added[@]} )) were already present and will be left alone by uninstall."
    fi
    if [[ ${#failed[@]} -gt 0 ]]; then
        warn "Not available on ${DISTRO_ID}, skipped: ${failed[*]}"
    fi

    return 0
}

# _wsl_apps_offer_window_buttons asks whether to restore the minimize and
# maximize buttons on GTK app title bars, and delegates to the existing
# install_window_buttons task rather than setting the key here — one
# implementation, in the file that owns it.
#
# Why it belongs in this flow: with no window manager installed, GTK apps draw
# their own title bar and honour the window-manager button-layout preference,
# which defaults to close-only under WSLg. An app with no minimize or maximize
# does not feel like a Windows app, which is the whole point of installing them
# this way. Qt apps (Dolphin, Konsole) do not read that key and are unaffected.
#
# It ASKS rather than applying silently because the key is a per-user desktop
# preference the user may have set deliberately, and this would overwrite it on
# every run.
_wsl_apps_offer_window_buttons() {
    if ! declare -F install_window_buttons >/dev/null 2>&1; then
        return 0
    fi

    # Nothing to set without a session bus to write through — say so once
    # instead of prompting for a change that cannot take effect.
    if [[ -z "${DBUS_SESSION_BUS_ADDRESS:-}" && -z "${WAYLAND_DISPLAY:-}" && -z "${DISPLAY:-}" ]]; then
        return 0
    fi

    local reply=""
    {
        printf '\n  %sWindow buttons%s — with no window manager installed, GTK apps such as\n' "${BOLD:-}" "${RESET:-}"
        printf '  Nautilus, Files and Remmina may show only a close button, with no\n'
        printf '  minimize or maximize. This sets your desktop button-layout preference\n'
        printf '  to show all three, so they behave like ordinary Windows windows.\n\n'
        printf '  It changes a per-user setting in your own profile and is not undone\n'
        printf '  automatically. Qt apps such as Dolphin and Konsole are unaffected.\n\n'
        printf 'Restore minimize and maximize buttons now? [y/N]: '
    } > /dev/tty 2>/dev/null
    read -r reply < /dev/tty 2>/dev/null || reply=""

    case "$reply" in
        [yY]|[yY][eE][sS]) ;;
        *)
            info "Left your window-button setting alone."
            return 0
            ;;
    esac

    install_window_buttons || warn "Could not set the window button layout."
    return 0
}

# ── Main interactive function ─────────────────────────────────────────────────
setup_wsl_apps() {
    if ! is_wsl; then
        warn "This machine is not running under WSL — nothing to do."
        echo "  Linux Apps on Windows installs a desktop environment's applications"
        echo "  inside a WSL distro so they appear on the Windows desktop via WSLg."
        echo "  On a native Linux install, use the Desktop Environments category"
        echo "  or install the individual applications you want."
        return 0
    fi

    echo ""
    echo "${BOLD:-}${CYAN:-}════════════════════════════════════════════════════════════════${RESET:-}"
    echo "${BOLD:-}${CYAN:-}  Linux Apps on Windows                                          ${RESET:-}"
    echo "${BOLD:-}${CYAN:-}════════════════════════════════════════════════════════════════${RESET:-}"
    echo ""

    local -a candidates
    mapfile -t candidates < <(_wsl_apps_candidates)
    if [[ ${#candidates[@]} -eq 0 ]]; then
        warn "No desktop environments are available for this distro."
        return 1
    fi

    # --- Which desktop environment's applications ---
    {
        printf '  Installs the applications from a desktop environment — file manager,\n'
        printf '  editor, terminal, archiver, image and document viewers — with no\n'
        printf '  desktop session, compositor or display manager. WSLg publishes each\n'
        printf '  one to the Windows Start menu, where they launch as ordinary windows.\n\n'
        printf '  Whose applications would you like to install?\n\n'
        local i=1 name status
        for name in "${candidates[@]}"; do
            status=""
            # Flag the DEs with no separable app set rather than letting the user
            # pick one and then fail.
            [[ -z "$(_wsl_apps_app_packages "$name")" ]] && status=" (no separate applications)"
            printf '  %2d)  %s%s\n' "$i" "$name" "$status"
            (( i++ ))
        done
        printf '   0)  Cancel\n\n'
    } > /dev/tty 2>/dev/null

    local choice
    while true; do
        # The prompt is written to /dev/tty separately rather than via `read -rp`:
        # read emits its prompt on stderr, and the 2>/dev/null needed to silence a
        # missing-/dev/tty error would swallow the prompt too, leaving a bare
        # cursor that looks like a hang. Same reasoning as _prompt_de_tier().
        printf 'Select [0-%d]: ' "${#candidates[@]}" > /dev/tty 2>/dev/null
        # A failed read (no controlling terminal) must abort rather than loop:
        # leaving $choice empty would spin here forever printing "Invalid selection".
        if ! read -r choice < /dev/tty 2>/dev/null; then
            error "No terminal available to read a selection — cancelling."
            return 1
        fi
        [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 0 && choice <= ${#candidates[@]} )) && break
        printf '%sInvalid selection.%s\n' "${RED:-}" "${RESET:-}" > /dev/tty 2>/dev/null
    done
    [[ "$choice" == "0" ]] && { info "Cancelled."; return 2; }

    local de_name="${candidates[$((choice - 1))]}"

    _wsl_apps_install_apps "$de_name" || return $?

    echo ""
    info "${de_name} applications installed."
    echo "  They should appear in the Windows Start menu under"
    echo "  ${BOLD:-}${WSL_DISTRO_NAME:-your distro}${RESET:-}, and can also be launched from this shell by name."
    echo "  No desktop session or display manager was installed."

    _wsl_apps_offer_window_buttons

    if [[ -z "${WAYLAND_DISPLAY:-}" && -z "${DISPLAY:-}" ]]; then
        echo ""
        warn "No WSLg display was detected in this session (\$WAYLAND_DISPLAY / \$DISPLAY are unset)."
        echo "  WSLg ships with WSL on Windows 11 and recent Windows 10 builds. If it is"
        echo "  missing, run 'wsl --update' from an elevated Windows prompt."
        echo "  ${RED:-}${BOLD:-}Then run 'wsl --shutdown' from Windows and reopen the distro.${RESET:-}"
    else
        echo ""
        echo "  If a newly installed app does not show in the Start menu yet, run"
        echo "  ${BOLD:-}wsl --shutdown${RESET:-} from Windows and reopen the distro."
    fi
    return 0
}


# ── Uninstall ─────────────────────────────────────────────────────────────────
# Removes the applications this utility installed, and nothing else. It works
# only from the record written at install time, so it can never remove a package
# that was already on the system or one belonging to a desktop session — a
# desktop is uninstalled through its own entry in Desktop Environments, which is
# where that uninstall logic lives.
uninstall_wsl_apps() {
    local state_dir
    # Both the current record location and the one used before this utility was
    # renamed, so an install made under the old name is still removable.
    local -a state_dirs=("$(_wsl_apps_state_dir)" "$(_wsl_apps_legacy_state_dir)")

    local -a state_files=()
    for state_dir in "${state_dirs[@]}"; do
        [[ -d "$state_dir" ]] || continue
        mapfile -t -O "${#state_files[@]}" state_files < <(find "$state_dir" -maxdepth 1 -name '*.pkgs' -type f 2>/dev/null | sort)
    done

    if [[ ${#state_files[@]} -eq 0 ]]; then
        info "No application installs were recorded, so there is nothing to remove."
        echo "  This utility installs nothing under its own name — it is a picker."
        echo "  A desktop session is removed from the Desktop Environments menu,"
        echo "  under that desktop's own entry."
        return 0
    fi

    # Build the removal list: recorded packages that are still installed.
    local f pkg de_label
    local -a to_remove=() labels=()
    for f in "${state_files[@]}"; do
        de_label="$(basename "$f" .pkgs)"
        labels+=("$de_label")
        while IFS= read -r pkg; do
            [[ -z "$pkg" ]] && continue
            pkg_check_installed "$pkg" || continue
            # Guard against a package being recorded twice across re-runs.
            local seen=false existing
            for existing in "${to_remove[@]}"; do
                [[ "$existing" == "$pkg" ]] && { seen=true; break; }
            done
            [[ "$seen" == false ]] && to_remove+=("$pkg")
        done < "$f"
    done

    if [[ ${#to_remove[@]} -eq 0 ]]; then
        info "The recorded applications are already gone; clearing the record."
        rm -f "${state_files[@]}" 2>/dev/null
        # Both dirs, since a record may exist under the pre-rename path. rmdir
        # only succeeds on an empty dir, so this cannot remove anything else.
        rmdir "${state_dirs[@]}" 2>/dev/null || true
        return 0
    fi

    echo ""
    echo "  The following applications were installed by Linux Apps on Windows"
    echo "  (${labels[*]}) and will be removed:"
    echo ""
    printf '    %s\n' "${to_remove[@]}"
    echo ""
    echo "  Packages that were already present before that install are not listed"
    echo "  and will not be touched."
    echo ""

    local reply=""
    printf 'Remove these %d package(s)? [y/N]: ' "${#to_remove[@]}" > /dev/tty 2>/dev/null
    read -r reply < /dev/tty 2>/dev/null || reply=""
    case "$reply" in
        [yY]|[yY][eE][sS]) ;;
        *) info "Cancelled — nothing was removed."; return 2 ;;
    esac

    info "Removing ${#to_remove[@]} package(s)..."
    local rc=0
    case "$PKG_MGR" in
        apt)      run_as_root apt-get purge --autoremove -y "${to_remove[@]}" || rc=1 ;;
        dnf|yum)  run_as_root "$PKG_MGR" remove -y "${to_remove[@]}" || rc=1 ;;
        pacman)   run_as_root pacman -Rs --noconfirm "${to_remove[@]}" || rc=1 ;;
        zypper)   run_as_root zypper remove -y --clean-deps "${to_remove[@]}" || rc=1 ;;
        *)        error "Uninstall is not supported for ${DISTRO_ID}"; return 1 ;;
    esac

    if (( rc != 0 )); then
        error "Package removal reported an error; the install record has been kept."
        echo "  Re-run this uninstall once the package manager problem is resolved."
        return 1
    fi

    rm -f "${state_files[@]}" 2>/dev/null
    rmdir "${state_dirs[@]}" 2>/dev/null || true

    info "Removed. No desktop session or display manager was involved."
    return 0
}

# ── Lifecycle ─────────────────────────────────────────────────────────────────
# Update re-runs the picker: there is no single installed thing to upgrade, and
# the package manager updates the applications themselves along with everything
# else. Re-running lets the user add another desktop's applications.
update_wsl_apps()    { setup_wsl_apps; }

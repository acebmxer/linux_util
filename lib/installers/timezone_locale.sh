#!/bin/bash
# Local Time Zone / Locale system task
# Lets the user set time zone, locale, or both in one guided flow.

get_version_timezone_locale() {
    local tz="" lang=""

    if _have_cmd timedatectl; then
        tz=$(timedatectl show --property=Timezone --value 2>/dev/null || true)
    elif [[ -f /etc/timezone ]]; then
        tz=$(< /etc/timezone)
    fi

    lang=$(locale 2>/dev/null | awk -F= '/^LANG=/{print $2; exit}')
    if [[ -z "$lang" ]] && _have_cmd localectl; then
        lang=$(localectl status 2>/dev/null | awk -F= '/^[[:space:]]*LANG=/{print $2; exit}')
    fi

    [[ -z "$tz" && -z "$lang" ]] && return 0

    if [[ -n "$tz" && -n "$lang" ]]; then
        echo "TZ: ${tz}, LANG: ${lang}"
    elif [[ -n "$tz" ]]; then
        echo "TZ: ${tz}"
    else
        echo "LANG: ${lang}"
    fi
}

_timezone_list_all() {
    if command -v timedatectl &>/dev/null; then
        timedatectl list-timezones 2>/dev/null
    fi
}

_pick_from_matches() {
    local prompt="$1"
    shift
    local -a matches=("$@")

    if (( ${#matches[@]} == 0 )); then
        return 1
    fi

    local i
    for (( i=0; i<${#matches[@]}; i++ )); do
        printf "  %2d) %s\n" "$((i + 1))" "${matches[$i]}" > /dev/tty
    done
    echo "   0) Cancel" > /dev/tty

    local choice
    while true; do
        read -rp "${prompt} [0-${#matches[@]}]: " choice < /dev/tty
        if [[ "$choice" == "0" ]]; then
            return 2
        fi
        if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#matches[@]} )); then
            echo "${matches[$((choice - 1))]}"
            return 0
        fi
        echo "${RED}Invalid selection. Please try again.${RESET}" > /dev/tty
    done
}

_select_timezone() {
    local current_tz=""
    if command -v timedatectl &>/dev/null; then
        current_tz=$(timedatectl show --property=Timezone --value 2>/dev/null || true)
    elif [[ -f /etc/timezone ]]; then
        current_tz=$(< /etc/timezone)
    fi

    info "Current time zone: ${current_tz:-unknown}"

    local -a all_tz
    mapfile -t all_tz < <(_timezone_list_all)
    if (( ${#all_tz[@]} == 0 )); then
        warn "Unable to list time zones (timedatectl not available)."
        return 1
    fi

    echo ""
    read -rp "Enter a timezone search term (e.g. New_York, London, Tokyo): " tz_term < /dev/tty
    if [[ -z "$tz_term" ]]; then
        warn "No search term entered. Time zone selection cancelled."
        return 2
    fi

    local -a matches=()
    local tz
    for tz in "${all_tz[@]}"; do
        if [[ "${tz,,}" == *"${tz_term,,}"* ]]; then
            matches+=("$tz")
            (( ${#matches[@]} >= 20 )) && break
        fi
    done

    if (( ${#matches[@]} == 0 )); then
        warn "No matching time zones found for '${tz_term}'."
        return 1
    fi

    local selected_tz
    if (( ${#matches[@]} == 1 )); then
        selected_tz="${matches[0]}"
        info "Auto-selected time zone: ${selected_tz}"
    elif [[ "${tz_term,,}" == "${current_tz,,}" ]]; then
        selected_tz="$current_tz"
        info "Using current time zone: ${selected_tz}"
    else
        echo ""
        echo "Select time zone:"
        selected_tz=$(_pick_from_matches "Choose time zone" "${matches[@]}")
        local pick_rc=$?
        if (( pick_rc == 2 )); then
            return 2
        elif (( pick_rc != 0 )); then
            return 1
        fi
    fi

    if [[ "$selected_tz" == "$current_tz" ]]; then
        info "Time zone already set to ${selected_tz}."
        return 3
    fi

    if ! command -v timedatectl &>/dev/null; then
        warn "timedatectl is not available on this system."
        return 1
    fi

    run_as_root timedatectl set-timezone "$selected_tz" || {
        warn "Failed to set time zone to ${selected_tz}."
        return 1
    }

    info "Time zone set to ${selected_tz}."
    return 0
}

# Debian's locale-gen ignores any locale name given as an argument: it only
# generates the entries that are uncommented in /etc/locale.gen (Ubuntu ships a
# variant that does honour arguments). Enable the entry first, then run it.
_locale_gen_entry() {
    local entry="$1"                    # e.g. "en_US.UTF-8 UTF-8"
    local gen_file="${2:-/etc/locale.gen}"

    if [[ "$entry" != *[[:space:]]* ]]; then
        warn "Malformed locale entry '${entry}' (missing charset)."
        return 1
    fi

    local name="${entry%%[[:space:]]*}"
    local name_re="${name//./\\.}"

    if [[ ! -f "$gen_file" ]]; then
        warn "${gen_file} not found; cannot generate locales on this system."
        return 1
    fi

    if grep -qE "^[[:space:]]*${name_re}[[:space:]]" "$gen_file"; then
        :   # already enabled
    elif grep -qE "^[[:space:]]*#[[:space:]]*${name_re}[[:space:]]" "$gen_file"; then
        run_as_root sed -i -E "s|^[[:space:]]*#[[:space:]]*(${name_re}[[:space:]])|\\1|" "$gen_file" || {
            warn "Failed to uncomment ${name} in ${gen_file}."
            return 1
        }
    else
        printf '%s\n' "$entry" | run_as_root tee -a "$gen_file" > /dev/null || {
            warn "Failed to add ${name} to ${gen_file}."
            return 1
        }
    fi

    local gen_bin
    gen_bin=$(_sbin_command locale-gen) || {
        warn "locale-gen not found."
        return 1
    }
    run_as_root "$gen_bin"
}

# Writes LANG=/LC_TIME= assignments with whichever tool the distro supports.
#
# update-locale is tried first on purpose. Debian ships a D-Bus policy
# (/usr/share/dbus-1/system.d/systemd-localed-read-only.conf) that denies
# locale1.SetLocale to everyone, root included — "locales are not set via
# localed" there — so localectl always fails with "Access denied". update-locale,
# from the same 'locales' package as locale-gen, writes /etc/locale.conf directly
# (/etc/default/locale is a symlink to it) and exists only on Debian/Ubuntu;
# everywhere else localectl is the right tool.
_apply_locale_setting() {
    local update_bin localectl_bin
    update_bin=$(_sbin_command update-locale) || update_bin=""
    localectl_bin=$(_sbin_command localectl) || localectl_bin=""

    if [[ -z "$update_bin" && -z "$localectl_bin" ]]; then
        warn "No supported locale configuration tool found (localectl/update-locale)."
        return 1
    fi

    if [[ -n "$update_bin" ]]; then
        run_as_root "$update_bin" "$@" && return 0
        warn "update-locale could not set the locale."
    fi

    if [[ -n "$localectl_bin" ]]; then
        run_as_root "$localectl_bin" set-locale "$@" && return 0
        warn "localectl could not set the locale."
    fi

    return 1
}

_select_locale() {
    local current_lang
    current_lang=$(locale 2>/dev/null | awk -F= '/^LANG=/{print $2; exit}')
    local current_lc_time
    current_lc_time=$(locale LC_TIME 2>/dev/null | awk -F= '/^LC_TIME=/{gsub(/"/,"",$2); print $2; exit}')
    [[ -z "$current_lc_time" ]] && current_lc_time="$current_lang"
    info "Current locale: ${current_lang:-unknown}"

    local -a available_locales
    mapfile -t available_locales < <(locale -a 2>/dev/null)
    if (( ${#available_locales[@]} == 0 )); then
        warn "Unable to list available locales."
        return 1
    fi

    echo ""
    read -rp "Enter a locale search term (e.g. en_US, en_GB, de_DE): " loc_term < /dev/tty
    if [[ -z "$loc_term" ]]; then
        warn "No search term entered. Locale selection cancelled."
        return 2
    fi

    local -a matches=()
    local loc
    for loc in "${available_locales[@]}"; do
        if [[ "${loc,,}" == *"${loc_term,,}"* ]]; then
            matches+=("$loc")
            (( ${#matches[@]} >= 20 )) && break
        fi
    done

    if (( ${#matches[@]} == 0 )); then
        # On minimal systems (cloud VMs, containers), locales may not be generated
        # or the locales package may not be installed at all.
        if ! _have_sbin_cmd locale-gen; then
            if command -v apt-get &>/dev/null; then
                warn "The 'locales' package is not installed. It is required to generate locales."
                local confirm
                while true; do
                    read -rp "Install 'locales' package now? [y/N]: " confirm < /dev/tty
                    case "${confirm,,}" in
                        y|yes) break ;;
                        n|no|'') warn "Locale selection cancelled."; return 1 ;;
                        *) echo "  Please enter Y or N." ;;
                    esac
                done
                run_as_root apt-get install -y locales || {
                    warn "Failed to install 'locales' package."
                    return 1
                }
            else
                warn "No matching locales found for '${loc_term}' and locale-gen is unavailable."
                return 1
            fi
        fi

        # SUPPORTED lines are "<locale> <charset>"; /etc/locale.gen needs both fields.
        local gen_entry gen_candidate
        gen_entry=$(grep -i "^${loc_term}" /usr/share/i18n/SUPPORTED 2>/dev/null | head -1)
        gen_candidate="${gen_entry%%[[:space:]]*}"
        if [[ -n "$gen_candidate" ]]; then
            warn "Locale '${loc_term}' is not generated yet. Nearest supported: ${gen_candidate}"
            local confirm
            while true; do
                read -rp "Generate ${gen_candidate} now? [y/N]: " confirm < /dev/tty
                case "${confirm,,}" in
                    y|yes)
                        _locale_gen_entry "$gen_entry" || {
                            warn "locale-gen failed for ${gen_candidate}."
                            return 1
                        }
                        mapfile -t available_locales < <(locale -a 2>/dev/null)
                        mapfile -t matches < <(printf '%s\n' "${available_locales[@]}" | grep -i "${loc_term}" | head -20)
                        if (( ${#matches[@]} == 0 )); then
                            warn "${gen_candidate} is still unavailable after running locale-gen."
                            return 1
                        fi
                        break
                        ;;
                    n|no|'') break ;;
                    *) echo "  Please enter Y or N." ;;
                esac
            done
        fi

        if (( ${#matches[@]} == 0 )); then
            warn "No matching locales found for '${loc_term}'."
            return 1
        fi
    fi

    local selected_locale
    if (( ${#matches[@]} == 1 )); then
        selected_locale="${matches[0]}"
        info "Auto-selected locale: ${selected_locale}"
    elif [[ "${loc_term,,}" == "${current_lang,,}" ]]; then
        selected_locale="$current_lang"
        info "Using current locale: ${selected_locale}"
    else
        echo ""
        echo "Select locale:"
        selected_locale=$(_pick_from_matches "Choose locale" "${matches[@]}")
        local pick_rc=$?
        if (( pick_rc == 2 )); then
            return 2
        elif (( pick_rc != 0 )); then
            return 1
        fi
    fi

    # locale -a emits "en_US.utf8"; LANG/localectl expect "en_US.UTF-8".
    # Normalize by uppercasing the encoding part and inserting the hyphen.
    _normalize_locale() {
        local raw="$1"
        local base enc
        if [[ "$raw" == *"."* ]]; then
            base="${raw%%.*}"
            enc="${raw##*.}"
            enc="${enc^^}"              # UTF8 → UTF8
            enc="${enc/UTF8/UTF-8}"     # UTF8 → UTF-8
            echo "${base}.${enc}"
        else
            echo "$raw"
        fi
    }

    local canonical_locale current_lang_norm selected_norm
    canonical_locale=$(_normalize_locale "$selected_locale")
    current_lang_norm=$(_normalize_locale "$current_lang")

    if [[ "${canonical_locale,,}" == "${current_lang_norm,,}" ]]; then
        info "Locale already set to ${current_lang}."
        return 3
    fi

    local -a locale_args=("LANG=${canonical_locale}")
    locale_args+=("LC_TIME=$(_normalize_locale "${current_lc_time}")")

    _apply_locale_setting "${locale_args[@]}" || {
        warn "Failed to set locale to ${selected_locale}."
        return 1
    }

    info "Locale set to ${selected_locale} (LC_TIME preserved as ${current_lc_time})."
    return 0
}

setup_timezone_locale() {
    info "Configuring local time zone and/or locale..."

    echo ""
    echo "${BOLD}${CYAN}════════════════════════════════════════════════════════════════${RESET}"
    echo "${BOLD}${CYAN}  Local Time Zone / Locale                                      ${RESET}"
    echo "${BOLD}${CYAN}════════════════════════════════════════════════════════════════${RESET}"
    echo ""
    echo "  1) Set time zone"
    echo "  2) Set locale"
    echo "  3) Set both"
    echo "  0) Cancel"
    echo ""

    local mode
    while true; do
        read -rp "Choose an option [0-3]: " mode < /dev/tty
        case "$mode" in
            1|2|3|0) break ;;
            *) echo "${RED}Invalid selection. Please try again.${RESET}" ;;
        esac
    done

    if [[ "$mode" == "0" ]]; then
        info "Time zone / locale configuration cancelled."
        return 2
    fi

    local changed=0
    local rc=0

    if [[ "$mode" == "1" || "$mode" == "3" ]]; then
        _select_timezone
        rc=$?
        if (( rc == 0 )); then
            changed=1
        elif (( rc == 2 )); then
            info "Time zone selection cancelled."
        elif (( rc != 3 )); then
            return 1
        fi
    fi

    if [[ "$mode" == "2" || "$mode" == "3" ]]; then
        _select_locale
        rc=$?
        if (( rc == 0 )); then
            changed=1
        elif (( rc == 2 )); then
            info "Locale selection cancelled."
        elif (( rc != 3 )); then
            return 1
        fi
    fi

    if (( changed == 0 )); then
        info "No time zone/locale changes were made."
        return 3
    fi

    info "Time zone/locale configuration complete."
    return 0
}

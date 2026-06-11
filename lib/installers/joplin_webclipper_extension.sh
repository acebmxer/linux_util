#!/bin/bash
# Joplin Web Clipper Browser Extension installer functions
#
# Installs the Joplin Web Clipper extension via browser policy files so it is
# force-installed on first launch for every detected browser.
#
# Supported browsers:
#   Chromium-family : Brave, Brave Origin, Chrome, Chromium, Thorium, Vivaldi  (ExtensionInstallForcelist policy)
#                     (Brave Origin reads the same /etc/brave policy dir as Brave)
#   Firefox-family  : Firefox (package/snap), LibreWolf          (ExtensionSettings policy)
#
# Note: The Joplin desktop application must be running with the Web Clipper
#       service enabled for this extension to function.

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

# Joplin Web Clipper Chrome Web Store extension ID
readonly _JWC_EXT_ID="alofnhikmmkdbbbgpnglcpdollgjjfek"
readonly _JWC_EXT_UPDATE_URL="https://clients2.google.com/service/update2/crx"

# Joplin Web Clipper Firefox extension GUID and AMO download URL
readonly _JWC_FF_GUID="{8419486a-54e9-11e8-9401-ac9e17909436}"
readonly _JWC_FF_URL="https://addons.mozilla.org/firefox/downloads/latest/joplin-web-clipper/latest.xpi"

# Policy directories for each Chromium-family browser
declare -A _JWC_CHROMIUM_POLICY_DIRS=(
    ["brave"]="/etc/brave/policies/managed"
    ["google-chrome"]="/etc/opt/chrome/policies/managed"
    ["chromium"]="/etc/chromium/policies/managed"
    ["thorium"]="/etc/thorium/policies/managed"
    ["vivaldi"]="/etc/vivaldi/policies/managed"
)

# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

# _jwc_ext_policy_file BROWSER
#   Prints the path to this browser's shared Chromium extension policy JSON file.
_jwc_ext_policy_file() {
    echo "${_JWC_CHROMIUM_POLICY_DIRS[$1]}/linux_util_chromium_extensions.json"
}

# _jwc_ext_write_chromium_forcelist POLICY_FILE ENTRY...
#   Writes ExtensionInstallForcelist policy JSON with the provided entries.
_jwc_ext_write_chromium_forcelist() {
    local policy_file="$1"
    shift
    local entries=("$@")

    {
        echo "{"
        echo "    \"ExtensionInstallForcelist\": ["
        local i
        for i in "${!entries[@]}"; do
            local suffix=","
            (( i == ${#entries[@]} - 1 )) && suffix=""
            printf '        "%s"%s\n' "${entries[$i]}" "$suffix"
        done
        echo "    ]"
        echo "}"
    } | sudo tee "$policy_file" > /dev/null
}

# _jwc_ext_apply_chromium_entry POLICY_FILE ENTRY
#   Adds this extension entry to the shared Chromium force-install list.
_jwc_ext_apply_chromium_entry() {
    local policy_file="$1"
    local entry="$2"
    local entries=()
    local seen=0
    local line

    if [[ -f "$policy_file" ]]; then
        while IFS= read -r line; do
            line="${line#\"}"
            line="${line%\"}"
            [[ -n "$line" ]] && entries+=("$line")
        done < <(sudo grep -oE '"[a-z0-9]{32};https://clients2\.google\.com/service/update2/crx"' "$policy_file" 2>/dev/null)
    fi

    for line in "${entries[@]}"; do
        if [[ "$line" == "$entry" ]]; then
            seen=1
            break
        fi
    done
    (( seen == 0 )) && entries+=("$entry")

    _jwc_ext_write_chromium_forcelist "$policy_file" "${entries[@]}"
}

# _jwc_ext_remove_chromium_entry POLICY_FILE ENTRY
#   Removes this extension entry from the shared Chromium force-install list.
_jwc_ext_remove_chromium_entry() {
    local policy_file="$1"
    local entry="$2"
    local kept=()
    local line

    [[ -f "$policy_file" ]] || return 0

    while IFS= read -r line; do
        line="${line#\"}"
        line="${line%\"}"
        [[ -n "$line" && "$line" != "$entry" ]] && kept+=("$line")
    done < <(sudo grep -oE '"[a-z0-9]{32};https://clients2\.google\.com/service/update2/crx"' "$policy_file" 2>/dev/null)

    if (( ${#kept[@]} == 0 )); then
        sudo rm -f "$policy_file"
    else
        _jwc_ext_write_chromium_forcelist "$policy_file" "${kept[@]}"
    fi
}

# _jwc_ext_detected_chromium_browsers
#   Prints one browser key per line for each Chromium-family browser found.
_jwc_ext_detected_chromium_browsers() {
    local browser
    for browser in "${!_JWC_CHROMIUM_POLICY_DIRS[@]}"; do
        if [[ "$browser" == "brave" ]]; then
            (command -v brave &>/dev/null || command -v brave-browser &>/dev/null || command -v brave-origin &>/dev/null) && echo "$browser"
        elif [[ "$browser" == "thorium" ]]; then
            command -v thorium-browser &>/dev/null && echo "$browser"
        else
            command -v "$browser" &>/dev/null && echo "$browser"
        fi
    done
}

# _jwc_ext_firefox_policy_path
#   Prints the Firefox policy file path to use, or empty if Firefox not found.
_jwc_ext_firefox_policy_path() {
    if command -v firefox &>/dev/null || pkg_check_installed firefox &>/dev/null; then
        echo "/etc/firefox/policies/policies.json"
        return
    fi
    if has_snap && snap list firefox &>/dev/null 2>&1; then
        echo "/etc/firefox/policies/policies.json"
        return
    fi
}

# _jwc_ext_librewolf_policy_path
#   Prints the LibreWolf policy file path, or empty if LibreWolf not found.
#   Note: Flatpak LibreWolf cannot be managed via system-level policies.
_jwc_ext_librewolf_policy_path() {
    command -v librewolf &>/dev/null && echo "/etc/librewolf/policies/policies.json"
}

# _jwc_ext_extract_firefox_entries POLICY_FILE
#   Prints existing Firefox ExtensionSettings entries as GUID|URL.
_jwc_ext_extract_firefox_entries() {
    local policy_file="$1"
    [[ -f "$policy_file" ]] || return 0

    sudo awk '
        BEGIN { in_settings=0; depth=0; guid="" }
        /"ExtensionSettings"[[:space:]]*:[[:space:]]*\{/ {
            in_settings=1
            depth=1
            next
        }
        in_settings {
            if (match($0, /^[[:space:]]*"([^"]+)"[[:space:]]*:[[:space:]]*\{/, m)) {
                guid=m[1]
            }
            if (guid != "" && match($0, /"install_url"[[:space:]]*:[[:space:]]*"([^"]+)"/, u)) {
                print guid "|" u[1]
                guid=""
            }
            open_count = gsub(/\{/, "{", $0)
            close_count = gsub(/\}/, "}", $0)
            depth += open_count - close_count
            if (depth <= 0) {
                in_settings=0
            }
        }
    ' "$policy_file" 2>/dev/null
}

# _jwc_ext_write_firefox_entries POLICY_FILE ENTRY...
#   Writes Firefox ExtensionSettings policy JSON with the provided entries.
_jwc_ext_write_firefox_entries() {
    local policy_file="$1"
    shift
    local entries=("$@")

    {
        echo "{"
        echo "    \"policies\": {"
        echo "        \"ExtensionSettings\": {"
        local i
        for i in "${!entries[@]}"; do
            local guid="${entries[$i]%%|*}"
            local url="${entries[$i]#*|}"
            local suffix=","
            (( i == ${#entries[@]} - 1 )) && suffix=""
            echo "            \"${guid}\": {"
            echo "                \"installation_mode\": \"force_installed\"," 
            echo "                \"install_url\": \"${url}\""
            echo "            }${suffix}"
        done
        echo "        }"
        echo "    }"
        echo "}"
    } | sudo tee "$policy_file" > /dev/null
}

# _jwc_ext_apply_firefox_entry POLICY_FILE GUID URL
#   Adds or updates this extension in Firefox ExtensionSettings.
_jwc_ext_apply_firefox_entry() {
    local policy_file="$1"
    local guid="$2"
    local url="$3"
    local line
    local -A settings=()

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        settings["${line%%|*}"]="${line#*|}"
    done < <(_jwc_ext_extract_firefox_entries "$policy_file")

    settings["$guid"]="$url"

    local entries=()
    local k
    for k in "${!settings[@]}"; do
        entries+=("$k|${settings[$k]}")
    done

    _jwc_ext_write_firefox_entries "$policy_file" "${entries[@]}"
}

# _jwc_ext_remove_firefox_entry POLICY_FILE GUID
#   Removes this extension from Firefox ExtensionSettings.
_jwc_ext_remove_firefox_entry() {
    local policy_file="$1"
    local guid="$2"
    local line
    local -A settings=()

    [[ -f "$policy_file" ]] || return 0

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        settings["${line%%|*}"]="${line#*|}"
    done < <(_jwc_ext_extract_firefox_entries "$policy_file")

    unset 'settings[$guid]'

    if (( ${#settings[@]} == 0 )); then
        sudo rm -f "$policy_file"
        return 0
    fi

    local entries=()
    local k
    for k in "${!settings[@]}"; do
        entries+=("$k|${settings[$k]}")
    done

    _jwc_ext_write_firefox_entries "$policy_file" "${entries[@]}"
}

# _jwc_ext_apply_chromium BROWSER
#   Creates the force-install policy JSON for a Chromium-family browser.
_jwc_ext_apply_chromium() {
    local browser="$1"
    local policy_dir="${_JWC_CHROMIUM_POLICY_DIRS[$browser]}"
    local policy_file
    policy_file="$(_jwc_ext_policy_file "$browser")"
    local legacy_policy_file="${policy_dir}/joplin_webclipper_extension.json"
    local entry="${_JWC_EXT_ID};${_JWC_EXT_UPDATE_URL}"

    sudo mkdir -p "$policy_dir"
    # Cleanup legacy per-extension file to avoid policy key conflicts.
    sudo rm -f "$legacy_policy_file"
    _jwc_ext_apply_chromium_entry "$policy_file" "$entry"
    echo "  → Ensured Joplin Web Clipper extension policy for ${browser}: ${policy_file}"
}

# _jwc_ext_apply_firefox POLICY_FILE
#   Creates the ExtensionSettings policy JSON for Firefox.
_jwc_ext_apply_firefox() {
    local policy_file="$1"
    local policy_dir
    policy_dir="$(dirname "$policy_file")"

    sudo mkdir -p "$policy_dir"
    _jwc_ext_apply_firefox_entry "$policy_file" "${_JWC_FF_GUID}" "${_JWC_FF_URL}"
    echo "  → Ensured Joplin Web Clipper extension policy for Firefox: ${policy_file}"
}

# _jwc_ext_apply_librewolf POLICY_FILE
#   Creates the ExtensionSettings policy JSON for LibreWolf.
_jwc_ext_apply_librewolf() {
    local policy_file="$1"
    local policy_dir
    policy_dir="$(dirname "$policy_file")"

    sudo mkdir -p "$policy_dir"
    _jwc_ext_apply_firefox_entry "$policy_file" "${_JWC_FF_GUID}" "${_JWC_FF_URL}"
    echo "  → Ensured Joplin Web Clipper extension policy for LibreWolf: ${policy_file}"
}

# ---------------------------------------------------------------------------
# Public functions required by the registry
# ---------------------------------------------------------------------------

check_joplin_webclipper_extension() {
    # Check policy files (installed by this tool)
    local browser
    for browser in "${!_JWC_CHROMIUM_POLICY_DIRS[@]}"; do
        local pf
        pf="$(_jwc_ext_policy_file "$browser")"
        [[ -f "$pf" ]] && sudo grep -q "${_JWC_EXT_ID};${_JWC_EXT_UPDATE_URL}" "$pf" 2>/dev/null && return 0
    done
    local ff_path
    ff_path="$(_jwc_ext_firefox_policy_path)"
    [[ -n "$ff_path" && -f "$ff_path" ]] && sudo grep -q "\"${_JWC_FF_GUID}\"" "$ff_path" 2>/dev/null && return 0
    local lw_path
    lw_path="$(_jwc_ext_librewolf_policy_path)"
    [[ -n "$lw_path" && -f "$lw_path" ]] && sudo grep -q "\"${_JWC_FF_GUID}\"" "$lw_path" 2>/dev/null && return 0
    # Check if the extension is already present in any browser profile directory
    local root
    for root in \
        "$HOME/.config/BraveSoftware/Brave-Browser" \
        "$HOME/.config/BraveSoftware/Brave-Origin" \
        "$HOME/.config/google-chrome" \
        "$HOME/.config/chromium" \
        "$HOME/.config/thorium" \
        "$HOME/.config/vivaldi"; do
        [[ -d "$root" ]] || continue
        find "$root" -maxdepth 3 -type d \
            -path "*/Extensions/${_JWC_EXT_ID}" 2>/dev/null | grep -q . && return 0
    done
    return 1
}

install_joplin_webclipper_extension() {
    echo "Installing Joplin Web Clipper Browser Extension (policy files)..."

    local installed_count=0

    # --- Chromium-family browsers ---
    local browser
    for browser in $(_jwc_ext_detected_chromium_browsers); do
        _jwc_ext_apply_chromium "$browser"
        (( installed_count++ ))
    done

    # --- Firefox ---
    local ff_path
    ff_path="$(_jwc_ext_firefox_policy_path)"
    if [[ -n "$ff_path" ]]; then
        _jwc_ext_apply_firefox "$ff_path"
        (( installed_count++ ))
    fi

    # --- LibreWolf ---
    local lw_path
    lw_path="$(_jwc_ext_librewolf_policy_path)"
    if [[ -n "$lw_path" ]]; then
        _jwc_ext_apply_librewolf "$lw_path"
        (( installed_count++ ))
    fi

    if (( installed_count == 0 )); then
        echo "Warning: No supported browsers detected. No policy files written."
        echo "         Install a browser first, then re-run this installer."
        return 1
    fi

    echo ""
    echo "Done. The Joplin Web Clipper extension will be auto-installed on next browser launch."
    echo "Note: The Joplin desktop app must be running with Web Clipper service enabled."
}

uninstall_joplin_webclipper_extension() {
    echo "Removing Joplin Web Clipper Browser Extension policy files..."

    local browser
    for browser in "${!_JWC_CHROMIUM_POLICY_DIRS[@]}"; do
        local pf
        pf="$(_jwc_ext_policy_file "$browser")"
        local legacy_pf="${_JWC_CHROMIUM_POLICY_DIRS[$browser]}/joplin_webclipper_extension.json"
        if [[ -f "$pf" ]]; then
            _jwc_ext_remove_chromium_entry "$pf" "${_JWC_EXT_ID};${_JWC_EXT_UPDATE_URL}"
            echo "  → Removed Joplin Web Clipper entry from: ${pf}"
            local pd="${_JWC_CHROMIUM_POLICY_DIRS[$browser]}"
            sudo rmdir --ignore-fail-on-non-empty "$pd" 2>/dev/null || true
        fi
        sudo rm -f "$legacy_pf"
    done

    local ff_path
    ff_path="$(_jwc_ext_firefox_policy_path)"
    if [[ -n "$ff_path" && -f "$ff_path" ]]; then
        _jwc_ext_remove_firefox_entry "$ff_path" "${_JWC_FF_GUID}"
        echo "  → Removed Joplin Web Clipper Firefox entry from: ${ff_path}"
        sudo rmdir --ignore-fail-on-non-empty "$(dirname "$ff_path")" 2>/dev/null || true
    fi

    local lw_path
    lw_path="$(_jwc_ext_librewolf_policy_path)"
    if [[ -n "$lw_path" && -f "$lw_path" ]]; then
        _jwc_ext_remove_firefox_entry "$lw_path" "${_JWC_FF_GUID}"
        echo "  → Removed Joplin Web Clipper LibreWolf entry from: ${lw_path}"
        sudo rmdir --ignore-fail-on-non-empty "$(dirname "$lw_path")" 2>/dev/null || true
    fi

    echo "Joplin Web Clipper extension policy files removed."
    echo "Note: Already-installed extensions will remain until manually removed in the browser."
}

update_joplin_webclipper_extension() {
    if check_joplin_webclipper_extension; then
        echo "Re-applying Joplin Web Clipper extension policies (extensions self-update via browser)..."
    else
        echo "Joplin Web Clipper extension policies not found — installing now."
    fi
    install_joplin_webclipper_extension
}

get_version_joplin_webclipper_extension() {
    echo ""
}

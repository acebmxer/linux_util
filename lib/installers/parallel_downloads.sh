#!/bin/bash
# Parallel Downloads — raises how many packages dnf / pacman fetch at once.
#
# dnf (Fedora, RHEL family) defaults max_parallel_downloads to 3; pacman
# (Arch family) ships ParallelDownloads = 5 in /etc/pacman.conf, and downloads
# one at a time when the key is absent. Both are set to 10 here. apt and zypper
# have no equivalent setting, so the task is only registered for dnf and pacman
# (lib/installers.sh).

readonly _PARDL_VALUE=10

# Config file, section, key and key/value separator for the active package
# manager. Prints nothing (and returns 1) for package managers without one.
_pardl_conf() {
    case "$PKG_MGR" in
        dnf)    printf '%s\n' /etc/dnf/dnf.conf main max_parallel_downloads "=" ;;
        pacman) printf '%s\n' /etc/pacman.conf options ParallelDownloads " = " ;;
        *)      return 1 ;;
    esac
}

# Current value of the key inside its section, or nothing if unset.
_pardl_current() {
    local conf section key sep
    { IFS= read -r conf; IFS= read -r section; IFS= read -r key; IFS= read -r sep; } < <(_pardl_conf) || return 1
    [[ -f "$conf" ]] || return 0
    awk -v section="$section" -v key="$key" '
        /^[[:space:]]*\[/ { insec = ($0 ~ "^[[:space:]]*\\[" section "\\]"); next }
        insec && $0 ~ "^[[:space:]]*" key "[[:space:]]*=" {
            sub("^[^=]*=[[:space:]]*", ""); sub("[[:space:]]*$", ""); print; exit
        }
    ' "$conf"
}

# Emit the config on stdin to stdout with the key set to <value> directly under
# the section header (any other active line for the key in that section is
# dropped; commented-out lines are left alone). Adds the section if missing.
_pardl_set_awk() {
    local section="$1" line="$2" key="$3"
    awk -v section="$section" -v line="$line" -v key="$key" '
        /^[[:space:]]*\[/ {
            insec = ($0 ~ "^[[:space:]]*\\[" section "\\]")
            print
            if (insec && !done) { print line; done = 1 }
            next
        }
        insec && $0 ~ "^[[:space:]]*" key "[[:space:]]*=" { next }
        { print }
        END { if (!done) { if (NR > 0) print ""; print "[" section "]"; print line } }
    '
}

# Emit the config on stdin to stdout with the key removed from the section.
_pardl_remove_awk() {
    local section="$1" key="$2"
    awk -v section="$section" -v key="$key" '
        /^[[:space:]]*\[/ { insec = ($0 ~ "^[[:space:]]*\\[" section "\\]"); print; next }
        insec && $0 ~ "^[[:space:]]*" key "[[:space:]]*=" { next }
        { print }
    '
}

# Back up the config and install the generated file over it, keeping the
# standard root:root 0644 ownership/permissions.
_pardl_install_file() {
    local src="$1" conf="$2" backup
    if [[ -f "$conf" ]]; then
        backup="${conf}.bak.$(date +%Y%m%d_%H%M%S)"
        run_as_root cp -- "$conf" "$backup" || { error "Failed to back up ${conf}."; return 1; }
        info "Backed up existing config to ${backup}"
    fi
    run_as_root install -m 0644 -- "$src" "$conf" || { error "Failed to write ${conf}."; return 1; }
}

check_parallel_downloads() {
    local cur
    cur=$(_pardl_current) || return 1
    [[ "$cur" =~ ^[0-9]+$ ]] && (( cur >= _PARDL_VALUE ))
}

install_parallel_downloads() {
    local conf section key sep tmp
    { IFS= read -r conf; IFS= read -r section; IFS= read -r key; IFS= read -r sep; } < <(_pardl_conf) || {
        error "Parallel downloads can only be set for dnf and pacman."
        return 1
    }

    if check_parallel_downloads; then
        info "${key} is already $(_pardl_current) in ${conf}. Nothing to do."
        return 0
    fi

    info "Setting ${key} to ${_PARDL_VALUE} in ${conf}..."
    tmp="$(mktemp)" || { error "Failed to create a temporary file."; return 1; }
    if [[ -f "$conf" ]]; then
        _pardl_set_awk "$section" "${key}${sep}${_PARDL_VALUE}" "$key" < "$conf" > "$tmp"
    else
        _pardl_set_awk "$section" "${key}${sep}${_PARDL_VALUE}" "$key" < /dev/null > "$tmp"
    fi
    _pardl_install_file "$tmp" "$conf"
    local rc=$?
    rm -f -- "$tmp"
    (( rc == 0 )) || return 1
    info "${key} set to ${_PARDL_VALUE}."
}

uninstall_parallel_downloads() {
    local conf section key sep tmp
    { IFS= read -r conf; IFS= read -r section; IFS= read -r key; IFS= read -r sep; } < <(_pardl_conf) || return 0
    [[ -f "$conf" ]] || return 0

    tmp="$(mktemp)" || { error "Failed to create a temporary file."; return 1; }
    case "$PKG_MGR" in
        dnf)
            # Removing the key returns dnf to its built-in default (3).
            info "Removing ${key} from ${conf} (dnf default: 3)..."
            _pardl_remove_awk "$section" "$key" < "$conf" > "$tmp"
            ;;
        pacman)
            # Without the key pacman downloads one package at a time, so put
            # back the value Arch's stock pacman.conf ships instead.
            info "Restoring ${key} to 5 in ${conf} (the stock pacman.conf value)..."
            _pardl_set_awk "$section" "${key}${sep}5" "$key" < "$conf" > "$tmp"
            ;;
    esac
    _pardl_install_file "$tmp" "$conf"
    local rc=$?
    rm -f -- "$tmp"
    return "$rc"
}

update_parallel_downloads() {
    install_parallel_downloads
}

get_version_parallel_downloads() {
    _pardl_current
}

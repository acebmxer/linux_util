#!/bin/bash
# Fix RDP Kerberos Delay — disables Kerberos DNS lookups in /etc/krb5.conf.
#
# The MIT krb5 package (a FreeRDP/Remmina dependency on Arch, CachyOS, and most
# distros) ships a sample /etc/krb5.conf that does NOT set dns_lookup_kdc, so
# krb5 falls back to its built-in default of dns_lookup_kdc = true. When a
# Windows RDP host advertises a Kerberos realm during SPNEGO negotiation,
# libfreerdp asks krb5 to locate a KDC, krb5 fires a DNS SRV lookup for
# _kerberos._tcp.<REALM>, finds a domain controller it cannot reach, and stalls
# ~20s per attempt before finally falling back to NTLM. Remmina and xfreerdp
# share the same libfreerdp + krb5, so both hang on every connection.
#
# Forcing the three [libdefaults] keys below to false skips those lookups and
# lets the NTLM fallback happen immediately. This is realm-agnostic — it fixes
# every domain, not a single hard-coded one — so leave default_realm and the
# [realms]/[domain_realm]/[logging] sections untouched.

readonly _KRB5_CONF="/etc/krb5.conf"
# Keys forced to false so krb5 stops doing the slow SRV/reverse-DNS lookups
# that stall FreeRDP/Remmina before the NTLM fallback.
readonly -a _KRB5_KEYS=(dns_lookup_kdc dns_lookup_realm rdns)

# Print the contents of the [libdefaults] section only (no section header).
# Returns 1 if the config file is missing.
_krb5_libdefaults_block() {
    [[ -f "$_KRB5_CONF" ]] || return 1
    awk '
        /^[[:space:]]*\[/ { inlib = ($0 ~ /^[[:space:]]*\[libdefaults\]/); next }
        inlib { print }
    ' "$_KRB5_CONF"
}

# Emit a corrected krb5.conf on stdout: each target key is forced to "false"
# directly under the [libdefaults] header, any stale occurrences of those keys
# elsewhere in [libdefaults] are dropped, and a [libdefaults] section is created
# if the file has none (or is empty). Idempotent — running it twice is a no-op.
_krb5_set_false_awk() {
    awk -v keys="${_KRB5_KEYS[*]}" '
    BEGIN {
        n = split(keys, karr, " ")
        for (i = 1; i <= n; i++) want[karr[i]] = 1
        inlib = 0; seen_lib = 0; indent = "    "
    }
    /^[[:space:]]*\[/ {
        inlib = ($0 ~ /^[[:space:]]*\[libdefaults\]/)
        print
        if (inlib) {
            seen_lib = 1
            for (i = 1; i <= n; i++)
                if (!emitted[karr[i]]) { print indent karr[i] " = false"; emitted[karr[i]] = 1 }
        }
        next
    }
    inlib {
        for (k in want) if ($0 ~ "^[[:space:]]*" k "[[:space:]]*=") next
        print; next
    }
    { print }
    END {
        if (!seen_lib) {
            if (NR > 0) print ""
            print "[libdefaults]"
            for (i = 1; i <= n; i++)
                if (!emitted[karr[i]]) print indent karr[i] " = false"
        }
    }
    '
}

# Emit a krb5.conf on stdout with the target keys removed from [libdefaults]
# only (keys with the same name in other sections are left alone).
_krb5_remove_awk() {
    awk -v keys="${_KRB5_KEYS[*]}" '
    BEGIN { n = split(keys, karr, " "); for (i = 1; i <= n; i++) want[karr[i]] = 1; inlib = 0 }
    /^[[:space:]]*\[/ { inlib = ($0 ~ /^[[:space:]]*\[libdefaults\]/); print; next }
    inlib {
        for (k in want) if ($0 ~ "^[[:space:]]*" k "[[:space:]]*=") next
        print; next
    }
    { print }
    '
}

# Back up the current krb5.conf (if any) and install the generated file in its
# place, preserving the standard root:root 0644 ownership/permissions.
_krb5_install_file() {
    local src="$1"
    if [[ -f "$_KRB5_CONF" ]]; then
        local backup="${_KRB5_CONF}.bak.$(date +%Y%m%d_%H%M%S)"
        run_as_root cp -- "$_KRB5_CONF" "$backup" || { error "Failed to back up ${_KRB5_CONF}."; return 1; }
        info "Backed up existing config to ${backup}"
    fi
    run_as_root install -m 0644 -- "$src" "$_KRB5_CONF" \
        || { error "Failed to write ${_KRB5_CONF}."; return 1; }
}

check_fix_rdp_kerberos() {
    local block key
    block="$(_krb5_libdefaults_block)" || return 1
    for key in "${_KRB5_KEYS[@]}"; do
        grep -Eiq "^[[:space:]]*${key}[[:space:]]*=[[:space:]]*(false|no|0|off)[[:space:]]*$" <<< "$block" || return 1
    done
    return 0
}

install_fix_rdp_kerberos() {
    info "Disabling Kerberos DNS lookups in ${_KRB5_CONF} (speeds up FreeRDP/Remmina NTLM fallback)..."

    if check_fix_rdp_kerberos; then
        info "Already configured — dns_lookup_kdc, dns_lookup_realm and rdns are disabled. Nothing to do."
        return 0
    fi

    [[ -f "$_KRB5_CONF" ]] || warn "${_KRB5_CONF} not found — creating a minimal one (krb5/FreeRDP not installed yet?)."

    local tmp
    tmp="$(mktemp)" || { error "Failed to create a temporary file."; return 1; }

    if [[ -f "$_KRB5_CONF" ]]; then
        _krb5_set_false_awk < "$_KRB5_CONF" > "$tmp"
    else
        _krb5_set_false_awk < /dev/null > "$tmp"
    fi

    if [[ ! -s "$tmp" ]]; then
        error "Failed to generate the updated ${_KRB5_CONF}."
        rm -f "$tmp"
        return 1
    fi

    _krb5_install_file "$tmp" || { rm -f "$tmp"; return 1; }
    rm -f "$tmp"

    info "Done — [libdefaults] now sets dns_lookup_kdc = false, dns_lookup_realm = false and rdns = false."
    info "Remmina / xfreerdp will fall back to NTLM immediately instead of stalling ~20s on KDC SRV lookups, for every realm."
    return 0
}

uninstall_fix_rdp_kerberos() {
    info "Reverting Kerberos DNS-lookup fix in ${_KRB5_CONF}..."

    if [[ ! -f "$_KRB5_CONF" ]]; then
        info "${_KRB5_CONF} not present — nothing to revert."
        return 0
    fi

    local tmp
    tmp="$(mktemp)" || { error "Failed to create a temporary file."; return 1; }
    _krb5_remove_awk < "$_KRB5_CONF" > "$tmp"

    if cmp -s "$tmp" "$_KRB5_CONF"; then
        info "Fix not present in ${_KRB5_CONF} — nothing to revert."
        rm -f "$tmp"
        return 0
    fi

    _krb5_install_file "$tmp" || { rm -f "$tmp"; return 1; }
    rm -f "$tmp"

    info "Removed dns_lookup_kdc, dns_lookup_realm and rdns from [libdefaults]. krb5 default behaviour restored."
    return 0
}

update_fix_rdp_kerberos() {
    install_fix_rdp_kerberos
}

get_version_fix_rdp_kerberos() {
    if check_fix_rdp_kerberos; then
        echo "configured"
    fi
}

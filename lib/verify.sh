#!/bin/bash

# ============================================================================
# Linux Utilities - Download Verification Module
# Provides helpers to verify integrity of downloaded binaries before install.
# ============================================================================

# Check a file is non-empty and not an HTML error page.
# Returns 1 and logs an error on failure.
_verify_not_empty_or_html() {
    local file="$1" label="$2"
    if [[ ! -s "$file" ]]; then
        error "Download verification failed: ${label} is empty (0 bytes)."
        return 1
    fi
    if head -c 15 "$file" 2>/dev/null | grep -qi "<html"; then
        error "Download verification failed: server returned an HTML error page instead of ${label}."
        return 1
    fi
    return 0
}

# Verify magic bytes / file format using the system `file` command.
# If `file` is unavailable the check is silently skipped.
# Supported extensions: deb, rpm, tar.gz, tgz, gz, tar.bz2, tbz, bz2, AppImage, run
# Returns 1 on format mismatch, 0 otherwise.
_verify_magic_bytes() {
    local file="$1" ext="$2" label="$3"
    if ! command -v file &>/dev/null; then
        verbose "Skipping magic-byte check for ${label} (file command unavailable)"
        return 0
    fi
    local file_output
    file_output=$(file "$file" 2>/dev/null)
    case "$ext" in
        deb)
            echo "$file_output" | grep -qiE "Debian binary package|current ar archive" && return 0
            error "Download verification failed: ${label} does not appear to be a valid .deb package."
            return 1
            ;;
        rpm)
            echo "$file_output" | grep -qi "RPM" && return 0
            error "Download verification failed: ${label} does not appear to be a valid .rpm package."
            return 1
            ;;
        tar.gz|tgz|gz)
            echo "$file_output" | grep -qi "gzip compressed" && return 0
            error "Download verification failed: ${label} does not appear to be a valid gzip archive."
            return 1
            ;;
        tar.bz2|tbz|bz2)
            echo "$file_output" | grep -qi "bzip2 compressed" && return 0
            error "Download verification failed: ${label} does not appear to be a valid bzip2 archive."
            return 1
            ;;
        AppImage)
            # AppImages are typically ELF executables; emit a soft warning rather than failing.
            echo "$file_output" | grep -qi "ELF" || \
                warn "Download: ${label} may not be a valid AppImage (expected ELF executable)."
            return 0
            ;;
        run)
            # Self-extracting scripts vary — non-empty / non-HTML check suffices.
            return 0
            ;;
    esac
    return 0
}

# Verify a file's SHA256 checksum against an expected hash string.
# Returns 1 and logs an error on mismatch; 0 on pass.
# Falls back gracefully when sha256sum / shasum is absent.
verify_sha256() {
    local file="$1" expected_hash="$2" label="${3:-downloaded file}"
    local actual_hash
    if command -v sha256sum &>/dev/null; then
        actual_hash=$(sha256sum "$file" | awk '{print $1}')
    elif command -v shasum &>/dev/null; then
        actual_hash=$(shasum -a 256 "$file" | awk '{print $1}')
    else
        warn "sha256sum not available — skipping checksum verification for ${label}."
        return 0
    fi
    if [[ "${actual_hash,,}" != "${expected_hash,,}" ]]; then
        error "Checksum verification FAILED for ${label}"
        error "  Expected: ${expected_hash}"
        error "  Got:      ${actual_hash}"
        return 1
    fi
    verbose "Checksum verified: ${label}"
    return 0
}

# Combined download verification: non-empty, not an HTML error page, correct magic bytes.
# Usage: verify_download <file> <ext> <label>
verify_download() {
    local file="$1" ext="$2" label="$3"
    _verify_not_empty_or_html "$file" "$label" || return 1
    _verify_magic_bytes       "$file" "$ext" "$label" || return 1
    return 0
}

# Best-effort GitHub release checksum verification.
#
# Fetches the release JSON from <api_release_url>, looks for a checksums
# asset (checksums.txt, SHA256SUMS, sha256sums, or <asset_filename>.sha256),
# and verifies <local_file> against it when found.
#
# Returns 0 when no checksums file is found (non-blocking) or verification passes.
# Returns 1 only when a checksums file IS found and verification FAILS.
#
# Usage: github_verify_checksum <api_release_url> <asset_filename> <local_file>
github_verify_checksum() {
    local api_url="$1" asset_filename="$2" local_file="$3"
    verbose "Seeking checksums for ${asset_filename} in GitHub release..."

    local release_json
    release_json=$(curl -fsSL "${api_url}" 2>/dev/null) || {
        warn "Could not fetch GitHub release JSON for checksum lookup — skipping."
        return 0
    }

    # Collect all browser_download_url values from the release JSON.
    local all_urls=()
    mapfile -t all_urls < <(
        echo "$release_json" \
            | grep -oP '"browser_download_url"\s*:\s*"\K[^"]+' )

    # Search for a checksums asset or a per-file .sha256 sidecar.
    local checksums_url=""
    local bname
    for bname in "${all_urls[@]}"; do
        local fname
        fname=$(basename "$bname")
        if echo "$fname" | grep -qiE "^(checksums?\.txt|SHA256SUMS?|sha256sums?)$" || \
               [[ "$fname" == "${asset_filename}.sha256" ]]; then
            checksums_url="$bname"
            break
        fi
    done

    if [[ -z "$checksums_url" ]]; then
        verbose "No checksums asset found in GitHub release — skipping verification."
        return 0
    fi

    verbose "Verifying checksum from: ${checksums_url}"
    local checksums_content
    checksums_content=$(curl -fsSL "$checksums_url" 2>/dev/null) || {
        warn "Could not download checksums file — skipping verification."
        return 0
    }

    local expected_hash
    expected_hash=$(echo "$checksums_content" \
        | grep -iF "$asset_filename" | awk '{print $1}' | head -1)

    if [[ -z "$expected_hash" ]]; then
        verbose "Filename '${asset_filename}' not found in checksums file — skipping."
        return 0
    fi

    verify_sha256 "$local_file" "$expected_hash" "$asset_filename" || return 1
    return 0
}

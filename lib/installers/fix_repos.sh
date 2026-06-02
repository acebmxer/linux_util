#!/bin/bash
# Fix Package Repos — repair/refresh repository metadata (broken mirrors, stale
# caches, missing keys). Action-style system task: always runnable, nothing
# persistent to install/uninstall.
#
# Flow: a metadata refresh runs first as the check. If it surfaces errors the
# heavier repair (cache wipe / keyring reinit) proceeds; if the refresh is clean
# the user is asked "No issues found. Continue anyway?" and can bail out.

setup_fix_repos() {
    info "Checking package repositories (PKG_MGR=${PKG_MGR:-unknown})..."

    local issues=""   # non-empty once a problem is detected

    case "${PKG_MGR:-}" in
        apt)
            info "Refreshing repository metadata (apt-get update)..."
            local out rc
            out=$(sudo apt-get update 2>&1); rc=$?
            printf '%s\n' "$out"
            if (( rc != 0 )) || grep -qE '^(Err|W):' <<<"$out"; then
                issues=1
                warn "apt-get update reported errors (missing GPG keys, unreachable mirrors, etc.)."
            fi

            _repair_gate "$issues" || return 3

            info "Clearing cached package lists and re-downloading all metadata..."
            sudo apt-get clean
            sudo rm -rf /var/lib/apt/lists/*
            sudo mkdir -p /var/lib/apt/lists/partial
            sudo apt-get update
            ;;

        dnf|yum)
            info "Refreshing repository metadata (${PKG_MGR} makecache)..."
            local out rc
            out=$(sudo "${PKG_MGR}" makecache 2>&1); rc=$?
            printf '%s\n' "$out" | tail -n 20
            (( rc != 0 )) && { issues=1; warn "Metadata refresh reported errors."; }

            _repair_gate "$issues" || return 3

            info "Clearing all cached metadata and rebuilding..."
            sudo "${PKG_MGR}" clean all
            sudo "${PKG_MGR}" makecache
            info "Current repository status:"
            sudo "${PKG_MGR}" repolist 2>&1 | tail -n 20 || true
            ;;

        pacman)
            info "Refreshing repository databases (pacman -Sy)..."
            sudo pacman -Sy || { issues=1; warn "Database refresh reported issues (see above)."; }

            _repair_gate "$issues" || return 3

            info "Force-refreshing databases (pacman -Syy)..."
            sudo pacman -Syy || warn "Database refresh reported issues."
            # Signature/keyring errors are a common cause of refresh failures.
            info "Reinitializing and repopulating the pacman keyring..."
            sudo pacman-key --init
            sudo pacman-key --populate
            ;;

        zypper)
            info "Refreshing repositories (zypper refresh)..."
            local out rc
            out=$(sudo zypper refresh 2>&1); rc=$?
            printf '%s\n' "$out"
            (( rc != 0 )) && { issues=1; warn "Repository refresh reported errors."; }

            _repair_gate "$issues" || return 3

            info "Clearing cached metadata and forcing a refresh..."
            sudo zypper clean -a
            sudo zypper refresh --force
            ;;

        *)
            error "Unsupported package manager: ${PKG_MGR:-unknown}"
            return 1
            ;;
    esac

    info "Repository repair complete."
    _repair_done
}

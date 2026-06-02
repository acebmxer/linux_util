#!/bin/bash
# Fix Broken Packages — repair half-installed packages and unmet dependencies.
# Action-style system task: always runnable, nothing persistent to install/uninstall.
#
# Flow: a read-only check runs first. If problems are found the repair proceeds;
# if nothing is wrong the user is asked "No issues found. Continue anyway?" and
# can bail out. The repair commands themselves (apt/dnf/pacman/zypper) prompt
# before adding or removing packages.

setup_fix_broken_packages() {
    info "Checking for broken package installs (PKG_MGR=${PKG_MGR:-unknown})..."

    local issues=""   # non-empty once a problem is detected

    case "${PKG_MGR:-}" in
        apt)
            # Read-only detection (no root needed): packages needing
            # reconfiguration/reinstall, plus broken/unmet dependencies.
            local audit check
            audit=$(dpkg --audit 2>/dev/null)
            check=$(LC_ALL=C apt-get check 2>&1 | grep -iE 'broken|unmet' || true)
            if [[ -n "$audit" ]]; then
                issues=1
                warn "Packages needing reconfiguration/reinstall:"
                printf '%s\n' "$audit"
            fi
            [[ -n "$check" ]] && { issues=1; warn "Broken or unmet dependencies detected."; }

            _repair_gate "$issues" || return 3

            info "Reconfiguring any half-installed packages (dpkg --configure -a)..."
            sudo dpkg --configure -a
            info "Repairing dependencies (apt-get --fix-broken install)..."
            sudo apt-get --fix-broken install
            ;;

        dnf|yum)
            local out rc
            out=$("${PKG_MGR}" check 2>&1); rc=$?
            if (( rc != 0 )); then
                issues=1
                warn "Dependency problems detected:"
                printf '%s\n' "$out" | tail -n 50
            fi

            _repair_gate "$issues" || return 3

            info "Rebuilding RPM database (rpm --rebuilddb)..."
            sudo rpm --rebuilddb
            info "Resolving broken/duplicate packages (${PKG_MGR} distro-sync)..."
            sudo "${PKG_MGR}" distro-sync
            ;;

        pacman)
            # A stale database lock from an interrupted operation counts as an issue.
            local lock="" depk
            if [[ -e /var/lib/pacman/db.lck ]] && ! pgrep -x pacman >/dev/null 2>&1; then
                lock=1; issues=1
                warn "Stale pacman lock found at /var/lib/pacman/db.lck (no pacman process running)."
            fi
            if ! depk=$(pacman -Dk 2>&1); then
                issues=1
                warn "Missing package dependencies detected:"
                printf '%s\n' "$depk"
            fi

            _repair_gate "$issues" || return 3

            [[ -n "$lock" ]] && { info "Removing stale lock file..."; sudo rm -f /var/lib/pacman/db.lck; }
            info "Running full sync upgrade (pacman -Syu)..."
            sudo pacman -Syu
            ;;

        zypper)
            local out
            out=$(sudo zypper --non-interactive verify --dry-run 2>&1)
            printf '%s\n' "$out" | tail -n 20
            grep -qiE 'are satisfied|Nothing to do' <<<"$out" || { issues=1; warn "Dependency problems detected."; }

            _repair_gate "$issues" || return 3

            info "Rebuilding RPM database (rpm --rebuilddb)..."
            sudo rpm --rebuilddb
            info "Verifying and repairing dependencies (zypper verify)..."
            sudo zypper verify
            ;;

        *)
            error "Unsupported package manager: ${PKG_MGR:-unknown}"
            return 1
            ;;
    esac

    info "Broken-package repair complete."
    _repair_done
}

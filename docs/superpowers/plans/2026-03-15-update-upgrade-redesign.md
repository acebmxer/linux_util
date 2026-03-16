# Update & Upgrade Redesign Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Redesign the two system update menu options so "System Updates" does package-level updates only while "Full System Upgrade/Update" handles distro version upgrades with LTS awareness, both with thorough cleanup.

**Architecture:** Three new `pkg_*` functions in `lib/pkg_manager.sh` handle cleanup, upgrade detection, and upgrade execution. The two orchestrator functions in `lib/installers.sh` are rewritten to use these building blocks. `pkg_full_upgrade` is refactored to remove its embedded `apt update`.

**Tech Stack:** Bash, apt/dnf/pacman/zypper, do-release-upgrade, dnf system-upgrade, zypper dup

**Spec:** `docs/superpowers/specs/2026-03-15-update-upgrade-redesign-design.md`

---

## Chunk 1: Refactor pkg_full_upgrade and add pkg_cleanup_thorough

### Task 1: Refactor `pkg_full_upgrade()` to remove embedded apt update

**Files:**
- Modify: `lib/pkg_manager.sh:153-160`

- [ ] **Step 1: Update `pkg_full_upgrade()` to remove internal `apt update`**

In `lib/pkg_manager.sh`, change the `apt` case in `pkg_full_upgrade()` from:

```bash
apt)     sudo apt update && sudo apt full-upgrade -y ;;
```

to:

```bash
apt)     sudo apt full-upgrade -y ;;
```

This makes `pkg_full_upgrade` a pure upgrade operation. Callers are responsible for calling `pkg_refresh` first.

- [ ] **Step 2: Verify no other callers rely on the embedded apt update**

Search the codebase for calls to `pkg_full_upgrade`:

```bash
grep -rn 'pkg_full_upgrade' lib/ linux_util.sh
```

Expected: Only found in `lib/installers.sh` inside `setup_full_update_bare_metal` and `setup_system_updates` — both of which will be rewritten to call `pkg_refresh` first.

- [ ] **Step 3: Commit**

```bash
git add lib/pkg_manager.sh
git commit -m "refactor: remove embedded apt update from pkg_full_upgrade

Callers now explicitly call pkg_refresh before pkg_full_upgrade,
making pkg_full_upgrade a pure upgrade operation."
```

---

### Task 2: Add `pkg_cleanup_thorough()` to pkg_manager.sh

**Files:**
- Modify: `lib/pkg_manager.sh` (add after `pkg_clean()` at line 169, before `pkg_get_version()`)

- [ ] **Step 1: Write `pkg_cleanup_thorough()`**

Add the following function after `pkg_clean()` (after line 169) and before `pkg_get_version()` (line 171):

```bash
# Thorough cleanup: autoremove, old kernels, purge configs, clean cache
pkg_cleanup_thorough() {
    info "Running thorough system cleanup..."

    # Step 1: Remove orphaned dependencies
    pkg_autoremove

    # Step 2: Remove old kernels (keep current + one previous)
    local current_kernel
    current_kernel=$(uname -r)
    info "Current kernel: ${current_kernel} (will be preserved)"

    case "$PKG_MGR" in
        apt)
            # List installed kernels, exclude current and latest, purge the rest
            local kernels_to_remove=""
            local installed_kernels
            installed_kernels=$(dpkg -l 'linux-image-*' 2>/dev/null | awk '/^ii.*linux-image-[0-9]/ {print $2}' | sort -V)
            if [[ -n "$installed_kernels" ]]; then
                # Keep the two newest and the currently running kernel
                local keep_count=2
                local total
                total=$(echo "$installed_kernels" | wc -l)
                if (( total > keep_count )); then
                    kernels_to_remove=$(echo "$installed_kernels" | head -n -${keep_count} | grep -v "$current_kernel" || true)
                fi
            fi
            if [[ -n "$kernels_to_remove" ]]; then
                info "Removing old kernels: $(echo "$kernels_to_remove" | tr '\n' ' ')"
                # Also remove matching headers
                local headers_to_remove=""
                for kern in $kernels_to_remove; do
                    local ver
                    ver=$(echo "$kern" | sed 's/linux-image-\(unsigned-\)\?//')
                    if dpkg -l "linux-headers-${ver}" 2>/dev/null | grep -q "^ii"; then
                        headers_to_remove+="linux-headers-${ver} "
                    fi
                done
                # shellcheck disable=SC2086
                sudo apt-get purge -y $kernels_to_remove $headers_to_remove 2>/dev/null || true
            else
                info "No old kernels to remove."
            fi
            ;;
        dnf|yum)
            sudo "$PKG_MGR" remove -y --oldinstallonly --setopt installonly_limit=2 2>/dev/null || true
            ;;
        pacman)
            # Arch doesn't accumulate old kernels the same way; skip
            ;;
        zypper)
            sudo zypper purge-kernels --keep 2 2>/dev/null || true
            ;;
    esac

    # Step 3: Purge removed package configs (Debian family only)
    if [[ "$PKG_MGR" == "apt" ]]; then
        local rc_packages
        rc_packages=$(dpkg -l 2>/dev/null | awk '/^rc/ {print $2}')
        if [[ -n "$rc_packages" ]]; then
            info "Purging removed package configs..."
            # shellcheck disable=SC2086
            sudo dpkg --purge $rc_packages 2>/dev/null || true
        fi
    fi

    # Step 4: Clean package cache
    pkg_clean

    # Step 5: Clean apt lists partial files (Debian family only)
    if [[ "$PKG_MGR" == "apt" ]]; then
        sudo rm -f /var/lib/apt/lists/partial/* 2>/dev/null || true
    fi

    info "System cleanup completed."
}
```

- [ ] **Step 2: Run the test suite to ensure nothing is broken**

```bash
bash tests/test_linux_util.sh
```

Expected: All existing tests pass. No tests exercise `pkg_cleanup_thorough` directly yet (it's a new function).

- [ ] **Step 3: Commit**

```bash
git add lib/pkg_manager.sh
git commit -m "feat: add pkg_cleanup_thorough for enhanced system cleanup

Handles autoremove, old kernel removal (keep current + 1 previous),
purging removed package configs (Debian), cache cleaning, and
apt lists cleanup. Dispatches on PKG_MGR so dnf branch covers
both Fedora and RHEL families."
```

---

## Chunk 2: Add pkg_check_upgrade_available and pkg_distro_upgrade

### Task 3: Add `pkg_check_upgrade_available()` to pkg_manager.sh

**Files:**
- Modify: `lib/pkg_manager.sh` (add after `pkg_cleanup_thorough()`, before `pkg_get_version()`)

- [ ] **Step 1: Write `pkg_check_upgrade_available()`**

Add the following function after `pkg_cleanup_thorough()`:

```bash
# Check if a distribution version upgrade is available.
# Returns 0 if available (outputs target version to stdout), 1 if not.
# Dispatches on DISTRO_ID since upgrade paths are distro-specific.
pkg_check_upgrade_available() {
    case "$DISTRO_ID" in
        ubuntu|kubuntu|pop|neon)
            # Ensure do-release-upgrade is available
            if ! command -v do-release-upgrade &>/dev/null; then
                info "Installing update-manager-core for upgrade checks..."
                sudo apt-get install -y update-manager-core 2>/dev/null || {
                    warn "Could not install update-manager-core"
                    return 1
                }
            fi
            # Check for available upgrade
            local check_output
            check_output=$(do-release-upgrade -c 2>&1) || true
            if echo "$check_output" | grep -qi "new release"; then
                # Extract target version from output like "New release '24.04 LTS' available."
                local target
                target=$(echo "$check_output" | grep -oP "New release '\K[^']+")
                if [[ -n "$target" ]]; then
                    echo "$target"
                    return 0
                fi
            fi
            return 1
            ;;
        fedora)
            # Try next release version — use repoquery to check if the next version's repos exist
            # without downloading any packages
            local next_ver=$(( DISTRO_VERSION_ID + 1 ))
            if sudo dnf --releasever="$next_ver" --repo=fedora repoquery --latest-limit=1 fedora-release &>/dev/null; then
                echo "$next_ver"
                return 0
            fi
            return 1
            ;;
        opensuse-leap)
            # Check for newer Leap version by querying product info
            local current_ver="$DISTRO_VERSION_ID"
            # Try incrementing minor version first (e.g., 15.5 -> 15.6), then major
            local major minor next_minor next_major
            major=$(echo "$current_ver" | cut -d. -f1)
            minor=$(echo "$current_ver" | cut -d. -f2)
            next_minor="${major}.$(( minor + 1 ))"
            next_major="$(( major + 1 )).0"

            # Check if next minor version repos exist
            if curl -sf --head "https://download.opensuse.org/distribution/leap/${next_minor}/repo/oss/" &>/dev/null; then
                echo "$next_minor"
                return 0
            elif curl -sf --head "https://download.opensuse.org/distribution/leap/${next_major}/repo/oss/" &>/dev/null; then
                echo "$next_major"
                return 0
            fi
            return 1
            ;;
        opensuse-tumbleweed|arch|manjaro|endeavouros|garuda|artix)
            # Rolling release — no discrete version upgrades
            return 1
            ;;
        rhel|centos|rocky|alma|ol|almalinux)
            # RHEL family: major version upgrades managed externally
            return 1
            ;;
        debian|linuxmint|elementary|zorin|kali)
            # Debian stable and derivatives: version upgrades require manual sources.list editing
            return 1
            ;;
        *)
            # Unknown distro — no upgrade path
            return 1
            ;;
    esac
}
```

- [ ] **Step 2: Run test suite**

```bash
bash tests/test_linux_util.sh
```

Expected: All existing tests pass.

- [ ] **Step 3: Commit**

```bash
git add lib/pkg_manager.sh
git commit -m "feat: add pkg_check_upgrade_available for distro upgrade detection

Supports Ubuntu (do-release-upgrade -c), Fedora (dnf system-upgrade),
and openSUSE Leap (repo URL check). Returns 1 for rolling release
distros, RHEL family, and Debian stable."
```

---

### Task 4: Add `pkg_distro_upgrade()` to pkg_manager.sh

**Files:**
- Modify: `lib/pkg_manager.sh` (add after `pkg_check_upgrade_available()`, before `pkg_get_version()`)

- [ ] **Step 1: Write `pkg_distro_upgrade()`**

Add the following function after `pkg_check_upgrade_available()`:

```bash
# Perform a distribution version upgrade.
# Argument: $1 = target version (from pkg_check_upgrade_available output)
# Returns 0 on success, 1 on failure.
pkg_distro_upgrade() {
    local target_version="$1"

    case "$DISTRO_ID" in
        ubuntu|kubuntu|pop|neon)
            # LTS awareness: check if current release is LTS
            local release_config="/etc/update-manager/release-upgrades"
            local original_prompt=""

            if [[ -f "$release_config" ]]; then
                original_prompt=$(grep -oP '^Prompt=\K.*' "$release_config" 2>/dev/null || echo "")

                # Check if current version is LTS (Ubuntu LTS versions: XX.04 where XX is even)
                local is_lts=false
                if [[ "$DISTRO_ID" == "ubuntu" ]]; then
                    local year month
                    year=$(echo "$DISTRO_VERSION_ID" | cut -d. -f1)
                    month=$(echo "$DISTRO_VERSION_ID" | cut -d. -f2)
                    if (( month == 4 && year % 2 == 0 )); then
                        is_lts=true
                    fi
                fi

                if [[ "$is_lts" == "true" ]]; then
                    echo ""
                    echo "You are currently on an LTS release (${DISTRO_NAME} ${DISTRO_VERSION_ID})."
                    echo ""
                    echo "  1) Stay on LTS track (upgrade only to next LTS release)"
                    echo "  2) Upgrade to latest release (including non-LTS)"
                    echo ""
                    local lts_choice=""
                    while [[ "$lts_choice" != "1" && "$lts_choice" != "2" ]]; do
                        read -rp "Choose [1/2]: " lts_choice
                    done

                    if [[ "$lts_choice" == "1" ]]; then
                        sudo sed -i "s/^Prompt=.*/Prompt=lts/" "$release_config"
                    else
                        sudo sed -i "s/^Prompt=.*/Prompt=normal/" "$release_config"
                    fi
                fi
            fi

            info "Starting distribution upgrade to ${target_version}..."
            if sudo do-release-upgrade -f DistUpgradeViewNonInteractive; then
                info "Distribution upgrade to ${target_version} completed successfully."
                # Restore original prompt setting
                if [[ -n "$original_prompt" && -f "$release_config" ]]; then
                    sudo sed -i "s/^Prompt=.*/Prompt=${original_prompt}/" "$release_config"
                fi
                return 0
            else
                error "Distribution upgrade to ${target_version} failed."
                # Restore original prompt setting
                if [[ -n "$original_prompt" && -f "$release_config" ]]; then
                    sudo sed -i "s/^Prompt=.*/Prompt=${original_prompt}/" "$release_config"
                fi
                return 1
            fi
            ;;
        fedora)
            info "Downloading upgrade packages for Fedora ${target_version}..."
            if sudo dnf system-upgrade download --releasever="$target_version" -y; then
                info "Upgrade packages downloaded for Fedora ${target_version}."
                warn "A reboot is required to apply the upgrade. The system will prompt for reboot after cleanup."
                return 0
            else
                error "Failed to download upgrade packages for Fedora ${target_version}."
                return 1
            fi
            ;;
        opensuse-leap)
            info "Upgrading openSUSE Leap to ${target_version}..."
            # Update repo URLs to target version
            local current_ver="$DISTRO_VERSION_ID"
            sudo sed -i "s/${current_ver}/${target_version}/g" /etc/zypp/repos.d/*.repo 2>/dev/null || {
                error "Failed to update repository URLs."
                return 1
            }
            sudo zypper ref || {
                error "Failed to refresh repositories after URL update."
                return 1
            }
            if sudo zypper dup --allow-vendor-change -y; then
                info "openSUSE Leap upgrade to ${target_version} completed."
                return 0
            else
                error "openSUSE Leap upgrade to ${target_version} failed."
                return 1
            fi
            ;;
        *)
            # Should never be reached (guarded by pkg_check_upgrade_available)
            error "Distribution upgrade not supported for ${DISTRO_ID}."
            return 1
            ;;
    esac
}
```

- [ ] **Step 2: Run test suite**

```bash
bash tests/test_linux_util.sh
```

Expected: All existing tests pass.

- [ ] **Step 3: Commit**

```bash
git add lib/pkg_manager.sh
git commit -m "feat: add pkg_distro_upgrade for distribution version upgrades

Supports Ubuntu (do-release-upgrade with LTS prompt), Fedora
(dnf system-upgrade download only, no immediate reboot), and
openSUSE Leap (repo URL update + zypper dup). Restores original
release-upgrades Prompt setting after Ubuntu upgrades."
```

---

## Chunk 3: Rewrite orchestrator functions and update registrations

### Task 5: Rewrite `setup_system_updates()` in installers.sh

**Files:**
- Modify: `lib/installers.sh:642-650`

- [ ] **Step 1: Replace `setup_system_updates()`**

Replace the entire function (lines 642-650) with:

```bash
# --- System Updates ---
setup_system_updates() {
    info "Running system updates..."
    pkg_refresh
    pkg_full_upgrade
    pkg_cleanup_thorough
    info "System updates completed."
    return 0
}
```

- [ ] **Step 2: Run test suite**

```bash
bash tests/test_linux_util.sh
```

Expected: All existing tests pass.

- [ ] **Step 3: Commit**

```bash
git add lib/installers.sh
git commit -m "refactor: rewrite setup_system_updates with pkg_refresh and thorough cleanup

Now explicitly calls pkg_refresh before pkg_full_upgrade, and
uses pkg_cleanup_thorough for enhanced cleanup (old kernels,
purge configs, cache cleaning)."
```

---

### Task 6: Rewrite `setup_full_update_bare_metal()` as `setup_full_update()` in installers.sh

**Files:**
- Modify: `lib/installers.sh:576-640`

- [ ] **Step 1: Replace the entire function**

Replace lines 576-640 (`setup_full_update_bare_metal`) with:

```bash
# --- Full System Upgrade/Update ---
setup_full_update() {
    info "Starting full system upgrade/update..."

    # Step 1: Refresh repos
    pkg_refresh

    # Step 2: Check for distro version upgrade
    local target_version=""
    local upgrade_available=1
    if target_version=$(pkg_check_upgrade_available); then
        upgrade_available=0
    fi

    if [[ $upgrade_available -eq 0 && -n "$target_version" ]]; then
        # Display confirmation prompt
        echo ""
        echo ""
        echo "  *** A distribution upgrade is available ***"
        echo ""
        echo "  Current: ${DISTRO_NAME} ${DISTRO_VERSION_ID}"
        echo "  Target:  ${target_version}"
        echo ""
        echo "  This is a major operation and may take some time."
        echo ""
        local confirm=""
        read -rp "Continue with distribution upgrade? (y/N): " confirm
        if [[ "$confirm" =~ ^[Yy]$ ]]; then
            if pkg_distro_upgrade "$target_version"; then
                info "Distribution upgrade completed. Running cleanup..."
                pkg_cleanup_thorough
                info "Full system upgrade completed."
                return 0
            else
                warn "Distribution upgrade failed. Falling back to package updates..."
            fi
        else
            info "Distribution upgrade skipped by user."
        fi
    else
        info "No distribution version upgrade available."
    fi

    # Fallback: standard package update
    info "Performing package updates..."
    pkg_full_upgrade
    pkg_cleanup_thorough
    info "System update completed."
    return 0
}
```

- [ ] **Step 2: Run test suite**

```bash
bash tests/test_linux_util.sh
```

Expected: All existing tests pass.

- [ ] **Step 3: Commit**

```bash
git add lib/installers.sh
git commit -m "feat: rewrite setup_full_update with distro upgrade support

Renamed from setup_full_update_bare_metal. Checks for distro
version upgrades, shows confirmation prompt with current/target
versions, handles LTS awareness, falls back to package updates
if no upgrade available or user declines. Removes basic tools
install and keyring backup logic."
```

---

### Task 7: Update `register_utility` calls and comments

**Files:**
- Modify: `lib/installers.sh:179`
- Modify: `linux_util.sh:69`

- [ ] **Step 1: Update registration in installers.sh**

In `lib/installers.sh` line 179, change:

```bash
register_utility "Full System Upgrade/Update" setup_full_update_bare_metal check_always_false noop_function setup_full_update_bare_metal
```

to:

```bash
register_utility "Full System Upgrade/Update" setup_full_update check_always_false noop_function setup_full_update
```

- [ ] **Step 2: Update comment in linux_util.sh**

In `linux_util.sh` line 69, the comment already says "Full System Upgrade/Update" without "bare metal" — verify no other references to "bare_metal" or "bare metal" remain:

```bash
grep -rni 'bare.metal' lib/ linux_util.sh
```

Expected: No results (the old function body and registration have been replaced in prior tasks).

- [ ] **Step 3: Run test suite**

```bash
bash tests/test_linux_util.sh
```

Expected: All existing tests pass.

- [ ] **Step 4: Commit**

```bash
git add lib/installers.sh linux_util.sh
git commit -m "chore: update register_utility to use renamed setup_full_update

Removes all references to bare_metal naming."
```

---

### Task 8: Final verification

- [ ] **Step 1: Run full test suite**

```bash
bash tests/test_linux_util.sh
```

Expected: All tests pass, zero failures.

- [ ] **Step 2: Run shellcheck on modified files**

```bash
shellcheck lib/pkg_manager.sh lib/installers.sh linux_util.sh 2>&1 | head -50
```

Expected: No new warnings (existing warnings are acceptable).

- [ ] **Step 3: Verify no stale references**

```bash
grep -rn 'setup_full_update_bare_metal' lib/ linux_util.sh
grep -rn 'keyring_backup' lib/ linux_util.sh
```

Expected: No results for either search.

- [ ] **Step 4: Dry-run the script to verify menu renders**

```bash
bash linux_util.sh --dry-run
```

Expected: Menu displays with "Full System Upgrade/Update" and "System Updates" as selectable system tasks.

- [ ] **Step 5: Commit any fixes if needed, then final summary**

If shellcheck or verification found issues, fix and commit. Otherwise, the implementation is complete.

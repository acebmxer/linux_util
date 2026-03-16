# Update & Upgrade Redesign

## Overview

Redesign the two system update menu options in linux_util to clearly separate their responsibilities:

- **System Updates**: Package-level updates only. No distribution version upgrades.
- **Full System Upgrade/Update**: Distribution version upgrade (if available), with fallback to package updates. LTS-aware prompting on Ubuntu.

Both options refresh repos, perform thorough cleanup (old kernels, purged configs, cache), and autoremove orphaned dependencies.

## Changes from Current Implementation

### Removed
- Basic tools installation (`jq`, `git`, `curl`, `wget`, `gnupg`, etc.) from `setup_full_update_bare_metal`
- GNOME keyring backup/restore logic
- All "bare metal" naming — function renamed from `setup_full_update_bare_metal` to `setup_full_update`

### Added
- `pkg_cleanup_thorough()` — shared enhanced cleanup used by both options
- `pkg_check_upgrade_available()` — checks if a distro version upgrade exists
- `pkg_distro_upgrade()` — performs the actual distro version upgrade
- LTS-awareness prompting for Ubuntu (specifically Ubuntu and direct derivatives that ship `update-manager-core`)
- Pre-upgrade confirmation with current/target version display

## Design

### 1. `pkg_cleanup_thorough()` — Shared Cleanup

**Location:** `lib/pkg_manager.sh` (alongside existing `pkg_*` functions)

**Called by:** Both `setup_system_updates` and `setup_full_update`

**Dispatches on:** `$PKG_MGR` (not `$DISTRO_FAMILY`), so the `dnf` branch naturally covers both Fedora and RHEL families.

**Steps (in order):**

1. **`pkg_autoremove`** — remove orphaned dependencies
2. **Remove old kernels** (keep current + one previous):
   - Determine current running kernel via `uname -r`
   - `apt`: List installed `linux-image-*` and `linux-headers-*` via `dpkg -l`, exclude current (`uname -r`) and latest installed, `apt-get purge` the rest
   - `dnf/yum`: `dnf remove --oldinstallonly --setopt installonly_limit=2` (covers both Fedora and RHEL families)
   - `pacman`: skip (Arch does not accumulate old kernels the same way)
   - `zypper`: `zypper purge-kernels --keep 2`
3. **Purge removed package configs** (Debian family only): `dpkg --purge $(dpkg -l | awk '/^rc/ {print $2}')` — only runs if there are `rc` state packages
4. **`pkg_clean`** — clean package cache
5. **Clean apt lists** (Debian family only): remove `/var/lib/apt/lists/*` partial files

### 2. `setup_system_updates()` — System Updates

**Location:** `lib/installers.sh`

**Purpose:** Safe, no-version-change package updates with thorough cleanup.

**Steps (in order):**

1. `pkg_refresh` — update repo lists
2. `pkg_full_upgrade` — upgrade all installed packages to latest within current release
   - **Note:** `pkg_full_upgrade` for apt currently includes its own `sudo apt update` call. This should be removed from `pkg_full_upgrade` since the caller now handles refresh via `pkg_refresh`. This makes `pkg_full_upgrade` a pure upgrade operation across all package managers.
3. `pkg_cleanup_thorough` — enhanced shared cleanup

### 3. `pkg_check_upgrade_available()` — Upgrade Availability Check

**Location:** `lib/pkg_manager.sh`

**Returns:** 0 if upgrade available, 1 if not. Outputs target version/name to stdout.

**Dispatches on:** `$DISTRO_ID` (since upgrade paths are distro-specific, not just package-manager-specific).

**Per distro:**

- **Ubuntu (and derivatives shipping `update-manager-core`):**
  - Ensures `update-manager-core` is installed (provides `do-release-upgrade`); installs it if missing
  - Runs `do-release-upgrade -c` to check availability
  - Parses output for the target version name (e.g., "New release '24.04 LTS' available")
  - Returns 0 if upgrade found, 1 if not

- **Fedora:**
  - Attempts `dnf system-upgrade download --releasever=$((DISTRO_VERSION_ID + 1)) --downloadonly` with a dry-run/check approach
  - If exit code 0, an upgrade is available; outputs target version
  - If exit code non-zero, returns 1

- **openSUSE Leap:**
  - Queries `https://get.opensuse.org/leap/` or checks zypper product info for a newer Leap version
  - Compares current `DISTRO_VERSION_ID` against discovered version
  - Returns 0 if newer version exists, 1 if not

- **Rolling release (Arch, openSUSE Tumbleweed):**
  - Always returns 1 (no discrete version upgrades — `pkg_full_upgrade` is already "latest")
  - Tumbleweed distinguished from Leap by checking `DISTRO_ID` (`opensuse-tumbleweed` vs `opensuse-leap`)

- **RHEL / CentOS / Rocky / Alma:**
  - Always returns 1 (major version upgrades are managed externally via RHEL subscription tooling or manual migration; not appropriate for automated in-place upgrades)

- **Debian stable:**
  - Always returns 1 (Debian stable upgrades require manual `sources.list` editing, not `do-release-upgrade`)

### 4. `pkg_distro_upgrade()` — Distribution Version Upgrade

**Location:** `lib/pkg_manager.sh`

**Purpose:** Performs the actual version upgrade after user confirmation.

**Per distro:**

- **Ubuntu (and derivatives with `update-manager-core`):**
  - **LTS prompt:** If current version is LTS, ask the user: "You're on an LTS release. (1) Stay on LTS track, (2) Upgrade to latest release."
  - Temporarily sets `Prompt=lts` or `Prompt=normal` in `/etc/update-manager/release-upgrades`, restoring original value after upgrade
  - Runs `do-release-upgrade -f DistUpgradeViewNonInteractive`

- **Fedora:**
  - Runs `dnf system-upgrade download --releasever=<target>` to download packages
  - Does NOT run `dnf system-upgrade reboot` (which triggers an immediate reboot and would prevent cleanup from running)
  - Instead, informs the user: "Upgrade packages downloaded. A reboot is required to apply the upgrade."
  - Cleanup runs after download, then the existing post-execution reboot prompt handles the reboot

- **openSUSE Leap:**
  - Updates repo URLs to target version
  - Runs `zypper ref` then `zypper dup --allow-vendor-change`

- **Rolling release / RHEL / Debian stable:**
  - Never reached (guarded by `pkg_check_upgrade_available` returning 1)

**Error handling:** If the upgrade command exits non-zero, log the error via `error()`, inform the user the upgrade failed, and fall through to `pkg_full_upgrade` as a fallback (same as the "no upgrade available" path). Cleanup always runs regardless.

### 5. `setup_full_update()` — Full System Upgrade/Update

**Location:** `lib/installers.sh`

**Purpose:** Orchestrates the full upgrade flow. Renamed from `setup_full_update_bare_metal`.

**Steps (in order):**

1. `pkg_refresh` — update repo lists
2. `pkg_check_upgrade_available` — check if a distro version upgrade exists
3. **If upgrade available:**
   - Display confirmation prompt:
     ```
     ┌─────────────────────────────────────────────────────┐
     │  A distribution upgrade is available.               │
     │                                                     │
     │  Current: Ubuntu 22.04 LTS (Jammy Jellyfish)        │
     │  Target:  Ubuntu 24.04 LTS (Noble Numbat)           │
     │                                                     │
     │  This is a major operation and may take some time.   │
     │  Continue? (y/N)                                     │
     └─────────────────────────────────────────────────────┘
     ```
   - If confirmed: `pkg_distro_upgrade`
   - If declined: info message that upgrade was skipped, proceed to step 4
4. **If no upgrade available (or declined/rolling release/upgrade failed):**
   - Info message: "No version upgrade available (or skipped), performing package updates"
   - `pkg_full_upgrade` — standard package update
5. `pkg_cleanup_thorough` — shared cleanup

**Key behavior:** Always does something useful. Whether the user gets a version upgrade, declines, or the upgrade fails, package updates and cleanup always run at the end.

### 6. Registration & Naming

**Updated `register_utility` calls in `lib/installers.sh`:**

```bash
register_utility "Full System Upgrade/Update" setup_full_update check_always_false noop_function setup_full_update
register_utility "System Updates" setup_system_updates check_always_false noop_function setup_system_updates
```

Update the comment on line 69 of `linux_util.sh` to remove "bare metal" wording. The `SYSTEM_TASK_COUNT` remains unchanged (still 5 system tasks).

### 7. `pkg_full_upgrade()` Refactor

**Location:** `lib/pkg_manager.sh`

Remove the internal `sudo apt update &&` from the `apt` case in `pkg_full_upgrade()`. Since callers now explicitly call `pkg_refresh` before `pkg_full_upgrade`, the embedded refresh is redundant and causes a double repo update on Debian-family systems.

**Before:** `apt) sudo apt update && sudo apt full-upgrade -y ;;`
**After:** `apt) sudo apt full-upgrade -y ;;`

## Distro Support Matrix

| Distro | Version Upgrade Method | Cleanup: Old Kernels | Cleanup: Purge Configs |
|---|---|---|---|
| Ubuntu (+ derivatives with update-manager-core) | `do-release-upgrade` | `apt-get purge` old linux-image/headers | `dpkg --purge` rc packages |
| Debian stable | N/A (manual sources.list) | `apt-get purge` old linux-image/headers | `dpkg --purge` rc packages |
| Fedora | `dnf system-upgrade download` | `dnf remove --oldinstallonly` | N/A |
| openSUSE Leap | `zypper dup` with updated repos | `zypper purge-kernels` | N/A |
| Arch / openSUSE Tumbleweed (rolling) | N/A (always latest) | N/A | N/A |
| RHEL / CentOS / Rocky / Alma | N/A (managed externally) | `dnf remove --oldinstallonly` | N/A |

## Behavior Summary

| | System Updates | Full System Upgrade/Update |
|---|---|---|
| Refresh repos | Yes | Yes |
| Package updates | Yes | Only if no version upgrade or user declines |
| Distro version upgrade | No | Yes (if available, with confirmation) |
| LTS awareness | N/A | Yes — asks user to stay LTS or go latest (Ubuntu only) |
| Old kernel removal | Yes | Yes |
| Purge removed configs | Yes | Yes |
| Clean cache/lists | Yes | Yes |
| Autoremove | Yes | Yes |

## Files Modified

- `lib/pkg_manager.sh` — add `pkg_cleanup_thorough`, `pkg_check_upgrade_available`, `pkg_distro_upgrade`; refactor `pkg_full_upgrade` to remove embedded apt update
- `lib/installers.sh` — rewrite `setup_full_update` (renamed from `setup_full_update_bare_metal`), rewrite `setup_system_updates`, update `register_utility` calls
- `linux_util.sh` — update comment removing "bare metal" reference

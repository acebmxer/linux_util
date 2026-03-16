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
- LTS-awareness prompting for Ubuntu/Debian family
- Pre-upgrade confirmation with current/target version display

## Design

### 1. `pkg_cleanup_thorough()` — Shared Cleanup

**Location:** `lib/pkg_manager.sh` (alongside existing `pkg_*` functions)

**Called by:** Both `setup_system_updates` and `setup_full_update`

**Steps (in order):**

1. **`pkg_autoremove`** — remove orphaned dependencies
2. **Remove old kernels** (keep current + one previous):
   - `apt`: `apt-get purge` old `linux-image-*` and `linux-headers-*` packages
   - `dnf/yum`: `dnf remove --oldinstallonly --setopt installonly_limit=2`
   - `pacman`: skip (Arch does not accumulate old kernels the same way)
   - `zypper`: `zypper purge-kernels --keep 2`
3. **Purge removed package configs** (Debian family only): `dpkg --purge $(dpkg -l | awk '/^rc/ {print $2}')`
4. **`pkg_clean`** — clean package cache
5. **Clean apt lists** (Debian family only): remove `/var/lib/apt/lists/*` partial files

### 2. `setup_system_updates()` — System Updates

**Location:** `lib/installers.sh`

**Purpose:** Safe, no-version-change package updates with thorough cleanup.

**Steps (in order):**

1. `pkg_refresh` — update repo lists
2. `pkg_full_upgrade` — upgrade all installed packages to latest within current release
3. `pkg_cleanup_thorough` — enhanced shared cleanup

### 3. `pkg_check_upgrade_available()` — Upgrade Availability Check

**Location:** `lib/pkg_manager.sh`

**Returns:** 0 if upgrade available, 1 if not. Outputs target version/name to stdout.

**Per distro family:**

- **Debian (Ubuntu/Mint/Pop/etc.):**
  - Ensures `update-manager-core` is installed (provides `do-release-upgrade`)
  - Runs `do-release-upgrade -c` to check availability
  - Parses output for the target version name

- **Fedora:**
  - Checks if a newer `fedora-release` version is available
  - Compares current `DISTRO_VERSION_ID` against latest available

- **openSUSE Leap:**
  - Checks if a newer Leap version exists via `zypper` repo metadata

- **Rolling release (Arch, Tumbleweed):**
  - Always returns 1 (no discrete version upgrades)

### 4. `pkg_distro_upgrade()` — Distribution Version Upgrade

**Location:** `lib/pkg_manager.sh`

**Purpose:** Performs the actual version upgrade after user confirmation.

**Per distro family:**

- **Debian (Ubuntu/Mint/Pop/etc.):**
  - **LTS prompt:** If current version is LTS, ask the user: "You're on an LTS release. (1) Stay on LTS track, (2) Upgrade to latest release."
  - Temporarily sets `Prompt=lts` or `Prompt=normal` in `/etc/update-manager/release-upgrades`, restoring original value after upgrade
  - Runs `do-release-upgrade -f DistUpgradeViewNonInteractive`

- **Fedora:**
  - Runs `dnf system-upgrade download --releasever=<target>`
  - Then `dnf system-upgrade reboot`
  - Informs user that reboot is required (handled by existing post-execution reboot prompt)

- **openSUSE Leap:**
  - Updates repo URLs to target version
  - Runs `zypper ref` then `zypper dup`

- **Rolling release (Arch, Tumbleweed):**
  - Never reached (guarded by `pkg_check_upgrade_available` returning 1)

### 5. `setup_full_update()` — Full System Upgrade/Update

**Location:** `lib/installers.sh`

**Purpose:** Orchestrates the full upgrade flow. Renamed from `setup_full_update_bare_metal`.

**Steps (in order):**

1. `pkg_refresh` — update repo lists
2. `pkg_check_upgrade_available` — check if a distro version upgrade exists
3. **If upgrade available:**
   - Display warning: current version, target version, distro name
   - Ask user to confirm (y/N) — defaults to No
   - If confirmed: `pkg_distro_upgrade`
   - If declined: info message that upgrade was skipped, proceed to step 4
4. **If no upgrade available (or declined/rolling release):**
   - Info message: "No version upgrade available, performing package updates"
   - `pkg_full_upgrade` — standard package update
5. `pkg_cleanup_thorough` — shared cleanup

**Key behavior:** Always does something useful. Whether the user gets a version upgrade or falls back to package updates, cleanup always runs at the end.

### 6. Registration & Naming

**Updated `register_utility` calls in `lib/installers.sh`:**

```bash
register_utility "Full System Upgrade/Update" setup_full_update check_always_false noop_function setup_full_update
register_utility "System Updates" setup_system_updates check_always_false noop_function setup_system_updates
```

Update the comment on line 69 of `linux_util.sh` to remove "bare metal" wording.

## Distro Support Matrix

| Distro Family | Version Upgrade Method | Cleanup: Old Kernels | Cleanup: Purge Configs |
|---|---|---|---|
| Debian (Ubuntu, Mint, Pop, etc.) | `do-release-upgrade` | `apt-get purge` old linux-image/headers | `dpkg --purge` rc packages |
| Fedora | `dnf system-upgrade` | `dnf remove --oldinstallonly` | N/A |
| openSUSE Leap | `zypper dup` with updated repos | `zypper purge-kernels` | N/A |
| Arch / Tumbleweed (rolling) | N/A (always latest) | N/A | N/A |
| RHEL / CentOS / Rocky / Alma | N/A (managed differently) | `dnf remove --oldinstallonly` | N/A |

## Behavior Summary

| | System Updates | Full System Upgrade/Update |
|---|---|---|
| Refresh repos | Yes | Yes |
| Package updates | Yes | Only if no version upgrade or user declines |
| Distro version upgrade | No | Yes (if available, with confirmation) |
| LTS awareness | N/A | Yes — asks user to stay LTS or go latest |
| Old kernel removal | Yes | Yes |
| Purge removed configs | Yes | Yes |
| Clean cache/lists | Yes | Yes |
| Autoremove | Yes | Yes |

## Files Modified

- `lib/pkg_manager.sh` — add `pkg_cleanup_thorough`, `pkg_check_upgrade_available`, `pkg_distro_upgrade`
- `lib/installers.sh` — rewrite `setup_full_update` (renamed), rewrite `setup_system_updates`, update `register_utility` calls
- `linux_util.sh` — update comment removing "bare metal" reference

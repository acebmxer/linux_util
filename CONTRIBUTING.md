# Contributing to linux_util

Thank you for taking the time to contribute! This document explains how the codebase is structured, how to add a new installer, and what to expect from code review.

---

## Table of Contents

1. [Project layout](#project-layout)
2. [Adding a new utility installer](#adding-a-new-utility-installer)
3. [Helper function reference](#helper-function-reference)
4. [Code style](#code-style)
5. [Running the tests](#running-the-tests)
6. [Writing tests](#writing-tests)
7. [Submitting a pull request](#submitting-a-pull-request)

---

## Project layout

```
linux_util.sh              # Entry point — parses CLI args, sets up env, launches TUI
lib/
  config.sh                # Config loading and defaults
  logging.sh               # log_info / log_error / log_success / metrics_*
  pkg_manager.sh           # Distro detection, pkg_install, pkg_remove helpers
  installers.sh            # Registers all utilities; sources lib/installers/*.sh
  installers/              # One file per utility (brave.sh, docker.sh, …)
  menu.sh                  # TUI rendering
  profiles.sh              # Install profiles (Run Me First, Developer Workstation, …)
  snapshot.sh              # Timeshift / Snapper integration
  system.sh                # Health checks, dependency resolution
  utilities.sh             # register_utility / register_system_task
  verify.sh                # Download integrity helpers
completions/               # Shell tab-completion scripts
tests/
  test_linux_util.sh       # Unit + integration test suite
```

### Which module to edit

| Module | Purpose | Edit when... |
|--------|---------|--------------|
| `linux_util.sh` | Main script, CLI argument parsing, initialization | Changing argument parsing or main flow |
| `lib/config.sh` | Configuration file parsing, verbose/debug output helpers | Adding new config options |
| `lib/logging.sh` | Logging functions, error handling, cleanup | Changing log format or adding log functions |
| `lib/pkg_manager.sh` | Package manager abstraction, distro detection | Adding new distros or package managers |
| `lib/aur.sh` | AUR/pacman-specific functions | Modifying AUR installation logic |
| `lib/system.sh` | Pre-flight checks, logrotate setup, system helpers | Adding pre-flight checks |
| `lib/snapshot.sh` | Automatic snapshots via Timeshift or Snapper | Adding snapshot backends |
| `lib/menu.sh` | TUI rendering, keyboard navigation, categories | Changing menu appearance or navigation |
| `lib/profiles.sh` | Curated selection presets | Adding, removing, or customizing a profile |
| `lib/utilities.sh` | Utility registry, name resolution, health checks | Modifying how utilities are registered |
| `lib/verify.sh` | Download integrity helpers | Changing how downloaded files are validated |
| `lib/installers.sh` | Sources `lib/installers/*.sh`, registers all entries | **Adding a registration line for a new utility** |
| `lib/installers/*.sh` | Per-utility install/uninstall/update/check functions | **Adding or modifying a specific utility** |

---

## Adding a new utility installer

Follow the four-step checklist; every existing installer in `lib/installers/` is a working example.

### Step 1 — Create the installer file

Create `lib/installers/<slug>.sh` (all lowercase, underscores for spaces):

```bash
#!/bin/bash
# <Utility Name> installer functions

# --- <Utility Name> ---

check_<slug>() {
    command -v <binary> &>/dev/null
}

install_<slug>() {
    info "Installing <Utility Name>..."
    ensure_tools          # ensures curl/wget are available
    case "$DISTRO_FAMILY" in
        debian)
            # apt-based install
            ;;
        fedora|rhel)
            # dnf/yum-based install
            ;;
        arch)
            # Always repo_or_aur, never aur_ensure: it tries pacman first and
            # only falls back to the AUR when the package is absent from the
            # configured repos. Derivatives such as CachyOS ship many AUR-named
            # packages (brave-bin, google-chrome, ...) in their own repos.
            repo_or_aur <package>
            ;;
        suse)
            sudo zypper install -y <package>
            ;;
        *)
            warn "<Utility Name> installation not implemented for ${DISTRO_NAME}."
            warn "Supported distros: Debian/Ubuntu, Fedora/RHEL, Arch/Manjaro, openSUSE."
            return 1
            ;;
    esac
}

uninstall_<slug>() {
    info "Uninstalling <Utility Name>..."
    case "$PKG_MGR" in
        apt)    sudo apt-get purge --autoremove -y <package> ;;
        dnf|yum) sudo "$PKG_MGR" remove -y <package> ;;
        pacman) sudo pacman -Rs --noconfirm <package> ;;
        zypper) sudo zypper remove -y <package> ;;
    esac
    # Remove any leftover config/cache dirs
    rm -rf ~/.config/<slug>
}

update_<slug>() {
    info "Updating <Utility Name>..."
    pkg_upgrade <package>    # or repeat the install steps
}

# Optional — omit if there is no reliable way to get the version
get_version_<slug>() {
    <binary> --version 2>/dev/null | grep -oP '[0-9]+\.[0-9]+(\.[0-9]+)?'
}
```

**Rules:**
- Use `info`/`warn`/`error` (from `lib/logging.sh`) for user-visible messages — not bare `echo` for status lines.
- Always handle all four distro families (`debian`, `fedora|rhel`, `arch`, `suse`). Add a `*)` fallback with a helpful message.
- When downloading a binary directly (not via a package manager), call `verify_download` or `_verify_not_empty_or_html` from `lib/verify.sh` before installing.
- Clean up temp files and package manager caches where appropriate (`apt autoclean`, `sudo pacman -Sc --noconfirm`).

### Step 2 — Register the utility

Open `lib/installers.sh` and add a `register_utility` line in the `--- Utilities ---` section, maintaining **alphabetical order**:

```bash
register_utility "My Utility" \
    install_my_utility  check_my_utility  uninstall_my_utility \
    update_my_utility   get_version_my_utility
```

Use `register_system_task` instead if the item is a system-level task (drivers, firewall, etc.) that should appear under System Tasks in the menu.

Then assign it a category in the category section further down the same file, so
the menu knows which tab to show it under:

```bash
UTILITY_CATEGORY["My Utility"]="Development"
```

Use one of the existing category names — `Backup`, `Bootloaders`, `Desktop
Environments`, `Development`, `Disk Utilities`, `Drivers`, `File Managers`,
`Firewalls`, `Gaming`, `Internet`, `Login Screens`, `Package Managers`,
`Productivity`, `Remote Admin Tools`, `System Tools`, `Window Managers` — unless
you are deliberately adding a new one.

### Step 3 — Add it to shell completions (optional but appreciated)

Add the display name to both `completions/linux_util.bash` (the `_linux_util_utilities` function) and `completions/_linux_util` (the `_linux_util_utilities` array) in alphabetical order.

### Step 4 — Update profiles if relevant

If the utility is a natural fit for the Developer Workstation or Home Desktop profile, add it to the appropriate `_profile_custom_*` function in `lib/profiles.sh`.

---

## Helper function reference

These are available to every installer. Prefer them over raw package manager
commands — they handle distro differences, retries, and dry-run mode for you.

| Function | Description |
|----------|-------------|
| `pkg_install <pkg>` | Install a package |
| `pkg_remove <pkg>` | Remove a package |
| `pkg_upgrade <pkg>` | Upgrade a package |
| `pkg_check_installed <pkg>` | Returns 0 if installed |
| `pkg_install_local <file>` | Install from a local `.deb`/`.rpm` |
| `pkg_refresh` | Refresh package lists |
| `pkg_full_upgrade` | Full system upgrade |
| `pkg_autoremove` | Remove orphaned packages |
| `pkg_clean` | Clean package cache |
| `has_snap` / `has_flatpak` / `has_aur_helper` | Availability checks |
| `aur_install <pkg>` | Install from AUR |
| `repo_or_aur <pkg>` | Install from the official Arch repos, falling back to the AUR |
| `flatpak_or_aur <flathub-id> <pkg>` | Install from Flathub when Flatpak is set up, else the AUR |
| `ensure_tools` | Ensure curl/wget/gpg are present |
| `check_internet` | Connectivity check (warns, does not abort) |
| `download_file <url> <dest> [retries]` | Retry-aware downloader |

Use `$DISTRO_FAMILY` (`debian`, `fedora`, `rhel`, `arch`, `suse`) for
distro-specific logic, and `$PKG_MGR` (`apt`, `dnf`, `yum`, `pacman`, `zypper`)
where the command itself differs.

---

## Code style

- **Shell**: bash 4.0+. Always include `#!/bin/bash` at the top of every file.
- **Indentation**: 4 spaces (no tabs).
- **Variables**: local variables use `snake_case`. Constants use `UPPER_SNAKE_CASE`.
- **Quoting**: always quote variable expansions (`"$var"`, `"${array[@]}"`).
- **Conditionals**: use `[[ ]]` rather than `[ ]`.
- **Command substitution**: use `$()` rather than backticks.
- **Error handling**: prefer early `return 1` over deeply nested `if/else` blocks.
- **ShellCheck**: all scripts must pass `shellcheck` with no errors or warnings. The CI pipeline enforces this automatically.
- **Header comment**: new installer files should start with a `# --- <Utility Name> ---` section separator comment.

---

## Running the tests

```bash
bash tests/test_linux_util.sh
```

All tests must pass (`0 failed`) before opening a PR. The CI workflow runs the same command on every push and pull request.

To also run ShellCheck locally (optional but recommended):

```bash
shellcheck -x linux_util.sh lib/**/*.sh lib/installers/*.sh tests/test_linux_util.sh
```

---

## Writing tests

Tests live in `tests/test_linux_util.sh`. The file uses a lightweight hand-rolled test framework:

| Helper | Purpose |
|--------|---------|
| `_pass "message"` | Record a passing assertion |
| `_fail "message"` | Record a failing assertion |
| `_skip "message"` | Record a skipped test |
| `assert_eq expected actual "message"` | Equality assertion |
| `assert_not_empty value "message"` | Non-empty assertion |
| `assert_contains haystack needle "message"` | Substring assertion |
| `assert_file_exists path "message"` | File existence assertion |

Group related tests under a `=== My Section ===` banner printed with `echo`.

When adding a new utility, consider adding tests for at minimum:
- `check_<slug>` returns the expected value in a mock environment
- `install_<slug>` in `--dry-run` mode exits 0

---

## Submitting a pull request

1. Fork the repository and create a branch from `main`.
2. Make your changes following the guidelines above.
3. Ensure `bash tests/test_linux_util.sh` exits 0.
4. Open a pull request using the PR template and fill in every section.
5. Be responsive to review feedback — the maintainer aims to review PRs within a week.

For larger changes (new feature, new profile, refactor) it is worth opening an issue first to discuss the approach before investing significant time in implementation.

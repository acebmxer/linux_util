#!/bin/bash

# ============================================================================
# Linux Utilities Installer & System Setup
# Interactive multi-select installer combining system setup and utility management
# Compatible with: Debian/Ubuntu, Fedora/RHEL/CentOS, Arch/Manjaro, openSUSE
# ============================================================================

# Prevent running as root
if [[ $EUID -eq 0 ]]; then
    echo "Error: This script should NOT be run as root."
    echo "Please run as a regular user. sudo will be used when needed."
    exit 1
fi

# Require Bash 4.0+ (associative arrays, mapfile, etc.)
if (( BASH_VERSINFO[0] < 4 )); then
    echo "Error: Bash 4.0 or newer is required (running: ${BASH_VERSION})."
    exit 1
fi

# Catch pipeline failures (e.g. cmd | grep where cmd fails)
set -o pipefail

# Dry-run flag — set to true via --dry-run CLI argument
DRY_RUN=false

# No-color flag — set to true via --no-color CLI argument
NO_COLOR_FLAG=false

# Preserve original CLI arguments for self-update re-exec
ORIGINAL_ARGS=("$@")

# Prevent concurrent runs via flock
LOCK_FILE="/tmp/linux_util_${USER:-$UID}.lock"
exec 9>"$LOCK_FILE"
if ! flock -n 9; then
    echo "Error: Another instance of this script is already running."
    exit 1
fi

# ============================================================================
# LOGGING SETUP
# ============================================================================

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_PATH="${SCRIPT_DIR}/$(basename "${BASH_SOURCE[0]}")"
LOG_DIR="${SCRIPT_DIR}/logs"

# Restrict log file permissions (owner-only read/write)
ORIG_UMASK=$(umask)
umask 077

# Create log directory if it doesn't exist
mkdir -p "$LOG_DIR"

# Log file names with timestamp
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
SUCCESS_LOG="${LOG_DIR}/success_${TIMESTAMP}.log"
ERROR_LOG="${LOG_DIR}/error_${TIMESTAMP}.log"

# Also maintain latest logs (symlinks or copies)
LATEST_SUCCESS_LOG="${LOG_DIR}/success_latest.log"
LATEST_ERROR_LOG="${LOG_DIR}/error_latest.log"

# Config file that persists the NVIDIA driver version chosen at install time
# (used by other installers, e.g. Steam, to install matching 32-bit libraries)
NVIDIA_VERSION_FILE="${HOME}/.config/linux_util/nvidia_driver_version"

# SYSTEM_TASKS array is declared in utilities.sh and populated by register_system_task
# calls in installers.sh. The count is derived as ${#SYSTEM_TASKS[@]}.

# Track if any errors have occurred
ERROR_LOG_INITIALIZED=false

# Initialize success log only
{
    echo "════════════════════════════════════════════════════════════════"
    echo "Linux Utilities Installer - Execution Log"
    echo "Started: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "User: $USER"
    echo "Hostname: $(hostname)"
    echo "════════════════════════════════════════════════════════════════"
    echo ""
} > "$SUCCESS_LOG"

# Create/update latest success log symlink
ln -sf "$(basename "$SUCCESS_LOG")" "$LATEST_SUCCESS_LOG" 2>/dev/null || cp "$SUCCESS_LOG" "$LATEST_SUCCESS_LOG"

# Restore original umask so installers create files with normal permissions
umask "$ORIG_UMASK"

# Lock down constants that should not be modified after initialization
readonly SCRIPT_DIR SCRIPT_PATH LOG_DIR TIMESTAMP SUCCESS_LOG ERROR_LOG
readonly LATEST_SUCCESS_LOG LATEST_ERROR_LOG LOCK_FILE NVIDIA_VERSION_FILE

# ============================================================================
# SOURCE LIBRARY MODULES
# ============================================================================

# Source config module first (provides debug/verbose helpers used by all modules)
source "${SCRIPT_DIR}/lib/config.sh" || { echo "Error: Failed to source config.sh"; exit 1; }

# Load user configuration (overrides defaults set in config.sh)
load_config

# Source remaining library modules in dependency order
source "${SCRIPT_DIR}/lib/logging.sh" || { echo "Error: Failed to source logging.sh"; exit 1; }
source "${SCRIPT_DIR}/lib/pkg_manager.sh" || { echo "Error: Failed to source pkg_manager.sh"; exit 1; }

# Initialize performance metrics tracking
metrics_init

# Prune log files according to retention policy (age + count limits from config)
prune_logs

# ============================================================================
# SYSTEM INITIALIZATION
# ============================================================================

# Detect the distro at startup (MUST be before sourcing installers.sh for conditional registrations)
detect_distro
echo ""

# Continue sourcing remaining library modules
source "${SCRIPT_DIR}/lib/aur.sh" || { echo "Error: Failed to source aur.sh"; exit 1; }
source "${SCRIPT_DIR}/lib/system.sh" || { echo "Error: Failed to source system.sh"; exit 1; }
source "${SCRIPT_DIR}/lib/snapshot.sh" || { echo "Error: Failed to source snapshot.sh"; exit 1; }
source "${SCRIPT_DIR}/lib/utilities.sh" || { echo "Error: Failed to source utilities.sh"; exit 1; }
source "${SCRIPT_DIR}/lib/menu.sh" || { echo "Error: Failed to source menu.sh"; exit 1; }
source "${SCRIPT_DIR}/lib/installers.sh" || { echo "Error: Failed to source installers.sh"; exit 1; }

# Initialize dependency map and health checks (must be after installers.sh registers utilities)
_init_deps_map
_init_health_checks

# Load profiles module — must come after installers.sh so all utility names
# are registered before the profile registration calls in profiles.sh run.
# Profiles reference utility names by exact string; unregistered names are
# silently skipped by the apply_profile() helper functions at runtime.
source "${SCRIPT_DIR}/lib/profiles.sh" || { echo "Error: Failed to source profiles.sh"; exit 1; }

# Setup traps for cleanup and error handling
trap cleanup_on_exit EXIT
trap 'echo ""; echo "Interrupted."; exit 130' INT TERM

# Clean up any orphaned sudo keep-alive from a previous killed run
SUDO_PID_FILE="${LOCK_FILE}.pid"
readonly SUDO_PID_FILE
if [[ -f "$SUDO_PID_FILE" ]]; then
    _orphan_pid=$(<"$SUDO_PID_FILE")
    if [[ -n "$_orphan_pid" ]] && kill -0 "$_orphan_pid" 2>/dev/null; then
        kill "$_orphan_pid" 2>/dev/null || true
    fi
    rm -f "$SUDO_PID_FILE"
fi

# Cache sudo credentials and keep them alive in the background so the user
# is not re-prompted mid-install when the sudo timeout expires.
sudo -v
( exec 9>&-; while true; do sudo -n true; sleep 50; done ) 2>/dev/null &
SUDO_KEEPALIVE_PID=$!
echo "$SUDO_KEEPALIVE_PID" > "$SUDO_PID_FILE"

# Initialize Timeshift integration (Debian/Ubuntu only — silent no-op otherwise)
timeshift_init

# ============================================================================
# UTILITY REGISTRY INITIALIZATION
# ============================================================================

# Initialize arrays for tracking utility state
declare -a SELECTED INSTALLED UPDATE_SELECTED INSTALLED_VERSIONS
for ((i=0; i<${#UTILITIES[@]}; i++)); do
    SELECTED[$i]=0
    INSTALLED[$i]=0
    UPDATE_SELECTED[$i]=0
    INSTALLED_VERSIONS[$i]=""
done

# Current cursor position
CURSOR=0

# Cached commit info (fetched in run_selection_menu)
CACHED_LOCAL_COMMIT="unknown"
CACHED_REMOTE_COMMIT="unknown"
CACHED_LOCAL_BRANCH="unknown"

# ============================================================================
# PROCESS SELECTED UTILITIES & SYSTEM TASKS
# ============================================================================

process_selected() {
    local total=${#UTILITIES[@]}
    local system_tasks=${#SYSTEM_TASKS[@]}
    declare -a to_install
    declare -a to_uninstall
    declare -a to_update
    local needs_reboot=false
    local needs_shell_reload=false

    # These tasks do not require a reboot after successful completion
    local -A NO_REBOOT=(["Create Snapshot"]=1 ["Local Time Zone / Locale"]=1)

    # Categorize utilities based on selection and installed state
    for ((i=0; i<total; i++)); do
        local util="${UTILITIES[$i]}"
        if [[ ${UPDATE_SELECTED[$i]} -eq 1 ]]; then
            to_update+=("$util")
        elif [[ ${SELECTED[$i]} -eq 1 ]]; then
            if [[ ${INSTALLED[$i]} -eq 1 ]]; then
                to_uninstall+=("$util")
            else
                to_install+=("$util")
            fi
        fi

    done

    # Check if there's anything to do
    if [[ ${#to_install[@]} -eq 0 ]] && [[ ${#to_uninstall[@]} -eq 0 ]] && [[ ${#to_update[@]} -eq 0 ]]; then
        echo ""
        echo "${YELLOW}No changes to make.${RESET}"
        read -rp "Press ENTER to return to menu..." < /dev/tty
        return 0
    fi

    echo ""
    echo "${BOLD}${CYAN}════════════════════════════════════════════════════════════════${RESET}"
    echo "${BOLD}${CYAN}                    Summary of Actions                         ${RESET}"
    echo "${BOLD}${CYAN}════════════════════════════════════════════════════════════════${RESET}"
    echo ""

    if [[ ${#to_install[@]} -gt 0 ]]; then
        echo "${GREEN}To Install/Run (${#to_install[@]}):${RESET}"
        for util in "${to_install[@]}"; do
            echo "  ${GREEN}+${RESET} $util"
        done
        echo ""
    fi

    if [[ ${#to_uninstall[@]} -gt 0 ]]; then
        echo "${RED}To Uninstall (${#to_uninstall[@]}):${RESET}"
        for util in "${to_uninstall[@]}"; do
            echo "  ${RED}-${RESET} $util"
        done
        echo ""
    fi

    if [[ ${#to_update[@]} -gt 0 ]]; then
        echo "${YELLOW}To Update (${#to_update[@]}):${RESET}"
        for util in "${to_update[@]}"; do
            echo "  ${YELLOW}↑${RESET} $util"
        done
        echo ""
    fi

    read -rp "Press ENTER to continue or Ctrl+C to cancel..." < /dev/tty
    clear

    if [[ "$DRY_RUN" == "true" ]]; then
        echo "${YELLOW}[DRY RUN] No changes made.${RESET}"
        read -rp "Press ENTER to return to menu..." < /dev/tty
        return 0
    fi

    # Create a Timeshift snapshot before making any changes.
    # Skip if the user explicitly selected Create Snapshot or Restore Snapshot
    # (those tasks manage their own snapshots — avoids creating duplicates).
    local _skip_auto_snapshot=false
    for _chk in "${to_install[@]}"; do
        [[ "$_chk" == "Create Snapshot" || "$_chk" == "Restore Snapshot" ]] && _skip_auto_snapshot=true
    done

    if [[ "$TIMESHIFT_AVAILABLE" == "true" && "$_skip_auto_snapshot" == "false" ]]; then
        local _ts_comment="linux_util:"

        # Separate "run" tasks from "install" tasks based on uninstall function.
        # System tasks with noop_function as uninstall are "run" (e.g. System Updates);
        # everything else is "install" (regular utilities + system tasks like KDE, NVIDIA).
        if [[ ${#to_install[@]} -gt 0 ]]; then
            local _run_items=() _install_items=()
            for _item in "${to_install[@]}"; do
                if [[ "${UNINSTALL_FUNCS[$_item]:-}" == "noop_function" ]]; then
                    _run_items+=("$_item")
                else
                    _install_items+=("$_item")
                fi
            done
            [[ ${#_run_items[@]} -gt 0 ]] && _ts_comment+=" Before running ${_run_items[*]},"
            [[ ${#_install_items[@]} -gt 0 ]] && _ts_comment+=" Before installing ${_install_items[*]},"
        fi

        [[ ${#to_uninstall[@]} -gt 0 ]] && _ts_comment+=" Before uninstalling ${to_uninstall[*]},"
        [[ ${#to_update[@]} -gt 0 ]] && _ts_comment+=" Before updating ${to_update[*]},"
        _ts_comment="${_ts_comment%,}"  # Remove trailing comma
        timeshift_create_snapshot "$_ts_comment"
    fi

    # Run pre-flight checks before proceeding
    if ! preflight_checks; then
        read -n 1 -rp "Pre-flight checks failed. Continue anyway? (y/N) " _pf_ans < /dev/tty
        echo
        if [[ ! "$_pf_ans" =~ ^[Yy]$ ]]; then
            echo "${YELLOW}Aborted.${RESET}"
            read -rp "Press ENTER to return to menu..." < /dev/tty
            return 0
        fi
    fi

    # Update package lists first
    echo "${CYAN}Updating package lists...${RESET}"
    pkg_refresh
    echo ""

    # Track results
    local success_count=0
    local fail_count=0
    declare -a failed_utils

    # --- Helper: run a single operation (install/uninstall/update) ---
    _run_operation() {
        local op_type="$1"   # install, uninstall, update
        local util="$2"
        local func="$3"
        local color="$4"
        local label="$5"

        # Use friendlier verbs for system tasks (they are "run", not "installed")
        local _is_system_task=false
        for _st in "${SYSTEM_TASKS[@]}"; do
            [[ "$_st" == "$util" ]] && _is_system_task=true && break
        done
        local _verb="$op_type" _past
        if [[ "$op_type" == *e ]]; then
            _past="${op_type}d"
        else
            _past="${op_type}ed"
        fi
        if [[ "$_is_system_task" == "true" && "$op_type" == "install" ]]; then
            _verb="run"
            _past="completed"
        fi

        echo ""
        echo "${BOLD}${color}────────────────────────────────────────────────────────────────${RESET}"
        echo "${DIM}[$(date '+%H:%M:%S')]${RESET} ${BOLD}${color}${label}: $util${RESET}"
        echo "${BOLD}${color}────────────────────────────────────────────────────────────────${RESET}"
        echo ""

        log_info "Starting ${_verb}: $util"

        # Resolve dependencies before install/update
        if [[ "$op_type" == "install" || "$op_type" == "update" ]]; then
            resolve_dependencies "$util" || verbose "Dependency resolution skipped for ${util}"
        fi

        local _op_start=$SECONDS

        if [[ -n "$func" ]] && declare -f "$func" > /dev/null; then
            # Capture stderr to temp file while still displaying on terminal
            local _stderr_tmp
            _stderr_tmp=$(mktemp)
            CLEANUP_FILES+=("$_stderr_tmp")

            local _exit_code=0
            $func 2> >(tee -a "$_stderr_tmp" >&2) || _exit_code=$?
            if [[ $_exit_code -eq 2 ]]; then
                local _duration=$(( SECONDS - _op_start ))
                echo ""
                echo "${YELLOW}⊘ Cancelled: $util${RESET} ${DIM}(${_duration}s)${RESET}"
                log_info "Cancelled by user: $util"
                rm -f "$_stderr_tmp"
            elif [[ $_exit_code -eq 0 || $_exit_code -eq 3 ]]; then
                local _duration=$(( SECONDS - _op_start ))
                echo ""
                echo "${GREEN}✓ Successfully ${_past}: $util${RESET} ${DIM}(${_duration}s)${RESET}"
                log_success "${label}: $util"
                metrics_record "$_verb" "$util" "$_duration" "success"

                # Run health check after install/update
                if [[ "$op_type" == "install" || "$op_type" == "update" ]]; then
                    health_check "$util" || true
                fi

                (( success_count += 1 ))

                # Reboot required for system tasks (except no-reboot list) and Docker
                # Exit code 3 = success with no changes — skip reboot prompt
                if [[ $_exit_code -ne 3 && -z "${NO_REBOOT[$util]:-}" ]]; then
                    if [[ "$_is_system_task" == "true" || "$util" == "Docker" ]]; then
                        needs_reboot=true
                    fi
                fi

                # Do not switch shells during batch/profile runs; defer to end-of-run notice.
                if [[ "$util" == "Zsh + Oh My Zsh" && ( "$op_type" == "install" || "$op_type" == "update" ) ]]; then
                    needs_shell_reload=true
                fi
                rm -f "$_stderr_tmp"
            else
                local _duration=$(( SECONDS - _op_start ))
                echo ""
                echo "${RED}✗ Failed to ${_verb}: $util${RESET} ${DIM}(${_duration}s)${RESET}"
                log_error "Failed to ${_verb}: $util"
                metrics_record "$_verb" "$util" "$_duration" "failed"

                # Append captured command stderr to error log
                if [[ -s "$_stderr_tmp" ]]; then
                    init_error_log
                    {
                        echo "[COMMAND OUTPUT for ${util}]"
                        cat "$_stderr_tmp"
                        echo ""
                    } >> "$ERROR_LOG"
                fi

                # Retry logic
                if [[ "$CFG_RETRY_FAILED" == "true" && "$op_type" != "uninstall" && -z "${NO_RETRY[$util]:-}" ]]; then
                    local _attempt=1
                    while (( _attempt < CFG_RETRY_ATTEMPTS )); do
                        (( _attempt += 1 ))
                        log_warning "Retrying ${_verb} for ${util} (attempt ${_attempt}/${CFG_RETRY_ATTEMPTS})"
                        echo "${YELLOW}Retrying ${_verb} for ${util} (attempt ${_attempt}/${CFG_RETRY_ATTEMPTS})...${RESET}"
                        > "$_stderr_tmp"  # Reset capture for retry
                        local _retry_start=$SECONDS
                        if $func 2> >(tee -a "$_stderr_tmp" >&2); then
                            local _retry_dur=$(( SECONDS - _retry_start ))
                            echo "${GREEN}✓ Retry succeeded: $util${RESET} ${DIM}(${_retry_dur}s)${RESET}"
                            log_success "Retry ${_verb} succeeded: $util (attempt ${_attempt})"
                            metrics_record "${_verb}_retry" "$util" "$_retry_dur" "success"
                            (( success_count += 1 ))
                            if [[ "$op_type" == "install" || "$op_type" == "update" ]]; then
                                health_check "$util" || true
                            fi
                            rm -f "$_stderr_tmp"
                            return 0
                        else
                            log_error "Retry ${_attempt}/${CFG_RETRY_ATTEMPTS} failed for ${util}"
                            # Append retry stderr to error log
                            if [[ -s "$_stderr_tmp" ]]; then
                                init_error_log
                                {
                                    echo "[COMMAND OUTPUT for ${util} - retry ${_attempt}/${CFG_RETRY_ATTEMPTS}]"
                                    cat "$_stderr_tmp"
                                    echo ""
                                } >> "$ERROR_LOG"
                            fi
                        fi
                    done
                fi

                rm -f "$_stderr_tmp"
                (( fail_count += 1 ))
                if [[ "$_is_system_task" == "true" ]]; then
                    failed_utils+=("$util")
                else
                    failed_utils+=("$util (${op_type})")
                fi
            fi
        else
            echo "${RED}✗ No ${_verb} function found for: $util${RESET}"
            log_error "No ${_verb} function found for: $util"
            (( fail_count += 1 ))
            if [[ "$_is_system_task" == "true" ]]; then
                failed_utils+=("$util")
            else
                failed_utils+=("$util (${op_type})")
            fi
        fi
    }

    # Process uninstallations first
    for util in "${to_uninstall[@]}"; do
        _run_operation "uninstall" "$util" "${UNINSTALL_FUNCS[$util]}" "$RED" "Uninstalling"
    done

    # Process installations
    for util in "${to_install[@]}"; do
        _run_operation "install" "$util" "${INSTALL_FUNCS[$util]}" "$GREEN" "Installing/Running"
    done

    # Process updates
    for util in "${to_update[@]}"; do
        _run_operation "update" "$util" "${UPDATE_FUNCS[$util]}" "$YELLOW" "Updating"
    done

    # Summary
    echo ""
    echo "${BOLD}${GREEN}════════════════════════════════════════════════════════════════${RESET}"
    echo "${BOLD}${GREEN}                    Operations Complete                        ${RESET}"
    echo "${BOLD}${GREEN}════════════════════════════════════════════════════════════════${RESET}"
    echo ""
    echo "Summary:"
    echo "  ${GREEN}✓ Successful: ${success_count}${RESET}"

    # Log execution summary
    log_info "════════════════════════════════════════════════════════════════"
    log_info "Execution Summary"
    log_info "════════════════════════════════════════════════════════════════"
    log_info "Successful operations: ${success_count}"
    log_info "Failed operations: ${fail_count}"

    if [[ $fail_count -gt 0 ]]; then
        echo "  ${RED}✗ Failed: ${fail_count}${RESET}"
        echo ""
        echo "Failed operations:"
        for util in "${failed_utils[@]}"; do
            echo "    ${RED}- $util${RESET}"
            log_error "Operation failed: $util"
        done
    fi
    echo ""

    # Performance metrics summary
    metrics_summary

    log_info "Script execution completed at: $(date '+%Y-%m-%d %H:%M:%S')"
    log_info "Log files saved to: ${LOG_DIR}"
    log_info "  - Success log: $(basename "$SUCCESS_LOG")"
    if [[ "$ERROR_LOG_INITIALIZED" == "true" ]]; then
        log_info "  - Error log: $(basename "$ERROR_LOG")"
    fi

    echo "Log files saved to: ${LOG_DIR}"
    echo ""

    if [[ "$needs_shell_reload" == "true" ]]; then
        echo "${YELLOW}Shell reload recommended:${RESET}"
        echo "  Run 'exec zsh' or open a new terminal to apply Zsh theme/plugin changes."
        echo ""
    fi

    # Offer reboot (only for System Tasks and Docker)
    if [[ "$needs_reboot" == "true" ]]; then
        read -n 1 -rp "Reboot now? (y/N) " REBOOT_CHOICE < /dev/tty
        echo
        REBOOT_CHOICE=${REBOOT_CHOICE:-N}
        case "$REBOOT_CHOICE" in
            y|Y)
                info "Rebooting…"
                printf '\n\n'
                sudo reboot
                ;;
            *)
                info "Remember to reboot later if needed."
                read -rp "Press ENTER to return to menu..." < /dev/tty
                ;;
        esac
    else
        read -n 1 -rp "No reboot needed. Reload script (Y) or exit (N)? " _RELOAD_CHOICE < /dev/tty
        echo
        _RELOAD_CHOICE=${_RELOAD_CHOICE:-Y}
        case "$_RELOAD_CHOICE" in
            y|Y|"")
                exec bash "$SCRIPT_PATH" "${ORIGINAL_ARGS[@]}"
                ;;
            *)
                info "Exiting."
                exit 0
                ;;
        esac
    fi
}

# ============================================================================
# CLI OPERATION DISPATCHER
# ============================================================================

# _cli_op op util func
#   op   — install | uninstall | update
#   util — resolved utility name
#   func — resolved function name (already validated by caller)
_cli_op() {
    local _op="$1" _util="$2" _func="$3"
    [[ "$_op" == "install" || "$_op" == "update" ]] && pkg_refresh
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "[DRY RUN] Would ${_op}: ${_util}"; exit 0
    fi
    local _snap_msg
    if [[ "$_op" == "install" && "${UNINSTALL_FUNCS[$_util]:-}" == "noop_function" ]]; then
        _snap_msg="linux_util: Before running ${_util}"
    else
        _snap_msg="linux_util: Before ${_op}ing ${_util}"
    fi
    timeshift_create_snapshot "$_snap_msg"
    if $_func; then
        echo "${_op^}ed: ${_util}"; exit 0
    else
        echo "Failed: ${_util}"; exit 1
    fi
}

# ============================================================================
# COMMAND-LINE ARGUMENT PARSING
# ============================================================================

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --help|-h)
                cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Options:
  --help, -h            Show this help message and exit
  --version             Show script version (git commit)
  --list                List all available utilities with install status
  --dry-run             Preview actions without making any changes
  --verbose             Enable verbose output (extra status messages)
  --debug               Enable debug output (internal state details)
  --install <name>      Non-interactively install a utility by name
  --uninstall <name>    Non-interactively uninstall a utility by name
  --update <name>       Non-interactively update a utility by name
  --update-all          Update every currently installed utility
  --check <name>        Exit 0 if utility is installed, 1 if not
  --no-color            Disable colored output
  --setup-logrotate     Install logrotate config for linux_util logs

Configuration: Copy linux_util.conf.example to linux_util.conf to customize.
Utility names are matched case-insensitively and support partial matches.
EOF
                exit 0
                ;;
            --version)
                echo "linux_util $(git -C "$SCRIPT_DIR" rev-parse --short HEAD 2>/dev/null || echo 'unknown')"
                exit 0
                ;;
            --list)
                echo "Available utilities:"
                for util in "${UTILITIES[@]}"; do
                    local check_func="${CHECK_FUNCS[$util]}"
                    local status="not installed"
                    if [[ -n "$check_func" ]] && declare -f "$check_func" &>/dev/null; then
                        if $check_func 2>/dev/null; then
                            status="installed"
                            local ver_func="${VERSION_FUNCS[$util]:-}"
                            if [[ -n "$ver_func" ]] && declare -f "$ver_func" &>/dev/null; then
                                local ver
                                ver=$($ver_func 2>/dev/null)
                                [[ -n "$ver" ]] && status="installed: v${ver}"
                            fi
                        fi
                    fi
                    printf "  %-35s [%s]\n" "$util" "$status"
                done
                exit 0
                ;;
            --dry-run)
                DRY_RUN=true
                echo "${YELLOW}[DRY RUN] No changes will be made.${RESET}"
                shift
                ;;
            --verbose)
                VERBOSE=true
                shift
                ;;
            --debug)
                DEBUG=true
                VERBOSE=true   # debug implies verbose
                shift
                ;;
            --no-color)
                NO_COLOR_FLAG=true
                BOLD="" DIM="" RESET="" RED="" GREEN="" YELLOW="" BLUE="" MAGENTA="" CYAN="" WHITE="" BG_BLUE="" BG_CYAN=""
                shift
                ;;
            --setup-logrotate)
                setup_logrotate
                exit $?
                ;;
            --install)
                [[ -z "${2:-}" ]] && { echo "Error: --install requires a utility name."; exit 1; }
                local _util; _util=$(resolve_utility_name "$2") || exit 1; shift 2
                local _func="${INSTALL_FUNCS[$_util]:-}"
                if [[ -z "$_func" ]] || ! declare -f "$_func" &>/dev/null; then
                    echo "Error: No install function found for: $_util"; exit 1
                fi
                _cli_op install "$_util" "$_func"
                ;;
            --uninstall)
                [[ -z "${2:-}" ]] && { echo "Error: --uninstall requires a utility name."; exit 1; }
                local _util; _util=$(resolve_utility_name "$2") || exit 1; shift 2
                local _func="${UNINSTALL_FUNCS[$_util]:-}"
                if [[ -z "$_func" ]] || ! declare -f "$_func" &>/dev/null; then
                    echo "Error: No uninstall function found for: $_util"; exit 1
                fi
                _cli_op uninstall "$_util" "$_func"
                ;;
            --update)
                [[ -z "${2:-}" ]] && { echo "Error: --update requires a utility name."; exit 1; }
                local _util; _util=$(resolve_utility_name "$2") || exit 1; shift 2
                local _func="${UPDATE_FUNCS[$_util]:-}"
                if [[ -z "$_func" ]] || ! declare -f "$_func" &>/dev/null; then
                    echo "Error: No update function found for: $_util"; exit 1
                fi
                _cli_op update "$_util" "$_func"
                ;;
            --update-all)
                shift
                echo "Updating all installed utilities..."
                pkg_refresh
                timeshift_create_snapshot "linux_util: Before updating all installed utilities"
                local _updated=0 _failed=0
                for _util in "${UTILITIES[@]}"; do
                    local _check="${CHECK_FUNCS[$_util]:-}"
                    local _upd="${UPDATE_FUNCS[$_util]:-}"
                    if [[ -n "$_check" ]] && declare -f "$_check" &>/dev/null && $_check 2>/dev/null; then
                        if [[ -n "$_upd" ]] && declare -f "$_upd" &>/dev/null; then
                            echo "Updating: $_util"
                            if [[ "$DRY_RUN" == "true" ]]; then
                                echo "  (dry-run skipped)"
                            elif $_upd; then
                                (( _updated += 1 ))
                            else
                                echo "  Failed to update: $_util"
                                (( _failed += 1 ))
                            fi
                        fi
                    fi
                done
                echo "Done. Updated: ${_updated}, Failed: ${_failed}."
                exit $(( _failed > 0 ? 1 : 0 ))
                ;;
            --check)
                [[ -z "${2:-}" ]] && { echo "Error: --check requires a utility name."; exit 1; }
                local _util
                _util=$(resolve_utility_name "$2") || exit 1
                shift 2
                local _func="${CHECK_FUNCS[$_util]:-}"
                if [[ -z "$_func" ]] || ! declare -f "$_func" &>/dev/null; then
                    echo "Error: No check function found for: $_util"; exit 1
                fi
                if $_func 2>/dev/null; then
                    local _ver_func="${VERSION_FUNCS[$_util]:-}"
                    if [[ -n "$_ver_func" ]] && declare -f "$_ver_func" &>/dev/null; then
                        local _ver
                        _ver=$($_ver_func 2>/dev/null)
                        if [[ -n "$_ver" ]]; then
                            echo "${_util} is installed (v${_ver})"; exit 0
                        fi
                    fi
                    echo "${_util} is installed"; exit 0
                else
                    echo "${_util} is not installed"; exit 1
                fi
                ;;
            *)
                echo "Unknown option: $1"
                echo "Run '$(basename "$0") --help' for usage."
                exit 1
                ;;
        esac
    done
}

# ============================================================================
# MAIN ENTRY POINT
# ============================================================================

main() {
    # Pre-parse info-only flags that should work without network access or
    # side effects (self_update_script does a git pull).
    for _arg in "$@"; do
        case "$_arg" in
            --help|-h|--version|--list|--check)
                parse_args "$@"
                return  # parse_args exits for these flags; this is a safety net
                ;;
        esac
    done

    self_update_script "$@"
    parse_args "$@"

    # Main loop: show menu, process selections, repeat
    while true; do
        run_selection_menu
        process_selected
    done
}

main "$@"

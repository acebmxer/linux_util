# Linux Utilities Script - Additional Recommendations

## Implemented Features ✓

### Logging System
- ✓ Dual log files (success/error) in `logs/` directory
- ✓ Timestamped log entries
- ✓ Latest log symlinks for easy access
- ✓ Log management utility (`manage_logs.sh`)
- ✓ Automatic log directory creation
- ✓ Error trapping and stack traces

## Recommended Enhancements

### 1. Configuration File
Create a `config.ini` or `linux_util.conf` file to allow customization:

```ini
[Logging]
log_retention_days=30
max_log_size_mb=50
compress_old_logs=true
log_level=INFO  # DEBUG, INFO, WARNING, ERROR

[Installation]
auto_confirm=false
parallel_installs=false
retry_failed=true
retry_attempts=3

[Network]
dns_check_enabled=true
dns_timeout_seconds=10
use_proxy=false
proxy_url=

[Behavior]
auto_cleanup=true
create_backups=true
backup_dir=./backups
```

### 2. Backup System
Before uninstalling or modifying configs:

```bash
backup_config() {
    local app="$1"
    local config_path="$2"
    local backup_dir="${SCRIPT_DIR}/backups/${app}_$(date +%Y%m%d_%H%M%S)"
    
    if [[ -e "$config_path" ]]; then
        mkdir -p "$backup_dir"
        cp -r "$config_path" "$backup_dir/"
        log_success "Backed up $app config to $backup_dir"
    fi
}
```

### 3. Rollback Functionality
Track installed packages and support rollback:

```bash
# Before installation
snapshot_system() {
    local snapshot_file="${LOG_DIR}/snapshot_$(date +%Y%m%d_%H%M%S).txt"
    dpkg -l > "$snapshot_file"  # Debian/Ubuntu
    log_info "System snapshot saved: $snapshot_file"
}

# Rollback to previous state
rollback() {
    local snapshot="$1"
    # Compare current state with snapshot
    # Uninstall new packages
    # Reinstall removed packages
}
```

### 4. Parallel Installation Support
Speed up installations using background processes:

```bash
parallel_install() {
    local -a utilities=("$@")
    local max_parallel=3
    local count=0
    
    for util in "${utilities[@]}"; do
        install_utility "$util" &
        ((count++))
        
        if [[ $count -ge $max_parallel ]]; then
            wait -n  # Wait for any job to finish
            ((count--))
        fi
    done
    
    wait  # Wait for all remaining jobs
}
```

### 5. Pre-flight Checks
Validate system before installation:

```bash
preflight_check() {
    local checks_passed=0
    local checks_failed=0
    
    # Check disk space
    local free_space=$(df / | awk 'NR==2 {print $4}')
    if [[ $free_space -lt 1048576 ]]; then  # Less than 1GB
        log_warning "Low disk space: ${free_space}KB available"
        ((checks_failed++))
    else
        ((checks_passed++))
    fi
    
    # Check internet connectivity
    if ! ping -c 1 8.8.8.8 &>/dev/null; then
        log_error "No internet connectivity"
        ((checks_failed++))
    else
        ((checks_passed++))
    fi
    
    # Check for conflicting processes
    if pgrep -f "apt|dnf|yum|pacman|zypper" &>/dev/null; then
        log_warning "Package manager is already running"
        ((checks_failed++))
    else
        ((checks_passed++))
    fi
    
    echo "Preflight: ${checks_passed} passed, ${checks_failed} failed"
    return $checks_failed
}
```

### 6. Dependency Resolution
Check and install dependencies before main package:

```bash
check_dependencies() {
    local app="$1"
    local -a deps=()
    
    case "$app" in
        docker)
            deps=("curl" "ca-certificates")
            ;;
        steam)
            deps=("lib32gcc1" "lib32stdc++6")
            ;;
    esac
    
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &>/dev/null; then
            log_info "Installing dependency: $dep"
            pkg_install "$dep"
        fi
    done
}
```

### 7. Update Notifications
Check for script updates:

```bash
check_script_update() {
    local current_version="1.0.0"
    local remote_version=$(curl -s "https://raw.githubusercontent.com/user/repo/main/VERSION")
    
    if [[ "$remote_version" > "$current_version" ]]; then
        echo "⚠ Script update available: $current_version → $remote_version"
        echo "Run: git pull to update"
        log_info "Script update available: $remote_version"
    fi
}
```

### 8. Dry-Run Mode
Preview changes without making them:

```bash
# Add to script start
DRY_RUN=false
if [[ "$1" == "--dry-run" ]]; then
    DRY_RUN=true
    echo "DRY RUN MODE - No changes will be made"
fi

# Wrap commands
execute() {
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "[DRY RUN] Would execute: $@"
        log_info "[DRY RUN] $@"
    else
        "$@"
    fi
}
```

### 9. Email Notifications
Send email on completion or errors:

```bash
send_email_report() {
    local subject="$1"
    local body="$2"
    local email="${ADMIN_EMAIL:-root@localhost}"
    
    if command -v mail &>/dev/null; then
        echo "$body" | mail -s "$subject" "$email"
        log_info "Email report sent to $email"
    fi
}

# Usage
if [[ $fail_count -gt 0 ]]; then
    send_email_report "Linux Util: Errors Detected" \
        "Installation completed with $fail_count error(s). See attached logs."
fi
```

### 10. Performance Metrics
Track execution time and resource usage:

```bash
# Start timer
SCRIPT_START=$(date +%s)

# End timer and calculate
script_duration() {
    local end=$(date +%s)
    local duration=$((end - SCRIPT_START))
    local minutes=$((duration / 60))
    local seconds=$((duration % 60))
    
    echo "Total execution time: ${minutes}m ${seconds}s"
    log_info "Execution time: ${minutes}m ${seconds}s"
}

# Call at end of script
trap script_duration EXIT
```

### 11. Package Version Pinning
Allow users to specify versions:

```bash
install_with_version() {
    local package="$1"
    local version="$2"
    
    case "$PKG_MGR" in
        apt)
            sudo apt install -y "${package}=${version}"
            ;;
        dnf|yum)
            sudo $PKG_MGR install -y "${package}-${version}"
            ;;
        pacman)
            # Download from archive
            ;;
    esac
}
```

### 12. Health Checks Post-Installation
Verify installations succeeded:

```bash
health_check() {
    local app="$1"
    
    case "$app" in
        docker)
            if docker --version &>/dev/null && \
               systemctl is-active docker &>/dev/null; then
                log_success "Docker health check passed"
                return 0
            fi
            ;;
        steam)
            if command -v steam &>/dev/null; then
                log_success "Steam health check passed"
                return 0
            fi
            ;;
    esac
    
    log_warning "Health check failed for $app"
    return 1
}
```

### 13. Log Rotation Configuration
Add logrotate config:

```bash
/path/to/linux_util/logs/*.log {
    daily
    missingok
    rotate 30
    compress
    delaycompress
    notifempty
    create 0644 user user
}
```

### 14. Verbose/Debug Mode
Add debug output:

```bash
VERBOSE=false
DEBUG=false

debug() {
    [[ "$DEBUG" == "true" ]] && echo "[DEBUG] $*" >&2
}

verbose() {
    [[ "$VERBOSE" == "true" ]] && echo "[VERBOSE] $*"
}
```

### 15. Unit Tests
Create test suite:

```bash
# test_linux_util.sh
test_distro_detection() {
    detect_distro
    [[ -n "$DISTRO_ID" ]] || return 1
    [[ -n "$PKG_MGR" ]] || return 1
    return 0
}

test_logging() {
    log_success "Test message"
    grep -q "Test message" "$SUCCESS_LOG" || return 1
    return 0
}

run_tests() {
    local passed=0
    local failed=0
    
    for test in $(declare -F | grep "test_" | awk '{print $3}'); do
        if $test; then
            echo "✓ $test"
            ((passed++))
        else
            echo "✗ $test"
            ((failed++))
        fi
    done
    
    echo "Tests: $passed passed, $failed failed"
}
```

## Priority Recommendations

1. **High Priority**:
   - Configuration file support
   - Pre-flight system checks
   - Backup system before uninstalls
   - Health checks after installation

2. **Medium Priority**:
   - Dry-run mode
   - Update notifications
   - Performance metrics
   - Better error recovery with retry logic

3. **Low Priority**:
   - Email notifications
   - Parallel installations
   - Unit tests
   - Package version pinning

## Security Recommendations

1. Never store credentials in logs
2. Sanitize user input before logging
3. Set restrictive permissions on log files (0600)
4. Implement log size limits to prevent disk fill
5. Rotate logs automatically
6. Validate script integrity with checksums

## Performance Recommendations

1. Cache package manager metadata
2. Use parallel downloads where supported
3. Minimize DNS lookups
4. Implement smart retry with exponential backoff
5. Optimize disk I/O for log writes

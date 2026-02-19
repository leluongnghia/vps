#!/bin/bash

# core/system_helpers.sh - System Utilities

LOCK_FILE="/var/lock/vps-manager.lock"

# Acquire lock to prevent concurrent execution
acquire_lock() {
    if [ -f "$LOCK_FILE" ]; then
        local pid
        pid=$(cat "$LOCK_FILE" 2>/dev/null)
        if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
            # Verify it's actually a vps-manager process (not just any PID reuse)
            local cmdline
            cmdline=$(cat "/proc/$pid/cmdline" 2>/dev/null | tr '\0' ' ')
            if echo "$cmdline" | grep -q "vps\|install.sh\|vps-manager"; then
                log_error "Another instance is running (PID: $pid)"
                return 1
            else
                # PID reused by different process - stale lock
                rm -f "$LOCK_FILE"
            fi
        else
            # Process dead - stale lock
            rm -f "$LOCK_FILE"
        fi
    fi

    echo $$ > "$LOCK_FILE"
    trap "rm -f $LOCK_FILE" EXIT INT TERM
    return 0
}

# Check available disk space (in MB)
check_disk_space() {
    local path=${1:-"/var/www"}
    local required_mb=${2:-1024}  # Default 1GB
    
    local available_kb=$(df "$path" 2>/dev/null | tail -1 | awk '{print $4}')
    local available_mb=$((available_kb / 1024))
    
    if [ "$available_mb" -lt "$required_mb" ]; then
        log_error "Insufficient disk space: ${available_mb}MB available, ${required_mb}MB required"
        return 1
    fi
    
    return 0
}

# Execute command with timeout
run_with_timeout() {
    local timeout_sec=$1
    shift
    local cmd="$@"
    
    if command -v timeout &>/dev/null; then
        timeout "$timeout_sec" bash -c "$cmd"
        local exit_code=$?
        if [ $exit_code -eq 124 ]; then
            log_error "Command timed out after ${timeout_sec}s"
            return 1
        fi
        return $exit_code
    else
        # Fallback if timeout command not available
        eval "$cmd"
    fi
}

# Show progress spinner for long operations
show_progress() {
    local pid=$1
    local message=${2:-"Processing"}
    local delay=0.1
    local spinstr='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
    
    echo -n "$message "
    while kill -0 "$pid" 2>/dev/null; do
        local temp=${spinstr#?}
        printf "[%c]" "$spinstr"
        spinstr=$temp${spinstr%"$temp"}
        sleep $delay
        printf "\b\b\b"
    done
    printf "   \b\b\b"
    echo ""
}

# Dynamic PHP version detection
detect_php_socket() {
    # Find the latest PHP-FPM socket
    local socket=$(find /run/php -name "php*-fpm.sock" 2>/dev/null | sort -V | tail -1)
    
    if [ -n "$socket" ]; then
        echo "unix:$socket"
        return 0
    fi
    
    # Fallback to common versions
    for ver in 8.3 8.2 8.1 8.0 7.4; do
        if [ -S "/run/php/php${ver}-fpm.sock" ]; then
            echo "unix:/run/php/php${ver}-fpm.sock"
            return 0
        fi
    done
    
    log_error "No PHP-FPM socket found"
    return 1
}

# Validate domain name format
validate_domain() {
    local domain=$1
    if [[ ! "$domain" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$ ]]; then
        log_error "Invalid domain format: $domain"
        return 1
    fi
    return 0
}

# Sanitize user input
sanitize_input() {
    local input=$1
    # Remove dangerous characters
    echo "$input" | sed 's/[;&|`$(){}]//g'
}

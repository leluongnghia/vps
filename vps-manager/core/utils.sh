#!/bin/bash

# core/utils.sh - Utility functions

# Get script directory
UTILS_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Source helper modules
if [ -f "$UTILS_DIR/nginx_helpers.sh" ]; then
    source "$UTILS_DIR/nginx_helpers.sh"
fi
if [ -f "$UTILS_DIR/mysql_helpers.sh" ]; then
    source "$UTILS_DIR/mysql_helpers.sh"
fi
if [ -f "$UTILS_DIR/system_helpers.sh" ]; then
    source "$UTILS_DIR/system_helpers.sh"
fi

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Logger config
LOG_FILE="/var/log/vps-manager.log"
# Ensure log file exists and is writable (if running as root)
if [ "$EUID" -eq 0 ]; then
    touch "$LOG_FILE" 2>/dev/null
    chmod 644 "$LOG_FILE" 2>/dev/null
fi

log() {
    local level=$1
    local msg=$2
    local color=$3
    local timestamp=$(date "+%Y-%m-%d %H:%M:%S")
    
    # Print to screen
    echo -e "${color}[${level}] ${msg}${NC}"
    
    # Log to file if writable
    if [ -w "$LOG_FILE" ]; then
        echo "[$timestamp] [${level}] $msg" >> "$LOG_FILE"
    fi
}

log_info() {
    log "INFO" "$1" "$GREEN"
}

log_warn() {
    log "WARN" "$1" "$YELLOW"
}

log_error() {
    log "ERROR" "$1" "$RED"
}

# Check if a package is installed
is_installed() {
    dpkg -s "$1" &> /dev/null
}

# Pause function
pause() {
    read -p "Press [Enter] key to continue..."
}

# Note: spinner/show_progress is in core/system_helpers.sh

#!/bin/bash

# core/utils.sh - Utility functions

# Get script directory
UTILS_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Source helper modules
if [[ -f "$UTILS_DIR/nginx_helpers.sh" ]]; then
    source "$UTILS_DIR/nginx_helpers.sh"
fi
if [[ -f "$UTILS_DIR/mysql_helpers.sh" ]]; then
    source "$UTILS_DIR/mysql_helpers.sh"
fi
if [[ -f "$UTILS_DIR/system_helpers.sh" ]]; then
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
if [[ "$EUID" -eq 0 ]]; then
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
    if [[ -w "$LOG_FILE" ]]; then
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

# OS Detection
detect_os() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        export OS_ID=$ID
        export OS_VER=$VERSION_ID
    else
        export OS_ID="unknown"
    fi

    if [[ "$OS_ID" == "ubuntu" ]] || [[ "$OS_ID" == "debian" ]]; then
        export OS_FAMILY="debian"
        export PKG_MGR="apt-get"
    elif [[ "$OS_ID" == "almalinux" ]] || [[ "$OS_ID" == "rocky" ]] || [[ "$OS_ID" == "rhel" ]] || [[ "$OS_ID" == "centos" ]]; then
        export OS_FAMILY="rhel"
        export PKG_MGR="dnf"
    else
        export OS_FAMILY="unknown"
    fi
}
# Run OS detection immediately
detect_os

# Web Server Detection
# Returns: nginx | none
detect_webserver() {
    if systemctl is-active --quiet nginx 2>/dev/null; then
        export WEB_SERVER_TYPE="nginx"
    elif command -v nginx &>/dev/null && nginx -v &>/dev/null 2>&1; then
        export WEB_SERVER_TYPE="nginx"
    else
        export WEB_SERVER_TYPE="none"
    fi
    echo "$WEB_SERVER_TYPE"
}

# Check if a specific web server is active
require_webserver() {
    local required=$1   # "nginx" or "openlitespeed"
    detect_webserver >/dev/null
    if [[ "$WEB_SERVER_TYPE" != "$required" ]]; then
        log_error "Tính năng này yêu cầu $required, nhưng đang dùng: ${WEB_SERVER_TYPE:-none}"
        pause
        return 1
    fi
    return 0
}

# Run web server detection immediately
detect_webserver >/dev/null 2>&1 || true

# Wrapper for package installation
pkg_install() {
    if [[ "$OS_FAMILY" == "debian" ]]; then
        DEBIAN_FRONTEND=noninteractive apt-get install -y "$@"
    elif [[ "$OS_FAMILY" == "rhel" ]]; then
        dnf install -y "$@"
    fi
}

pkg_update() {
    if [[ "$OS_FAMILY" == "debian" ]]; then
        # Fix stale LiteSpeed GPG key error if left-over repo file exists on this server
        if [[ -f /etc/apt/sources.list.d/lst_debian_repo.list ]]; then
            wget -qO /etc/apt/trusted.gpg.d/lst_debian_repo.gpg http://rpms.litespeedtech.com/debian/lst_debian_repo.gpg 2>/dev/null || true
            wget -qO - http://rpms.litespeedtech.com/debian/lst_repo.gpg 2>/dev/null | gpg --dearmor --yes -o /etc/apt/trusted.gpg.d/litespeed.gpg 2>/dev/null || true
        fi
        apt-get update -qq
    elif [[ "$OS_FAMILY" == "rhel" ]]; then
        dnf makecache
    fi
}

# Check if a package is installed
is_installed() {
    if [[ "$OS_FAMILY" == "debian" ]]; then
        dpkg -s "$1" &> /dev/null
    elif [[ "$OS_FAMILY" == "rhel" ]]; then
        rpm -q "$1" &> /dev/null
    fi
}

# Pause function
pause() {
    read -p "Press [Enter] key to continue..."
}

# Note: spinner/show_progress is in core/system_helpers.sh

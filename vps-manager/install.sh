#!/bin/bash

# VPS Manager - Installation & Entry Script
# Compatible with Ubuntu 20.04, 22.04 & 24.04

# Define paths
INSTALL_DIR="/usr/local/vps-manager"
REPO_URL="https://github.com/leluongnghia/vps.git"
BRANCH="main"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Check for root
if [[ "$EUID" -ne 0 ]]; then
  echo -e "${RED}Please run as root.${NC}"
  exit 1
fi

# Function to check OS
check_os() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        OS=$NAME
        VER=$VERSION_ID
    elif type lsb_release >/dev/null 2>&1; then
        OS=$(lsb_release -si)
        VER=$(lsb_release -sr)
    else
        echo -e "${RED}Unsupported OS.${NC}"
        exit 1
    fi

    if [[ "$ID" != "ubuntu" ]] && [[ "$ID" != "debian" ]] && [[ "$ID" != "almalinux" ]] && [[ "$ID" != "rocky" ]] && [[ "$ID" != "rhel" ]] && [[ "$ID" != "centos" ]]; then
        echo -e "${YELLOW}Warning: This script is optimized for Ubuntu/Debian and AlmaLinux/RHEL.${NC}"
        echo -e "${YELLOW}Detected: $OS $VER${NC}"
        read -p "Press Enter to continue anyway or Ctrl+C to cancel..."
    fi
}

# Function to install dependencies
install_dependencies() {
    echo -e "${GREEN}Checking dependencies...${NC}"
    if ! command -v git &> /dev/null || ! command -v curl &> /dev/null; then
        echo -e "${YELLOW}Installing git, curl, wget...${NC}"
        if [[ -f /etc/redhat-release ]]; then
            dnf install -y curl wget git unzip tar socat cronie
        else
            apt-get update -qq
            apt-get install -y curl wget git unzip tar socat cron lsb-release
        fi
    fi
}

# Function to self-update/install
update_self() {
    SCRIPT_path=$(readlink -f "$0")
    SCRIPT_DIR=$(dirname "$SCRIPT_path")

    # If we are NOT running from the install directory, we should install/update
    if [[ "$SCRIPT_DIR" != "$INSTALL_DIR" ]]; then
        echo -e "${GREEN}Installing VPS Manager to $INSTALL_DIR...${NC}"
        
        # Helper to clone only the subdirectory if possible, but git archive is remote only if supported.
        # Github supports svn export or partial clone, but simple git clone is most reliable.
        # We will clone the WHOLE repo to a temp dir, then move vps-manager to INSTALL_DIR
        
        TEMP_DIR=$(mktemp -d)
        echo -e "${YELLOW}Cloning repository...${NC}"
        git clone -b "$BRANCH" --depth 1 "$REPO_URL" "$TEMP_DIR/vps-repo"
        
        if [[ $? -ne 0 ]]; then
            echo -e "${RED}Failed to clone repository. Check internet connection.${NC}"
            rm -rf "$TEMP_DIR"
            exit 1
        fi

        # Safe Update Strategy
        BACKUP_DIR="${INSTALL_DIR}_backup_$(date +%s)"
        
        # Change to safe directory to avoid getcwd errors when moving install dir
        cd /tmp
        
        # Move current install to backup instead of deleting immediately
        if [[ -d "$INSTALL_DIR" ]]; then
            echo -e "${YELLOW}Backing up current version...${NC}"
            mv "$INSTALL_DIR" "$BACKUP_DIR"
        fi
        
        mkdir -p "$INSTALL_DIR"

        # Move vps-manager content to INSTALL_DIR
        if [[ -d "$TEMP_DIR/vps-repo/vps-manager" ]]; then
            cp -r "$TEMP_DIR/vps-repo/vps-manager/"* "$INSTALL_DIR/"
            
            # Verify critical file exists
            if [[ ! -f "$INSTALL_DIR/install.sh" ]]; then
                 echo -e "${RED}Update failed: install.sh missing! Restoring backup...${NC}"
                 rm -rf "$INSTALL_DIR"
                 mv "$BACKUP_DIR" "$INSTALL_DIR"
                 rm -rf "$TEMP_DIR"
                 exit 1
            fi
            
            # Update successful - Remove backup
            rm -rf "$BACKUP_DIR"
        else
            echo -e "${RED}Error: vps-manager directory not found in repo! Restoring backup...${NC}"
            rm -rf "$INSTALL_DIR"
            mv "$BACKUP_DIR" "$INSTALL_DIR"
            rm -rf "$TEMP_DIR"
            exit 1
        fi
        
        # Cleanup temp
        rm -rf "$TEMP_DIR"
        
        # Set permissions
        chmod +x "$INSTALL_DIR/install.sh"
        find "$INSTALL_DIR" -name "*.sh" -exec chmod +x {} \;
        
        # Create Symlink
        ln -sf "$INSTALL_DIR/install.sh" /usr/local/bin/vps
        
        # Remove lock file before exec (important!)
        rm -f /var/lock/vps-manager.lock
        
        echo -e "${GREEN}Update completed successfully!${NC}"
        echo -e "${GREEN}Type 'vps' to run the manager anytime.${NC}"
        sleep 2
        
        # Change to new install dir and exec
        cd "$INSTALL_DIR"
        exec "$INSTALL_DIR/install.sh"
        exit 0
    fi
}

# Auto Install Stack
auto_install_stack() {
    clear
    echo -e "${YELLOW}=================================================${NC}"
    echo -e "${GREEN}   AUTO INSTALL: Nginx + MariaDB + PHP + Swap + Cache${NC}"
    echo -e "${YELLOW}=================================================${NC}"
    echo -e "Hệ thống sẽ cài đặt toàn bộ Stack 2026 tự động:"
    echo -e "- RAM ảo: Swap 2GB"
    echo -e "- Database: MariaDB"
    echo -e "- Web Server: Nginx"
    echo -e "- Core: PHP 8.4"
    echo -e "- Caching: Valkey (Thay thế Redis)"
    echo -e "- Tường lửa: Firewalld/UFW + Fail2ban"
    echo -e "- Quản trị cơ sở dữ liệu: phpMyAdmin"
    echo -e ""
    read -p "Chạy Cài đặt Tự động ngay? [Y/n]: " opt_lemp
    if [[ "$opt_lemp" == "y" || "$opt_lemp" == "Y" || -z "$opt_lemp" ]]; then
        echo -e "${BLUE}[1/6] Đang thiết lập Swap...${NC}"
        if [[ ! -f /swapfile ]]; then
            source modules/swap.sh
            create_swap 2048 "auto"
        else
            echo -e "${YELLOW}Swap đã tồn tại. Bỏ qua.${NC}"
        fi

        echo -e "${BLUE}[2/6] Đang cài đặt Nginx & MariaDB...${NC}"
        source modules/lemp.sh
        install_nginx
        install_mariadb
        
        echo -e "${BLUE}[3/6] Đang cài đặt PHP 8.4...${NC}"
        install_php "8.4"

        if [[ -f "modules/phpmyadmin.sh" ]]; then
             echo -e "${BLUE}[4/6] Đang cài đặt phpMyAdmin...${NC}"
             source modules/phpmyadmin.sh
             install_phpmyadmin
        fi

        echo -e "${BLUE}[5/6] Đang cài đặt Valkey (Memory Cache)...${NC}"
        source modules/wordpress_performance.sh 2>/dev/null
        install_valkey

        echo -e "${BLUE}[6/6] Đang cấu hình Firewall...${NC}"
        source modules/security.sh
        setup_firewall "auto"
        
        echo -e "${GREEN}=================================================${NC}"
        echo -e "${GREEN}Quá trình khởi tạo Server đã hoàn tất xuất sắc!${NC}"
    else
        echo -e "${YELLOW}Đã huỷ Auto-Install.${NC}"
    fi
    
    read -p "Nhấn Enter để về Menu chính..."
}

# Main startup logic
main() {
    check_os
    install_dependencies
    
    # Check if we need to install (if core/menu.sh is missing locally)
    # OR if we are running from a one-liner (pipe) or curl
    # A robust check is: does core/menu.sh exist in the directory of this script?
    
    MY_DIR=$(dirname "$(readlink -f "$0")")
    if [[ ! -f "$MY_DIR/core/menu.sh" ]]; then
        # We are likely running from curl | bash or a standalone file
        update_self
    fi
    
    # If we are here, we expect core/menu.sh to exist relative to us
    if [[ -f "$MY_DIR/core/menu.sh" ]]; then
        cd "$MY_DIR"
        source core/menu.sh
        
        # Prevent concurrent execution
        if ! acquire_lock; then
            exit 1
        fi
        
        # Create WWW Shortcut for easier access (On every run to ensure it exists)
        if [[ ! -L /www ]] && [[ -d /var/www ]]; then
            ln -sfn /var/www /www
            # echo -e "${GREEN}Created shortcut /www -> /var/www${NC}"
        fi
        
        # Check if installed to skip auto-install prompt
        if ! command -v nginx &> /dev/null || ! command -v php &> /dev/null; then
            echo -e "${BLUE}=================================================${NC}"
            echo -e "Đây là lần đầu tiên chạy VPS Manager."
            echo -e "Bạn có muốn chạy Auto-Install toàn bộ hệ thống LEMP không?"
            echo -e "(Bao gồm: Nginx, MariaDB, PHP 8.1/8.2/8.3 tự động nhận diện, Valkey Cache, Swap 2GB, Firewall)"
            read -p "Chạy Auto-Install ngay? [Y/n]: " auto
            if [[ "$auto" == "y" || "$auto" == "Y" || -z "$auto" ]]; then
                auto_install_stack
            fi
        fi
        
        main_menu
    else
        echo -e "${RED}Critical Error: core/menu.sh not found in $MY_DIR${NC}"
        echo -e "${YELLOW}Attempting to repair...${NC}"
        update_self
    fi
}

main "$@"

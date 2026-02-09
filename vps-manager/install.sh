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
if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}Please run as root.${NC}"
  exit 1
fi

# Function to check OS
check_os() {
    if [ -f /etc/os-release ]; then
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

    if [[ "$ID" != "ubuntu" ]] && [[ "$ID" != "debian" ]]; then
        echo -e "${YELLOW}Warning: This script is optimized for Ubuntu/Debian.${NC}"
        echo -e "${YELLOW}Detected: $OS $VER${NC}"
        read -p "Press Enter to continue anyway or Ctrl+C to cancel..."
    fi
}

# Function to install dependencies
install_dependencies() {
    echo -e "${GREEN}Checking dependencies...${NC}"
    if ! command -v git &> /dev/null || ! command -v curl &> /dev/null; then
        echo -e "${YELLOW}Installing git, curl, wget...${NC}"
        apt-get update -qq
        apt-get install -y curl wget git unzip tar socat cron lsb-release
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
        
        if [ $? -ne 0 ]; then
            echo -e "${RED}Failed to clone repository. Check internet connection.${NC}"
            rm -rf "$TEMP_DIR"
            exit 1
        fi

        # Remove old install dir
        rm -rf "$INSTALL_DIR"
        mkdir -p "$INSTALL_DIR"

        # Move vps-manager content to INSTALL_DIR
        if [ -d "$TEMP_DIR/vps-repo/vps-manager" ]; then
            cp -r "$TEMP_DIR/vps-repo/vps-manager/"* "$INSTALL_DIR/"
        else
            echo -e "${RED}Error: vps-manager directory not found in repository!${NC}"
            rm -rf "$TEMP_DIR"
            exit 1
        fi
        
        # Cleanup
        rm -rf "$TEMP_DIR"
        
        # Set permissions
        chmod +x "$INSTALL_DIR/install.sh"
        find "$INSTALL_DIR" -name "*.sh" -exec chmod +x {} \;
        
        # Create Symlink
        ln -sf "$INSTALL_DIR/install.sh" /usr/local/bin/vps
        
        echo -e "${GREEN}Installation complete!${NC}"
        echo -e "${GREEN}Type 'vps' to run the manager anytime.${NC}"
        sleep 2
        
        # Handover execution to the installed script
        exec "$INSTALL_DIR/install.sh"
        exit 0
    fi
}

# Main startup logic
main() {
    check_os
    install_dependencies
    
    # Check if we need to install (if core/menu.sh is missing locally)
    # OR if we are running from a one-liner (pipe) or curl
    # A robust check is: does core/menu.sh exist in the directory of this script?
    
    MY_DIR=$(dirname "$(readlink -f "$0")")
    if [ ! -f "$MY_DIR/core/menu.sh" ]; then
        # We are likely running from curl | bash or a standalone file
        update_self
    fi
    
    # If we are here, we expect core/menu.sh to exist relative to us
    if [ -f "$MY_DIR/core/menu.sh" ]; then
        cd "$MY_DIR"
        source core/menu.sh
        main_menu
    else
        echo -e "${RED}Critical Error: core/menu.sh not found in $MY_DIR${NC}"
        echo -e "${YELLOW}Attempting to repair...${NC}"
        update_self
    fi
}

main "$@"

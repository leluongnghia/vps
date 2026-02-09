#!/bin/bash

# VPS Manager - Installation & Entry Script
# Compatible with Ubuntu 22.04 & 24.04

# Define paths
INSTALL_DIR="/usr/local/vps-manager"
SCRIPT_URL="https://raw.githubusercontent.com/yourusername/vps-manager/main" # Placeholder

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check for root
if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}Please run as root.${NC}"
  exit 1
fi

# Check OS
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

if [[ "$ID" != "ubuntu" ]] || [[ "$VER" != "22.04" && "$VER" != "24.04" ]]; then
    echo -e "${RED}This script only supports Ubuntu 22.04 and 24.04.${NC}"
    echo -e "${YELLOW}Detected: $OS $VER${NC}"
    # exit 1 # Strict check, can be commented out for testing
fi

# Function to install dependencies
install_dependencies() {
    echo -e "${GREEN}Installing dependencies...${NC}"
    apt-get update -qq
    apt-get install -y curl wget git unzip tar socat cron
}

# Function to setup the script environment (simulated for local dev)
setup_environment() {
    # In a real scenario, this would clone the repo to /usr/local/vps-manager
    # For now, we assume the script is running from the current directory
    chmod +x core/*.sh modules/*.sh 2>/dev/null
}

# Main execution
clear
echo -e "${GREEN}=================================================${NC}"
echo -e "${GREEN}   Welcome to VPS Manager Installer${NC}"
echo -e "${GREEN}=================================================${NC}"

setup_environment

# Load the menu
if [ -f "core/menu.sh" ]; then
    source core/menu.sh
    main_menu
else
    echo -e "${RED}Error: Menu file not found!${NC}"
    exit 1
fi

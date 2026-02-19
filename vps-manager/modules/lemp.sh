#!/bin/bash

# modules/lemp.sh - LEMP Stack Installation

install_lemp_menu() {
    clear
    echo -e "${BLUE}=================================================${NC}"
    echo -e "${GREEN}          LEMP Stack Installation${NC}"
    echo -e "${BLUE}=================================================${NC}"
    echo -e "1. Install Full LEMP Stack (Recommended)"
    echo -e "2. Install Nginx Only"
    echo -e "3. Install MariaDB Only"
    echo -e "4. Install PHP Only"
    echo -e "0. Back to Main Menu"
    echo -e "${BLUE}=================================================${NC}"
    read -p "Enter your choice [0-4]: " choice

    case $choice in
        1)
            install_nginx
            install_mariadb
            install_php
            
            # Auto-install phpMyAdmin
            if [ -f "$ROOT_DIR/modules/phpmyadmin.sh" ]; then
                log_info "Tự động cài đặt phpMyAdmin..."
                source "$ROOT_DIR/modules/phpmyadmin.sh"
                install_phpmyadmin
            fi
            
            pause
            ;;
        2)
            install_nginx
            pause
            ;;
        3)
            install_mariadb
            pause
            ;;
        4)
            install_php
            pause
            ;;
        0)
            return
            ;;
        *)
            echo -e "${RED}Invalid choice!${NC}"
            pause
            ;;
    esac
}

install_nginx() {
    if is_installed nginx; then
        log_warn "Nginx is already installed."
    else
        log_info "Installing Nginx..."
        apt-get update
        apt-get install -y nginx
        systemctl enable nginx
        systemctl start nginx
        log_info "Nginx installed successfully."
    fi
}

install_mariadb() {
    if is_installed mariadb-server; then
        log_warn "MariaDB is already installed."
    else
        log_info "Installing MariaDB..."
        apt-get install -y mariadb-server
        systemctl enable mariadb
        systemctl start mariadb
        
        # Secure installation automation could go here
        log_info "MariaDB installed. Please run 'mysql_secure_installation' manually for security."
    fi
}

install_php() {
    log_info "Adding PHP repository (ondrej/php)..."
    apt-get install -y software-properties-common
    add-apt-repository -y ppa:ondrej/php
    apt-get update

    if [ -n "$1" ]; then
        php_choice=$1
    else
        echo -e "Select PHP Version:"
        echo -e "1) PHP 8.3"
        echo -e "2) PHP 8.2"
        echo -e "3) PHP 8.1"
        read -p "Choice [1-3]: " php_choice
    fi

    case $php_choice in
        1|8.3) ver="8.3" ;;
        2|8.2) ver="8.2" ;;
        3|8.1) ver="8.1" ;;
        *) ver="8.3" ;;
    esac

    log_info "Installing PHP $ver..."
    apt-get install -y php$ver php$ver-fpm php$ver-mysql php$ver-common php$ver-cli php$ver-curl php$ver-xml php$ver-mbstring php$ver-zip php$ver-bcmath php$ver-intl php$ver-gd php$ver-imagick
    
    systemctl enable php$ver-fpm
    systemctl start php$ver-fpm
    log_info "PHP $ver installed successfully."
}

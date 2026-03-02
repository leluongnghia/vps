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
        
        # Increase global upload limit right after install
        if [ -f /etc/nginx/nginx.conf ]; then
            sed -i '/http {/a \        client_max_body_size 128M;' /etc/nginx/nginx.conf
        fi
        
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
    apt-get install -y software-properties-common >/dev/null 2>&1
    add-apt-repository -y ppa:ondrej/php >/dev/null 2>&1
    apt-get update >/dev/null 2>&1

    local primary_ver="8.3"
    
    if [ -n "$1" ]; then
        primary_ver="$1"
    else
        echo -e "${YELLOW}Cài đặt PHP (Mặc định: PHP 8.3)${NC}"
    fi

    _install_single_php "$primary_ver"

    # Chỉ hỏi cài thêm nếu không điền tham số (khi chạy menu tương tác)
    if [ -z "$1" ]; then
        echo ""
        read -p "Bạn có muốn cài thêm phiên bản PHP phụ không? [y/N]: " install_more
        if [[ "$install_more" == "y" || "$install_more" == "Y" ]]; then
            echo -e "Chọn phiên bản PHP muốn cài thêm:"
            echo -e "1. PHP 8.1"
            echo -e "2. PHP 8.2"
            echo -e "3. PHP 8.4"
            echo -e "0. Bỏ qua"
            read -p "Chọn [0-3]: " extra_choice
            case $extra_choice in
                1) _install_single_php "8.1" ;;
                2) _install_single_php "8.2" ;;
                3) _install_single_php "8.4" ;;
                *) echo "Đã bỏ qua cài thêm PHP phụ." ;;
            esac
        fi
    fi
}

_install_single_php() {
    local ver=$1
    log_info "Installing PHP $ver..."
    apt-get install -y php$ver php$ver-fpm php$ver-mysql php$ver-common php$ver-cli php$ver-curl php$ver-xml php$ver-mbstring php$ver-zip php$ver-bcmath php$ver-intl php$ver-gd php$ver-imagick
    
    # Configure PHP Upload Limits
    local php_ini="/etc/php/$ver/fpm/php.ini"
    if [ -f "$php_ini" ]; then
        sed -i -E "s/^[; ]*upload_max_filesize.*/upload_max_filesize = 128M/" "$php_ini"
        sed -i -E "s/^[; ]*post_max_size.*/post_max_size = 128M/" "$php_ini"
        sed -i -E "s/^[; ]*memory_limit.*/memory_limit = 256M/" "$php_ini"
        sed -i -E "s/^[; ]*max_execution_time.*/max_execution_time = 300/" "$php_ini"
        sed -i -E "s/^[; ]*max_input_vars.*/max_input_vars = 3000/" "$php_ini"
    fi
    
    systemctl enable php$ver-fpm >/dev/null 2>&1
    systemctl start php$ver-fpm >/dev/null 2>&1
    log_info "PHP $ver installed successfully."
}

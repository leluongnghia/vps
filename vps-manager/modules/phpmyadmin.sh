#!/bin/bash

# modules/phpmyadmin.sh - Install & Manage phpMyAdmin

phpmyadmin_menu() {
    clear
    echo -e "${BLUE}=================================================${NC}"
    echo -e "${GREEN}          Quản lý phpMyAdmin${NC}"
    echo -e "${BLUE}=================================================${NC}"
    echo -e "1. Cài đặt phpMyAdmin"
    echo -e "2. Xóa phpMyAdmin"
    echo -e "3. Secure phpMyAdmin (Đổi URL/Protected)"
    echo -e "0. Quay lại"
    echo -e "${BLUE}=================================================${NC}"
    read -p "Chọn: " c
    
    case $c in
        1) install_phpmyadmin ;;
        2) uninstall_phpmyadmin ;;
        3) secure_phpmyadmin ;;
        0) return ;;
        *) echo -e "${RED}Sai lựa chọn.${NC}"; pause ;;
    esac
}

install_phpmyadmin() {
    echo -e "${GREEN}--- Cài đặt phpMyAdmin ---${NC}"
    
    PMA_DIR="/var/www/html/phpmyadmin"
    
    # Check dependencies
    if ! dpkg -l | grep -q php-mbstring; then
        log_info "Cài đặt dependencies..."
        apt-get update
        apt-get install -y php-mbstring php-zip php-gd php-json php-curl
    fi
    
    # Download
    log_info "Đang tải phpMyAdmin..."
    PMA_VER="5.2.1"
    cd /tmp
    wget -q https://files.phpmyadmin.net/phpMyAdmin/${PMA_VER}/phpMyAdmin-${PMA_VER}-all-languages.tar.gz
    
    if [ ! -f "phpMyAdmin-${PMA_VER}-all-languages.tar.gz" ]; then
        log_error "Tải thất bại."
        return
    fi
    
    mkdir -p /var/www/html
    tar xzf phpMyAdmin-${PMA_VER}-all-languages.tar.gz
    rm -rf "$PMA_DIR"
    mv phpMyAdmin-${PMA_VER}-all-languages "$PMA_DIR"
    rm phpMyAdmin-${PMA_VER}-all-languages.tar.gz
    
    # Config
    cp "$PMA_DIR/config.sample.inc.php" "$PMA_DIR/config.inc.php"
    
    # Generate secret
    SECRET=$(openssl rand -base64 32 | tr -dc 'a-zA-Z0-9')
    sed -i "s/\$cfg\['blowfish_secret'\] = '';/\$cfg\['blowfish_secret'\] = '$SECRET';/" "$PMA_DIR/config.inc.php"
    
    # Permissions
    chown -R www-data:www-data "$PMA_DIR"
    find "$PMA_DIR" -type d -exec chmod 755 {} \;
    find "$PMA_DIR" -type f -exec chmod 644 {} \;
    
    # Nginx Config Check
    # Ensure default site or specific location exists
    # We will append a location block to the default site if it exists, or suggest URL
    
    log_info "Cài đặt hoàn tất!"
    echo -e "Truy cập tại: http://<IP_VPS>/phpmyadmin"
    echo -e "User: root (MySQL root) hoặc user database bất kỳ."
    pause
}

uninstall_phpmyadmin() {
    read -p "Xác nhận gỡ bỏ phpMyAdmin? (y/n): " c
    if [[ "$c" == "y" ]]; then
        rm -rf /var/www/html/phpmyadmin
        log_info "Đã gỡ bỏ."
    fi
    pause
}

secure_phpmyadmin() {
    echo -e "${YELLOW}Tính năng này sẽ đổi tên thư mục để che giấu URL.${NC}"
    read -p "Nhập tên đường dẫn mới (ví dụ: sequalo): " new_alias
    
    if [ -z "$new_alias" ]; then return; fi
    
    if [ -d "/var/www/html/phpmyadmin" ]; then
        mv "/var/www/html/phpmyadmin" "/var/www/html/$new_alias"
        log_info "Đã đổi thành: http://<IP_VPS>/$new_alias"
    elif [ -d "/var/www/html/$new_alias" ]; then
        log_warn "Thư mục đã tồn tại."
    else
        log_error "Không tìm thấy thư mục gốc phpMyAdmin."
    fi
    pause
}

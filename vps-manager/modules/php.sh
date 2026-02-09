#!/bin/bash

# modules/php.sh - Multi-PHP Version Management

php_menu() {
    clear
    echo -e "${BLUE}=================================================${NC}"
    echo -e "${GREEN}          Quản lý Đa phiên bản PHP${NC}"
    echo -e "${BLUE}=================================================${NC}"
    echo -e "1. Cài đặt thêm phiên bản PHP (7.4, 8.0, 8.1, 8.2, 8.3)"
    echo -e "2. Thay đổi phiên bản PHP cho Website"
    echo -e "3. Kiểm tra các phiên bản PHP đang cài đặt"
    echo -e "0. Quay lại Menu chính"
    echo -e "${BLUE}=================================================${NC}"
    read -p "Nhập lựa chọn [0-3]: " choice

    case $choice in
        1) install_additional_php ;;
        2) change_site_php ;;
        3) list_php_versions ;;
        0) return ;;
        *) echo -e "${RED}Lựa chọn không hợp lệ!${NC}"; pause ;;
    esac
}

install_additional_php() {
    echo -e "Chọn phiên bản PHP muốn cài đặt:"
    echo -e "1) PHP 7.4 (Cũ - Cho code legacy)"
    echo -e "2) PHP 8.0"
    echo -e "3) PHP 8.1"
    echo -e "4) PHP 8.2"
    echo -e "5) PHP 8.3 (Mới nhất)"
    read -p "Nhập lựa chọn [1-5]: " ver_choice

    case $ver_choice in
        1) ver="7.4" ;;
        2) ver="8.0" ;;
        3) ver="8.1" ;;
        4) ver="8.2" ;;
        5) ver="8.3" ;;
        *) echo -e "${RED}Phiên bản không hợp lệ!${NC}"; return ;;
    esac

    if dpkg -s "php$ver-fpm" &> /dev/null; then
        echo -e "${YELLOW}PHP $ver đã được cài đặt.${NC}"
        pause
        return
    fi

    log_info "Đang cài đặt PHP $ver và các module phổ biến..."
    apt-get update
    apt-get install -y php$ver php$ver-fpm php$ver-mysql php$ver-common php$ver-cli php$ver-curl php$ver-xml php$ver-mbstring php$ver-zip php$ver-bcmath php$ver-intl php$ver-gd php$ver-imagick
    
    # Check if redis module is needed (if redis is installed)
    if dpkg -s php-redis &> /dev/null; then
        apt-get install -y php$ver-redis
    fi

    systemctl enable php$ver-fpm
    systemctl start php$ver-fpm
    log_info "Cài đặt PHP $ver thành công."
    pause
}

change_site_php() {
    echo -e "${GREEN}Danh sách Website:${NC}"
    ls /var/www/
    echo ""
    read -p "Nhập tên miền cần đổi PHP: " domain

    if [ ! -f "/etc/nginx/sites-available/$domain" ]; then
        echo -e "${RED}Website $domain không tồn tại config Nginx!${NC}"
        pause
        return
    fi

    echo -e "Chọn phiên bản PHP mới cho $domain:"
    echo -e "1) PHP 7.4"
    echo -e "2) PHP 8.0"
    echo -e "3) PHP 8.1"
    echo -e "4) PHP 8.2"
    echo -e "5) PHP 8.3"
    read -p "Nhập lựa chọn [1-5]: " ver_choice

    case $ver_choice in
        1) new_ver="7.4" ;;
        2) new_ver="8.0" ;;
        3) new_ver="8.1" ;;
        4) new_ver="8.2" ;;
        5) new_ver="8.3" ;;
        *) echo -e "${RED}Phiên bản không hợp lệ!${NC}"; return ;;
    esac

    # Check if selected PHP version is installed
    if ! dpkg -s "php$new_ver-fpm" &> /dev/null; then
        echo -e "${RED}PHP $new_ver chưa được cài đặt. Vui lòng cài đặt trước trong menu PHP Management.${NC}"
        pause
        return
    fi

    log_info "Đang cập nhật cấu hình Nginx cho $domain sang PHP $new_ver..."
    
    local config_file="/etc/nginx/sites-available/$domain"
    
    # Replace fastcgi_pass line
    # Using sed with regex to match any php version in the socket path
    sed -i "s|unix:/run/php/php[0-9.]*-fpm.sock|unix:/run/php/php$new_ver-fpm.sock|g" "$config_file"
    
    nginx -t && systemctl reload nginx
    log_info "Đã chuyển đổi $domain sang PHP $new_ver."
    pause
}

list_php_versions() {
    echo -e "${GREEN}Các phiên bản PHP đã cài đặt:${NC}"
    dpkg --get-selections | grep -E "php[0-9]\.[0-9]-fpm" | awk '{print $1}'
    pause
}

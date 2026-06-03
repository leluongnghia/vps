#!/bin/bash

# modules/php.sh - Multi-PHP Version Management

php_menu() {
    clear
    echo -e "${BLUE}=================================================${NC}"
    echo -e "${GREEN}          Quản lý Đa phiên bản PHP${NC}"
    echo -e "${BLUE}=================================================${NC}"
    echo -e "1. Cài đặt thêm phiên bản PHP (7.4, 8.0, 8.1, 8.2, 8.3, 8.4)"
    echo -e "2. Thay đổi phiên bản PHP cho Website"
    echo -e "3. Kiểm tra các phiên bản PHP đang cài đặt"
    echo -e "0. Quay lại Menu chính"
    echo -e "${BLUE}=================================================${NC}"
    read -p "Nhập lựa chọn [0-3]: " choice

    case $choice in
        1) install_additional_php ;;
        2) 
            source "$(dirname "${BASH_SOURCE[0]}")/site.sh"
            change_site_php 
            ;;
        3) list_php_versions ;;
        0) return ;;
        *) echo -e "${RED}Lựa chọn không hợp lệ!${NC}"; pause ;;
    esac
}

install_additional_php() {
    local ver="$1"
    if [[ -z "$ver" ]]; then
        echo -e "Chọn phiên bản PHP muốn cài đặt:"
        echo -e "1) PHP 7.4 (Cũ - Cho code legacy)"
        echo -e "2) PHP 8.0"
        echo -e "3) PHP 8.1"
        echo -e "4) PHP 8.2"
        echo -e "5) PHP 8.3"
        echo -e "6) PHP 8.4 (Mới nhất)"
        read -p "Nhập lựa chọn [1-6]: " ver_choice

        case $ver_choice in
            1) ver="7.4" ;;
            2) ver="8.0" ;;
            3) ver="8.1" ;;
            4) ver="8.2" ;;
            5) ver="8.3" ;;
            6) ver="8.4" ;;
            *) echo -e "${RED}Phiên bản không hợp lệ!${NC}"; return ;;
        esac
    fi

    if [[ "$OS_FAMILY" == "rhel" ]]; then
        local rhel_pkg="php${ver//./}-php-fpm"
        if is_installed "$rhel_pkg"; then
            echo -e "${YELLOW}PHP $ver đã được cài đặt.${NC}"
            pause
            return
        fi
        log_info "Đang cài đặt PHP $ver và các module phổ biến qua Remi..."
        pkg_install "php${ver//./}-php-fpm" "php${ver//./}-php-mysqlnd" "php${ver//./}-php-common" "php${ver//./}-php-cli" "php${ver//./}-php-gd" "php${ver//./}-php-mbstring" "php${ver//./}-php-xml" "php${ver//./}-php-pecl-zip"
        
        systemctl enable "php${ver//./}-php-fpm"
        systemctl start "php${ver//./}-php-fpm"
    else
        if is_installed "php$ver-fpm"; then
            echo -e "${YELLOW}PHP $ver đã được cài đặt.${NC}"
            pause
            return
        fi

        log_info "Đang cài đặt PHP $ver và các module phổ biến..."
        pkg_update
        pkg_install php$ver php$ver-fpm php$ver-mysql php$ver-common php$ver-cli php$ver-curl php$ver-xml php$ver-mbstring php$ver-zip php$ver-bcmath php$ver-intl php$ver-gd php$ver-imagick
        
        # Check if redis module is needed (if redis is installed)
        if is_installed php-redis; then
            pkg_install php$ver-redis
        fi

        systemctl enable php$ver-fpm
        systemctl start php$ver-fpm
    fi
    log_info "Cài đặt PHP $ver thành công."
    pause
}

list_php_versions() {
    echo -e "${GREEN}Các phiên bản PHP đã cài đặt:${NC}"
    if [[ "$OS_FAMILY" == "rhel" ]]; then
        rpm -qa | grep -E "^php[0-9]+-php-fpm" | awk '{print $1}'
    else
        dpkg --get-selections | grep -E "php[0-9]\.[0-9]-fpm" | awk '{print $1}'
    fi
    pause
}

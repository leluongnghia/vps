#!/bin/bash

# modules/cache.sh - Cache Management

cache_menu() {
    clear
    echo -e "${BLUE}=================================================${NC}"
    echo -e "${GREEN}          Quản lý Cache${NC}"
    echo -e "${BLUE}=================================================${NC}"
    echo -e "1. Xóa Cache (FastCGI, Redis, Memcached)"
    echo -e "2. Bật/Tắt Redis PHP Extension"
    echo -e "3. Bật/Tắt Memcached PHP Extension"
    echo -e "4. Bật/Tắt Opcache"
    echo -e "0. Quay lại Menu chính"
    echo -e "${BLUE}=================================================${NC}"
    read -p "Nhập lựa chọn [0-4]: " choice

    case $choice in
        1) clear_all_cache ;;
        2) toggle_extension "redis" ;;
        3) toggle_extension "memcached" ;;
        4) toggle_extension "opcache" ;;
        0) return ;;
        *) echo -e "${RED}Lựa chọn không hợp lệ!${NC}"; pause ;;
    esac
}

clear_all_cache() {
    log_info "Đang xóa Nginx FastCGI Cache..."
    rm -rf /var/run/nginx-cache/*
    
    log_info "Đang Flush Redis..."
    if command -v redis-cli &> /dev/null; then
        redis-cli flushall
    fi
    
    log_info "Đang restart Memcached..."
    systemctl restart memcached 2>/dev/null
    
    log_info "Đang reload PHP-FPM..."
    systemctl reload php*-fpm
    
    log_info "Đã xóa sạch Cache hệ thống."
    pause
}

toggle_extension() {
    ext=$1
    echo -e "Chọn phiên bản PHP để cấu hình $ext:"
    echo -e "1) PHP 8.1"
    echo -e "2) PHP 8.2"
    echo -e "3) PHP 8.3"
    echo -e "4) Tất cả"
    read -p "Chọn: " v
    
    case $v in
        1) ver="8.1" ;;
        2) ver="8.2" ;;
        3) ver="8.3" ;;
        4) ver="all" ;;
        *) return ;;
    esac
    
    read -p "Bạn muốn (on/off)? " state
    
    if [[ "$ver" == "all" ]]; then
        for v in 8.1 8.2 8.3; do
             if [[ "$state" == "off" ]]; then
                 phpdismod -v $v $ext
             else
                 phpenmod -v $v $ext
             fi
        done
        systemctl restart php*-fpm
    else
        if [[ "$state" == "off" ]]; then
             phpdismod -v $ver $ext
        else
             phpenmod -v $ver $ext
        fi
        systemctl restart php$ver-fpm
    fi
    
    log_info "Đã cấu hình $ext -> $state."
    pause
}

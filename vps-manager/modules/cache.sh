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
    echo -e "5. Cấu hình Nginx cho WP Rocket"
    echo -e "7. Tối ưu Server cho Object Cache Pro"
    echo -e "0. Quay lại Menu chính"
    echo -e "${BLUE}=================================================${NC}"
    read -p "Nhập lựa chọn [0-7]: " choice

    case $choice in
        1) clear_all_cache ;;
        2) toggle_extension "redis" ;;
        3) toggle_extension "memcached" ;;
        4) toggle_extension "opcache" ;;
        5) setup_rocket_nginx ;;
        6) setup_w3tc_nginx ;;
        7) setup_object_cache_pro ;;
        0) return ;;
        *) echo -e "${RED}Lựa chọn không hợp lệ!${NC}"; pause ;;
    esac
}

setup_object_cache_pro() {
    log_info "Đang tối ưu Server cho Object Cache Pro..."
    
    # 1. System Tuning (Overcommit Memory)
    if ! grep -q "vm.overcommit_memory" /etc/sysctl.conf; then
        echo "vm.overcommit_memory = 1" >> /etc/sysctl.conf
        sysctl -p
        log_info "Đã bật vm.overcommit_memory = 1"
    fi
    
    # 2. Redis Tuning
    if [ -f /etc/redis/redis.conf ]; then
        # Backup config
        cp /etc/redis/redis.conf /etc/redis/redis.conf.bak
        
        # Set maxmemory (if not set, default to 256mb or keep existing? Let's be safe 256MB)
        # Actually better to not touch maxmemory if user set it, but ensure policy.
        
        # Ensure maxmemory-policy is allkeys-lru (Best for Object Cache)
        if grep -q "^maxmemory-policy" /etc/redis/redis.conf; then
            sed -i "s/^maxmemory-policy.*/maxmemory-policy allkeys-lru/" /etc/redis/redis.conf
        else
            echo "maxmemory-policy allkeys-lru" >> /etc/redis/redis.conf
        fi
        
        systemctl restart redis-server
        log_info "Đã cấu hình Redis: maxmemory-policy allkeys-lru"
    else
        log_warn "Không tìm thấy file cấu hình Redis (/etc/redis/redis.conf)."
    fi
    
    # 3. Check PHP Redis
    toggle_extension "redis" "on" # Ensure enabled
    
    echo -e "${GREEN}Hoàn tất tối ưu cho Object Cache Pro!${NC}"
    echo -e "Lưu ý: Bạn cần cài đặt plugin Object Cache Pro trong WordPress và điền key bản quyền."
    pause
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
    
    # Check if module exists for common versions or install
    # Just force install generic meta-package which usually triggers config generation
    if ! dpkg -s php-$ext &> /dev/null; then
        echo -e "${YELLOW}Extension php-$ext chưa được cài đặt. Đang cài đặt...${NC}"
        apt-get update -qq
        apt-get install -y php-$ext
    fi
    
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
    
    # Ensure package for specific version exists
    if [[ "$ver" != "all" ]]; then
       if ! dpkg -s php$ver-$ext &> /dev/null && ! [ -f "/etc/php/$ver/mods-available/$ext.ini" ]; then
           echo -e "${YELLOW}Cài đặt thêm php$ver-$ext...${NC}"
           apt-get install -y php$ver-$ext
       fi
    else
       # For ALL, ensure for all versions if possible
       apt-get install -y php8.1-$ext php8.2-$ext php8.3-$ext 2>/dev/null
    fi
    
    echo -e "Trạng thái mong muốn:"
    echo -e "1. BẬT (Enable/On)"
    echo -e "2. TẮT (Disable/Off)"
    read -p "Chọn [1-2]: " state_choice
    
    if [[ "$state_choice" == "1" || "$state_choice" == "on" || "$state_choice" == "y" || "$state_choice" == "yes" ]]; then
        state="on"
        action="phpenmod"
    elif [[ "$state_choice" == "2" || "$state_choice" == "off" || "$state_choice" == "n" || "$state_choice" == "no" ]]; then
        state="off"
        action="phpdismod"
    else
        echo -e "${RED}Lựa chọn không hợp lệ!${NC}"
        pause; return
    fi
    
    if [[ "$ver" == "all" ]]; then
        for v in 8.1 8.2 8.3; do
             $action -v $v $ext
        done
        systemctl restart php*-fpm
    else
        $action -v $ver $ext
        systemctl restart php$ver-fpm
    fi
    
    log_info "Đã cấu hình $ext -> $state."
    pause
}

setup_rocket_nginx() {
    log_info "Đang tạo cấu hình Nginx cho WP Rocket..."
    mkdir -p /etc/nginx/snippets
    
    # WP Rocket Nginx Configuration
    cat > /etc/nginx/snippets/wp-rocket.conf <<EOF
# WP Rocket Nginx Config
location ~ /wp-content/cache/wp-rocket/.*html$ {
    etag on;
    add_header Vary "Accept-Encoding, Cookie";
    add_header Cache-Control "no-cache, no-store, must-revalidate";
    add_header X-WP-Rocket "Served";
}

location ~ /wp-content/cache/min/.*(js|css)$ {
    etag on;
    add_header Vary "Accept-Encoding";
    add_header Cache-Control "max-age=31536000, public";
}
EOF
    log_info "Đã tạo snippet WP Rocket tại /etc/nginx/snippets/wp-rocket.conf"
    echo -e "${YELLOW}Vui lòng thêm dòng sau vào block server {} của website:${NC}"
    echo -e "include snippets/wp-rocket.conf;"
    pause
}

setup_w3tc_nginx() {
    log_info "Đang tạo cấu hình Nginx cho W3 Total Cache..."
    mkdir -p /etc/nginx/snippets
    
    cat > /etc/nginx/snippets/w3tc.conf <<EOF
# W3TC Nginx Config
location ~ /wp-content/cache/.*(html|xml|json)$ {
    add_header Vary "Accept-Encoding, Cookie";
    add_header Cache-Control "max-age=3600, must-revalidate";
}

location ~ /wp-content/cache/minify/.*(js|css)$ {
    add_header Cache-Control "max-age=31536000, public";
    add_header Vary "Accept-Encoding";
}
EOF
    log_info "Đã tạo snippet W3TC tại /etc/nginx/snippets/w3tc.conf"
    echo -e "${YELLOW}Vui lòng thêm dòng sau vào block server {} của website:${NC}"
    echo -e "include snippets/w3tc.conf;"
    pause
}

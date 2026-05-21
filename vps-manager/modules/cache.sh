#!/bin/bash

# modules/cache.sh - Cache Management

cache_menu() {
    while true; do
        clear
        echo -e "${BLUE}=================================================${NC}"
        echo -e "${GREEN}          Quản lý Cache${NC}"
        echo -e "${BLUE}=================================================${NC}"
        echo -e "1. Xóa Cache (FastCGI, Redis/Valkey, Memcached)"
        echo -e "2. Bật/Tắt Redis PHP Extension"
        echo -e "3. Bật/Tắt Memcached PHP Extension"
        echo -e "4. Bật/Tắt Opcache"
        echo -e "5. Cấu hình Nginx cho WP Rocket"
        echo -e "6. Cấu hình Nginx cho W3 Total Cache"
        echo -e "7. Tối ưu Server cho Object Cache Pro"
        echo -e "8. Fix lỗi kết nối Redis (Connection Refused)"
        echo -e "9. Cài đặt Object Cache (Redis/Valkey/KeyDB/Memcached)"
        echo -e "0. Quay lại Menu chính"
        echo -e "${BLUE}=================================================${NC}"
        read -p "Nhập lựa chọn [0-9]: " choice

        case $choice in
            1) clear_all_cache ;;
            2) toggle_extension "redis" ;;
            3) toggle_extension "memcached" ;;
            4) toggle_extension "opcache" ;;
            5) setup_rocket_nginx ;;
            6) setup_w3tc_nginx ;;
            7) setup_object_cache_pro ;;
            8) fix_redis_connection ;;
            9) install_object_cache ;;
            0) return ;;
            *) echo -e "${RED}Lựa chọn không hợp lệ!${NC}"; pause ;;
        esac
    done
}

# =============================================================================
# Cài đặt Object Cache theo loại (Redis / Valkey / KeyDB / Memcached)
# Unix Socket theo mặc định để giảm overhead mạng nội bộ
# =============================================================================

install_object_cache() {
    echo -e "${BLUE}=================================================${NC}"
    echo -e "${GREEN}     Cài đặt Object Cache Server${NC}"
    echo -e "${BLUE}=================================================${NC}"
    echo -e "1. Redis"
    echo -e "2. Valkey (fork mới của Redis, khuyến dùng)"
    echo -e "3. KeyDB  (đa luồng, nhanh hơn Redis)"
    echo -e "4. Memcached"
    echo -e "0. Huỷ"
    echo -e "${BLUE}=================================================${NC}"
    read -p "Chọn loại cache [0-4]: " cache_choice

    local object_cache
    case $cache_choice in
        1) object_cache="redis" ;;
        2) object_cache="valkey" ;;
        3) object_cache="keydb" ;;
        4) object_cache="memcached" ;;
        0) return ;;
        *) echo -e "${RED}Lựa chọn không hợp lệ!${NC}"; pause; return ;;
    esac

    log_info "Cài đặt Object Cache: $object_cache..."

    if [[ "$object_cache" == "memcached" ]]; then
        # Memcached ─ sử dụng Unix Socket
        if [[ "$OS_FAMILY" == "debian" ]]; then
            DEBIAN_FRONTEND=noninteractive apt-get install -y memcached &>/dev/null
        else
            dnf install -y memcached &>/dev/null
        fi
        mkdir -p /var/run/memcached
        chown -R memcache:memcache /var/run/memcached 2>/dev/null || true
        cat > /etc/memcached.conf <<'MEMCONF'
-d
logfile /var/log/memcached.log
-m 128
-u memcache
-s /var/run/memcached/memcached.sock
-a 0766
-c 10240
-P /var/run/memcached/memcached.pid
MEMCONF
        systemctl enable memcached
        systemctl restart memcached
        log_info "✓ Memcached đã cài (socket: /var/run/memcached/memcached.sock)"
        pause; return
    fi

    # Redis / Valkey / KeyDB ─ đều dùng Unix Socket
    local name_service="$object_cache"
    local conf_file="/etc/${object_cache}/${object_cache}.conf"
    local socket_path="/var/run/${object_cache}/${object_cache}.sock"

    if [[ "$object_cache" == "redis" ]]; then
        if [[ "$OS_FAMILY" == "debian" ]]; then
            DEBIAN_FRONTEND=noninteractive apt-get install -y redis-server &>/dev/null
        else
            dnf install -y redis &>/dev/null
        fi
        conf_file="/etc/redis/redis.conf"
        socket_path="/var/run/redis/redis.sock"
        mkdir -p /var/run/redis
        chown redis:redis /var/run/redis
    else
        # Valkey / KeyDB
        if [[ "$OS_FAMILY" == "debian" ]]; then
            DEBIAN_FRONTEND=noninteractive apt-get install -y "$object_cache" &>/dev/null
        else
            dnf install -y "$object_cache" &>/dev/null
        fi
        mkdir -p "/var/run/${object_cache}" "/var/lib/${object_cache}" "/var/log/${object_cache}"
        chown -R "${object_cache}:${object_cache}" "/var/run/${object_cache}" 2>/dev/null || true
    fi

    if [[ ! -f "$conf_file" ]]; then
        log_warn "Không tìm thấy file config $conf_file. Có thể gói chưa được cài."
        pause; return
    fi

    # Backup
    cp "$conf_file" "${conf_file}.bak.$(date +%s)" 2>/dev/null || true

    # Tắt TCP port (bảo mật), chỉ dùng Unix Socket
    sed -i 's/^port 6379/#port 6379/g'            "$conf_file"
    sed -i 's/tcp-keepalive 300/tcp-keepalive 0/g' "$conf_file"
    sed -i 's/rdbcompression yes/rdbcompression no/g' "$conf_file"
    sed -i 's/rdbchecksum yes/rdbchecksum no/g'    "$conf_file"

    # Ensure unixsocket path is correctly configured
    if grep -q "^unixsocket " "$conf_file"; then
        sed -i "s|^unixsocket .*|unixsocket ${socket_path}|g" "$conf_file"
    else
        echo "unixsocket ${socket_path}" >> "$conf_file"
    fi
    
    if grep -q "^unixsocketperm " "$conf_file"; then
        sed -i "s|^unixsocketperm .*|unixsocketperm 777|g" "$conf_file"
    else
        echo "unixsocketperm 777" >> "$conf_file"
    fi

    # Set optimal memory policies if not present
    if ! grep -q "^maxmemory " "$conf_file"; then
        cat >> "$conf_file" <<CACHECONF

# vps-manager object cache config
maxmemory 128mb
maxmemory-policy allkeys-lfu
save ""
appendonly no
activedefrag yes
tcp-keepalive 60
CACHECONF
    fi

    chown "${name_service}:${name_service}" "$conf_file" 2>/dev/null || true
    chmod 600 "$conf_file"

    systemctl enable "${object_cache}" 2>/dev/null || systemctl enable "${object_cache}-server" 2>/dev/null || true
    systemctl restart "${object_cache}" 2>/dev/null || systemctl restart "${object_cache}-server" 2>/dev/null || true

    mkdir -p /etc/vps-manager
    echo "OBJECT_CACHE_TYPE=${object_cache}" > /etc/vps-manager/cache.conf
    echo "OBJECT_CACHE_SOCKET=${socket_path}" >> /etc/vps-manager/cache.conf
    chmod 600 /etc/vps-manager/cache.conf

    log_info "✓ $object_cache đã cài đặt với Unix Socket: $socket_path"
    echo -e "${YELLOW}Ghi chú: Thay socket path này vào wp-config.php (WP_REDIS_PATH)${NC}"
    pause
}

fix_redis_connection() {
    source "$(dirname "${BASH_SOURCE[0]}")/site.sh"
    select_site || return
    local domain=$SELECTED_DOMAIN
    local wp_config="/var/www/$domain/public_html/wp-config.php"
    
    if [[ ! -f "$wp_config" ]]; then
        echo -e "${RED}Không tìm thấy wp-config.php cho $domain${NC}"
        pause; return
    fi
    
    echo -e "${CYAN}Đang kiểm tra trạng thái Redis Server...${NC}"
    
    # 1. Check Installation
    if ! command -v redis-server &> /dev/null; then
        echo -e "${RED}CẢNH BÁO: Redis chưa được cài đặt trên VPS!${NC}"
        read -p "Bạn có muốn cài đặt Redis + PHP Extension ngay không? (y/n): " install_opt
        if [[ "$install_opt" == "y" ]]; then
            log_info "Đang cài đặt Redis..."
            apt-get update -qq
            apt-get install -y redis-server php-redis
            
            # Configure Redis (Socket)
            local rconf="/etc/redis/redis.conf"
            cp "$rconf" "$rconf.bak"
            mkdir -p /var/run/redis
            chown redis:redis /var/run/redis 2>/dev/null || true
            
            if ! grep -q "^unixsocket " "$rconf"; then
                echo "" >> "$rconf"
                echo "unixsocket /var/run/redis/redis.sock" >> "$rconf"
                echo "unixsocketperm 770" >> "$rconf"
            fi
            
            # Maxmemory
            if ! grep -q "maxmemory 256mb" "$rconf"; then
                echo "maxmemory 256mb" >> "$rconf"
                echo "maxmemory-policy allkeys-lru" >> "$rconf"
            fi
            
            usermod -aG redis www-data
            systemctl enable redis-server
            systemctl restart redis-server
            
            log_info "Redis đã cài đặt và khởi động."
        else
            return
        fi
    fi
    
    # 2. Check Service Running
    if ! systemctl is-active --quiet redis-server; then
        echo -e "${YELLOW}Redis Service đang tắt. Đang bật lại...${NC}"
        systemctl unmask redis-server 2>/dev/null
        systemctl enable redis-server
        systemctl start redis-server
        
        if ! systemctl is-active --quiet redis-server; then
            echo -e "${RED}LỖI NGHIÊM TRỌNG: Không thể khởi động Redis. Hãy kiểm tra 'systemctl status redis-server'.${NC}"
            pause; return
        fi
    fi
    
    # 3. Detect Connection Method
    local redis_conf="/etc/redis/redis.conf"
    local use_socket=false
    local socket_path="/var/run/redis/redis.sock"

    if [[ -f /etc/vps-manager/cache.conf ]]; then
        local saved_socket
        saved_socket=$(grep -E '^OBJECT_CACHE_SOCKET=' /etc/vps-manager/cache.conf 2>/dev/null | head -n 1 | cut -d= -f2-)
        [[ -n "$saved_socket" ]] && socket_path="$saved_socket"
    fi
    
    if [[ ! -f "$redis_conf" ]]; then
        echo -e "${RED}Không tìm thấy file config $redis_conf. Giả định mặc định (TCP).${NC}"
    elif grep -q "^unixsocket " "$redis_conf"; then
        use_socket=true
        # Try finding exact path
        local found_path=$(grep "^unixsocket " "$redis_conf" | head -n1 | awk '{print $2}')
        if [[ -n "$found_path" ]]; then socket_path="$found_path"; fi
    fi
    
    # Verify socket existence if config says so
    if [[ "$use_socket" = "true" ]] && [[ ! -S "$socket_path" ]]; then
        echo -e "${YELLOW}Cấu hình dùng Socket nhưng file $socket_path không tồn tại.${NC}"
        echo -e "Đang restart Redis để tạo socket..."
        systemctl restart redis-server
        sleep 2
        if [[ ! -S "$socket_path" ]]; then
            echo -e "${RED}Vẫn không thấy socket. Chuyển về TCP.${NC}"
            use_socket=false
        fi
    fi
    
    # 4. Update wp-config.php
    echo -e "${YELLOW}Đang cấu hình lại kết nối Redis cho WordPress...${NC}"
    
    # Clean old configs
    sed -i "/WP_REDIS_SCHEME/d" "$wp_config"
    sed -i "/WP_REDIS_PATH/d" "$wp_config"
    sed -i "/WP_REDIS_HOST/d" "$wp_config"
    sed -i "/WP_REDIS_PORT/d" "$wp_config"
    sed -i "/WP_REDIS_DATABASE/d" "$wp_config" # Clean DB ID config too
    
    if [[ "$use_socket" = "true" ]]; then
        echo -e "-> Chế độ: ${GREEN}Unix Socket ($socket_path)${NC}"
        sed -i "/table_prefix/i define( 'WP_REDIS_SCHEME', 'unix' );" "$wp_config"
        sed -i "/table_prefix/i define( 'WP_REDIS_PATH', '$socket_path' );" "$wp_config"
        # Perm Fix: add www-data to redis group, ensure socket writable
        usermod -aG redis www-data 2>/dev/null
        chmod 777 "$socket_path" 2>/dev/null
    else
        echo -e "-> Chế độ: ${YELLOW}TCP (127.0.0.1:6379)${NC}"
        sed -i "/table_prefix/i define( 'WP_REDIS_HOST', '127.0.0.1' );" "$wp_config"
        sed -i "/table_prefix/i define( 'WP_REDIS_PORT', 6379 );" "$wp_config"
    fi
    
    # Key Salt
    if ! grep -q "WP_CACHE_KEY_SALT" "$wp_config"; then
        sed -i "/table_prefix/i define( 'WP_CACHE_KEY_SALT', '$domain:' );" "$wp_config"
    fi
    
    echo -e "${GREEN}Đã sửa lỗi xong!${NC}"
    pause
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
    if [[ -f /etc/redis/redis.conf ]]; then
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
    # Call toggle_extension with an environment variable or flag to auto-select ALL and ON, or just use commands directly
    if ! dpkg -s php-redis &> /dev/null; then
        apt-get update -qq
        apt-get install -y php-redis php8.1-redis php8.2-redis php8.3-redis php8.4-redis 2>/dev/null
    fi
    for v in 8.1 8.2 8.3 8.4; do
        phpenmod -v $v redis 2>/dev/null
        systemctl restart php$v-fpm 2>/dev/null
    done
    
    echo -e "${GREEN}Hoàn tất tối ưu cho Object Cache Pro!${NC}"
    echo -e "Lưu ý: Bạn cần cài đặt plugin Object Cache Pro trong WordPress và điền key bản quyền."
    pause
}

clear_all_cache() {
    log_info "Đang xóa Nginx FastCGI Cache..."
    rm -rf /var/cache/nginx/fastcgi/* /var/run/nginx-cache/* 2>/dev/null
    rm -rf /var/cache/nginx/* 2>/dev/null
    mkdir -p /var/cache/nginx/fastcgi
    chown -R www-data:www-data /var/cache/nginx 2>/dev/null || true
    systemctl reload nginx 2>/dev/null
    
    log_info "Đang Flush Redis..."
    if command -v redis-cli &> /dev/null; then
        redis-cli flushall
    fi
    
    log_info "Đang restart Memcached..."
    systemctl restart memcached 2>/dev/null
    
    log_info "Đang reload PHP-FPM (Clear OPcache)..."
    systemctl reload php*-fpm 2>/dev/null
    
    log_info "Đang xóa thư mục Cache của plugin (WP Rocket, W3TC...)"
    rm -rf /var/www/*/public_html/wp-content/cache/* 2>/dev/null
    
    log_info "Đang Flush Object Cache & Transients bằng WP-CLI..."
    for wp_config in /var/www/*/public_html/wp-config.php; do
        if [[ -f "$wp_config" ]]; then
            site_path=$(dirname "$wp_config")
            wp cache flush --path="$site_path" --allow-root 2>/dev/null
        fi
    done
    
    log_info "Đã xóa sạch Cache hệ thống từ Server."
    pause
}

toggle_extension() {
    local ext=$1
    local versions=()
    local ver_dir ver

    if [[ -d /etc/php ]]; then
        for ver_dir in /etc/php/*/; do
            [[ -d "$ver_dir" ]] || continue
            ver=$(basename "$ver_dir")
            [[ "$ver" =~ ^[0-9]+\.[0-9]+$ ]] && versions+=("$ver")
        done
    fi

    if [[ ${#versions[@]} -eq 0 ]]; then
        versions=(8.4 8.3 8.2 8.1)
    else
        IFS=$'\n' versions=($(printf '%s\n' "${versions[@]}" | sort -rV))
        unset IFS
    fi

    if command -v dpkg >/dev/null 2>&1 && ! dpkg -s "php-$ext" &> /dev/null; then
        echo -e "${YELLOW}Extension php-$ext chưa được cài đặt. Đang cài đặt...${NC}"
        apt-get update -qq
        apt-get install -y "php-$ext" 2>/dev/null || true
    fi

    echo -e "Chọn phiên bản PHP để cấu hình $ext:"
    local idx=1
    for ver in "${versions[@]}"; do
        echo -e "$idx) PHP $ver"
        idx=$((idx + 1))
    done
    echo -e "$idx) Tất cả"
    read -p "Chọn: " v

    if ! [[ "$v" =~ ^[0-9]+$ ]]; then
        return
    fi
    if [[ "$v" -eq "$idx" ]]; then
        ver="all"
    elif [[ "$v" -ge 1 && "$v" -lt "$idx" ]]; then
        ver="${versions[$((v - 1))]}"
    else
        return
    fi

    # Ensure package for selected PHP version exists
    if [[ "$ver" != "all" ]]; then
       if command -v dpkg >/dev/null 2>&1 && ! dpkg -s "php$ver-$ext" &> /dev/null && ! [[ -f "/etc/php/$ver/mods-available/$ext.ini" ]]; then
           echo -e "${YELLOW}Cài đặt thêm php$ver-$ext...${NC}"
           apt-get install -y "php$ver-$ext" 2>/dev/null || true
       fi
    else
       if command -v apt-get >/dev/null 2>&1; then
           for v in "${versions[@]}"; do
               apt-get install -y "php$v-$ext" 2>/dev/null || true
           done
       fi
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
        for v in "${versions[@]}"; do
             $action -v "$v" "$ext" 2>/dev/null || true
             systemctl restart "php$v-fpm" 2>/dev/null || true
        done
    else
        $action -v "$ver" "$ext"
        systemctl restart "php$ver-fpm" 2>/dev/null || true
    fi

    log_info "Đã cấu hình $ext -> $state."
    pause
}

setup_rocket_nginx() {
    log_info "Đang tạo cấu hình Nginx cho WP Rocket..."
    mkdir -p /etc/nginx/snippets
    snippet="/etc/nginx/snippets/wp-rocket.conf"
    
    # 1. Create Safe Snippet (Headers & Expiry) - NO location /
    cat > "$snippet" <<EOF
# WP Rocket Headers
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

    echo -e "${YELLOW}Bạn có muốn tự động áp dụng cấu hình này cho website không?${NC}"
    echo -e "  1. Áp dụng cho TẤT CẢ website WordPress"
    echo -e "  2. Chọn website cụ thể"
    echo -e "  0. Không (Chỉ tạo file snippet)"
    read -p "Chọn: " c

    if [[ "$c" == "0" ]]; then return; fi

    apply_rocket() {
        local domain=$1
        local conf="/etc/nginx/sites-available/$domain"
        if [[ -f "$conf" ]]; then
            if ! grep -q "wp-rocket.conf" "$conf"; then
                sed -i "/server_name/a \    include $snippet;" "$conf"
                log_info "Đã thêm include wp-rocket.conf cho $domain"
            fi
            if grep -q 'try_files \$uri \$uri/ /index.php?\$args;' "$conf"; then
                cp "$conf" "$conf.bak_rocket"
                rocket_path='/wp-content/cache/wp-rocket/$http_host$request_uri/index-https.html /wp-content/cache/wp-rocket/$http_host$request_uri/index.html'
                sed -i "s|try_files \$uri \$uri/ /index.php?\$args;|try_files $rocket_path \$uri \$uri/ /index.php?\$args;|" "$conf"
                log_info "Đã tối ưu try_files cho $domain"
            fi
        fi
    }

    # Chỉ áp dụng cho domain thật: có /var/www/$d/public_html, không phải .bak/.old/000-*
    _is_real_site() {
        local d="$1"
        [[ "$d" == "default" || "$d" == "html" ]] && return 1
        [[ "$d" == 000-* ]] && return 1
        [[ "$d" == *.bak* || "$d" == *.old || "$d" == *.disabled || "$d" == *.bak_* ]] && return 1
        [ -d "/var/www/$d/public_html" ] || return 1
        return 0
    }

    if [[ "$c" == "1" ]]; then
        local applied=0
        local skipped=0
        for conf in /etc/nginx/sites-available/*; do
            d=$(basename "$conf")
            if _is_real_site "$d"; then
                apply_rocket "$d"
                applied=$((applied+1))
            else
                echo -e "  ${YELLOW}Bỏ qua: $d${NC}"
                skipped=$((skipped+1))
            fi
        done
        echo -e "${GREEN}Áp dụng: $applied site | Bỏ qua: $skipped file không hợp lệ${NC}"
        nginx -t && systemctl reload nginx
        log_info "Hoàn tất setup WP Rocket."
    elif [[ "$c" == "2" ]]; then
        source "$(dirname "${BASH_SOURCE[0]}")/site.sh"
        select_site || return
        apply_rocket "$SELECTED_DOMAIN"
        nginx -t && systemctl reload nginx
        log_info "Hoàn tất setup WP Rocket cho $SELECTED_DOMAIN."
    fi

    pause
}

setup_w3tc_nginx() {
    log_info "Đang tạo cấu hình Nginx cho W3 Total Cache..."
    mkdir -p /etc/nginx/snippets
    snippet="/etc/nginx/snippets/w3tc.conf"
    
    cat > "$snippet" <<EOF
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
    
    echo -e "${YELLOW}Bạn có muốn tự động áp dụng cho website?${NC}"
    echo -e "  1. Áp dụng cho TẤT CẢ website WordPress"
    echo -e "  2. Chọn website cụ thể"
    echo -e "  0. Không"
    read -p "Chọn: " c

    if [[ "$c" == "0" ]]; then return; fi

    apply_w3tc() {
        local domain=$1
        local conf="/etc/nginx/sites-available/$domain"
        if [[ -f "$conf" ]]; then
            if ! grep -q "w3tc.conf" "$conf"; then
                sed -i "/server_name/a \    include $snippet;" "$conf"
                log_info "Đã áp dụng W3TC cho $domain"
            fi
        fi
    }

    _is_real_site() {
        local d="$1"
        [[ "$d" == "default" || "$d" == "html" ]] && return 1
        [[ "$d" == 000-* ]] && return 1
        [[ "$d" == *.bak* || "$d" == *.old || "$d" == *.disabled || "$d" == *.bak_* ]] && return 1
        [ -d "/var/www/$d/public_html" ] || return 1
        return 0
    }

    if [[ "$c" == "1" ]]; then
        local applied=0 skipped=0
        for conf in /etc/nginx/sites-available/*; do
            d=$(basename "$conf")
            if _is_real_site "$d"; then
                apply_w3tc "$d"
                applied=$((applied+1))
            else
                echo -e "  ${YELLOW}Bỏ qua: $d${NC}"
                skipped=$((skipped+1))
            fi
        done
        echo -e "${GREEN}Áp dụng: $applied site | Bỏ qua: $skipped file không hợp lệ${NC}"
        nginx -t && systemctl reload nginx
        log_info "Đã áp dụng W3TC toàn hệ thống."
    elif [[ "$c" == "2" ]]; then
        source "$(dirname "${BASH_SOURCE[0]}")/site.sh"
        select_site || return
        apply_w3tc "$SELECTED_DOMAIN"
        nginx -t && systemctl reload nginx

        log_info "Đã áp dụng W3TC cho $SELECTED_DOMAIN."
    fi
    pause
}

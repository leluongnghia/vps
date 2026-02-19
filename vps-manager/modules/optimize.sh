#!/bin/bash

# modules/optimize.sh - System & Server Optimization

optimize_menu() {
    while true; do
        clear
        echo -e "${BLUE}=================================================${NC}"
        echo -e "${GREEN}          Tối ưu hóa Hiệu suất (High Performance)${NC}"
        echo -e "${BLUE}=================================================${NC}"
        echo -e "1. Cài đặt & Cấu hình Redis Object Cache"
        echo -e "2. Bật FastCGI Cache cho Nginx"
        echo -e "3. Tối ưu hóa System (TCP BBR, Swap, Limits)"
        echo -e "4. Cài đặt Brotli Compression (Nginx)"
        echo -e "5. Cài đặt Memcached"
        echo -e "0. Quay lại Menu chính"
        echo -e "${BLUE}=================================================${NC}"
        read -p "Nhập lựa chọn [0-5]: " choice

        case $choice in
            1) install_redis ;;
            2) setup_fastcgi_cache ;;
            3) optimize_system ;;
            4) install_brotli ;;
            5) install_memcached ;;
            0) return ;;
            *) echo -e "${RED}Lựa chọn không hợp lệ!${NC}"; pause ;;
        esac
    done
}

install_memcached() {
    log_info "Đang cài đặt Memcached..."
    apt-get install -y memcached php-memcached libmemcached-tools
    
    systemctl enable memcached
    systemctl restart memcached
    
    log_info "Memcached đã được cài đặt."
    pause
}

install_redis() {
    log_info "Đang cài đặt Redis Server & PHP Extensions..."
    apt-get update
    apt-get install -y redis-server php-redis

    # Tune Redis Config
    log_info "Tối ưu hóa cấu hình Redis (Enable UNIX Socket)..."
    cp /etc/redis/redis.conf /etc/redis/redis.conf.bak
    
    # Enable Unix Socket
    if ! grep -q "unixsocket /var/run/redis/redis-server.sock" /etc/redis/redis.conf; then
        echo "unixsocket /var/run/redis/redis-server.sock" >> /etc/redis/redis.conf
        echo "unixsocketperm 770" >> /etc/redis/redis.conf
    fi

    # Set permissions for socket
    usermod -aG redis www-data
    
    # Set maxmemory and policy
    if ! grep -q "maxmemory 256mb" /etc/redis/redis.conf; then
        echo "maxmemory 256mb" >> /etc/redis/redis.conf
        echo "maxmemory-policy allkeys-lru" >> /etc/redis/redis.conf
    fi

    systemctl restart redis-server
    systemctl enable redis-server

    log_info "Redis đã được cài đặt và tối ưu (Unix Socket: /var/run/redis/redis-server.sock)."
    log_info "Hãy cài plugin 'Redis Object Cache' trong WordPress để kích hoạt."
    pause
}

setup_fastcgi_cache() {
    log_info "Đang cấu hình Nginx FastCGI Cache..."
    
    # Create cache directory
    mkdir -p /var/run/nginx-cache
    chown -R www-data:www-data /var/run/nginx-cache

    # Add cache config to nginx.conf if not present
    if ! grep -q "fastcgi_cache_path" /etc/nginx/nginx.conf; then
        # Insert inside http block is tricky with sed. 
        # Easier strategy: Create a conf.d file
        cat > /etc/nginx/conf.d/fastcgi_cache.conf <<EOF
fastcgi_cache_path /var/run/nginx-cache levels=1:2 keys_zone=WORDPRESS:100m inactive=60m;
fastcgi_cache_key "\$scheme\$request_method\$host\$request_uri";
fastcgi_cache_use_stale error timeout invalid_header http_500;
fastcgi_ignore_headers Cache-Control Expires Set-Cookie;
EOF
        log_info "Đã thêm cấu hình FastCGI Cache Global."
    else
        log_warn "Cấu hình FastCGI Cache có thể đã tồn tại."
    fi

    log_info "LƯU Ý: Mỗi site cần được cấu hình riêng trong file vhost để sử dụng cache."
    # Helper to enable for a site could be added here
    
    nginx -t && systemctl reload nginx
    pause
}

optimize_system() {
    log_info "Đang tối ưu hóa hệ thống..."

    # 1. Enable TCP BBR
    if ! grep -q "net.core.default_qdisc=fq" /etc/sysctl.conf; then
        echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
        echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
        sysctl -p
        log_info "TCP BBR đã được kích hoạt."
    fi

    # 2. Setup Swap (2GB) if not exists
    if [ ! -f /swapfile ]; then
        log_info "Đang tạo Swap file 2GB..."
        fallocate -l 2G /swapfile
        chmod 600 /swapfile
        mkswap /swapfile
        swapon /swapfile
        echo "/swapfile none swap sw 0 0" >> /etc/fstab
        
        # Optimize Swapiness
        echo "vm.swappiness=10" >> /etc/sysctl.conf
        echo "vm.vfs_cache_pressure=50" >> /etc/sysctl.conf
        sysctl -p
        log_info "Swap 2GB đã được tạo."
    else
        log_info "Swap file đã tồn tại."
    fi

    # 3. Increase File Limits
    if ! grep -q "fs.file-max" /etc/sysctl.conf; then
        echo "fs.file-max = 2097152" >> /etc/sysctl.conf
        sysctl -p
    fi
    
    pause
}

install_brotli() {
    log_info "Đang cài đặt Nginx Brotli module..."
    
    if nginx -V 2>&1 | grep -qi "brotli"; then
        echo -e "${GREEN}Module Brotli đã có sẵn trong Nginx.${NC}"
    else
        echo -e "${YELLOW}Module Brotli chưa có. Đang thử cài đặt từ Repository...${NC}"
        
        # 1. Try standard apt install first
        apt-get update -qq
        if apt-get install -y libnginx-mod-http-brotli 2>/dev/null; then
            log_info "Đã cài libnginx-mod-http-brotli từ repo mặc định."
        else
            echo -e "${YELLOW}Repo mặc định không có. Bạn có muốn thêm PPA Ondrej/Nginx (Stable) không?${NC}"
            echo "Việc này sẽ cập nhật Nginx lên phiên bản mới nhất hỗ trợ Brotli."
            read -p "Đồng ý? [y/N]: " agreemma
            if [[ "$agreemma" == "y" || "$agreemma" == "Y" ]]; then
                apt-get install -y software-properties-common
                add-apt-repository -y ppa:ondrej/nginx
                apt-get update
                apt-get install -y nginx libnginx-mod-http-brotli
                log_info "Đã thêm PPA và cài đặt Nginx + Brotli."
            else
                log_warn "Đã hủy cài đặt Brotli."
                return
            fi
        fi
    fi
    
    # Configure Brotli with Safety Check
    echo -e "${CYAN}Đang cấu hình và kiểm tra Brotli...${NC}"
    local conf_file="/etc/nginx/conf.d/brotli.conf"
    
    # Create valid config content
    cat > "$conf_file" <<EOF
brotli on;
brotli_comp_level 6;
brotli_static on;
brotli_types text/plain text/css application/javascript application/x-javascript text/xml application/xml application/xml+rss text/javascript image/x-icon image/vnd.microsoft.icon image/bmp image/svg+xml;
EOF

    # STRICT TEST
    if nginx -t; then
        systemctl restart nginx
        log_info "✅ Brotli compression đã được kích hoạt thành công!"
    else
        log_error "Nginx không hỗ trợ Brotli (Test failed). Đang gỡ bỏ cấu hình..."
        rm -f "$conf_file"
        systemctl restart nginx
        echo -e "${RED}Đã khôi phục Nginx về trạng thái cũ. Không thể bật Brotli trên hệ thống này.${NC}"
    fi
    pause
}

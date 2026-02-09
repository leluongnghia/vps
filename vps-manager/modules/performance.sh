#!/bin/bash

# modules/performance.sh - System & Web Performance Tuning

performance_menu() {
    clear
    echo -e "${BLUE}=================================================${NC}"
    echo -e "${GREEN}          Tối ưu hóa Hiệu năng (Speed)${NC}"
    echo -e "${BLUE}=================================================${NC}"
    echo -e "1. Bật nén Gzip & Browser Caching (Nginx)"
    echo -e "2. Tối ưu hóa PHP Opcache"
    echo -e "3. Tối ưu hóa MySQL (InnoDB Buffer Pool)"
    echo -e "0. Quay lại Menu chính"
    echo -e "${BLUE}=================================================${NC}"
    read -p "Nhập lựa chọn [0-3]: " choice

    case $choice in
        1) enable_gzip_cache ;;
        2) optimize_opcache ;;
        3) optimize_mysql ;;
        0) return ;;
        *) echo -e "${RED}Lựa chọn không hợp lệ!${NC}"; pause ;;
    esac
}

enable_gzip_cache() {
    log_info "Đang cấu hình Gzip & Cache Headers..."
    
    cat > /etc/nginx/conf.d/gzip.conf <<EOF
gzip on;
gzip_disable "msie6";
gzip_vary on;
gzip_proxied any;
gzip_comp_level 6;
gzip_buffers 16 8k;
gzip_http_version 1.1;
gzip_types text/plain text/css application/json application/javascript text/xml application/xml application/xml+rss text/javascript image/svg+xml;
EOF

    cat > /etc/nginx/conf.d/cache_headers.conf <<EOF
location ~* \.(jpg|jpeg|gif|png|ico|svg|css|js|woff|woff2)$ {
    expires 365d;
    add_header Cache-Control "public, no-transform";
}
EOF

    nginx -t && systemctl reload nginx
    log_info "Đã bật Gzip và Browser Caching (Expires 365d)."
    pause
}

optimize_opcache() {
    log_info "Đang tối ưu Opcache cho PHP..."
    
    # Apply to all php ver
    for ver in 8.1 8.2 8.3; do
        if [ -d "/etc/php/$ver/fpm/conf.d" ]; then
            cat > /etc/php/$ver/fpm/conf.d/99-opcache-optimization.ini <<EOF
opcache.enable=1
opcache.memory_consumption=256
opcache.interned_strings_buffer=16
opcache.max_accelerated_files=10000
opcache.revalidate_freq=0
opcache.validate_timestamps=0
EOF
            systemctl restart php$ver-fpm
            log_info "Đã tối ưu Opcache cho PHP $ver"
        fi
    done
    
    log_info "Lưu ý: validate_timestamps=0 có nghĩa là bạn cần restart PHP khi sửa code PHP, nhưng tốc độ sẽ nhanh nhất."
    pause
}

optimize_mysql() {
    log_info "Đang tính toán InnoDB Buffer Pool..."
    
    total_ram=$(free -m | awk '/Mem:/ {print $2}')
    # Set buffer pool to 50% of RAM
    pool_size=$((total_ram / 2))
    
    if [ ! -f /etc/mysql/conf.d/optimization.cnf ]; then
        echo "[mysqld]" > /etc/mysql/conf.d/optimization.cnf
    fi
    
    # Simple replacement or append
    sed -i '/innodb_buffer_pool_size/d' /etc/mysql/conf.d/optimization.cnf
    echo "innodb_buffer_pool_size = ${pool_size}M" >> /etc/mysql/conf.d/optimization.cnf
    
    systemctl restart mariadb
    log_info "Đã thiết lập InnoDB Buffer Pool = ${pool_size}MB"
    pause
}

install_brotli() {
    log_info "Tính năng Brotli đang được phát triển..."
    # Requires apt install nginx-brotli or compiling module.
    # Easy way: apt install brotli, but connecting to nginx requires module.
    pause
}

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
    
    # 0. Emergency Cleanup & Recovery
    # Remove files known to cause issues
    rm -f /etc/nginx/conf.d/cache_headers.conf
    rm -f /etc/nginx/conf.d/gzip.conf
    rm -f /etc/nginx/conf.d/browser_caching.conf
    
    # Check if nginx is dead, try to revive
    if ! systemctl is-active --quiet nginx; then
        log_warn "Nginx đang lỗi. Đang cố gắng khôi phục..."
        systemctl restart nginx
    fi

    # 1. Aggressively remove default gzip from nginx.conf
    if [ -f /etc/nginx/nginx.conf ]; then
        cp /etc/nginx/nginx.conf /etc/nginx/nginx.conf.bak
        # Remove 'gzip on;' line (delete line containing gzip on;)
        sed -i '/^\s*gzip\s\+on;/d' /etc/nginx/nginx.conf
        # Also comment out gzip_disable if present default
        sed -i 's/^\s*gzip_disable/#gzip_disable/' /etc/nginx/nginx.conf
        
        log_info "Đã loại bỏ cấu hình Gzip mặc định (Backup tại nginx.conf.bak)"
    fi
    
    # 2. Create optimized Gzip config
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

    # Create snippet for browser caching (to be included in server blocks)
    mkdir -p /etc/nginx/snippets
    cat > /etc/nginx/snippets/browser_caching.conf <<EOF
location ~* \.(jpg|jpeg|gif|png|ico|svg|css|js|woff|woff2|ttf|eot)$ {
    expires 365d;
    add_header Cache-Control "public, no-transform";
    access_log off;
}
EOF

    # Test & Reload
    log_info "Kiểm tra cấu hình Nginx..."
    if nginx -t; then
        systemctl reload nginx
        log_info "Đã kích hoạt Gzip & Cache thành công!"
    else
        log_warn "Cấu hình Nginx lỗi! Đang khôi phục..."
        # Restore main config
        cp /etc/nginx/nginx.conf.bak /etc/nginx/nginx.conf
        rm -f /etc/nginx/conf.d/gzip.conf
        systemctl restart nginx
        echo -e "${RED}Đã khôi phục trạng thái cũ do lỗi config. Vui lòng kiểm tra log.${NC}"
    fi
    
    log_info "Snippet Browser Caching tại: /etc/nginx/snippets/browser_caching.conf"
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

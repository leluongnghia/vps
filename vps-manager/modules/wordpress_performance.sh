#!/bin/bash

# modules/wordpress_performance.sh - WordPress Performance Optimization

# Helper: Get installed PHP version with fallback
get_installed_php_version() {
    local php_ver=$(php -r "echo PHP_MAJOR_VERSION.'.'.PHP_MINOR_VERSION;" 2>/dev/null)
    
    # Check if config exists for detected version
    if [ -d "/etc/php/${php_ver}" ]; then
        echo "$php_ver"
        return 0
    fi
    
    # Fallback: Find installed PHP versions
    for ver in 8.4 8.3 8.2 8.1 8.0 7.4; do
        if [ -d "/etc/php/${ver}" ]; then
            echo "$ver"
            return 0
        fi
    done
    
    # Last resort: return detected version anyway
    echo "$php_ver"
    return 1
}

wp_performance_menu() {
    while true; do
        clear
        echo -e "${BLUE}=================================================${NC}"
        echo -e "${GREEN}    🚀 WordPress Performance Optimization${NC}"
        echo -e "${BLUE}=================================================${NC}"
        echo -e "${CYAN}--- ⚙️  Server-level (Toàn bộ server) ---${NC}"
        echo -e "1. 🚀 Auto-Optimize Server (PHP + MySQL + Nginx + OPcache)"
        echo -e "2. ⚡ PHP-FPM Tuning (Memory, Workers)"
        echo -e "3. 💾 OPcache Optimization"
        echo -e "4. 🗄️  MySQL/MariaDB Tuning"
        echo -e "5. 🔥 Nginx FastCGI Micro-Caching"
        echo -e "6. 📦 Enable Object Cache (Redis/Memcached)"
        echo -e "7. 🌐 HTTP/2 & Brotli Compression"
        echo -e ""
        echo -e "${CYAN}--- 🌐 Per-Site (Chọn từng website) ---${NC}"
        echo -e "8.  🧹 Database Cleanup & Optimization"
        echo -e "9.  🎯 Disable WordPress Bloat (Heartbeat, Embeds...)"
        echo -e "10. 🖼️  Image Optimization Setup"
        echo -e "11. 📊 Performance Benchmark Test"
        echo -e ""
        echo -e "0. Back to Main Menu"
        echo -e "${BLUE}=================================================${NC}"
        read -p "Select [0-11]: " choice

        case $choice in
            1) auto_optimize_server ;;
            2) tune_php_fpm ;;
            3) optimize_opcache ;;
            4) tune_mysql ;;
            5) setup_fastcgi_microcache ;;
            6) setup_object_cache ;;
            7) enable_http2_brotli ;;
            8) cleanup_wordpress_db ;;
            9) disable_wordpress_bloat ;;
            10) setup_image_optimization ;;
            11) benchmark_wordpress ;;
            0) return ;;
            *) echo -e "${RED}Invalid choice!${NC}"; pause ;;
        esac
    done
}

# 1. Auto-Optimize SERVER (server-level settings only, NOT per-site)
auto_optimize_server() {
    clear
    echo -e "${BLUE}=================================================${NC}"
    echo -e "${GREEN}    🚀 Auto-Optimize Server${NC}"
    echo -e "${BLUE}=================================================${NC}"
    echo -e "${CYAN}Các cài đặt này áp dụng cho TOÀN BỘ server${NC}"
    echo -e "(Không đụng vào wp-config.php của bất kỳ site nào)"
    echo ""
    echo -e "Đị sẽ tối ưu:"
    echo "  ✓ PHP-FPM (workers, memory dựa theo RAM thực tế)"
    echo "  ✓ OPcache + JIT compilation"
    echo "  ✓ MySQL/MariaDB InnoDB buffer (50% RAM)"
    echo "  ✓ Nginx FastCGI Cache zone (100MB)"
    echo ""
    echo -e "${YELLOW}Không ảnh hưởng đến:${NC}"
    echo "  ✓ wp-config.php → dùng Option 9 cho từng site"
    echo "  ✓ Database WordPress → dùng Option 8 cho từng site"
    echo ""
    read -p "Tiếp tục? [y/N]: " confirm
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then return; fi

    tune_php_fpm "auto"
    optimize_opcache "auto"
    tune_mysql "auto"
    setup_fastcgi_microcache "auto"

    echo ""
    log_info "✅ Server optimization complete!"
    echo -e "${YELLOW}Bước tiếp theo (per-site):${NC}"
    echo "  → Option 8: Dọn Database từng site"
    echo "  → Option 9: Tắt Bloat từng site"
    echo "  → Option 11: Benchmark từng site"
    pause
}

# 2. PHP-FPM Tuning
tune_php_fpm() {
    local auto_mode=$1
    log_info "Tuning PHP-FPM for WordPress..."
    
    # Detect PHP version
    local php_ver=$(get_installed_php_version)
    local fpm_conf="/etc/php/${php_ver}/fpm/pool.d/www.conf"
    
    if [ ! -f "$fpm_conf" ]; then
        log_error "PHP-FPM config not found for PHP $php_ver"
        return 1
    fi
    
    # Backup original
    cp "$fpm_conf" "${fpm_conf}.bak_$(date +%s)"
    
    # Calculate optimal settings based on RAM
    local total_ram=$(free -m | awk '/^Mem:/{print $2}')
    local max_children=$((total_ram / 50))  # ~50MB per child
    local start_servers=$((max_children / 4))
    local min_spare=$((max_children / 4))
    local max_spare=$((max_children / 2))
    
    # Apply optimizations
    sed -i "s/^pm = .*/pm = dynamic/" "$fpm_conf"
    sed -i "s/^pm.max_children = .*/pm.max_children = $max_children/" "$fpm_conf"
    sed -i "s/^pm.start_servers = .*/pm.start_servers = $start_servers/" "$fpm_conf"
    sed -i "s/^pm.min_spare_servers = .*/pm.min_spare_servers = $min_spare/" "$fpm_conf"
    sed -i "s/^pm.max_spare_servers = .*/pm.max_spare_servers = $max_spare/" "$fpm_conf"
    sed -i "s/^;pm.max_requests = .*/pm.max_requests = 500/" "$fpm_conf"
    
    # Increase memory limit for WordPress
    local php_ini="/etc/php/${php_ver}/fpm/php.ini"
    sed -i "s/^memory_limit = .*/memory_limit = 256M/" "$php_ini"
    sed -i "s/^max_execution_time = .*/max_execution_time = 300/" "$php_ini"
    sed -i "s/^upload_max_filesize = .*/upload_max_filesize = 64M/" "$php_ini"
    sed -i "s/^post_max_size = .*/post_max_size = 64M/" "$php_ini"
    
    systemctl restart php${php_ver}-fpm
    
    log_info "PHP-FPM optimized for ${total_ram}MB RAM"
    echo -e "${GREEN}Settings: max_children=$max_children, start=$start_servers${NC}"
    
    if [ -z "$auto_mode" ]; then pause; fi
}

# 3. OPcache Optimization
optimize_opcache() {
    local auto_mode=$1
    log_info "Optimizing OPcache for maximum performance..."
    
    local php_ver=$(get_installed_php_version)
    local opcache_ini="/etc/php/${php_ver}/fpm/conf.d/10-opcache.ini"
    
    # Aggressive OPcache settings for WordPress
    cat > "$opcache_ini" <<EOF
; OPcache Optimization for WordPress
zend_extension=opcache.so
opcache.enable=1
opcache.enable_cli=0
opcache.memory_consumption=256
opcache.interned_strings_buffer=16
opcache.max_accelerated_files=10000
opcache.max_wasted_percentage=5
opcache.use_cwd=1
opcache.validate_timestamps=0
opcache.revalidate_freq=0
opcache.save_comments=1
opcache.fast_shutdown=1
opcache.enable_file_override=1
opcache.optimization_level=0x7FFEBFFF
opcache.jit=1255
opcache.jit_buffer_size=128M
EOF
    
    systemctl restart php${php_ver}-fpm
    
    log_info "OPcache optimized with JIT compilation"
    echo -e "${YELLOW}Note: Set opcache.validate_timestamps=1 in development${NC}"
    
    if [ -z "$auto_mode" ]; then pause; fi
}

# 4. MySQL/MariaDB Tuning
tune_mysql() {
    local auto_mode=$1
    log_info "Tuning MySQL/MariaDB for WordPress..."
    
    local mysql_conf="/etc/mysql/mariadb.conf.d/50-server.cnf"
    if [ ! -f "$mysql_conf" ]; then
        mysql_conf="/etc/mysql/my.cnf"
    fi
    
    # Backup
    cp "$mysql_conf" "${mysql_conf}.bak_$(date +%s)"
    
    # Calculate based on RAM
    local total_ram=$(free -m | awk '/^Mem:/{print $2}')
    local innodb_buffer=$((total_ram / 2))  # 50% of RAM
    
    # Add optimizations to [mysqld] section
    if ! grep -q "# WordPress Optimizations" "$mysql_conf"; then
        cat >> "$mysql_conf" <<EOF

# WordPress Optimizations
[mysqld]
innodb_buffer_pool_size = ${innodb_buffer}M
innodb_log_file_size = 256M
innodb_flush_log_at_trx_commit = 2
innodb_flush_method = O_DIRECT
query_cache_type = 1
query_cache_limit = 2M
query_cache_size = 64M
max_connections = 200
thread_cache_size = 50
table_open_cache = 4000
tmp_table_size = 64M
max_heap_table_size = 64M
EOF
    fi
    
    systemctl restart mysql
    
    log_info "MySQL optimized with ${innodb_buffer}MB InnoDB buffer"
    
    if [ -z "$auto_mode" ]; then pause; fi
}

# 5. Nginx FastCGI Micro-Caching
setup_fastcgi_microcache() {
    local auto_mode=$1
    log_info "Setting up Nginx FastCGI micro-caching..."
    
    # Create cache directory
    mkdir -p /var/run/nginx-cache
    chown -R www-data:www-data /var/run/nginx-cache
    
    # Global cache config (if not exists)
    if [ ! -f /etc/nginx/conf.d/fastcgi_cache.conf ]; then
        cat > /etc/nginx/conf.d/fastcgi_cache.conf <<EOF
# FastCGI Cache Configuration
fastcgi_cache_path /var/run/nginx-cache levels=1:2 keys_zone=WORDPRESS:100m inactive=60m max_size=1g;
fastcgi_cache_key "\$scheme\$request_method\$host\$request_uri";
fastcgi_cache_use_stale error timeout invalid_header http_500 http_503;
fastcgi_cache_valid 200 301 302 60m;
fastcgi_cache_valid 404 10m;
fastcgi_ignore_headers Cache-Control Expires Set-Cookie;
EOF
    fi
    
    log_info "FastCGI cache configured (100MB zone, 1GB max)"
    echo -e "${YELLOW}Cache is already applied to sites via create_nginx_config${NC}"
    
    if [ -z "$auto_mode" ]; then pause; fi
}

# 8. Database Cleanup
cleanup_wordpress_db() {
    clear
    echo -e "${BLUE}=================================================${NC}"
    echo -e "${GREEN}     🧹 Database Cleanup & Optimization${NC}"
    echo -e "${BLUE}=================================================${NC}"
    echo -e "Phạm vi áp dụng:"
    echo -e "  1. Chọn 1 website cụ thể"
    echo -e "  2. Áp dụng cho TẤT CẢ WordPress sites"
    echo -e "  0. Hủy"
    read -p "Chọn: " scope

    case $scope in
        1)
            source "$(dirname "${BASH_SOURCE[0]}")/wordpress_tool.sh"
            select_wp_site || return
            ensure_wp_cli
            _do_db_cleanup "$SELECTED_DOMAIN"
            ;;
        2)
            echo -e "${YELLOW}Sẽ dọn database TẤT CẢ WordPress sites:${NC}"
            local found=0
            for d in /var/www/*/public_html/wp-config.php; do
                [ ! -f "$d" ] && continue
                local domain
                domain=$(basename "$(dirname "$(dirname "$d")")")
                echo "  → $domain"
                found=$((found+1))
            done
            [ "$found" -eq 0 ] && echo -e "${RED}Không có site WordPress nào.${NC}" && pause && return
            echo ""
            read -p "Tiếp tục dọn $found site? [y/N]: " c
            [[ "$c" != "y" && "$c" != "Y" ]] && return
            for d in /var/www/*/public_html/wp-config.php; do
                [ ! -f "$d" ] && continue
                local domain
                domain=$(basename "$(dirname "$(dirname "$d")")")
                _do_db_cleanup "$domain"
            done
            ;;
        0) return ;;
    esac
    pause
}

_do_db_cleanup() {
    local domain=$1
    local WEB_ROOT="/var/www/$domain/public_html"
    local WP_CMD="wp --path=$WEB_ROOT --allow-root"

    if [ ! -f "$WEB_ROOT/wp-config.php" ]; then
        echo -e "${RED}$domain không phải WordPress site.${NC}"
        return
    fi

    log_info "Dọn database: $domain"
    $WP_CMD transient delete --all 2>/dev/null && echo "  ✓ Transients"
    local rev_ids
    rev_ids=$($WP_CMD post list --post_type='revision' --format=ids 2>/dev/null)
    [ -n "$rev_ids" ] && $WP_CMD post delete $rev_ids --force 2>/dev/null && echo "  ✓ Revisions"
    local spam_ids
    spam_ids=$($WP_CMD comment list --status=spam --format=ids 2>/dev/null)
    [ -n "$spam_ids" ] && $WP_CMD comment delete $spam_ids --force 2>/dev/null && echo "  ✓ Spam"
    local trash_ids
    trash_ids=$($WP_CMD comment list --status=trash --format=ids 2>/dev/null)
    [ -n "$trash_ids" ] && $WP_CMD comment delete $trash_ids --force 2>/dev/null && echo "  ✓ Trash"
    $WP_CMD db optimize 2>/dev/null && echo "  ✓ DB Optimized"
    log_info "✅ $domain: Database cleaned"
}

# 7. Object Cache Setup
setup_object_cache() {
    echo -e "${YELLOW}Select Object Cache Backend:${NC}"
    echo "1. Redis (Recommended)"
    echo "2. Memcached"
    echo "0. Cancel"
    read -p "Choice: " cache_choice
    
    case $cache_choice in
        1)
            # Install Redis
            if ! command -v redis-server &>/dev/null; then
                log_info "Installing Redis..."
                apt-get update -qq
                apt-get install -y redis-server
                systemctl enable redis-server
                systemctl start redis-server
            fi
            
            # Install PHP Redis extension
            local php_ver=$(get_installed_php_version)
            apt-get install -y php${php_ver}-redis
            phpenmod -v ${php_ver} redis
            systemctl restart php${php_ver}-fpm
            
            log_info "Redis installed and enabled"
            echo -e "${GREEN}Install 'Redis Object Cache' plugin in WordPress${NC}"
            ;;
        2)
            # Install Memcached
            if ! command -v memcached &>/dev/null; then
                log_info "Installing Memcached..."
                apt-get update -qq
                apt-get install -y memcached
                systemctl enable memcached
                systemctl start memcached
            fi
            
            # Install PHP Memcached extension
            local php_ver=$(get_installed_php_version)
            apt-get install -y php${php_ver}-memcached
            phpenmod -v ${php_ver} memcached
            systemctl restart php${php_ver}-fpm
            
            log_info "Memcached installed and enabled"
            echo -e "${GREEN}Install 'Memcached Object Cache' plugin in WordPress${NC}"
            ;;
    esac
    pause
}

# 9. Disable WordPress Bloat
disable_wordpress_bloat() {
    clear
    echo -e "${BLUE}=================================================${NC}"
    echo -e "${GREEN}     🎯 Disable WordPress Bloat${NC}"
    echo -e "${BLUE}=================================================${NC}"
    echo -e "Sẽ tắt: Heartbeat limits, Embeds, Post Revisions (wp-config.php)"
    echo ""
    echo -e "Phạm vi áp dụng:"
    echo -e "  1. Chọn 1 website cụ thể"
    echo -e "  2. Áp dụng cho TẤT CẢ WordPress sites"
    echo -e "  0. Hủy"
    read -p "Chọn: " scope

    case $scope in
        1)
            source "$(dirname "${BASH_SOURCE[0]}")/wordpress_tool.sh"
            select_wp_site || return
            ensure_wp_cli
            _do_disable_bloat "$SELECTED_DOMAIN"
            ;;
        2)
            echo -e "${YELLOW}Áp dụng cho TẤT CẢ WordPress sites:${NC}"
            local found=0
            for d in /var/www/*/public_html/wp-config.php; do
                [ ! -f "$d" ] && continue
                local domain
                domain=$(basename "$(dirname "$(dirname "$d")")")
                echo "  → $domain"
                found=$((found+1))
            done
            [ "$found" -eq 0 ] && echo -e "${RED}Không có site WordPress nào.${NC}" && pause && return
            echo ""
            read -p "Tiếp tục cho $found site? [y/N]: " c
            [[ "$c" != "y" && "$c" != "Y" ]] && return
            for d in /var/www/*/public_html/wp-config.php; do
                [ ! -f "$d" ] && continue
                local domain
                domain=$(basename "$(dirname "$(dirname "$d")")")
                _do_disable_bloat "$domain"
            done
            ;;
        0) return ;;
    esac
    pause
}

_do_disable_bloat() {
    local domain=$1
    local WEB_ROOT="/var/www/$domain/public_html"
    local WP_CMD="wp --path=$WEB_ROOT --allow-root"

    if [ ! -f "$WEB_ROOT/wp-config.php" ]; then
        echo -e "${RED}$domain không phải WordPress site.${NC}"
        return
    fi

    log_info "Disable Bloat: $domain"
    $WP_CMD config set WP_POST_REVISIONS 3 --raw --type=constant 2>/dev/null && echo "  ✓ Revisions limit = 3"
    $WP_CMD config set AUTOSAVE_INTERVAL 300 --raw --type=constant 2>/dev/null && echo "  ✓ Autosave = 5 phút"
    $WP_CMD config set EMPTY_TRASH_DAYS 7 --raw --type=constant 2>/dev/null && echo "  ✓ Trash = 7 ngày"
    $WP_CMD config set WP_CRON_LOCK_TIMEOUT 60 --raw --type=constant 2>/dev/null && echo "  ✓ Cron timeout"
    log_info "✅ $domain: Bloat disabled"
    echo -e "${YELLOW}Gợi ý: Dùng plugin (Perfmatters / Asset CleanUp) để tắt Heartbeat, Embeds per-page${NC}"
}


# 9. Image Optimization Setup
setup_image_optimization() {
    echo -e "${GREEN}Image Optimization Recommendations:${NC}"
    echo ""
    echo "1. Install 'Imagify' or 'ShortPixel' plugin"
    echo "2. Enable WebP conversion"
    echo "3. Set compression level to 'Aggressive'"
    echo "4. Enable lazy loading"
    echo ""
    echo -e "${YELLOW}Server-side WebP support:${NC}"
    
    # Install WebP support
    local php_ver=$(get_installed_php_version)
    apt-get install -y php${php_ver}-gd webp
    
    log_info "WebP support installed"
    echo -e "${GREEN}You can now use WebP images in WordPress${NC}"
    pause
}

# 10. HTTP/2 & Brotli
enable_http2_brotli() {
    log_info "Enabling HTTP/2 and Brotli compression..."
    
    # Check if Nginx supports HTTP/2
    if nginx -V 2>&1 | grep -q "http_v2"; then
        log_info "HTTP/2 already supported"
    else
        log_warn "Nginx doesn't support HTTP/2. Upgrade Nginx first."
    fi
    
    # Install Brotli module
    if ! nginx -V 2>&1 | grep -q "brotli"; then
        log_warn "Brotli module not compiled. Using gzip only."
    fi
    
    # Enable Brotli in Nginx
    cat > /etc/nginx/conf.d/brotli.conf <<EOF
# Brotli Compression
brotli on;
brotli_comp_level 6;
brotli_types text/plain text/css text/xml text/javascript application/x-javascript application/javascript application/xml+rss application/json image/svg+xml;
EOF
    
    nginx -t && systemctl reload nginx
    
    log_info "Compression optimized"
    echo -e "${YELLOW}Note: HTTP/2 requires SSL certificate${NC}"
    pause
}

# 11. Benchmark Test
benchmark_wordpress() {
    source "$(dirname "${BASH_SOURCE[0]}")/wordpress_tool.sh"
    select_wp_site || return
    
    local url="https://$SELECTED_DOMAIN"
    
    echo -e "${YELLOW}Running performance benchmark...${NC}"
    echo ""
    
    # Test with curl
    echo "Testing response time..."
    local response_time=$(curl -o /dev/null -s -w '%{time_total}\n' "$url")
    echo -e "Response Time: ${GREEN}${response_time}s${NC}"
    
    # Test with ab (if available)
    if command -v ab &>/dev/null; then
        echo ""
        echo "Running Apache Bench (100 requests, 10 concurrent)..."
        ab -n 100 -c 10 "$url/" 2>/dev/null | grep -E "Requests per second|Time per request"
    fi
    
    echo ""
    echo -e "${YELLOW}Recommended tools for detailed testing:${NC}"
    echo "  • GTmetrix (https://gtmetrix.com)"
    echo "  • Google PageSpeed Insights"
    echo "  • WebPageTest.org"
    pause
}

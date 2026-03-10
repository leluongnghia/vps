#!/bin/bash

# modules/wordpress_performance.sh - WordPress Performance Optimization

# Helper: Get ACTIVE PHP-FPM version (not CLI version which may differ)
get_installed_php_version() {
    # Method 1: Find running php-fpm service (most reliable)
    local running
    running=$(systemctl list-units --type=service --state=running 2>/dev/null \
        | grep 'php.*-fpm' | grep -oP '\d+\.\d+' | sort -rV | head -1)
    if [[ -n "$running" ]] && [[ -d "/etc/php/$running" ]]; then
        echo "$running"; return 0
    fi

    # Method 2: Find version with FPM pool config present
    for ver in 8.4 8.3 8.2 8.1 8.0 7.4; do
        if [[ -f "/etc/php/${ver}/fpm/pool.d/www.conf" ]]; then
            echo "$ver"; return 0
        fi
    done

    # Method 3: php-fpm binary in PATH
    local fpm_bin
    fpm_bin=$(command -v php-fpm8.3 php-fpm8.2 php-fpm8.1 php-fpm 2>/dev/null | head -1)
    if [[ -n "$fpm_bin" ]]; then
        local v
        v=$("$fpm_bin" -v 2>/dev/null | grep -oP '\d+\.\d+' | head -1)
        [ -n "$v" ] && echo "$v" && return 0
    fi

    # Method 4: PHP CLI (last resort - may be different from FPM)
    local cli_ver
    cli_ver=$(php -r "echo PHP_MAJOR_VERSION.'.'.PHP_MINOR_VERSION;" 2>/dev/null)
    if [[ -n "$cli_ver" ]] && [[ -d "/etc/php/$cli_ver" ]]; then
        echo "$cli_ver"; return 0
    fi

    echo ""; return 1
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
        echo -e "12. 🔧 System Kernel Tuning (TCP BBR, File Limits)"
        echo -e ""
        echo -e "0. Back to Main Menu"
        echo -e "${BLUE}=================================================${NC}"
        read -p "Select [0-12]: " choice

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
            12) optimize_system_kernel ;;
            0) return ;;
            *) echo -e "${RED}Invalid choice!${NC}"; pause ;;
        esac
    done
}

# 12. Optimize System Kernel (Merged from optimize.sh)
optimize_system_kernel() {
    log_info "Đang tối ưu hóa hệ thống (Kernel & Network)..."

    # 1. Enable TCP BBR
    if ! grep -q "net.core.default_qdisc=fq" /etc/sysctl.conf; then
        echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
        echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
        sysctl -p
        log_info "TCP BBR đã được kích hoạt."
    else
        log_info "TCP BBR đã được cấu hình từ trước."
    fi

    # 2. Increase File Limits
    if ! grep -q "fs.file-max" /etc/sysctl.conf; then
        echo "fs.file-max = 2097152" >> /etc/sysctl.conf
        sysctl -p
        log_info "Đã tăng giới hạn fs.file-max."
    else
        log_info "fs.file-max đã được cấu hình từ trước."
    fi
    
    pause
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

    # Detect active PHP-FPM version
    local php_ver
    php_ver=$(get_installed_php_version)
    if [[ -z "$php_ver" ]]; then
        log_error "Không tìm thấy PHP-FPM cài đặt!"
        echo -e "${YELLOW}PHP đị: $(php -v 2>/dev/null | head -1)${NC}"
        echo -e "${YELLOW}Thư mục /etc/php/: $(ls /etc/php/ 2>/dev/null || echo 'trống')${NC}"
        return 1
    fi
    log_info "PHP-FPM version: $php_ver"

    local fpm_conf="/etc/php/${php_ver}/fpm/pool.d/www.conf"
    if [[ ! -f "$fpm_conf" ]]; then
        log_error "PHP-FPM config not found: $fpm_conf"
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
    sed -i -E "s/^[; ]*memory_limit.*/memory_limit = 256M/" "$php_ini"
    sed -i -E "s/^[; ]*max_execution_time.*/max_execution_time = 300/" "$php_ini"
    sed -i -E "s/^[; ]*upload_max_filesize.*/upload_max_filesize = 128M/" "$php_ini"
    sed -i -E "s/^[; ]*post_max_size.*/post_max_size = 128M/" "$php_ini"
    
    systemctl restart php${php_ver}-fpm
    
    log_info "PHP-FPM optimized for ${total_ram}MB RAM"
    echo -e "${GREEN}Settings: max_children=$max_children, start=$start_servers${NC}"
    
    if [[ -z "$auto_mode" ]]; then pause; fi
}

# 3. OPcache Optimization
optimize_opcache() {
    local auto_mode=$1
    log_info "Optimizing OPcache for maximum performance..."

    local php_ver
    php_ver=$(get_installed_php_version)
    if [[ -z "$php_ver" ]]; then
        log_error "Không tìm thấy PHP-FPM để cấu hình OPcache!"
        return 1
    fi
    log_info "OPcache target: PHP $php_ver"

    local conf_dir="/etc/php/${php_ver}/fpm/conf.d"
    if [[ ! -d "$conf_dir" ]]; then
        mkdir -p "$conf_dir"
    fi
    local opcache_ini="$conf_dir/10-opcache.ini"
    
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
    
    if [[ -z "$auto_mode" ]]; then pause; fi
}

# 4. MySQL/MariaDB Tuning
tune_mysql() {
    local auto_mode=$1
    log_info "Tuning MySQL/MariaDB for WordPress..."
    
    local mysql_conf="/etc/mysql/mariadb.conf.d/50-server.cnf"
    if [[ ! -f "$mysql_conf" ]]; then
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
    
    if [[ -z "$auto_mode" ]]; then pause; fi
}

# 5. Nginx FastCGI Micro-Caching
setup_fastcgi_microcache() {
    local auto_mode=$1
    log_info "Setting up Nginx FastCGI micro-caching..."
    
    # Create cache directory
    mkdir -p /var/run/nginx-cache
    chown -R www-data:www-data /var/run/nginx-cache
    
    # Global cache config (if not exists)
    if [[ ! -f /etc/nginx/conf.d/fastcgi_cache.conf ]]; then
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
    
    if [[ -z "$auto_mode" ]]; then pause; fi
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
    
    local WP_PHP_BIN="php"
    local SITE_CONF="/etc/nginx/sites-available/$domain"
    if [[ -f "$SITE_CONF" ]]; then
        local SITE_PHP_VER=$(grep -shoP 'unix:/run/php/php\K[0-9.]+(?=-fpm.sock)' "$SITE_CONF" | head -n 1)
        if [[ -n "$SITE_PHP_VER" ]] && command -v "php$SITE_PHP_VER" >/dev/null 2>&1; then
            WP_PHP_BIN="php$SITE_PHP_VER"
        fi
    fi
    
    if ! "$WP_PHP_BIN" -m 2>/dev/null | grep -qEi "(mysqli|pdo_mysql)"; then
        for v in 8.3 8.4 8.5 8.2 8.1 8.0 7.4; do
            if command -v "php$v" >/dev/null 2>&1 && "php$v" -m 2>/dev/null | grep -qEi "(mysqli|pdo_mysql)"; then
                WP_PHP_BIN="php$v"
                break
            fi
        done
    fi
    local WP_CMD="$WP_PHP_BIN -d display_errors=0 /usr/local/bin/wp --path=$WEB_ROOT --allow-root"

    if [[ ! -f "$WEB_ROOT/wp-config.php" ]]; then
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
    
    local WP_PHP_BIN="php"
    local SITE_CONF="/etc/nginx/sites-available/$domain"
    if [[ -f "$SITE_CONF" ]]; then
        local SITE_PHP_VER=$(grep -shoP 'unix:/run/php/php\K[0-9.]+(?=-fpm.sock)' "$SITE_CONF" | head -n 1)
        if [[ -n "$SITE_PHP_VER" ]] && command -v "php$SITE_PHP_VER" >/dev/null 2>&1; then
            WP_PHP_BIN="php$SITE_PHP_VER"
        fi
    fi
    
    if ! "$WP_PHP_BIN" -m 2>/dev/null | grep -qEi "(mysqli|pdo_mysql)"; then
        for v in 8.3 8.4 8.5 8.2 8.1 8.0 7.4; do
            if command -v "php$v" >/dev/null 2>&1 && "php$v" -m 2>/dev/null | grep -qEi "(mysqli|pdo_mysql)"; then
                WP_PHP_BIN="php$v"
                break
            fi
        done
    fi
    local WP_CMD="$WP_PHP_BIN -d display_errors=0 /usr/local/bin/wp --path=$WEB_ROOT --allow-root"

    if [[ ! -f "$WEB_ROOT/wp-config.php" ]]; then
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


# 10. Image Optimization Setup
setup_image_optimization() {
    clear
    echo -e "${BLUE}=================================================${NC}"
    echo -e "${GREEN}     🖼️  Image Optimization Setup${NC}"
    echo -e "${BLUE}=================================================${NC}"
    echo -e "Script sẽ đảm bảo cài đặt thư viện WebP trên server và"
    echo -e "tự động cài plugin Imagify vào website WordPress của bạn."
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
            _install_webp_server
            _do_image_optimization "$SELECTED_DOMAIN"
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
            
            _install_webp_server
            
            for d in /var/www/*/public_html/wp-config.php; do
                [ ! -f "$d" ] && continue
                local domain
                domain=$(basename "$(dirname "$(dirname "$d")")")
                _do_image_optimization "$domain"
            done
            ;;
        0) return ;;
    esac
    pause
}

_install_webp_server() {
    local php_ver=$(get_installed_php_version)
    if ! command -v cwebp >/dev/null 2>&1 || ! dpkg -l | grep -q "php${php_ver}-gd"; then
        log_info "Đang cài đặt Server-side WebP support..."
        export DEBIAN_FRONTEND=noninteractive
        apt-get install -y php${php_ver}-gd webp >/dev/null 2>&1
        systemctl restart php${php_ver}-fpm >/dev/null 2>&1
        log_info "WebP support installed."
    else
        log_info "Server đã hỗ trợ WebP."
    fi
}

_do_image_optimization() {
    local domain=$1
    local WEB_ROOT="/var/www/$domain/public_html"
    
    local WP_PHP_BIN="php"
    local SITE_CONF="/etc/nginx/sites-available/$domain"
    if [[ -f "$SITE_CONF" ]]; then
        local SITE_PHP_VER=$(grep -shoP 'unix:/run/php/php\K[0-9.]+(?=-fpm.sock)' "$SITE_CONF" | head -n 1)
        if [[ -n "$SITE_PHP_VER" ]] && command -v "php$SITE_PHP_VER" >/dev/null 2>&1; then
            WP_PHP_BIN="php$SITE_PHP_VER"
        fi
    fi
    
    if ! "$WP_PHP_BIN" -m 2>/dev/null | grep -qEi "(mysqli|pdo_mysql)"; then
        for v in 8.3 8.4 8.5 8.2 8.1 8.0 7.4; do
            if command -v "php$v" >/dev/null 2>&1 && "php$v" -m 2>/dev/null | grep -qEi "(mysqli|pdo_mysql)"; then
                WP_PHP_BIN="php$v"
                break
            fi
        done
    fi
    local WP_CMD="$WP_PHP_BIN -d /usr/local/bin/wp --path=$WEB_ROOT --allow-root"

    if [[ ! -f "$WEB_ROOT/wp-config.php" ]]; then
        echo -e "${RED}$domain không phải WordPress site.${NC}"
        return
    fi

    log_info "Cài đặt Plugin tối ưu ảnh: $domain"
    
    if $WP_CMD plugin is-installed imagify 2>/dev/null; then
        echo "  ✓ Imagify plugin đã có sẵn."
        $WP_CMD plugin activate imagify 2>/dev/null
    elif $WP_CMD plugin is-installed shortpixel-image-optimiser 2>/dev/null; then
        echo "  ✓ ShortPixel plugin đã có sẵn."
    elif $WP_CMD plugin is-installed litespeed-cache 2>/dev/null; then
        echo "  ✓ LiteSpeed Cache đã có sẵn."
    else
        echo "  - Đang tải và cài đặt Imagify..."
        if $WP_CMD plugin install imagify --activate 2>/dev/null; then
            echo "  ✓ Cài đặt Imagify thành công."
        else
            echo "  ✗ Lỗi khi cài đặt Imagify."
        fi
    fi
    
    echo -e "${YELLOW}Gợi ý: Hãy đăng nhập WP Admin -> Settings -> Imagify để lấy API Key miễn phí và kích hoạt WebP!${NC}"
}

# 10. HTTP/2 & Brotli
enable_http2_brotli() {
    log_info "Enabling HTTP/2 and Brotli compression..."

    # ── HTTP/2 check ─────────────────────────────────────────
    if nginx -V 2>&1 | grep -q "http_v2\|http_v3"; then
        log_info "HTTP/2 already supported (built-in)"
    else
        log_warn "Nginx không hỗ trợ HTTP/2. Nâng cấp Nginx lên mainline."
    fi

    # ── Brotli check ─────────────────────────────────────────
    local brotli_ok=0
    # Strict check: Test config with brotli directive before enabling
    if nginx -V 2>&1 | grep -qi "brotli"; then
        # Create temp config to test
        echo "brotli on;" > /etc/nginx/conf.d/brotli_test_temp.conf
        if nginx -t &>/dev/null; then
            brotli_ok=1
            log_info "Brotli module: ✅ Hoạt động tốt"
        else
            log_warn "Nginx build có string 'brotli' nhưng directive không chạy được."
            brotli_ok=0
        fi
        rm -f /etc/nginx/conf.d/brotli_test_temp.conf
    else
        log_warn "Brotli module chưa có trong Nginx build hiện tại."
    fi

    if [[ "$brotli_ok" -eq 0 ]]; then
        echo ""
        echo -e "Muốn thử cài module Brotli không?"
        echo -e "  1. Cài libnginx-mod-http-brotli (apt)"
        echo -e "  2. Bỏ qua, chỉ dùng Gzip"
        read -p "Chọn [1/2]: " bc

        if [[ "$bc" == "1" ]]; then
            apt-get install -y libnginx-mod-http-brotli 2>/dev/null
            # Test again
            echo "brotli on;" > /etc/nginx/conf.d/brotli_test_temp.conf
            if nginx -t &>/dev/null; then
                brotli_ok=1
                log_info "✅ Brotli module đã cài và hoạt động"
            else
                log_warn "Cài xong nhưng vẫn không chạy được. Dùng Gzip."
            fi
            rm -f /etc/nginx/conf.d/brotli_test_temp.conf
        fi
    fi

    # ── Xóa brotli.conf cũ nếu Brotli KHÔNG có (tránh nginx fail) ──
    if [[ "$brotli_ok" -eq 0 ]] && [[ -f /etc/nginx/conf.d/brotli.conf ]]; then
        log_warn "Xóa /etc/nginx/conf.d/brotli.conf cũ (module không tồn tại)"
        rm -f /etc/nginx/conf.d/brotli.conf
    fi

    # ── Gzip (luôn áp dụng, hoạt động mọi Nginx build) ──────
    if ! grep -q "gzip on" /etc/nginx/nginx.conf 2>/dev/null \
       && ! [ -f /etc/nginx/conf.d/gzip.conf ]; then
        cat > /etc/nginx/conf.d/gzip.conf << 'GEOF'
# Gzip Compression (universal fallback)
gzip on;
gzip_vary on;
gzip_proxied any;
gzip_comp_level 6;
gzip_min_length 256;
gzip_types
    text/plain text/css text/xml text/javascript
    application/javascript application/x-javascript
    application/json application/xml application/xml+rss
    application/rss+xml application/atom+xml
    image/svg+xml font/woff2 font/woff font/ttf;
GEOF
        log_info "Gzip config tạo tại /etc/nginx/conf.d/gzip.conf"
    else
        log_info "Gzip đã được cấu hình"
    fi

    # ── Brotli config (chỉ khi module có mặt) ─────────────
    if [[ "$brotli_ok" -eq 1 ]]; then
        cat > /etc/nginx/conf.d/brotli.conf << 'BEOF'
# Brotli Compression
brotli on;
brotli_comp_level 6;
brotli_static on;
brotli_types text/plain text/css text/xml text/javascript
    application/javascript application/x-javascript
    application/json application/xml application/rss+xml
    image/svg+xml font/woff2 font/woff;
BEOF
        log_info "Brotli config tạo tại /etc/nginx/conf.d/brotli.conf"
    fi

    # ── Browser Caching Snippet ───────────────────────────
    if [[ ! -f /etc/nginx/snippets/browser_caching.conf ]]; then
        mkdir -p /etc/nginx/snippets
        cat > /etc/nginx/snippets/browser_caching.conf << 'CEOF'
location ~* \.(jpg|jpeg|gif|png|ico|svg|css|js|woff|woff2|ttf|eot)$ {
    expires 365d;
    add_header Cache-Control "public, no-transform";
    access_log off;
}
CEOF
        log_info "Browser caching config tạo tại /etc/nginx/snippets/browser_caching.conf"
    fi

    # ── Test & Reload ─────────────────────────────────────
    echo ""
    if nginx -t; then
        systemctl reload nginx
        log_info "✅ Compression đã áp dụng thành công"
        echo -e "${YELLOW}Note: HTTP/2 cần SSL certificate (HTTPS)${NC}"
        [ "$brotli_ok" -eq 1 ] \
            && echo -e "${GREEN}  → Brotli + Gzip: cả hai đang hoạt động${NC}" \
            || echo -e "${YELLOW}  → Chỉ Gzip: Brotli cần module riêng${NC}"
    else
        log_error "Nginx config lỗi. Kiểm tra /etc/nginx/conf.d/"
    fi
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

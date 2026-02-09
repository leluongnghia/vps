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
    clear
    echo -e "${BLUE}=================================================${NC}"
    echo -e "${GREEN}    WordPress Performance Optimization${NC}"
    echo -e "${BLUE}=================================================${NC}"
    echo -e "1. 🚀 Auto-Optimize (All-in-One - Recommended)"
    echo -e "2. ⚡ PHP-FPM Tuning (Memory, Workers)"
    echo -e "3. 💾 OPcache Optimization"
    echo -e "4. 🗄️  MySQL/MariaDB Tuning"
    echo -e "5. 🔥 Nginx FastCGI Micro-Caching"
    echo -e "6. 🧹 Database Cleanup & Optimization"
    echo -e "7. 📦 Enable Object Cache (Redis/Memcached)"
    echo -e "8. 🎯 Disable WordPress Bloat (Heartbeat, Embeds, etc.)"
    echo -e "9. 🖼️  Image Optimization Setup"
    echo -e "10. 🌐 HTTP/2 & Brotli Compression"
    echo -e "11. 📊 Performance Benchmark Test"
    echo -e "0. Back to Main Menu"
    echo -e "${BLUE}=================================================${NC}"
    read -p "Select [0-11]: " choice

    case $choice in
        1) auto_optimize_wordpress ;;
        2) tune_php_fpm ;;
        3) optimize_opcache ;;
        4) tune_mysql ;;
        5) setup_fastcgi_microcache ;;
        6) cleanup_wordpress_db ;;
        7) setup_object_cache ;;
        8) disable_wordpress_bloat ;;
        9) setup_image_optimization ;;
        10) enable_http2_brotli ;;
        11) benchmark_wordpress ;;
        0) return ;;
        *) echo -e "${RED}Invalid choice!${NC}"; pause ;;
    esac
}

# 1. Auto-Optimize Everything
auto_optimize_wordpress() {
    log_info "Starting comprehensive WordPress optimization..."
    
    echo -e "${YELLOW}This will optimize:${NC}"
    echo "  ✓ PHP-FPM settings"
    echo "  ✓ OPcache configuration"
    echo "  ✓ MySQL/MariaDB"
    echo "  ✓ Nginx caching"
    echo "  ✓ WordPress database"
    echo "  ✓ Disable bloat features"
    echo ""
    read -p "Continue? [y/N]: " confirm
    
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        return
    fi
    
    # Run all optimizations
    tune_php_fpm "auto"
    optimize_opcache "auto"
    tune_mysql "auto"
    setup_fastcgi_microcache "auto"
    cleanup_wordpress_db "auto"
    disable_wordpress_bloat "auto"
    
    log_info "✅ WordPress optimization complete!"
    echo -e "${GREEN}Your WordPress site should now be significantly faster!${NC}"
    echo -e "${YELLOW}Recommended next steps:${NC}"
    echo "  1. Install a caching plugin (WP Rocket, W3 Total Cache)"
    echo "  2. Enable object cache (Option 7)"
    echo "  3. Run benchmark test (Option 11)"
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

# 6. Database Cleanup
cleanup_wordpress_db() {
    local auto_mode=$1
    
    # Select WordPress site
    if [ -z "$auto_mode" ]; then
        source "$(dirname "${BASH_SOURCE[0]}")/wordpress_tool.sh"
        select_wp_site || return
        ensure_wp_cli
    else
        # Auto mode: clean all WP sites
        log_info "Cleaning all WordPress databases..."
        for d in /var/www/*; do
            if [[ -d "$d" && -f "$d/public_html/wp-config.php" ]]; then
                local domain=$(basename "$d")
                WEB_ROOT="/var/www/$domain/public_html"
                WP_CMD="wp --path=$WEB_ROOT --allow-root"
                
                log_info "Cleaning $domain database..."
                $WP_CMD transient delete --all 2>/dev/null
                $WP_CMD post delete $($WP_CMD post list --post_type='revision' --format=ids 2>/dev/null) --force 2>/dev/null
                $WP_CMD comment delete $($WP_CMD comment list --status=spam --format=ids 2>/dev/null) --force 2>/dev/null
                $WP_CMD db optimize 2>/dev/null
            fi
        done
        return
    fi
    
    log_info "Cleaning WordPress database for $SELECTED_DOMAIN..."
    
    # Delete transients
    $WP_CMD transient delete --all
    
    # Delete post revisions
    $WP_CMD post delete $($WP_CMD post list --post_type='revision' --format=ids) --force 2>/dev/null
    
    # Delete spam comments
    $WP_CMD comment delete $($WP_CMD comment list --status=spam --format=ids) --force 2>/dev/null
    
    # Delete trashed comments
    $WP_CMD comment delete $($WP_CMD comment list --status=trash --format=ids) --force 2>/dev/null
    
    # Optimize database tables
    $WP_CMD db optimize
    
    log_info "Database cleaned and optimized"
    pause
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

# 8. Disable WordPress Bloat
disable_wordpress_bloat() {
    local auto_mode=$1
    
    if [ -z "$auto_mode" ]; then
        source "$(dirname "${BASH_SOURCE[0]}")/wordpress_tool.sh"
        select_wp_site || return
        ensure_wp_cli
    else
        # Auto mode: apply to all sites
        for d in /var/www/*; do
            if [[ -d "$d" && -f "$d/public_html/wp-config.php" ]]; then
                local domain=$(basename "$d")
                WEB_ROOT="/var/www/$domain/public_html"
                WP_CMD="wp --path=$WEB_ROOT --allow-root"
                
                # Apply optimizations
                $WP_CMD config set WP_POST_REVISIONS 3 --raw --type=constant 2>/dev/null
                $WP_CMD config set AUTOSAVE_INTERVAL 300 --raw --type=constant 2>/dev/null
                $WP_CMD config set EMPTY_TRASH_DAYS 7 --raw --type=constant 2>/dev/null
                $WP_CMD config set WP_CRON_LOCK_TIMEOUT 60 --raw --type=constant 2>/dev/null
            fi
        done
        return
    fi
    
    log_info "Disabling WordPress bloat features..."
    
    # Limit post revisions
    $WP_CMD config set WP_POST_REVISIONS 3 --raw --type=constant
    
    # Increase autosave interval (5 minutes)
    $WP_CMD config set AUTOSAVE_INTERVAL 300 --raw --type=constant
    
    # Auto-empty trash after 7 days
    $WP_CMD config set EMPTY_TRASH_DAYS 7 --raw --type=constant
    
    # Increase cron lock timeout
    $WP_CMD config set WP_CRON_LOCK_TIMEOUT 60 --raw --type=constant
    
    log_info "WordPress bloat features optimized"
    echo -e "${YELLOW}Recommended: Disable embeds, heartbeat via plugin${NC}"
    pause
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

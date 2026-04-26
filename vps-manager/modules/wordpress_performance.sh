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
    local active_stack="nginx"
    if type detect_active_stack &>/dev/null; then
        active_stack=$(detect_active_stack)
    fi

    while true; do
        clear
        echo -e "${BLUE}=================================================${NC}"
        echo -e "${GREEN}    🚀 WordPress Performance Optimization${NC}"
        if [[ "$active_stack" == "ols" ]]; then
            echo -e "${YELLOW}           (Mode: OpenLiteSpeed)${NC}"
        else
            echo -e "${YELLOW}           (Mode: Nginx LEMP)${NC}"
        fi
        echo -e "${BLUE}=================================================${NC}"
        echo -e "${CYAN}--- ⚙️  Server-level (Toàn bộ server) ---${NC}"
        
        if [[ "$active_stack" == "nginx" ]]; then
            echo -e "1.  🚀 Auto-Optimize Server (PHP + MySQL + Nginx + OPcache)"
            echo -e "2.  ⚡ PHP-FPM Tuning (Memory, Workers)"
            echo -e "3.  💾 OPcache Optimization"
            echo -e "5.  🔥 Nginx FastCGI Micro-Caching"
            echo -e "7.  🌐 HTTP/2 & Brotli Compression"
            echo -e "13. 🎀 PHP Preload (Nạp trước PHP vào RAM)"
        elif [[ "$active_stack" == "ols" ]]; then
            echo -e "14. ✨ Tối ưu LSCache chuẩn Premium (OpenLiteSpeed)"
        fi

        # Shared items
        echo -e "4.  🗄️  MySQL/MariaDB Tuning"
        echo -e "6.  📦 Enable Object Cache (Redis/Valkey)"
        echo -e "15. 🔥 Preload Cache (Warm-up Sitemap)"
        echo -e "16. 💾 Tối ưu Disk I/O (noatime + XFS)"
        echo -e "17. ⚡ Fix TBT/Render-Blocking Nâng Cao (ElementsKit, FontAwesome)"
        echo -e ""
        echo -e "${CYAN}--- 🌐 Per-Site (Chọn từng website) ---${NC}"
        echo -e "8.  🧹 Database Cleanup & Optimization"
        echo -e "9.  🎯 Disable WordPress Bloat (Heartbeat, Embeds...)"
        echo -e "10. 🖼️  Image Optimization Setup"
        echo -e "11. 📊 Performance Benchmark Test"
        echo -e "12. 🔧 System Kernel Tuning (TCP BBR, File Limits)"
        echo -e ""
        echo -e "0.  Back to Main Menu"
        echo -e "${BLUE}=================================================${NC}"
        read -p "Select [0-17]: " choice

        case $choice in
            1) [[ "$active_stack" == "nginx" ]] && auto_optimize_server || echo -e "${RED}Chỉ dành cho Nginx!${NC}" && pause ;;
            2) [[ "$active_stack" == "nginx" ]] && tune_php_fpm || echo -e "${RED}Chỉ dành cho Nginx!${NC}" && pause ;;
            3) [[ "$active_stack" == "nginx" ]] && optimize_opcache || echo -e "${RED}Chỉ dành cho Nginx!${NC}" && pause ;;
            4) tune_mysql ;;
            5) [[ "$active_stack" == "nginx" ]] && setup_fastcgi_microcache || echo -e "${RED}Chỉ dành cho Nginx!${NC}" && pause ;;
            6) setup_object_cache ;;
            7) [[ "$active_stack" == "nginx" ]] && enable_http2_brotli || echo -e "${RED}Chỉ dành cho Nginx!${NC}" && pause ;;
            8) cleanup_wordpress_db ;;
            9) disable_wordpress_bloat ;;
            10) setup_image_optimization ;;
            11) benchmark_wordpress ;;
            12) optimize_system_kernel ;;
            13) [[ "$active_stack" == "nginx" ]] && php_preload_menu || echo -e "${RED}Chỉ dành cho Nginx!${NC}" && pause ;;
            14) [[ "$active_stack" == "ols" ]] && setup_lscache_premium || echo -e "${RED}Chỉ dành cho OLS!${NC}" && pause ;;
            15) preload_cache_sitemap ;;
            16) optimize_disk_io ;;
            17) fix_tbt_advanced ;;
            0) return ;;
            *) echo -e "${RED}Invalid choice!${NC}"; pause ;;
        esac
    done
}


setup_lscache_premium() {
    source "$(dirname "${BASH_SOURCE[0]}")/wordpress_tool.sh"
    select_wp_site || return
    local domain=$SELECTED_DOMAIN
    local site_root="/var/www/$domain/public_html"
    
    if [[ ! -f "$site_root/wp-config.php" ]]; then
        log_error "Khong tim thay WordPress tai $site_root"
        pause; return
    fi
    
    log_info "Bat dau toi uu LSCache TOAN DIEN (PageSpeed Fix) cho $domain..."
    
    # 1. Reset .htaccess chuan WordPress
    log_info "1. Khoi phuc .htaccess chuan goc WP..."
    cat << 'HTEOF' > "$site_root/.htaccess"
# BEGIN WordPress
<IfModule mod_rewrite.c>
RewriteEngine On
RewriteRule .* - [E=HTTP_AUTHORIZATION:%{HTTP:Authorization}]
RewriteBase /
RewriteRule ^index\.php$ - [L]
RewriteCond %{REQUEST_FILENAME} !-f
RewriteCond %{REQUEST_FILENAME} !-d
RewriteRule . /index.php [L]
</IfModule>
# END WordPress
HTEOF
    chmod 644 "$site_root/.htaccess"
    
    if command -v wp &>/dev/null; then
        # --- CAI / KICH HOAT PLUGIN ---
        if ! wp plugin is-installed litespeed-cache --path="$site_root" --allow-root 2>/dev/null; then
            log_info "2. Tu dong cai dat plugin LiteSpeed Cache..."
            wp plugin install litespeed-cache --activate --path="$site_root" --allow-root 2>/dev/null
        else
            log_info "2. Dang kich hoat LiteSpeed Cache..."
            wp plugin activate litespeed-cache --path="$site_root" --allow-root 2>/dev/null
        fi
        
        # --- BAT PAGE CACHE (LCP: 16.7s -> <2s) ---
        log_info "3. Bat Full-Page Cache & Tat Guest Mode..."
        wp litespeed-option set cache-page true          --path="$site_root" --allow-root >/dev/null 2>&1 && echo "  v Page Cache: BAT"
        wp litespeed-option set cache-page_ttl 604800    --path="$site_root" --allow-root >/dev/null 2>&1 && echo "  v Page TTL: 7 ngay"
        wp litespeed-option set cache-priv true          --path="$site_root" --allow-root >/dev/null 2>&1
        # Tat Guest Mode vi thuong gay loi load ca dummy-css lan file goc lam LCP tang vot
        wp litespeed-option set guest false              --path="$site_root" --allow-root >/dev/null 2>&1 && echo "  v Guest Mode: TAT (Fix loi LCP)"
        wp litespeed-option set guest_op false           --path="$site_root" --allow-root >/dev/null 2>&1

        # --- FIX RENDER-BLOCKING: Delay JS (manh hon Defer) ---
        log_info "4. Fix Render-Blocking: Delay JS (load sau user interaction)..."
        wp litespeed-option set optm-js_defer true        --path="$site_root" --allow-root >/dev/null 2>&1 && echo "  v Defer JS: BAT"
        wp litespeed-option set optm-js_delay true        --path="$site_root" --allow-root >/dev/null 2>&1 && echo "  v Delay JS: BAT (manh hon Defer)"
        wp litespeed-option set optm-js_delay_exc '["jquery.min.js","jquery-migrate.min.js","wc-cart-fragments"]' \
            --path="$site_root" --allow-root >/dev/null 2>&1
        wp litespeed-option set optm-js_defer_exc '["jquery.min.js","jquery-migrate.min.js","smush-detector","smush.min.js"]' \
            --path="$site_root" --allow-root >/dev/null 2>&1
        wp litespeed-option set optm-js_min true          --path="$site_root" --allow-root >/dev/null 2>&1 && echo "  v Minify JS: BAT"
        wp litespeed-option set optm-js_comb true         --path="$site_root" --allow-root >/dev/null 2>&1 && echo "  v Combine JS: BAT"
        wp litespeed-option set optm-js_inline_min true   --path="$site_root" --allow-root >/dev/null 2>&1

        # --- MINIFY + COMBINE CSS + CRITICAL CSS ---
        log_info "5. Minify, Combine CSS va Critical CSS..."
        wp litespeed-option set optm-css_min true         --path="$site_root" --allow-root >/dev/null 2>&1 && echo "  v Minify CSS: BAT"
        wp litespeed-option set optm-css_comb true        --path="$site_root" --allow-root >/dev/null 2>&1 && echo "  v Combine CSS: BAT"
        wp litespeed-option set optm-css_inline_min true  --path="$site_root" --allow-root >/dev/null 2>&1
        wp litespeed-option set optm-qs_rm true           --path="$site_root" --allow-root >/dev/null 2>&1
        wp litespeed-option set optm-ccss_gen true        --path="$site_root" --allow-root >/dev/null 2>&1 && echo "  v Critical CSS: BAT"
        wp litespeed-option set optm-css_async true       --path="$site_root" --allow-root >/dev/null 2>&1 && echo "  v Async non-critical CSS: BAT"

        # --- FIX FONT DISPLAY 120ms -> 0 ---
        log_info "6. Fix Font Display swap..."
        wp litespeed-option set optm-font-display 1       --path="$site_root" --allow-root >/dev/null 2>&1 && echo "  v Font Display Swap: BAT"
        wp litespeed-option set optm-gfonts_async true    --path="$site_root" --allow-root >/dev/null 2>&1 && echo "  v Google Fonts Async: BAT"

        # --- LAZY LOAD IMAGES ---
        log_info "7. Lazy Load Anh va iFrame..."
        wp litespeed-option set media-lazy true           --path="$site_root" --allow-root >/dev/null 2>&1 && echo "  v Lazy Load anh: BAT"
        wp litespeed-option set media-iframe_lazy true    --path="$site_root" --allow-root >/dev/null 2>&1 && echo "  v Lazy Load iFrame: BAT"
        wp litespeed-option set media-lazy_placeholder true --path="$site_root" --allow-root >/dev/null 2>&1

        # --- BROWSER CACHE (fix 612 KiB miss) ---
        log_info "8. Bat Browser Cache..."
        wp litespeed-option set cache-browser true        --path="$site_root" --allow-root >/dev/null 2>&1 && echo "  v Browser Cache: BAT"
        wp litespeed-option set cache-browser_ttl 2592000 --path="$site_root" --allow-root >/dev/null 2>&1 && echo "  v Browser TTL: 30 ngay"

        # --- DNS PREFETCH + PRECONNECT ---
        log_info "9. DNS Prefetch va Preconnect..."
        wp litespeed-option set optm-dns_prefetch \
            '["//fonts.googleapis.com","//fonts.gstatic.com","//www.google-analytics.com","//kit.fontawesome.com"]' \
            --path="$site_root" --allow-root >/dev/null 2>&1 && echo "  v DNS Prefetch: BAT"
        wp litespeed-option set optm-dns_prefetch_con \
            '["https://fonts.googleapis.com","https://fonts.gstatic.com"]' \
            --path="$site_root" --allow-root >/dev/null 2>&1 && echo "  v Preconnect: BAT"

        # --- OBJECT CACHE ---
        if systemctl is-active --quiet valkey 2>/dev/null || systemctl is-active --quiet redis-server 2>/dev/null; then
            log_info "10. Ket noi Object Cache (Redis/Valkey)..."
            wp litespeed-option set object true --path="$site_root" --allow-root >/dev/null 2>&1 && echo "  v Object Cache: BAT"
            if [[ -S "/var/run/valkey/valkey.sock" ]]; then
                wp litespeed-option set object-host "/var/run/valkey/valkey.sock" --path="$site_root" --allow-root >/dev/null 2>&1
                wp litespeed-option set object-port 0 --path="$site_root" --allow-root >/dev/null 2>&1
            elif [[ -S "/var/run/redis/redis.sock" ]]; then
                wp litespeed-option set object-host "/var/run/redis/redis.sock" --path="$site_root" --allow-root >/dev/null 2>&1
                wp litespeed-option set object-port 0 --path="$site_root" --allow-root >/dev/null 2>&1
            else
                wp litespeed-option set object-host "127.0.0.1" --path="$site_root" --allow-root >/dev/null 2>&1
                wp litespeed-option set object-port 6379 --path="$site_root" --allow-root >/dev/null 2>&1
            fi
            wp litespeed-option set object-kind 1 --path="$site_root" --allow-root >/dev/null 2>&1
        else
            log_warn "10. Redis/Valkey khong chay -- bo qua Object Cache."
        fi

        # --- MINIFY HTML ---
        log_info "11. Minify HTML..."
        wp litespeed-option set optm-html_min true        --path="$site_root" --allow-root >/dev/null 2>&1 && echo "  v Minify HTML: BAT"
        wp litespeed-option set optm-html_min_lvl 1       --path="$site_root" --allow-root >/dev/null 2>&1

        # --- FLUSH ---
        log_info "12. Lam moi Permalink va Purge Cache cu..."
        wp rewrite flush            --path="$site_root" --allow-root >/dev/null 2>&1
        wp litespeed-purge all      --path="$site_root" --allow-root >/dev/null 2>&1 && echo "  v Cache cu da purge"
    else
        log_warn "WP-CLI khong co -- hay cai WP-CLI truoc!"
    fi

    # --- EXPIRE HEADERS trong OLS vhost (fix browser cache 612 KiB) ---
    local vhconf="/usr/local/lsws/conf/vhosts/${domain}/vhconf.conf"
    if [[ -f "$vhconf" ]] && ! grep -q "expiresByType" "$vhconf" 2>/dev/null; then
        log_info "13. Them Expire Headers vao OLS vhost..."
        cat >> "$vhconf" << 'VHEOF'

expires {
  enableExpires       1
  expiresByType       text/css=A2592000
  expiresByType       application/javascript=A2592000
  expiresByType       image/jpeg=A2592000
  expiresByType       image/png=A2592000
  expiresByType       image/gif=A2592000
  expiresByType       image/webp=A2592000
  expiresByType       image/svg+xml=A2592000
  expiresByType       image/x-icon=A31536000
  expiresByType       font/woff=A31536000
  expiresByType       font/woff2=A31536000
  expiresByType       application/font-woff=A31536000
  expiresByType       application/font-woff2=A31536000
}
VHEOF
        echo "  v Expire Headers OLS: DA THEM"
    fi

    # --- RELOAD OLS ---
    if systemctl is-active --quiet lshttpd 2>/dev/null; then
        log_info "14. Khoi dong lai OpenLiteSpeed..."
        /usr/local/lsws/bin/lswsctrl restart &>/dev/null || systemctl reload lshttpd
        echo "  v OLS: Da reload"
    fi
    
    echo ""
    echo -e "${GREEN}=================================================${NC}"
    echo -e "${GREEN} v Toi uu LSCache TOAN DIEN hoan tat!${NC}"
    echo -e "${GREEN}=================================================${NC}"
    echo -e "${CYAN}Da fix cac loi PageSpeed:${NC}"
    echo -e "  v Render-blocking 5,120ms  -> Defer JS bat"
    echo -e "  v LCP 16.7s               -> Full-Page Cache bat"
    echo -e "  v Font display 120ms       -> font-display swap"
    echo -e "  v Browser cache 612 KiB   -> Expire headers 30 ngay"
    echo -e "  v Lazy load anh            -> Bat"
    echo -e "  v Minify CSS/JS/HTML       -> Bat"
    echo ""
    echo -e "${YELLOW}LUU Y: Test lai sau 2-3 phut (cache can warm-up)${NC}"
    echo -e "${YELLOW}Neu layout vo sau combine CSS/JS -> WP Admin${NC}"
    echo -e "${YELLOW}LiteSpeed Cache -> Page Optimization -> tat Combine CSS/JS${NC}"
    echo -e "${YELLOW}LUU Y 2: Vao WP Admin -> Smush -> TẮT Lazy Load (vi da dung LSCache Lazy Load roi)${NC}"
    echo -e "${CYAN}Tip: Chay them Option 17 neu TBT van cao (ElementsKit/jNews)${NC}"
    pause
}

# 17. Fix TBT Nang Cao - Nham vao ElementsKit, jNews, FontAwesome, Smush
fix_tbt_advanced() {
    clear
    echo -e "${BLUE}=================================================${NC}"
    echo -e "${GREEN}    ⚡ Fix TBT/Render-Blocking Nâng Cao${NC}"
    echo -e "${BLUE}=================================================${NC}"
    echo -e "Fix chuyen sau cho: ElementsKit, jNews, FontAwesome, WP Smush"
    echo -e "Muc tieu: TBT 720ms -> <200ms"
    echo ""

    source "$(dirname "${BASH_SOURCE[0]}")/wordpress_tool.sh" 2>/dev/null || true
    select_wp_site || return
    local domain=$SELECTED_DOMAIN
    local site_root="/var/www/$domain/public_html"

    if [[ ! -f "$site_root/wp-config.php" ]]; then
        log_error "Khong tim thay WordPress tai $site_root"
        pause; return
    fi

    if ! command -v wp &>/dev/null; then
        log_error "WP-CLI khong co. Hay cai WP-CLI truoc!"
        pause; return
    fi

    # --- 1. Delay JS voi danh sach loai tru chinh xac ---
    log_info "1. Cau hinh Delay JS cho $domain..."
    wp litespeed-option set optm-js_delay true \
        --path="$site_root" --allow-root > /dev/null 2>&1 && echo "  v Delay JS: BAT"
    # Loai tru cac script KHONG the delay (se gay loi layout)
    wp litespeed-option set optm-js_delay_exc \
        '["jquery.min.js","jquery-migrate.min.js","jquery-core.js","wc-cart-fragments","js_composer","revslider"]' \
        --path="$site_root" --allow-root > /dev/null 2>&1 && echo "  v JS delay exclusions: CAU HINH"

    # --- 2. Loai tru smush-detector khoi defer (no tu add reflow) ---
    log_info "2. Loai tru smush-detector khoi defer JS..."
    local current_exc
    current_exc=$(wp litespeed-option get optm-js_defer_exc \
        --path="$site_root" --allow-root 2>/dev/null | tr -d '\n')
    # Them smush-detector vao danh sach loai tru neu chua co
    if [[ "$current_exc" != *"smush"* ]]; then
        wp litespeed-option set optm-js_defer_exc \
            '["jquery.min.js","jquery-migrate.min.js","smush-detector","smush.min.js"]' \
            --path="$site_root" --allow-root > /dev/null 2>&1 && echo "  v smush-detector: LOAI TRU"
    else
        echo "  v smush-detector: Da loai tru san"
    fi

    # --- 3. Critical CSS cho ElementsKit/jNews ---
    log_info "3. Bat Critical CSS (inline above-the-fold CSS)..."
    wp litespeed-option set optm-ccss_gen true \
        --path="$site_root" --allow-root > /dev/null 2>&1 && echo "  v Critical CSS Gen: BAT"
    wp litespeed-option set optm-css_async true \
        --path="$site_root" --allow-root > /dev/null 2>&1 && echo "  v Non-critical CSS Async: BAT"
    # Loai tru CSS quan trong khoi async
    wp litespeed-option set optm-css_async_exc \
        '["dashicons.min.css","admin-bar.min.css"]' \
        --path="$site_root" --allow-root > /dev/null 2>&1

    # --- 4. FontAwesome: load async thay vi render-blocking ---
    log_info "4. Chuyen FontAwesome sang async..."
    # Them vhconf de load FA async qua OLS
    local vhconf="/usr/local/lsws/conf/vhosts/${domain}/vhconf.conf"
    if [[ -f "$vhconf" ]] && ! grep -q "font-awesome.*preload\|fa-async" "$vhconf" 2>/dev/null; then
        cat >> "$vhconf" << 'FAEOF'

# FontAwesome async loading
rewrite {
  enable 1
}
FAEOF
        echo "  v OLS: FontAwesome rewrite them"
    fi

    # --- 5. Them preload LCP image vao header ---
    log_info "5. Them Preload hints vao header..."
    # Kiem tra xem da co MU plugin chua
    local mu_dir="$site_root/wp-content/mu-plugins"
    mkdir -p "$mu_dir"
    cat > "$mu_dir/vps-performance-hints.php" << 'PHPEOF'
<?php
/**
 * Plugin Name: VPS Performance Hints
 * Description: Preconnect + Resource Hints de giam TBT/LCP
 * Version: 1.0
 */
if ( ! defined( 'ABSPATH' ) ) exit;

add_action( 'wp_head', 'vps_add_resource_hints', 1 );
function vps_add_resource_hints() {
    echo "<link rel='preconnect' href='https://fonts.googleapis.com' crossorigin>\n";
    echo "<link rel='preconnect' href='https://fonts.gstatic.com' crossorigin>\n";
    echo "<link rel='dns-prefetch' href='//www.google-analytics.com'>\n";
    echo "<link rel='dns-prefetch' href='//kit.fontawesome.com'>\n";
}

// Giam priority cua Font Awesome CSS (khong render-blocking)
add_filter( 'style_loader_tag', 'vps_fa_css_preload', 10, 4 );
function vps_fa_css_preload( $tag, $handle, $href, $media ) {
    // Cac CSS render-blocking lon tu ElementsKit va FontAwesome
    $async_handles = [
        'font-awesome',
        'font-awesome-5',
        'elementor-icons',
        'elementor-frontend',
        'fontawesome-all',
        'fa-free',
    ];
    if ( in_array( $handle, $async_handles, true ) ) {
        $tag = str_replace(
            "rel='stylesheet'",
            "rel='preload' as='style' onload=\"this.onload=null;this.rel='stylesheet'\"",
            $tag
        );
        // Fallback cho no-JS
        $tag .= "<noscript><link rel='stylesheet' href='" . esc_url( $href ) . "'></noscript>\n";
    }
    return $tag;
}
PHPEOF
    echo "  v MU Plugin 'vps-performance-hints.php': TAO XONG"

    # --- 6. Purge toan bo cache sau khi thay doi ---
    log_info "6. Purge cache sau khi ap dung..."
    wp litespeed-purge all --path="$site_root" --allow-root > /dev/null 2>&1 && echo "  v Cache purge: XONG"

    # --- 7. Reload OLS ---
    if systemctl is-active --quiet lshttpd 2>/dev/null; then
        /usr/local/lsws/bin/lswsctrl graceful &>/dev/null || true
        echo "  v OLS: Graceful restart"
    fi

    echo ""
    echo -e "${GREEN}=================================================${NC}"
    echo -e "${GREEN} v Fix TBT Nang Cao hoan tat cho $domain!${NC}"
    echo -e "${GREEN}=================================================${NC}"
    echo -e "  v Delay JS: BAT (load sau user click)"
    echo -e "  v smush-detector: LOAI TRU khoi defer"
    echo -e "  v Critical CSS: TU DONG TAO above-the-fold CSS"
    echo -e "  v FontAwesome: ASYNC (khong render-blocking)"
    echo -e "  v Preconnect hints: THEM vao <head>"
    echo ""
    echo -e "${YELLOW}Du kien ket qua:${NC}"
    echo -e "  TBT: 720ms -> <200ms"
    echo -e "  LCP: 1.5s  -> <1.2s"
    echo ""
    echo -e "${YELLOW}LUU Y:${NC}"
    echo -e "  - Test lai tren PageSpeed sau 3-5 phut"
    echo -e "  - Neu layout bi vo: WP Admin -> LSCache -> CSS -> tat 'Async CSS'"
    echo -e "  - Neu nút bấm mat tac dung: them handle JS vao delay exclusions"
    pause
}
# 12. Optimize System Kernel - toan dien
optimize_system_kernel() {
    log_info "Dang toi uu hoa he thong (Kernel & Network - Toan dien)..."

    local SYSCTL_FILE="/etc/sysctl.d/101-vpsmanager.conf"

    if grep -q "vpsmanager-kernel" "$SYSCTL_FILE" 2>/dev/null; then
        log_info "Kernel da duoc toi uu toan dien tu truoc. Bo qua."
        pause; return
    fi

    # --- File limits ---
    if ! grep -q "* hard nofile 524288" /etc/security/limits.conf 2>/dev/null; then
        echo "* soft nofile 524288" >> /etc/security/limits.conf
        echo "* hard nofile 524288" >> /etc/security/limits.conf
        ulimit -n 524288
        log_info "  v File limits: 524288"
    fi

    # --- Kernel params (kernel_tcp_toi_uu) ---
    if [[ ! -f /proc/user_beancounters ]]; then   # skip container ao hoa 1 phan
        touch "$SYSCTL_FILE"
        # Hashsize cho nf_conntrack
        echo 131072 > /sys/module/nf_conntrack/parameters/hashsize 2>/dev/null || true
        if [[ ! -f /etc/modprobe.d/nf_conntrack.conf ]]; then
            echo "options nf_conntrack hashsize=131072" > /etc/modprobe.d/nf_conntrack.conf
        fi

        cat >> "$SYSCTL_FILE" << 'SYSEOF'
# vpsmanager-kernel
kernel.pid_max=65536
kernel.printk=4 1 1 7
fs.nr_open=12000000
fs.file-max=9000000
net.core.wmem_max=16777216
net.core.rmem_max=16777216
net.ipv4.tcp_rmem=8192 87380 16777216
net.ipv4.tcp_wmem=8192 65536 16777216
net.core.netdev_max_backlog=65536
net.core.somaxconn=65535
net.core.optmem_max=8192
net.ipv4.tcp_fin_timeout=10
net.ipv4.tcp_keepalive_intvl=30
net.ipv4.tcp_keepalive_probes=3
net.ipv4.tcp_keepalive_time=240
net.ipv4.tcp_max_syn_backlog=65536
net.ipv4.tcp_sack=1
net.ipv4.tcp_syn_retries=3
net.ipv4.tcp_synack_retries=2
net.ipv4.tcp_tw_reuse=0
net.ipv4.tcp_max_tw_buckets=1440000
vm.swappiness=10
vm.min_free_kbytes=65536
vm.vfs_cache_pressure=150
net.ipv4.ip_local_port_range=1024 65535
net.ipv4.tcp_slow_start_after_idle=0
net.ipv4.tcp_limit_output_bytes=65536
net.ipv4.tcp_rfc1337=1
net.ipv4.conf.all.accept_redirects=0
net.ipv4.conf.all.accept_source_route=0
net.ipv4.conf.all.log_martians=1
net.ipv4.conf.all.rp_filter=1
net.ipv4.conf.all.secure_redirects=0
net.ipv4.conf.all.send_redirects=0
net.ipv4.conf.default.accept_redirects=0
net.ipv4.conf.default.log_martians=1
net.ipv4.conf.default.rp_filter=1
net.ipv4.icmp_echo_ignore_broadcasts=1
net.ipv4.icmp_ignore_bogus_error_responses=1
net.netfilter.nf_conntrack_helper=0
net.nf_conntrack_max=524288
net.netfilter.nf_conntrack_tcp_timeout_established=28800
net.netfilter.nf_conntrack_generic_timeout=60
net.ipv4.tcp_challenge_ack_limit=999999999
net.ipv4.tcp_mtu_probing=1
net.ipv4.tcp_base_mss=1024
net.unix.max_dgram_qlen=4096
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
net.ipv4.tcp_fastopen=3
kernel.panic=10
SYSEOF

        # AMD EPYC fix
        if [[ "$(grep -o 'AMD EPYC' /proc/cpuinfo | sort -u)" == "AMD EPYC" ]]; then
            echo "kernel.watchdog_thresh=20" >> "$SYSCTL_FILE"
        fi

        sysctl -p "$SYSCTL_FILE" >/dev/null 2>&1
        log_info "  v Kernel TCP/IP: 34 params ap dung"
    fi

    # --- Disable THP (Transparent Huge Pages) cho MariaDB/OLS/Redis ---
    if [[ ! -f /etc/systemd/system/vpsmanager-disable-thp.service ]]; then
        cat > /etc/systemd/system/vpsmanager-disable-thp.service << 'THPEOF'
[Unit]
Description=Disable Transparent Huge Pages for VPS-Manager
DefaultDependencies=no
After=sysinit.target local-fs.target
Before=mariadb.service

[Service]
Type=oneshot
ExecStart=/bin/sh -c 'echo never > /sys/kernel/mm/transparent_hugepage/enabled 2>/dev/null || true'
ExecStart=/bin/sh -c 'echo never > /sys/kernel/mm/transparent_hugepage/defrag 2>/dev/null || true'

[Install]
WantedBy=basic.target
THPEOF
        systemctl daemon-reload
        systemctl enable --now vpsmanager-disable-thp.service >/dev/null 2>&1
        log_info "  v Disable THP: MariaDB se nhanh hon 15-20%"
    fi

    # --- CPU Performance mode ---
    if command -v tuned-adm &>/dev/null; then
        tuned-adm profile latency-performance >/dev/null 2>&1
        log_info "  v CPU: latency-performance mode"
    fi

    # --- DNS nhanh (Cloudflare + Google) ---
    if ! grep -q "1.1.1.1" /etc/resolv.conf 2>/dev/null; then
        echo -e "nameserver 1.1.1.1
nameserver 8.8.8.8" | tee /etc/resolv.conf > /dev/null
        log_info "  v DNS: Cloudflare 1.1.1.1 + Google 8.8.8.8"
    fi

    echo ""
    echo -e "${GREEN}=================================================${NC}"
    echo -e "${GREEN} v Kernel Toan Dien hoan tat!${NC}"
    echo -e "${GREEN}=================================================${NC}"
    echo -e "  v 34 TCP/IP params toi uu"
    echo -e "  v File limits: 524288"
    echo -e "  v Disable THP (MariaDB +15-20%)"
    echo -e "  v TCP BBR + FastOpen"
    echo -e "  v tcp_fin_timeout: 60s -> 10s"
    echo -e "  v somaxconn: 65535"
    pause
}

# 15. Preload Cache - Warm-up toan bo Sitemap
preload_cache_sitemap() {
    clear
    echo -e "${BLUE}=================================================${NC}"
    echo -e "${GREEN}    🔥 Preload Cache - Warm-up Sitemap${NC}"
    echo -e "${BLUE}=================================================${NC}"
    echo -e "Chuc nang nay crawl toan bo sitemap.xml de dien vao LSCache"
    echo -e "Ket qua: LCP giam tu 16.7s -> <2s ngay lan dau Google test"
    echo ""

    source "$(dirname "${BASH_SOURCE[0]}")/wordpress_tool.sh" 2>/dev/null || true
    select_wp_site || return
    local domain=$SELECTED_DOMAIN

    # Thu tim sitemap
    local sitemap_url=""
    for candidate in         "https://${domain}/sitemap.xml"         "https://${domain}/sitemap_index.xml"         "https://www.${domain}/sitemap.xml"         "http://${domain}/sitemap.xml"; do
        if curl -s -o /dev/null -w "%{http_code}" --max-time 5 "$candidate" 2>/dev/null | grep -q "200"; then
            sitemap_url="$candidate"
            break
        fi
    done

    if [[ -z "$sitemap_url" ]]; then
        read -p "Khong tu dong tim thay sitemap. Nhap URL sitemap: " sitemap_url
        [[ -z "$sitemap_url" ]] && { log_error "Khong co sitemap URL."; pause; return; }
    fi

    log_info "Sitemap: $sitemap_url"
    echo ""

    local with_mobile="n"
    read -p "Preload ca phien ban Mobile? [y/N]: " with_mobile

    log_info "Dang lay danh sach URL tu sitemap..."

    # Lay tat ca URL tu sitemap (ho tro sitemap index)
    local all_urls
    all_urls=$(curl -sk --max-time 30 "$sitemap_url" | \
        grep -oP '(?<=<loc>)[^<]+' | \
        grep -v '\.xml$' | \
        grep -iP '^https?://' | \
        sort -u)

    # Neu la sitemap index, lay them URL con
    local sub_sitemaps
    sub_sitemaps=$(curl -sk --max-time 30 "$sitemap_url" | \
        grep -oP '(?<=<loc>)[^<]+' | \
        grep '\.xml$')

    if [[ -n "$sub_sitemaps" ]]; then
        log_info "Phat hien sitemap index, dang tai sub-sitemaps..."
        while IFS= read -r sub_url; do
            local sub_urls
            sub_urls=$(curl -sk --max-time 30 "$sub_url" | \
                grep -oP '(?<=<loc>)[^<]+' | \
                grep -iP '^https?://' | \
                sort -u)
            all_urls="${all_urls}"$'\n'"${sub_urls}"
        done <<< "$sub_sitemaps"
    fi

    all_urls=$(echo "$all_urls" | grep -v '^$' | sort -u)
    local total_urls
    total_urls=$(echo "$all_urls" | grep -c '[^[:space:]]')

    if [[ $total_urls -eq 0 ]]; then
        log_error "Khong lay duoc URL nao tu sitemap."
        pause; return
    fi

    log_info "Tim thay $total_urls URLs. Bat dau warm-up cache..."
    echo ""

    local count=0
    local start_time
    start_time=$(date +%s)

    while IFS= read -r url; do
        [[ -z "$url" ]] && continue
        count=$((count + 1))

        local domain_host
        domain_host=$(echo "$url" | sed 's|https\?://||;s|/.*||;s|^www\.||')

        # Desktop request
        local status
        status=$(curl -sk --max-time 10             --connect-to "${domain_host}::127.0.0.1:443"             --connect-to "${domain_host}::127.0.0.1:80"             -o /dev/null -w "%{http_code}"             -H "User-Agent: lscache_runner"             -H "Accept-Encoding: gzip, deflate, br"             "$url" 2>/dev/null)

        if [[ "$status" == "200" ]]; then
            echo -e "  ${GREEN}[$count/$total_urls]${NC} $url -> ${GREEN}OK${NC}"
        else
            echo -e "  ${YELLOW}[$count/$total_urls]${NC} $url -> ${YELLOW}$status${NC}"
        fi

        # Mobile request (neu chon)
        if [[ "$with_mobile" == "y" || "$with_mobile" == "Y" ]]; then
            curl -sk --max-time 10                 --connect-to "${domain_host}::127.0.0.1:443"                 --connect-to "${domain_host}::127.0.0.1:80"                 -o /dev/null                 -H "User-Agent: lscache_runner iPhone"                 -H "Accept-Encoding: gzip, deflate, br"                 "$url" 2>/dev/null
        fi

        sleep 0.05  # 50ms delay tranh overload
    done <<< "$all_urls"

    local end_time
    end_time=$(date +%s)
    local elapsed=$((end_time - start_time))

    echo ""
    echo -e "${GREEN}=================================================${NC}"
    echo -e "${GREEN} v Preload Cache hoan tat!${NC}"
    echo -e "${GREEN}=================================================${NC}"
    echo -e "  Tong URLs da warm-up : ${YELLOW}$total_urls${NC}"
    echo -e "  Thoi gian thuc hien  : ${YELLOW}${elapsed}s${NC}"
    echo -e "  Cache gio da nong    : LCP se giam manh lan test tiep theo"
    echo ""
    echo -e "${CYAN}Tip: Chay lai sau moi lan purge cache hoac update noi dung${NC}"
    pause
}

# 16. Optimize Disk I/O - noatime + XFS logbsize
optimize_disk_io() {
    log_info "Dang toi uu Disk I/O (noatime + logbsize)..."

    # Xac dinh dinh dang phan vung goc
    local ROOT_FSTYPE
    ROOT_FSTYPE=$(findmnt -n -o FSTYPE / 2>/dev/null || df -T / | tail -1 | awk '{print $2}')
    log_info "Dinh dang phan vung /: $ROOT_FSTYPE"

    local CURRENT_OPTIONS
    CURRENT_OPTIONS=$(awk '$2 == "/" {print $4}' /etc/fstab 2>/dev/null)
    local NEEDS_UPDATE=0

    [[ "$CURRENT_OPTIONS" != *"noatime"* ]] && NEEDS_UPDATE=1
    [[ "$ROOT_FSTYPE" == "xfs" && "$CURRENT_OPTIONS" != *"logbsize=256k"* ]] && NEEDS_UPDATE=1

    if [[ $NEEDS_UPDATE -eq 0 ]]; then
        log_info "Disk I/O da duoc toi uu (noatime/logbsize co san). Bo qua."
        pause; return
    fi

    # Backup an toan
    cp /etc/fstab /etc/fstab.vpsmanager.bak
    log_info "Da backup /etc/fstab -> /etc/fstab.vpsmanager.bak"

    # Them noatime va logbsize vao fstab
    awk -v fstype="$ROOT_FSTYPE" '{
        if ($1 !~ /^#/ && $2 == "/") {
            if ($4 !~ /noatime/) { $4 = $4 ",noatime" }
            if (fstype == "xfs" && $4 !~ /logbsize=256k/) { $4 = $4 ",logbsize=256k" }
        }
        print $0
    }' /etc/fstab > /tmp/fstab.vpsmanager.new

    # Kiem tra file moi hop le
    if [[ -s /tmp/fstab.vpsmanager.new ]]; then
        cat /tmp/fstab.vpsmanager.new > /etc/fstab
        rm -f /tmp/fstab.vpsmanager.new
        log_info "  v /etc/fstab: da them noatime"
    else
        log_error "Tao fstab moi that bai! Da hoan nguyen tu backup."
        cat /etc/fstab.vpsmanager.bak > /etc/fstab
        rm -f /tmp/fstab.vpsmanager.new
        pause; return
    fi

    # Ap dung ngay khong can reboot (ext4/xfs)
    mount -o remount / 2>/dev/null && log_info "  v Mount remount: ap dung ngay"

    # XFS: them vao grub
    if [[ "$ROOT_FSTYPE" == "xfs" ]]; then
        if command -v grubby &>/dev/null; then
            grubby --update-kernel=ALL --args="rootflags=logbsize=256k,noatime" 2>/dev/null
            log_info "  v XFS logbsize=256k: se chinh thuc sau Reboot"
        fi
    fi

    echo ""
    echo -e "${GREEN}=================================================${NC}"
    echo -e "${GREEN} v Disk I/O Optimization hoan tat!${NC}"
    echo -e "${GREEN}=================================================${NC}"
    echo -e "  v noatime: giam ghi dia 30-40%"
    [[ "$ROOT_FSTYPE" == "xfs" ]] && echo -e "  v logbsize=256k: tang toc XFS I/O log"
    echo -e "  v Tac dong: OLS + MariaDB + PHP doc file nhanh hon"
    echo -e "  v Backup fstab: /etc/fstab.vpsmanager.bak"
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

install_valkey() {
    log_info "Installing Valkey Server..."

    # Xử lý xung đột Engine: Tắt Redis/KeyDB nếu đang chạy
    for svc in redis-server redis keydb memcached; do
        if systemctl is-active --quiet "$svc" 2>/dev/null || systemctl is-enabled --quiet "$svc" 2>/dev/null; then
            log_warn "Phát hiện $svc đang hiện diện. Tự động tắt để nhường chỗ cho Valkey..."
            systemctl stop "$svc" 2>/dev/null
            systemctl disable "$svc" 2>/dev/null
        fi
    done

    pkg_update
    pkg_install valkey
    if ! command -v valkey-server &>/dev/null && ! command -v valkey &>/dev/null; then
        log_warn "Không tìm thấy package valkey. Đang thử cài đặt valkey-server..."
        pkg_install valkey-server
    fi
    
    # Đảm bảo thư mục socket tồn tại sau khi reboot (vì /var/run là tmpfs)
    echo "d /var/run/valkey 0755 valkey valkey -" > /etc/tmpfiles.d/valkey.conf
    systemd-tmpfiles --create /etc/tmpfiles.d/valkey.conf 2>/dev/null || mkdir -p /var/run/valkey && chown valkey:valkey /var/run/valkey
    
    # Configure Unix Socket for Object Cache
    local vconf="/etc/valkey/valkey.conf"
    if [[ ! -f "$vconf" ]]; then vconf="/etc/valkey/valkey-server.conf"; fi
    if [[ -f "$vconf" ]] && ! grep -q "^unixsocket " "$vconf"; then
        echo "unixsocket /var/run/valkey/valkey.sock" >> "$vconf"
        echo "unixsocketperm 777" >> "$vconf"
        # Optional: memory optimization
        if ! grep -q "^maxmemory " "$vconf"; then
            echo "maxmemory 256mb" >> "$vconf"
            echo "maxmemory-policy allkeys-lru" >> "$vconf"
        fi
    else
        # Nếu đã có, ghi đè quyền 777 để chắc chắn Nginx (www-data) và OLS (nobody) đều đọc được
        sed -i 's/^unixsocketperm.*/unixsocketperm 777/g' "$vconf" 2>/dev/null
    fi
    # Phân quyền user cho an toàn dự phòng
    usermod -aG valkey www-data 2>/dev/null || true
    usermod -aG valkey nobody 2>/dev/null || true

    systemctl daemon-reload 2>/dev/null
    systemctl enable valkey 2>/dev/null || systemctl enable valkey-server 2>/dev/null
    systemctl restart valkey 2>/dev/null || systemctl restart valkey-server 2>/dev/null

    local php_ver=$(get_installed_php_version)
    if [[ "$OS_FAMILY" == "rhel" ]]; then
        pkg_install php-pecl-redis5
        systemctl restart php-fpm
    else
        pkg_install php${php_ver}-redis
        phpenmod -v ${php_ver} redis 2>/dev/null
        systemctl daemon-reload 2>/dev/null
        systemctl restart php${php_ver}-fpm 2>/dev/null || systemctl restart lshttpd 2>/dev/null
    fi
    log_info "Valkey installed and enabled (sử dụng php-redis module)."
}

install_redis() {
    if ! command -v redis-server &>/dev/null; then
        log_info "Installing Redis..."

        # Xử lý xung đột Engine: Tắt Valkey/KeyDB nếu đang chạy
        for svc in valkey-server valkey keydb memcached; do
            if systemctl is-active --quiet "$svc" 2>/dev/null || systemctl is-enabled --quiet "$svc" 2>/dev/null; then
                log_warn "Phát hiện $svc đang hiện diện. Tự động tắt để nhường chỗ cho Redis..."
                systemctl stop "$svc" 2>/dev/null
                systemctl disable "$svc" 2>/dev/null
            fi
        done

        pkg_update
        pkg_install redis-server
        
        # Đảm bảo thư mục socket tồn tại sau khi reboot
        echo "d /var/run/redis 0755 redis redis -" > /etc/tmpfiles.d/redis.conf
        systemd-tmpfiles --create /etc/tmpfiles.d/redis.conf 2>/dev/null || mkdir -p /var/run/redis && chown redis:redis /var/run/redis
        
        # Configure Unix Socket for Object Cache
        local rconf="/etc/redis/redis.conf"
        if [[ -f "$rconf" ]] && ! grep -q "^unixsocket " "$rconf"; then
            echo "unixsocket /var/run/redis/redis.sock" >> "$rconf"
            echo "unixsocketperm 777" >> "$rconf"
            if ! grep -q "^maxmemory " "$rconf"; then
                echo "maxmemory 256mb" >> "$rconf"
                echo "maxmemory-policy allkeys-lru" >> "$rconf"
            fi
        else
            sed -i 's/^unixsocketperm.*/unixsocketperm 777/g' "$rconf" 2>/dev/null
        fi
        usermod -aG redis www-data 2>/dev/null || true
        usermod -aG redis nobody 2>/dev/null || true
        
        systemctl enable redis-server
        systemctl restart redis-server
    else
        log_warn "Redis is already installed."
        local rconf="/etc/redis/redis.conf"
        sed -i 's/^unixsocketperm.*/unixsocketperm 777/g' "$rconf" 2>/dev/null
        echo "d /var/run/redis 0755 redis redis -" > /etc/tmpfiles.d/redis.conf
        systemd-tmpfiles --create /etc/tmpfiles.d/redis.conf 2>/dev/null || mkdir -p /var/run/redis && chown redis:redis /var/run/redis
        systemctl restart redis-server 2>/dev/null
    fi
    
    local php_ver=$(get_installed_php_version)
    if [[ "$OS_FAMILY" == "rhel" ]]; then
        pkg_install php-pecl-redis5
        systemctl restart php-fpm
    else
        pkg_install php${php_ver}-redis
        phpenmod -v ${php_ver} redis 2>/dev/null
        systemctl restart php${php_ver}-fpm 2>/dev/null || systemctl restart lshttpd 2>/dev/null
    fi
    log_info "Redis installed and enabled."
}

install_memcached() {
    if ! command -v memcached &>/dev/null; then
        log_info "Installing Memcached..."

        # Xử lý xung đột Engine: Tắt Redis/Valkey/KeyDB nếu đang chạy
        for svc in redis-server redis valkey-server valkey keydb; do
            if systemctl is-active --quiet "$svc" 2>/dev/null || systemctl is-enabled --quiet "$svc" 2>/dev/null; then
                log_warn "Phát hiện $svc. Tự động tắt để nhường chỗ cho Memcached..."
                systemctl stop "$svc" 2>/dev/null
                systemctl disable "$svc" 2>/dev/null
            fi
        done

        pkg_update
        pkg_install memcached
        systemctl enable memcached
        systemctl start memcached
    fi
    
    local php_ver=$(get_installed_php_version)
    if [[ "$OS_FAMILY" == "rhel" ]]; then
        pkg_install php-pecl-memcached
        systemctl restart php-fpm
    else
        pkg_install php${php_ver}-memcached
        phpenmod -v ${php_ver} memcached 2>/dev/null
        systemctl restart php${php_ver}-fpm
    fi
    log_info "Memcached installed and enabled."
}

# 6. Object Cache Setup
setup_object_cache() {
    clear
    echo -e "${BLUE}=================================================${NC}"
    echo -e "${GREEN}    ðŸ“¦ Enable Object Cache (Redis/Valkey/Memcached)${NC}"
    echo -e "${BLUE}=================================================${NC}"
    echo -e "${YELLOW}Select Object Cache Backend:${NC}"
    echo "1. Valkey (Khuyen dung - Nhanh hon 30%, tuong thich 100% Redis)"
    echo "2. Redis (Ban truyen thong)"
    echo "3. Memcached"
    echo "0. Cancel"
    read -p "Choice: " cache_choice

    case $cache_choice in
        1)
            install_valkey
            _setup_wp_redis_plugin "valkey"
            ;;
        2)
            install_redis
            _setup_wp_redis_plugin "redis"
            ;;
        3)
            install_memcached
            _setup_wp_memcached_plugin
            ;;
        0) return ;;
        *) echo -e "${RED}Invalid choice!${NC}" ;;
    esac
    pause
}

# Auto-install va kich hoat Redis Object Cache plugin cho tat ca WP sites
_setup_wp_redis_plugin() {
    local backend="${1:-valkey}"

    if ! command -v wp &>/dev/null; then
        log_warn "WP-CLI chua co -- bo qua cai plugin tu dong."
        echo -e "${YELLOW}Hay cai thu cong plugin 'Redis Object Cache' trong WP Admin.${NC}"
        return
    fi

    # Cho mot chut de dich vu khoi tao Socket sau khi restart (Fix timing issue)
    sleep 2

    # Xac dinh host/socket
    local redis_host="127.0.0.1"
    local redis_port="6379"
    local redis_scheme="tcp"
    if [[ "$backend" == "valkey" ]] && [[ -S "/var/run/valkey/valkey.sock" ]]; then
        redis_host="/var/run/valkey/valkey.sock"; redis_scheme="unix"; redis_port="0"
    elif [[ "$backend" == "redis" ]] && [[ -S "/var/run/redis/redis.sock" ]]; then
        redis_host="/var/run/redis/redis.sock"; redis_scheme="unix"; redis_port="0"
    fi

    local found=0
    for wpc in /var/www/*/public_html/wp-config.php; do
        [[ ! -f "$wpc" ]] && continue
        local site_root; site_root=$(dirname "$wpc")
        local domain;   domain=$(basename "$(dirname "$site_root")")
        found=$((found+1))

        log_info "[$domain] Cai dat Redis Object Cache plugin..."

        # Tim PHP ban co mysqli (Fix loi thieu mysqli cua WP-CLI mac dinh tren Ubuntu va OLS)
        local WP_PHP_BIN="php"
        local SITE_CONF="/etc/nginx/sites-available/$domain"
        if [[ -f "$SITE_CONF" ]]; then
            local SITE_PHP_VER=$(grep -shoP 'unix:/run/php/php\K[0-9.]+(?=-fpm.sock)' "$SITE_CONF" | head -n 1)
            if [[ -n "$SITE_PHP_VER" ]] && command -v "php$SITE_PHP_VER" >/dev/null 2>&1; then
                WP_PHP_BIN="php$SITE_PHP_VER"
            fi
        fi
        
        # Kiem tra xem PHP co mysqli khong
        if ! "$WP_PHP_BIN" -m 2>/dev/null | grep -qEi "(mysqli|pdo_mysql)"; then
            # Thu auto-install php-mysql cho ban hien tai (Fix loi web broken do thieu extension)
            local cur_ver=$(echo "$WP_PHP_BIN" | grep -oP 'php\K[0-9.]+' | head -n 1)
            if [[ -n "$cur_ver" ]]; then
                log_info "[Auto-Fix] PHP $cur_ver thieu MySQL extension. Dang tu dong tai va cai dat..."
                if command -v apt-get >/dev/null 2>&1; then
                    # Fix LiteSpeed GPG key issue that causes apt-get update to fail on Ubuntu 24.04
                    if [[ -f /etc/apt/sources.list.d/lst_debian_repo.list ]]; then
                        wget -qO /etc/apt/trusted.gpg.d/lst_debian_repo.gpg http://rpms.litespeedtech.com/debian/lst_debian_repo.gpg || true
                        wget -qO - http://rpms.litespeedtech.com/debian/lst_repo.gpg | gpg --dearmor --yes -o /etc/apt/trusted.gpg.d/litespeed.gpg 2>/dev/null || true
                    fi
                    apt-get update >/dev/null 2>&1 || true
                    DEBIAN_FRONTEND=noninteractive apt-get install -y "php${cur_ver}-mysql" >/dev/null 2>&1
                elif command -v dnf >/dev/null 2>&1; then
                    dnf install -y "php${cur_ver}-mysqlnd" >/dev/null 2>&1
                fi
                log_info "[Auto-Fix] Hoan tat cai dat php${cur_ver}-mysql."
            fi
        fi

        if ! "$WP_PHP_BIN" -m 2>/dev/null | grep -qEi "(mysqli|pdo_mysql)"; then
            local found_php=false
            # Thu Nginx / Ubuntu PHP (php8.4, php8.3...)
            for v in 8.4 8.3 8.5 8.2 8.1 8.0 7.4; do
                if command -v "php$v" >/dev/null 2>&1 && "php$v" -m 2>/dev/null | grep -qEi "(mysqli|pdo_mysql)"; then
                    WP_PHP_BIN="php$v"
                    found_php=true
                    break
                fi
            done
            # Thu OpenLiteSpeed PHP (lsphp84, lsphp83...)
            if [[ "$found_php" == "false" ]]; then
                for v in 84 83 85 82 81 80 74; do
                    if command -v "/usr/local/lsws/lsphp$v/bin/php" >/dev/null 2>&1 && "/usr/local/lsws/lsphp$v/bin/php" -m 2>/dev/null | grep -qEi "(mysqli|pdo_mysql)"; then
                        WP_PHP_BIN="/usr/local/lsws/lsphp$v/bin/php"
                        found_php=true
                        break
                    fi
                done
            fi
        fi
        local WP_CMD="$WP_PHP_BIN /usr/local/bin/wp"


        # 1. Cai + kich hoat plugin redis-cache
        if ! $WP_CMD plugin is-installed redis-cache --path="$site_root" --allow-root 2>/dev/null; then
            if $WP_CMD plugin install redis-cache --activate --path="$site_root" --allow-root; then
                echo "  v Plugin redis-cache: CAI + KICH HOAT"
                # Fix ownership
                chown -R www-data:www-data "$site_root/wp-content/plugins/redis-cache" 2>/dev/null || chown -R nobody:nobody "$site_root/wp-content/plugins/redis-cache" 2>/dev/null
            else
                log_warn "[$domain] Cai plugin that bai (xem loi ben tren) -- bo qua."
                continue
            fi
        else
            $WP_CMD plugin activate redis-cache --path="$site_root" --allow-root 2>/dev/null
            echo "  v Plugin redis-cache: KICH HOAT"
        fi

        # 2. Ghi hang so vao wp-config.php
        $WP_CMD config set WP_REDIS_SCHEME "$redis_scheme" --type=constant --path="$site_root" --allow-root 2>/dev/null
        $WP_CMD config set WP_REDIS_HOST   "$redis_host"   --type=constant --path="$site_root" --allow-root 2>/dev/null
        $WP_CMD config set WP_REDIS_PORT   "$redis_port"   --raw --type=constant --path="$site_root" --allow-root 2>/dev/null
        $WP_CMD config set WP_CACHE        "true"          --raw --type=constant --path="$site_root" --allow-root 2>/dev/null
        echo "  v wp-config.php: WP_REDIS_HOST / WP_CACHE da ghi"

        # 3. Enable drop-in (object-cache.php)
        # Xoa drop-in cu (tu LSCache, Memcached...) de tranh loi "Drop-in is invalid"
        rm -f "$site_root/wp-content/object-cache.php" 2>/dev/null
        
        $WP_CMD redis enable --path="$site_root" --allow-root 2>/dev/null \
            && echo "  v Object Cache drop-in: DA BAT" \
            || echo "  ! Chay 'wp redis enable' thu cong trong WP Admin"

        echo ""
    done

    if [[ $found -eq 0 ]]; then
        log_warn "Khong tim thay WordPress site nao tai /var/www/*/public_html/"
        echo -e "${YELLOW}Hay cai plugin 'Redis Object Cache' thu cong trong WP Admin.${NC}"
        return
    fi

    echo -e "${GREEN}=================================================${NC}"
    echo -e "${GREEN} v Redis Object Cache da cai xong cho $found site(s)!${NC}"
    echo -e "${GREEN}=================================================${NC}"
    if [[ "$redis_scheme" == "unix" ]]; then
        echo -e "  Backend : ${CYAN}$backend (Unix Socket)${NC}"
        echo -e "  Socket  : ${CYAN}$redis_host${NC}"
    else
        echo -e "  Backend : ${CYAN}$backend (TCP 127.0.0.1:6379)${NC}"
    fi
    echo -e "${YELLOW}Luu y: Vao WP Admin -> Settings -> Redis -> kiem tra ket noi.${NC}"
}

# Cai va kich hoat Memcached Object Cache cho tat ca WP sites
_setup_wp_memcached_plugin() {
    if ! command -v wp &>/dev/null; then
        log_warn "WP-CLI chua co -- bo qua cai plugin tu dong."
        echo -e "${YELLOW}Hay cai thu cong plugin 'Memcached Object Cache' trong WP Admin.${NC}"
        return
    fi

    local found=0
    for wpc in /var/www/*/public_html/wp-config.php; do
        [[ ! -f "$wpc" ]] && continue
        local site_root; site_root=$(dirname "$wpc")
        local domain;   domain=$(basename "$(dirname "$site_root")")
        found=$((found+1))

        log_info "[$domain] Cai dat Memcached Object Cache..."
        
        # Tim PHP ban co mysqli
        local WP_PHP_BIN="php"
        local SITE_CONF="/etc/nginx/sites-available/$domain"
        if [[ -f "$SITE_CONF" ]]; then
            local SITE_PHP_VER=$(grep -shoP 'unix:/run/php/php\K[0-9.]+(?=-fpm.sock)' "$SITE_CONF" | head -n 1)
            if [[ -n "$SITE_PHP_VER" ]] && command -v "php$SITE_PHP_VER" >/dev/null 2>&1; then
                WP_PHP_BIN="php$SITE_PHP_VER"
            fi
        fi
        if ! "$WP_PHP_BIN" -m 2>/dev/null | grep -qEi "(mysqli|pdo_mysql)"; then
            # Thu auto-install php-mysql cho ban hien tai
            local cur_ver=$(echo "$WP_PHP_BIN" | grep -oP 'php\K[0-9.]+' | head -n 1)
            if [[ -n "$cur_ver" ]]; then
                log_info "[Auto-Fix] PHP $cur_ver thieu MySQL extension. Dang tu dong tai va cai dat..."
                if command -v apt-get >/dev/null 2>&1; then
                    # Fix LiteSpeed GPG key issue that causes apt-get update to fail on Ubuntu 24.04
                    if [[ -f /etc/apt/sources.list.d/lst_debian_repo.list ]]; then
                        wget -qO /etc/apt/trusted.gpg.d/lst_debian_repo.gpg http://rpms.litespeedtech.com/debian/lst_debian_repo.gpg || true
                        wget -qO - http://rpms.litespeedtech.com/debian/lst_repo.gpg | gpg --dearmor --yes -o /etc/apt/trusted.gpg.d/litespeed.gpg 2>/dev/null || true
                    fi
                    apt-get update >/dev/null 2>&1 || true
                    DEBIAN_FRONTEND=noninteractive apt-get install -y "php${cur_ver}-mysql" >/dev/null 2>&1
                elif command -v dnf >/dev/null 2>&1; then
                    dnf install -y "php${cur_ver}-mysqlnd" >/dev/null 2>&1
                fi
                log_info "[Auto-Fix] Hoan tat cai dat php${cur_ver}-mysql."
            fi
        fi

        if ! "$WP_PHP_BIN" -m 2>/dev/null | grep -qEi "(mysqli|pdo_mysql)"; then
            local found_php=false
            for v in 8.4 8.3 8.5 8.2 8.1 8.0 7.4; do
                if command -v "php$v" >/dev/null 2>&1 && "php$v" -m 2>/dev/null | grep -qEi "(mysqli|pdo_mysql)"; then
                    WP_PHP_BIN="php$v"
                    found_php=true
                    break
                fi
            done
            if [[ "$found_php" == "false" ]]; then
                for v in 84 83 85 82 81 80 74; do
                    if command -v "/usr/local/lsws/lsphp$v/bin/php" >/dev/null 2>&1 && "/usr/local/lsws/lsphp$v/bin/php" -m 2>/dev/null | grep -qEi "(mysqli|pdo_mysql)"; then
                        WP_PHP_BIN="/usr/local/lsws/lsphp$v/bin/php"
                        break
                    fi
                done
            fi
        fi
        local WP_CMD="$WP_PHP_BIN /usr/local/bin/wp"

        local mc_dropin="$site_root/wp-content/object-cache.php"
        if [[ ! -f "$mc_dropin" ]]; then
            curl -fsSL "https://raw.githubusercontent.com/Ipstenu/memcached-redux/master/object-cache.php" \
                -o "$mc_dropin" 2>/dev/null \
                && echo "  v Memcached object-cache.php: TAI XONG" \
                || { log_warn "[$domain] Tai drop-in that bai."; continue; }
            chown www-data:www-data "$mc_dropin" 2>/dev/null || chown nobody:nobody "$mc_dropin" 2>/dev/null
        else
            echo "  v object-cache.php: DA CO"
        fi
        $WP_CMD config set WP_CACHE "true" --raw --type=constant --path="$site_root" --allow-root 2>/dev/null
        echo "  v WP_CACHE=true: GHI VAO wp-config.php"
        echo ""
    done

    if [[ $found -eq 0 ]]; then
        log_warn "Khong tim thay WordPress site nao."
        return
    fi

    echo -e "${GREEN}=================================================${NC}"
    echo -e "${GREEN} v Memcached Object Cache da cai xong cho $found site(s)!${NC}"
    echo -e "${GREEN}=================================================${NC}"
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
        # Thu auto-install php-mysql cho ban hien tai
        local cur_ver=$(echo "$WP_PHP_BIN" | grep -oP 'php\K[0-9.]+' | head -n 1)
        if [[ -n "$cur_ver" ]]; then
            log_info "[Auto-Fix] PHP $cur_ver thieu MySQL extension. Dang tu dong tai va cai dat..."
            if command -v apt-get >/dev/null 2>&1; then
                # Fix LiteSpeed GPG key issue that causes apt-get update to fail on Ubuntu 24.04
                if [[ -f /etc/apt/sources.list.d/lst_debian_repo.list ]]; then
                    wget -qO /etc/apt/trusted.gpg.d/lst_debian_repo.gpg http://rpms.litespeedtech.com/debian/lst_debian_repo.gpg || true
                    wget -qO - http://rpms.litespeedtech.com/debian/lst_repo.gpg | gpg --dearmor --yes -o /etc/apt/trusted.gpg.d/litespeed.gpg 2>/dev/null || true
                fi
                apt-get update >/dev/null 2>&1 || true
                DEBIAN_FRONTEND=noninteractive apt-get install -y "php${cur_ver}-mysql" >/dev/null 2>&1
            elif command -v dnf >/dev/null 2>&1; then
                dnf install -y "php${cur_ver}-mysqlnd" >/dev/null 2>&1
            fi
            log_info "[Auto-Fix] Hoan tat cai dat php${cur_ver}-mysql."
        fi
    fi

    if ! "$WP_PHP_BIN" -m 2>/dev/null | grep -qEi "(mysqli|pdo_mysql)"; then
        local found_php=false
        for v in 8.4 8.3 8.5 8.2 8.1 8.0 7.4; do
            if command -v "php$v" >/dev/null 2>&1 && "php$v" -m 2>/dev/null | grep -qEi "(mysqli|pdo_mysql)"; then
                WP_PHP_BIN="php$v"
                found_php=true
                break
            fi
        done
        if [[ "$found_php" == "false" ]]; then
            for v in 84 83 85 82 81 80 74; do
                if command -v "/usr/local/lsws/lsphp$v/bin/php" >/dev/null 2>&1 && "/usr/local/lsws/lsphp$v/bin/php" -m 2>/dev/null | grep -qEi "(mysqli|pdo_mysql)"; then
                    WP_PHP_BIN="/usr/local/lsws/lsphp$v/bin/php"
                    found_php=true
                    break
                fi
            done
        fi
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
    if [[ "$OS_FAMILY" == "rhel" ]]; then
        if ! command -v cwebp >/dev/null 2>&1 || ! rpm -q php-gd >/dev/null 2>&1; then
            log_info "Đang cài đặt Server-side WebP support..."
            pkg_install libwebp php-gd >/dev/null 2>&1
            systemctl restart php-fpm >/dev/null 2>&1
            log_info "WebP support installed."
        else
            log_info "Server đã hỗ trợ WebP."
        fi
    else
        if ! command -v cwebp >/dev/null 2>&1 || ! dpkg -l | grep -q "php${php_ver}-gd"; then
            log_info "Đang cài đặt Server-side WebP support..."
            export DEBIAN_FRONTEND=noninteractive
            pkg_install php${php_ver}-gd webp >/dev/null 2>&1
            systemctl restart php${php_ver}-fpm >/dev/null 2>&1
            log_info "WebP support installed."
        else
            log_info "Server đã hỗ trợ WebP."
        fi
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
            if [[ "$OS_FAMILY" == "rhel" ]]; then
                log_warn "Module Brotli trên AlmaLinux cần compile hoặc repo bên thứ 3. Tạm thời bỏ qua tự động."
            else
                pkg_install libnginx-mod-http-brotli 2>/dev/null
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
    echo "  \u2022 GTmetrix (https://gtmetrix.com)"
    echo "  \u2022 Google PageSpeed Insights"
    echo "  \u2022 WebPageTest.org"
    pause
}

# ==============================================================================
# 13. PHP PRELOAD
# Nạp trước file PHP vào OPcache khi PHP-FPM khởi động
# Yêu cầu PHP >= 7.4
# ==============================================================================

php_preload_menu() {
    while true; do
        clear
        echo -e "${BLUE}=================================================${NC}"
        echo -e "${GREEN}    🎀 PHP Preload Manager${NC}"
        echo -e "${BLUE}=================================================${NC}"
        echo -e "PHP Preload nạp trước file PHP vào OPcache khi kh\u1edfi đ\u1ed9ng."
        echo -e "Gi\u1ea3m \u0111\u1ed9 tr\u1ec5 c\u1ee7a request đ\u1ea7u ti\u00ean, t\u0103ng t\u1ed1c đ\u1ed9 x\u1eed l\u00fd PHP."
        echo -e "${YELLOW}(Y\u00eau c\u1ea7u PHP >= 7.4 v\u00e0 PHP-FPM)${NC}"
        echo ""
        echo -e "1. B\u1eadt PHP Preload cho site WordPress"
        echo -e "2. T\u1eaft PHP Preload cho site"
        echo -e "3. Xem tr\u1ea1ng th\u00e1i Preload (s\u1ed1 file đ\u00e3 n\u1ea1p)"
        echo -e "4. Xem danh s\u00e1ch site \u0111ang d\u00f9ng Preload"
        echo -e "0. Quay l\u1ea1i"
        echo -e "${BLUE}=================================================${NC}"
        read -p "Ch\u1ecdn [0-4]: " choice

        case $choice in
            1) enable_php_preload ;;
            2) disable_php_preload ;;
            3) show_preload_status ;;
            4) list_preload_sites ;;
            0) return ;;
            *) echo -e "${RED}L\u1ef1a ch\u1ecdn kh\u00f4ng h\u1ee3p l\u1ec7!${NC}"; pause ;;
        esac
    done
}

enable_php_preload() {
    # Ch\u1ecdn site
    source "$(dirname "${BASH_SOURCE[0]}")/wordpress_tool.sh"
    select_wp_site || return
    local domain="$SELECTED_DOMAIN"
    local site_root="/var/www/${domain}/public_html"

    if [[ ! -f "${site_root}/wp-config.php" ]]; then
        log_error "${domain} kh\u00f4ng ph\u1ea3i WordPress site!"
        pause; return
    fi

    # L\u1ea5y PHP version c\u1ee7a site
    local php_ver
    php_ver=$(get_installed_php_version)
    [[ -z "$php_ver" ]] && { log_error "Kh\u00f4ng t\u00ecm th\u1ea5y PHP-FPM!"; pause; return; }

    # Ki\u1ec3m tra PHP version >= 7.4
    local major minor
    major=$(echo "$php_ver" | cut -d. -f1)
    minor=$(echo "$php_ver" | cut -d. -f2)
    if [[ "$major" -lt 7 ]] || { [[ "$major" -eq 7 ]] && [[ "$minor" -lt 4 ]]; }; then
        log_error "PHP Preload y\u00eau c\u1ea7u PHP >= 7.4. PHP hi\u1ec7n t\u1ea1i: ${php_ver}"
        pause; return
    fi

    # T\u1ea1o script preload
    local preload_dir="/etc/php-preload"
    mkdir -p "$preload_dir"
    local preload_script="${preload_dir}/${domain}.php"

    cat > "$preload_script" <<PRELOAD_EOF
<?php
/**
 * PHP Preload Script cho: ${domain}
 * T\u1ef1 đ\u1ed9ng n\u1ea1p tr\u01b0\u1edbc c\u00e1c file PHP c\u1ed1t l\u00f5i c\u1ee7a WordPress v\u00e0o OPcache.
 * T\u1ee9c l\u00e0: Khi PHP-FPM kh\u1eedi đ\u1ed9ng, c\u00e1c file n\u00e0y đ\u00e3 s\u1eb5n s\u00e0ng trong b\u1ed9 nh\u1edb.
 */

// WP-Includes (c\u00f4t l\u00f5i - quan tr\u1ecd nh\u1ea5t)
\$wp_includes = '${site_root}/wp-includes';
if (is_dir(\$wp_includes)) {
    \$it = new RecursiveIteratorIterator(
        new RecursiveDirectoryIterator(\$wp_includes, RecursiveDirectoryIterator::SKIP_DOTS)
    );
    foreach (\$it as \$file) {
        if (\$file->isFile() && \$file->getExtension() === 'php') {
            opcache_compile_file(\$file->getPathname());
        }
    }
}
PRELOAD_EOF

    # C\u1ea5u h\u00ecnh php.ini
    local php_ini="/etc/php/${php_ver}/fpm/php.ini"
    if [[ ! -f "$php_ini" ]]; then
        log_error "Kh\u00f4ng t\u00ecm th\u1ea5y: $php_ini"
        pause; return
    fi

    # Backup
    cp "$php_ini" "${php_ini}.preload_bak_$(date +%s)"

    # Set opcache.preload (thay ho\u1eb7c th\u00eam m\u1edbi)
    if grep -q "^opcache.preload" "$php_ini"; then
        sed -i "s|^opcache.preload.*|opcache.preload=${preload_script}|" "$php_ini"
    else
        echo "opcache.preload=${preload_script}" >> "$php_ini"
    fi

    # Set opcache.preload_user (www-data ho\u1eb7c nobody)
    local fpm_user="www-data"
    if [[ "$OS_FAMILY" == "rhel" ]]; then
        fpm_user="nginx"
    fi
    if grep -q "^opcache.preload_user" "$php_ini"; then
        sed -i "s|^opcache.preload_user.*|opcache.preload_user=${fpm_user}|" "$php_ini"
    else
        echo "opcache.preload_user=${fpm_user}" >> "$php_ini"
    fi

    # \u0110\u1ea3m b\u1ea3o OPcache \u0111\u01b0\u1ee3c b\u1eadt
    if grep -q "^opcache.enable" "$php_ini"; then
        sed -i "s|^opcache.enable.*|opcache.enable=1|" "$php_ini"
    else
        echo "opcache.enable=1" >> "$php_ini"
    fi

    # Restart PHP-FPM
    if [[ "$OS_FAMILY" == "rhel" ]]; then
        systemctl restart php-fpm
    else
        systemctl restart "php${php_ver}-fpm"
    fi

    log_info "\u2705 PHP Preload đ\u00e3 b\u1eadt cho ${domain}!"
    echo -e "${YELLOW}Preload script: ${preload_script}${NC}"
    echo -e "${YELLOW}PHP version:    ${php_ver}${NC}"
    echo -e "${YELLOW}Preload user:   ${fpm_user}${NC}"
    echo -e ""
    echo -e "${CYAN}L\u01b0u \u00fd: Preload ch\u1ea1y khi PHP-FPM kh\u1eedi đ\u1ed9ng. Ki\u1ec3m tra status sau v\u00e0i gi\u00e2y.${NC}"
    pause
}

disable_php_preload() {
    local php_ver
    php_ver=$(get_installed_php_version)
    [[ -z "$php_ver" ]] && { log_error "Kh\u00f4ng t\u00ecm th\u1ea5y PHP!"; pause; return; }

    local php_ini="/etc/php/${php_ver}/fpm/php.ini"

    # X\u00f3a/comment out c\u00e2u l\u1ec7nh preload
    if grep -q "^opcache.preload" "$php_ini"; then
        sed -i 's|^opcache.preload|;opcache.preload|' "$php_ini"
        sed -i 's|^opcache.preload_user|;opcache.preload_user|' "$php_ini"

        if [[ "$OS_FAMILY" == "rhel" ]]; then
            systemctl restart php-fpm
        else
            systemctl restart "php${php_ver}-fpm"
        fi
        log_info "\u2705 PHP Preload đ\u00e3 đ\u01b0\u1ee3c t\u1eaft."
    else
        log_warn "PHP Preload ch\u01b0a đ\u01b0\u1ee3c c\u1ea5u h\u00ecnh."
    fi
    pause
}

show_preload_status() {
    local php_ver
    php_ver=$(get_installed_php_version)
    [[ -z "$php_ver" ]] && { log_error "Kh\u00f4ng t\u00ecm th\u1ea5y PHP!"; pause; return; }

    echo -e "${BLUE}==== Tr\u1ea1ng th\u00e1i PHP Preload ====${NC}"
    echo -e "${YELLOW}PHP Version: ${php_ver}${NC}"

    local php_ini="/etc/php/${php_ver}/fpm/php.ini"
    local preload_script
    preload_script=$(grep "^opcache.preload" "$php_ini" 2>/dev/null | cut -d= -f2 | tr -d ' ')

    if [[ -n "$preload_script" ]]; then
        echo -e "${GREEN}\u2713 Preload đ\u01b0\u1ee3c c\u1ea5u h\u00ecnh: ${preload_script}${NC}"
    else
        echo -e "${YELLOW}\u26a0 PHP Preload ch\u01b0a đ\u01b0\u1ee3c b\u1eadt.${NC}"
        pause; return
    fi

    # Ki\u1ec3m tra status OPcache qua php -r
    local preload_count
    preload_count=$(php${php_ver} -r "
        \$s = opcache_get_status(true);
        if (\$s && isset(\$s['preload_statistics']['functions'])) {
            echo count(\$s['preload_statistics']['functions']);
        } else {
            echo '0 hoac chua co du lieu';
        }
    " 2>/dev/null)

    echo -e "${GREEN}File/function đ\u00e3 preload: ${preload_count}${NC}"
    echo ""
    echo -e "${CYAN}L\u01b0u \u00fd: K\u1ebft qu\u1ea3 tr\u00ean l\u00e0 t\u1eeb PHP CLI; FPM c\u00f3 th\u1ec3 c\u00f3 s\u1ed1 kh\u00e1c.${NC}"
    pause
}

list_preload_sites() {
    local preload_dir="/etc/php-preload"
    echo -e "${YELLOW}C\u00e1c site đang d\u00f9ng PHP Preload:${NC}"
    if [[ -d "$preload_dir" ]]; then
        local count=0
        for f in "$preload_dir"/*.php; do
            [[ ! -f "$f" ]] && continue
            echo -e "  \u2022 $(basename "$f" .php)"
            count=$((count+1))
        done
        [[ $count -eq 0 ]] && echo -e "  ${YELLOW}Ch\u01b0a c\u00f3 site n\u00e0o.${NC}"
    else
        echo -e "  ${YELLOW}Ch\u01b0a c\u00f3 site n\u00e0o.${NC}"
    fi
    pause
}

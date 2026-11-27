#!/bin/bash

# modules/wordpress_performance.sh - WordPress Performance Optimization

# Helper dùng chung cho WordPress/Object Cache nằm ở cache.sh
# (_wp_config_path, _wp_list_sites, _wp_config_put_define, _wp_redis_*, _oc_*)
# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/cache.sh"

# Helper: Get ACTIVE PHP-FPM version (not CLI version which may differ)
get_installed_php_version() {
    # RHEL / Oracle Linux: 1 bản PHP theo module stream, không có /etc/php/X.Y
    if [[ "${OS_FAMILY:-}" == "rhel" ]]; then
        local rv
        rv=$(php_default_version)
        if [[ -n "$rv" ]]; then echo "$rv"; return 0; fi
        echo ""; return 1
    fi

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
    fpm_bin=$(command -v php-fpm8.4 php-fpm8.3 php-fpm8.2 php-fpm8.1 php-fpm 2>/dev/null | head -1)
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

_wp_php_has_mysql() {
    local php_bin="${1:-php}"
    "$php_bin" -m 2>/dev/null | grep -qEi '^(mysqli|pdo_mysql)$'
}

_wp_php_version() {
    local php_bin="${1:-php}"
    local ver
    ver=$(echo "$php_bin" | grep -oP 'php\K[0-9.]+$' | head -n 1)
    if [[ -z "$ver" ]]; then
        ver=$("$php_bin" -r "echo PHP_MAJOR_VERSION . '.' . PHP_MINOR_VERSION;" 2>/dev/null)
    fi
    echo "$ver"
}

_wp_enable_php_mysql_extension() {
    local php_bin="${1:-php}"
    local ver
    ver=$(_wp_php_version "$php_bin")
    [[ -z "$ver" ]] && return 1

    log_info "[Auto-Fix] PHP $ver thieu MySQL extension. Dang tu dong tai va cai dat/bat extension..."
    if [[ "${OS_FAMILY:-}" == "rhel" ]]; then
        pkg_install php-mysqlnd >/dev/null 2>&1 || true
    else
        pkg_update > /dev/null 2>&1 || true
        pkg_install "php${ver}-mysql" > /dev/null 2>&1 || true
    fi

    if command -v phpenmod >/dev/null 2>&1; then
        phpenmod -v "$ver" mysqli pdo_mysql mysqlnd >/dev/null 2>&1 || true
        phpenmod mysqli pdo_mysql mysqlnd >/dev/null 2>&1 || true
    fi

    if _wp_php_has_mysql "$php_bin"; then
        log_info "[Auto-Fix] PHP $ver da bat mysqli/pdo_mysql."
        # Reload PHP-FPM so Nginx picks up the new extension
        if systemctl list-units --type=service --state=running 2>/dev/null | grep -q "php${ver}-fpm"; then
            systemctl reload "php${ver}-fpm" > /dev/null 2>&1 || true
        elif systemctl list-units --type=service --state=running 2>/dev/null | grep -q "php-fpm"; then
            systemctl reload php-fpm > /dev/null 2>&1 || true
        fi
        return 0
    fi

    log_warn "[Auto-Fix] PHP $ver van chua load mysqli/pdo_mysql."
    return 1
}

_wp_resolve_php_bin_for_site() {
    local domain="$1"
    local outvar="$2"
    local preferred="php"
    local site_conf="/etc/nginx/sites-available/$domain"
    local site_php_ver

    if [[ -f "$site_conf" ]]; then
        site_php_ver=$(grep -v '^[[:space:]]*#' "$site_conf" 2>/dev/null | grep 'fastcgi_pass' | grep -oP 'php\K[0-9.]+(?=-fpm)' | head -n 1)
        if [[ -n "$site_php_ver" ]] && command -v "php$site_php_ver" >/dev/null 2>&1; then
            preferred="php$site_php_ver"
        fi
    fi

    if _wp_php_has_mysql "$preferred" || _wp_enable_php_mysql_extension "$preferred"; then
        printf -v "$outvar" '%s' "$preferred"
        return 0
    fi

    local v bin
    for v in 8.4 8.3 8.5 8.2 8.1 8.0 7.4; do
        bin="php$v"
        if command -v "$bin" > /dev/null 2>&1 && _wp_php_has_mysql "$bin"; then
            printf -v "$outvar" '%s' "$bin"
            return 0
        fi
    done

    printf -v "$outvar" '%s' "$preferred"
    return 1
}

# Chuẩn bị WP-CLI cho 1 site: đặt biến WEB_ROOT và WP_CMD (chạy bằng user của site, KHÔNG dùng root).
# Dùng trong hàm đã khai báo: local WEB_ROOT WP_CMD;  _wp_prepare_cli "$domain" || return
_wp_prepare_cli() {
    local domain=$1 php_bin="php"
    WEB_ROOT="/var/www/$domain/public_html"
    if ! _wp_config_path "$domain" >/dev/null; then
        echo -e "${RED}$domain không phải WordPress site.${NC}"
        return 1
    fi
    ensure_wp_cli || return 1
    if ! _wp_resolve_php_bin_for_site "$domain" php_bin; then
        log_warn "[$domain] PHP CLI vẫn thiếu mysqli/pdo_mysql sau auto-fix -- bỏ qua."
        return 1
    fi
    WP_CMD=$(wp_cmd_prefix "$WEB_ROOT" "$php_bin")
    return 0
}

# Chạy 1 hàm cho 1 site được chọn hoặc TẤT CẢ WordPress site.
# Dùng: _wp_run_scoped <tên hàm nhận domain> [hàm chạy 1 lần trước khi lặp]
_wp_run_scoped() {
    local callback=$1 pre=${2:-}
    local scope domain c found=0 all_sites=()

    echo -e "Phạm vi áp dụng:"
    echo -e "  1. Chọn 1 website cụ thể"
    echo -e "  2. Áp dụng cho TẤT CẢ WordPress sites"
    echo -e "  0. Hủy"
    read -p "Chọn: " scope

    case $scope in
        1)
            source "$(dirname "${BASH_SOURCE[0]}")/wordpress_tool.sh"
            select_wp_site || return 1
            [[ -n "$pre" ]] && "$pre"
            "$callback" "$SELECTED_DOMAIN"
            ;;
        2)
            all_sites=($(_wp_list_sites))
            found=${#all_sites[@]}
            if [[ "$found" -eq 0 ]]; then
                echo -e "${RED}Không có site WordPress nào.${NC}"
                return 1
            fi
            echo -e "${YELLOW}Áp dụng cho TẤT CẢ WordPress sites:${NC}"
            for domain in "${all_sites[@]}"; do echo "  → $domain"; done
            echo ""
            read -p "Tiếp tục cho $found site? [y/N]: " c
            [[ "$c" != "y" && "$c" != "Y" ]] && return 1
            [[ -n "$pre" ]] && "$pre"
            for domain in "${all_sites[@]}"; do
                "$callback" "$domain"
            done
            ;;
        *) return 1 ;;
    esac
    return 0
}


wp_performance_menu() {
    while true; do
        clear
        echo -e "${BLUE}=================================================${NC}"
        echo -e "${GREEN}    🚀 WordPress Performance Optimization${NC}"
        echo -e "${YELLOW}           (Mode: Nginx LEMP)${NC}"
        echo -e "${BLUE}=================================================${NC}"
        echo -e "${CYAN}--- ⚙️  Server-level (Toàn bộ server) ---${NC}"
        echo -e "1.  🚀 Auto-Optimize Server (PHP + MySQL + Nginx + OPcache)"
        echo -e "2.  ⚡ PHP-FPM Tuning (Áp lại workers/memory theo RAM)"
        echo -e "3.  💾 OPcache Optimization"
        echo -e "4.  🗄️  MySQL/MariaDB Tuning (Áp lại theo RAM)"
        echo -e "5.  🔥 Nginx FastCGI Cache (Tạo/sửa cấu hình cache zone)"
        echo -e "6.  🌐 HTTP/2 & Brotli Compression"
        echo -e "7.  🔧 System Kernel Tuning (TCP BBR, File Limits)"
        echo -e "8.  💾 Tối ưu Disk I/O (noatime + XFS)"
        echo -e "9.  🧠 RAM Disk FastCGI Cache (tmpfs trên RAM - TTFB 5-15ms)"
        echo -e ""
        echo -e "${CYAN}--- 🌐 Per-Site (Chọn từng website) ---${NC}"
        echo -e "10. 🧹 Database Cleanup & Optimization"
        echo -e "11. 🎯 Disable WordPress Bloat (Revisions, Autosave, Trash)"
        echo -e "12. 🖼️  Image Optimization Setup"
        echo -e "13. 🔥 Preload Cache (Warm-up Sitemap)"
        echo -e "14. ⚡ Fix TBT/Render-Blocking Nâng Cao (ElementsKit, FontAwesome)"
        echo -e "15. ⚡ Instant.page (Chuyển trang 0ms) & Tắt WC Cart Fragments"
        echo -e "16. 📊 Performance Benchmark Test"
        echo -e ""
        echo -e "${CYAN}Object Cache (Valkey/Redis): Menu chính -> Quản lý Cache -> mục 8${NC}"
        echo -e "0.  Quay lại Menu chính"
        echo -e "${BLUE}=================================================${NC}"
        read -p "Select [0-16]: " choice

        case $choice in
            1) auto_optimize_server ;;
            2) tune_php_fpm ;;
            3) optimize_opcache ;;
            4) tune_mysql ;;
            5) setup_fastcgi_microcache ;;
            6) enable_http2_brotli ;;
            7) optimize_system_kernel ;;
            8) optimize_disk_io ;;
            9) setup_tmpfs_fastcgi_cache ;;
            10) cleanup_wordpress_db ;;
            11) disable_wordpress_bloat ;;
            12) setup_image_optimization ;;
            13) preload_cache_sitemap ;;
            14) fix_tbt_advanced ;;
            15) setup_instant_page_optimizer ;;
            16) benchmark_wordpress ;;
            0) return ;;
            *) echo -e "${RED}Invalid choice!${NC}"; pause ;;
        esac
    done
}


# 15. Fix TBT/Render-Blocking Nâng Cao (Nginx)
# Áp dụng: MU Plugin PHP + Nginx headers + WP-CLI
fix_tbt_advanced() {
    clear
    echo -e "${BLUE}=================================================${NC}"
    echo -e "${GREEN}    ⚡ Fix TBT/Render-Blocking Nâng Cao (Nginx)${NC}"
    echo -e "${BLUE}=================================================${NC}"
    echo -e "Fix chuyên sâu cho: ElementsKit, jNews, FontAwesome, WP Smush"
    echo -e "Mục tiêu: TBT 720ms → <200ms | Nginx LEMP native"
    echo ""

    source "$(dirname "${BASH_SOURCE[0]}")/wordpress_tool.sh" 2>/dev/null || true
    select_wp_site || return
    local domain=$SELECTED_DOMAIN
    local site_root="/var/www/$domain/public_html"
    local nginx_conf="/etc/nginx/sites-available/$domain"

    if ! _wp_config_path "$domain" >/dev/null; then
        log_error "Không tìm thấy WordPress tại $site_root"
        pause; return
    fi
    local site_user
    site_user=$(site_owner "$site_root")

    # ── 1. MU Plugin: Resource Hints + FontAwesome Async + Delay JS ──────────
    log_info "1. Tạo MU Plugin 'vps-performance-hints.php'..."
    local mu_dir="$site_root/wp-content/mu-plugins"
    mkdir -p "$mu_dir"
    cat > "$mu_dir/vps-performance-hints.php" << 'PHPEOF'
<?php
/**
 * Plugin Name: VPS Performance Hints (Nginx)
 * Description: Resource Hints, Async CSS/JS, Preconnect để giảm TBT/LCP trên Nginx LEMP
 * Version: 2.1
 */
if ( ! defined( 'ABSPATH' ) ) exit;

/**
 * Chỉ tối ưu ở FRONT-END cho khách xem trang.
 * Không đụng tới wp-admin, trang đăng nhập, Customizer, REST/AJAX, cron, feed,
 * và các trình dựng trang (Elementor / Beaver / Divi / Bricks) ở chế độ chỉnh sửa.
 */
function vps_perf_is_frontend() {
    if ( is_admin() || wp_doing_ajax() || wp_doing_cron() ) return false;
    if ( defined( 'REST_REQUEST' ) && REST_REQUEST ) return false;
    if ( defined( 'XMLRPC_REQUEST' ) && XMLRPC_REQUEST ) return false;
    if ( defined( 'WP_CLI' ) && WP_CLI ) return false;
    if ( isset( $GLOBALS['pagenow'] ) && in_array( $GLOBALS['pagenow'], [ 'wp-login.php', 'wp-register.php' ], true ) ) return false;
    if ( function_exists( 'is_customize_preview' ) && is_customize_preview() ) return false;
    if ( function_exists( 'is_feed' ) && is_feed() ) return false;
    foreach ( [ 'elementor-preview', 'fl_builder', 'et_fb', 'bricks', 'vc_editable', 'preview' ] as $q ) {
        if ( isset( $_GET[ $q ] ) ) return false;
    }
    return true;
}

// --- Preconnect & DNS-Prefetch ---
add_action( 'wp_head', 'vps_add_resource_hints', 1 );
function vps_add_resource_hints() {
    echo "<link rel='preconnect' href='https://fonts.googleapis.com' crossorigin>\n";
    echo "<link rel='preconnect' href='https://fonts.gstatic.com' crossorigin>\n";
    echo "<link rel='dns-prefetch' href='//www.google-analytics.com'>\n";
    echo "<link rel='dns-prefetch' href='//kit.fontawesome.com'>\n";
}

// --- FontAwesome & ElementsKit CSS: async (không render-blocking) ---
add_filter( 'style_loader_tag', 'vps_async_render_blocking_css', 10, 4 );
function vps_async_render_blocking_css( $tag, $handle, $href, $media ) {
    if ( ! vps_perf_is_frontend() ) return $tag;
    $async_handles = [
        'font-awesome', 'font-awesome-5', 'fontawesome-all', 'fa-free',
        'elementor-icons', 'elementor-frontend',
    ];
    if ( in_array( $handle, $async_handles, true ) ) {
        $tag = str_replace(
            "rel='stylesheet'",
            "rel='preload' as='style' onload=\"this.onload=null;this.rel='stylesheet'\"",
            $tag
        );
        $tag .= "<noscript><link rel='stylesheet' href='" . esc_url( $href ) . "'></noscript>\n";
    }
    return $tag;
}

// --- Defer JS (trừ jQuery và wc-cart-fragments) ---
add_filter( 'script_loader_tag', 'vps_defer_js_except_critical', 10, 3 );
function vps_defer_js_except_critical( $tag, $handle, $src ) {
    if ( ! vps_perf_is_frontend() ) return $tag;
    $no_defer = [
        'jquery-core', 'jquery', 'jquery-migrate',
        'wc-cart-fragments', 'js_composer', 'revslider',
        'wp-i18n', 'wp-hooks', 'wp-polyfill',
    ];
    if ( in_array( $handle, $no_defer, true ) ) {
        return $tag;
    }
    // Script module / đã async / đã defer: giữ nguyên
    if ( strpos( $tag, ' defer' ) !== false || strpos( $tag, ' async' ) !== false || strpos( $tag, 'type="module"' ) !== false || strpos( $tag, "type='module'" ) !== false ) {
        return $tag;
    }
    // Script có inline "after" (wp_add_inline_script) phải chạy NGAY SAU file này.
    // Nếu defer file chính, đoạn inline sẽ chạy trước và báo lỗi "... is not defined" -> không defer.
    $wp_scripts = wp_scripts();
    if ( $wp_scripts->get_data( $handle, 'after' ) ) {
        return $tag;
    }
    // Script mà một script KHÔNG defer khác phụ thuộc vào (vd phụ thuộc của script có inline "after")
    static $needed_sync = null;
    if ( null === $needed_sync ) {
        $needed_sync = [];
        foreach ( array_keys( (array) $wp_scripts->registered ) as $h ) {
            if ( in_array( $h, $no_defer, true ) || $wp_scripts->get_data( $h, 'after' ) ) {
                $stack = isset( $wp_scripts->registered[ $h ] ) ? (array) $wp_scripts->registered[ $h ]->deps : [];
                while ( $stack ) {
                    $d = array_pop( $stack );
                    if ( isset( $needed_sync[ $d ] ) ) continue;
                    $needed_sync[ $d ] = true;
                    if ( isset( $wp_scripts->registered[ $d ] ) ) {
                        $stack = array_merge( $stack, (array) $wp_scripts->registered[ $d ]->deps );
                    }
                }
            }
        }
    }
    if ( isset( $needed_sync[ $handle ] ) ) {
        return $tag;
    }
    return str_replace( ' src=', ' defer src=', $tag );
}

// --- font-display: swap cho Google Fonts ---
add_filter( 'style_loader_src', 'vps_gfonts_display_swap' );
function vps_gfonts_display_swap( $href ) {
    if ( strpos( $href, 'fonts.googleapis.com' ) !== false && strpos( $href, 'display=' ) === false ) {
        $href = add_query_arg( 'display', 'swap', $href );
    }
    return $href;
}
PHPEOF
    chown "$site_user:$site_user" "$mu_dir" "$mu_dir/vps-performance-hints.php" 2>/dev/null || true
    echo -e "  ${GREEN}✓${NC} MU Plugin tạo xong: $mu_dir/vps-performance-hints.php"

    # ── 2. Nginx: Thêm Preload & performance snippet cho vhost ──────────────────
    log_info "2. Thêm Nginx performance snippet cho $domain..."
    local snippet_file="/etc/nginx/snippets/vps-tbt-${domain}.conf"
    local nginx_ok=0
    if [[ -f "$nginx_conf" ]]; then
        mkdir -p /etc/nginx/snippets
        # Chỉ header Link (preconnect). X-Content-Type-Options đã có trong security-headers.conf.
        cat > "$snippet_file" << 'SNIPEOF'
# vps-manager-tbt: Performance Headers (Nginx-native)
add_header Link "<https://fonts.googleapis.com>; rel=preconnect" always;
add_header Link "<https://fonts.gstatic.com>; rel=preconnect; crossorigin=anonymous" always;
SNIPEOF
        echo -e "  ${GREEN}✓${NC} Snippet tạo xong: $snippet_file"

        # Include có test + tự hoàn tác vhost nếu nginx -t lỗi
        if grep -qF "include $snippet_file;" "$nginx_conf"; then
            echo -e "  ${YELLOW}→${NC} Snippet đã được include"
            nginx_test_reload && nginx_ok=1
        elif nginx_add_include "$nginx_conf" "$snippet_file"; then
            nginx_ok=1
        fi
        if [[ "$nginx_ok" -eq 1 ]]; then
            echo -e "  ${GREEN}✓${NC} Nginx reload thành công"
        else
            echo -e "  ${RED}✗${NC} Nginx chưa nhận snippet (vhost đã được giữ nguyên) – xem lỗi ở trên"
        fi
    else
        log_warn "Không tìm thấy Nginx config: $nginx_conf"
    fi

    # ── 3. WP-CLI: Flush permalink & cache ────────────────────────────────────
    local WEB_ROOT WP_CMD
    if _wp_prepare_cli "$domain"; then
        log_info "3. Flush permalink và transient cache..."
        $WP_CMD rewrite flush > /dev/null 2>&1 && \
            echo -e "  ${GREEN}✓${NC} Permalink flush xong"
        $WP_CMD transient delete --all > /dev/null 2>&1 && \
            echo -e "  ${GREEN}✓${NC} Transient cache đã xóa"
        $WP_CMD cache flush > /dev/null 2>&1 && \
            echo -e "  ${GREEN}✓${NC} Object cache flush xong"
    else
        log_warn "WP-CLI chưa dùng được – bỏ qua bước flush cache."
    fi

    echo ""
    echo -e "${GREEN}=================================================${NC}"
    echo -e "${GREEN} ✓ Fix TBT Nâng Cao (Nginx) hoàn tất cho $domain!${NC}"
    echo -e "${GREEN}=================================================${NC}"
    echo -e "  ${GREEN}✓${NC} MU Plugin async CSS/JS: ĐÃ TẠO (chỉ chạy ở front-end, không ảnh hưởng wp-admin)"
    echo -e "  ${GREEN}✓${NC} FontAwesome + ElementsKit: ASYNC (không render-blocking)"
    echo -e "  ${GREEN}✓${NC} Defer JS (trừ jQuery, WC fragments, script có inline phụ thuộc): ĐÃ BẬT"
    echo -e "  ${GREEN}✓${NC} Google Fonts display=swap: ĐÃ BẬT"
    echo -e "  ${GREEN}✓${NC} Preconnect hints: ĐÃ THÊM vào <head>"
    if [[ "$nginx_ok" -eq 1 ]]; then
        echo -e "  ${GREEN}✓${NC} Nginx header preconnect: ĐÃ ÁP DỤNG"
    else
        echo -e "  ${YELLOW}!${NC} Nginx header preconnect: CHƯA áp dụng"
    fi
    echo ""
    echo -e "${YELLOW}Dự kiến kết quả:${NC}"
    echo -e "  TBT: 720ms → <200ms"
    echo -e "  LCP: 1.5s  → <1.2s"
    echo ""
    echo -e "${YELLOW}Lưu ý:${NC}"
    echo -e "  - Test lại trên PageSpeed sau 3-5 phút"
    echo -e "  - Nếu layout bị vỡ: xóa file $mu_dir/vps-performance-hints.php"
    echo -e "  - Nếu nút bấm mất tác dụng: thêm handle JS vào mảng \$no_defer trong MU plugin"
    pause
}


# 8. System Kernel Tuning
# Chỉ có MỘT bộ tối ưu kernel: core/kernel_tuning.sh (run_system_optimization).
# Hàm này gọi lại bộ đó và dọn các file trùng lặp do phiên bản cũ của menu này tạo ra.
optimize_system_kernel() {
    log_info "Tối ưu hệ thống (Kernel, TCP, THP, File limits)..."

    if ! declare -F run_system_optimization >/dev/null; then
        # shellcheck disable=SC1091
        source "$(dirname "${BASH_SOURCE[0]}")/../core/kernel_tuning.sh" 2>/dev/null
    fi
    if ! declare -F run_system_optimization >/dev/null; then
        log_error "Không nạp được core/kernel_tuning.sh."
        pause; return 1
    fi

    # Dọn bản trùng lặp cũ: /etc/sysctl.d/101-vpsmanager.conf và vpsmanager-disable-thp.service
    local old_sysctl="/etc/sysctl.d/101-vpsmanager.conf"
    local old_thp="/etc/systemd/system/vpsmanager-disable-thp.service"
    if [[ -f "$old_sysctl" ]] && grep -q "vpsmanager-kernel" "$old_sysctl" 2>/dev/null; then
        rm -f "$old_sysctl"
        log_info "Đã gỡ file sysctl trùng lặp cũ: $old_sysctl"
    fi
    if [[ -f "$old_thp" ]]; then
        systemctl disable vpsmanager-disable-thp.service >/dev/null 2>&1
        rm -f "$old_thp"
        systemctl daemon-reload
        log_info "Đã gỡ unit THP trùng lặp cũ: vpsmanager-disable-thp.service"
    fi

    run_system_optimization
    sysctl --system >/dev/null 2>&1 || true

    echo -e "${YELLOW}Ghi chú: menu này KHÔNG còn ghi đè /etc/resolv.conf. Nếu bản cũ đã đổi DNS sang 1.1.1.1/8.8.8.8"
    echo -e "và máy chủ cần DNS nội bộ của nhà cung cấp, hãy khôi phục /etc/resolv.conf thủ công.${NC}"
    pause
}

# 14. Preload Cache - Warm-up toàn bộ Sitemap
preload_cache_sitemap() {
    clear
    echo -e "${BLUE}=================================================${NC}"
    echo -e "${GREEN}    🔥 Preload Cache - Warm-up Sitemap${NC}"
    echo -e "${BLUE}=================================================${NC}"
    echo -e "Chức năng này crawl toàn bộ sitemap.xml để làm nóng Nginx FastCGI Cache"
    echo -e "Kết quả: khách (và Google) nhận trang từ cache ngay lần truy cập đầu tiên"
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
        status=$(curl -sk --max-time 10             --connect-to "${domain_host}::127.0.0.1:443"             --connect-to "${domain_host}::127.0.0.1:80"             -o /dev/null -w "%{http_code}"             -H "User-Agent: vps-manager-cache-warmer"             -H "Accept-Encoding: gzip, deflate, br"             "$url" 2>/dev/null)

        if [[ "$status" == "200" ]]; then
            echo -e "  ${GREEN}[$count/$total_urls]${NC} $url -> ${GREEN}OK${NC}"
        else
            echo -e "  ${YELLOW}[$count/$total_urls]${NC} $url -> ${YELLOW}$status${NC}"
        fi

        # Mobile request (neu chon)
        if [[ "$with_mobile" == "y" || "$with_mobile" == "Y" ]]; then
            curl -sk --max-time 10                 --connect-to "${domain_host}::127.0.0.1:443"                 --connect-to "${domain_host}::127.0.0.1:80"                 -o /dev/null                 -H "User-Agent: vps-manager-cache-warmer iPhone"                 -H "Accept-Encoding: gzip, deflate, br"                 "$url" 2>/dev/null
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

# 9. Optimize Disk I/O - noatime + XFS logbsize
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

    local fstab_new
    fstab_new=$(mktemp) || { log_error "Khong tao duoc file tam."; pause; return; }

    # Them noatime va logbsize vao fstab
    awk -v fstype="$ROOT_FSTYPE" '{
        if ($1 !~ /^#/ && $2 == "/") {
            if ($4 !~ /noatime/) { $4 = $4 ",noatime" }
            if (fstype == "xfs" && $4 !~ /logbsize=256k/) { $4 = $4 ",logbsize=256k" }
        }
        print $0
    }' /etc/fstab > "$fstab_new"

    # Kiem tra file moi hop le
    if [[ -s "$fstab_new" ]]; then
        cat "$fstab_new" > /etc/fstab
        rm -f "$fstab_new"
        log_info "  v /etc/fstab: da them noatime"
    else
        log_error "Tao fstab moi that bai! Da hoan nguyen tu backup."
        cat /etc/fstab.vpsmanager.bak > /etc/fstab
        rm -f "$fstab_new"
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
    echo -e "  v Tac dong: Nginx + MariaDB + PHP doc file nhanh hon"
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
    echo -e "Sẽ tối ưu:"
    echo "  ✓ PHP-FPM (số worker theo ngân sách RAM chung của server)"
    echo "  ✓ OPcache"
    echo "  ✓ MySQL/MariaDB (InnoDB buffer ~25% RAM, cùng công thức với trình cài đặt)"
    echo "  ✓ Nginx FastCGI Cache zone"
    echo ""
    echo -e "${YELLOW}Các bước theo từng site nằm ở menu riêng:${NC}"
    echo "  → Mục 10: Dọn Database từng site"
    echo "  → Mục 11: Tắt Bloat từng site"
    echo "  → Mục 16: Benchmark từng site"
    echo ""
    read -p "Tiếp tục? [y/N]: " confirm
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then return; fi

    local failed=0
    tune_php_fpm "auto" || failed=$((failed + 1))
    optimize_opcache "auto" || failed=$((failed + 1))
    tune_mysql "auto" || failed=$((failed + 1))
    setup_fastcgi_microcache "auto" || failed=$((failed + 1))

    echo ""
    if [[ "$failed" -eq 0 ]]; then
        log_info "✅ Tối ưu server hoàn tất!"
    else
        log_warn "Tối ưu server xong nhưng có $failed bước KHÔNG áp dụng được - xem thông báo lỗi ở trên."
    fi
    pause
}

# 2. PHP-FPM Tuning - áp lại theo RAM cho pool mặc định (www)
# Dùng chung ngân sách với trình cài đặt: core php_fpm_children_budget (~40% RAM cho toàn bộ PHP).
tune_php_fpm() {
    local auto_mode=${1:-}
    log_info "Tuning PHP-FPM for WordPress..."

    local php_ver
    php_ver=$(get_installed_php_version)
    if [[ -z "$php_ver" ]]; then
        log_error "Không tìm thấy PHP-FPM cài đặt!"
        [[ -z "$auto_mode" ]] && pause
        return 1
    fi
    log_info "PHP-FPM version: $php_ver"

    local pool_dir fpm_conf php_ini
    pool_dir=$(php_fpm_pool_dir "$php_ver")
    fpm_conf="${pool_dir}/www.conf"
    php_ini=$(php_ini_path "$php_ver")
    if [[ ! -f "$fpm_conf" ]]; then
        log_error "Không tìm thấy cấu hình pool PHP-FPM: $fpm_conf - chưa thay đổi gì."
        [[ -z "$auto_mode" ]] && pause
        return 1
    fi

    # Backup (đặt ngoài pool.d để FPM không nạp nhầm file backup)
    local bak_dir="/root/.vps-manager/backups"
    mkdir -p "$bak_dir"
    local bak="${bak_dir}/www.conf.${php_ver}.$(date +%s)"
    cp -p "$fpm_conf" "$bak"
    local ini_bak=""
    if [[ -f "$php_ini" ]]; then
        ini_bak="${bak_dir}/php.ini.${php_ver}.$(date +%s)"
        cp -p "$php_ini" "$ini_bak"
    fi

    # Ngân sách worker cho TOÀN server. Nếu có pool riêng theo site, pool chung chỉ nhận một nửa.
    local budget other_pools max_children start_servers min_spare max_spare
    budget=$(php_fpm_children_budget)
    other_pools=$(ls "$pool_dir"/*.conf 2>/dev/null | grep -vc '/www\.conf$')
    max_children=$budget
    if [[ "$other_pools" -gt 0 ]]; then
        max_children=$(( budget / 2 ))
        log_info "Có $other_pools pool riêng theo site -> pool chung nhận 1/2 ngân sách ($budget worker)."
    fi
    [[ "$max_children" -lt 4 ]] && max_children=4
    start_servers=$(( max_children / 4 )); [[ "$start_servers" -lt 2 ]] && start_servers=2
    min_spare=$(( max_children / 8 ));     [[ "$min_spare" -lt 1 ]] && min_spare=1
    max_spare=$(( max_children / 2 ));     [[ "$max_spare" -lt "$start_servers" ]] && max_spare=$start_servers

    sed -i -E "s/^[; ]*pm[ ]*=.*/pm = dynamic/" "$fpm_conf"
    sed -i -E "s/^[; ]*pm\.max_children[ ]*=.*/pm.max_children = $max_children/" "$fpm_conf"
    sed -i -E "s/^[; ]*pm\.start_servers[ ]*=.*/pm.start_servers = $start_servers/" "$fpm_conf"
    sed -i -E "s/^[; ]*pm\.min_spare_servers[ ]*=.*/pm.min_spare_servers = $min_spare/" "$fpm_conf"
    sed -i -E "s/^[; ]*pm\.max_spare_servers[ ]*=.*/pm.max_spare_servers = $max_spare/" "$fpm_conf"
    sed -i -E "s/^[; ]*pm\.max_requests[ ]*=.*/pm.max_requests = 500/" "$fpm_conf"

    if [[ -f "$php_ini" ]]; then
        sed -i -E "s/^[; ]*memory_limit.*/memory_limit = 256M/" "$php_ini"
        sed -i -E "s/^[; ]*max_execution_time.*/max_execution_time = 300/" "$php_ini"
        sed -i -E "s/^[; ]*upload_max_filesize.*/upload_max_filesize = 128M/" "$php_ini"
        sed -i -E "s/^[; ]*post_max_size.*/post_max_size = 128M/" "$php_ini"
    else
        log_warn "Không tìm thấy $php_ini - bỏ qua phần memory/upload limits."
    fi

    if ! php_fpm_restart_safe "$php_ver"; then
        cp -p "$bak" "$fpm_conf"
        [[ -n "$ini_bak" ]] && cp -p "$ini_bak" "$php_ini"
        systemctl restart "$(php_fpm_service "$php_ver")" 2>/dev/null
        log_error "PHP-FPM không nhận cấu hình mới - đã khôi phục cấu hình cũ."
        [[ -z "$auto_mode" ]] && pause
        return 1
    fi

    log_info "PHP-FPM đã áp dụng: max_children=$max_children, start=$start_servers, spare=$min_spare-$max_spare"
    [[ -z "$auto_mode" ]] && pause
    return 0
}

# 3. OPcache Optimization
optimize_opcache() {
    local auto_mode=${1:-}
    log_info "Optimizing OPcache..."

    # Dọn cấu hình PHP Preload do phiên bản cũ để lại (tính năng đã gỡ bỏ)
    _remove_legacy_php_preload

    local php_ver
    php_ver=$(get_installed_php_version)
    if [[ -z "$php_ver" ]]; then
        log_error "Không tìm thấy PHP-FPM để cấu hình OPcache!"
        [[ -z "$auto_mode" ]] && pause
        return 1
    fi
    log_info "OPcache target: PHP $php_ver"

    local conf_dir
    conf_dir=$(php_conf_d_dir "$php_ver")
    if [[ ! -d "$conf_dir" ]]; then
        log_error "Không tìm thấy thư mục ini của PHP-FPM: $conf_dir - chưa thay đổi gì."
        [[ -z "$auto_mode" ]] && pause
        return 1
    fi
    # File riêng, nạp sau cùng. KHÔNG ghi đè 10-opcache.ini của distro (file đó mới là nơi nạp extension).
    local opcache_ini="$conf_dir/99-vps-manager-opcache.ini"
    local had_old=0
    [[ -f "$opcache_ini" ]] && { cp -p "$opcache_ini" "${opcache_ini}.bak"; had_old=1; }

    local ram_mb mem=128
    ram_mb=$(free -m | awk '/^Mem:/{print $2}')
    [[ "${ram_mb:-0}" -ge 3500 ]] && mem=256

    # JIT: chỉ bật cho PHP 8.0-8.2. Từ 8.3 tắt để tránh lỗi "Allowed memory size exhausted" đã gặp.
    local major minor jit_setting="off" jit_buffer="0"
    major=${php_ver%%.*}; minor=${php_ver#*.}
    if [[ "$major" -eq 8 && "$minor" -le 2 ]]; then
        jit_setting="1255"; jit_buffer="64M"
    fi

    cat > "$opcache_ini" <<EOF
; OPcache Optimization for WordPress (vps-manager)
opcache.enable=1
opcache.enable_cli=0
opcache.memory_consumption=${mem}
opcache.interned_strings_buffer=16
opcache.max_accelerated_files=20000
opcache.max_wasted_percentage=5
; Kiểm tra file thay đổi mỗi 60 giây (trước là 2 giây): giảm I/O đĩa trên mỗi request.
; Code mới (cập nhật plugin/theme) có hiệu lực chậm nhất sau 60 giây, không cần restart PHP.
opcache.validate_timestamps=1
opcache.revalidate_freq=60
opcache.save_comments=1
opcache.jit=${jit_setting}
opcache.jit_buffer_size=${jit_buffer}
EOF

    if ! php_fpm_restart_safe "$php_ver"; then
        if [[ "$had_old" -eq 1 ]]; then mv -f "${opcache_ini}.bak" "$opcache_ini"; else rm -f "$opcache_ini"; fi
        systemctl restart "$(php_fpm_service "$php_ver")" 2>/dev/null
        log_error "PHP-FPM không nhận cấu hình OPcache mới - đã hoàn tác."
        [[ -z "$auto_mode" ]] && pause
        return 1
    fi
    rm -f "${opcache_ini}.bak"

    log_info "OPcache đã áp dụng (${mem}MB, JIT: ${jit_setting}) -> $opcache_ini"
    [[ -z "$auto_mode" ]] && pause
    return 0
}

# 4. MySQL/MariaDB Tuning - áp lại theo RAM, cùng công thức với trình cài đặt
# (core/kernel_tuning.sh: calc_mariadb_tuning_params). Ghi vào file drop-in riêng, có rollback.
tune_mysql() {
    local auto_mode=${1:-}
    log_info "Tuning MySQL/MariaDB for WordPress..."

    local conf_dir
    if ! conf_dir=$(mariadb_conf_dir); then
        log_error "Không tìm thấy thư mục cấu hình MariaDB/MySQL - chưa thay đổi gì."
        [[ -z "$auto_mode" ]] && pause
        return 1
    fi

    if ! declare -F calc_mariadb_tuning_params >/dev/null; then
        # shellcheck disable=SC1091
        source "$(dirname "${BASH_SOURCE[0]}")/../core/kernel_tuning.sh" 2>/dev/null
    fi
    if ! declare -F calc_mariadb_tuning_params >/dev/null; then
        log_error "Không nạp được core/kernel_tuning.sh - chưa thay đổi gì."
        [[ -z "$auto_mode" ]] && pause
        return 1
    fi
    calc_mariadb_tuning_params

    local dropin="${conf_dir}/99-vps-manager-perf.cnf"
    local svc had_old=0
    svc=$(mariadb_service_name)
    [[ -f "$dropin" ]] && { cp -p "$dropin" "${dropin}.bak"; had_old=1; }

    # Gỡ khối "# WordPress Optimizations" do phiên bản cũ của menu này nối vào file cấu hình chính
    # (InnoDB 50% RAM + query cache vô điều kiện). Chỉ xoá đúng khối đó, có backup để hoàn tác.
    local legacy legacy_bak=""
    for legacy in /etc/mysql/mariadb.conf.d/50-server.cnf /etc/mysql/my.cnf /etc/my.cnf; do
        if [[ -f "$legacy" ]] && grep -q "^# WordPress Optimizations$" "$legacy"; then
            legacy_bak="${legacy}.bak_vpsmanager"
            cp -p "$legacy" "$legacy_bak"
            sed -i '/^# WordPress Optimizations$/,/^max_heap_table_size = 64M$/d' "$legacy"
            log_info "Đã gỡ khối tuning cũ khỏi $legacy"
            break
        fi
    done

    {
        echo "# vps-manager: MySQL/MariaDB tuning theo RAM (ghi bởi menu Performance)"
        echo "[mysqld]"
        echo "innodb_buffer_pool_size = ${DB_INNODB_BUFFER}"
        echo "innodb_flush_log_at_trx_commit = 2"
        echo "innodb_flush_method = O_DIRECT"
        echo "innodb_file_per_table = 1"
        echo "max_connections = ${DB_MAX_CONNECTIONS}"
        echo "thread_cache_size = 50"
        echo "table_open_cache = 2000"
        echo "tmp_table_size = ${DB_TABLE_SIZE}"
        echo "max_heap_table_size = ${DB_TABLE_SIZE}"
        # query_cache_* chỉ tồn tại ở MariaDB (MySQL 8 sẽ không khởi động được nếu có các dòng này)
        if is_mariadb; then
            echo "query_cache_type = ${DB_QUERY_CACHE_TYPE:-0}"
            echo "query_cache_size = ${DB_QUERY_CACHE_SIZE:-0}"
        fi
    } > "$dropin"

    if ! systemctl restart "$svc" || ! systemctl is-active --quiet "$svc"; then
        if [[ "$had_old" -eq 1 ]]; then mv -f "${dropin}.bak" "$dropin"; else rm -f "$dropin"; fi
        [[ -n "$legacy_bak" ]] && cp -p "$legacy_bak" "${legacy_bak%.bak_vpsmanager}"
        systemctl restart "$svc" 2>/dev/null
        if systemctl is-active --quiet "$svc"; then
            log_error "$svc không khởi động được với cấu hình mới - đã khôi phục cấu hình cũ, DB đang chạy lại."
        else
            log_error "$svc KHÔNG khởi động được kể cả sau khi khôi phục. Kiểm tra ngay: journalctl -u $svc -n 50"
        fi
        [[ -z "$auto_mode" ]] && pause
        return 1
    fi
    rm -f "${dropin}.bak"

    # Báo giá trị THỰC TẾ đang có hiệu lực (my.cnf chính có thể ghi đè file drop-in)
    local effective=""
    effective=$(mysql -Nse "SELECT ROUND(@@innodb_buffer_pool_size/1024/1024)" 2>/dev/null)
    if [[ -n "$effective" ]]; then
        log_info "MySQL/MariaDB đã restart. InnoDB buffer đang có hiệu lực: ${effective}MB (mục tiêu ${DB_INNODB_BUFFER})."
        if [[ "${effective}M" != "${DB_INNODB_BUFFER}" ]]; then
            log_warn "Giá trị hiệu lực khác mục tiêu: có khối cấu hình khác (vd 'vps-manager-db-tuning' trong my.cnf) đang ghi đè $dropin."
        fi
    else
        log_info "MySQL/MariaDB đã restart với $dropin (không đọc được giá trị hiệu lực để xác nhận)."
    fi
    [[ -z "$auto_mode" ]] && pause
    return 0
}

# 5. Nginx FastCGI Cache zone
# Chỉ có MỘT nơi định nghĩa cache zone: site.sh (_site_setup_fastcgi_cache_global). Menu này gọi lại
# hàm đó (tạo mới nếu thiếu, nâng cấp cấu hình cũ), rồi test + reload nginx.
setup_fastcgi_microcache() {
    local auto_mode=${1:-}
    log_info "Thiết lập Nginx FastCGI Cache zone..."

    local cache_conf="/etc/nginx/conf.d/fastcgi_cache.conf"
    local bak=""
    [[ -f "$cache_conf" ]] && bak=$(backup_nginx_config "$cache_conf")

    if ! declare -F _site_setup_fastcgi_cache_global >/dev/null; then
        # shellcheck disable=SC1091
        source "$(dirname "${BASH_SOURCE[0]}")/site.sh" 2>/dev/null
    fi
    if ! declare -F _site_setup_fastcgi_cache_global >/dev/null; then
        log_error "Không nạp được modules/site.sh - chưa thay đổi gì."
        [[ -n "$bak" ]] && rm -f "$bak"
        [[ -z "$auto_mode" ]] && pause
        return 1
    fi
    _site_setup_fastcgi_cache_global

    if ! nginx_test_reload; then
        if [[ -n "$bak" ]]; then mv -f "$bak" "$cache_conf"; else rm -f "$cache_conf"; fi
        log_error "Nginx không nhận cấu hình cache - đã hoàn tác $cache_conf."
        [[ -z "$auto_mode" ]] && pause
        return 1
    fi
    [[ -n "$bak" ]] && rm -f "$bak"

    log_info "FastCGI cache zone sẵn sàng (response có Set-Cookie sẽ không bị cache)."
    echo -e "${YELLOW}Mỗi site WordPress tạo từ menu Website đã tự dùng zone này trong vhost.${NC}"
    [[ -z "$auto_mode" ]] && pause
    return 0
}

# 11. Database Cleanup
cleanup_wordpress_db() {
    clear
    echo -e "${BLUE}=================================================${NC}"
    echo -e "${GREEN}     🧹 Database Cleanup & Optimization${NC}"
    echo -e "${BLUE}=================================================${NC}"
    _wp_run_scoped _do_db_cleanup
    pause
}

_do_db_cleanup() {
    local domain=$1
    local WEB_ROOT WP_CMD
    _wp_prepare_cli "$domain" || return

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


# 12. Disable WordPress Bloat
disable_wordpress_bloat() {
    clear
    echo -e "${BLUE}=================================================${NC}"
    echo -e "${GREEN}     🎯 Disable WordPress Bloat${NC}"
    echo -e "${BLUE}=================================================${NC}"
    echo -e "Sẽ đặt trong wp-config.php: giới hạn Post Revisions, giãn Autosave, tự dọn Trash."
    echo ""
    _wp_run_scoped _do_disable_bloat
    pause
}

_do_disable_bloat() {
    local domain=$1
    local WEB_ROOT WP_CMD
    _wp_prepare_cli "$domain" || return

    log_info "Disable Bloat: $domain"
    local ok=0
    $WP_CMD config set WP_POST_REVISIONS 3 --raw --type=constant 2>/dev/null && { echo "  ✓ Revisions limit = 3"; ok=$((ok+1)); }
    $WP_CMD config set AUTOSAVE_INTERVAL 300 --raw --type=constant 2>/dev/null && { echo "  ✓ Autosave = 5 phút"; ok=$((ok+1)); }
    $WP_CMD config set EMPTY_TRASH_DAYS 7 --raw --type=constant 2>/dev/null && { echo "  ✓ Trash = 7 ngày"; ok=$((ok+1)); }
    $WP_CMD config set WP_CRON_LOCK_TIMEOUT 60 --raw --type=constant 2>/dev/null && { echo "  ✓ Cron timeout"; ok=$((ok+1)); }
    if [[ "$ok" -eq 4 ]]; then
        log_info "✅ $domain: Bloat disabled"
    else
        log_warn "$domain: chỉ ghi được $ok/4 thiết lập (kiểm tra quyền ghi wp-config.php)."
    fi
    echo -e "${YELLOW}Gợi ý: Dùng plugin (Perfmatters / Asset CleanUp) để tắt Heartbeat, Embeds per-page${NC}"
}


# 13. Image Optimization Setup
setup_image_optimization() {
    clear
    echo -e "${BLUE}=================================================${NC}"
    echo -e "${GREEN}     🖼️  Image Optimization Setup${NC}"
    echo -e "${BLUE}=================================================${NC}"
    echo -e "Script sẽ đảm bảo cài đặt thư viện WebP trên server và"
    echo -e "tự động cài plugin Imagify vào website WordPress của bạn."
    echo ""
    _wp_run_scoped _do_image_optimization _install_webp_server
    pause
}

_install_webp_server() {
    local php_ver gd_pkg webp_pkg
    php_ver=$(get_installed_php_version)
    if [[ "$OS_FAMILY" == "rhel" ]]; then
        gd_pkg="php-gd"; webp_pkg="libwebp-tools"
    else
        gd_pkg="php${php_ver}-gd"; webp_pkg="webp"
    fi

    if command -v cwebp >/dev/null 2>&1 && is_installed "$gd_pkg"; then
        log_info "Server đã hỗ trợ WebP."
        return 0
    fi

    log_info "Đang cài đặt Server-side WebP support..."
    pkg_install "$gd_pkg" "$webp_pkg" >/dev/null 2>&1
    if ! is_installed "$gd_pkg"; then
        log_warn "Chưa cài được $gd_pkg - WordPress có thể không tạo được ảnh WebP."
        return 1
    fi
    php_fpm_restart_safe "$php_ver" || return 1
    log_info "WebP support installed."
}

_do_image_optimization() {
    local domain=$1
    local WEB_ROOT WP_CMD
    _wp_prepare_cli "$domain" || return

    log_info "Cài đặt Plugin tối ưu ảnh: $domain"

    if $WP_CMD plugin is-installed imagify 2>/dev/null; then
        echo "  ✓ Imagify plugin đã có sẵn."
        $WP_CMD plugin activate imagify 2>/dev/null
    elif $WP_CMD plugin is-installed shortpixel-image-optimiser 2>/dev/null; then
        echo "  ✓ ShortPixel plugin đã có sẵn."
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

# 6. HTTP/2 & Brotli
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
    local created_files=()
    # Đã có brotli.conf và nginx đang chạy tốt với nó -> module hoạt động.
    # (Không test bằng file tạm trong trường hợp này: "brotli on;" lặp 2 lần sẽ báo lỗi giả
    #  và khiến brotli.conf đang chạy tốt bị xoá nhầm.)
    if [[ -f /etc/nginx/conf.d/brotli.conf ]] && nginx -t &>/dev/null; then
        brotli_ok=1
        log_info "Brotli module: ✅ Đang hoạt động (brotli.conf đã có)"
    elif nginx -V 2>&1 | grep -qi "brotli"; then
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
        created_files+=(/etc/nginx/conf.d/gzip.conf)
        log_info "Gzip config tạo tại /etc/nginx/conf.d/gzip.conf"
    else
        log_info "Gzip đã được cấu hình"
    fi

    # ── Brotli config (chỉ khi module có mặt, và chưa có file) ─────────────
    if [[ "$brotli_ok" -eq 1 ]] && [[ ! -f /etc/nginx/conf.d/brotli.conf ]]; then
        created_files+=(/etc/nginx/conf.d/brotli.conf)
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
    if nginx_test_reload; then
        log_info "✅ Compression đã áp dụng thành công"
        echo -e "${YELLOW}Note: HTTP/2 cần SSL certificate (HTTPS)${NC}"
        if [[ "$brotli_ok" -eq 1 ]]; then
            echo -e "${GREEN}  → Brotli + Gzip: cả hai đang hoạt động${NC}"
        else
            echo -e "${YELLOW}  → Chỉ Gzip: Brotli cần module riêng${NC}"
        fi
    else
        # Hoàn tác: gỡ các file vừa tạo trong lần chạy này để các lần reload sau không bị kẹt
        local cf
        for cf in "${created_files[@]}"; do
            rm -f "$cf"
            log_warn "Đã gỡ $cf (vừa tạo, gây lỗi cấu hình)."
        done
        if nginx -t &>/dev/null; then
            log_error "Compression chưa được áp dụng; cấu hình Nginx đã trở lại trạng thái hợp lệ."
        else
            log_error "Nginx config vẫn lỗi vì nguyên nhân có từ trước. Kiểm tra: nginx -t"
        fi
    fi
    pause
}


# 17. Benchmark Test
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

# ==============================================================================
# PHP Preload: tính năng đã gỡ bỏ (lợi ích nhỏ với WordPress, mỗi phiên bản PHP chỉ preload được
# một site, và code preload cũ gây lỗi fatal sau khi WordPress tự cập nhật core).
# Hàm dưới đây dọn cấu hình preload do các phiên bản trước để lại; được gọi từ optimize_opcache.
# ==============================================================================
_remove_legacy_php_preload() {
    local ini php_ini ver changed
    for php_ini in /etc/php/*/fpm/php.ini /etc/php.ini; do
        [[ -f "$php_ini" ]] || continue
        changed=0
        ver=$(echo "$php_ini" | grep -oE '[0-9]+\.[0-9]+' | head -1)
        ini="$(php_conf_d_dir "$ver")/99-vps-manager-preload.ini"
        if [[ -f "$ini" ]]; then rm -f "$ini"; changed=1; fi
        if grep -qE '^opcache\.preload(_user)?=' "$php_ini"; then
            sed -i -E 's|^(opcache\.preload(_user)?=)|;\1|' "$php_ini"; changed=1
        fi
        if [[ "$changed" -eq 1 ]]; then
            php_fpm_restart_safe "$ver" && log_info "Đã gỡ cấu hình PHP Preload cũ (PHP ${ver:-mặc định})."
        fi
    done
    return 0
}

# ==============================================================================
# 10. RAM Disk cho FastCGI Cache (tmpfs)
# ==============================================================================

# Đặt max_size của cache zone (MB) trong fastcgi_cache.conf - phải nhỏ hơn dung lượng tmpfs,
# nếu không nginx sẽ ghi đầy tmpfs (ENOSPC) trước khi kịp dọn cache.
_tmpfs_set_cache_max_size() {
    local size=$1
    local cache_conf="/etc/nginx/conf.d/fastcgi_cache.conf"
    [[ -f "$cache_conf" ]] || return 0
    sed -i -E "/^[[:space:]]*fastcgi_cache_path/ s/max_size=[0-9]+[kKmMgG]?/max_size=${size}/" "$cache_conf"
}

# Ghi lại /etc/fstab: bỏ dòng tmpfs cũ của cache, thêm dòng mới nếu có. Dùng file tạm, giữ backup.
_tmpfs_update_fstab() {
    local new_line=${1:-}
    local tmp
    tmp=$(mktemp) || return 1
    cp -p /etc/fstab /etc/fstab.vpsmanager.bak
    grep -v '/var/cache/nginx/fastcgi' /etc/fstab > "$tmp"
    [[ -n "$new_line" ]] && echo "$new_line" >> "$tmp"
    if [[ ! -s "$tmp" ]]; then
        rm -f "$tmp"
        return 1
    fi
    cat "$tmp" > /etc/fstab
    rm -f "$tmp"
}

setup_tmpfs_fastcgi_cache() {
    clear
    echo -e "${BLUE}=================================================${NC}"
    echo -e "${GREEN}   🧠 Cấu hình RAM Disk cho FastCGI Cache (tmpfs)${NC}"
    echo -e "${BLUE}=================================================${NC}"
    echo -e "Công nghệ này đưa toàn bộ thư mục /var/cache/nginx/fastcgi lên RAM (tmpfs):"
    echo -e "  • Lợi ích: Đọc cache không phụ thuộc ổ cứng."
    echo -e "  • Đánh đổi: Cache mất khi reboot và chiếm RAM thật của máy."
    echo -e "  • Tự động ghi vào /etc/fstab (có nofail) để duy trì sau khi khởi động lại."
    echo -e "${BLUE}=================================================${NC}"

    local cache_dir="/var/cache/nginx/fastcgi"
    local is_mounted=0
    if mountpoint -q "$cache_dir" 2>/dev/null && [[ "$(findmnt -n -o FSTYPE "$cache_dir" 2>/dev/null)" == "tmpfs" ]]; then
        is_mounted=1
        echo -e "Trạng thái hiện tại: ${GREEN}● ĐÃ BẬT RAM Disk (tmpfs)${NC}"
        df -h "$cache_dir" 2>/dev/null | tail -n 1 | awk '{print "  Dung lượng đã dùng: " $3 " / " $2 " (" $5 ")"}'
    else
        echo -e "Trạng thái hiện tại: ${YELLOW}○ ĐANG DÙNG Ổ CỨNG VẬT LÝ (SSD/NVMe)${NC}"
    fi

    echo ""
    echo -e "1. Bật / đổi dung lượng RAM Disk FastCGI Cache (Khuyến nghị 256MB - 512MB)"
    echo -e "2. Tắt RAM Disk (Chuyển lại về lưu trên ổ SSD)"
    echo -e "0. Quay lại"
    read -p "Chọn [0-2]: " t_choice

    local cache_user cache_uid cache_gid
    cache_user=$(nginx_worker_user)
    cache_uid=$(id -u "$cache_user" 2>/dev/null)
    cache_gid=$(id -g "$cache_user" 2>/dev/null)

    case $t_choice in
        1)
            if [[ -z "$cache_uid" || -z "$cache_gid" ]]; then
                log_error "Không xác định được user của nginx worker ($cache_user)."
                pause; return
            fi

            local ram_mb def_size=256 user_size
            ram_mb=$(free -m | awk '/^Mem:/{print $2}')
            [[ "$ram_mb" -ge 4000 ]] && def_size=512
            [[ "$ram_mb" -ge 8000 ]] && def_size=1024

            read -p "Nhập dung lượng RAM cấp cho Cache (MB, chỉ nhập số) [Mặc định $def_size]: " user_size
            [[ -z "$user_size" ]] && user_size=$def_size
            if ! valid_uint "$user_size"; then
                log_error "Dung lượng không hợp lệ: '$user_size' (chỉ nhập số nguyên dương, đơn vị MB)."
                pause; return
            fi
            if [[ "$user_size" -lt 32 ]] || [[ "$user_size" -gt $(( ram_mb / 2 )) ]]; then
                log_error "Dung lượng phải từ 32MB đến $(( ram_mb / 2 ))MB (tối đa 1/2 RAM của máy)."
                pause; return
            fi

            mkdir -p "$cache_dir"
            local opts="size=${user_size}M,noatime,mode=0700,uid=${cache_uid},gid=${cache_gid}"
            log_info "Đang mount tmpfs ${user_size}M vào $cache_dir..."
            if [[ "$is_mounted" -eq 1 ]]; then
                mount -o "remount,${opts}" "$cache_dir"
            else
                # Cache cũ trên đĩa bị che khuất sau khi mount -> xoá trước cho gọn
                find "$cache_dir" -mindepth 1 -delete 2>/dev/null
                mount -t tmpfs -o "$opts" tmpfs "$cache_dir"
            fi
            if [[ $? -ne 0 ]] || ! mountpoint -q "$cache_dir"; then
                log_error "Mount tmpfs THẤT BẠI - không ghi gì vào /etc/fstab."
                pause; return
            fi

            # nofail: nếu dòng này lỗi khi boot, máy vẫn khởi động bình thường (không rơi vào emergency mode)
            if ! _tmpfs_update_fstab "tmpfs $cache_dir tmpfs defaults,nofail,${opts} 0 0"; then
                log_error "Không cập nhật được /etc/fstab (RAM Disk đang chạy nhưng sẽ mất sau reboot)."
            fi

            # max_size của cache zone = 80% tmpfs
            local cache_conf="/etc/nginx/conf.d/fastcgi_cache.conf" bak=""
            [[ -f "$cache_conf" ]] && bak=$(backup_nginx_config "$cache_conf")
            _tmpfs_set_cache_max_size "$(( user_size * 80 / 100 ))m"
            if nginx_test_reload; then
                [[ -n "$bak" ]] && rm -f "$bak"
                log_info "✅ Đã kích hoạt RAM Disk FastCGI Cache (${user_size}MB, cache tối đa $(( user_size * 80 / 100 ))MB)."
            else
                [[ -n "$bak" ]] && mv -f "$bak" "$cache_conf"
                log_error "RAM Disk đã mount nhưng Nginx chưa reload được - xem lỗi ở trên."
            fi
            pause
            ;;
        2)
            if [[ "$is_mounted" -eq 0 ]]; then
                echo -e "${YELLOW}RAM Disk chưa được bật.${NC}"
                # Vẫn dọn dòng fstab cũ nếu còn sót
                grep -q '/var/cache/nginx/fastcgi' /etc/fstab && _tmpfs_update_fstab ""
                pause; return
            fi
            log_info "Đang gỡ bỏ RAM Disk..."
            if ! umount "$cache_dir" 2>/dev/null && ! umount -l "$cache_dir" 2>/dev/null; then
                log_error "Không umount được $cache_dir - chưa thay đổi /etc/fstab."
                pause; return
            fi
            _tmpfs_update_fstab "" || log_warn "Không cập nhật được /etc/fstab - hãy xoá dòng tmpfs của $cache_dir thủ công."
            mkdir -p "$cache_dir"
            chown "$cache_user" "$cache_dir" 2>/dev/null
            chmod 700 "$cache_dir"
            _tmpfs_set_cache_max_size "1g"
            if nginx_test_reload; then
                log_info "Đã hoàn nguyên về lưu trữ trên ổ đĩa SSD."
            else
                log_error "Đã gỡ RAM Disk nhưng Nginx chưa reload được - xem lỗi ở trên."
            fi
            pause
            ;;
        *) return ;;
    esac
}

setup_instant_page_optimizer() {
    clear
    echo -e "${BLUE}=================================================${NC}"
    echo -e "${GREEN} ⚡ Tối ưu Trải nghiệm: Instant.page & Tắt Cart Fragments${NC}"
    echo -e "${BLUE}=================================================${NC}"
    echo -e "Công cụ này sẽ triển khai một MU-Plugin (Must-Use Plugin) nhẹ vào WordPress:"
    echo -e "  1. ${CYAN}Instant.page (Speculative Preload)${NC}:"
    echo -e "     Khi người dùng rê chuột lên liên kết (>65ms), trình duyệt tự prefetch trước"
    echo -e "     nội dung ngầm. Khi click, trang hiển thị ${GREEN}NGAY LẬP TỨC (0ms cảm nhận)${NC}!"
    echo -e "  2. ${CYAN}Chặn WooCommerce Cart Fragments trên trang tĩnh${NC}:"
    echo -e "     Triệt tiêu request AJAX chậm chạp /?wc-ajax=get_refreshed_fragments trên"
    echo -e "     Trang chủ, Bài viết... Giúp giảm 0.5s – 1s thời gian chờ!"
    echo -e "  3. ${CYAN}DNS Prefetch & Preconnect${NC} sẵn cho Google Fonts / CDN."
    echo -e "${BLUE}=================================================${NC}"

    source "$(dirname "${BASH_SOURCE[0]}")/site.sh"
    select_site || return
    local domain=$SELECTED_DOMAIN
    local site_root="/var/www/$domain/public_html"
    local mu_dir="$site_root/wp-content/mu-plugins"
    local booster_file="$mu_dir/vps-speed-booster.php"

    if [[ ! -d "$site_root/wp-content" ]]; then
        echo -e "${RED}Không tìm thấy thư mục WordPress wp-content!${NC}"
        pause; return
    fi

    echo ""
    echo -e "1. Kích hoạt Siêu tốc (Instant.page + Tắt Cart Fragments + DNS Prefetch)"
    echo -e "2. Gỡ bỏ tính năng này"
    echo -e "0. Quay lại"
    read -p "Chọn [0-2]: " b_choice

    case $b_choice in
        1)
            mkdir -p "$mu_dir"
            cat > "$booster_file" << 'PHPBOOSTER'
<?php
/**
 * Plugin Name: VPS Speed Booster (Instant.page & WC Performance)
 * Description: Tăng tốc độ chuyển trang 0ms và loại bỏ request chặn hiển thị của WooCommerce.
 * Author: VPS Manager
 * Version: 1.0.0
 */

// 1. Tải trước trang khi rê chuột (Instant.page - Speculative Preloading)
add_action('wp_footer', function() {
    if (is_admin()) return;
    ?>
    <script type="module">
    /*! instant.page v5.2.0 - (C) 2019-2023 Alexandre Dieulot - https://instant.page/license */
    let t,e;const n=new Set,o=document.createElement("link"),s=o.relList&&o.relList.supports&&o.relList.supports("prefetch"),c="instantPageExternalAllowed"in document.body.dataset,d="instantAllowQueryString"in document.body.dataset,u="instantAllowExternalLinks"in document.body.dataset,l="instantWhitelist"in document.body.dataset,a="instantVaryAccept"in document.body.dataset,f=1111;let r=65,m=!1,v=!1,p=!1;if("instantIntensity"in document.body.dataset){const t=document.body.dataset.instantIntensity;if("mousedown"==t)m=!0,"mousedown-only"==t&&(v=!0);else if("viewport"==t){const e=navigator.connection;(!e||!e.saveData)&&(p=!0)}else{const e=parseInt(t);isNaN(e)||(r=e)}}if(s){const o={capture:!0,passive:!0};v||document.addEventListener("touchstart",(function(t){w(t)}),o),document.addEventListener("mouseover",(function(e){y(e)}),o),m||document.addEventListener("mousedown",(function(t){A(t)}),o),p&&("requestIdleCallback"in window?requestIdleCallback((function(){b()})):b())}function b(){const t=new IntersectionObserver((e=>{e.forEach((e=>{if(e.isIntersecting){const n=e.target;t.unobserve(n),h(n.href)}}))}));document.querySelectorAll("a").forEach((e=>{E(e)&&t.observe(e)}))}function w(t){const e=t.target.closest("a");E(e)&&h(e.href,"high")}function y(n){if(n.relatedTarget&&n.target.closest("a")==n.relatedTarget.closest("a"))return;const o=n.target.closest("a");E(o)&&(o.addEventListener("mouseout",k,{passive:!0}),t=setTimeout((()=>{h(o.href,"high"),t=void 0}),r))}function A(t){const e=t.target.closest("a");E(e)&&h(e.href,"high")}function k(n){n.relatedTarget&&n.target.closest("a")==n.relatedTarget.closest("a")||t&&(clearTimeout(t),t=void 0)}function E(t){if(!t||!t.href)return!1;if(l&&!("instant"in t.dataset))return!1;if(!c&&t.origin!=location.origin&&!("instant"in t.dataset))return!1;if(["http:","https:"].indexOf(t.protocol)==-1)return!1;if("http:"==t.protocol&&"https:"==location.protocol)return!1;if(!d&&t.search&&!("instant"in t.dataset))return!1;if(t.hash&&t.pathname+t.search==location.pathname+location.search)return!1;if("noInstant"in t.dataset)return!1;return!0}function h(t,e="auto"){if(n.has(t))return;const o=document.createElement("link");o.rel="prefetch",o.href=t,o.as="document",o.fetchPriority=e,document.head.appendChild(o),n.add(t)}
    </script>
    <?php
}, 999);

// 2. Vô hiệu hóa WooCommerce Cart Fragments trên trang KHÔNG thuộc cửa hàng
//    (giữ nguyên ở Shop / danh mục / trang sản phẩm / Cart / Checkout / Tài khoản để mini-cart cập nhật đúng)
add_action('wp_enqueue_scripts', function() {
    if (!function_exists('is_woocommerce')) return;
    if (is_woocommerce() || is_cart() || is_checkout() || is_account_page()) return;
    wp_dequeue_script('wc-cart-fragments');
}, 100);

// 3. DNS Prefetch & Preconnect tự động
add_action('wp_head', function() {
    echo '<link rel="dns-prefetch" href="//fonts.googleapis.com">' . "\n";
    echo '<link rel="dns-prefetch" href="//fonts.gstatic.com">' . "\n";
    echo '<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>' . "\n";
}, 1);
PHPBOOSTER
            local booster_owner
            booster_owner=$(site_owner "$site_root")
            chown "$booster_owner:$booster_owner" "$mu_dir" "$booster_file" 2>/dev/null || true
            log_info "✅ Đã cài đặt VPS Speed Booster cho $domain!"
            pause
            ;;
        2)
            rm -f "$booster_file"
            log_info "Đã gỡ bỏ VPS Speed Booster cho $domain."
            pause
            ;;
        *) return ;;
    esac
}


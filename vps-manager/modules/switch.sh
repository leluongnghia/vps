#!/bin/bash

# modules/switch.sh - Web Server Switcher (Nginx <-> OLS)

switch_webserver_menu() {
    clear
    echo -e "${BLUE}=================================================${NC}"
    echo -e "${GREEN}     🔄 DI CHUYỂN MÁY CHỦ WEB (NGINX <=> OLS)${NC}"
    echo -e "${BLUE}=================================================${NC}"
    echo -e "Tính năng này giúp bạn chuyển đổi mượt mà giữa Nginx và OpenLiteSpeed"
    echo -e "mà không làm mất dữ liệu web, tự động map toàn bộ tên miền."
    echo -e ""
    
    local active_server="${RED}Không có webserver nào đang chạy!${NC}"
    if systemctl is-active --quiet nginx 2>/dev/null; then
        active_server="${YELLOW}Nginx (Truyền thống)${NC}"
    elif systemctl is-active --quiet lshttpd 2>/dev/null; then
        active_server="${CYAN}OpenLiteSpeed (Tốc độ)${NC}"
    fi
    echo -e "Web Server ĐANG CHẠY hiện tại: $active_server"
    echo -e ""
    
    echo -e "1. Chuyển TẤT CẢ website sang ${CYAN}OpenLiteSpeed${NC}"
    echo -e "2. Chuyển TẤT CẢ website sang ${YELLOW}Nginx${NC}"
    echo -e "0. Thoát"
    echo -e "${BLUE}=================================================${NC}"
    read -p "Chọn [0-2]: " choice
    
    case $choice in
        1) switch_to_ols ;;
        2) switch_to_nginx ;;
        0) return ;;
        *) echo -e "${RED}Lựa chọn không hợp lệ.${NC}"; pause; switch_webserver_menu ;;
    esac
}

switch_to_ols() {
    log_info "Bắt đầu chuyển đổi hạ tầng sang OpenLiteSpeed..."
    
    # Check OLS installation
    if [[ ! -d "/usr/local/lsws" ]]; then
        log_warn "OpenLiteSpeed chưa được cài đặt trên máy chủ!"
        read -p "Bạn có muốn CÀI ĐẶT OpenLiteSpeed ngay bây giờ không? [Y/n]: " auto_install
        if [[ "$auto_install" == "y" || "$auto_install" == "Y" || -z "$auto_install" ]]; then
            source "$(dirname "${BASH_SOURCE[0]}")/ols.sh"
            install_ols_stack
            
            if [[ ! -d "/usr/local/lsws" ]]; then
                log_error "Lỗi cài đặt OLS. Không thể tiếp tục chuyển đổi."
                pause; return
            fi
            # OLS cài xong sẽ dừng Nginx, tiếp tục luồng chuyển đổi bên dưới
        else
            echo -e "Vui lòng cài đặt OLS trước khi chuyển đổi."
            pause; return
        fi
    fi
    
    # 1. Switch Services
    if systemctl is-active --quiet nginx 2>/dev/null; then
        log_info "Đang tắt và đóng băng Nginx..."
        systemctl stop nginx 2>/dev/null
        systemctl disable nginx 2>/dev/null
    fi
    systemctl enable lshttpd 2>/dev/null
    
    # 2. Iterate websites
    local count=0
    for wp_config in /var/www/*/public_html/wp-config.php /var/www/*/public_html/index.php /var/www/*/public_html/index.html; do
        [[ ! -f "$wp_config" ]] && continue
        local domain=$(basename $(dirname $(dirname "$wp_config")))
        
        # Bỏ qua nếu đã tạo vhost hoặc trùng
        if grep -q "virtualhost ${domain}" "/usr/local/lsws/conf/httpd_config.conf" 2>/dev/null; then
            log_warn "[$domain] Đã có vhost bên OLS, bỏ qua..."
            continue
        fi
        
        log_info "Đang tạo hồ sơ Virtual Host cho: $domain..."
        
        local lsphp_bin="/usr/local/lsws/lsphp84/bin/lsphp"
        [[ ! -x "$lsphp_bin" ]] && lsphp_bin="/usr/local/lsws/lsphp83/bin/lsphp"
        [[ ! -x "$lsphp_bin" ]] && lsphp_bin="/usr/local/lsws/lsphp82/bin/lsphp"
        [[ ! -x "$lsphp_bin" ]] && lsphp_bin="/usr/local/lsws/lsphp81/bin/lsphp"
        
        mkdir -p "/usr/local/lsws/conf/vhosts/${domain}"
        cat > "/usr/local/lsws/conf/vhosts/${domain}/vhconf.conf" <<EOF
docRoot                   \$VH_ROOT/public_html
vhDomain                  ${domain}
vhAliases                 www.${domain}
enableGzip                1

index  {
  useServer               0
  indexFiles              index.php, index.html
}

scripthandler  {
  add                     lsapi:lsphp php
}

extprocessor lsphp {
  type                    lsapi
  address                 uds://tmp/lshttpd/${domain}-lsphp.sock
  maxConns                35
  extUser                 www-data
  extGroup                www-data
  env                     PHP_LSAPI_CHILDREN=35
  env                     LSAPI_AVOID_FORK=0
  env                     LSAPI_MAX_IDLE=30
  env                     LSAPI_MAX_IDLE_CHILDREN=1
  env                     LSAPI_MAX_PROCESS_TIME=120
  env                     LSAPI_PGRP_MAX_IDLE=30
  env                     LSAPI_ACCEPT_NOTIFY=1
  env                     LSAPI_MAX_CMD_SCRIPT_PATH_LEN=200
  initTimeout             60
  retryTimeout            0
  persistConn             1
  respBuffer              0
  autoStart               1
  path                    \${lsphp_bin}
  backlog                 100
  instances               1
}

rewrite  {
  enable                  1
  autoLoadHtaccess        1
  rules                   <<<END_rules
RewriteEngine on
RewriteBase /

# --- Static file pass-through: uploads & wp-content assets never go through WordPress ---
RewriteRule ^wp-content/uploads/ - [L]
RewriteRule ^wp-includes/ - [L]
RewriteRule ^wp-content/plugins/ - [L]
RewriteRule ^wp-content/themes/ - [L]

# WebP Fallback: only for image extensions (not generic catch-all)
# Serve .webp if browser supports it AND a .webp version exists beside the original
RewriteCond %{HTTP_ACCEPT} image/webp
RewriteCond %{DOCUMENT_ROOT}%{REQUEST_FILENAME} -f
RewriteCond %{DOCUMENT_ROOT}%{REQUEST_FILENAME}\.webp !-f
RewriteRule ^(.*)\.(?:jpe?g|png|gif)$ - [L]

RewriteCond %{HTTP_ACCEPT} image/webp
RewriteCond %{DOCUMENT_ROOT}%{REQUEST_FILENAME}\.webp -f
RewriteRule ^(.*)\.(?:jpe?g|png|gif)$ $1.webp [T=image/webp,E=accept:1,L]

# WordPress: only route to index.php if file/dir does not exist
RewriteRule ^index\.php$ - [L]
RewriteCond %{REQUEST_FILENAME} !-f
RewriteCond %{REQUEST_FILENAME} !-d
RewriteRule . /index.php [L]
  END_rules
}
EOF

        # Tạo/cập nhật .htaccess WordPress cho site (Nginx không cần nhưng OLS cần)
        local htaccess_file="/var/www/${domain}/public_html/.htaccess"
        if [[ ! -f "$htaccess_file" ]] || ! grep -q "WordPress" "$htaccess_file" 2>/dev/null; then
            log_info "Tạo file .htaccess WordPress cho ${domain}..."
            cat > "$htaccess_file" <<'HTEOF'
# BEGIN WordPress
# Các chỉ thị (dòng) giữa "BEGIN WordPress" và "END WordPress" được
# tự động tạo ra và chỉ nên được chỉnh sửa qua bộ lọc WordPress filters.
<IfModule mod_rewrite.c>
RewriteEngine On
RewriteBase /
RewriteRule ^index\.php$ - [L]
RewriteCond %{REQUEST_FILENAME} !-f
RewriteCond %{REQUEST_FILENAME} !-d
RewriteRule . /index.php [L]
</IfModule>
# END WordPress
HTEOF
            chown www-data:www-data "$htaccess_file" 2>/dev/null
            chmod 644 "$htaccess_file"
        fi
        
        # Add to httpd_config
        cat >> "/usr/local/lsws/conf/httpd_config.conf" <<EOF

virtualhost ${domain} {
  vhRoot                  /var/www/${domain}
  configFile              \$SERVER_ROOT/conf/vhosts/${domain}/vhconf.conf
  allowSymbolLink         1
  enableScript            1
  restrained              0
}
EOF
        sed -i "/listener HTTP {/a\\  map                     ${domain} ${domain}, www.${domain}" "/usr/local/lsws/conf/httpd_config.conf"
        sed -i "/listener HTTPS {/a\\  map                     ${domain} ${domain}, www.${domain}" "/usr/local/lsws/conf/httpd_config.conf"
        
        chown -R lsadm:lsadm "/usr/local/lsws/conf/vhosts/${domain}"
        
        # Ensure correct user for web folder (safe default)
        chown -R www-data:www-data "/var/www/$domain/public_html" 2>/dev/null
        
        # Setup LSCache locally
        if [[ -f "$wp_config" && "$wp_config" == *"wp-config"* ]]; then
            sudo -u www-data wp litespeed-option set cache-browser false --path="/var/www/$domain/public_html" --allow-root >/dev/null 2>&1
        fi
        
        count=$((count+1))
    done
    
    # Update global site conf
    if [[ -f ~/.vps-manager/sites_data.conf ]]; then
        sed -i 's/^webserver=.*/webserver=openlitespeed/' ~/.vps-manager/sites_data.conf
    fi
    
    systemctl start lshttpd 2>/dev/null
    systemctl reload lshttpd 2>/dev/null

    # Cập nhật stack config — menu sẽ hiển thị chế độ OLS
    mkdir -p "$HOME/.vps-manager"
    echo "ACTIVE_STACK=ols" > "$HOME/.vps-manager/stack.conf"

    echo -e "${GREEN}Đã di tản thành công $count website sang OpenLiteSpeed!${NC}"
    pause
}

switch_to_nginx() {
    echo -e "${BLUE}════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}   Chuyển đổi OLS → Nginx (toàn bộ website)${NC}"
    echo -e "${BLUE}════════════════════════════════════════════════════${NC}"
    echo -e "${YELLOW}Quá trình này sẽ:${NC}"
    echo -e "  1. Cài Nginx + PHP-FPM (nếu chưa có)"
    echo -e "  2. Dừng OLS, giải phóng port 80/443"
    echo -e "  3. Tạo Nginx vhost cho từng site"
    echo -e "  4. Cài Valkey Unix Socket (object cache L2)"
    echo -e "  5. Cập nhật wp-config.php kết nối cache mới"
    echo -e ""
    read -p "Tiếp tục? [Y/n]: " confirm
    [[ "${confirm,,}" == "n" ]] && return

    local SCRIPT_DIR
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

    # ── Bước 1: Đảm bảo Nginx đã cài ──────────────────────────────────────
    log_info "[1/5] Kiểm tra Nginx + PHP-FPM..."
    if ! command -v nginx &>/dev/null; then
        log_info "Nginx chưa có, đang cài..."
        source "${SCRIPT_DIR}/lemp.sh"
        install_nginx
    else
        log_info "✓ Nginx đã có."
    fi

    # Cài PHP-FPM nếu chưa có phiên bản nào
    local php_installed=""
    for v in 8.3 8.2 8.1 8.4; do
        [[ -f "/etc/php/${v}/fpm/php.ini" ]] && { php_installed="$v"; break; }
    done
    if [[ -z "$php_installed" ]]; then
        log_info "PHP-FPM chưa có, đang cài PHP 8.3..."
        source "${SCRIPT_DIR}/lemp.sh"
        install_php "8.3"
        php_installed="8.3"
    fi
    log_info "✓ PHP-FPM version: ${php_installed}"

    # ── Bước 2: Dừng OLS ───────────────────────────────────────────────────
    log_info "[2/5] Dừng OpenLiteSpeed..."
    systemctl stop  lshttpd 2>/dev/null || true
    systemctl disable lshttpd 2>/dev/null || true
    # Giải phóng port nếu OLS vẫn chiếm
    fuser -k 80/tcp  2>/dev/null || true
    fuser -k 443/tcp 2>/dev/null || true
    sleep 1
    log_info "✓ OLS đã dừng."

    # ── Bước 3: Tạo Nginx vhost cho từng site ──────────────────────────────
    log_info "[3/5] Migrate virtual hosts..."
    source "${SCRIPT_DIR}/site.sh" 2>/dev/null || true

    local count=0
    local sites_found=()

    # Quét tất cả site trong /var/www/
    for site_dir in /var/www/*/; do
        local domain
        domain=$(basename "$site_dir")
        local pub_html="${site_dir}public_html"

        # Bỏ qua thư mục không phải site thật
        [[ "$domain" == "html" || "$domain" == "default" ]] && continue
        [[ ! -d "$pub_html" ]] && continue

        sites_found+=("$domain")

        # Phát hiện PHP version từ các symlink LSPHP hoặc dùng default
        local site_php="$php_installed"
        # Thử đọc từ OLS vhconf nếu có
        local ols_vhconf="/usr/local/lsws/conf/vhosts/${domain}/vhconf.conf"
        if [[ -f "$ols_vhconf" ]]; then
            # Tìm lsphp83/lsphp82/... trong path
            local detected_ver
            detected_ver=$(grep -oP 'lsphp\K\d+' "$ols_vhconf" | head -1)
            if [[ -n "$detected_ver" ]]; then
                # "83" -> "8.3"
                site_php="${detected_ver:0:1}.${detected_ver:1}"
            fi
        fi
        # Fallback: dùng php version nào đã cài cao nhất
        for v in 8.4 8.3 8.2 8.1; do
            [[ -f "/etc/php/${v}/fpm/php.ini" ]] && { site_php="$v"; break; }
        done

        if [[ -f "/etc/nginx/sites-available/${domain}" ]]; then
            log_warn "  [${domain}] Nginx vhost đã tồn tại, enable lại..."
            [[ ! -L "/etc/nginx/sites-enabled/${domain}" ]] && \
                ln -sf "/etc/nginx/sites-available/${domain}" "/etc/nginx/sites-enabled/${domain}"
        else
            log_info "  Tạo Nginx vhost: ${domain} (PHP ${site_php})"
            if type create_nginx_config &>/dev/null; then
                create_nginx_config "$domain" "$site_php"
            else
                # Fallback vhost tối thiểu
                _make_minimal_nginx_vhost "$domain" "$site_php"
            fi
        fi

        # Fix quyền thư mục web
        chown -R www-data:www-data "$pub_html" 2>/dev/null || true

        count=$(( count + 1 ))
    done

    log_info "✓ Đã migrate ${count} site sang Nginx."

    # ── Bước 4: Cài Valkey Unix Socket ─────────────────────────────────────
    log_info "[4/5] Cài đặt Valkey Object Cache (Unix Socket)..."
    if ! command -v valkey-server &>/dev/null && ! command -v valkey-cli &>/dev/null; then
        source "${SCRIPT_DIR}/lemp.sh" 2>/dev/null || true
        if type _install_object_cache_nginx &>/dev/null; then
            _install_object_cache_nginx "valkey"
        else
            # Fallback cài trực tiếp
            apt-get install -y valkey &>/dev/null 2>&1 || \
                apt-get install -y redis-server &>/dev/null 2>&1 || true
        fi
    else
        log_info "✓ Valkey/Redis đã được cài sẵn."
    fi

    # Xác định socket path đang dùng
    local cache_socket=""
    [[ -S "/var/run/valkey/valkey.sock" ]] && cache_socket="/var/run/valkey/valkey.sock"
    [[ -S "/var/run/redis/redis.sock"   ]] && cache_socket="/var/run/redis/redis.sock"
    [[ -S "/tmp/valkey.sock"            ]] && cache_socket="/tmp/valkey.sock"
    [[ -S "/tmp/redis.sock"             ]] && cache_socket="/tmp/redis.sock"

    # ── Bước 5: Cập nhật wp-config.php ────────────────────────────────────
    log_info "[5/5] Cập nhật Object Cache trong wp-config.php..."
    local db_idx=0
    for domain in "${sites_found[@]}"; do
        local wpcfg="/var/www/${domain}/public_html/wp-config.php"
        [[ ! -f "$wpcfg" ]] && continue

        # Xoá config OLS/cache cũ
        sed -i "/WP_REDIS_SCHEME\|WP_REDIS_PATH\|WP_REDIS_HOST\|WP_REDIS_PORT\|WP_CACHE_KEY_SALT\|WP_REDIS_DATABASE/d" "$wpcfg"

        if [[ -n "$cache_socket" ]]; then
            sed -i "/table_prefix/i define( 'WP_REDIS_SCHEME',   'unix' );"            "$wpcfg"
            sed -i "/table_prefix/i define( 'WP_REDIS_PATH',     '${cache_socket}' );" "$wpcfg"
            sed -i "/table_prefix/i define( 'WP_REDIS_DATABASE', ${db_idx} );"         "$wpcfg"
            sed -i "/table_prefix/i define( 'WP_CACHE_KEY_SALT', '${domain}:' );"      "$wpcfg"
            log_info "  ✓ ${domain} → Unix Socket DB#${db_idx}"
            db_idx=$(( db_idx + 1 ))
        fi
    done

    # ── Bước 6: Dọn dẹp OLS (giải phóng disk) ────────────────────────────
    log_info "[+] Dọn dẹp OpenLiteSpeed để giải phóng disk..."
    local disk_before
    disk_before=$(df -BM / | awk 'NR==2{print $3}')

    # Gỡ gói openlitespeed và toàn bộ lsphp
    if [[ "$OS_FAMILY" == "debian" ]]; then
        DEBIAN_FRONTEND=noninteractive apt-get remove -y --purge \
            openlitespeed lsphp* 2>/dev/null || true
        apt-get autoremove -y 2>/dev/null || true

        # Xóa OLS apt repo để không update lại
        rm -f /etc/apt/sources.list.d/openlitespeed.list \
              /etc/apt/sources.list.d/lsphp.list \
              /etc/apt/trusted.gpg.d/lst_*.gpg 2>/dev/null || true
    else
        dnf remove -y openlitespeed lsphp* 2>/dev/null || true
        rm -f /etc/yum.repos.d/openlitespeed.repo \
              /etc/yum.repos.d/litespeed.repo 2>/dev/null || true
    fi

    # Xóa thư mục OLS còn sót
    local ols_dirs=(
        /usr/local/lsws          # binary, conf, vhosts, logs
        /tmp/lshttpd             # socket files
        /etc/systemd/system/lshttpd.service.d
    )
    for d in "${ols_dirs[@]}"; do
        if [[ -e "$d" ]]; then
            rm -rf "$d" 2>/dev/null && log_info "  ✓ Đã xóa: $d"
        fi
    done

    # Reload systemd sau khi xóa service
    systemctl daemon-reload 2>/dev/null || true

    # Xóa log OLS còn nằm trong /var/log
    rm -rf /var/log/lsws 2>/dev/null || true

    local disk_after
    disk_after=$(df -BM / | awk 'NR==2{print $3}')
    local freed=$(( ${disk_before%M} - ${disk_after%M} ))
    log_info "✓ Dọn dẹp xong. Giải phóng ~${freed}MB disk."

    # ── Khởi động Nginx ────────────────────────────────────────────────────
    systemctl enable nginx
    if nginx -t 2>/dev/null; then
        systemctl restart nginx
        log_info "✓ Nginx đang chạy."
    else
        log_error "Nginx config lỗi! Chạy 'nginx -t' để xem chi tiết."
    fi

    # Cập nhật stack marker
    mkdir -p "$HOME/.vps-manager"
    echo "ACTIVE_STACK=nginx" > "$HOME/.vps-manager/stack.conf"
    if [[ -f ~/.vps-manager/sites_data.conf ]]; then
        sed -i 's/^webserver=.*/webserver=nginx/' ~/.vps-manager/sites_data.conf
    fi

    echo ""
    echo -e "${GREEN}════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}  ✅ Chuyển đổi OLS → Nginx hoàn tất!${NC}"
    echo -e "${GREEN}  Đã migrate : ${count} website${NC}"
    echo -e "${GREEN}  Giải phóng : ~${freed}MB disk${NC}"
    [[ -n "$cache_socket" ]] && \
        echo -e "${CYAN}  Object Cache: Unix Socket → ${cache_socket}${NC}"
    echo -e "${YELLOW}  Bước tiếp theo:${NC}"
    echo -e "  • Cài SSL: vps → SSL/TLS → Let's Encrypt từng domain"
    echo -e "  • Kích hoạt Redis Object Cache plugin trong WordPress"
    echo -e "${GREEN}════════════════════════════════════════════════════${NC}"
    pause
}

# Tạo Nginx vhost tối thiểu khi site.sh chưa load được
_make_minimal_nginx_vhost() {
    local domain="$1" php_ver="$2"
    local sock="/run/php/php${php_ver}-fpm.sock"
    local root="/var/www/${domain}/public_html"
    mkdir -p /etc/nginx/sites-available /etc/nginx/sites-enabled

    cat > "/etc/nginx/sites-available/${domain}" <<NGINXEOF
server {
    listen 80;
    server_name ${domain} www.${domain};
    root ${root};
    index index.php index.html;

    client_max_body_size 128M;

    location / {
        try_files \$uri \$uri/ /index.php?\$args;
    }

    location ~ \.php$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:${sock};
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        include fastcgi_params;
    }

    location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg|webp|woff2?)$ {
        expires 1y;
        add_header Cache-Control "public, immutable";
        access_log off;
    }

    location = /favicon.ico { log_not_found off; access_log off; }
    location = /robots.txt  { allow all; log_not_found off; access_log off; }
    location ~ /\.          { deny all; }
}
NGINXEOF
    ln -sf "/etc/nginx/sites-available/${domain}" "/etc/nginx/sites-enabled/${domain}"
}

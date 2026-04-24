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
    
    echo -e "${GREEN}Đã di tản thành công $count website sang OpenLiteSpeed!${NC}"
    pause
}

switch_to_nginx() {
    log_info "Bắt đầu chuyển đổi hạ tầng sang Nginx..."
    
    # Check Nginx installation
    if ! command -v nginx &>/dev/null; then
        log_error "Nginx chưa được cài đặt trên máy chủ!"
        echo -e "Vui lòng vào Menu 1 để Cài đặt LEMP trước."
        pause; return
    fi
    
    # 1. Switch Services
    if systemctl is-active --quiet lshttpd 2>/dev/null; then
        log_info "Đang tắt OpenLiteSpeed..."
        systemctl stop lshttpd 2>/dev/null
        systemctl disable lshttpd 2>/dev/null
    fi
    systemctl enable nginx 2>/dev/null
    
    # 2. Iterate websites
    local count=0
    for wp_config in /var/www/*/public_html/wp-config.php /var/www/*/public_html/index.php /var/www/*/public_html/index.html; do
        [[ ! -f "$wp_config" ]] && continue
        local domain=$(basename $(dirname $(dirname "$wp_config")))
        
        if [[ -f "/etc/nginx/sites-available/$domain" ]]; then
            log_warn "[$domain] Đã có cấu hình bên Nginx, bỏ qua..."
            [[ ! -L "/etc/nginx/sites-enabled/$domain" ]] && ln -s /etc/nginx/sites-available/$domain /etc/nginx/sites-enabled/
            continue
        fi
        
        log_info "Đang tạo hồ sơ Virtual Host cho: $domain..."
        source modules/site.sh
        
        local php_ver="8.3"
        [[ -d "/etc/php/8.4" ]] && php_ver="8.4"
        
        create_nginx_config "$domain" "$php_ver"
        
        count=$((count+1))
    done
    
    # Update global site conf
    if [[ -f ~/.vps-manager/sites_data.conf ]]; then
        sed -i 's/^webserver=.*/webserver=nginx/' ~/.vps-manager/sites_data.conf
    fi
    
    nginx -t && systemctl start nginx 2>/dev/null && systemctl restart nginx 2>/dev/null
    
    echo -e "${GREEN}Đã khôi phục thành công $count website về Nginx!${NC}"
    pause
}

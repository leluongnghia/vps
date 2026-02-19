#!/bin/bash

# modules/phpmyadmin.sh - Install & Manage phpMyAdmin

phpmyadmin_menu() {
    while true; do
        clear
        echo -e "${BLUE}=================================================${NC}"
        echo -e "${GREEN}          🗄️  Quản lý phpMyAdmin${NC}"
        echo -e "${BLUE}=================================================${NC}"

        # Show status
        if [ -d "/var/www/html/phpmyadmin" ]; then
            PMA_STATUS="${GREEN}● Đã cài đặt${NC}"
        else
            PMA_STATUS="${RED}● Chưa cài đặt${NC}"
        fi
        echo -e "Trạng thái: $PMA_STATUS"
        echo -e "${BLUE}=================================================${NC}"
        echo -e "1. Cài đặt / Cài lại phpMyAdmin"
        echo -e "2. Xóa phpMyAdmin"
        echo -e "3. Secure phpMyAdmin (Đổi URL ẩn)"
        echo -e "4. Reset mật khẩu HTTP Auth"
        echo -e "5. Xem thông tin truy cập"
        echo -e "0. Quay lại"
        echo -e "${BLUE}=================================================${NC}"
        read -p "Chọn: " c

        case $c in
            1) install_phpmyadmin ;;
            2) uninstall_phpmyadmin ;;
            3) secure_phpmyadmin ;;
            4) reset_phpmyadmin_auth ;;
            5) view_phpmyadmin_info ;;
            0) return ;;
            *) echo -e "${RED}Sai lựa chọn.${NC}"; pause ;;
        esac
    done
}

install_phpmyadmin() {
    echo -e "${GREEN}--- Cài đặt phpMyAdmin ---${NC}"

    PMA_DIR="/var/www/html/phpmyadmin"
    PMA_VER="5.2.1"
    TEMP_DIR="/tmp/pma_install"

    # Step 1: Dependencies
    log_info "Kiểm tra và cài đặt dependencies..."
    apt-get update -qq
    apt-get install -y php-mbstring php-zip php-gd php-curl php-xml apache2-utils wget 2>/dev/null

    # Step 2: Download
    log_info "Đang tải phpMyAdmin ${PMA_VER}..."
    rm -rf "$TEMP_DIR"
    mkdir -p "$TEMP_DIR"
    cd "$TEMP_DIR"

    if ! wget -q --show-progress "https://files.phpmyadmin.net/phpMyAdmin/${PMA_VER}/phpMyAdmin-${PMA_VER}-all-languages.tar.gz"; then
        log_error "Tải thất bại. Kiểm tra kết nối mạng."
        return 1
    fi

    # Step 3: Extract & Install
    log_info "Giải nén và cài đặt vào ${PMA_DIR}..."
    rm -rf "$PMA_DIR"
    tar xzf "phpMyAdmin-${PMA_VER}-all-languages.tar.gz" -C "$TEMP_DIR"
    mv "$TEMP_DIR"/phpMyAdmin-${PMA_VER}-* "$PMA_DIR"

    if [ ! -d "$PMA_DIR" ]; then
        log_error "Lỗi: Không tìm thấy thư mục sau khi giải nén."
        rm -rf "$TEMP_DIR"
        return 1
    fi

    # Step 4: Config file
    if [ -f "$PMA_DIR/config.sample.inc.php" ]; then
        cp "$PMA_DIR/config.sample.inc.php" "$PMA_DIR/config.inc.php"
        SECRET=$(openssl rand -base64 32 | tr -dc 'a-zA-Z0-9' | head -c 32)
        sed -i "s|\$cfg\['blowfish_secret'\] = '';|\$cfg['blowfish_secret'] = '${SECRET}';|" "$PMA_DIR/config.inc.php"
        log_info "Đã tạo config.inc.php với blowfish_secret."
    else
        log_error "Không tìm thấy config.sample.inc.php!"
    fi

    # Step 5: Permissions
    chown -R www-data:www-data "$PMA_DIR"
    find "$PMA_DIR" -type d -exec chmod 755 {} \;
    find "$PMA_DIR" -type f -exec chmod 644 {} \;

    # Cleanup temp
    rm -rf "$TEMP_DIR"

    # Step 6: HTTP Auth
    PMA_AUTH_USER="pma_admin"
    PMA_AUTH_PASS=$(openssl rand -base64 12 | tr -dc 'a-zA-Z0-9' | head -c 12)
    htpasswd -cb /etc/nginx/.phpmyadmin_htpasswd "$PMA_AUTH_USER" "$PMA_AUTH_PASS"
    log_info "Đã tạo HTTP Auth (lớp 1 bảo mật)."

    # Step 7: Detect PHP socket
    PHP_SOCK=""
    PHP_VER=$(php -r "echo PHP_MAJOR_VERSION.'.'.PHP_MINOR_VERSION;" 2>/dev/null)
    for ver in "$PHP_VER" "8.3" "8.2" "8.1"; do
        if [ -S "/run/php/php${ver}-fpm.sock" ]; then
            PHP_SOCK="unix:/run/php/php${ver}-fpm.sock"
            log_info "Tìm thấy PHP socket: ${PHP_SOCK}"
            break
        fi
    done

    if [ -z "$PHP_SOCK" ]; then
        log_error "Không tìm thấy PHP-FPM socket! Hãy cài PHP-FPM trước."
        return 1
    fi

    # Step 8: Detect VPS IP
    VPS_IP=$(curl -4 -s --connect-timeout 5 https://ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}')
    VPS_IP=$(echo "$VPS_IP" | tr -d '\n ' )

    # Step 9: Remove old default nginx
    if [ -L "/etc/nginx/sites-enabled/default" ]; then
        rm -f /etc/nginx/sites-enabled/default
        log_info "Đã gỡ nginx default site."
    fi

    # Step 10: Write Nginx config via printf (tránh bug heredoc với biến $)
    NGINX_CONF="/etc/nginx/sites-available/000-phpmyadmin"

    printf 'server {\n' > "$NGINX_CONF"
    printf '    listen 80 default_server;\n' >> "$NGINX_CONF"
    printf '    listen [::]:80 default_server;\n' >> "$NGINX_CONF"
    printf '    server_name _;\n' >> "$NGINX_CONF"
    printf '    root /var/www/html;\n' >> "$NGINX_CONF"
    printf '    index index.php index.html index.htm;\n\n' >> "$NGINX_CONF"

    printf '    location / {\n' >> "$NGINX_CONF"
    printf '        try_files $uri $uri/ =404;\n' >> "$NGINX_CONF"
    printf '    }\n\n' >> "$NGINX_CONF"

    printf '    # phpMyAdmin\n' >> "$NGINX_CONF"
    printf '    location ^~ /phpmyadmin {\n' >> "$NGINX_CONF"
    printf '        root /var/www/html;\n' >> "$NGINX_CONF"
    printf '        index index.php index.html index.htm;\n\n' >> "$NGINX_CONF"
    printf '        auth_basic "Restricted Access";\n' >> "$NGINX_CONF"
    printf '        auth_basic_user_file /etc/nginx/.phpmyadmin_htpasswd;\n\n' >> "$NGINX_CONF"
    printf '        location ~ ^/phpmyadmin/(.+\\.php)$ {\n' >> "$NGINX_CONF"
    printf '            try_files $uri =404;\n' >> "$NGINX_CONF"
    printf '            fastcgi_pass %s;\n' "$PHP_SOCK" >> "$NGINX_CONF"
    printf '            fastcgi_index index.php;\n' >> "$NGINX_CONF"
    printf '            fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;\n' >> "$NGINX_CONF"
    printf '            include fastcgi_params;\n' >> "$NGINX_CONF"
    printf '        }\n\n' >> "$NGINX_CONF"
    printf '        location ~* ^/phpmyadmin/.+\.(js|css|png|jpg|jpeg|gif|ico|svg|woff|woff2|ttf)$ {\n' >> "$NGINX_CONF"
    printf '            try_files $uri =404;\n' >> "$NGINX_CONF"
    printf '            expires max;\n' >> "$NGINX_CONF"
    printf '            add_header Cache-Control "public";\n' >> "$NGINX_CONF"
    printf '        }\n' >> "$NGINX_CONF"
    printf '    }\n\n' >> "$NGINX_CONF"

    printf '    location ~ \\.php$ {\n' >> "$NGINX_CONF"
    printf '        try_files $uri =404;\n' >> "$NGINX_CONF"
    printf '        include snippets/fastcgi-php.conf;\n' >> "$NGINX_CONF"
    printf '        fastcgi_pass %s;\n' "$PHP_SOCK" >> "$NGINX_CONF"
    printf '        fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;\n' >> "$NGINX_CONF"
    printf '        include fastcgi_params;\n' >> "$NGINX_CONF"
    printf '    }\n' >> "$NGINX_CONF"
    printf '}\n' >> "$NGINX_CONF"

    ln -sf "$NGINX_CONF" /etc/nginx/sites-enabled/000-phpmyadmin

    # Step 11: Test & Reload Nginx
    if nginx -t 2>/dev/null; then
        systemctl reload nginx
        echo -e "${GREEN}=====================================${NC}"
        echo -e "${GREEN}  ✅ Cài đặt phpMyAdmin hoàn tất!${NC}"
        echo -e "${GREEN}=====================================${NC}"
        echo -e "${YELLOW}URL truy cập:${NC} http://${VPS_IP}/phpmyadmin/"
        echo -e ""
        echo -e "${CYAN}[Lớp 1] HTTP Basic Auth:${NC}"
        echo -e "  User: ${PMA_AUTH_USER}"
        echo -e "  Pass: ${PMA_AUTH_PASS}"
        echo -e ""
        echo -e "${CYAN}[Lớp 2] Database Login:${NC}"
        if [ -f /root/.my.cnf ]; then
            root_pass=$(grep "password" /root/.my.cnf | head -1 | cut -d'=' -f2 | tr -d ' "')
            echo -e "  MySQL Root  → User: root | Pass: ${root_pass}"
        fi
        local data_file="$HOME/.vps-manager/sites_data.conf"
        if [ -f "$data_file" ]; then
            echo -e "  Website DBs →"
            while IFS='|' read -r dom dbn dbu dbp; do
                [ -n "$dom" ] && echo -e "    • ${dom}: user=${dbu} pass=${dbp}"
            done < "$data_file"
        fi
    else
        log_error "Nginx config lỗi! Kiểm tra: nginx -t"
        rm -f /etc/nginx/sites-enabled/000-phpmyadmin
    fi
    pause
}

uninstall_phpmyadmin() {
    echo -e "${YELLOW}--- Xóa phpMyAdmin ---${NC}"
    read -p "Xác nhận gỡ bỏ phpMyAdmin? (y/n): " c
    if [[ "$c" == "y" ]]; then
        rm -rf /var/www/html/phpmyadmin
        rm -f /etc/nginx/sites-enabled/000-phpmyadmin
        rm -f /etc/nginx/sites-available/000-phpmyadmin
        rm -f /etc/nginx/.phpmyadmin_htpasswd
        # Restore default nginx if no other sites
        nginx -t 2>/dev/null && systemctl reload nginx
        log_info "Đã gỡ bỏ phpMyAdmin và cấu hình Nginx."
    else
        echo -e "${YELLOW}Đã hủy.${NC}"
    fi
    pause
}

secure_phpmyadmin() {
    echo -e "${YELLOW}--- Đổi URL phpMyAdmin (Ẩn đường dẫn) ---${NC}"
    echo -e "Tính năng này đổi đường dẫn /phpmyadmin thành URL bí mật."
    read -p "Nhập tên đường dẫn mới (vd: manage_db_2025): " new_path

    if [ -z "$new_path" ]; then
        echo -e "${RED}Tên đường dẫn không được rỗng.${NC}"
        pause; return
    fi

    NGINX_CONF="/etc/nginx/sites-available/000-phpmyadmin"
    if [ ! -f "$NGINX_CONF" ]; then
        log_error "Chưa cài đặt phpMyAdmin hoặc thiếu cấu hình Nginx."
        pause; return
    fi

    # Rename physical folder
    if [ -d "/var/www/html/phpmyadmin" ]; then
        mv "/var/www/html/phpmyadmin" "/var/www/html/${new_path}"
    fi

    # Update nginx config
    sed -i "s|location \^~ /phpmyadmin|location ^~ /${new_path}|g" "$NGINX_CONF"
    sed -i "s|/phpmyadmin/|/${new_path}/|g" "$NGINX_CONF"

    if nginx -t 2>/dev/null; then
        systemctl reload nginx
        VPS_IP=$(curl -4 -s --connect-timeout 5 https://ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}')
        log_info "Đã đổi URL thành công!"
        echo -e "${GREEN}URL mới: http://${VPS_IP}/${new_path}/${NC}"
    else
        log_error "Lỗi Nginx sau khi cập nhật. Kiểm tra nginx -t"
    fi
    pause
}

reset_phpmyadmin_auth() {
    echo -e "${YELLOW}--- Reset mật khẩu HTTP Auth ---${NC}"

    if ! command -v htpasswd &> /dev/null; then apt-get install -y apache2-utils -qq; fi

    read -p "Nhập mật khẩu mới (Để trống = sinh ngẫu nhiên): " new_pass
    if [ -z "$new_pass" ]; then
        new_pass=$(openssl rand -base64 12 | tr -dc 'a-zA-Z0-9' | head -c 12)
    fi

    htpasswd -cb /etc/nginx/.phpmyadmin_htpasswd "pma_admin" "$new_pass"
    echo -e "${GREEN}✅ Đã đặt lại mật khẩu HTTP Auth!${NC}"
    echo -e "  User: pma_admin"
    echo -e "  Pass: ${new_pass}"
    pause
}

view_phpmyadmin_info() {
    echo -e "${YELLOW}--- Thông tin truy cập phpMyAdmin ---${NC}"

    VPS_IP=$(curl -4 -s --connect-timeout 5 https://ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}')

    # Detect current URL from nginx config
    NGINX_CONF="/etc/nginx/sites-available/000-phpmyadmin"
    if [ -f "$NGINX_CONF" ]; then
        PMA_PATH=$(grep "location \^~" "$NGINX_CONF" | awk '{print $3}')
        echo -e "${CYAN}URL:${NC} http://${VPS_IP}${PMA_PATH}"
    else
        echo -e "${RED}Chưa có cấu hình Nginx cho phpMyAdmin.${NC}"
    fi

    echo -e ""
    echo -e "${CYAN}[Lớp 1] HTTP Basic Auth:${NC}"
    if [ -f /etc/nginx/.phpmyadmin_htpasswd ]; then
        echo -e "  User: pma_admin"
        echo -e "  Pass: ${YELLOW}(đã mã hóa - dùng option 4 để reset)${NC}"
    else
        echo -e "  ${RED}Chưa có file htpasswd!${NC}"
    fi

    echo -e ""
    echo -e "${CYAN}[Lớp 2] Database Credentials:${NC}"
    if [ -f /root/.my.cnf ]; then
        root_pass=$(grep "password" /root/.my.cnf | head -1 | cut -d'=' -f2 | tr -d ' "')
        echo -e "  ${RED}MySQL Root${NC} → User: root | Pass: ${root_pass}"
    else
        echo -e "  MySQL Root: ${RED}Không tìm thấy .my.cnf${NC}"
    fi

    local data_file="$HOME/.vps-manager/sites_data.conf"
    if [ -f "$data_file" ]; then
        echo -e ""
        echo -e "${CYAN}  Website Database Users:${NC}"
        while IFS='|' read -r dom dbn dbu dbp; do
            [ -n "$dom" ] && echo -e "  🌐 ${dom}: db=${dbn} user=${dbu} pass=${dbp}"
        done < "$data_file"
    fi
    pause
}

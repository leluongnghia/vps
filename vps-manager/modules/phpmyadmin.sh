#!/bin/bash

# modules/phpmyadmin.sh - Install & Manage phpMyAdmin

# ─── Self-contained helpers (in case this module is sourced standalone) ───
_pma_log()  { echo -e "\033[0;32m[INFO]\033[0m $1"; }
_pma_warn() { echo -e "\033[1;33m[WARN]\033[0m $1"; }
_pma_err()  { echo -e "\033[0;31m[ERROR]\033[0m $1"; }

# ─── PHP socket detection (standalone, no external deps) ──────────────────
_detect_php_sock() {
    # Try current PHP version first
    local ver
    ver=$(php -r "echo PHP_MAJOR_VERSION.'.'.PHP_MINOR_VERSION;" 2>/dev/null)
    for v in "$ver" "8.3" "8.2" "8.1" "8.0" "7.4"; do
        [ -z "$v" ] && continue
        if [[ -S "/run/php/php${v}-fpm.sock" ]]; then
            echo "unix:/run/php/php${v}-fpm.sock"
            return 0
        fi
    done
    # Fallback: find any socket
    local sock
    sock=$(find /run/php -name "php*-fpm.sock" 2>/dev/null | sort -V | tail -1)
    if [[ -n "$sock" ]]; then
        echo "unix:$sock"
        return 0
    fi
    return 1
}

phpmyadmin_menu() {
    while true; do
        clear
        echo -e "${BLUE}=================================================${NC}"
        echo -e "${GREEN}          🗄️  Quản lý phpMyAdmin${NC}"
        echo -e "${BLUE}=================================================${NC}"

        if [[ -d "/var/www/html/phpmyadmin" ]]; then
            echo -e "Trạng thái: ${GREEN}● Đã cài đặt${NC}"
        else
            echo -e "Trạng thái: ${RED}● Chưa cài đặt${NC}"
        fi
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
    echo -e "${GREEN}============================================${NC}"
    echo -e "${GREEN}     Cài đặt phpMyAdmin                    ${NC}"
    echo -e "${GREEN}============================================${NC}"

    # ── Kiểm tra root ─────────────────────────────────────────
    if [[ "$EUID" -ne 0 ]]; then
        _pma_err "Cần chạy với quyền root!"
        pause; return 1
    fi

    PMA_DIR="/var/www/html/phpmyadmin"
    PMA_VER="5.2.1"
    TEMP_DIR="/tmp/pma_install_$$"

    # ── Step 1: Dependencies ───────────────────────────────────
    _pma_log "Step 1/7: Cài đặt dependencies..."
    apt-get update -qq 2>/dev/null
    apt-get install -y php-mbstring php-zip php-gd php-curl php-xml apache2-utils wget unzip 2>/dev/null
    if [[ $? -ne 0 ]]; then
        _pma_warn "Một số package có thể chưa được cài. Tiếp tục..."
    fi

    # ── Step 2: Download ───────────────────────────────────────
    _pma_log "Step 2/7: Tải phpMyAdmin ${PMA_VER}..."
    rm -rf "$TEMP_DIR"
    mkdir -p "$TEMP_DIR"

    local tarball="phpMyAdmin-${PMA_VER}-all-languages.tar.gz"
    local url="https://files.phpmyadmin.net/phpMyAdmin/${PMA_VER}/${tarball}"

    # Try wget, fallback to curl
    if command -v wget &>/dev/null; then
        wget -q -O "$TEMP_DIR/$tarball" "$url"
    elif command -v curl &>/dev/null; then
        curl -sL -o "$TEMP_DIR/$tarball" "$url"
    else
        _pma_err "Không có wget hoặc curl. Cài wget: apt-get install -y wget"
        rm -rf "$TEMP_DIR"; pause; return 1
    fi

    if [[ ! -f "$TEMP_DIR/$tarball" ]] || [[ ! -s "$TEMP_DIR/$tarball" ]]; then
        _pma_err "Tải thất bại! Kiểm tra kết nối mạng."
        _pma_err "Thử thủ công: wget '$url'"
        rm -rf "$TEMP_DIR"; pause; return 1
    fi
    _pma_log "Tải thành công: $(du -sh "$TEMP_DIR/$tarball" | cut -f1)"

    # ── Step 3: Extract ────────────────────────────────────────
    _pma_log "Step 3/7: Giải nén..."
    tar xzf "$TEMP_DIR/$tarball" -C "$TEMP_DIR"
    if [[ $? -ne 0 ]]; then
        _pma_err "Giải nén thất bại! File có thể bị hỏng."
        rm -rf "$TEMP_DIR"; pause; return 1
    fi

    # ── Step 4: Install ────────────────────────────────────────
    _pma_log "Step 4/7: Cài đặt vào ${PMA_DIR}..."
    rm -rf "$PMA_DIR"
    # Find extracted folder (handle version mismatch in folder name)
    local extracted_dir
    extracted_dir=$(find "$TEMP_DIR" -maxdepth 1 -type d -name "phpMyAdmin-*" | head -1)

    if [[ -z "$extracted_dir" ]]; then
        _pma_err "Không tìm thấy thư mục sau giải nén!"
        ls -la "$TEMP_DIR"
        rm -rf "$TEMP_DIR"; pause; return 1
    fi

    mv "$extracted_dir" "$PMA_DIR"
    rm -rf "$TEMP_DIR"

    if [[ ! -d "$PMA_DIR" ]]; then
        _pma_err "Di chuyển thư mục thất bại!"
        pause; return 1
    fi
    _pma_log "Đã cài đặt vào: $PMA_DIR"

    # ── Step 5: Config ─────────────────────────────────────────
    _pma_log "Step 5/7: Tạo config..."
    if [[ -f "$PMA_DIR/config.sample.inc.php" ]]; then
        cp "$PMA_DIR/config.sample.inc.php" "$PMA_DIR/config.inc.php"
        local SECRET
        SECRET=$(openssl rand -base64 32 | tr -dc 'a-zA-Z0-9' | head -c 32)
        # Use perl -pi -e for correct in-place substitution
        if command -v perl &>/dev/null; then
            perl -pi -e "s|\\\$cfg\\['blowfish_secret'\\] = '';|\$cfg['blowfish_secret'] = '${SECRET}';|" "$PMA_DIR/config.inc.php"
        else
            sed -i "s/\\\$cfg\\['blowfish_secret'\\] = '';/\$cfg['blowfish_secret'] = '${SECRET}';/" "$PMA_DIR/config.inc.php"
        fi
        _pma_log "Config tạo thành công."
    else
        _pma_warn "Không tìm thấy config.sample.inc.php (không nghiêm trọng)"
    fi

    # ── Step 5b: disable tmp dir security warning ──────────────
    mkdir -p "$PMA_DIR/tmp"
    chown www-data:www-data "$PMA_DIR/tmp"
    chmod 700 "$PMA_DIR/tmp"

    # ── Step 6: Permissions ────────────────────────────────────
    _pma_log "Step 6/7: Cấu hình quyền..."
    chown -R www-data:www-data "$PMA_DIR"
    find "$PMA_DIR" -type d -exec chmod 755 {} \; 2>/dev/null
    find "$PMA_DIR" -type f -exec chmod 644 {} \; 2>/dev/null
    chmod 700 "$PMA_DIR/tmp" 2>/dev/null

    # ── Step 7: HTTP Auth + Nginx ──────────────────────────────
    _pma_log "Step 7/7: Cấu hình Nginx + HTTP Auth..."

    # Install htpasswd if missing
    if ! command -v htpasswd &>/dev/null; then
        apt-get install -y apache2-utils -qq
    fi

    local PMA_AUTH_USER="pma_admin"
    local PMA_AUTH_PASS
    PMA_AUTH_PASS=$(openssl rand -base64 12 | tr -dc 'a-zA-Z0-9' | head -c 12)
    echo "$PMA_AUTH_PASS" | htpasswd -ci /etc/nginx/.phpmyadmin_htpasswd "$PMA_AUTH_USER"

    # Lưu plaintext để xem lại sau
    mkdir -p /root/.vps-manager
    echo "PMA_USER=${PMA_AUTH_USER}" > /root/.vps-manager/phpmyadmin_auth.conf
    echo "PMA_PASS=${PMA_AUTH_PASS}" >> /root/.vps-manager/phpmyadmin_auth.conf
    chmod 600 /root/.vps-manager/phpmyadmin_auth.conf

    # ── Detect PHP Socket ──────────────────────────────────────
    local PHP_SOCK
    PHP_SOCK=$(_detect_php_sock)
    if [[ -z "$PHP_SOCK" ]]; then
        _pma_err "Không tìm thấy PHP-FPM socket!"
        _pma_err "Kiểm tra: ls /run/php/"
        _pma_warn "Cài số: apt-get install -y php-fpm"
        pause; return 1
    fi
    _pma_log "PHP Socket: $PHP_SOCK"

    # ── Detect VPS IP ──────────────────────────────────────────
    local VPS_IP
    VPS_IP=$(curl -4 -s --connect-timeout 5 https://ifconfig.me 2>/dev/null)
    [ -z "$VPS_IP" ] && VPS_IP=$(hostname -I | awk '{print $1}')
    VPS_IP=$(echo "$VPS_IP" | tr -d '\n ')

    # ── Remove old default Nginx ───────────────────────────────
    [ -L "/etc/nginx/sites-enabled/default" ] && rm -f /etc/nginx/sites-enabled/default

    # ── Write Nginx config (printf avoids heredoc $ escaping issues) ─
    local NGINX_CONF="/etc/nginx/sites-available/000-phpmyadmin"
    {
        printf 'server {\n'
        printf '    listen 80 default_server;\n'
        printf '    listen [::]:80 default_server;\n'
        printf '    server_name _;\n'
        printf '    root /var/www/html;\n'
        printf '    index index.php index.html index.htm;\n\n'

        printf '    location / {\n'
        printf '        try_files $uri $uri/ =404;\n'
        printf '    }\n\n'

        printf '    # phpMyAdmin location\n'
        printf '    location ^~ /phpmyadmin {\n'
        printf '        root /var/www/html;\n'
        printf '        index index.php index.html index.htm;\n\n'
        printf '        auth_basic "Restricted Access";\n'
        printf '        auth_basic_user_file /etc/nginx/.phpmyadmin_htpasswd;\n\n'

        printf '        location ~ ^/phpmyadmin/(.+\\.php)$ {\n'
        printf '            try_files $uri =404;\n'
        printf '            fastcgi_pass %s;\n' "$PHP_SOCK"
        printf '            fastcgi_index index.php;\n'
        printf '            fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;\n'
        printf '            include fastcgi_params;\n'
        printf '        }\n\n'

        printf '        location ~* ^/phpmyadmin/.+\\.(js|css|png|jpg|jpeg|gif|ico|svg|woff|woff2|ttf)$ {\n'
        printf '            try_files $uri =404;\n'
        printf '            expires max;\n'
        printf '            add_header Cache-Control "public";\n'
        printf '        }\n'
        printf '    }\n\n'

        printf '    # PHP handler for root (NOTE: fastcgi-php.conf already has try_files)\n'
        printf '    location ~ \\.php$ {\n'
        printf '        include snippets/fastcgi-php.conf;\n'
        printf '        fastcgi_pass %s;\n' "$PHP_SOCK"
        printf '        fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;\n'
        printf '        include fastcgi_params;\n'
        printf '    }\n'
        printf '}\n'
    } > "$NGINX_CONF"

    ln -sf "$NGINX_CONF" /etc/nginx/sites-enabled/000-phpmyadmin

    # ── Test & Reload ──────────────────────────────────────────
    echo ""
    nginx -t
    if [[ $? -eq 0 ]]; then
        systemctl reload nginx
        echo ""
        echo -e "${GREEN}╔══════════════════════════════════════════════╗${NC}"
        echo -e "${GREEN}║  ✅  Cài đặt phpMyAdmin THÀNH CÔNG!          ║${NC}"
        echo -e "${GREEN}╚══════════════════════════════════════════════╝${NC}"
        echo ""
        echo -e "${YELLOW}🌐 URL truy cập:${NC}"
        echo -e "   http://${VPS_IP}/phpmyadmin/"
        echo ""
        echo -e "${CYAN}🔐 [Lớp 1] HTTP Basic Auth:${NC}"
        echo -e "   User: ${PMA_AUTH_USER}"
        echo -e "   Pass: ${PMA_AUTH_PASS}"
        echo ""
        echo -e "${CYAN}🔐 [Lớp 2] Database Login:${NC}"
        if [[ -f /root/.my.cnf ]]; then
            local root_pass
            root_pass=$(grep "^password" /root/.my.cnf | head -1 | cut -d'=' -f2 | tr -d ' "')
            echo -e "   MySQL Root → User: root | Pass: ${root_pass}"
        else
            echo -e "   Dùng user/pass MySQL của bạn."
        fi
        local data_file="$HOME/.vps-manager/sites_data.conf"
        if [[ -f "$data_file" ]]; then
            echo ""
            echo -e "${CYAN}   Website DB Users:${NC}"
            while IFS='|' read -r dom dbn dbu dbp; do
                [ -n "$dom" ] && echo -e "   • ${dom}: user=${dbu} pass=${dbp}"
            done < "$data_file"
        fi
    else
        _pma_err "Nginx config có lỗi! Đang rollback..."
        rm -f /etc/nginx/sites-enabled/000-phpmyadmin
        _pma_err "Kiểm tra thủ công: nginx -t"
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
        nginx -t 2>/dev/null && systemctl reload nginx
        _pma_log "Đã gỡ bỏ phpMyAdmin."
    else
        echo -e "${YELLOW}Đã hủy.${NC}"
    fi
    pause
}

secure_phpmyadmin() {
    echo -e "${YELLOW}--- Đổi URL phpMyAdmin (Ẩn đường dẫn) ---${NC}"
    read -p "Nhập tên đường dẫn mới (vd: manage_db_2025): " new_path

    if [[ -z "$new_path" ]]; then
        echo -e "${RED}Tên đường dẫn không được rỗng.${NC}"
        pause; return
    fi

    local NGINX_CONF="/etc/nginx/sites-available/000-phpmyadmin"
    if [[ ! -f "$NGINX_CONF" ]]; then
        _pma_err "Chưa cài đặt phpMyAdmin hoặc thiếu cấu hình Nginx."
        pause; return
    fi

    # Rename folder
    if [[ -d "/var/www/html/phpmyadmin" ]]; then
        mv "/var/www/html/phpmyadmin" "/var/www/html/${new_path}"
        _pma_log "Đã đổi thư mục thành /var/www/html/${new_path}"
    fi

    # Update nginx config
    sed -i "s|location \^~ /phpmyadmin|location ^~ /${new_path}|g" "$NGINX_CONF"
    sed -i "s|/phpmyadmin/|/${new_path}/|g" "$NGINX_CONF"

    if nginx -t 2>/dev/null; then
        systemctl reload nginx
        local VPS_IP
        VPS_IP=$(curl -4 -s --connect-timeout 5 https://ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}')
        _pma_log "Đã đổi URL thành công!"
        echo -e "${GREEN}URL mới: http://${VPS_IP}/${new_path}/${NC}"
    else
        _pma_err "Lỗi Nginx sau khi cập nhật. Kiểm tra nginx -t"
    fi
    pause
}

reset_phpmyadmin_auth() {
    echo -e "${YELLOW}--- Reset mật khẩu HTTP Auth ---${NC}"
    if ! command -v htpasswd &>/dev/null; then
        apt-get install -y apache2-utils -qq
    fi

    read -p "Nhập mật khẩu mới (Để trống = sinh ngẫu nhiên): " new_pass
    if [[ -z "$new_pass" ]]; then
        new_pass=$(openssl rand -base64 12 | tr -dc 'a-zA-Z0-9' | head -c 12)
    fi

    echo "$new_pass" | htpasswd -ci /etc/nginx/.phpmyadmin_htpasswd "pma_admin"

    # Lưu plaintext để xem lại sau
    mkdir -p /root/.vps-manager
    echo "PMA_USER=pma_admin" > /root/.vps-manager/phpmyadmin_auth.conf
    echo "PMA_PASS=${new_pass}" >> /root/.vps-manager/phpmyadmin_auth.conf
    chmod 600 /root/.vps-manager/phpmyadmin_auth.conf

    echo -e "${GREEN}✅ Đã đặt lại mật khẩu!${NC}"
    echo -e "   User: pma_admin"
    echo -e "   Pass: ${new_pass}"
    echo -e "   ${CYAN}(Đã lưu vào /root/.vps-manager/phpmyadmin_auth.conf)${NC}"
    pause
}

view_phpmyadmin_info() {
    echo -e "${YELLOW}--- Thông tin truy cập phpMyAdmin ---${NC}"

    local VPS_IP
    VPS_IP=$(curl -4 -s --connect-timeout 5 https://ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}')

    local NGINX_CONF="/etc/nginx/sites-available/000-phpmyadmin"
    if [[ -f "$NGINX_CONF" ]]; then
        local PMA_PATH
        PMA_PATH=$(grep "location \^~" "$NGINX_CONF" | awk '{print $3}')
        echo -e "${CYAN}URL:${NC} http://${VPS_IP}${PMA_PATH}"
    else
        echo -e "${RED}Chưa có cấu hình Nginx cho phpMyAdmin.${NC}"
    fi

    echo ""
    echo -e "${CYAN}[Lớp 1] HTTP Basic Auth:${NC}"
    if [[ -f /root/.vps-manager/phpmyadmin_auth.conf ]]; then
        source /root/.vps-manager/phpmyadmin_auth.conf
        echo -e "   User: ${PMA_USER:-pma_admin}"
        echo -e "   Pass: ${GREEN}${PMA_PASS}${NC}"
    elif [[ -f /etc/nginx/.phpmyadmin_htpasswd ]]; then
        echo -e "   User: pma_admin"
        echo -e "   Pass: ${YELLOW}(chưa lưu plaintext — dùng option 4 để reset và lưu lại)${NC}"
    else
        echo -e "   ${RED}Chưa có file htpasswd!${NC}"
    fi

    echo ""
    echo -e "${CYAN}[Lớp 2] Database Credentials:${NC}"
    if [[ -f /root/.my.cnf ]]; then
        local root_pass
        root_pass=$(grep "^password" /root/.my.cnf | head -1 | cut -d'=' -f2 | tr -d ' "')
        echo -e "   ${RED}MySQL Root${NC} → User: root | Pass: ${root_pass}"
    else
        echo -e "   MySQL Root: ${RED}Không tìm thấy .my.cnf${NC}"
    fi

    local data_file="$HOME/.vps-manager/sites_data.conf"
    if [[ -f "$data_file" ]]; then
        echo ""
        echo -e "${CYAN}   Website DB Users:${NC}"
        while IFS='|' read -r dom dbn dbu dbp; do
            [ -n "$dom" ] && echo -e "   🌐 ${dom}: db=${dbn} user=${dbu} pass=${dbp}"
        done < "$data_file"
    fi
    pause
}

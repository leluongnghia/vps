#!/bin/bash

# modules/phpmyadmin.sh - Install & Manage phpMyAdmin

# ─── Self-contained helpers (in case this module is sourced standalone) ───
_pma_log()  { echo -e "\033[0;32m[INFO]\033[0m $1"; }
_pma_warn() { echo -e "\033[1;33m[WARN]\033[0m $1"; }
_pma_err()  { echo -e "\033[0;31m[ERROR]\033[0m $1"; }

# (PHP socket: dùng detect_php_socket của core/system_helpers.sh)

PMA_STATE_FILE="/etc/vps-manager/pma_path"
PMA_NGINX_CONF="/etc/nginx/sites-available/000-phpmyadmin"
PMA_CERT_DIR="/etc/nginx/ssl/phpmyadmin"

# Tên đường dẫn hiện tại của phpMyAdmin (mặc định "phpmyadmin", đổi được qua mục Secure)
_pma_path() {
    local p=""
    [[ -f "$PMA_STATE_FILE" ]] && p=$(head -n 1 "$PMA_STATE_FILE" | tr -d '[:space:]')
    [[ "$p" =~ ^[A-Za-z0-9_-]{1,64}$ ]] || p="phpmyadmin"
    echo "$p"
}

_pma_public_ip() {
    local ip
    ip=$(curl -4 -s --connect-timeout 5 https://ifconfig.me 2>/dev/null)
    [[ -z "$ip" ]] && ip=$(hostname -I | awk '{print $1}')
    echo "$ip" | tr -d '\n '
}

# http hay https, tuỳ vhost đang chạy có TLS không
_pma_scheme() {
    if grep -q "listen 443 ssl" "$PMA_NGINX_CONF" 2>/dev/null; then echo "https"; else echo "http"; fi
}

# Tạo chứng chỉ tự ký để mật khẩu Basic Auth / MySQL không đi dạng cleartext trên Internet
_pma_ensure_cert() {
    [[ -s "$PMA_CERT_DIR/cert.pem" && -s "$PMA_CERT_DIR/key.pem" ]] && return 0
    mkdir -p "$PMA_CERT_DIR"
    openssl req -x509 -nodes -newkey rsa:2048 -days 3650 \
        -subj "/CN=phpmyadmin.local" \
        -keyout "$PMA_CERT_DIR/key.pem" -out "$PMA_CERT_DIR/cert.pem" &>/dev/null || return 1
    chmod 600 "$PMA_CERT_DIR/key.pem"
}

# Ghi vhost phpMyAdmin.  $1 = tên đường dẫn, $2 = fastcgi_pass, $3 = "tls" | "plain"
_pma_write_nginx_conf() {
    local path=$1 sock=$2 mode=${3:-tls}
    local pma_block
    pma_block=$(cat <<EOF
    location ^~ /${path} {
        client_max_body_size 500M;
        root /var/www/html;
        index index.php index.html index.htm;

        auth_basic "Restricted Access";
        auth_basic_user_file /etc/nginx/.phpmyadmin_htpasswd;

        # Thư mục nội bộ của phpMyAdmin không được truy cập từ web
        location ~ ^/${path}/(libraries|templates|setup/lib|vendor|tmp|sql)/ { deny all; }

        location ~ ^/${path}/(.+\\.php)\$ {
            try_files \$uri =404;
            fastcgi_pass ${sock};
            fastcgi_buffer_size 128k;
            fastcgi_buffers 4 256k;
            fastcgi_busy_buffers_size 256k;
            fastcgi_index index.php;
            fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
            fastcgi_param PHP_VALUE "upload_max_filesize=500M \\n post_max_size=500M \\n max_execution_time=3600 \\n max_input_time=3600";
            include fastcgi_params;
        }

        location ~* ^/${path}/.+\\.(js|css|png|jpg|jpeg|gif|ico|svg|woff|woff2|ttf)\$ {
            try_files \$uri =404;
            expires max;
            add_header Cache-Control "public";
        }
    }
EOF
)
    # PHP nằm ngoài thư mục phpMyAdmin trong /var/www/html KHÔNG được thực thi (cũng không lộ mã nguồn):
    # tránh việc một bản sao cũ của phpMyAdmin chạy được mà không qua Basic Auth.
    local deny_php='    location ~ \.php$ { return 404; }'

    if [[ "$mode" == "tls" ]]; then
        cat > "$PMA_NGINX_CONF" <<EOF
# Managed by VPS-Manager (modules/phpmyadmin.sh)
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name _;
    root /var/www/html;
    index index.html index.htm;

    location / { try_files \$uri \$uri/ =404; }
    # phpMyAdmin chỉ phục vụ qua HTTPS
    location ^~ /${path} { return 301 https://\$host\$request_uri; }
${deny_php}
}

server {
    listen 443 ssl default_server;
    listen [::]:443 ssl default_server;
    server_name _;
    ssl_certificate     ${PMA_CERT_DIR}/cert.pem;
    ssl_certificate_key ${PMA_CERT_DIR}/key.pem;
    root /var/www/html;
    index index.html index.htm;

    location / { return 444; }
${pma_block}
${deny_php}
}
EOF
    else
        cat > "$PMA_NGINX_CONF" <<EOF
# Managed by VPS-Manager (modules/phpmyadmin.sh)
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name _;
    root /var/www/html;
    index index.html index.htm;

    location / { try_files \$uri \$uri/ =404; }
${pma_block}
${deny_php}
}
EOF
    fi
    ln -sf "$PMA_NGINX_CONF" /etc/nginx/sites-enabled/000-phpmyadmin
    type selinux_restore &>/dev/null && selinux_restore "$PMA_NGINX_CONF" /var/www/html
    return 0
}

# Ghi vhost (ưu tiên HTTPS tự ký; nếu nginx từ chối thì lùi về HTTP) rồi test + reload.
# Lỗi hoàn toàn -> khôi phục vhost cũ.  $1 = path, $2 = fastcgi_pass
_pma_apply_nginx() {
    local path=$1 sock=$2 bak=""
    [[ -f "$PMA_NGINX_CONF" ]] && { bak="${PMA_NGINX_CONF}.bak_$$"; cp -p "$PMA_NGINX_CONF" "$bak"; }

    if _pma_ensure_cert; then
        _pma_write_nginx_conf "$path" "$sock" tls
        if nginx -t &>/dev/null; then
            systemctl reload nginx; rm -f "$bak"; return 0
        fi
        _pma_warn "Không bật được HTTPS cho phpMyAdmin (có vhost khác đã là default_server cổng 443?). Dùng HTTP."
    fi
    _pma_write_nginx_conf "$path" "$sock" plain
    if nginx -t &>/dev/null; then
        systemctl reload nginx; rm -f "$bak"; return 0
    fi
    _pma_err "Nginx config có lỗi:"
    nginx -t 2>&1 | tail -5
    if [[ -n "$bak" ]]; then
        mv -f "$bak" "$PMA_NGINX_CONF"
    else
        rm -f /etc/nginx/sites-enabled/000-phpmyadmin
    fi
    return 1
}

phpmyadmin_menu() {
    while true; do
        clear
        echo -e "${BLUE}=================================================${NC}"
        echo -e "${GREEN}          🗄️  Quản lý phpMyAdmin${NC}"
        echo -e "${BLUE}=================================================${NC}"

        if [[ -d "/var/www/html/$(_pma_path)" ]]; then
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

    local PMA_PATH
    PMA_PATH=$(_pma_path)
    PMA_DIR="/var/www/html/${PMA_PATH}"
    # Lấy phiên bản ổn định mới nhất từ phpmyadmin.net (bản cũ còn lỗi bảo mật đã được vá)
    PMA_VER=$(curl -fsSL --max-time 10 https://www.phpmyadmin.net/home_page/version.txt 2>/dev/null | head -n 1 | tr -d '[:space:]')
    [[ "$PMA_VER" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || PMA_VER="5.2.2"
    TEMP_DIR=$(mktemp -d /tmp/pma_install_XXXXXX) || { _pma_err "Không tạo được thư mục tạm."; pause; return 1; }

    # ── Step 1: Dependencies ───────────────────────────────────
    _pma_log "Step 1/7: Cài đặt dependencies..."
    # Detect OS and install dependencies
    if [[ -f /etc/os-release ]]; then
        source /etc/os-release
    fi
    if [[ "${ID:-}" == "ubuntu" || "${ID:-}" == "debian" ]]; then
        apt-get update -qq 2>/dev/null || true
        apt-get install -y php-mbstring php-zip php-gd php-curl php-xml apache2-utils wget unzip 2>/dev/null || true
    elif [[ "${ID:-}" == "almalinux" || "${ID:-}" == "rocky" || "${ID:-}" == "rhel" || "${ID:-}" == "centos" || "${ID:-}" == "ol" || "${ID:-}" == "oracle" || "${ID_LIKE:-}" =~ (rhel|fedora|centos) ]]; then
        dnf install -y php-mbstring php-zip php-gd php-curl php-xml httpd-tools wget unzip 2>/dev/null || true
    else
        # Fallback: try pkg_install if available
        if type pkg_install &>/dev/null; then
            pkg_install php-mbstring php-zip php-gd php-curl php-xml wget unzip 2>/dev/null || true
        fi
    fi
    if [[ $? -ne 0 ]]; then
        _pma_warn "Một số package có thể chưa được cài. Tiếp tục..."
    fi

    # ── Step 2: Download ───────────────────────────────────────
    _pma_log "Step 2/7: Tải phpMyAdmin ${PMA_VER}..."
    local tarball="phpMyAdmin-${PMA_VER}-all-languages.tar.gz"
    local url="https://files.phpmyadmin.net/phpMyAdmin/${PMA_VER}/${tarball}"

    # Tải kèm kiểm tra SHA256 do phpmyadmin.net công bố (bắt được file tải dở / bị thay đổi)
    local pma_sum
    pma_sum=$(curl -fsSL --max-time 20 "${url}.sha256" 2>/dev/null | awk '{print $1}' | head -n 1)
    if [[ ! "$pma_sum" =~ ^[0-9a-fA-F]{64}$ ]]; then
        _pma_err "Không lấy được checksum của phpMyAdmin ${PMA_VER}. Kiểm tra kết nối mạng."
        rm -rf "$TEMP_DIR"; pause; return 1
    fi
    if ! safe_download "$url" "$TEMP_DIR/$tarball" "$pma_sum"; then
        _pma_err "Tải thất bại hoặc checksum không khớp."
        _pma_err "Thử thủ công: wget '$url'"
        rm -rf "$TEMP_DIR"; pause; return 1
    fi
    _pma_log "Tải thành công (đã xác minh SHA256): $(du -sh "$TEMP_DIR/$tarball" | cut -f1)"

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
    # Ensure parent directory exists (may not exist on Nginx-only setup)
    mkdir -p "$(dirname "$PMA_DIR")"
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
            perl -pi -e "s|(\\\$cfg\['blowfish_secret'\] = )'';|\${1}'${SECRET}';|" "$PMA_DIR/config.inc.php"
        else
            sed -i "s/\(\\\$cfg\\['blowfish_secret'\\] = \)'';/\\1'${SECRET}';/" "$PMA_DIR/config.inc.php"
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
        if [[ "${ID:-}" == "ubuntu" || "${ID:-}" == "debian" ]]; then
            apt-get install -y apache2-utils -qq
        else
            dnf install -y httpd-tools -q 2>/dev/null || true
        fi
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
    PHP_SOCK=$(detect_php_socket 2>/dev/null)
    if [[ -z "$PHP_SOCK" ]]; then
        _pma_err "Không tìm thấy PHP-FPM socket!"
        _pma_err "Kiểm tra: ls /run/php/ hoặc ls /var/run/php-fpm/"
        _pma_warn "Cài PHP-FPM: apt-get install -y php-fpm  hoặc  dnf install -y php-fpm"
        pause; return 1
    fi
    _pma_log "PHP Socket: $PHP_SOCK"

    # ── Detect VPS IP ──────────────────────────────────────────
    local VPS_IP
    VPS_IP=$(_pma_public_ip)

    # ── Remove old default Nginx ───────────────────────────────
    [ -L "/etc/nginx/sites-enabled/default" ] && rm -f /etc/nginx/sites-enabled/default

    # ── Ghi vhost (HTTPS tự ký, lùi về HTTP nếu không được), test & reload, tự hoàn tác khi lỗi ─
    echo ""
    if _pma_apply_nginx "$PMA_PATH" "$PHP_SOCK"; then
        mkdir -p "$(dirname "$PMA_STATE_FILE")"
        echo "$PMA_PATH" > "$PMA_STATE_FILE"
        local scheme
        scheme=$(_pma_scheme)
        echo ""
        echo -e "${GREEN}╔══════════════════════════════════════════════╗${NC}"
        echo -e "${GREEN}║  ✅  Cài đặt phpMyAdmin THÀNH CÔNG!          ║${NC}"
        echo -e "${GREEN}╚══════════════════════════════════════════════╝${NC}"
        echo ""
        echo -e "${YELLOW}🌐 URL truy cập:${NC}"
        echo -e "   ${scheme}://${VPS_IP}/${PMA_PATH}/"
        if [[ "$scheme" == "https" ]]; then
            echo -e "   ${CYAN}(Chứng chỉ tự ký: trình duyệt sẽ cảnh báo lần đầu - chọn 'Tiếp tục'. Kết nối vẫn được mã hoá.)${NC}"
        else
            echo -e "   ${RED}CẢNH BÁO: đang chạy HTTP - mật khẩu đi qua mạng không mã hoá. Nên giới hạn IP truy cập.${NC}"
        fi
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
        _pma_err "Không cấu hình được Nginx cho phpMyAdmin (đã hoàn tác). Kiểm tra thủ công: nginx -t"
    fi
    pause
}

uninstall_phpmyadmin() {
    echo -e "${YELLOW}--- Xóa phpMyAdmin ---${NC}"
    local cur
    cur=$(_pma_path)
    read -p "Xác nhận gỡ bỏ phpMyAdmin (/var/www/html/${cur})? (y/n): " c
    if [[ "$c" == "y" ]]; then
        # $cur đã được _pma_path kiểm tra chỉ gồm [A-Za-z0-9_-] nên không thể trỏ ra ngoài /var/www/html
        rm -rf "/var/www/html/${cur}"
        [[ "$cur" != "phpmyadmin" ]] && rm -rf /var/www/html/phpmyadmin
        rm -f /etc/nginx/sites-enabled/000-phpmyadmin
        rm -f "$PMA_NGINX_CONF"
        rm -f /etc/nginx/.phpmyadmin_htpasswd "$PMA_STATE_FILE"
        rm -f /root/.vps-manager/phpmyadmin_auth.conf
        nginx_test_reload
        _pma_log "Đã gỡ bỏ phpMyAdmin."
    else
        echo -e "${YELLOW}Đã hủy.${NC}"
    fi
    pause
}

secure_phpmyadmin() {
    echo -e "${YELLOW}--- Đổi URL phpMyAdmin (Ẩn đường dẫn) ---${NC}"
    local cur
    cur=$(_pma_path)
    if [[ ! -f "$PMA_NGINX_CONF" ]] || [[ ! -d "/var/www/html/${cur}" ]]; then
        _pma_err "Chưa cài đặt phpMyAdmin hoặc thiếu cấu hình Nginx."
        pause; return
    fi
    echo -e "Đường dẫn hiện tại: /${cur}/"
    read -p "Nhập tên đường dẫn mới (vd: manage_db_2025): " new_path

    if ! [[ "$new_path" =~ ^[A-Za-z0-9_-]{6,64}$ ]]; then
        echo -e "${RED}Tên đường dẫn chỉ gồm chữ, số, '_' hoặc '-', dài 6-64 ký tự.${NC}"
        pause; return
    fi
    if [[ "$new_path" == "$cur" ]]; then
        echo -e "${YELLOW}Đường dẫn mới trùng với đường dẫn hiện tại.${NC}"
        pause; return
    fi
    if [[ -e "/var/www/html/${new_path}" ]]; then
        echo -e "${RED}/var/www/html/${new_path} đã tồn tại. Chọn tên khác.${NC}"
        pause; return
    fi

    local PHP_SOCK
    PHP_SOCK=$(detect_php_socket 2>/dev/null)
    if [[ -z "$PHP_SOCK" ]]; then
        _pma_err "Không tìm thấy PHP-FPM socket."
        pause; return 1
    fi

    mv "/var/www/html/${cur}" "/var/www/html/${new_path}"
    if _pma_apply_nginx "$new_path" "$PHP_SOCK"; then
        mkdir -p "$(dirname "$PMA_STATE_FILE")"
        echo "$new_path" > "$PMA_STATE_FILE"
        _pma_log "Đã đổi URL thành công!"
        echo -e "${GREEN}URL mới: $(_pma_scheme)://$(_pma_public_ip)/${new_path}/${NC}"
    else
        # Vhost đã được hoàn tác -> trả thư mục về tên cũ cho khớp
        mv "/var/www/html/${new_path}" "/var/www/html/${cur}"
        _pma_err "Đổi URL thất bại - đã giữ nguyên đường dẫn cũ /${cur}/."
    fi
    pause
}

reset_phpmyadmin_auth() {
    echo -e "${YELLOW}--- Reset mật khẩu HTTP Auth ---${NC}"
    if ! command -v htpasswd &>/dev/null; then
        if [[ -f /etc/redhat-release ]]; then
            dnf install -y httpd-tools -q 2>/dev/null || true
        else
            apt-get install -y apache2-utils -qq 2>/dev/null || true
        fi
    fi

    read -s -p "Nhập mật khẩu mới (Để trống = sinh ngẫu nhiên): " new_pass
    echo ""
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
    VPS_IP=$(_pma_public_ip)

    if [[ -f "$PMA_NGINX_CONF" ]]; then
        echo -e "${CYAN}URL:${NC} $(_pma_scheme)://${VPS_IP}/$(_pma_path)/"
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

#!/bin/bash

# modules/lemp.sh - LEMP Stack Component Installers
# Cung cấp các hàm cài đặt thành phần (Nginx, PHP, MariaDB) dùng trong install.sh và các module khác.

install_nginx() {
    # Xử lý xung đột với OpenLiteSpeed
    if systemctl is-active --quiet lshttpd 2>/dev/null || systemctl is-enabled --quiet lshttpd 2>/dev/null; then
        echo -e "${YELLOW}CẢNH BÁO: Phát hiện OpenLiteSpeed đang hiển diện trên máy chủ!${NC}"
        echo -e "Việc cài đặt Nginx sẽ đâm đụng port 80/443. Hệ thống sẽ tự động TẮT và VÔ HIỆU HOÁ OpenLiteSpeed để nhường port cho Nginx."
        read -p "Tiếp tục cài đặt Nginx? [Y/n]: " c_nginx
        if [[ "${c_nginx,,}" == "n" ]]; then
            echo -e "${YELLOW}Đã huỷ cài đặt Nginx.${NC}"
            return
        fi
        systemctl stop lshttpd 2>/dev/null
        systemctl disable lshttpd 2>/dev/null
        log_info "Đã tắt OpenLiteSpeed."
    fi

    if is_installed nginx; then
        log_warn "Nginx is already installed."
    else
        log_info "Installing Nginx (Mainline - QUIC HTTP/3 Support)..."
        
        # Cấu hình Repo Mainline (Nginx 1.25.0+) để hỗ trợ QUIC HTTP/3
        if [[ "$OS_FAMILY" == "debian" ]]; then
            apt-get install -y curl gnupg2 ca-certificates lsb-release
            curl -fsSL https://nginx.org/keys/nginx_signing.key | gpg --dearmor -o /usr/share/keyrings/nginx-archive-keyring.gpg --yes
            
            local os_name_lower
            os_name_lower=$(cat /etc/os-release | grep -E '^ID=' | cut -d= -f2 | tr -d '"')
            
            echo "deb [signed-by=/usr/share/keyrings/nginx-archive-keyring.gpg] http://nginx.org/packages/mainline/${os_name_lower} $(lsb_release -cs) nginx" > /etc/apt/sources.list.d/nginx.list
            
            cat > /etc/apt/preferences.d/99nginx <<EOF
Package: *
Pin: origin nginx.org
Pin: release o=nginx
Pin-Priority: 900
EOF
            apt-get update
        elif [[ "$OS_FAMILY" == "rhel" ]]; then
            cat > /etc/yum.repos.d/nginx.repo <<EOF
[nginx-mainline]
name=nginx mainline repo
baseurl=http://nginx.org/packages/mainline/centos/\$releasever/\$basearch/
gpgcheck=1
enabled=1
gpgkey=https://nginx.org/keys/nginx_signing.key
module_hotfixes=true
EOF
        fi

        pkg_install nginx
        
        # Đảm bảo group và user www-data tồn tại trên RHEL/Oracle Linux để tương thích permissions
        if [[ "$OS_FAMILY" == "rhel" ]]; then
            groupadd -f www-data 2>/dev/null || true
            id -u www-data &>/dev/null || useradd -r -g www-data -s /sbin/nologin -d /var/www www-data 2>/dev/null || true
            usermod -aG www-data nginx 2>/dev/null || true
        fi

        # Đảm bảo tương thích cấu trúc thư mục sites-available/sites-enabled (Debian style)
        if [[ ! -d /etc/nginx/sites-available ]]; then
            mkdir -p /etc/nginx/sites-available /etc/nginx/sites-enabled
            if ! grep -q "sites-enabled" /etc/nginx/nginx.conf; then
                sed -i '/include \/etc\/nginx\/conf\.d\/\*\.conf;/a \    include \/etc\/nginx\/sites-enabled\/\*;' /etc/nginx/nginx.conf
            fi
        fi
        
        # Increase global upload limit right after install
        if [[ -f /etc/nginx/nginx.conf ]] && ! grep -q "client_max_body_size" /etc/nginx/nginx.conf; then
            sed -i '/http {/a \    client_max_body_size 128M;' /etc/nginx/nginx.conf
        fi
        
        # SELinux (RHEL/Oracle): cho nginx/php-fpm đọc-ghi /var/www và proxy tới app
        selinux_allow_web

        systemctl enable nginx
        if systemctl start nginx; then
            log_info "Nginx (Mainline) installed successfully."
        else
            log_error "Nginx đã cài nhưng KHÔNG khởi động được. Kiểm tra: nginx -t ; journalctl -u nginx -n 30"
        fi
    fi

    # Auto-harden nginx.conf sau khi cài (idempotent)
    _configure_nginx_global
}

# ==============================================================================
# Tự động cấu hình nginx.conf: Performance + Security (idempotent)
# ==============================================================================
_configure_nginx_global() {
    local nginx_conf="/etc/nginx/nginx.conf"
    [[ ! -f "$nginx_conf" ]] && return

    log_info "Đang tối ưu hóa nginx.conf (Performance + Security)..."

    # Backup để hoàn tác nếu nginx -t lỗi sau khi chỉnh
    local nginx_conf_bak="${nginx_conf}.bak_vpsm_$$"
    cp -p "$nginx_conf" "$nginx_conf_bak"

    # ── worker_processes auto ──────────────────────────────
    sed -i 's/^worker_processes.*/worker_processes auto;/' "$nginx_conf" 2>/dev/null || true

    # ── Thêm worker_rlimit_nofile & events nếu chưa có ────
    if ! grep -q "worker_rlimit_nofile" "$nginx_conf"; then
        sed -i '/^worker_processes/a worker_rlimit_nofile 65535;' "$nginx_conf" 2>/dev/null || true
    fi
    if grep -q "events {" "$nginx_conf" && ! grep -q "worker_connections" "$nginx_conf"; then
        sed -i '/events {/a \    worker_connections 4096;\n    multi_accept on;\n    use epoll;' "$nginx_conf" 2>/dev/null || true
    fi

    # ── Gzip toàn cầu ─────────────────────────────────────
    # nginx.conf của distro thường đã có "gzip on;" -> chèn thêm sẽ thành directive trùng lặp
    if ! grep -q "vps-manager-gzip" "$nginx_conf" && ! grep -qE "^[[:space:]]*gzip[[:space:]]+on;" "$nginx_conf"; then
        local gzip_block
        gzip_block='
    # vps-manager-gzip
    gzip on;
    gzip_vary on;
    gzip_proxied any;
    gzip_comp_level 6;
    gzip_types text/plain text/css text/xml application/json application/javascript application/rss+xml application/atom+xml image/svg+xml;'
        python3 -c "
import re, sys
content = open('$nginx_conf').read()
block = '''$gzip_block'''
# Insert inside http { block, after opening brace
content = re.sub(r'(http\s*\{)', r'\1\n' + block, content, count=1)
open('$nginx_conf', 'w').write(content)
" 2>/dev/null || sed -i "/http {/a \\$gzip_block" "$nginx_conf" 2>/dev/null || true
    fi

    # ── Security: hide server version & open_file_cache ───
    if ! grep -q "server_tokens" "$nginx_conf"; then
        sed -i '/http {/a \    server_tokens off;' "$nginx_conf" 2>/dev/null || true
    fi
    if ! grep -q "open_file_cache" "$nginx_conf"; then
        sed -i '/http {/a \    open_file_cache max=10000 inactive=30s;\n    open_file_cache_valid 60s;\n    open_file_cache_min_uses 2;\n    open_file_cache_errors on;' "$nginx_conf" 2>/dev/null || true
    fi

    # ── Security: Security Headers snippet ────────────────
    local sec_conf="/etc/nginx/snippets/security-headers.conf"
    mkdir -p /etc/nginx/snippets
    if [[ ! -f "$sec_conf" ]]; then
        cat > "$sec_conf" << 'SECEOF'
# VPS Manager - Security Headers (include trong server block)
add_header X-Content-Type-Options    "nosniff"       always;
add_header X-Frame-Options           "SAMEORIGIN"    always;
add_header X-XSS-Protection          "1; mode=block" always;
add_header Referrer-Policy           "strict-origin-when-cross-origin" always;
add_header Permissions-Policy        "camera=(), microphone=(), geolocation=()" always;
add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
SECEOF
        log_info "✓ Tạo security-headers.conf snippet"
    fi

    # ── WordPress Security Locations snippet ──────────────
    local wp_sec_conf="/etc/nginx/snippets/wp-security.conf"
    # Ghi lại khi file chưa có HOẶC còn là bản cũ (không có dấu rev2)
    if [[ ! -f "$wp_sec_conf" ]] || ! grep -q "wp-security-rev2" "$wp_sec_conf"; then
        cat > "$wp_sec_conf" << 'WPSEC'
# VPS Manager - WordPress Security Locations (wp-security-rev2)
# File này phải được include TRƯỚC "location ~ \.php$" trong server block thì các luật chặn PHP mới có tác dụng.
# Chặn truy cập các file nhạy cảm
location ~* /xmlrpc\.php$ {
    deny all;
    access_log off;
    log_not_found off;
}
location ~* /wp-config\.php { deny all; }
location ~* /\.git           { deny all; }
location ~* /\.env           { deny all; }
location ~* \.(bak|conf|dist|fla|inc|ini|log|sql|swp|tar|gz|zip)$ {
    deny all;
    access_log off;
    log_not_found off;
}
# Chặn PHP trong uploads/ (ngăn web shell)
location ~* /(?:uploads|files)/.*\.php$ { deny all; }
# Bảo vệ wp-includes (bộ luật chuẩn của WordPress: chặn gọi trực tiếp file PHP nội bộ,
# nhưng KHÔNG chặn wp-includes/js/tinymce/wp-tinymce.php mà trình soạn thảo cần)
location ~* ^/wp-admin/includes/ { deny all; }
location ~* ^/wp-includes/[^/]+\.php$ { deny all; }
location ~* ^/wp-includes/js/tinymce/langs/.+\.php$ { deny all; }
location ~* ^/wp-includes/theme-compat/ { deny all; }
WPSEC
        log_info "✓ Tạo wp-security.conf snippet"
    fi

    # ── FastCGI buffer toàn cục ────────────────────────────
    local fastcgi_conf="/etc/nginx/conf.d/fastcgi-buffer.conf"
    if [[ ! -f "$fastcgi_conf" ]]; then
        cat > "$fastcgi_conf" << 'FCEOF'
# VPS Manager - FastCGI buffer tuning
fastcgi_buffer_size          128k;
fastcgi_buffers              4 256k;
fastcgi_busy_buffers_size    256k;
fastcgi_temp_file_write_size 256k;
FCEOF
        log_info "✓ Tạo fastcgi-buffer.conf"
    fi

    # ── Kiểm tra & reload ─────────────────────────────────
    if nginx -t 2>/dev/null; then
        systemctl reload nginx 2>/dev/null || true
        rm -f "$nginx_conf_bak"
        log_info "✓ nginx.conf đã được tối ưu và reload thành công"
    else
        log_warn "⚠ nginx.conf có lỗi sau khi chỉnh - đã khôi phục bản trước đó:"
        nginx -t 2>&1 | tail -5
        mv -f "$nginx_conf_bak" "$nginx_conf"
    fi
}

install_mariadb() {
    if is_installed mariadb-server; then
        log_warn "MariaDB is already installed."
        _tune_mariadb_config
        return
    fi

    log_info "Cài đặt MariaDB..."
    pkg_install mariadb-server
    systemctl enable mariadb
    systemctl start mariadb

    # Tạo mật khẩu admin mạnh
    local db_admin_pass
    db_admin_pass=$(openssl rand -base64 32 | tr -dc 'a-zA-Z0-9' | head -c 32)

    # Bảo mật: Cấu hình user admin wpdbadmin và bảo vệ user root
    local db_client="mariadb"
    command -v mariadb &>/dev/null || db_client="mysql"
    if ! $db_client <<SQLEOF
FLUSH PRIVILEGES;
CREATE USER IF NOT EXISTS 'wpdbadmin'@'localhost' IDENTIFIED BY '${db_admin_pass}';
GRANT ALL PRIVILEGES ON *.* TO 'wpdbadmin'@'localhost' WITH GRANT OPTION;
ALTER USER 'root'@'localhost' IDENTIFIED BY '${db_admin_pass}';
DROP USER IF EXISTS ''@'localhost';
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';
FLUSH PRIVILEGES;
SQLEOF
    then
        # Không ghi ~/.my.cnf với mật khẩu CHƯA được đặt - nếu ghi, mọi lệnh mysql sau đó sẽ bị từ chối
        log_error "Không thiết lập được mật khẩu cho MariaDB. Root vẫn đăng nhập bằng unix_socket (không mật khẩu)."
        _tune_mariadb_config
        return 1
    fi

    # Ghi credentials cho cả root và wpdbadmin
    cat > /root/.my.cnf <<MYCNF
# Managed by VPS-Manager
[client]
host     = localhost
user     = root
password = ${db_admin_pass}

[mysql_upgrade]
host     = localhost
user     = root
password = ${db_admin_pass}
MYCNF
    chmod 600 /root/.my.cnf

    # Áp tuning config theo RAM (hàm này tự restart và tự hoàn tác nếu MariaDB không lên)
    _tune_mariadb_config

    log_info "MariaDB installed and secured! (User: wpdbadmin)"
}

# Ghi tuning vào 1 file drop-in riêng (không nối vào my.cnf), restart và hoàn tác nếu MariaDB không khởi động.
_tune_mariadb_config() {
    local conf_dir svc
    conf_dir=$(mariadb_conf_dir) || { log_warn "Không tìm thấy thư mục cấu hình MariaDB. Bỏ qua tuning."; return 0; }
    svc=$(mariadb_service_name)
    local tune_file="${conf_dir}/50-vps-manager.cnf"

    if [[ -f "$tune_file" ]]; then
        log_info "MariaDB đã được tối ưu từ trước ($tune_file)."; return 0
    fi
    # Bản cũ của script nối thẳng vào my.cnf - đã có thì không ghi thêm lần nữa
    if grep -qs "vps-manager-db-tuning" /etc/mysql/my.cnf /etc/my.cnf; then
        log_info "MariaDB đã được tối ưu từ trước (trong my.cnf)."; return 0
    fi

    local total_ram_mb
    total_ram_mb=$(free -m | awk '/^Mem:/{print $2}')
    [[ -z "$total_ram_mb" ]] && total_ram_mb=1024
    # InnoDB 25% RAM: phần còn lại dành cho PHP-FPM (~40%), object cache và hệ điều hành.
    local innodb_buffer=$(( total_ram_mb / 4 ))
    local db_table_size=$(( total_ram_mb / 128 ))
    local max_connections=$(( total_ram_mb / 50 ))

    [[ "$innodb_buffer" -lt 64 ]] && innodb_buffer=64
    [[ "$db_table_size" -lt 16 ]] && db_table_size=16
    [[ "$db_table_size" -gt 64 ]] && db_table_size=64
    [[ "$max_connections" -lt 30 ]] && max_connections=30
    [[ "$max_connections" -gt 150 ]] && max_connections=150

    # key_buffer_size chỉ phục vụ bảng MyISAM; WordPress dùng InnoDB nên giữ nhỏ cố định.
    # Query cache tắt hẳn: đã deprecated, gây tranh chấp khoá, và object cache (Valkey/Redis) làm tốt hơn.
    cat > "$tune_file" <<DBCONF
# vps-manager-db-tuning (tự tính theo RAM: ${total_ram_mb}MB)
[mysqld]
key_buffer_size         = 16M
table_open_cache        = 2000
innodb_buffer_pool_size = ${innodb_buffer}M
max_connections         = ${max_connections}
query_cache_type        = 0
query_cache_size        = 0
tmp_table_size          = ${db_table_size}M
max_heap_table_size     = ${db_table_size}M
thread_cache_size       = 32
max_allowed_packet      = 64M
wait_timeout            = 60
interactive_timeout     = 60
skip-log-bin
bind-address            = 127.0.0.1
innodb_flush_log_at_trx_commit = 2
innodb_flush_method     = O_DIRECT
innodb_file_per_table   = 1
DBCONF

    if systemctl restart "$svc" && systemctl is-active --quiet "$svc"; then
        log_info "MariaDB tuning: RAM=${total_ram_mb}MB, InnoDB=${innodb_buffer}M, MaxConn=${max_connections}"
    else
        log_error "MariaDB không khởi động được với cấu hình tuning - đang hoàn tác."
        rm -f "$tune_file"
        systemctl restart "$svc"
        return 1
    fi
}

# ==============================================================================
# Cài đặt Object Cache (L2) cho Nginx stack
# Kiến trúc 2 tầng: L1 Nginx FastCGI Cache + L2 Unix Socket Object Cache
# Tham khảo: research best practices 2025
# ==============================================================================

_install_object_cache_nginx() {
    # valkey | redis
    # - Valkey: mặc định. Mã nguồn mở (BSD), do Linux Foundation duy trì, tương thích hoàn toàn giao thức Redis,
    #   có sẵn trong kho Ubuntu 24.04+, Debian 13+, EPEL 9 và là bản thay thế Redis chính thức trên RHEL 10.
    # - Redis: dùng khi hệ điều hành chưa có gói Valkey (Ubuntu 22.04, Debian 12) - hàm này tự lùi về Redis.
    # - KeyDB đã bị loại: không có trong kho mặc định của Debian/Ubuntu/EPEL và dự án gần như ngừng phát hành.
    local cache_type="${1:-valkey}"
    if [[ "$cache_type" != "valkey" && "$cache_type" != "redis" ]]; then
        log_error "Loại object cache không hỗ trợ: '$cache_type' (chỉ valkey hoặc redis)."
        return 1
    fi

    log_info "═══════════════════════════════════════════════════"
    log_info "  Cài đặt Object Cache L2: ${cache_type} (Unix Socket)"
    log_info "  Mục đích: Giảm tải MariaDB 80%+, tăng tốc WP"
    log_info "═══════════════════════════════════════════════════"

    local service_name="$cache_type"
    local conf_file socket_path socket_dir

    case "$cache_type" in
        redis)
            conf_file="/etc/redis/redis.conf"
            socket_dir="/var/run/redis"
            socket_path="${socket_dir}/redis.sock"
            ;;
        valkey)
            conf_file="/etc/valkey/valkey.conf"
            socket_dir="/var/run/valkey"
            socket_path="${socket_dir}/valkey.sock"
            ;;
    esac

    # ── Cài đặt gói ──
    if [[ "$OS_FAMILY" == "debian" ]]; then
        case "$cache_type" in
            redis)   DEBIAN_FRONTEND=noninteractive apt-get install -y redis-server &>/dev/null ;;
            # Tên gói là valkey-server trên Debian/Ubuntu; "valkey" giữ lại cho kho nào đặt tên như vậy
            valkey)  DEBIAN_FRONTEND=noninteractive apt-get install -y valkey-server &>/dev/null || \
                     DEBIAN_FRONTEND=noninteractive apt-get install -y valkey &>/dev/null ;;
        esac
    else
        case "$cache_type" in
            redis)  dnf install -y redis &>/dev/null ;;
            valkey) dnf install -y valkey &>/dev/null ;;
        esac
    fi

    # Hệ điều hành chưa có gói Valkey -> tự lùi về Redis (cùng giao thức, cùng plugin WordPress)
    if [[ "$cache_type" == "valkey" && ! -f "$conf_file" ]]; then
        log_warn "Kho gói của hệ điều hành này chưa có Valkey. Chuyển sang cài Redis (tương thích hoàn toàn)."
        _install_object_cache_nginx redis
        return $?
    fi

    local service_candidate actual_service=""
    local service_candidates=()
    case "$cache_type" in
        redis) service_candidates=(redis-server redis) ;;
        valkey) service_candidates=(valkey-server valkey) ;;
    esac
    for service_candidate in "${service_candidates[@]}"; do
        if systemctl list-unit-files "${service_candidate}.service" 2>/dev/null | grep -q "^${service_candidate}\.service" || [[ -f "/lib/systemd/system/${service_candidate}.service" ]] || [[ -f "/etc/systemd/system/${service_candidate}.service" ]]; then
            actual_service="$service_candidate"
            break
        fi
    done
    [[ -n "$actual_service" ]] && service_name="$actual_service"

    # ── Tạo thư mục socket với quyền www-data group ─────
    # www-data cần đọc/ghi socket → socket_dir phải chown về group www-data
    mkdir -p "$socket_dir"
    # Xác định user owner của cache service
    local cache_user
    cache_user=$(id -nu "${cache_type}" 2>/dev/null || id -nu "redis" 2>/dev/null || echo "${cache_type}")
    # Dir: cache_user:www-data → cache service ghi, www-data (PHP-FPM) đọc
    chown "${cache_user}:www-data" "$socket_dir" 2>/dev/null || \
        chown "${cache_type}:www-data" "$socket_dir" 2>/dev/null || true
    chmod 750 "$socket_dir"

    # ── Cấu hình Unix Socket (tắt TCP, chỉ Unix) ──
    if [[ -f "$conf_file" ]]; then
        # Backup
        cp "$conf_file" "${conf_file}.bak.$(date +%s)" 2>/dev/null || true

        # Tắt TCP port → bảo mật, loại bỏ overhead
        sed -i 's/^port 6379/#port 6379/g'              "$conf_file"
        sed -i '/^# port /a port 0' "$conf_file" 2>/dev/null || true
        sed -i 's/^tcp-keepalive 300/tcp-keepalive 0/g' "$conf_file"
        # Tắt RDB compression/checksum không cần thiết (pure object cache)
        sed -i 's/rdbcompression yes/rdbcompression no/g' "$conf_file"
        sed -i 's/rdbchecksum yes/rdbchecksum no/g'       "$conf_file"

        # Thêm Unix Socket config nếu chưa có
        if ! grep -q "^unixsocket " "$conf_file"; then
            # Tính maxmemory: 10% RAM (không chiếm quá nhiều, để MariaDB và PHP-FPM)
            local total_ram_mb; total_ram_mb=$(free -m | awk '/^Mem:/{print $2}')
            local maxmem_mb=$(( total_ram_mb / 10 ))
            [[ "$maxmem_mb" -lt 64 ]]  && maxmem_mb=64
            [[ "$maxmem_mb" -gt 512 ]] && maxmem_mb=512

            cat >> "$conf_file" <<SOCKCONF

# ── vps-manager: Unix Socket config (Premium-grade) ──
port 0
unixsocket ${socket_path}
unixsocketperm 660
maxmemory ${maxmem_mb}mb
maxmemory-policy allkeys-lfu
save ""
appendonly no
tcp-keepalive 60
SOCKCONF
        fi

        # Fix quyền config file
        chown "${cache_type}:${cache_type}" "$conf_file" 2>/dev/null || \
            chown "redis:redis" "$conf_file" 2>/dev/null || true
        chmod 640 "$conf_file"
    else
        log_warn "Không tìm thấy file config ${conf_file}. Có thể gói chưa cài được."
        return 1
    fi

    # ── Systemd override: fix socket permissions sau mỗi lần start (kể cả reboot) ──
    # RuntimeDirectory bị systemd reset về default ownership mỗi lần start
    # → Dùng ExecStartPost để chown lại SAU khi service tạo socket
    for s_name in "${service_candidates[@]}"; do
        local override_dir="/etc/systemd/system/${s_name}.service.d"
        mkdir -p "$override_dir"
        cat > "${override_dir}/vps-socket-perms.conf" <<SYSOVERRIDE
[Service]
RuntimeDirectory=${cache_type}
RuntimeDirectoryMode=0755
# Fix socket permissions sau khi start để www-data (PHP-FPM) có thể kết nối
ExecStartPost=/bin/bash -c 'sleep 1; chown ${cache_type}:www-data ${socket_path} 2>/dev/null; chmod 660 ${socket_path} 2>/dev/null; chown ${cache_type}:www-data ${socket_dir} 2>/dev/null; chmod 750 ${socket_dir} 2>/dev/null; true'
SYSOVERRIDE
    done

    # ── Thêm www-data vào group của cache service TRƯỚC khi start ──
    # Phải làm TRƯỚC restart để process PHP-FPM mới kế thừa group membership
    local cache_group
    cache_group=$(getent group "${cache_type}" 2>/dev/null | cut -d: -f1 || \
                  getent group "redis"         2>/dev/null | cut -d: -f1 || \
                  echo "${cache_type}")
    if getent group "$cache_group" &>/dev/null; then
        usermod -aG "$cache_group" www-data 2>/dev/null || true
        log_info "✓ Đã thêm www-data vào group ${cache_group}"
    fi

    systemctl daemon-reload
    systemctl enable "${service_name}" 2>/dev/null || true
    systemctl restart "${service_name}" 2>/dev/null || true

    # Đợi socket khởi tạo (tối đa 5s)
    local waited=0
    while [[ ! -S "$socket_path" ]] && [[ $waited -lt 5 ]]; do
        sleep 1; waited=$((waited+1))
    done

    if ! systemctl is-active --quiet "${service_name}" || [[ ! -S "$socket_path" ]]; then
        log_error "${cache_type} KHÔNG khởi động được hoặc không tạo socket ${socket_path}."
        log_error "Kiểm tra: journalctl -u ${service_name} -n 30. Chưa ghi cấu hình cache cho các website."
        return 1
    fi

    # ── Fix quyền socket sau khi service tạo ra ──────────
    # socket owner: cache_user:www-data, mode 660 → PHP-FPM (www-data) đọc được
    if [[ -S "$socket_path" ]]; then
        chown "${cache_user:-${cache_type}}:www-data" "$socket_path" 2>/dev/null || true
        chmod 660 "$socket_path" 2>/dev/null || true
        log_info "✓ Socket permissions: ${cache_user}:www-data 660"
    fi

    # ── Cài PHP Redis extension, rồi restart PHP-FPM ──
    # Restart là BẮT BUỘC: process PHP-FPM cũ chưa có group của cache service và chưa nạp extension.
    log_info "Cài đặt PHP Redis extension..."
    if [[ "$OS_FAMILY" == "debian" ]]; then
        local ini phpver
        for ini in /etc/php/*/fpm/php.ini; do
            [[ -f "$ini" ]] || continue
            phpver=$(echo "$ini" | grep -oE '[0-9]+\.[0-9]+' | head -1)
            DEBIAN_FRONTEND=noninteractive apt-get install -y "php${phpver}-redis" &>/dev/null || \
                log_warn "Không cài được php${phpver}-redis"
            phpenmod -v "$phpver" redis 2>/dev/null || true
            php_fpm_restart_safe "$phpver" && log_info "✓ PHP ${phpver}: redis extension đã bật, FPM đã restart"
        done
    else
        # RHEL/Oracle (Remi module stream): 1 phiên bản PHP, gói extension là php-pecl-redis*
        dnf install -y php-pecl-redis6 &>/dev/null || dnf install -y php-pecl-redis5 &>/dev/null || \
            dnf install -y php-pecl-redis &>/dev/null || dnf install -y php-redis &>/dev/null || \
            log_warn "Không cài được PHP redis extension (php-pecl-redis)."
        php_fpm_restart_safe && log_info "✓ PHP redis extension đã cài, php-fpm đã restart"
    fi

    # ── Verify socket hoạt động ──
    if [[ -S "$socket_path" ]]; then
        log_info "✓ ${cache_type} Unix Socket đang hoạt động: ${socket_path}"
    else
        log_warn "⚠ Socket ${socket_path} chưa tồn tại. Kiểm tra: systemctl status ${service_name}"
    fi

    # ── In hướng dẫn wp-config.php ──
    echo ""
    echo -e "${GREEN}═══════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}  ✓ ${cache_type} đã cài thành công với Unix Socket!${NC}"
    echo -e "${YELLOW}  Thêm vào wp-config.php của mỗi WordPress site:${NC}"
    echo ""
    echo "  define('WP_REDIS_SCHEME', 'unix');"
    echo "  define('WP_REDIS_PATH',   '${socket_path}');"
    echo "  define('WP_CACHE_KEY_SALT', 'tensite:');  // Mỗi site 1 salt khác nhau"
    echo ""
    echo -e "${CYAN}  Plugin đề xuất: Redis Cache by Till Krüss${NC}"
    echo -e "${CYAN}  (Tương thích với Redis, Valkey, KeyDB)${NC}"
    echo -e "${GREEN}═══════════════════════════════════════════════════════${NC}"
    echo ""

    # Lưu socket path để các module khác dùng
    mkdir -p /etc/vps-manager
    echo "OBJECT_CACHE_TYPE=${cache_type}" > /etc/vps-manager/cache.conf
    echo "OBJECT_CACHE_SOCKET=${socket_path}" >> /etc/vps-manager/cache.conf
    chmod 600 /etc/vps-manager/cache.conf
}

install_php() {
    if [[ "$OS_FAMILY" == "rhel" ]]; then
        log_info "Adding PHP repository (Remi/EPEL)..."
        dnf config-manager --enable ol9_codeready_builder ol9_developer_EPEL 2>/dev/null || true
        dnf config-manager --set-enabled crb 2>/dev/null || true
        pkg_install epel-release dnf-utils >/dev/null 2>&1
        dnf install -y https://rpms.remirepo.net/enterprise/remi-release-9.rpm >/dev/null 2>&1
        dnf module reset php -y >/dev/null 2>&1
    else
        log_info "Adding PHP repository (ondrej/php)..."
        rm -f /etc/apt/sources.list.d/*ondrej*php* 2>/dev/null || true

        pkg_install software-properties-common curl gnupg2 ca-certificates lsb-release > /dev/null 2>&1

        local codename
        codename=$(lsb_release -cs 2>/dev/null || echo "noble")

        local ppa_check
        ppa_check=$(curl -s -o /dev/null -w "%{http_code}" \
            "https://ppa.launchpadcontent.net/ondrej/php/ubuntu/dists/${codename}/Release" \
            --max-time 5)

        if [[ "$ppa_check" == "200" ]]; then
            # add-apt-repository tự lấy khoá ký của PPA từ Launchpad -> gói PHP được kiểm tra chữ ký.
            # KHÔNG dùng [trusted=yes]: tuỳ chọn đó tắt hẳn việc kiểm tra chữ ký gói.
            if add-apt-repository -y ppa:ondrej/php > /dev/null 2>&1; then
                pkg_update > /dev/null 2>&1
            else
                log_warn "Không thêm được PPA ondrej/php (có chữ ký). Sử dụng PHP gốc của hệ điều hành..."
            fi
        else
            log_warn "PPA ondrej/php không hỗ trợ '${codename}'. Sử dụng PHP gốc của Ubuntu..."
        fi
    fi

    local primary_ver="8.4"
    
    if [[ -n "$1" ]]; then
        primary_ver="$1"
    else
        echo -e "${YELLOW}Cài đặt PHP (Mặc định: PHP 8.4)${NC}"
    fi

    _install_single_php "$primary_ver"

    # Chỉ hỏi cài thêm nếu không điền tham số (khi chạy menu tương tác)
    if [[ -z "$1" ]]; then
        echo ""
        read -p "Bạn có muốn cài thêm phiên bản PHP phụ không? [y/N]: " install_more
        if [[ "$OS_FAMILY" == "rhel" ]] && [[ "$install_more" == "y" || "$install_more" == "Y" ]]; then
            log_warn "Trên RHEL/Oracle Linux (Remi module stream) chỉ chạy được MỘT phiên bản PHP. Bỏ qua cài PHP phụ."
        elif [[ "$install_more" == "y" || "$install_more" == "Y" ]]; then
            echo -e "Chọn phiên bản PHP muốn cài thêm:"
            echo -e "1. PHP 8.1"
            echo -e "2. PHP 8.2"
            echo -e "3. PHP 8.4"
            echo -e "0. Bỏ qua"
            read -p "Chọn [0-3]: " extra_choice
            case $extra_choice in
                1) _install_single_php "8.1" ;;
                2) _install_single_php "8.2" ;;
                3) _install_single_php "8.4" ;;
                *) echo "Đã bỏ qua cài thêm PHP phụ." ;;
            esac
        fi
    fi
}

_install_single_php() {
    local ver=$1
    log_info "Installing PHP $ver..."
    # Ngân sách tiến trình PHP-FPM cho pool mặc định (~40% RAM, 64MB/tiến trình, xem core/platform_helpers.sh)
    local calc_children
    calc_children=$(php_fpm_children_budget)
    local spare_start=$(( calc_children / 4 )); [[ "$spare_start" -lt 2 ]] && spare_start=2
    local spare_min=$(( calc_children / 6 ));  [[ "$spare_min" -lt 1 ]] && spare_min=1
    local spare_max=$(( calc_children / 2 ));  [[ "$spare_max" -lt "$spare_start" ]] && spare_max=$spare_start

    if [[ "$OS_FAMILY" == "rhel" ]]; then
        # Module stream chỉ cho phép 1 phiên bản PHP: phải reset trước khi enable stream khác
        local cur_ver=""
        command -v php &>/dev/null && cur_ver=$(php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;' 2>/dev/null)
        if [[ -n "$cur_ver" && "$cur_ver" != "$ver" ]]; then
            log_error "Server đang chạy PHP $cur_ver. RHEL/Oracle Linux chỉ hỗ trợ 1 phiên bản PHP (module stream)."
            log_error "Muốn đổi sang PHP $ver: dnf module reset php -y && dnf module enable php:remi-$ver -y && dnf distro-sync 'php*'"
            return 1
        fi
        if ! dnf module enable "php:remi-$ver" -y >/dev/null 2>&1; then
            log_error "Không enable được module php:remi-$ver. Kiểm tra repo Remi: dnf module list php"
            return 1
        fi
        if ! pkg_install php-fpm php-mysqlnd php-common php-cli \
            php-curl php-xml php-mbstring php-zip php-bcmath \
            php-intl php-gd php-pecl-imagick; then
            log_error "Cài đặt PHP $ver THẤT BẠI."
            return 1
        fi

        local php_ini="/etc/php.ini"
        if [[ -f "$php_ini" ]]; then
            sed -i -E "s/^[; ]*upload_max_filesize.*/upload_max_filesize = 128M/" "$php_ini"
            sed -i -E "s/^[; ]*post_max_size.*/post_max_size = 128M/" "$php_ini"
            sed -i -E "s/^[; ]*memory_limit.*/memory_limit = 256M/" "$php_ini"
            sed -i -E "s/^[; ]*max_execution_time.*/max_execution_time = 300/" "$php_ini"
            sed -i -E "s/^[; ]*max_input_vars.*/max_input_vars = 3000/" "$php_ini"
        fi

        local pool_conf="/etc/php-fpm.d/www.conf"
        # PHP chạy bằng www-data - CÙNG user sở hữu /var/www - để WordPress upload/cập nhật được.
        # nginx (đã ở trong group www-data, xem install_nginx) kết nối socket qua quyền group 0660.
        groupadd -f www-data 2>/dev/null || true
        id -u www-data &>/dev/null || useradd -r -g www-data -s /sbin/nologin -d /var/www www-data 2>/dev/null || true
        if id -u nginx &>/dev/null && ! id -nG nginx | grep -qw www-data; then
            usermod -aG www-data nginx 2>/dev/null || true
            systemctl is-active --quiet nginx && systemctl restart nginx   # worker phải khởi động lại mới nhận group mới
        fi
        if [[ -f "$pool_conf" ]]; then
            sed -i -E 's/^[; ]*user = .*/user = www-data/' "$pool_conf"
            sed -i -E 's/^[; ]*group = .*/group = www-data/' "$pool_conf"
            sed -i -E 's/^[; ]*listen\.owner = .*/listen.owner = www-data/' "$pool_conf"
            sed -i -E 's/^[; ]*listen\.group = .*/listen.group = www-data/' "$pool_conf"
            sed -i -E 's/^[; ]*listen\.mode = .*/listen.mode = 0660/' "$pool_conf"
            # listen.acl_users/acl_groups (mặc định của RHEL) ghi đè owner/group/mode -> phải tắt
            sed -i -E 's/^(listen\.acl_(users|groups)[[:space:]]*=.*)/;\1/' "$pool_conf"
            sed -i -E "s/^[; ]*pm\.max_children.*/pm.max_children = $calc_children/" "$pool_conf"
            sed -i -E "s/^[; ]*pm\.start_servers.*/pm.start_servers = $spare_start/" "$pool_conf"
            sed -i -E "s/^[; ]*pm\.min_spare_servers.*/pm.min_spare_servers = $spare_min/" "$pool_conf"
            sed -i -E "s/^[; ]*pm\.max_spare_servers.*/pm.max_spare_servers = $spare_max/" "$pool_conf"
            sed -i -E "s/^[; ]*pm\.max_requests.*/pm.max_requests = 1000/" "$pool_conf"
        fi
        # Thư mục session/opcache của gói RHEL thuộc group apache -> chuyển cho www-data
        local d
        for d in /var/lib/php/session /var/lib/php/wsdlcache /var/lib/php/opcache; do
            [[ -d "$d" ]] && chown root:www-data "$d" && chmod 770 "$d"
        done
        selinux_allow_web

        systemctl enable php-fpm >/dev/null 2>&1
        if ! php_fpm_restart_safe "$ver"; then
            log_error "PHP-FPM không khởi động được sau khi cấu hình."
            return 1
        fi
    else
        pkg_install php$ver php$ver-fpm php$ver-mysql php$ver-common php$ver-cli \
            php$ver-curl php$ver-xml php$ver-mbstring php$ver-zip php$ver-bcmath \
            php$ver-intl php$ver-gd php$ver-imagick 2>/dev/null || \
        pkg_install php-fpm php-mysql php-common php-cli \
            php-curl php-xml php-mbstring php-zip php-bcmath \
            php-intl php-gd php-imagick

        local actual_ver="$ver"
        if [[ ! -d "/etc/php/$ver" ]]; then
            actual_ver=$(ls -d /etc/php/* 2>/dev/null | grep -oE '[0-9]+\.[0-9]+' | head -n 1)
        fi
        [ -z "$actual_ver" ] && actual_ver="$ver"

        # Configure PHP Upload Limits & Socket Permissions
        local php_ini="/etc/php/$actual_ver/fpm/php.ini"
        if [[ -f "$php_ini" ]]; then
            sed -i -E "s/^[; ]*upload_max_filesize.*/upload_max_filesize = 128M/" "$php_ini"
            sed -i -E "s/^[; ]*post_max_size.*/post_max_size = 128M/" "$php_ini"
            sed -i -E "s/^[; ]*memory_limit.*/memory_limit = 256M/" "$php_ini"
            sed -i -E "s/^[; ]*max_execution_time.*/max_execution_time = 300/" "$php_ini"
            sed -i -E "s/^[; ]*max_input_vars.*/max_input_vars = 3000/" "$php_ini"
        fi

        # Fix 502 Bad Gateway & Auto-tune PHP-FPM pool for 524 Timeout prevention
        # nginx worker (user "nginx" của gói nginx.org) phải thuộc group www-data để mở socket 0660.
        # Worker chỉ nhận group mới sau khi restart -> restart nginx nếu vừa thêm group.
        if id -u nginx &>/dev/null && ! id -nG nginx | grep -qw www-data; then
            usermod -aG www-data nginx 2>/dev/null || true
            systemctl is-active --quiet nginx && systemctl restart nginx
        fi
        chmod 755 /run/php 2>/dev/null || true

        local pool_conf="/etc/php/$actual_ver/fpm/pool.d/www.conf"
        if [[ -f "$pool_conf" ]]; then
            # 0660 (không phải 0666): chỉ www-data và group www-data (có nginx) được gọi PHP qua socket
            sed -i -E "s/^[; ]*listen\.owner.*/listen.owner = www-data/" "$pool_conf"
            sed -i -E "s/^[; ]*listen\.group.*/listen.group = www-data/" "$pool_conf"
            sed -i -E "s/^[; ]*listen\.mode.*/listen.mode = 0660/" "$pool_conf"
            sed -i -E "s/^[; ]*pm\.max_children.*/pm.max_children = $calc_children/" "$pool_conf"
            sed -i -E "s/^[; ]*pm\.start_servers.*/pm.start_servers = $spare_start/" "$pool_conf"
            sed -i -E "s/^[; ]*pm\.min_spare_servers.*/pm.min_spare_servers = $spare_min/" "$pool_conf"
            sed -i -E "s/^[; ]*pm\.max_spare_servers.*/pm.max_spare_servers = $spare_max/" "$pool_conf"
            sed -i -E "s/^[; ]*pm\.max_requests.*/pm.max_requests = 1000/" "$pool_conf"
        fi

        systemctl enable php$actual_ver-fpm >/dev/null 2>&1 || systemctl enable php-fpm >/dev/null 2>&1
        if ! php_fpm_restart_safe "$actual_ver"; then
            log_error "PHP-FPM $actual_ver không khởi động được sau khi cấu hình."
            return 1
        fi

        # Verify & auto-fix DOM/XML symlinks cho cả FPM và CLI
        _fix_php_ext_symlinks "$actual_ver"
    fi

    log_info "PHP $ver installed successfully."
}

# Fix symlinks cho các PHP extension quan trọng (dom, xml, mbstring, ...)
# Đảm bảo cả CLI và FPM đều load đúng extension
_fix_php_ext_symlinks() {
    local ver=$1
    local mods_dir="/etc/php/$ver/mods-available"
    local fixed=0

    if [[ ! -d "$mods_dir" ]]; then
        log_warn "PHP $ver mods-available không tồn tại, bỏ qua."
        return
    fi

    # Danh sách extension quan trọng cần đảm bảo có trong cả CLI & FPM
    local critical_exts=("dom" "xml" "simplexml" "xmlreader" "xmlwriter" "mbstring" "curl")

    for ext in "${critical_exts[@]}"; do
        local ini_file="$mods_dir/${ext}.ini"
        [[ ! -f "$ini_file" ]] && continue  # Extension chưa được cài, bỏ qua

        for sapi in cli fpm; do
            local conf_dir="/etc/php/$ver/$sapi/conf.d"
            [[ ! -d "$conf_dir" ]] && continue

            # Tìm symlink hiện có (ví dụ: 20-dom.ini)
            local symlink
            symlink=$(find "$conf_dir" -name "*-${ext}.ini" 2>/dev/null | head -1)

            if [[ -z "$symlink" ]]; then
                # Symlink bị thiếu → tạo mới với priority 20
                ln -s "$ini_file" "$conf_dir/20-${ext}.ini" 2>/dev/null
                log_info "  [PHP $ver $sapi] Đã tạo symlink: 20-${ext}.ini"
                fixed=$((fixed + 1))
            fi
        done
    done

    if [[ $fixed -gt 0 ]]; then
        # Restart FPM để apply thay đổi
        systemctl restart php$ver-fpm >/dev/null 2>&1 && \
            log_info "PHP $ver FPM restarted để apply extension mới."
    fi
}

# Fix tất cả PHP versions đã cài trên server
fix_php_extensions() {
    echo -e "${BLUE}=================================================${NC}"
    echo -e "${GREEN}   Fix PHP Extensions (DOM/XML/MBSTRING/CLI symlinks)${NC}"
    echo -e "${BLUE}=================================================${NC}"
    echo -e "Đang kiểm tra tất cả PHP versions..."
    echo ""

    if [[ ! -d /etc/php ]]; then
        log_warn "Không tìm thấy /etc/php. PHP chưa được cài?"
        return
    fi

    local versions=()
    for ver_dir in /etc/php/*/; do
        local ver
        ver=$(basename "$ver_dir")
        versions+=("$ver")
    done

    if [[ ${#versions[@]} -eq 0 ]]; then
        log_warn "Không tìm thấy PHP version nào."
        return
    fi

    echo -e "Tìm thấy ${#versions[@]} PHP version(s): ${versions[*]}"
    echo ""

    for ver in "${versions[@]}"; do
        echo -e "${YELLOW}--- PHP $ver ---${NC}"

        # Kiểm tra php-xml đã cài chưa, nếu chưa thì cài
        if [[ ! -f "/etc/php/$ver/mods-available/dom.ini" ]]; then
            log_info "PHP $ver: php${ver}-xml chưa được cài. Đang cài..."
            pkg_install php${ver}-xml >/dev/null 2>&1 && \
                log_info "PHP $ver: Đã cài php${ver}-xml thành công." || \
                log_warn "PHP $ver: Không thể cài php${ver}-xml (version không hỗ trợ?)"
        else
            echo -e "  ${GREEN}✓${NC} php${ver}-xml đã được cài."
        fi

        # Kiểm tra php-mbstring đã cài chưa, nếu chưa thì cài
        if [[ ! -f "/etc/php/$ver/mods-available/mbstring.ini" ]]; then
            log_info "PHP $ver: php${ver}-mbstring chưa được cài. Đang cài..."
            pkg_install php${ver}-mbstring >/dev/null 2>&1 && \
                log_info "PHP $ver: Đã cài php${ver}-mbstring thành công." || \
                log_warn "PHP $ver: Không thể cài php${ver}-mbstring (version không hỗ trợ?)"
        else
            echo -e "  ${GREEN}✓${NC} php${ver}-mbstring đã được cài."
        fi

        # Fix symlinks
        _fix_php_ext_symlinks "$ver"

        # Verify kết quả
        local cli_dom
        cli_dom=$(php$ver -m 2>/dev/null | grep -c "^dom$" || true)
        if [[ "$cli_dom" -ge 1 ]]; then
            echo -e "  ${GREEN}✓${NC} PHP $ver CLI: dom extension OK"
        else
            echo -e "  ${RED}✗${NC} PHP $ver CLI: dom extension vẫn thiếu!"
        fi

        local cli_mbstring
        cli_mbstring=$(php$ver -m 2>/dev/null | grep -c "^mbstring$" || true)
        if [[ "$cli_mbstring" -ge 1 ]]; then
            echo -e "  ${GREEN}✓${NC} PHP $ver CLI: mbstring extension OK"
        else
            echo -e "  ${RED}✗${NC} PHP $ver CLI: mbstring extension vẫn thiếu!"
        fi
    done

    echo ""
    echo -e "${GREEN}Hoàn tất kiểm tra và fix PHP extensions!${NC}"
}

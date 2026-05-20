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
        
        systemctl enable nginx
        systemctl start nginx
        log_info "Nginx (Mainline) installed successfully."
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
    if ! grep -q "vps-manager-gzip" "$nginx_conf"; then
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

    # ── Security: hide server version ─────────────────────
    if ! grep -q "server_tokens" "$nginx_conf"; then
        sed -i '/http {/a \    server_tokens off;' "$nginx_conf" 2>/dev/null || true
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
    if [[ ! -f "$wp_sec_conf" ]]; then
        cat > "$wp_sec_conf" << 'WPSEC'
# VPS Manager - WordPress Security Locations
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
# Bảo vệ wp-includes
location ~* /wp-includes/.*\.php$ {
    deny all;
    allow /wp-includes/ms-files.php;
}
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
        log_info "✓ nginx.conf đã được tối ưu và reload thành công"
    else
        log_warn "⚠ nginx.conf có lỗi sau khi chỉnh. Kiểm tra: nginx -t"
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

    # Bảo mật: đổi tên user root -> wpdbadmin
    # Hacker brute-force khó đoán tên user hơn
    mariadb <<SQLEOF 2>/dev/null || mysql <<SQLEOF2 2>/dev/null
use mysql;
FLUSH PRIVILEGES;
CREATE USER IF NOT EXISTS 'wpdbadmin'@'localhost' IDENTIFIED BY '${db_admin_pass}';
GRANT ALL PRIVILEGES ON *.* TO 'wpdbadmin'@'localhost' WITH GRANT OPTION;
DROP USER IF EXISTS 'root'@'localhost';
DROP USER IF EXISTS ''@'localhost';
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db='test' OR Db='test_%';
FLUSH PRIVILEGES;
SQLEOF
use mysql;
ALTER USER 'root'@'localhost' IDENTIFIED BY '${db_admin_pass}';
DELETE FROM mysql.user WHERE User='';
DROP DATABASE IF EXISTS test;
FLUSH PRIVILEGES;
SQLEOF2

    # Ghi credentials
    cat > /root/.my.cnf <<MYCNF
# Managed by VPS-Manager
[client]
host     = localhost
user     = wpdbadmin
password = ${db_admin_pass}

[mysql_upgrade]
host     = localhost
user     = wpdbadmin
password = ${db_admin_pass}
MYCNF
    chmod 600 /root/.my.cnf

    # Áp tuning config theo RAM
    _tune_mariadb_config
    systemctl restart mariadb

    log_info "MariaDB installed and secured! (User: wpdbadmin)"
}

_tune_mariadb_config() {
    local mycnf="/etc/mysql/my.cnf"
    [[ ! -f "$mycnf" ]] && mycnf="/etc/my.cnf"
    [[ ! -f "$mycnf" ]] && { log_warn "Không tìm thấy my.cnf. Bỏ qua tuning."; return; }

    if grep -q "vps-manager-db-tuning" "$mycnf" 2>/dev/null; then
        log_info "MariaDB đã được tối ưu từ trước."; return 0
    fi

    local total_ram_mb cpu_cores
    total_ram_mb=$(free -m | awk '/^Mem:/{print $2}')
    cpu_cores=$(grep -c ^processor /proc/cpuinfo 2>/dev/null || echo 2)
    local innodb_buffer=$(( total_ram_mb / 4 ))
    local key_buffer=$(( total_ram_mb / 8 ))
    local db_table_size=$(( total_ram_mb / 128 ))
    local max_connections=$(( total_ram_mb / 50 ))

    # Tuning bảo thủ cho VPS nhỏ để tránh OOM khi PHP-FPM tăng tải.
    [[ "$innodb_buffer" -lt 48 ]] && innodb_buffer=48
    [[ "$key_buffer" -lt 16 ]] && key_buffer=16
    [[ "$db_table_size" -lt 16 ]] && db_table_size=16
    [[ "$db_table_size" -gt 64 ]] && db_table_size=64
    [[ "$max_connections" -lt 30 ]] && max_connections=30
    [[ "$max_connections" -gt 150 ]] && max_connections=150

    # Query cache: tắt nếu > 2 CPU (MariaDB 10.8+ đã deprecated)
    local query_cache_conf="query_cache_type = 0
query_cache_size = 0"
    if [[ "$cpu_cores" -le 2 ]]; then
        query_cache_conf="query_cache_type = 1
query_cache_limit = 2M
query_cache_min_res_unit = 2k
query_cache_size = 50M"
    fi

    cat >> "$mycnf" <<DBCONF

# vps-manager-db-tuning (Premium-grade, RAM-auto-scaled)
[mysqld]
key_buffer_size         = ${key_buffer}M
table_cache             = 2000
innodb_buffer_pool_size = ${innodb_buffer}M
max_connections         = ${max_connections}
${query_cache_conf}
tmp_table_size          = ${db_table_size}M
max_heap_table_size     = ${db_table_size}M
thread_cache_size       = 81
max_allowed_packet      = 64M
wait_timeout            = 60
interactive_timeout     = 60
skip-log-bin
skip-networking
DBCONF

    log_info "MariaDB tuning: RAM=${total_ram_mb}MB, InnoDB=${innodb_buffer}M, MaxConn=${max_connections}"
}

# ==============================================================================
# Cài đặt Object Cache (L2) cho Nginx stack
# Kiến trúc 2 tầng: L1 Nginx FastCGI Cache + L2 Unix Socket Object Cache
# Tham khảo: research best practices 2025
# ==============================================================================

_install_object_cache_nginx() {
    local cache_type="${1:-valkey}"  # valkey | redis | keydb

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
        keydb)
            conf_file="/etc/keydb/keydb.conf"
            socket_dir="/var/run/keydb"
            socket_path="${socket_dir}/keydb.sock"
            ;;
    esac

    # ── Cài đặt gói ──
    if [[ "$OS_FAMILY" == "debian" ]]; then
        case "$cache_type" in
            redis)   DEBIAN_FRONTEND=noninteractive apt-get install -y redis-server &>/dev/null ;;
            valkey)  DEBIAN_FRONTEND=noninteractive apt-get install -y valkey &>/dev/null ;;
            keydb)   DEBIAN_FRONTEND=noninteractive apt-get install -y keydb &>/dev/null ;;
        esac
    else
        case "$cache_type" in
            redis)  dnf install -y redis &>/dev/null ;;
            valkey) dnf install -y valkey &>/dev/null ;;
            keydb)  dnf install -y keydb &>/dev/null ;;
        esac
    fi

    local service_candidate actual_service=""
    local service_candidates=()
    case "$cache_type" in
        redis) service_candidates=(redis-server redis) ;;
        valkey) service_candidates=(valkey-server valkey) ;;
        keydb) service_candidates=(keydb-server keydb) ;;
    esac
    for service_candidate in "${service_candidates[@]}"; do
        if systemctl list-unit-files "${service_candidate}.service" 2>/dev/null | grep -q "^${service_candidate}\.service" || [[ -f "/lib/systemd/system/${service_candidate}.service" ]] || [[ -f "/etc/systemd/system/${service_candidate}.service" ]]; then
            actual_service="$service_candidate"
            break
        fi
    done
    [[ -n "$actual_service" ]] && service_name="$actual_service"

    # ── Tạo thư mục socket ──
    mkdir -p "$socket_dir"
    chown "${cache_type}:${cache_type}" "$socket_dir" 2>/dev/null || \
        chown "redis:redis" "$socket_dir" 2>/dev/null || true
    chmod 755 "$socket_dir"

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
unixsocketperm 777
maxmemory ${maxmem_mb}mb
maxmemory-policy allkeys-lfu
save ""
appendonly no
activedefrag yes
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

    # ── Systemd override: đảm bảo socket dir tồn tại trước khi service start ──
    for s_name in "${service_candidates[@]}"; do
        local override_dir="/etc/systemd/system/${s_name}.service.d"
        mkdir -p "$override_dir"
        cat > "${override_dir}/socket-dir.conf" <<SYSOVERRIDE
[Service]
RuntimeDirectory=${cache_type}
RuntimeDirectoryMode=0755
SYSOVERRIDE
    done

    systemctl daemon-reload
    systemctl enable "${service_name}" 2>/dev/null || true
    systemctl restart "${service_name}" 2>/dev/null || true
    
    # Đợi 2s để socket kịp khởi tạo trước khi WordPress setup gọi tới
    sleep 2

    sleep 1

    # ── Thêm www-data vào group của cache service ──
    # Đây là bước quan trọng nhất khi dùng Unix Socket với PHP-FPM
    local cache_group="${service_name}"
    if getent group "$cache_group" &>/dev/null; then
        usermod -aG "$cache_group" www-data 2>/dev/null || true
        log_info "✓ Đã thêm www-data vào group ${cache_group}"
    fi
    # Đảm bảo socket có thể truy cập
    chmod 770 "$socket_path" 2>/dev/null || true

    # ── Cài PHP Redis extension ──
    log_info "Cài đặt PHP Redis extension..."
    if [[ "$OS_FAMILY" == "debian" ]]; then
        for phpver in 8.3 8.2 8.1 8.4; do
            if [[ -f "/etc/php/${phpver}/fpm/php.ini" ]]; then
                DEBIAN_FRONTEND=noninteractive apt-get install -y "php${phpver}-redis" &>/dev/null || true
                phpenmod -v "$phpver" redis 2>/dev/null || true
                systemctl restart "php${phpver}-fpm" 2>/dev/null || true
                log_info "✓ PHP ${phpver}-redis extension đã bật"
            fi
        done
    else
        for phpver in 83 82 81; do
            dnf install -y "php${phpver}-php-redis" &>/dev/null || \
            dnf install -y "php-redis" &>/dev/null || true
        done
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
    echo "  define('WP_REDIS_DATABASE', 0);  // Tăng số này cho mỗi site"
    echo "  define('WP_CACHE_KEY_SALT', 'tensite:');"
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
        pkg_install epel-release dnf-utils >/dev/null 2>&1
        dnf install -y https://rpms.remirepo.net/enterprise/remi-release-9.rpm >/dev/null 2>&1
        dnf module reset php -y >/dev/null 2>&1
    else
        log_info "Adding PHP repository (ondrej/php)..."
        pkg_install software-properties-common >/dev/null 2>&1
        add-apt-repository -y ppa:ondrej/php >/dev/null 2>&1
        pkg_update >/dev/null 2>&1
    fi

    local primary_ver="8.3"
    
    if [[ -n "$1" ]]; then
        primary_ver="$1"
    else
        echo -e "${YELLOW}Cài đặt PHP (Mặc định: PHP 8.3)${NC}"
    fi

    _install_single_php "$primary_ver"

    # Chỉ hỏi cài thêm nếu không điền tham số (khi chạy menu tương tác)
    if [[ -z "$1" ]]; then
        echo ""
        read -p "Bạn có muốn cài thêm phiên bản PHP phụ không? [y/N]: " install_more
        if [[ "$install_more" == "y" || "$install_more" == "Y" ]]; then
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
    if [[ "$OS_FAMILY" == "rhel" ]]; then
        dnf module enable php:remi-$ver -y >/dev/null 2>&1
        pkg_install php-fpm php-mysqlnd php-common php-cli \
            php-curl php-xml php-mbstring php-zip php-bcmath \
            php-intl php-gd php-pecl-imagick

        local php_ini="/etc/php.ini"
        if [[ -f "$php_ini" ]]; then
            sed -i -E "s/^[; ]*upload_max_filesize.*/upload_max_filesize = 128M/" "$php_ini"
            sed -i -E "s/^[; ]*post_max_size.*/post_max_size = 128M/" "$php_ini"
            sed -i -E "s/^[; ]*memory_limit.*/memory_limit = 256M/" "$php_ini"
            sed -i -E "s/^[; ]*max_execution_time.*/max_execution_time = 300/" "$php_ini"
            sed -i -E "s/^[; ]*max_input_vars.*/max_input_vars = 3000/" "$php_ini"
        fi

        local pool_conf="/etc/php-fpm.d/www.conf"
        if [[ -f "$pool_conf" ]]; then
            sed -i 's/^user = apache/user = nginx/' "$pool_conf"
            sed -i 's/^group = apache/group = nginx/' "$pool_conf"
            sed -i 's/^listen.owner = nobody/listen.owner = nginx/' "$pool_conf"
            sed -i 's/^listen.group = nobody/listen.group = nginx/' "$pool_conf"
        fi

        systemctl enable php-fpm >/dev/null 2>&1
        systemctl start php-fpm >/dev/null 2>&1
    else
        pkg_install php$ver php$ver-fpm php$ver-mysql php$ver-common php$ver-cli \
            php$ver-curl php$ver-xml php$ver-mbstring php$ver-zip php$ver-bcmath \
            php$ver-intl php$ver-gd php$ver-imagick

        # Configure PHP Upload Limits
        local php_ini="/etc/php/$ver/fpm/php.ini"
        if [[ -f "$php_ini" ]]; then
            sed -i -E "s/^[; ]*upload_max_filesize.*/upload_max_filesize = 128M/" "$php_ini"
            sed -i -E "s/^[; ]*post_max_size.*/post_max_size = 128M/" "$php_ini"
            sed -i -E "s/^[; ]*memory_limit.*/memory_limit = 256M/" "$php_ini"
            sed -i -E "s/^[; ]*max_execution_time.*/max_execution_time = 300/" "$php_ini"
            sed -i -E "s/^[; ]*max_input_vars.*/max_input_vars = 3000/" "$php_ini"
        fi

        systemctl enable php$ver-fpm >/dev/null 2>&1
        systemctl start php$ver-fpm >/dev/null 2>&1

        # Verify & auto-fix DOM/XML symlinks cho cả FPM và CLI
        _fix_php_ext_symlinks "$ver"
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

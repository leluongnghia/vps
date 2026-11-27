#!/bin/bash

# core/platform_helpers.sh - Helper dùng chung giữa các module
# - Đường dẫn / tên service theo hệ điều hành (Debian/Ubuntu vs RHEL/Oracle Linux)
# - SELinux
# - WP-CLI chạy bằng user của site (không phải root)
# - Tải file có kiểm tra, sửa crontab an toàn, tên database của site
#
# Mọi module nên dùng các hàm này thay vì ghi cứng /etc/php/X.Y, phpX.Y-fpm, redis-server...

# ==============================================================================
# PHP
# ==============================================================================

# Phiên bản PHP mặc định đang cài (vd: 8.3). Rỗng nếu chưa có PHP.
php_default_version() {
    local v=""
    if [[ "${OS_FAMILY:-}" != "rhel" ]] && [[ -d /etc/php ]]; then
        v=$(ls -d /etc/php/*/fpm 2>/dev/null | grep -oE '[0-9]+\.[0-9]+' | sort -V | tail -1)
    fi
    if [[ -z "$v" ]] && command -v php &>/dev/null; then
        v=$(php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;' 2>/dev/null)
    fi
    echo "$v"
}

# Tên service PHP-FPM
php_fpm_service() {
    local ver="${1:-$(php_default_version)}"
    if [[ "${OS_FAMILY:-}" == "rhel" ]]; then echo "php-fpm"; else echo "php${ver}-fpm"; fi
}

# Đường dẫn php.ini của FPM
php_ini_path() {
    local ver="${1:-$(php_default_version)}"
    if [[ "${OS_FAMILY:-}" == "rhel" ]]; then echo "/etc/php.ini"; else echo "/etc/php/${ver}/fpm/php.ini"; fi
}

# Thư mục pool.d của FPM
php_fpm_pool_dir() {
    local ver="${1:-$(php_default_version)}"
    if [[ "${OS_FAMILY:-}" == "rhel" ]]; then echo "/etc/php-fpm.d"; else echo "/etc/php/${ver}/fpm/pool.d"; fi
}

# Thư mục conf.d (ini bổ sung) của FPM
php_conf_d_dir() {
    local ver="${1:-$(php_default_version)}"
    if [[ "${OS_FAMILY:-}" == "rhel" ]]; then echo "/etc/php.d"; else echo "/etc/php/${ver}/fpm/conf.d"; fi
}

# Socket của pool mặc định (KHÔNG kèm tiền tố unix:)
php_fpm_socket() {
    local ver="${1:-$(php_default_version)}"
    if [[ "${OS_FAMILY:-}" == "rhel" ]]; then echo "/run/php-fpm/www.sock"; else echo "/run/php/php${ver}-fpm.sock"; fi
}

# Kiểm tra cấu hình FPM rồi mới restart. Trả về 1 (và KHÔNG restart) nếu config lỗi.
php_fpm_restart_safe() {
    local ver="${1:-$(php_default_version)}"
    local svc bin
    svc=$(php_fpm_service "$ver")
    if [[ "${OS_FAMILY:-}" == "rhel" ]]; then bin="php-fpm"; else bin="php-fpm${ver}"; fi
    if command -v "$bin" &>/dev/null && ! "$bin" -t &>/dev/null; then
        log_error "Cấu hình PHP-FPM ($svc) có lỗi - KHÔNG restart. Chi tiết:"
        "$bin" -t 2>&1 | tail -5
        return 1
    fi
    # Xoá trạng thái "start-limit-hit" nếu có: nhiều lần restart liên tiếp (do chính công cụ thực hiện)
    # không được phép khiến systemd từ chối khởi động PHP-FPM.
    systemctl reset-failed "$svc" 2>/dev/null
    if ! systemctl restart "$svc"; then
        log_error "Không restart được $svc. Kiểm tra: journalctl -u $svc -n 30"
        return 1
    fi
    return 0
}

# Ngân sách số tiến trình PHP-FPM cho TOÀN server (mọi pool cộng lại).
# Dành ~40% RAM cho PHP (phần còn lại cho MariaDB, cache, hệ điều hành), ~64MB mỗi tiến trình.
php_fpm_children_budget() {
    local ram_mb n
    ram_mb=$(free -m 2>/dev/null | awk '/^Mem:/{print $2}')
    [[ -z "$ram_mb" ]] && ram_mb=1024
    n=$(( ram_mb * 40 / 100 / 64 ))
    [[ "$n" -lt 4 ]] && n=4
    [[ "$n" -gt 100 ]] && n=100
    echo "$n"
}

# ==============================================================================
# Service khác
# ==============================================================================

# Tên service object cache đang cài (valkey/redis/keydb). Trả về 1 nếu không có.
cache_service_name() {
    local s
    for s in valkey-server valkey redis-server redis keydb-server keydb; do
        if systemctl list-unit-files "${s}.service" 2>/dev/null | grep -q "^${s}\.service"; then
            echo "$s"; return 0
        fi
    done
    return 1
}

# Tên service MariaDB/MySQL
mariadb_service_name() {
    local s
    for s in mariadb mysql mysqld; do
        if systemctl list-unit-files "${s}.service" 2>/dev/null | grep -q "^${s}\.service"; then
            echo "$s"; return 0
        fi
    done
    echo "mariadb"
}

# Thư mục drop-in cấu hình MariaDB (file *.cnf trong đây được nạp sau my.cnf)
mariadb_conf_dir() {
    local d
    for d in /etc/mysql/mariadb.conf.d /etc/mysql/conf.d /etc/my.cnf.d; do
        [[ -d "$d" ]] && { echo "$d"; return 0; }
    done
    return 1
}

# true nếu server DB là MariaDB (query_cache_* chỉ tồn tại ở MariaDB / MySQL < 8)
is_mariadb() {
    mysql --version 2>/dev/null | grep -qi mariadb || mariadb --version &>/dev/null
}

# User mà nginx worker đang chạy (đọc từ nginx.conf)
nginx_worker_user() {
    local u
    u=$(awk '$1=="user"{gsub(";","",$2); print $2; exit}' /etc/nginx/nginx.conf 2>/dev/null)
    if [[ -z "$u" ]]; then
        if id -u nginx &>/dev/null; then u="nginx"; else u="www-data"; fi
    fi
    echo "$u"
}

# ==============================================================================
# SELinux (RHEL/Oracle Linux)
# ==============================================================================
selinux_active() {
    command -v getenforce &>/dev/null && [[ "$(getenforce 2>/dev/null)" != "Disabled" ]]
}

# Cho phép nginx/php-fpm đọc-ghi /var/www, proxy tới app (Node/Docker) và kết nối DB/cache
selinux_allow_web() {
    selinux_active || return 0
    command -v semanage &>/dev/null || pkg_install policycoreutils-python-utils &>/dev/null || true
    setsebool -P httpd_can_network_connect 1 2>/dev/null || true
    setsebool -P httpd_can_network_connect_db 1 2>/dev/null || true
    setsebool -P httpd_unified 1 2>/dev/null || true
    if command -v semanage &>/dev/null; then
        semanage fcontext -a -t httpd_sys_rw_content_t "/var/www(/.*)?" 2>/dev/null || \
            semanage fcontext -m -t httpd_sys_rw_content_t "/var/www(/.*)?" 2>/dev/null || true
    fi
    [[ -d /var/www ]] && restorecon -R /var/www 2>/dev/null
    [[ -d /etc/nginx ]] && restorecon -R /etc/nginx 2>/dev/null
    return 0
}

# Gắn lại nhãn SELinux cho đường dẫn (no-op nếu SELinux tắt)
selinux_restore() {
    selinux_active || return 0
    restorecon -R "$@" 2>/dev/null
    return 0
}

# ==============================================================================
# Input / chuỗi
# ==============================================================================

# Tên DB / user hợp lệ: chữ, số, gạch dưới
valid_identifier() {
    [[ "$1" =~ ^[A-Za-z0-9_]{1,64}$ ]]
}

# Số nguyên dương
valid_uint() {
    [[ "$1" =~ ^[0-9]+$ ]] && [[ "$1" -gt 0 ]]
}

# Escape chuỗi để dùng làm phần THAY THẾ trong sed "s|...|<đây>|"
sed_escape_repl() {
    printf '%s' "$1" | sed -e 's/[\\&|]/\\&/g'
}

# Escape chuỗi để dùng làm PATTERN (BRE) trong sed/grep
sed_escape_pattern() {
    printf '%s' "$1" | sed -e 's/[][\\.*^$/|]/\\&/g'
}

# ==============================================================================
# Tải file an toàn: lỗi HTTP = thất bại, tải ra file tạm, chỉ ghi đè khi thành công.
# Dùng: safe_download <url> <dest> [sha256 hoặc sha512 dạng hex]
# ==============================================================================
safe_download() {
    local url=$1 dest=$2 expect=${3:-}
    local tmp got
    tmp=$(mktemp) || return 1
    if ! curl -fsSL --retry 2 --max-time 120 -o "$tmp" "$url" || [[ ! -s "$tmp" ]]; then
        rm -f "$tmp"
        log_error "Tải thất bại: $url"
        return 1
    fi
    if [[ -n "$expect" ]]; then
        if [[ ${#expect} -eq 128 ]]; then
            got=$(sha512sum "$tmp" | awk '{print $1}')
        else
            got=$(sha256sum "$tmp" | awk '{print $1}')
        fi
        if [[ "${got,,}" != "${expect,,}" ]]; then
            rm -f "$tmp"
            log_error "Checksum không khớp cho $url - đã huỷ."
            return 1
        fi
    fi
    mv -f "$tmp" "$dest"
}

# ==============================================================================
# WP-CLI: cài có kiểm tra checksum, và LUÔN chạy bằng user sở hữu site (không phải root)
# ==============================================================================
ensure_wp_cli() {
    if [[ -x /usr/local/bin/wp ]] && [[ $(stat -c %s /usr/local/bin/wp 2>/dev/null || echo 0) -gt 1000000 ]]; then
        return 0
    fi
    local base="https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar"
    local sum
    sum=$(curl -fsSL --max-time 30 "${base}.sha512" 2>/dev/null | tr -d '[:space:]')
    if [[ ! "$sum" =~ ^[0-9a-fA-F]{128}$ ]]; then
        log_error "Không lấy được checksum WP-CLI. Huỷ cài đặt."
        return 1
    fi
    safe_download "$base" /usr/local/bin/wp "$sum" || return 1
    chmod 755 /usr/local/bin/wp
    log_info "Đã cài WP-CLI (đã xác minh sha512)."
}

# User nên dùng để chạy PHP của 1 site (chủ sở hữu web root; không bao giờ là root)
site_owner() {
    local web_root=$1 u=""
    [[ -e "$web_root" ]] && u=$(stat -c %U "$web_root" 2>/dev/null)
    if [[ -z "$u" || "$u" == "root" || "$u" == "UNKNOWN" ]]; then u="www-data"; fi
    echo "$u"
}

# In ra tiền tố lệnh WP-CLI chạy bằng user của site.
# Dùng:  WP_CMD=$(wp_cmd_prefix "$web_root" "$php_bin");  $WP_CMD plugin list
# (web_root không được chứa khoảng trắng - domain đã qua validate_domain thì luôn đúng)
wp_cmd_prefix() {
    local web_root=$1 php_bin=${2:-php}
    local u cache_dir
    u=$(site_owner "$web_root")
    cache_dir="/var/cache/wp-cli-${u}"
    mkdir -p "$cache_dir" 2>/dev/null && chown "$u" "$cache_dir" 2>/dev/null
    echo "runuser -u $u -- env HOME=$cache_dir WP_CLI_CACHE_DIR=$cache_dir $php_bin -d display_errors=0 /usr/local/bin/wp --path=$web_root"
}

# ==============================================================================
# Tên database của site
# ==============================================================================

# Cách đặt tên cũ (giữ để tìm DB của site đã tạo trước đây)
legacy_db_name() {
    echo "$1" | tr -d '.-' | cut -c1-16
}

# Đọc 1 hằng số (DB_NAME, DB_USER, DB_PASSWORD...) từ wp-config.php
wp_config_get() {
    local file=$1 key=$2
    [[ -f "$file" ]] || return 1
    grep -E "^[[:space:]]*define\([[:space:]]*['\"]${key}['\"]" "$file" | head -1 | \
        sed -E "s/^[^,]*,[[:space:]]*['\"](.*)['\"][[:space:]]*\)[[:space:]]*;.*$/\1/"
}

# Tên DB THẬT của 1 site: ưu tiên wp-config.php, cuối cùng mới suy từ domain
site_db_name() {
    local domain=$1 name="" f
    for f in "/var/www/$domain/public_html/wp-config.php" "/var/www/$domain/wp-config.php"; do
        name=$(wp_config_get "$f" DB_NAME)
        [[ -n "$name" ]] && break
    done
    [[ -z "$name" ]] && name=$(legacy_db_name "$domain")
    echo "$name"
}

# Tên DB MỚI không trùng với DB đã có: tên cũ nếu còn trống, nếu không thì gắn hậu tố hash của domain
unique_db_name() {
    local domain=$1 base name
    base=$(legacy_db_name "$domain")
    name="$base"
    if db_exists "$name" 2>/dev/null; then
        name="$(echo "$base" | cut -c1-9)_$(printf '%s' "$domain" | md5sum | cut -c1-6)"
    fi
    echo "$name"
}

# ==============================================================================
# Crontab
# ==============================================================================

# Xoá các dòng cron CHỨA chuỗi cố định (fixed-string, không phải regex). Chuỗi rỗng bị từ chối.
crontab_remove_containing() {
    local needle=$1 user=${2:-root}
    [[ -z "${needle//[[:space:]]/}" ]] && return 1
    local cur
    cur=$(crontab -u "$user" -l 2>/dev/null) || return 0
    printf '%s\n' "$cur" | grep -vF -- "$needle" | crontab -u "$user" -
}

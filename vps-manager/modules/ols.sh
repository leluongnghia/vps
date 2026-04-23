#!/bin/bash

# modules/ols.sh - OpenLiteSpeed (OLS) & LSCache Manager
# Hỗ trợ: Ubuntu 20.04/22.04/24.04, Debian 11/12, AlmaLinux 8/9, Rocky Linux 8/9

OLS_WEBADMIN_PORT=7080
OLS_CONF="/usr/local/lsws/conf/httpd_config.conf"
OLS_VHOSTS_DIR="/usr/local/lsws/conf/vhosts"
OLS_WEBROOT="/var/www"
LSPHP_DEFAULT_VER="8.3"

ols_menu() {
    detect_webserver >/dev/null 2>&1

    while true; do
        clear
        echo -e "${BLUE}=================================================${NC}"
        echo -e "${GREEN}    ⚡ OpenLiteSpeed (OLS) Manager${NC}"
        echo -e "${BLUE}=================================================${NC}"

        # Hiển thị trạng thái
        if systemctl is-active --quiet lshttpd 2>/dev/null; then
            local ols_ver
            ols_ver=$(/usr/local/lsws/bin/lshttpd -v 2>/dev/null | head -1 || echo "Unknown")
            echo -e "${GREEN}  ✓ OLS đang chạy: ${ols_ver}${NC}"
        else
            echo -e "${YELLOW}  ⚠ OLS chưa được cài đặt hoặc không hoạt động${NC}"
        fi
        echo ""
        echo -e "1.  🔧 Cài đặt OpenLiteSpeed + LSPHP"
        echo -e "2.  🌐 Tạo Website WordPress mới (OLS Virtual Host)"
        echo -e "3.  🗑️  Xóa Website (OLS)"
        echo -e "4.  ⚡ Quản lý LSCache (Bật/Tắt/Purge/Cài Plugin)"
        echo -e "5.  🐘 Quản lý LSPHP Version"
        echo -e "6.  📋 Xem danh sách Virtual Hosts"
        echo -e "7.  🔄 Khởi động lại OLS"
        echo -e "8.  📊 Xem trạng thái OLS (Status + Log)"
        echo -e "9.  🔐 Truy cập WebAdmin (Thông tin cổng + Pass)"
        echo -e "0.  ↩ Quay lại Menu chính"
        echo -e "${BLUE}=================================================${NC}"
        read -p "Nhập lựa chọn [0-9]: " choice

        case $choice in
            1) install_ols_stack ;;
            2) create_ols_wp_site ;;
            3) delete_ols_site ;;
            4) lscache_menu ;;
            5) lsphp_version_menu ;;
            6) list_ols_vhosts ;;
            7) restart_ols ;;
            8) ols_status ;;
            9) show_webadmin_info ;;
            0) return ;;
            *) echo -e "${RED}Lựa chọn không hợp lệ!${NC}"; pause ;;
        esac
    done
}

# ==============================================================================
# INSTALL
# ==============================================================================

install_ols_stack() {
    # Cảnh báo nếu Nginx đang chạy
    if systemctl is-active --quiet nginx 2>/dev/null; then
        echo -e "${RED}⚠ CẢNH BÁO: Nginx đang chạy trên cổng 80/443!${NC}"
        echo -e "${YELLOW}Nginx và OLS không thể dùng chung port. Bạn cần dừng Nginx trước.${NC}"
        read -p "Dừng Nginx và tiếp tục cài OLS? [y/N]: " confirm
        if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
            log_warn "Đã huỷ cài đặt OLS."
            pause; return
        fi
        systemctl stop nginx
        systemctl disable nginx
        log_info "Đã dừng Nginx."
    fi

    echo -e "${BLUE}=================================================${NC}"
    echo -e "${GREEN}     Cài đặt OpenLiteSpeed + LSPHP${NC}"
    echo -e "${BLUE}=================================================${NC}"

    # Chọn LSPHP version
    echo -e "${YELLOW}Chọn phiên bản LSPHP cài chính:${NC}"
    echo "1. LSPHP 8.3 (Khuyên dùng)"
    echo "2. LSPHP 8.2"
    echo "3. LSPHP 8.1"
    echo "4. LSPHP 8.4"
    read -p "Chọn [1-4, mặc định 1]: " php_choice
    case $php_choice in
        2) LSPHP_DEFAULT_VER="8.2" ;;
        3) LSPHP_DEFAULT_VER="8.1" ;;
        4) LSPHP_DEFAULT_VER="8.4" ;;
        *) LSPHP_DEFAULT_VER="8.3" ;;
    esac

    log_info "Cài đặt OpenLiteSpeed + LSPHP ${LSPHP_DEFAULT_VER}..."

    # Thêm repo
    setup_ols_repo
    setup_lsphp_repo

    # Cài OLS
    if ! command -v lshttpd &>/dev/null && [[ ! -f /usr/local/lsws/bin/lshttpd ]]; then
        if [[ "$OS_FAMILY" == "debian" ]]; then
            DEBIAN_FRONTEND=noninteractive apt-get install -y openlitespeed
        else
            dnf install -y openlitespeed
        fi
    else
        log_warn "OpenLiteSpeed đã được cài. Bỏ qua cài lại."
    fi

    # Cài LSPHP
    _install_lsphp "$LSPHP_DEFAULT_VER"

    # Cài MariaDB nếu chưa có
    if ! command -v mysql &>/dev/null; then
        log_info "Cài đặt MariaDB..."
        source "$(dirname "${BASH_SOURCE[0]}")/lemp.sh"
        install_mariadb
    fi

    # Sinh mật khẩu WebAdmin ngẫu nhiên nếu chưa cấu hình
    _set_ols_webadmin_pass

    # Cấu hình ban đầu
    _configure_ols_base

    # Khởi động
    systemctl enable lshttpd
    systemctl start lshttpd

    # Mở port firewall
    _ols_open_ports

    log_info "✅ OpenLiteSpeed đã cài đặt thành công!"
    echo ""
    show_webadmin_info
    pause
}

_install_lsphp() {
    local ver=$1
    local lsphp_ver="${ver//./}"  # "8.3" -> "83"
    log_info "Cài đặt LSPHP ${ver} (lsphp${lsphp_ver})..."

    local packages=(
        "lsphp${lsphp_ver}"
        "lsphp${lsphp_ver}-common"
        "lsphp${lsphp_ver}-mysql"
        "lsphp${lsphp_ver}-curl"
        "lsphp${lsphp_ver}-xml"
        "lsphp${lsphp_ver}-mbstring"
        "lsphp${lsphp_ver}-zip"
        "lsphp${lsphp_ver}-bcmath"
        "lsphp${lsphp_ver}-intl"
        "lsphp${lsphp_ver}-gd"
        "lsphp${lsphp_ver}-imagick"
    )

    if [[ "$OS_FAMILY" == "debian" ]]; then
        DEBIAN_FRONTEND=noninteractive apt-get install -y "${packages[@]}" 2>/dev/null || {
            # Thử cài từng gói, bỏ qua gói không có
            for pkg in "${packages[@]}"; do
                DEBIAN_FRONTEND=noninteractive apt-get install -y "$pkg" &>/dev/null || true
            done
        }
    else
        dnf install -y "${packages[@]}" 2>/dev/null || {
            for pkg in "${packages[@]}"; do
                dnf install -y "$pkg" &>/dev/null || true
            done
        }
    fi

    # Cấu hình php.ini cho LSPHP
    local lsphp_ini="/usr/local/lsws/lsphp${lsphp_ver}/etc/php/${ver}/litespeed/php.ini"
    if [[ -f "$lsphp_ini" ]]; then
        sed -i -E "s/^[; ]*upload_max_filesize.*/upload_max_filesize = 128M/" "$lsphp_ini"
        sed -i -E "s/^[; ]*post_max_size.*/post_max_size = 128M/" "$lsphp_ini"
        sed -i -E "s/^[; ]*memory_limit.*/memory_limit = 256M/" "$lsphp_ini"
        sed -i -E "s/^[; ]*max_execution_time.*/max_execution_time = 300/" "$lsphp_ini"
        sed -i -E "s/^[; ]*max_input_vars.*/max_input_vars = 3000/" "$lsphp_ini"
        # Bật OPcache
        sed -i -E "s/^[; ]*opcache.enable.*/opcache.enable = 1/" "$lsphp_ini"
        sed -i -E "s/^[; ]*opcache.memory_consumption.*/opcache.memory_consumption = 256/" "$lsphp_ini"
        sed -i -E "s/^[; ]*opcache.max_accelerated_files.*/opcache.max_accelerated_files = 10000/" "$lsphp_ini"
        log_info "Đã cấu hình php.ini cho LSPHP ${ver}"
    fi

    log_info "LSPHP ${ver} đã được cài đặt."
}

_set_ols_webadmin_pass() {
    local pass_file="/root/.ols_webadmin_pass"
    if [[ ! -f "$pass_file" ]]; then
        local new_pass
        new_pass=$(openssl rand -base64 16 | tr -dc 'a-zA-Z0-9' | head -c 16)
        echo "$new_pass" > "$pass_file"
        chmod 600 "$pass_file"

        # Set password cho OLS WebAdmin
        if [[ -f /usr/local/lsws/admin/misc/htpasswd.sh ]]; then
            /usr/local/lsws/admin/misc/htpasswd.sh -b /usr/local/lsws/admin/conf/htpasswd admin "$new_pass" &>/dev/null
        fi
        log_info "WebAdmin password được tạo. Xem tại: $pass_file"
    fi
}

_configure_ols_base() {
    # Đảm bảo thư mục vhosts tồn tại
    mkdir -p "$OLS_VHOSTS_DIR"
    mkdir -p "$OLS_WEBROOT"

    # Cấu hình OLS lắng nghe cổng 80/443
    if [[ -f "$OLS_CONF" ]]; then
        # 1. Tối ưu OLS LSCache nhét vào RAM giống WpTangToc
        if ! grep -q "totalInMemCacheSize" "$OLS_CONF" 2>/dev/null; then
            sed -i '/module cache {/a \  totalInMemCacheSize     64M\n  maxCachedFileSize       10M' "$OLS_CONF" 2>/dev/null
            log_info "Đã kích hoạt LSCache lưu trữ trực tiếp trên RAM (64M) cho hệ thống."
        fi

        # Đảm bảo listeners có trong config (nội dung cơ bản)
        if ! grep -q "listener HTTP" "$OLS_CONF" 2>/dev/null; then
            cat >> "$OLS_CONF" <<'EOF'

listener HTTP {
  address                 *:80
  secure                  0
}

listener HTTPS {
  address                 *:443
  secure                  1
  keyFile                 /usr/local/lsws/conf/example.key
  certFile                /usr/local/lsws/conf/example.crt
  enableSpdy              4
  enableQuic              1
}
EOF
        fi
    fi
}

_ols_open_ports() {
    if [[ "$OS_FAMILY" == "debian" ]]; then
        if command -v ufw &>/dev/null && ufw status | grep -q "active"; then
            ufw allow 80/tcp
            ufw allow 443/tcp
            ufw allow 443/udp
            ufw allow "${OLS_WEBADMIN_PORT}/tcp"
        fi
    elif [[ "$OS_FAMILY" == "rhel" ]]; then
        if command -v firewall-cmd &>/dev/null; then
            firewall-cmd --permanent --add-service=http
            firewall-cmd --permanent --add-service=https
            firewall-cmd --permanent --add-port=443/udp
            firewall-cmd --permanent --add-port="${OLS_WEBADMIN_PORT}/tcp"
            firewall-cmd --reload
        fi
    fi
}

# ==============================================================================
# VIRTUAL HOST
# ==============================================================================

create_ols_wp_site() {
    require_webserver "openlitespeed" || return

    echo -e "${BLUE}=================================================${NC}"
    echo -e "${GREEN}    Tạo WordPress Site mới (OLS)${NC}"
    echo -e "${BLUE}=================================================${NC}"

    read -p "Nhập tên domain (vd: example.com): " domain
    domain=$(echo "$domain" | tr '[:upper:]' '[:lower:]' | sed 's/^www\.//')
    [[ -z "$domain" ]] && { log_error "Domain không hợp lệ!"; pause; return; }
    validate_domain "$domain" || { pause; return; }

    local site_root="${OLS_WEBROOT}/${domain}/public_html"
    local lsphp_bin
    local lsphp_ver_no_dot="${LSPHP_DEFAULT_VER//./}"
    lsphp_bin="/usr/local/lsws/lsphp${lsphp_ver_no_dot}/bin/lsphp"

    # Chọn LSPHP version
    echo -e "${YELLOW}Phiên bản LSPHP cho site này:${NC}"
    echo "1. LSPHP 8.3 (Khuyên dùng)"
    echo "2. LSPHP 8.2"
    echo "3. LSPHP 8.1"
    read -p "Chọn [1-3, mặc định 1]: " pv
    case $pv in
        2) local site_php_ver="8.2"; lsphp_bin="/usr/local/lsws/lsphp82/bin/lsphp" ;;
        3) local site_php_ver="8.1"; lsphp_bin="/usr/local/lsws/lsphp81/bin/lsphp" ;;
        *) local site_php_ver="8.3"; lsphp_bin="/usr/local/lsws/lsphp83/bin/lsphp" ;;
    esac

    if [[ ! -x "$lsphp_bin" ]]; then
        log_warn "LSPHP ${site_php_ver} chưa được cài. Đang cài..."
        _install_lsphp "$site_php_ver"
    fi

    # Tạo thư mục web
    mkdir -p "$site_root"
    chown -R nobody:nogroup "$site_root" 2>/dev/null || chown -R www-data:www-data "$site_root" 2>/dev/null
    chmod -R 755 "$site_root"

    # Tạo database WordPress
    local db_name="${domain//./_}_wp"
    local db_user="${domain//./_}_usr"
    local db_pass
    db_pass=$(openssl rand -base64 16 | tr -dc 'a-zA-Z0-9' | head -c 16)
    db_name="${db_name:0:32}"
    db_user="${db_user:0:16}"

    mysql <<EOF
CREATE DATABASE IF NOT EXISTS \`${db_name}\`;
CREATE USER IF NOT EXISTS '${db_user}'@'localhost' IDENTIFIED BY '${db_pass}';
GRANT ALL PRIVILEGES ON \`${db_name}\`.* TO '${db_user}'@'localhost';
FLUSH PRIVILEGES;
EOF

    # Tạo OLS Virtual Host config
    mkdir -p "${OLS_VHOSTS_DIR}/${domain}"
    cat > "${OLS_VHOSTS_DIR}/${domain}/vhconf.conf" <<EOF
docRoot                   \$VH_ROOT/public_html
vhDomain                  ${domain}
vhAliases                 www.${domain}
enableGzip                1

index  {
  useServer               0
  indexFiles              index.php, index.html
}

scripthandler  {
  add                     lsapi:${lsphp_bin} php
}

extprocessor lsphp {
  type                    lsapi
  address                 uds://tmp/lshttpd/${domain}-lsphp.sock
  maxConns                35
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
  path                    ${lsphp_bin}
  backlog                 100
  instances               1
}

rewrite  {
  enable                  1
  autoLoadHtaccess        1
  rules                   <<<END_rules
RewriteEngine on
RewriteBase /
RewriteRule ^index\.php$ - [L]
RewriteCond %{REQUEST_FILENAME} !-f
RewriteCond %{REQUEST_FILENAME} !-d
RewriteRule . /index.php [L]
  END_rules
}

EOF

    # Đăng ký vhost vào httpd_config.conf
    if [[ -f "$OLS_CONF" ]] && ! grep -q "virtualhost ${domain}" "$OLS_CONF"; then
        cat >> "$OLS_CONF" <<EOF

virtualhost ${domain} {
  vhRoot                  ${OLS_WEBROOT}/${domain}
  configFile              \$SERVER_ROOT/conf/vhosts/${domain}/vhconf.conf
  allowSymbolLink         1
  enableScript            1
  restrained              0
}
EOF

        # Thêm mapping listener -> vhost
        if grep -q "listener HTTP" "$OLS_CONF"; then
            sed -i "/listener HTTP {/a\\  vhosts                  ${domain}" "$OLS_CONF"
        fi
    fi

    # Lưu thông tin site
    mkdir -p ~/.vps-manager
    cat >> ~/.vps-manager/sites_data.conf <<EOF
[${domain}]
site_root=${site_root}
db_name=${db_name}
db_user=${db_user}
db_pass=${db_pass}
webserver=openlitespeed
php_ver=${site_php_ver}
created=$(date '+%Y-%m-%d %H:%M:%S')
EOF

    # Cài WordPress bằng WP-CLI
    if command -v wp &>/dev/null; then
        read -p "Cài đặt WordPress tự động? [Y/n]: " install_wp
        if [[ "$install_wp" != "n" && "$install_wp" != "N" ]]; then
            log_info "Đang tải WordPress..."
            sudo -u www-data wp core download --path="$site_root" --locale=vi --quiet 2>/dev/null || \
                wp core download --path="$site_root" --locale=vi --allow-root --quiet

            wp config create \
                --path="$site_root" \
                --dbname="$db_name" \
                --dbuser="$db_user" \
                --dbpass="$db_pass" \
                --allow-root --quiet

            # Auto inject Object Cache Unix Socket if exists
            if [[ -S "/tmp/valkey.sock" ]] || [[ -S "/tmp/redis.sock" ]]; then
                local socket_path=""
                [[ -S "/tmp/redis.sock" ]] && socket_path="/tmp/redis.sock"
                [[ -S "/tmp/valkey.sock" ]] && socket_path="/tmp/valkey.sock"
                
                if [[ -n "$socket_path" ]]; then
                    sed -i "/table_prefix/i define( 'WP_REDIS_SCHEME', 'unix' );" "$site_root/wp-config.php"
                    sed -i "/table_prefix/i define( 'WP_REDIS_PATH', '$socket_path' );" "$site_root/wp-config.php"
                    sed -i "/table_prefix/i define( 'WP_CACHE_KEY_SALT', '$domain:' );" "$site_root/wp-config.php"
                fi
            fi

            read -p "Nhập title website: " site_title
            local admin_pass
            admin_pass=$(openssl rand -base64 12 | tr -dc 'a-zA-Z0-9' | head -c 12)
            read -p "Nhập email admin: " admin_email

            wp core install \
                --path="$site_root" \
                --url="http://${domain}" \
                --title="${site_title:-My WordPress Site}" \
                --admin_user="admin" \
                --admin_password="$admin_pass" \
                --admin_email="${admin_email:-admin@${domain}}" \
                --allow-root --quiet

            log_info "WordPress đã được cài đặt!"
            echo -e "${YELLOW}Admin URL: http://${domain}/wp-admin${NC}"
            echo -e "${YELLOW}Username:  admin${NC}"
            echo -e "${YELLOW}Password:  ${admin_pass}${NC}"
        fi
    fi

    restart_ols

    echo ""
    log_info "✅ Site ${domain} đã được tạo thành công!"
    echo -e "${YELLOW}DB Name:   ${db_name}${NC}"
    echo -e "${YELLOW}DB User:   ${db_user}${NC}"
    echo -e "${YELLOW}DB Pass:   ${db_pass}${NC}"
    echo -e "${YELLOW}Site Root: ${site_root}${NC}"
    pause
}

delete_ols_site() {
    require_webserver "openlitespeed" || return
    list_ols_vhosts
    read -p "Nhập domain cần xóa: " domain
    [[ -z "$domain" ]] && return

    read -p "Bạn chắc chắn muốn xóa ${domain}? Thao tác này KHÔNG thể hoàn tác! [y/N]: " confirm
    [[ "$confirm" != "y" && "$confirm" != "Y" ]] && return

    # Xóa vhost config
    rm -rf "${OLS_VHOSTS_DIR}/${domain}"

    # Xóa khỏi httpd_config.conf
    if [[ -f "$OLS_CONF" ]]; then
        # Tạo backup
        cp "$OLS_CONF" "${OLS_CONF}.bak.$(date +%Y%m%d%H%M%S)"
        # Xóa block virtualhost
        sed -i "/^virtualhost ${domain}/,/^}/d" "$OLS_CONF"
    fi

    # Xóa thư mục web (hỏi thêm)
    if [[ -d "${OLS_WEBROOT}/${domain}" ]]; then
        read -p "Xóa cả thư mục file web (${OLS_WEBROOT}/${domain})? [y/N]: " del_files
        if [[ "$del_files" == "y" || "$del_files" == "Y" ]]; then
            rm -rf "${OLS_WEBROOT:?}/${domain}"
            log_info "Đã xóa thư mục: ${OLS_WEBROOT}/${domain}"
        fi
    fi

    restart_ols
    log_info "Đã xóa site: ${domain}"
    pause
}

# ==============================================================================
# LSCACHE
# ==============================================================================

lscache_menu() {
    while true; do
        clear
        echo -e "${BLUE}=================================================${NC}"
        echo -e "${GREEN}    ⚡ LSCache Manager${NC}"
        echo -e "${BLUE}=================================================${NC}"
        echo -e "1. Cài Plugin LiteSpeed Cache (WP-CLI)"
        echo -e "2. Bật LSCache cho site"
        echo -e "3. Tắt LSCache cho site"
        echo -e "4. 🗑️  Purge LSCache cho site"
        echo -e "5. Purge LSCache TẤT CẢ site"
        echo -e "0. Quay lại"
        echo -e "${BLUE}=================================================${NC}"
        read -p "Nhập lựa chọn [0-5]: " choice

        case $choice in
            1) install_lscache_plugin ;;
            2) enable_lscache ;;
            3) disable_lscache ;;
            4) purge_lscache_site ;;
            5) purge_lscache_all ;;
            0) return ;;
            *) echo -e "${RED}Lựa chọn không hợp lệ!${NC}"; pause ;;
        esac
    done
}

install_lscache_plugin() {
    if ! command -v wp &>/dev/null; then
        log_error "WP-CLI chưa được cài đặt. Vào Menu 3 để cài WP-CLI trước."
        pause; return
    fi

    list_ols_vhosts
    read -p "Nhập domain cần cài LSCache plugin: " domain
    local site_root="${OLS_WEBROOT}/${domain}/public_html"
    [[ ! -d "$site_root" ]] && { log_error "Không tìm thấy site root: $site_root"; pause; return; }

    log_info "Cài đặt LiteSpeed Cache plugin cho ${domain}..."
    wp plugin install litespeed-cache --activate --path="$site_root" --allow-root

    log_info "✅ LiteSpeed Cache plugin đã được cài và kích hoạt cho ${domain}"
    log_info "Vào wp-admin > LiteSpeed Cache > Settings để cấu hình thêm."
    pause
}

enable_lscache() {
    list_ols_vhosts
    read -p "Nhập domain: " domain
    local vhconf="${OLS_VHOSTS_DIR}/${domain}/vhconf.conf"
    [[ ! -f "$vhconf" ]] && { log_error "Không tìm thấy vhost config!"; pause; return; }

    if ! grep -q "lscachePolicy" "$vhconf"; then
        cat >> "$vhconf" <<'EOF'

lscachePolicy {
  enableCache           1
  maxCacheSize          2048
  maxStaleAge           200
  qsCache               1
  reqCookieCache        1
  respCookieCache       1
  ignoreReqCacheCtrl    1
  ignoreRespCacheCtrl   0
  respCacheCtrlNoStore  0
  respCCMaxAge          0
  maxURLLen             2048
  maxFieldLen           200
  maxNumOfFields        50
  maxReqBodyLen         0
}
EOF
        log_info "Đã bật LSCache cho ${domain}"
    else
        sed -i "s/enableCache.*0/enableCache           1/" "$vhconf"
        log_info "LSCache đã được bật cho ${domain}"
    fi
    restart_ols
    pause
}

disable_lscache() {
    list_ols_vhosts
    read -p "Nhập domain: " domain
    local vhconf="${OLS_VHOSTS_DIR}/${domain}/vhconf.conf"
    [[ ! -f "$vhconf" ]] && { log_error "Không tìm thấy vhost config!"; pause; return; }
    sed -i "s/enableCache.*1/enableCache           0/" "$vhconf"
    restart_ols
    log_info "Đã tắt LSCache cho ${domain}"
    pause
}

purge_lscache_site() {
    list_ols_vhosts
    read -p "Nhập domain cần purge cache: " domain
    local lscache_dir="/dev/shm/opc_docroot_$(echo "${OLS_WEBROOT}/${domain}" | md5sum | cut -c1-8)"
    local lscache_dir2="/tmp/lscache/${domain}"

    # LiteSpeed lưu cache theo nhiều đường dẫn khác nhau
    for cache_path in \
        "/dev/shm/lscache" \
        "/tmp/lshttpd/lscache" \
        "${OLS_WEBROOT}/${domain}/public_html/wp-content/cache/lite-speed"; do
        if [[ -d "$cache_path" ]]; then
            rm -rf "${cache_path:?}"/* 2>/dev/null
            log_info "Đã purge: $cache_path"
        fi
    done

    # Gọi WP-CLI nếu có
    if command -v wp &>/dev/null && [[ -d "${OLS_WEBROOT}/${domain}/public_html" ]]; then
        wp litespeed-purge all \
            --path="${OLS_WEBROOT}/${domain}/public_html" \
            --allow-root 2>/dev/null && log_info "WP-CLI: Đã purge LSCache qua plugin."
    fi

    log_info "✅ Đã purge LSCache cho ${domain}"
    pause
}

purge_lscache_all() {
    log_info "Đang purge LSCache toàn bộ server..."
    for cache_path in "/dev/shm/lscache" "/tmp/lshttpd/lscache"; do
        [[ -d "$cache_path" ]] && rm -rf "${cache_path:?}"/* && log_info "Đã purge: $cache_path"
    done
    restart_ols
    log_info "✅ Đã purge cache toàn bộ và restart OLS."
    pause
}

# ==============================================================================
# LSPHP VERSION
# ==============================================================================

lsphp_version_menu() {
    while true; do
        clear
        echo -e "${BLUE}=================================================${NC}"
        echo -e "${GREEN}    🐘 Quản lý LSPHP Version${NC}"
        echo -e "${BLUE}=================================================${NC}"

        # Hiển thị LSPHP đang cài
        echo -e "${YELLOW}LSPHP đã cài:${NC}"
        for ver in 74 80 81 82 83 84; do
            local bin="/usr/local/lsws/lsphp${ver}/bin/lsphp"
            if [[ -x "$bin" ]]; then
                local ver_str="${ver:0:1}.${ver:1}"
                echo -e "  ${GREEN}✓${NC} LSPHP ${ver_str}"
            fi
        done
        echo ""
        echo -e "1. Cài thêm LSPHP version"
        echo -e "2. Đổi LSPHP mặc định cho site"
        echo -e "0. Quay lại"
        echo -e "${BLUE}=================================================${NC}"
        read -p "Nhập lựa chọn [0-2]: " choice

        case $choice in
            1)
                echo "Phiên bản cần cài: 1) 8.1  2) 8.2  3) 8.3  4) 8.4  5) 7.4"
                read -p "Chọn [1-5]: " pv
                case $pv in
                    1) _install_lsphp "8.1" ;;
                    2) _install_lsphp "8.2" ;;
                    3) _install_lsphp "8.3" ;;
                    4) _install_lsphp "8.4" ;;
                    5) _install_lsphp "7.4" ;;
                esac
                pause
                ;;
            2)
                list_ols_vhosts
                read -p "Nhập domain: " domain
                echo "Đổi sang LSPHP: 1) 8.1  2) 8.2  3) 8.3  4) 8.4"
                read -p "Chọn [1-4]: " pv
                local new_ver="8.3"
                case $pv in
                    1) new_ver="8.1" ;;
                    2) new_ver="8.2" ;;
                    3) new_ver="8.3" ;;
                    4) new_ver="8.4" ;;
                esac
                local new_bin="/usr/local/lsws/lsphp${new_ver//./}/bin/lsphp"
                local vhconf="${OLS_VHOSTS_DIR}/${domain}/vhconf.conf"
                if [[ -f "$vhconf" ]]; then
                    sed -i "s|lsphp[0-9][0-9]/bin/lsphp|lsphp${new_ver//./}/bin/lsphp|g" "$vhconf"
                    restart_ols
                    log_info "Đã đổi sang LSPHP ${new_ver} cho ${domain}"
                else
                    log_error "Không tìm thấy vhost config cho ${domain}"
                fi
                pause
                ;;
            0) return ;;
        esac
    done
}

# ==============================================================================
# UTILS
# ==============================================================================

list_ols_vhosts() {
    echo -e "${YELLOW}Danh sách Virtual Hosts:${NC}"
    if [[ -d "$OLS_VHOSTS_DIR" ]]; then
        local count=0
        for vh_dir in "${OLS_VHOSTS_DIR}"/*/; do
            if [[ -d "$vh_dir" ]]; then
                local vh_name
                vh_name=$(basename "$vh_dir")
                echo -e "  • ${vh_name}"
                count=$((count + 1))
            fi
        done
        [[ $count -eq 0 ]] && echo -e "  ${YELLOW}Chưa có Virtual Host nào.${NC}"
    else
        echo -e "  ${RED}Thư mục vhosts không tồn tại.${NC}"
    fi
    echo ""
}

restart_ols() {
    if [[ -f /usr/local/lsws/bin/lswsctrl ]]; then
        /usr/local/lsws/bin/lswsctrl restart &>/dev/null
        log_info "Đã restart OpenLiteSpeed."
    else
        systemctl restart lshttpd 2>/dev/null && log_info "Đã restart OLS."
    fi
}

ols_status() {
    clear
    echo -e "${BLUE}========================================${NC}"
    echo -e "${GREEN}  Trạng thái OpenLiteSpeed${NC}"
    echo -e "${BLUE}========================================${NC}"

    # Service status
    systemctl status lshttpd --no-pager -l 2>/dev/null || echo "OLS không chạy."
    echo ""

    # Version
    echo -e "${YELLOW}Version:${NC}"
    /usr/local/lsws/bin/lshttpd -v 2>/dev/null || echo "Không xác định"
    echo ""

    # Logs (20 dòng cuối)
    echo -e "${YELLOW}Error Log (20 dòng cuối):${NC}"
    tail -20 /usr/local/lsws/logs/error.log 2>/dev/null || echo "Không tìm thấy log."
    pause
}

show_webadmin_info() {
    local pass_file="/root/.ols_webadmin_pass"
    local vps_ip
    vps_ip=$(curl -s -m 3 ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}')

    echo -e "${BLUE}========================================${NC}"
    echo -e "${GREEN}  Thông tin WebAdmin Panel${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo -e "${YELLOW}URL:      https://${vps_ip}:${OLS_WEBADMIN_PORT}${NC}"
    echo -e "${YELLOW}Username: admin${NC}"
    if [[ -f "$pass_file" ]]; then
        echo -e "${YELLOW}Password: $(cat "$pass_file")${NC}"
    else
        echo -e "${YELLOW}Password: (Xem tại /root/.ols_webadmin_pass hoặc đặt lại trong OLS)${NC}"
    fi
    echo -e "${BLUE}========================================${NC}"
}

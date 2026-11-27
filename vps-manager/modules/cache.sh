#!/bin/bash

# modules/cache.sh - Cache Management
#
# File này cũng chứa các helper dùng chung cho WordPress + Object Cache
# (wordpress_performance.sh source file này để dùng lại, tránh viết 2-3 bản khác nhau):
#   _wp_config_path, _is_real_site, _wp_list_sites, _wp_config_put_define, _wp_redis_write_config,
#   _wp_redis_enable_plugin, _oc_install_server, _oc_ensure_php_ext, _oc_restart_all_php_fpm
#
# Cài server cache chỉ có MỘT hiện thực: _install_object_cache_nginx trong modules/lemp.sh.
# File này chỉ lo phần theo từng site (hằng số wp-config, plugin, flush, trạng thái).

cache_menu() {
    while true; do
        clear
        echo -e "${BLUE}=================================================${NC}"
        echo -e "${GREEN}          Quản lý Cache${NC}"
        echo -e "${BLUE}=================================================${NC}"
        echo -e "1. Xóa Cache (FastCGI, Redis/Valkey/KeyDB, OPcache)"
        echo -e "2. Bật/Tắt Redis PHP Extension"
        echo -e "3. Bật/Tắt Opcache"
        echo -e "4. Cấu hình Nginx cho WP Rocket"
        echo -e "5. Cấu hình Nginx cho W3 Total Cache"
        echo -e "6. Tối ưu Server cho Object Cache Pro"
        echo -e "7. Fix lỗi kết nối Redis/Valkey (Connection Refused)"
        echo -e "8. Cài đặt Object Cache (Valkey/Redis) + bật cho WordPress"
        echo -e "9. Tự làm mới FastCGI Cache khi sửa bài (bật cho mọi site WordPress)"
        echo -e "0. Quay lại Menu chính"
        echo -e "${BLUE}=================================================${NC}"
        read -p "Nhập lựa chọn [0-9]: " choice

        case $choice in
            1) clear_all_cache ;;
            2) toggle_extension "redis" ;;
            3) toggle_extension "opcache" ;;
            4) setup_rocket_nginx ;;
            5) setup_w3tc_nginx ;;
            6) setup_object_cache_pro ;;
            7) fix_redis_connection ;;
            8) install_object_cache ;;
            9) cache_refresh_enable_all; pause ;;
            0) return ;;
            *) echo -e "${RED}Lựa chọn không hợp lệ!${NC}"; pause ;;
        esac
    done
}

# =============================================================================
# Helper dùng chung
# =============================================================================

# Đường dẫn wp-config.php của 1 site: trong public_html, hoặc thư mục cha (khi đã "Move wp-config").
_wp_config_path() {
    local domain=$1 f
    for f in "/var/www/$domain/public_html/wp-config.php" "/var/www/$domain/wp-config.php"; do
        if [[ -f "$f" ]]; then echo "$f"; return 0; fi
    done
    return 1
}

# Chỉ áp dụng cho domain thật: có /var/www/$d/public_html, không phải .bak/.old/000-*
_is_real_site() {
    local d="$1"
    [[ "$d" == "default" || "$d" == "html" ]] && return 1
    [[ "$d" == 000-* ]] && return 1
    [[ "$d" == *.bak* || "$d" == *.old || "$d" == *.disabled || "$d" == *.bak_* ]] && return 1
    [ -d "/var/www/$d/public_html" ] || return 1
    return 0
}

# In ra danh sách domain WordPress (mỗi dòng 1 domain)
_wp_list_sites() {
    local d domain
    for d in /var/www/*/; do
        domain=$(basename "$d")
        [[ -d "/var/www/$domain/public_html" ]] || continue
        _wp_config_path "$domain" >/dev/null && echo "$domain"
    done
}

# Ghi 1 hằng số vào wp-config.php (idempotent: xoá define cũ cùng tên rồi chèn trước $table_prefix).
# Dùng: _wp_config_put_define <file> <NAME> <giá trị PHP nguyên văn>
#   vd: _wp_config_put_define "$f" WP_CACHE true
#       _wp_config_put_define "$f" WP_REDIS_PATH "'/var/run/valkey/valkey.sock'"
# Giữ nguyên owner/permission của file.
_wp_config_put_define() {
    local file=$1 name=$2 value=$3
    [[ -f "$file" ]] || return 1
    local tmp has_tp=0
    tmp=$(mktemp) || return 1
    grep -qE '^[[:space:]]*\$table_prefix' "$file" && has_tp=1
    if ! WPC_NAME="$name" WPC_LINE="define( '$name', $value );" WPC_HAS_TP="$has_tp" awk -v q="'" '
        BEGIN {
            n = ENVIRON["WPC_NAME"]; l = ENVIRON["WPC_LINE"]; has_tp = ENVIRON["WPC_HAS_TP"]
            pat = "^[ \t]*define\\([ \t]*[\"" q "]" n "[\"" q "]"
        }
        $0 ~ pat { next }
        !done && has_tp == 1 && /^[ \t]*\$table_prefix/ { print l; done = 1 }
        { print }
        !done && has_tp != 1 && NR == 1 { print l; done = 1 }
    ' "$file" > "$tmp" || [[ ! -s "$tmp" ]]; then
        rm -f "$tmp"
        return 1
    fi
    cat "$tmp" > "$file"
    rm -f "$tmp"
}

# Xoá 1 hằng số khỏi wp-config.php
_wp_config_remove_define() {
    local file=$1 name=$2
    [[ -f "$file" ]] || return 1
    sed -i -E "/^[[:space:]]*define\([[:space:]]*['\"]${name}['\"]/d" "$file"
}

# Bộ hằng số Redis/Valkey/KeyDB THỐNG NHẤT cho plugin "Redis Object Cache":
#   Unix socket: WP_REDIS_SCHEME 'unix' + WP_REDIS_PATH
#   TCP        : WP_REDIS_HOST + WP_REDIS_PORT
# Dùng: _wp_redis_write_config <domain> <socket_path | rỗng nếu TCP>
_wp_redis_write_config() {
    local domain=$1 socket_path=$2
    local wp_config k
    wp_config=$(_wp_config_path "$domain") || return 1

    for k in WP_REDIS_SCHEME WP_REDIS_PATH WP_REDIS_HOST WP_REDIS_PORT WP_REDIS_DISABLED; do
        _wp_config_remove_define "$wp_config" "$k"
    done

    if [[ -n "$socket_path" ]]; then
        _wp_config_put_define "$wp_config" WP_REDIS_SCHEME "'unix'" || return 1
        _wp_config_put_define "$wp_config" WP_REDIS_PATH "'$socket_path'" || return 1
    else
        _wp_config_put_define "$wp_config" WP_REDIS_HOST "'127.0.0.1'" || return 1
        _wp_config_put_define "$wp_config" WP_REDIS_PORT "6379" || return 1
    fi

    # Mỗi site 1 tiền tố key riêng -> không cần chia WP_REDIS_DATABASE (Redis chỉ có 0-15)
    if ! grep -q "WP_CACHE_KEY_SALT" "$wp_config"; then
        local salt
        salt="${domain}_$(head -c 64 /dev/urandom | tr -dc 'A-Za-z0-9' | head -c 8)_"
        _wp_config_put_define "$wp_config" WP_CACHE_KEY_SALT "'$salt'" || return 1
    fi
    return 0
}

# Flush object cache của 1 site bằng WP-CLI (chạy bằng user của site, không phải root)
_wp_cache_flush_site() {
    local domain=$1
    local root="/var/www/$domain/public_html"
    [[ -x /usr/local/bin/wp ]] || return 0
    $(wp_cmd_prefix "$root") cache flush >/dev/null 2>&1 || true
}

# Đường dẫn socket chuẩn của từng loại cache
_oc_socket_path() {
    echo "/var/run/${1}/${1}.sock"
}

# Loại cache (valkey|redis|keydb) suy từ tên service
_oc_type_from_service() {
    echo "${1%-server}"
}

# Socket đang dùng: ưu tiên /etc/vps-manager/cache.conf, rồi file config của service
_oc_current_socket() {
    local svc=${1:-} type conf s=""
    if [[ -f /etc/vps-manager/cache.conf ]]; then
        s=$(grep -E '^OBJECT_CACHE_SOCKET=' /etc/vps-manager/cache.conf 2>/dev/null | head -n 1 | cut -d= -f2-)
    fi
    if [[ -z "$s" || ! -S "$s" ]] && [[ -n "$svc" ]]; then
        type=$(_oc_type_from_service "$svc")
        for conf in "/etc/${type}/${type}.conf" "/etc/${type}/${type}-server.conf" "/etc/${type}.conf"; do
            if [[ -f "$conf" ]]; then
                s=$(awk '$1=="unixsocket"{print $2; exit}' "$conf")
                [[ -n "$s" ]] && break
            fi
        done
    fi
    # Dò trực tiếp socket đang tồn tại
    if [[ -z "$s" || ! -S "$s" ]]; then
        local probe
        for probe in /var/run/valkey/*.sock /var/run/redis/*.sock /var/run/keydb/*.sock; do
            if [[ -S "$probe" ]]; then s="$probe"; break; fi
        done
    fi
    echo "$s"
}

# Cài + kích hoạt plugin "Redis Object Cache" và bật drop-in cho 1 site (WP-CLI chạy bằng user của site).
# Không tự xoá object-cache.php lạ (vd Object Cache Pro) - chỉ thay khi người dùng đồng ý.
# Dùng: _wp_redis_enable_plugin <domain>
_wp_redis_enable_plugin() {
    local domain=$1
    local root="/var/www/$domain/public_html"
    local wp_config dropin php_bin="php" WP
    wp_config=$(_wp_config_path "$domain") || return 1
    ensure_wp_cli || return 1

    if declare -F _wp_resolve_php_bin_for_site >/dev/null; then
        _wp_resolve_php_bin_for_site "$domain" php_bin || true
    fi
    WP=$(wp_cmd_prefix "$root" "$php_bin")

    if ! $WP plugin is-installed redis-cache 2>/dev/null; then
        if ! $WP plugin install redis-cache --activate >/dev/null 2>&1; then
            log_warn "[$domain] Cài plugin redis-cache thất bại."
            return 1
        fi
    else
        $WP plugin activate redis-cache >/dev/null 2>&1 || true
    fi

    _wp_config_put_define "$wp_config" WP_CACHE true || true

    dropin="$root/wp-content/object-cache.php"
    if [[ -f "$dropin" ]] && ! grep -q "Redis Object Cache" "$dropin" 2>/dev/null; then
        echo -e "${YELLOW}[$domain] Đang có drop-in object-cache.php của plugin khác.${NC}"
        read -p "  Thay bằng drop-in của Redis Object Cache? [y/N]: " rep
        if [[ "$rep" != "y" && "$rep" != "Y" ]]; then
            log_warn "[$domain] Giữ nguyên drop-in hiện có - chưa bật Redis Object Cache."
            return 0
        fi
        mv -f "$dropin" "${dropin}.bak_$(date +%s)"
    fi

    if $WP redis enable >/dev/null 2>&1 || $WP redis update-dropin >/dev/null 2>&1; then
        log_info "✓ [$domain] Redis Object Cache: plugin + drop-in đã bật"
        return 0
    fi
    log_warn "[$domain] Chưa bật được drop-in - vào WP Admin -> Settings -> Redis -> Enable Object Cache."
    return 1
}

# File config của service cache
_oc_conf_file() {
    local type conf
    type=$(_oc_type_from_service "$1")
    for conf in "/etc/${type}/${type}.conf" "/etc/${type}/${type}-server.conf" "/etc/${type}.conf"; do
        [[ -f "$conf" ]] && { echo "$conf"; return 0; }
    done
    return 1
}

# CLI tương ứng (valkey-cli / redis-cli / keydb-cli)
_oc_cli() {
    local type c
    type=$(_oc_type_from_service "${1:-redis}")
    for c in "${type}-cli" redis-cli valkey-cli keydb-cli; do
        command -v "$c" &>/dev/null && { echo "$c"; return 0; }
    done
    return 1
}

# Restart (có kiểm tra config) mọi PHP-FPM đang chạy - cần sau khi đổi group của www-data / bật extension
_oc_restart_all_php_fpm() {
    local rc=0 v
    if [[ "$OS_FAMILY" == "rhel" ]]; then
        php_fpm_restart_safe || rc=1
    else
        for v in $(ls -d /etc/php/*/fpm 2>/dev/null | grep -oE '[0-9]+\.[0-9]+' | sort -V); do
            if systemctl is-active --quiet "$(php_fpm_service "$v")" 2>/dev/null; then
                php_fpm_restart_safe "$v" || rc=1
            fi
        done
    fi
    return $rc
}

# Reload mọi PHP-FPM đang chạy (xoá OPcache) - không phụ thuộc tên service theo distro
_oc_reload_all_php_fpm() {
    local u
    for u in $(systemctl list-units --type=service --state=running --no-legend 2>/dev/null | awk '{print $1}' | grep -E '^php.*fpm.*\.service$'); do
        systemctl reload "$u" 2>/dev/null || true
    done
}

# Cài + bật PHP extension (redis | memcached) cho mọi PHP-FPM, đúng tên gói theo distro
_oc_ensure_php_ext() {
    local ext=$1 v
    if [[ "$OS_FAMILY" == "rhel" ]]; then
        if ! php -m 2>/dev/null | grep -qix "$ext"; then
            pkg_install "php-pecl-${ext}" &>/dev/null || pkg_install "php-${ext}" &>/dev/null || \
                pkg_install "php-pecl-${ext}5" &>/dev/null || pkg_install "php-pecl-${ext}6" &>/dev/null || true
        fi
        if ! php -m 2>/dev/null | grep -qix "$ext"; then
            log_warn "Chưa cài được PHP extension '$ext' (kiểm tra repo Remi/EPEL)."
            return 1
        fi
    else
        local any=0
        for v in $(ls -d /etc/php/*/fpm 2>/dev/null | grep -oE '[0-9]+\.[0-9]+' | sort -V); do
            if [[ ! -f "/etc/php/$v/mods-available/${ext}.ini" ]]; then
                pkg_install "php${v}-${ext}" &>/dev/null || true
            fi
            if [[ -f "/etc/php/$v/mods-available/${ext}.ini" ]]; then
                phpenmod -v "$v" "$ext" 2>/dev/null || true
                any=1
            fi
        done
        if [[ "$any" -eq 0 ]]; then
            log_warn "Chưa cài được PHP extension '$ext' cho phiên bản PHP nào."
            return 1
        fi
    fi
    _oc_restart_all_php_fpm
}

# Cài Redis / Valkey / KeyDB qua MỘT hiện thực duy nhất (lemp.sh: _install_object_cache_nginx):
# Unix socket 660, www-data trong group của service, TCP tắt. Trả về 1 nếu socket không lên.
# Dùng: _oc_install_server <valkey|redis|keydb>
_oc_install_server() {
    local type=$1
    local module_dir socket_path waited=0
    module_dir="$(dirname "${BASH_SOURCE[0]}")"

    if ! declare -F _install_object_cache_nginx >/dev/null; then
        # shellcheck disable=SC1091
        source "$module_dir/lemp.sh" || { log_error "Không nạp được modules/lemp.sh"; return 1; }
    fi

    pkg_update &>/dev/null || true
    if ! _install_object_cache_nginx "$type"; then
        log_error "Cài đặt $type thất bại."
        return 1
    fi

    socket_path=$(_oc_socket_path "$type")
    while [[ ! -S "$socket_path" ]] && [[ $waited -lt 8 ]]; do
        sleep 1; waited=$((waited + 1))
    done
    if [[ ! -S "$socket_path" ]]; then
        local svc
        svc=$(cache_service_name 2>/dev/null || echo "$type")
        log_error "$type không tạo được socket $socket_path. Kiểm tra: journalctl -u $svc -n 30"
        return 1
    fi

    _oc_ensure_php_ext redis || true
    return 0
}

# =============================================================================
# Cài đặt Object Cache (Valkey / Redis / KeyDB) + bật cho WordPress
# =============================================================================

install_object_cache() {
    echo -e "${BLUE}=================================================${NC}"
    echo -e "${GREEN}     Cài đặt Object Cache Server${NC}"
    echo -e "${BLUE}=================================================${NC}"
    echo -e "1. Valkey (khuyên dùng - mã nguồn mở, tương thích Redis; tự chuyển sang Redis nếu OS chưa có gói)"
    echo -e "2. Redis"
    echo -e "0. Huỷ"
    echo -e "${BLUE}=================================================${NC}"
    read -p "Chọn loại cache [0-2]: " cache_choice

    local object_cache
    case $cache_choice in
        1) object_cache="valkey" ;;
        2) object_cache="redis" ;;
        0) return ;;
        *) echo -e "${RED}Lựa chọn không hợp lệ!${NC}"; pause; return ;;
    esac

    # Đã có sẵn 1 server cache khác loại -> hỏi trước, tránh chạy 2 server song song
    local existing existing_type
    existing=$(cache_service_name 2>/dev/null || true)
    if [[ -n "$existing" ]]; then
        existing_type=$(_oc_type_from_service "$existing")
        if [[ "$existing_type" != "$object_cache" ]]; then
            echo -e "${YELLOW}Server đã có sẵn: ${existing}. Cài thêm ${object_cache} sẽ chạy 2 cache server song song (tốn RAM).${NC}"
            read -p "Vẫn tiếp tục cài ${object_cache}? [y/N]: " go_on
            [[ "$go_on" != "y" && "$go_on" != "Y" ]] && return
        fi
    fi

    log_info "Cài đặt Object Cache: $object_cache..."
    if ! _oc_install_server "$object_cache"; then
        log_error "Chưa cài xong $object_cache - KHÔNG thay đổi wp-config.php của website nào."
        pause; return
    fi

    local socket_path
    socket_path=$(_oc_socket_path "$object_cache")
    log_info "✓ $object_cache đang chạy với Unix Socket: $socket_path"

    echo -e "${YELLOW}Bật Object Cache cho website WordPress (ghi wp-config.php + cài plugin Redis Object Cache)?${NC}"
    echo -e "  1. Áp dụng cho TẤT CẢ website WordPress"
    echo -e "  2. Chọn website cụ thể"
    echo -e "  0. Không (Tôi tự cấu hình thủ công)"
    read -p "Chọn [0-2]: " apply_choice

    local targets=() d ok=0
    if [[ "$apply_choice" == "1" ]]; then
        targets=($(_wp_list_sites))
    elif [[ "$apply_choice" == "2" ]]; then
        source "$(dirname "${BASH_SOURCE[0]}")/site.sh"
        select_site || { pause; return; }
        targets=("$SELECTED_DOMAIN")
    fi

    for d in "${targets[@]}"; do
        if ! _wp_redis_write_config "$d" "$socket_path"; then
            log_warn "[$d] Không tìm thấy / không ghi được wp-config.php - bỏ qua."
            continue
        fi
        _wp_redis_enable_plugin "$d" || true
        _wp_cache_flush_site "$d"
        ok=$((ok + 1))
    done
    [[ ${#targets[@]} -gt 0 ]] && log_info "Đã cấu hình Object Cache cho $ok/${#targets[@]} website."
    echo -e "${CYAN}Kiểm tra kết nối: WP Admin -> Settings -> Redis (plugin dùng được cho Redis/Valkey/KeyDB).${NC}"
    pause
}

fix_redis_connection() {
    source "$(dirname "${BASH_SOURCE[0]}")/site.sh"
    select_site || return
    local domain=$SELECTED_DOMAIN
    local wp_config
    wp_config=$(_wp_config_path "$domain")

    if [[ -z "$wp_config" ]]; then
        echo -e "${RED}Không tìm thấy wp-config.php cho $domain${NC}"
        pause; return
    fi

    echo -e "${CYAN}Đang kiểm tra trạng thái Object Cache Server (Valkey/Redis/KeyDB)...${NC}"

    # 1. Đã cài server nào chưa? (Valkey/KeyDB cũng tính - không cài Redis chồng lên)
    local svc
    svc=$(cache_service_name 2>/dev/null || true)
    if [[ -z "$svc" ]]; then
        echo -e "${RED}CẢNH BÁO: Chưa có Redis/Valkey/KeyDB nào trên VPS!${NC}"
        read -p "Cài đặt Valkey (tương thích 100% Redis) + PHP Extension ngay? (y/n): " install_opt
        if [[ "$install_opt" != "y" ]]; then return; fi
        if ! _oc_install_server valkey; then
            pause; return
        fi
        svc=$(cache_service_name 2>/dev/null || true)
        [[ -z "$svc" ]] && { log_error "Không xác định được service cache sau khi cài."; pause; return; }
    fi
    echo -e "Service: ${GREEN}${svc}${NC}"

    # 2. Service có đang chạy không
    if ! systemctl is-active --quiet "$svc"; then
        echo -e "${YELLOW}${svc} đang tắt. Đang bật lại...${NC}"
        systemctl unmask "$svc" 2>/dev/null
        systemctl enable "$svc" 2>/dev/null
        systemctl start "$svc"
        sleep 1
        if ! systemctl is-active --quiet "$svc"; then
            echo -e "${RED}LỖI NGHIÊM TRỌNG: Không thể khởi động ${svc}. Hãy kiểm tra 'journalctl -u ${svc} -n 30'.${NC}"
            pause; return
        fi
    fi

    # 3. Xác định cách kết nối
    local socket_path use_socket=false
    socket_path=$(_oc_current_socket "$svc")
    if [[ -n "$socket_path" ]]; then
        use_socket=true
        if [[ ! -S "$socket_path" ]]; then
            echo -e "${YELLOW}Cấu hình dùng Socket nhưng $socket_path không tồn tại. Đang restart ${svc}...${NC}"
            systemctl restart "$svc"
            sleep 2
            if [[ ! -S "$socket_path" ]]; then
                echo -e "${RED}Vẫn không thấy socket.${NC}"
                use_socket=false
            fi
        fi
    fi

    if [[ "$use_socket" != "true" ]]; then
        # TCP chỉ dùng được khi server thật sự đang nghe 6379
        local conf_file port_line=""
        conf_file=$(_oc_conf_file "$svc" || true)
        [[ -n "$conf_file" ]] && port_line=$(awk '$1=="port"{print $2}' "$conf_file" | tail -n 1)
        if [[ "$port_line" == "0" ]]; then
            log_error "${svc} đã tắt TCP (port 0) và socket không hoạt động. Chưa sửa wp-config.php."
            echo -e "Kiểm tra: journalctl -u ${svc} -n 30"
            pause; return
        fi
    fi

    # 4. Ghi lại wp-config.php (một bộ hằng số thống nhất)
    echo -e "${YELLOW}Đang cấu hình lại kết nối cho WordPress...${NC}"
    if [[ "$use_socket" == "true" ]]; then
        echo -e "-> Chế độ: ${GREEN}Unix Socket ($socket_path)${NC}"
        if ! _wp_redis_write_config "$domain" "$socket_path"; then
            log_error "Không ghi được $wp_config"; pause; return
        fi
        # Quyền: KHÔNG chmod 777. Cho user chạy PHP của site vào group sở hữu socket.
        local sock_group php_user
        sock_group=$(stat -c %G "$socket_path" 2>/dev/null)
        php_user=$(site_owner "/var/www/$domain/public_html")
        if [[ -n "$sock_group" && "$sock_group" != "UNKNOWN" ]] && ! id -nG "$php_user" 2>/dev/null | tr ' ' '\n' | grep -qx "$sock_group"; then
            usermod -aG "$sock_group" "$php_user" 2>/dev/null
            log_info "Đã thêm $php_user vào group $sock_group."
            # PHP-FPM phải restart mới nhận group mới
            _oc_restart_all_php_fpm || log_warn "Có PHP-FPM chưa restart được - group mới chưa có hiệu lực."
        fi
        chmod g+rw "$socket_path" 2>/dev/null
    else
        echo -e "-> Chế độ: ${YELLOW}TCP (127.0.0.1:6379)${NC}"
        if ! _wp_redis_write_config "$domain" ""; then
            log_error "Không ghi được $wp_config"; pause; return
        fi
    fi

    _wp_cache_flush_site "$domain"
    echo -e "${GREEN}Đã sửa cấu hình kết nối xong!${NC}"
    pause
}

setup_object_cache_pro() {
    log_info "Đang tối ưu Server cho Object Cache Pro..."

    # 1. System Tuning (Overcommit Memory) - ghi vào drop-in riêng, không sửa /etc/sysctl.conf
    local sysctl_file="/etc/sysctl.d/99-vps-manager-overcommit.conf"
    if [[ "$(sysctl -n vm.overcommit_memory 2>/dev/null)" != "1" ]]; then
        echo "vm.overcommit_memory = 1" > "$sysctl_file"
        sysctl -p "$sysctl_file" >/dev/null 2>&1
        log_info "Đã bật vm.overcommit_memory = 1"
    fi

    # 2. Redis/Valkey/KeyDB tuning
    local svc conf_file
    svc=$(cache_service_name 2>/dev/null || true)
    conf_file=""
    [[ -n "$svc" ]] && conf_file=$(_oc_conf_file "$svc" || true)

    if [[ -n "$conf_file" ]]; then
        local bak="${conf_file}.bak_ocp"
        cp -p "$conf_file" "$bak"

        # maxmemory-policy allkeys-lru (không đụng maxmemory người dùng đã đặt)
        if grep -q "^maxmemory-policy" "$conf_file"; then
            sed -i "s/^maxmemory-policy.*/maxmemory-policy allkeys-lru/" "$conf_file"
        else
            echo "maxmemory-policy allkeys-lru" >> "$conf_file"
        fi

        if systemctl restart "$svc" && sleep 1 && systemctl is-active --quiet "$svc"; then
            rm -f "$bak"
            log_info "Đã cấu hình ${svc}: maxmemory-policy allkeys-lru"
        else
            cp -p "$bak" "$conf_file"
            systemctl restart "$svc" 2>/dev/null
            log_error "${svc} không khởi động lại được với cấu hình mới - đã khôi phục cấu hình cũ."
        fi
    else
        log_warn "Chưa cài Redis/Valkey/KeyDB (dùng mục 8 để cài)."
    fi

    # 3. PHP Redis extension
    if _oc_ensure_php_ext redis; then
        echo -e "${GREEN}Hoàn tất tối ưu cho Object Cache Pro!${NC}"
    else
        echo -e "${YELLOW}Server đã chỉnh xong nhưng PHP extension redis chưa sẵn sàng - xem cảnh báo ở trên.${NC}"
    fi
    echo -e "Lưu ý: Bạn cần cài đặt plugin Object Cache Pro trong WordPress và điền key bản quyền."
    pause
}

clear_all_cache() {
    log_info "Đang xóa Nginx FastCGI Cache..."
    # Chỉ xoá nội dung thư mục fastcgi cache - KHÔNG xoá /var/cache/nginx/* (client_temp, proxy_temp...
    # của nginx nằm ở đó; xoá khi nginx đang chạy sẽ làm lỗi upload cho tới khi restart)
    local d cache_user
    for d in /var/cache/nginx/fastcgi /var/run/nginx-cache; do
        [[ -d "$d" ]] && find "$d" -mindepth 1 -delete 2>/dev/null
    done
    mkdir -p /var/cache/nginx/fastcgi
    cache_user=$(nginx_worker_user)
    chown -R "$cache_user" /var/cache/nginx/fastcgi 2>/dev/null || true
    systemctl reload nginx 2>/dev/null

    local svc cli sock
    svc=$(cache_service_name 2>/dev/null || true)
    if [[ -n "$svc" ]] && cli=$(_oc_cli "$svc"); then
        log_info "Đang Flush ${svc}..."
        sock=$(_oc_current_socket "$svc")
        if [[ -n "$sock" && -S "$sock" ]]; then
            "$cli" -s "$sock" flushall >/dev/null 2>&1 || log_warn "Flush ${svc} qua socket thất bại."
        else
            "$cli" flushall >/dev/null 2>&1 || log_warn "Flush ${svc} thất bại."
        fi
    fi

    log_info "Đang reload PHP-FPM (Clear OPcache)..."
    _oc_reload_all_php_fpm

    log_info "Đang xóa thư mục Cache của plugin (WP Rocket, W3TC...)"
    local domain cdir
    for domain in $(_wp_list_sites); do
        cdir="/var/www/$domain/public_html/wp-content/cache"
        [[ -d "$cdir" ]] && find "$cdir" -mindepth 1 -delete 2>/dev/null
    done

    log_info "Đang Flush Object Cache & Transients bằng WP-CLI..."
    for domain in $(_wp_list_sites); do
        _wp_cache_flush_site "$domain"
    done

    log_info "Đã xóa sạch Cache hệ thống từ Server."
    pause
}

toggle_extension() {
    local ext=$1

    # ── RHEL / Oracle Linux: 1 bản PHP (module stream), không có phpenmod ──
    if [[ "$OS_FAMILY" == "rhel" ]]; then
        echo -e "Trạng thái mong muốn cho PHP extension '$ext':"
        echo -e "1. BẬT (Enable/On)"
        echo -e "2. TẮT (Disable/Off)"
        read -p "Chọn [1-2]: " state_choice
        local f changed=0
        case "$state_choice" in
            1)
                for f in /etc/php.d/*-"$ext".ini.disabled; do
                    [[ -f "$f" ]] && mv "$f" "${f%.disabled}" && changed=1
                done
                if ! ls /etc/php.d/*-"$ext".ini &>/dev/null; then
                    echo -e "${YELLOW}Extension $ext chưa được cài. Đang cài đặt...${NC}"
                    pkg_install "php-${ext}" &>/dev/null || pkg_install "php-pecl-${ext}" &>/dev/null || true
                fi
                if ! ls /etc/php.d/*-"$ext".ini &>/dev/null; then
                    log_error "Không cài được php-$ext."
                    pause; return
                fi
                ;;
            2)
                for f in /etc/php.d/*-"$ext".ini; do
                    [[ -f "$f" ]] && mv "$f" "${f}.disabled" && changed=1
                done
                [[ "$changed" -eq 0 ]] && log_warn "Extension $ext vốn đang tắt / chưa cài."
                ;;
            *) echo -e "${RED}Lựa chọn không hợp lệ!${NC}"; pause; return ;;
        esac
        if php_fpm_restart_safe; then
            log_info "Đã cấu hình $ext -> $([[ "$state_choice" == "1" ]] && echo on || echo off)."
        else
            log_error "PHP-FPM không restart được sau khi đổi $ext - xem lỗi ở trên."
        fi
        pause; return
    fi

    # ── Debian / Ubuntu ──
    local versions=()
    local ver_dir ver

    if [[ -d /etc/php ]]; then
        for ver_dir in /etc/php/*/; do
            [[ -d "$ver_dir" ]] || continue
            ver=$(basename "$ver_dir")
            [[ "$ver" =~ ^[0-9]+\.[0-9]+$ ]] && versions+=("$ver")
        done
    fi

    if [[ ${#versions[@]} -eq 0 ]]; then
        log_error "Không tìm thấy phiên bản PHP nào trong /etc/php."
        pause; return
    fi
    IFS=$'\n' versions=($(printf '%s\n' "${versions[@]}" | sort -rV))
    unset IFS

    echo -e "Chọn phiên bản PHP để cấu hình $ext:"
    local idx=1
    for ver in "${versions[@]}"; do
        echo -e "$idx) PHP $ver"
        idx=$((idx + 1))
    done
    echo -e "$idx) Tất cả"
    read -p "Chọn: " v

    if ! [[ "$v" =~ ^[0-9]+$ ]]; then
        return
    fi
    local targets=()
    if [[ "$v" -eq "$idx" ]]; then
        targets=("${versions[@]}")
    elif [[ "$v" -ge 1 && "$v" -lt "$idx" ]]; then
        targets=("${versions[$((v - 1))]}")
    else
        return
    fi

    echo -e "Trạng thái mong muốn:"
    echo -e "1. BẬT (Enable/On)"
    echo -e "2. TẮT (Disable/Off)"
    read -p "Chọn [1-2]: " state_choice

    local state action
    if [[ "$state_choice" == "1" || "$state_choice" == "on" || "$state_choice" == "y" || "$state_choice" == "yes" ]]; then
        state="on"
        action="phpenmod"
    elif [[ "$state_choice" == "2" || "$state_choice" == "off" || "$state_choice" == "n" || "$state_choice" == "no" ]]; then
        state="off"
        action="phpdismod"
    else
        echo -e "${RED}Lựa chọn không hợp lệ!${NC}"
        pause; return
    fi

    local failed=0 t
    for t in "${targets[@]}"; do
        # Cài gói theo đúng phiên bản nếu thiếu (chỉ khi BẬT)
        if [[ "$state" == "on" && ! -f "/etc/php/$t/mods-available/$ext.ini" ]]; then
            echo -e "${YELLOW}Cài đặt thêm php$t-$ext...${NC}"
            pkg_install "php$t-$ext" &>/dev/null || true
        fi
        if [[ ! -f "/etc/php/$t/mods-available/$ext.ini" ]]; then
            [[ "$state" == "on" ]] && { log_warn "PHP $t: không có extension $ext - bỏ qua."; failed=1; }
            continue
        fi
        $action -v "$t" "$ext" 2>/dev/null || failed=1
        if systemctl is-active --quiet "$(php_fpm_service "$t")" 2>/dev/null; then
            php_fpm_restart_safe "$t" || failed=1
        fi
    done

    if [[ "$failed" -eq 0 ]]; then
        log_info "Đã cấu hình $ext -> $state."
    else
        log_warn "Cấu hình $ext -> $state chưa hoàn tất cho mọi phiên bản - xem thông báo ở trên."
    fi
    pause
}

setup_rocket_nginx() {
    log_info "Đang tạo cấu hình Nginx cho WP Rocket..."
    mkdir -p /etc/nginx/snippets
    local snippet="/etc/nginx/snippets/wp-rocket.conf"

    # Snippet đặt ở cấp server (include ngay sau server_name).
    # $rocket_file / $rocket_file_http chỉ trỏ tới file HTML tĩnh khi request là GET, không có
    # query string và khách CHƯA đăng nhập / không có giỏ hàng. Các trường hợp khác trỏ tới 1 đường
    # dẫn không tồn tại -> try_files rơi xuống PHP như bình thường (POST không còn bị 405,
    # người đăng nhập không còn nhận HTML của khách).
    cat > "$snippet" <<'EOF'
# WP Rocket - phuc vu HTML tinh co dieu kien (vps-manager)
set $rocket_bypass 0;
if ($request_method != GET) { set $rocket_bypass 1; }
if ($query_string != "") { set $rocket_bypass 1; }
if ($http_cookie ~* "wordpress_logged_in_|wp-postpass_|comment_author_|woocommerce_items_in_cart|woocommerce_cart_hash|wptouch_switch_toggle") { set $rocket_bypass 1; }
set $rocket_file "/wp-content/cache/wp-rocket/$http_host$request_uri/index-https.html";
set $rocket_file_http "/wp-content/cache/wp-rocket/$http_host$request_uri/index.html";
if ($rocket_bypass = 1) {
    set $rocket_file "/.vps-rocket-bypass";
    set $rocket_file_http "/.vps-rocket-bypass";
}

# WP Rocket Headers
location ~ /wp-content/cache/wp-rocket/.*html$ {
    etag on;
    add_header Vary "Accept-Encoding, Cookie";
    add_header Cache-Control "no-cache, no-store, must-revalidate";
    add_header X-WP-Rocket "Served";
}

location ~ /wp-content/cache/min/.*(js|css)$ {
    etag on;
    add_header Vary "Accept-Encoding";
    add_header Cache-Control "max-age=31536000, public";
}
EOF

    echo -e "${YELLOW}Bạn có muốn tự động áp dụng cấu hình này cho website không?${NC}"
    echo -e "  1. Áp dụng cho TẤT CẢ website WordPress"
    echo -e "  2. Chọn website cụ thể"
    echo -e "  0. Không (Chỉ tạo file snippet)"
    read -p "Chọn: " c

    if [[ "$c" == "0" ]]; then return; fi

    # Áp dụng cho 1 vhost: thêm include + đổi try_files, test, lỗi thì hoàn tác vhost đó.
    apply_rocket() {
        local domain=$1
        local conf="/etc/nginx/sites-available/$domain"
        [[ -f "$conf" ]] || return 1

        # try_files gốc của vhost, và bản "blanket" do phiên bản cũ của script tạo ra
        local plain_re='try_files \$uri \$uri/ /index\.php?\$args;'
        local old_re='try_files /wp-content/cache/wp-rocket/\$http_host\$request_uri/index-https\.html /wp-content/cache/wp-rocket/\$http_host\$request_uri/index\.html \$uri \$uri/ /index\.php?\$args;'
        local new_tf='try_files $rocket_file $rocket_file_http $uri $uri/ /index.php?$args;'

        local bak
        bak=$(backup_nginx_config "$conf")

        if ! grep -qF "include $snippet;" "$conf"; then
            sed -i "/server_name/a \    include $snippet;" "$conf"
        fi
        sed -i "s|${old_re}|${new_tf}|" "$conf"
        sed -i "s|${plain_re}|${new_tf}|" "$conf"

        if ! grep -qF 'try_files $rocket_file ' "$conf"; then
            log_warn "$domain: không thấy dòng try_files chuẩn - chỉ thêm header, HTML tĩnh sẽ do PHP phục vụ."
        fi

        if nginx_commit "$conf" "$bak"; then
            rm -f "$conf.bak_rocket"
            log_info "Đã áp dụng WP Rocket cho $domain"
            return 0
        fi
        log_error "$domain: áp dụng thất bại, vhost đã được khôi phục."
        return 1
    }

    if [[ "$c" == "1" ]]; then
        local applied=0 skipped=0 failed=0 conf d
        for conf in /etc/nginx/sites-available/*; do
            d=$(basename "$conf")
            if _is_real_site "$d"; then
                if apply_rocket "$d"; then applied=$((applied+1)); else failed=$((failed+1)); fi
            else
                echo -e "  ${YELLOW}Bỏ qua: $d${NC}"
                skipped=$((skipped+1))
            fi
        done
        echo -e "${GREEN}Áp dụng: $applied site${NC} | ${RED}Lỗi: $failed${NC} | Bỏ qua: $skipped file không hợp lệ"
    elif [[ "$c" == "2" ]]; then
        source "$(dirname "${BASH_SOURCE[0]}")/site.sh"
        select_site || return
        apply_rocket "$SELECTED_DOMAIN"
    fi

    pause
}

setup_w3tc_nginx() {
    log_info "Đang tạo cấu hình Nginx cho W3 Total Cache..."
    mkdir -p /etc/nginx/snippets
    local snippet="/etc/nginx/snippets/w3tc.conf"

    cat > "$snippet" <<'EOF'
# W3TC Nginx Config
location ~ /wp-content/cache/.*(html|xml|json)$ {
    add_header Vary "Accept-Encoding, Cookie";
    add_header Cache-Control "max-age=3600, must-revalidate";
}

location ~ /wp-content/cache/minify/.*(js|css)$ {
    add_header Cache-Control "max-age=31536000, public";
    add_header Vary "Accept-Encoding";
}
EOF

    echo -e "${YELLOW}Bạn có muốn tự động áp dụng cho website?${NC}"
    echo -e "  1. Áp dụng cho TẤT CẢ website WordPress"
    echo -e "  2. Chọn website cụ thể"
    echo -e "  0. Không"
    read -p "Chọn: " c

    if [[ "$c" == "0" ]]; then return; fi

    apply_w3tc() {
        local domain=$1
        local conf="/etc/nginx/sites-available/$domain"
        [[ -f "$conf" ]] || return 1
        if nginx_add_include "$conf" "$snippet"; then
            log_info "Đã áp dụng W3TC cho $domain"
            return 0
        fi
        log_error "$domain: áp dụng W3TC thất bại, vhost đã được khôi phục."
        return 1
    }

    if [[ "$c" == "1" ]]; then
        local applied=0 skipped=0 failed=0 conf d
        for conf in /etc/nginx/sites-available/*; do
            d=$(basename "$conf")
            if _is_real_site "$d"; then
                if apply_w3tc "$d"; then applied=$((applied+1)); else failed=$((failed+1)); fi
            else
                echo -e "  ${YELLOW}Bỏ qua: $d${NC}"
                skipped=$((skipped+1))
            fi
        done
        echo -e "${GREEN}Áp dụng: $applied site${NC} | ${RED}Lỗi: $failed${NC} | Bỏ qua: $skipped file không hợp lệ"
    elif [[ "$c" == "2" ]]; then
        source "$(dirname "${BASH_SOURCE[0]}")/site.sh"
        select_site || return
        apply_w3tc "$SELECTED_DOMAIN"
    fi
    pause
}

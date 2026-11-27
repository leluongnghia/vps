#!/bin/bash

# modules/site.sh - Site & Domain Management

manage_sites_menu() {
    while true; do
        clear
        echo -e "${BLUE}=================================================${NC}"
        echo -e "${GREEN}          Quản lý Website & Tên miền${NC}"
        echo -e "${BLUE}=================================================${NC}"
        echo -e "1. Danh sách Tên miền"
        echo -e "2. Thêm Tên miền mới"
        echo -e "3. Xóa Tên miền"
        echo -e "4. Thay đổi Tên miền (Rename Domain)"
        echo -e "5. Cấu hình lại Nginx (Rewrite Vhost)"
        echo -e "6. Parked/Alias Domain"
        echo -e "7. Đổi phiên bản PHP cho Website"
        echo -e "8. Clone/Nhân bản Website"
        echo -e "9. Đổi thông tin Database (wp-config)"
        echo -e "10. Đặt mật khẩu bảo vệ thư mục"
        echo -e "11. Fix Permissions"
        echo -e "12. Kiểm tra/Sửa lỗi WordPress Core"
        echo -e "13. Bật/Tắt FastCGI Cache (Dev Mode)"
        echo -e "0. Quay lại Menu chính"
        echo -e "${BLUE}=================================================${NC}"
        read -p "Nhập lựa chọn [0-13]: " choice

        case $choice in
            1) list_sites ;;
            2) 
                echo -e "1. WordPress\n2. PHP Thuần\n3. Node.js (Host + PM2)\n4. Docker Proxy\n0. Quay lại"
                read -p "Chọn loại [0-4]: " t
                if [[ "$t" == "1" ]]; then add_new_site "wordpress"; elif [[ "$t" == "2" ]]; then add_new_site "php"; elif [[ "$t" == "3" ]]; then add_new_site "nodejs"; elif [[ "$t" == "4" ]]; then add_new_site "docker_proxy"; elif [[ "$t" == "0" ]]; then continue; else echo -e "${RED}Lựa chọn không hợp lệ!${NC}"; pause; fi
                ;;
            3) delete_site ;;
            4) rename_site ;;
            5) rewrite_vhost_config ;;
            6) manage_parked_domains ;;
            7) change_site_php ;;
            8) clone_site ;;
            9) update_site_db_info ;;
            10) protect_folder ;;
            11) fix_permissions ;;
            12) check_wp_core ;;
            13) toggle_site_cache ;;
            0) return ;;
            *) echo -e "${RED}Lựa chọn không hợp lệ!${NC}"; pause ;;
        esac
    done
}

# ==============================================================================
# Helper nội bộ của module site
# ==============================================================================

# true nếu là domain gốc (apex) - chỉ domain gốc mới thêm www.
# Nhận biết cả đuôi 2 cấp phổ biến (example.com.vn, example.co.uk...)
_site_is_apex_domain() {
    local domain="$1" dots
    dots=$(printf '%s' "$domain" | tr -cd '.' | wc -c)
    if [[ "$dots" -eq 1 ]]; then return 0; fi
    if [[ "$dots" -eq 2 ]] && [[ "$domain" =~ \.(com|net|org|edu|gov|biz|info|name|pro|health|int|ac|co)\.[a-z]{2}$ ]]; then
        return 0
    fi
    return 1
}

# server_name mặc định cho 1 domain (subdomain thì không thêm www.)
_site_server_names() {
    local domain="$1"
    if _site_is_apex_domain "$domain"; then
        echo "$domain www.$domain"
    else
        echo "$domain"
    fi
}

# Cổng hợp lệ 1-65535
_site_valid_port() {
    [[ "$1" =~ ^[0-9]{1,5}$ ]] && [[ "$1" -ge 1 ]] && [[ "$1" -le 65535 ]]
}

# Tìm bản PHP CLI có sẵn mysqli (WP-CLI cần) - tránh lỗi thiếu extension của PHP mặc định
_site_find_wp_php() {
    local bin
    for bin in php8.4 php8.3 php8.2 php8.1 php8.0 php7.4 php; do
        if command -v "$bin" &>/dev/null && "$bin" -m 2>/dev/null | grep -qi mysqli; then
            echo "$bin"; return 0
        fi
    done
    echo "php"
}

# Tiền tố lệnh WP-CLI cho 1 web root: chạy bằng user sở hữu site, KHÔNG dùng --allow-root
_site_wp_cmd() {
    wp_cmd_prefix "$1" "$(_site_find_wp_php)"
}

# Loại vhost: php | proxy | unknown
_site_vhost_type() {
    local conf=$1
    [[ -f "$conf" ]] || { echo "unknown"; return; }
    if grep -v '^[[:space:]]*#' "$conf" | grep -q 'fastcgi_pass'; then
        echo "php"
    elif grep -v '^[[:space:]]*#' "$conf" | grep -q 'proxy_pass'; then
        echo "proxy"
    else
        echo "unknown"
    fi
}

# Dòng include security headers (rỗng nếu snippet chưa tồn tại, để vhost không lỗi)
_site_sec_headers_include() {
    if [[ -f /etc/nginx/snippets/security-headers.conf ]]; then
        echo "include /etc/nginx/snippets/security-headers.conf;"
    fi
}

# Bật vhost: tạo symlink, test, reload. Lỗi -> khôi phục backup (nếu có) hoặc gỡ khỏi sites-enabled.
# Dùng: _site_enable_vhost <domain> [backup_file]
_site_enable_vhost() {
    local domain=$1 backup=${2:-}
    local config_file="/etc/nginx/sites-available/$domain"
    rm -f "/etc/nginx/sites-enabled/$domain"
    ln -s "$config_file" "/etc/nginx/sites-enabled/$domain"
    selinux_restore "$config_file" "/etc/nginx/sites-enabled/$domain"
    nginx_commit "$config_file" "$backup"
}

# Cấu hình FastCGI cache toàn cục (idempotent) + nâng cấp cấu hình cũ
_site_setup_fastcgi_cache_global() {
    local cache_conf="/etc/nginx/conf.d/fastcgi_cache.conf"
    local cache_dir="/var/cache/nginx/fastcgi"
    local worker_user
    worker_user=$(nginx_worker_user)

    # Thư mục cache phải thuộc user của nginx worker. Chỉ chown khi sai chủ,
    # không chown -R mỗi lần thêm site (làm worker mất quyền với cache đang có).
    mkdir -p "$cache_dir"
    if [[ "$(stat -c %U "$cache_dir" 2>/dev/null)" != "$worker_user" ]]; then
        chown -R "$worker_user" "$cache_dir" 2>/dev/null || true
    fi

    if [[ -f "$cache_conf" ]]; then
        sed -i 's|/var/run/nginx-cache|/var/cache/nginx/fastcgi|g' "$cache_conf"
        # Nâng cấp: KHÔNG bỏ qua Set-Cookie nữa. Nếu bỏ qua, trang có Set-Cookie bị cache
        # và cookie phiên của khách này sẽ bị phát lại cho khách khác.
        if grep -qE '^[[:space:]]*fastcgi_ignore_headers.*Set-Cookie' "$cache_conf"; then
            sed -i -E '/^[[:space:]]*fastcgi_ignore_headers/ s/[[:space:]]+Set-Cookie//' "$cache_conf"
            sed -i -E '/^[[:space:]]*fastcgi_ignore_headers[[:space:]]*;/d' "$cache_conf"
            log_info "Đã nâng cấp fastcgi_cache.conf: không còn cache response có Set-Cookie."
        fi
    else
        log_info "Đang khởi tạo cấu hình FastCGI Cache Global..."
        # Kích thước tự tính theo RAM và dung lượng đĩa trống của VPS (core/reliability.sh)
        local cache_zone_mb cache_max_mb
        read -r cache_zone_mb cache_max_mb <<< "$(fastcgi_cache_sizing)"
        cat > "$cache_conf" <<EOF
fastcgi_cache_path /var/cache/nginx/fastcgi levels=1:2 keys_zone=WORDPRESS:${cache_zone_mb:-16}m inactive=60m max_size=${cache_max_mb:-1024}m;
fastcgi_cache_key "\$scheme\$request_method\$host\$request_uri";
fastcgi_cache_use_stale error timeout updating invalid_header http_500 http_503;
fastcgi_cache_background_update on;
fastcgi_cache_lock on;
# Không ignore Set-Cookie: response có Set-Cookie sẽ KHÔNG được cache (tránh lộ phiên giữa các khách)
fastcgi_ignore_headers Cache-Control Expires;
EOF
    fi
    selinux_restore "$cache_conf"
    # Biến $vpsm_cache_refresh (dùng trong vhost WordPress) và các cấu hình toàn cục khác phải có trước khi tạo vhost
    setup_nginx_globals || true
}

# Tham số bổ sung cho fastcgi_cache_bypass: chỉ thêm khi map $vpsm_cache_refresh đã tồn tại
_site_cache_refresh_var() {
    if grep -qs 'vpsm_cache_refresh' /etc/nginx/conf.d/vps-manager-cache-refresh.conf; then
        echo ' $vpsm_cache_refresh'
    fi
}

# Xoá pool PHP-FPM riêng của 1 domain (mọi phiên bản PHP) và restart FPM tương ứng
_site_remove_fpm_pools() {
    local domain=$1 pool_file ver
    for pool_file in /etc/php/*/fpm/pool.d/"${domain}".conf /etc/php-fpm.d/"${domain}".conf; do
        [[ -f "$pool_file" ]] || continue
        ver=$(echo "$pool_file" | grep -oE '/etc/php/[0-9]+\.[0-9]+/' | grep -oE '[0-9]+\.[0-9]+')
        rm -f "$pool_file"
        php_fpm_restart_safe "$ver" >/dev/null 2>&1 || true
        log_info "  ✓ Đã xóa PHP-FPM pool: $pool_file"
    done
}

# Tên DB các site KHÁC đang dùng (để không drop nhầm DB dùng chung)
_site_db_used_by_other() {
    local domain=$1 db_name=$2 d other f name
    for d in /var/www/*; do
        [[ -d "$d" ]] || continue
        other=$(basename "$d")
        [[ "$other" == "$domain" || "$other" == "html" ]] && continue
        for f in "$d/public_html/wp-config.php" "$d/wp-config.php"; do
            name=$(wp_config_get "$f" DB_NAME 2>/dev/null)
            [[ -n "$name" && "$name" == "$db_name" ]] && return 0
        done
    done
    local data_file="$HOME/.vps-manager/sites_data.conf"
    if [[ -f "$data_file" ]] && awk -F'|' -v d="$domain" -v n="$db_name" '$1!=d && $2==n {found=1} END{exit !found}' "$data_file"; then
        return 0
    fi
    return 1
}

# Xác định DB + user THẬT của 1 site. Kết quả: biến SITE_DB_NAME, SITE_DB_USER (rỗng nếu không chắc chắn).
# Ưu tiên: wp-config.php -> sites_data.conf -> tên suy từ domain (chỉ khi không site nào khác dùng tên đó)
_site_resolve_db() {
    local domain=$1 f
    local data_file="$HOME/.vps-manager/sites_data.conf"
    SITE_DB_NAME=""; SITE_DB_USER=""

    for f in "/var/www/$domain/public_html/wp-config.php" "/var/www/$domain/wp-config.php"; do
        if [[ -f "$f" ]]; then
            SITE_DB_NAME=$(wp_config_get "$f" DB_NAME)
            SITE_DB_USER=$(wp_config_get "$f" DB_USER)
            [[ -n "$SITE_DB_NAME" ]] && break
        fi
    done
    if [[ -z "$SITE_DB_NAME" && -f "$data_file" ]]; then
        SITE_DB_NAME=$(awk -F'|' -v d="$domain" '$1==d{print $2; exit}' "$data_file")
        SITE_DB_USER=$(awk -F'|' -v d="$domain" '$1==d{print $3; exit}' "$data_file")
    fi
    if [[ -z "$SITE_DB_NAME" ]]; then
        local guess
        guess=$(legacy_db_name "$domain")
        if ! _site_db_used_by_other "$domain" "$guess"; then
            SITE_DB_NAME="$guess"
            SITE_DB_USER="${guess}_u"
        fi
    fi
    if [[ -n "$SITE_DB_NAME" ]] && ! valid_identifier "$SITE_DB_NAME"; then
        SITE_DB_NAME=""; SITE_DB_USER=""
    fi
    # Không bao giờ đụng tới user hệ thống của DB
    case "$SITE_DB_USER" in
        root|wpdbadmin|mysql|mariadb.sys|debian-sys-maint|"") SITE_DB_USER="" ;;
    esac
    [[ -n "$SITE_DB_USER" ]] && ! valid_identifier "$SITE_DB_USER" && SITE_DB_USER=""
    return 0
}

# Search-replace domain trong DB WordPress, an toàn cả khi domain mới CHỨA domain cũ
# (vd example.com -> staging.example.com). Dùng placeholder 2 bước để không thay 2 lần.
# Dùng: _site_wp_search_replace_domain <web_root> <old_domain> <new_domain>
_site_wp_search_replace_domain() {
    local web_root=$1 old=$2 new=$3
    local wp_cmd ph ph_www new_www rc=0
    wp_cmd=$(_site_wp_cmd "$web_root")
    ph="vpsmtmp$(openssl rand -hex 6)x"
    ph_www="${ph}w"
    # www.old -> www.new nếu domain mới là domain gốc, ngược lại gộp về domain mới
    if _site_is_apex_domain "$new"; then new_www="www.$new"; else new_www="$new"; fi

    local sr_opts=(--all-tables-with-prefix --skip-plugins --skip-themes --quiet)
    $wp_cmd search-replace "www.$old" "$ph_www" "${sr_opts[@]}" || rc=1
    $wp_cmd search-replace "$old"     "$ph"     "${sr_opts[@]}" || rc=1
    $wp_cmd search-replace "$ph_www"  "$new_www" "${sr_opts[@]}" || rc=1
    $wp_cmd search-replace "$ph"      "$new"     "${sr_opts[@]}" || rc=1
    return $rc
}

# Cài Node.js: ưu tiên gói của distro nếu đủ mới (>= 18), nếu không mới dùng NodeSource
_site_install_nodejs() {
    if [[ "$OS_FAMILY" == "rhel" ]]; then
        dnf module reset nodejs -y &>/dev/null || true
        dnf module enable nodejs:20 -y &>/dev/null || true
        pkg_install nodejs npm
    else
        local cand
        cand=$(apt-cache policy nodejs 2>/dev/null | awk '/Candidate:/{print $2}' | grep -oE '^[0-9]+')
        if [[ -n "$cand" && "$cand" -ge 18 ]]; then
            pkg_install nodejs npm
        else
            # Tải script cài repo về file tạm rồi mới chạy (không pipe thẳng vào bash)
            local ns_script
            ns_script=$(mktemp)
            if safe_download "https://deb.nodesource.com/setup_20.x" "$ns_script"; then
                bash "$ns_script"
                rm -f "$ns_script"
                pkg_install nodejs
            else
                rm -f "$ns_script"
                return 1
            fi
        fi
    fi
    command -v node &>/dev/null
}

# Dọn dẹp khi thêm site thất bại. Chỉ xoá những gì CHÍNH lần chạy này đã tạo.
# Dùng: _site_add_rollback <domain> [db_name] [db_user]
_site_add_rollback() {
    local domain=$1 db_name=${2:-} db_user=${3:-}

    echo -e "\n${YELLOW}⚠️ Đang tự động dọn dẹp tài nguyên bị lỗi (Rollback)...${NC}"

    # 1. Clean root directory
    if [[ -n "$domain" && -d "/var/www/$domain" ]]; then
        rm -rf "/var/www/${domain:?}"
    fi

    # 2. Clean Nginx configurations + pool riêng
    rm -f "/etc/nginx/sites-available/$domain" "/etc/nginx/sites-enabled/$domain"
    rm -f /etc/nginx/sites-available/"$domain".bak_* 2>/dev/null
    _site_remove_fpm_pools "$domain"
    nginx -t &>/dev/null && systemctl reload nginx 2>/dev/null

    # 3. Clean MySQL Database & User - chỉ khi DB do chính lần chạy này tạo ra
    if [[ -n "$db_name" ]] && valid_identifier "$db_name"; then
        drop_database "$db_name" "$db_user"
    fi

    # 4. Clean local persistent sites data
    local data_file="$HOME/.vps-manager/sites_data.conf"
    if [[ -f "$data_file" ]]; then
        local ed
        ed=$(sed_escape_pattern "$domain")
        sed -i "/^${ed}|/d" "$data_file" 2>/dev/null
        sed -i "/^docker:${ed}|/d" "$data_file" 2>/dev/null
    fi

    unset WP_DB_NAME WP_DB_USER WP_DB_PASS
    echo -e "${GREEN}✅ Dọn dẹp hoàn tất.${NC}"
}

add_new_site() {
    local type=$1
    local domain
    echo -e "${GREEN}--- Thêm Website Mới ($type) ---${NC}"
    read -p "Nhập tên miền (ví dụ: example.com): " domain
    domain="${domain,,}"

    # Validate domain format
    if ! validate_domain "$domain"; then
        pause; return
    fi

    # Check disk space (require 2GB free for WordPress)
    if ! check_disk_space "/var/www" 2048; then
        pause; return
    fi

    # Check if site exists
    if [[ -d "/var/www/$domain" ]] || [[ -f "/etc/nginx/sites-available/$domain" ]]; then
        echo -e "${RED}Website $domain đã tồn tại!${NC}"
        pause; return
    fi

    # Không dùng lại thông tin DB của site tạo trước đó trong cùng phiên menu
    unset WP_DB_NAME WP_DB_USER WP_DB_PASS
    # DB do lần chạy này tạo (dùng cho rollback); rỗng = chưa tạo gì
    local created_db="" created_db_user=""

    echo -e "${YELLOW}Đang tạo cấu hình cho $domain...${NC}"

    # 1. Setup Global Cache if missing
    _site_setup_fastcgi_cache_global
    # Reload to apply global cache config first!
    if ! nginx_test_reload; then
        log_error "Nginx đang lỗi cấu hình - sửa lỗi trên trước khi thêm website."
        pause; return
    fi

    # 2. Create web root
    mkdir -p "/var/www/$domain/public_html"
    chown -R www-data:www-data "/var/www/$domain"
    chmod -R 755 "/var/www/$domain"

    # 3. Create Nginx Config
    if [[ "$type" == "nodejs" ]]; then
        # Check and install Node.js / PM2 if missing
        if ! command -v node &> /dev/null || ! command -v pm2 &> /dev/null; then
            echo -e "${YELLOW}Hệ thống phát hiện chưa có Node.js hoặc PM2. Đang tiến hành cài đặt tự động...${NC}"
            if ! command -v node &> /dev/null; then
                if ! _site_install_nodejs; then
                    log_error "Cài Node.js thất bại."
                    _site_add_rollback "$domain"; pause; return
                fi
            fi
            if ! command -v pm2 &> /dev/null; then
                npm install -g pm2 || log_warn "Cài PM2 thất bại. Cài thủ công: npm install -g pm2"
            fi
            echo -e "${GREEN}Cài đặt môi trường Node.js hoàn tất!${NC}"
        fi

        read -p "Nhập Port ứng dụng Node.js (Mặc định 3000): " node_port
        if [[ -z "$node_port" ]]; then node_port="3000"; fi
        if ! _site_valid_port "$node_port"; then
            log_error "Port không hợp lệ: $node_port"
            _site_add_rollback "$domain"; pause; return
        fi
        if ! create_nginx_nodejs_config "$domain" "$node_port"; then
            log_error "Tạo cấu hình Nginx thất bại."
            _site_add_rollback "$domain"; pause; return
        fi

        # Tạo Database MySQL cho dự án Node.js theo yêu cầu
        echo -e "${YELLOW}Tiến hành khởi tạo Database MySQL cho dự án này...${NC}"
        if ! setup_database "$domain"; then
            log_error "Tạo Database thất bại - hủy thêm website."
            _site_add_rollback "$domain"; pause; return
        fi
        created_db="$WP_DB_NAME"; created_db_user="$WP_DB_USER"

        # Tạo sẵn file .env
        cat > "/var/www/$domain/public_html/.env" <<EOF
DB_HOST=127.0.0.1
DB_NAME=$WP_DB_NAME
DB_USER=$WP_DB_USER
DB_PASSWORD=$WP_DB_PASS
JWT_SECRET=$(openssl rand -base64 32)
PORT=$node_port
EOF
        chown www-data:www-data "/var/www/$domain/public_html/.env"
        chmod 600 "/var/www/$domain/public_html/.env"
        echo -e "${GREEN}Đã tạo file .env tự động cho ứng dụng Node.js!${NC}"
        
        echo -e "${YELLOW}Gợi ý: Cần dùng PM2 để duy trì ứng dụng chạy ngầm (pm2 start npx --name 'app' -- tsx server.ts).${NC}"

    elif [[ "$type" == "docker_proxy" ]]; then
        # ── Docker Proxy + ZaloCRM Auto Setup ────────────────────
        read -p "Nhập Port Docker container (Mặc định 3080): " docker_port
        if [[ -z "$docker_port" ]]; then docker_port="3080"; fi
        if ! _site_valid_port "$docker_port"; then
            log_error "Port không hợp lệ: $docker_port"
            _site_add_rollback "$domain"; pause; return
        fi

        # Hỏi có phải ZaloCRM không
        echo -e "\n${YELLOW}Đây có phải ZaloCRM không?${NC}"
        echo -e "1. Có — cài đặt ZaloCRM tự động (clone/cấu hình/khởi chạy)"
        echo -e "2. Không — chỉ tạo Nginx Proxy đơn thuần"
        read -p "Chọn [1-2]: " is_zalocrm

        if [[ "$is_zalocrm" == "1" ]]; then
            # Dùng luôn thư mục vps-manager vừa tạo — nhất quán, không hỏi thêm
            local app_dir="/var/www/$domain"

            # ── Bước A: Cài Docker nếu chưa có ──────────────────
            if ! command -v docker &> /dev/null; then
                log_info "Docker chưa có. Đang cài đặt tự động..."
                # Tải script cài đặt về file tạm rồi mới chạy (không pipe thẳng vào shell)
                local docker_installer
                docker_installer=$(mktemp)
                if ! safe_download "https://get.docker.com" "$docker_installer"; then
                    rm -f "$docker_installer"
                    _site_add_rollback "$domain"; pause; return
                fi
                sh "$docker_installer"
                rm -f "$docker_installer"
                if ! command -v docker &> /dev/null; then
                    log_error "Cài Docker thất bại."
                    _site_add_rollback "$domain"; pause; return
                fi
                [[ -n "${SUDO_USER:-}" ]] && usermod -aG docker "$SUDO_USER" 2>/dev/null
                log_info "Docker đã cài xong!"
            else
                log_info "Docker đã có sẵn: $(docker --version)"
            fi

            # ── Bước B: Clone hoặc cập nhật ZaloCRM ──────────
            if [[ -d "$app_dir/.git" ]]; then
                log_info "Mã nguồn đã có. Đang cập nhật (git pull)..."
                git -C "$app_dir" pull
            else
                echo -e "${CYAN}Nhập URL repo GitHub của ZaloCRM:${NC}"
                echo -e "  (Mặc định: https://github.com/leluongnghia/ZaloCRM-Custom.git)"
                read -p "URL (Enter = dùng mặc định): " repo_url
                if [[ -z "$repo_url" ]]; then
                    repo_url="https://github.com/leluongnghia/ZaloCRM-Custom.git"
                fi
                log_info "Đang clone ZaloCRM vào $app_dir ..."
                # Clone vào thư mục tạm rồi copy sang (vps-manager đã tạo $app_dir sẵn)
                git clone "$repo_url" "$app_dir/tmp_clone"
                if [[ $? -ne 0 ]]; then
                    log_error "Clone thất bại! Kiểm tra URL hoặc quyền truy cập repo."
                    rm -rf "$app_dir/tmp_clone"
                    _site_add_rollback "$domain"; pause; return
                fi
                cp -r "$app_dir/tmp_clone/." "$app_dir/"
                rm -rf "$app_dir/tmp_clone"
            fi

            # ── Bước C: Tạo file .env tự động ────────────────
            if [[ ! -f "$app_dir/.env" ]]; then
                log_info "Đang tạo file .env ..."
                if [[ ! -f "$app_dir/.env.example" ]]; then
                    log_error "Repo không có file .env.example - không phải ZaloCRM hợp lệ."
                    _site_add_rollback "$domain"; pause; return
                fi
                cp "$app_dir/.env.example" "$app_dir/.env"
                chmod 600 "$app_dir/.env"

                local db_pass; db_pass=$(openssl rand -hex 16)
                local jwt_secret; jwt_secret=$(openssl rand -hex 32)
                local enc_key; enc_key=$(openssl rand -hex 16)

                sed -i "s|APP_URL=.*|APP_URL=https://$domain|" "$app_dir/.env"
                sed -i "s|DB_PASSWORD=.*|DB_PASSWORD=$db_pass|" "$app_dir/.env"
                sed -i "s|DATABASE_URL=.*|DATABASE_URL=postgresql://crmuser:$db_pass@db:5432/zalocrm|" "$app_dir/.env"
                sed -i "s|JWT_SECRET=.*|JWT_SECRET=$jwt_secret|" "$app_dir/.env"
                sed -i "s|ENCRYPTION_KEY=.*|ENCRYPTION_KEY=$enc_key|" "$app_dir/.env"

                log_info "File .env đã được tạo và cấu hình tự động."
            else
                sed -i "s|APP_URL=.*|APP_URL=https://$domain|" "$app_dir/.env"
                log_info "Đã cập nhật APP_URL=https://$domain trong .env"
            fi

            # ── Bước D: Khởi chạy Docker Compose ─────────────
            log_info "Đang khởi chạy ZaloCRM (docker compose up --build)..."
            local compose_ok=1
            docker compose -f "$app_dir/docker-compose.yml" up -d --build || compose_ok=0

            # Lưu vào sites_data để quản lý sau (restart/update)
            local data_file="$HOME/.vps-manager/sites_data.conf"
            mkdir -p "$(dirname "$data_file")"
            sed -i "/^docker:$(sed_escape_pattern "$domain")|/d" "$data_file" 2>/dev/null || true
            echo "docker:$domain|$app_dir|$docker_port" >> "$data_file"
            chmod 600 "$data_file"

            if [[ "$compose_ok" -eq 1 ]]; then
                echo -e "\n${GREEN}✅ ZaloCRM đang chạy tại cổng $docker_port${NC}"
            else
                log_warn "docker compose báo lỗi. Kiểm tra: docker compose -f $app_dir/docker-compose.yml logs"
            fi
            echo -e "${CYAN}   Thư mục: $app_dir${NC}"
        fi

        # ── Tạo Nginx Proxy (luôn chạy dù ZaloCRM hay không) ─
        if ! create_nginx_docker_proxy_config "$domain" "$docker_port"; then
            log_error "Tạo cấu hình Nginx thất bại."
            _site_add_rollback "$domain"; pause; return
        fi
        echo -e "${GREEN}✅ Nginx đã được cấu hình: $domain → localhost:$docker_port${NC}"
    else
        if ! create_nginx_config "$domain"; then
            log_error "Tạo cấu hình Nginx thất bại."
            _site_add_rollback "$domain"; pause; return
        fi
    fi

    # 4. Database & WP setup
    if [[ "$type" == "wordpress" ]]; then
        if ! setup_database "$domain"; then
            log_error "Tạo Database thất bại - hủy thêm website."
            _site_add_rollback "$domain"; pause; return
        fi
        created_db="$WP_DB_NAME"; created_db_user="$WP_DB_USER"

        echo -e "${YELLOW}Bạn có muốn cài đặt WordPress Core mặc định không?${NC}"
        echo -e "1. Có (Tải bản mới nhất từ WordPress.org)"
        echo -e "2. Không (Tôi sẽ tự upload code hoặc restore backup)"
        read -p "Chọn [1-2]: " wp_choice

        if [[ "$wp_choice" == "1" ]]; then
            if ! install_wordpress "$domain"; then
                log_error "Cài đặt WordPress thất bại - hủy thêm website."
                _site_add_rollback "$domain" "$created_db" "$created_db_user"; pause; return
            fi
        else
            echo -e "${GREEN}Đã bỏ qua bước cài đặt WordPress.${NC}"
            echo -e "Thư mục root: /var/www/$domain/public_html"
            echo -e "Thông tin Database đã tạo (dùng để cấu hình wp-config.php):"
            echo -e "DB Name: $WP_DB_NAME"
            echo -e "DB User: $WP_DB_USER"
            echo -e "DB Pass: $WP_DB_PASS"
        fi
    fi

    # SELinux (RHEL/Oracle Linux): cho phép nginx/php-fpm đọc-ghi site, proxy tới app
    selinux_allow_web

    # 5. SSL Setup (lỗi SSL không làm hủy website - có thể cài lại ở menu SSL)
    echo -e "${YELLOW}Đang cấu hình SSL...${NC}"
    if [[ -f "$(dirname "${BASH_SOURCE[0]}")/ssl.sh" ]]; then
         source "$(dirname "${BASH_SOURCE[0]}")/ssl.sh"
         install_ssl "$domain" || log_warn "Chưa cài được SSL cho $domain. Cài lại tại: Menu SSL → Cài đặt SSL."
    else
         log_warn "Module SSL chưa được cài đặt."
    fi

    log_info "Hoàn tất thêm website $domain."
    pause
}

# ─────────────────────────────────────────────────────────────
# Vhost reverse-proxy dùng chung cho Node.js (PM2) và Docker container.
# Hỗ trợ đầy đủ Socket.IO, WebSocket, Upload file lớn.
# Dùng: _site_write_proxy_vhost <domain> <port> [backup_file]
# ─────────────────────────────────────────────────────────────
_site_write_proxy_vhost() {
    local domain=$1
    local app_port=$2
    local backup=${3:-}
    local config_file="/etc/nginx/sites-available/$domain"

    if ! _site_valid_port "$app_port"; then
        log_error "Port không hợp lệ: $app_port"
        return 1
    fi

    local server_names sec_inc
    server_names=$(_site_server_names "$domain")
    sec_inc=$(_site_sec_headers_include)

    cat > "$config_file" <<EOF
server {
    listen 80;
    listen [::]:80;
    server_name $server_names;
    $sec_inc

    root /var/www/$domain/public_html;

    # Cho phép upload file lớn (ảnh, file đính kèm,...)
    client_max_body_size 50M;

    access_log /var/log/nginx/${domain}.access.log;
    error_log  /var/log/nginx/${domain}.error.log;

    location / {
        proxy_pass http://127.0.0.1:$app_port;
        proxy_http_version 1.1;

        # Hỗ trợ WebSocket / Socket.IO (chat real-time)
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';

        # Headers chuẩn
        proxy_set_header Host              \$host;
        proxy_set_header X-Real-IP         \$remote_addr;
        proxy_set_header X-Forwarded-For   \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_cache_bypass \$http_upgrade;

        # Timeout dài cho kết nối real-time
        proxy_read_timeout    600s;
        proxy_send_timeout    600s;
        proxy_connect_timeout  60s;
    }

    location ~ /\.ht {
        deny all;
    }
}
EOF

    _site_enable_vhost "$domain" "$backup"
}

create_nginx_nodejs_config() {
    _site_write_proxy_vhost "$1" "$2" "${3:-}"
}

create_nginx_docker_proxy_config() {
    if _site_write_proxy_vhost "$1" "$2" "${3:-}"; then
        log_info "Nginx Docker Proxy cho $1 (port $2) đã được tạo thành công!"
    else
        log_error "Cấu hình Nginx có lỗi. Kiểm tra lại bằng: nginx -t"
        return 1
    fi
}

# Dùng: create_nginx_config <domain> [backup_file]
create_nginx_config() {
    local domain=$1
    local backup=${2:-}
    local config_file="/etc/nginx/sites-available/$domain"

    # Dynamic PHP socket detection using shared helper
    local php_sock
    php_sock=$(detect_php_socket 2>/dev/null)
    if [[ $? -ne 0 ]] || [[ -z "$php_sock" ]]; then
        log_error "Không tìm thấy PHP-FPM socket. Hãy cài PHP-FPM trước."
        return 1
    fi

    log_info "Using PHP socket: $php_sock"

    local server_names sec_inc
    server_names=$(_site_server_names "$domain")
    sec_inc=$(_site_sec_headers_include)

    # Create Nginx configuration
    cat > "$config_file" <<EOF
server {
    listen 80;
    listen [::]:80;
    server_name $server_names;
    $sec_inc
    root /var/www/$domain/public_html;
    index index.php index.html index.htm;
    client_max_body_size 128M;

    # ============================================================
    # FastCGI Cache Skip Rules
    # ============================================================
    set \$skip_cache 0;
    if (\$request_method = POST) { set \$skip_cache 1; }

    # Bỏ qua cache khi có query string (kể cả utm_*/fbclid/gclid): cache key chứa nguyên
    # query string nên mỗi click ID sẽ là 1 entry riêng - cache chỉ tốn đĩa mà không bao giờ hit.
    if (\$query_string != "") { set \$skip_cache 1; }

    # Bỏ qua cache cho wp-admin/, wp-login.php, xmlrpc, feed, sitemap
    if (\$request_uri ~* "/wp-admin/|/wp-login\.php|/xmlrpc\.php|/wp-.*\.php|^/feed/|/tag/.*/feed/|/.*sitemap.*\.(xml|xsl)") {
        set \$skip_cache 1;
    }
    # Bỏ qua cache cho user đã đăng nhập hoặc giỏ hàng WooCommerce
    if (\$http_cookie ~* "comment_author|wordpress_[a-f0-9]+|wp-postpass|wordpress_no_cache|wordpress_logged_in|woocommerce_items_in_cart|woocommerce_cart_hash") {
        set \$skip_cache 1;
    }

    location / {
        try_files \$uri \$uri/ /index.php?\$args;
    }

    # ============================================================
    # High-Performance Browser Caching (Images, Fonts, CSS, JS)
    # ============================================================
    location ~* \.(jpg|jpeg|gif|png|webp|avif|ico|svg|woff|woff2|ttf|eot)$ {
        expires 365d;
        add_header Cache-Control "public, no-transform, immutable";
        # add_header ở location sẽ che add_header của server -> phải include lại security headers
        $sec_inc
        access_log off;
        log_not_found off;
    }

    location ~* \.(css|js)$ {
        expires 30d;
        add_header Cache-Control "public, no-transform";
        $sec_inc
        access_log off;
        log_not_found off;
    }

    location ~ \.php$ {
        try_files \$uri =404;
        fastcgi_pass $php_sock;
        fastcgi_index index.php;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        include fastcgi_params;
        fastcgi_buffer_size 128k;
        fastcgi_buffers 4 256k;
        fastcgi_busy_buffers_size 256k;
        fastcgi_read_timeout 300;
        fastcgi_send_timeout 300;
        fastcgi_connect_timeout 300;
        
        # FastCGI Cache Settings (Zero-Downtime Background Update)
        fastcgi_cache WORDPRESS;
        fastcgi_cache_valid 200 301 302 60m;
        fastcgi_cache_use_stale error timeout updating invalid_header http_500 http_503;
        fastcgi_cache_background_update on;
        fastcgi_cache_min_uses 1;
        fastcgi_cache_lock on;
        fastcgi_cache_bypass \$skip_cache$(_site_cache_refresh_var);
        fastcgi_no_cache \$skip_cache;
        add_header X-FastCGI-Cache \$upstream_cache_status;
        $sec_inc
    }

    location ~ /\.ht {
        deny all;
    }
}
EOF

    # Bật vhost: test + reload, lỗi thì tự hoàn tác
    _site_enable_vhost "$domain" "$backup"
}

setup_database() {
    local domain=$1
    # Không để sót thông tin DB của site khác trong cùng phiên menu
    unset WP_DB_NAME WP_DB_USER WP_DB_PASS

    # Tên DB không trùng: tên rút gọn từ domain, nếu đã có DB trùng tên thì gắn hậu tố hash
    # (my-shop.com và myshop.com trước đây cho ra CÙNG một tên DB)
    local db_name
    db_name=$(unique_db_name "$domain")
    if ! valid_identifier "$db_name"; then
        log_error "Không tạo được tên database hợp lệ từ domain: $domain"
        return 1
    fi
    local db_user="${db_name}_u"
    # Use alphanumeric password to avoid sed issues and complexity
    local db_pass=$(openssl rand -base64 18 | tr -dc 'a-zA-Z0-9' | head -c 16)

    log_info "Creating database..."
    
    # Use new MySQL helper with proper credential handling
    if create_database "$db_name" "$db_user" "$db_pass"; then
        echo -e "${GREEN}DB Name: $db_name${NC}"
        echo -e "${GREEN}DB User: $db_user${NC}"
        echo -e "${GREEN}DB Pass: $db_pass${NC}"
        
        export WP_DB_NAME="$db_name"
        export WP_DB_USER="$db_user"
        export WP_DB_PASS="$db_pass"
        
        # SAVE TO LOCAL STORAGE (Persistent)
        local data_file="$HOME/.vps-manager/sites_data.conf"
        mkdir -p "$(dirname "$data_file")"
        
        # Remove old entry if exists
        if [[ -f "$data_file" ]]; then
            sed -i "/^$domain|/d" "$data_file"
        fi
        
        # Format: domain|db_name|db_user|db_pass
        echo "$domain|$db_name|$db_user|$db_pass" >> "$data_file"
        chmod 600 "$data_file"
    else
        log_error "Failed to create database"
        return 1
    fi
}

install_wordpress() {
    local domain=$1
    log_info "Đang tải và cài đặt WordPress..."

    # Không ghi wp-config với thông tin DB rỗng / của site khác
    if [[ -z "${WP_DB_NAME:-}" || -z "${WP_DB_USER:-}" || -z "${WP_DB_PASS:-}" ]]; then
        log_error "Thiếu thông tin Database cho $domain - không cài WordPress."
        return 1
    fi

    cd "/var/www/$domain/public_html" || return 1

    # Check disk space: need at least 256MB for WordPress
    if ! check_disk_space "/var/www/$domain" 256; then
        log_error "Không đủ dung lượng ổ đĩa để cài đặt WordPress!"
        return 1
    fi

    # Download WordPress with error check
    if ! wget -q --timeout=60 https://wordpress.org/latest.tar.gz; then
        log_error "Tải WordPress thất bại! Kiểm tra kết nối mạng."
        return 1
    fi

    # Extract with error check
    if ! tar -xzf latest.tar.gz; then
        log_error "Giải nén WordPress thất bại! File có thể bị hỏng."
        rm -f latest.tar.gz
        return 1
    fi

    mv wordpress/* .
    rm -rf wordpress latest.tar.gz

    # Setup wp-config.php
    if [[ ! -f wp-config-sample.php ]]; then
        log_error "Bộ cài WordPress thiếu wp-config-sample.php."
        return 1
    fi
    cp wp-config-sample.php wp-config.php
    chmod 640 wp-config.php

    # Use pipe | delimiter to avoid issues with special chars if any
    sed -i "s|database_name_here|$(sed_escape_repl "$WP_DB_NAME")|" wp-config.php
    sed -i "s|username_here|$(sed_escape_repl "$WP_DB_USER")|" wp-config.php
    sed -i "s|password_here|$(sed_escape_repl "$WP_DB_PASS")|" wp-config.php

    # Auto inject Object Cache Unix Socket if exists
    local socket_path=""
    if [[ -f /etc/vps-manager/cache.conf ]]; then
        socket_path=$(grep -E '^OBJECT_CACHE_SOCKET=' /etc/vps-manager/cache.conf 2>/dev/null | head -n 1 | cut -d= -f2-)
    fi
    if [[ -z "$socket_path" ]]; then
        if [[ -e "/var/run/valkey/valkey.sock" ]]; then socket_path="/var/run/valkey/valkey.sock"
        elif [[ -e "/var/run/redis/redis.sock" ]]; then socket_path="/var/run/redis/redis.sock"
        elif [[ -e "/var/run/keydb/keydb.sock" ]]; then socket_path="/var/run/keydb/keydb.sock"
        elif [[ -e "/tmp/valkey.sock" ]]; then socket_path="/tmp/valkey.sock"
        elif [[ -e "/tmp/redis.sock" ]]; then socket_path="/tmp/redis.sock"
        elif command -v redis-server >/dev/null 2>&1 || systemctl is-active --quiet redis-server 2>/dev/null || [[ -d /etc/redis ]]; then
            socket_path="/var/run/redis/redis.sock"
        elif command -v valkey-server >/dev/null 2>&1 || systemctl is-active --quiet valkey 2>/dev/null || [[ -d /etc/valkey ]]; then
            socket_path="/var/run/valkey/valkey.sock"
        fi
    fi

    if [[ -n "$socket_path" ]]; then
        # Luôn dùng DB 0: Redis/Valkey mặc định chỉ có DB 0-15, đếm theo số site sẽ vượt giới hạn
        # từ site thứ 16. Các site được tách biệt bằng WP_CACHE_KEY_SALT (theo domain).
        local db_index=0

        sed -i "/table_prefix/i define( 'WP_REDIS_SCHEME', 'unix' );" wp-config.php
        sed -i "/table_prefix/i define( 'WP_REDIS_PATH', '$socket_path' );" wp-config.php
        sed -i "/table_prefix/i define( 'WP_REDIS_DATABASE', ${db_index} );" wp-config.php
        sed -i "/table_prefix/i define( 'WP_CACHE_KEY_SALT', '${domain}:' );" wp-config.php
        log_info "  ✓ Object Cache: Unix Socket $socket_path (DB=${db_index})"
    fi

    # Auto-configure security, performance, PHP-FPM pool
    _auto_configure_wp_site "$domain"

    # Fix permissions again
    chown -R www-data:www-data "/var/www/$domain/public_html"
    chmod 640 "/var/www/$domain/public_html/wp-config.php" 2>/dev/null
    cd - >/dev/null 2>&1 || true
    return 0
}

# Đường dẫn socket của pool riêng theo domain
_site_pool_sock_path() {
    local domain=$1 ver=$2
    if [[ "$OS_FAMILY" == "rhel" ]]; then
        echo "/run/php-fpm/${domain}.sock"
    else
        echo "/run/php/php${ver}-fpm-${domain}.sock"
    fi
}

# Phiên bản PHP mà vhost của domain đang dùng (rỗng nếu không xác định được)
_site_vhost_php_version() {
    local conf="/etc/nginx/sites-available/$1" v=""
    if [[ "$OS_FAMILY" == "rhel" ]]; then
        php_default_version
        return
    fi
    if [[ -f "$conf" ]]; then
        v=$(grep -v '^[[:space:]]*#' "$conf" 2>/dev/null | grep 'fastcgi_pass' | grep -oP 'php\K[0-9]+\.[0-9]+(?=-fpm)' | head -n 1)
    fi
    [[ -z "$v" ]] && v=$(php_default_version)
    echo "$v"
}

# Tạo PHP-FPM pool riêng cho domain (nếu chưa có) và trỏ vhost sang socket của pool.
# Vhost CHỈ được đổi socket khi FPM đã restart thành công và socket thật sự tồn tại.
_site_setup_fpm_pool() {
    local domain="$1"
    local conf="/etc/nginx/sites-available/$domain"
    local php_ver pool_dir pool_file pool_sock

    php_ver=$(_site_vhost_php_version "$domain")
    if [[ -z "$php_ver" ]]; then
        log_warn "  ⚠ Không tìm thấy PHP-FPM. Bỏ qua tạo pool riêng."
        return 1
    fi
    pool_dir=$(php_fpm_pool_dir "$php_ver")
    if [[ ! -d "$pool_dir" ]]; then
        log_warn "  ⚠ Không tìm thấy thư mục pool: $pool_dir"
        return 1
    fi
    pool_file="${pool_dir}/${domain}.conf"
    pool_sock=$(_site_pool_sock_path "$domain" "$php_ver")

    log_info "  → PHP version cho pool: ${php_ver}"

    if [[ ! -f "$pool_file" ]]; then
        # Xác định socket dir của cache (cần thêm vào open_basedir)
        local cache_sock_dir=""
        if [[ -f /etc/vps-manager/cache.conf ]]; then
            local sock_path
            sock_path=$(grep '^OBJECT_CACHE_SOCKET=' /etc/vps-manager/cache.conf 2>/dev/null | cut -d= -f2-)
            [[ -n "$sock_path" ]] && cache_sock_dir=$(dirname "$sock_path")
        fi
        # Fallback auto-detect
        if [[ -z "$cache_sock_dir" ]]; then
            if   [[ -d /var/run/valkey ]]; then cache_sock_dir="/var/run/valkey"
            elif [[ -d /run/valkey    ]]; then cache_sock_dir="/run/valkey"
            elif [[ -d /var/run/redis ]]; then cache_sock_dir="/var/run/redis"
            elif [[ -d /run/redis     ]]; then cache_sock_dir="/run/redis"
            elif [[ -d /var/run/keydb ]]; then cache_sock_dir="/var/run/keydb"
            fi
        fi

        # open_basedir: domain root + /tmp + socket dir (nếu có) - các mục ngăn cách bằng dấu ":"
        local open_basedir="/var/www/${domain}/:/tmp/"
        [[ -n "$cache_sock_dir" ]] && open_basedir+=":${cache_sock_dir}/"

        # Chia ngân sách tiến trình PHP của cả server cho số site hiện có (tối thiểu 4/site).
        # pm = ondemand: site không có truy cập thì không giữ tiến trình nào -> tiết kiệm RAM.
        local budget site_count max_children
        budget=$(php_fpm_children_budget)
        site_count=$(find /var/www -mindepth 1 -maxdepth 1 -type d ! -name html 2>/dev/null | wc -l)
        [[ "$site_count" -lt 1 ]] && site_count=1
        max_children=$(( budget / site_count ))
        [[ "$max_children" -lt 4 ]] && max_children=4

        cat > "$pool_file" << POOLEOF
; VPS Manager - PHP-FPM pool cho $domain
[$domain]
user = www-data
group = www-data
listen = $pool_sock
listen.owner = www-data
listen.group = www-data
listen.mode = 0660

pm = ondemand
pm.max_children = $max_children
pm.process_idle_timeout = 30s
pm.max_requests = 500

; Ghi stack trace của request chạy quá 5 giây (\$pool = tên pool, do PHP-FPM thay thế)
slowlog = /var/log/vps-php-slow-\$pool.log
request_slowlog_timeout = 5s

php_admin_value[upload_max_filesize] = 128M
php_admin_value[post_max_size] = 128M
php_admin_value[memory_limit] = 256M
php_admin_value[max_execution_time] = 300
php_admin_value[error_log] = /var/log/nginx/${domain}.php_error.log
php_admin_value[open_basedir] = ${open_basedir}
POOLEOF
        selinux_restore "$pool_file"

        if ! php_fpm_restart_safe "$php_ver"; then
            # Pool mới làm FPM lỗi -> gỡ pool, đưa FPM về trạng thái chạy được
            rm -f "$pool_file"
            php_fpm_restart_safe "$php_ver" >/dev/null 2>&1 || true
            return 1
        fi
        log_info "  ✓ PHP-FPM pool riêng: $pool_sock (ondemand, max_children=$max_children)"
        log_info "  ✓ open_basedir: ${open_basedir}"
    fi

    # Đợi socket của pool xuất hiện (tối đa 5s)
    local waited=0
    while [[ ! -S "$pool_sock" ]] && [[ $waited -lt 5 ]]; do
        sleep 1; waited=$((waited+1))
    done
    if [[ ! -S "$pool_sock" ]]; then
        log_warn "  ⚠ Socket $pool_sock chưa tồn tại - giữ nguyên vhost đang dùng socket chung."
        return 1
    fi

    # Update Nginx vhost để dùng pool socket riêng (nếu vhost đang dùng socket khác)
    if [[ -f "$conf" ]] && grep -v '^[[:space:]]*#' "$conf" | grep -q "fastcgi_pass" \
        && ! grep -qF "fastcgi_pass unix:${pool_sock};" "$conf"; then
        local bak
        bak=$(backup_nginx_config "$conf")
        sed -i "/^[[:space:]]*#/!s|fastcgi_pass.*;|fastcgi_pass unix:${pool_sock};|g" "$conf"
        if nginx_commit "$conf" "$bak"; then
            log_info "  ✓ Đã cập nhật vhost dùng pool socket riêng"
        else
            return 1
        fi
    fi
    return 0
}

# Chèn các snippet bảo mật vào vhost WordPress (idempotent, có rollback từng bước).
# Snippet chứa "location" phải nằm TRƯỚC "location ~ \.php$" của vhost thì mới có hiệu lực
# (nginx dùng regex location khớp ĐẦU TIÊN), nên luôn chèn ngay sau server_name.
_site_apply_wp_snippets() {
    local domain="$1"
    local conf="/etc/nginx/sites-available/$domain"
    [[ -f "$conf" ]] || return 0

    local snippet inc_line loc_line
    for snippet in /etc/nginx/snippets/security-headers.conf /etc/nginx/snippets/wp-security.conf; do
        [[ -f "$snippet" ]] || continue

        # Vhost cũ: include nằm cuối server block (sau location php) -> gỡ để chèn lại đúng chỗ
        inc_line=$(grep -nF "include $snippet;" "$conf" | head -1 | cut -d: -f1)
        loc_line=$(grep -nE '^[[:space:]]*location[[:space:]]' "$conf" | head -1 | cut -d: -f1)
        if [[ -n "$inc_line" && -n "$loc_line" && "$inc_line" -gt "$loc_line" ]]; then
            nginx_remove_include "$conf" "$snippet" || continue
        fi

        if grep -qF "include $snippet;" "$conf"; then
            continue
        fi
        if nginx_add_include "$conf" "$snippet"; then
            log_info "  ✓ Đã thêm snippet $(basename "$snippet")"
        else
            log_warn "  ⚠ Không thêm được $(basename "$snippet") (đã hoàn tác)."
        fi
    done

    # 7G WAF nếu tồn tại - chỉ giữ lại khi nginx -t chấp nhận (snippet lỗi sẽ được hoàn tác)
    if [[ -f "/etc/nginx/snippets/7g.conf" ]] && ! grep -q "7g.conf\|8g.conf" "$conf"; then
        if nginx_add_include "$conf" "/etc/nginx/snippets/7g.conf"; then
            log_info "  ✓ Đã thêm 7G WAF snippet"
        else
            log_warn "  ⚠ 7G WAF snippet làm Nginx lỗi - đã bỏ qua (kiểm tra lại ở menu Bảo mật)."
        fi
    fi
    return 0
}

# ==============================================================================
# Tự động cấu hình toàn diện sau khi tạo/cài WordPress site
# - PHP-FPM pool riêng cho domain
# - Inject Security Headers + WP Security snippet vào vhost
# - Inject 7G WAF nếu snippet tồn tại
# - Fetch WordPress Salts tự động từ WordPress.org API
# ==============================================================================
_auto_configure_wp_site() {
    local domain="$1"
    local conf="/etc/nginx/sites-available/$domain"
    local wp_config="/var/www/$domain/public_html/wp-config.php"

    log_info "🔧 Tự động cấu hình WordPress site: $domain"

    # ── 1. Tạo PHP-FPM Pool riêng cho domain ──────────────
    _site_setup_fpm_pool "$domain" || log_warn "  ⚠ Chưa tạo được PHP-FPM pool riêng - site tiếp tục dùng pool chung."

    # ── 2. Inject Security Headers + WP Security Locations ─
    _site_apply_wp_snippets "$domain"

    # ── 3. Inject WordPress Salts vào wp-config.php ────
    # wp-config-sample.php luôn có sẵn AUTH_KEY với giá trị mẫu -> phải kiểm tra giá trị mẫu,
    # không phải kiểm tra sự tồn tại của AUTH_KEY.
    if [[ -f "$wp_config" ]] && { grep -q "put your unique phrase here" "$wp_config" || ! grep -q "AUTH_KEY" "$wp_config"; }; then
        log_info "  Đang tải WordPress Salts từ API..."
        local salts
        salts=$(curl -fsSL --max-time 10 "https://api.wordpress.org/secret-key/1.1/salt/" 2>/dev/null || true)
        if [[ -n "$salts" ]] && echo "$salts" | grep -q "AUTH_KEY"; then
            # Ghi salts vào temp file an toàn
            local tmp_salts
            tmp_salts=$(mktemp)
            printf '%s' "$salts" > "$tmp_salts"

            # Dùng python3 thay thế sed để tránh vấn đề escape ký tự đặc biệt trong salts
            python3 - "$wp_config" "$tmp_salts" <<'PYEOF'
import sys, re

wp_config_path = sys.argv[1]
salts_path     = sys.argv[2]

with open(wp_config_path, 'r') as f:
    content = f.read()

with open(salts_path, 'r') as f:
    salts = f.read().strip()

# Remove existing placeholder or old salt lines
content = re.sub(r"define\s*\(\s*['\"](?:AUTH|SECURE_AUTH|LOGGED_IN|NONCE)_(?:KEY|SALT)['\"].*?\);\n", "", content)
content = re.sub(r".*put your unique phrase here.*\n", "", content)

# Insert salts before $table_prefix
content = re.sub(
    r"(\$table_prefix\s*=)",
    salts + "\n\n" + r"\1",
    content,
    count=1
)

with open(wp_config_path, 'w') as f:
    f.write(content)

print("  OK: WP Salts injected")
PYEOF
            local py_exit=$?
            rm -f "$tmp_salts"
            if [[ $py_exit -eq 0 ]]; then
                log_info "  ✓ WordPress Salts đã được tạo tự động"
            else
                log_warn "  ⚠ Inject Salts thất bại (python3 error). Vui lòng điền thủ công tại: https://api.wordpress.org/secret-key/1.1/salt/"
            fi
        else
            log_warn "  ⚠ Không thể lấy WP Salts từ WordPress.org (kiểm tra kết nối mạng)"
        fi
    fi

    # ── 4. Thêm các cấu hình WordPress tối ưu vào wp-config ─
    if [[ -f "$wp_config" ]] && ! grep -q "vps-manager-wp-config" "$wp_config"; then
        sed -i "/table_prefix/i \\
/* vps-manager-wp-config */\\
define('WP_POST_REVISIONS', 5);           // Giới hạn revisions\\
define('EMPTY_TRASH_DAYS', 7);             // Tự xóa thùng rác 7 ngày\\
define('AUTOSAVE_INTERVAL', 120);          // Autosave mỗi 2 phút\\
define('WP_CRON_LOCK_TIMEOUT', 60);        // WP-Cron timeout\\
define('DISALLOW_FILE_EDIT', true);        // Tắt editor file trong admin (bảo mật)\\
define('WP_MEMORY_LIMIT', '256M');         // PHP memory cho WP\\
define('WP_MAX_MEMORY_LIMIT', '512M');     // PHP memory cho admin\\
define('RT_WP_NGINX_HELPER_CACHE_PATH', '/var/cache/nginx/fastcgi'); // Đường dẫn cache cho Nginx Helper\\
" "$wp_config" 2>/dev/null || true
        log_info "  ✓ Đã thêm cấu hình WordPress tối ưu vào wp-config.php"
    fi

    # ── 5. Làm mới FastCGI cache ngay khi sửa bài (mu-plugin + khoá của server) ─
    if cache_refresh_install_plugin "$domain"; then
        log_info "  ✓ Đã bật tự làm mới cache khi nội dung thay đổi"
    fi

    log_info "✅ Hoàn tất cấu hình tự động cho $domain"
}

list_sites() {
    echo -e "\n${CYAN}Danh sách Website trên VPS:${NC}"
    echo -e "${BLUE}----------------------------------------------------------------${NC}"
    printf "%-5s %-35s %-10s %-6s %-10s\n" "STT" "Domain" "SSL" "PHP" "FastCGI"
    echo -e "${BLUE}----------------------------------------------------------------${NC}"

    local i=1
    for d in /var/www/*; do
        if [[ -d "$d" && "$(basename "$d")" != "html" ]]; then
            domain=$(basename "$d")
            conf="/etc/nginx/sites-available/$domain"

            # Detect SSL
            if grep -q "listen 443" "$conf" 2>/dev/null; then
                ssl="${GREEN}ON${NC}"
            else
                ssl="${RED}OFF${NC}"
            fi

            # Detect PHP version
            php_ver=$(grep -v '^[[:space:]]*#' "$conf" 2>/dev/null | grep 'fastcgi_pass' | grep -oP 'php\K[0-9]+\.[0-9]+(?=-fpm)' | head -n 1)
            if [[ -z "$php_ver" ]]; then
                # RHEL/Oracle: socket không mang số phiên bản -> dùng phiên bản PHP của hệ thống
                if [[ "$OS_FAMILY" == "rhel" ]] && grep -v '^[[:space:]]*#' "$conf" 2>/dev/null | grep -q 'fastcgi_pass'; then
                    php_ver=$(php_default_version)
                elif [[ "$(_site_vhost_type "$conf")" == "proxy" ]]; then
                    php_ver="-"
                fi
            fi
            [ -z "$php_ver" ] && php_ver="?"

            # Detect FastCGI Cache
            if grep -q 'skip_cache 1; # DEV_MODE_ACTIVE' "$conf" 2>/dev/null; then
                cache="${RED}DEV${NC}"
            elif grep -q 'fastcgi_cache WORDPRESS' "$conf" 2>/dev/null; then
                cache="${GREEN}ON${NC}"
            else
                cache="${YELLOW}OFF${NC}"
            fi

            printf "%-5s %-35s " "$i." "$domain"
            echo -e "$ssl    $php_ver    $cache"
            ((i++))
        fi
    done

    if [[ "$i" -eq 1 ]]; then
        echo -e "${RED}Không tìm thấy website nào!${NC}"
    fi
    echo -e "${BLUE}----------------------------------------------------------------${NC}"
    pause
}

# Helper: Select Site
select_site() {

    echo -e "\n${CYAN}Danh sách Website trên VPS:${NC}"
    sites=()
    i=1
    for d in /var/www/*; do
        if [[ -d "$d" && "$(basename "$d")" != "html" ]]; then
            domain=$(basename "$d")
            # Chỉ nhận tên thư mục có dạng domain: tên này sẽ được đưa vào lệnh chạy bằng root
            [[ "$domain" =~ ^[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?$ ]] || continue
            sites+=("$domain")
            echo -e "$i. $domain"
            ((i++))
        fi
    done
    
    if [[ ${#sites[@]} -eq 0 ]]; then
        echo -e "${RED}Không tìm thấy website nào!${NC}"
        return 1
    fi
    
    read -p "Chọn website [1-${#sites[@]}]: " choice
    if ! [[ "$choice" =~ ^[0-9]+$ ]] || [[ "$choice" -lt 1 ]] || [[ "$choice" -gt "${#sites[@]}" ]]; then
        echo -e "${RED}Lựa chọn không hợp lệ.${NC}"
        return 1
    fi
    
    SELECTED_DOMAIN="${sites[$((choice-1))]}"
    echo -e "${GREEN}-> Đã chọn: $SELECTED_DOMAIN${NC}"
    return 0
}

# Ghi 1 hằng số chuỗi vào wp-config.php (không đưa giá trị lên dòng lệnh, escape đầy đủ).
# Dùng: _site_wp_config_set <wp-config.php> <KEY> <value>
_site_wp_config_set() {
    local file=$1 key=$2 value=$3
    [[ -f "$file" ]] || return 1
    grep -qE "^[[:space:]]*define\([[:space:]]*['\"]${key}['\"]" "$file" || return 1
    # Escape cho chuỗi PHP nháy đơn, rồi escape cho phần thay thế của sed
    local php_val="${value//\\/\\\\}"
    php_val="${php_val//\'/\\\'}"
    local esc
    esc=$(sed_escape_repl "$php_val")
    sed -i -E "s|^([[:space:]]*define\([[:space:]]*['\"]${key}['\"][[:space:]]*,[[:space:]]*)(['\"]).*\2([[:space:]]*\)[[:space:]]*;.*)$|\1'${esc}'\3|" "$file"
}

delete_site() {
    echo -e "${YELLOW}--- Xóa Website ---${NC}"
    select_site || return
    local domain="$SELECTED_DOMAIN"

    # Chốt chặn cho rm -rf: tên phải khác rỗng và không chứa đường dẫn
    if [[ -z "$domain" || "$domain" == *"/"* || "$domain" == "." || "$domain" == ".." ]]; then
        log_error "Tên website không hợp lệ: '$domain'"
        pause; return
    fi

    # Xác định DB THẬT của site TRƯỚC khi xoá mã nguồn (đọc từ wp-config.php / sites_data.conf),
    # không suy lại từ domain: 2 domain khác nhau có thể cho ra cùng một tên rút gọn.
    _site_resolve_db "$domain"
    local db_name="$SITE_DB_NAME" db_user="$SITE_DB_USER"
    local drop_db=1
    if [[ -z "$db_name" ]]; then
        drop_db=0
    elif _site_db_used_by_other "$domain" "$db_name"; then
        drop_db=0
        log_warn "Database '$db_name' đang được website KHÁC dùng chung - sẽ KHÔNG xoá database."
    fi

    echo -e "${RED}╔══════════════════════════════════════════════════╗${NC}"
    echo -e "${RED}║  ⚠  CẢNH BÁO: KHÔNG THỂ HOÀN TÁC!              ║${NC}"
    echo -e "${RED}║  Xóa toàn bộ mã nguồn + Database của: $domain${NC}"
    echo -e "${RED}╚══════════════════════════════════════════════════╝${NC}"
    echo -e "  Thư mục : /var/www/$domain"
    if [[ "$drop_db" -eq 1 ]]; then
        echo -e "  Database: ${db_name}${db_user:+ (user: $db_user)}"
    else
        echo -e "  Database: (không xoá)"
    fi

    echo -ne "${RED}Xác nhận lần cuối - Nhập 'y' để xóa: ${NC}"
    read -r confirm

    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        echo -e "${YELLOW}Đã hủy thao tác xóa.${NC}"
        pause; return
    fi

    log_info "Đang xóa website $domain..."

    # Remove files
    rm -rf "/var/www/${domain:?}"

    # Remove Nginx config
    rm -f "/etc/nginx/sites-available/$domain"
    rm -f "/etc/nginx/sites-enabled/$domain"
    rm -f /etc/nginx/sites-available/"$domain".bak_* 2>/dev/null
    rm -f "/etc/nginx/.htpasswd_$domain"
    nginx_test_reload || log_warn "Nginx chưa reload được - kiểm tra: nginx -t"

    # Remove PHP-FPM pool riêng của site (nếu có)
    _site_remove_fpm_pools "$domain"

    # Drop DB (đã xác định ở trên, không dùng chung với site khác)
    if [[ "$drop_db" -eq 1 ]] && command -v mysql &>/dev/null; then
        if drop_database "$db_name" "$db_user"; then
            log_info "  ✓ Đã xóa database: $db_name"
        else
            log_warn "  ⚠ Không xóa được database $db_name - kiểm tra thủ công."
        fi
    fi

    # Gỡ cron của site (wp-cron, runner...) đang trỏ vào thư mục vừa xoá
    crontab_remove_containing "/var/www/$domain/" 2>/dev/null || true

    # Xóa khỏi sites_data.conf
    local data_file="$HOME/.vps-manager/sites_data.conf"
    if [[ -f "$data_file" ]]; then
        local ed
        ed=$(sed_escape_pattern "$domain")
        if grep -q "^docker:${ed}|" "$data_file"; then
            log_warn "Site này có Docker container - container KHÔNG tự dừng. Dừng thủ công: docker ps"
        fi
        sed -i "/^${ed}|/d; /^docker:${ed}|/d" "$data_file" 2>/dev/null || true
    fi

    if [[ -d "/etc/letsencrypt/live/$domain" ]]; then
        echo -e "${YELLOW}Chứng chỉ SSL của $domain vẫn còn. Xoá bằng: certbot delete --cert-name $domain${NC}"
    fi

    log_info "Đã xóa hoàn toàn website $domain."
    pause
}

clone_site() {
    echo -e "${YELLOW}--- Clone Website ---${NC}"
    select_site || return
    local src_domain="$SELECTED_DOMAIN"
    local dest_domain

    read -p "Nhập domain ĐÍCH (Mới): " dest_domain
    dest_domain="${dest_domain,,}"

    if ! validate_domain "$dest_domain"; then
        pause; return
    fi
    if [[ "$dest_domain" == "$src_domain" ]]; then
        echo -e "${RED}Domain đích trùng với domain nguồn.${NC}"
        pause; return
    fi

    if [[ -d "/var/www/$dest_domain" ]] || [[ -f "/etc/nginx/sites-available/$dest_domain" ]]; then
        echo -e "${RED}Domain đích đã tồn tại! Vui lòng xóa trước.${NC}"
        pause; return
    fi

    # ── Kiểm tra wp-config.php nguồn ────────────────────────────
    local src_wp_config="/var/www/$src_domain/public_html/wp-config.php"
    if [[ ! -f "$src_wp_config" ]]; then
        echo -e "${RED}Không tìm thấy wp-config.php trên site nguồn!${NC}"
        pause; return
    fi

    # ── Đọc thông tin DB nguồn (hỗ trợ cả ' và ") ───────────────
    local src_db_name src_table_prefix
    src_db_name=$(wp_config_get "$src_wp_config" DB_NAME)
    src_table_prefix=$(grep -m1 -E '^[[:space:]]*\$table_prefix' "$src_wp_config" | grep -oP "(?<=['\"])[^'\"]+(?=['\"])" | head -1)
    src_table_prefix="${src_table_prefix:-wp_}"

    if [[ -z "$src_db_name" ]] || ! valid_identifier "$src_db_name"; then
        echo -e "${RED}Không đọc được DB_NAME hợp lệ từ wp-config.php nguồn!${NC}"
        pause; return
    fi
    if ! valid_identifier "$src_table_prefix"; then
        echo -e "${RED}Table prefix không hợp lệ: $src_table_prefix${NC}"
        pause; return
    fi

    # ── Tạo thông tin DB đích (tên không trùng với DB đã có) ─────
    local new_db_name new_db_user new_db_pass
    new_db_name=$(unique_db_name "$dest_domain")
    new_db_user="${new_db_name}_u"
    new_db_pass=$(openssl rand -base64 18 | tr -dc 'a-zA-Z0-9' | head -c 16)
    if ! valid_identifier "$new_db_name" || [[ "$new_db_name" == "$src_db_name" ]]; then
        echo -e "${RED}Không tạo được tên DB đích hợp lệ.${NC}"
        pause; return
    fi

    echo -e "\n${CYAN}=== Clone: ${src_domain} → ${dest_domain} ===${NC}"
    echo -e "  DB nguồn    : ${CYAN}${src_db_name}${NC}"
    echo -e "  Table prefix: ${CYAN}${src_table_prefix}${NC}"
    echo -e "  DB đích     : ${CYAN}${new_db_name}${NC}"

    local dest_path="/var/www/$dest_domain/public_html"
    local dest_wp_config="$dest_path/wp-config.php"
    local created_db=""
    local tmp_dump=""
    # Dọn dẹp khi clone thất bại giữa chừng (site nguồn không bị đụng tới)
    _clone_fail() {
        [[ -n "$tmp_dump" ]] && rm -f "$tmp_dump"
        _site_add_rollback "$dest_domain" "$created_db" "${created_db:+$new_db_user}"
        pause
    }

    # ── BƯỚC 1: Copy mã nguồn ────────────────────────────────────
    log_info "1/6 Đang copy mã nguồn..."
    mkdir -p "$dest_path"
    if ! rsync -a \
        --exclude 'wp-config.php' \
        --exclude 'wp-content/cache/' \
        --exclude 'wp-content/ai1wm-backups/' \
        --exclude '*.log' \
        "/var/www/$src_domain/public_html/" \
        "$dest_path/"; then
        echo -e "  ${RED}❌ Copy mã nguồn thất bại!${NC}"
        _clone_fail; return
    fi
    echo -e "  ✅ Copy mã nguồn hoàn tất"

    # ── BƯỚC 2: Tạo Nginx config ─────────────────────────────────
    log_info "2/6 Tạo cấu hình Nginx..."
    _site_setup_fastcgi_cache_global
    if ! create_nginx_config "$dest_domain"; then
        echo -e "  ${RED}❌ Tạo cấu hình Nginx thất bại!${NC}"
        _clone_fail; return
    fi
    echo -e "  ✅ Nginx config đã tạo"

    # ── BƯỚC 3: Tạo Database mới ─────────────────────────────────
    log_info "3/6 Tạo Database..."
    if ! create_database "$new_db_name" "$new_db_user" "$new_db_pass"; then
        echo -e "  ${RED}❌ Tạo Database thất bại!${NC}"
        _clone_fail; return
    fi
    created_db="$new_db_name"
    echo -e "  ✅ Database đã tạo"

    # ── BƯỚC 4: Export & Import DB ───────────────────────────────
    log_info "4/6 Clone Database (${src_db_name} → ${new_db_name})..."
    # File dump chứa toàn bộ dữ liệu site: tạo bằng mktemp (quyền 600), xoá ở mọi nhánh
    tmp_dump=$(mktemp /tmp/vpsm_clone_XXXXXXXX.sql) || { _clone_fail; return; }
    chmod 600 "$tmp_dump"
    if mysqldump --single-transaction --quick --max_allowed_packet=1G "$src_db_name" > "$tmp_dump" 2>/dev/null \
        && [[ -s "$tmp_dump" ]]; then
        if mysql "$new_db_name" < "$tmp_dump" 2>/dev/null; then
            echo -e "  ✅ Import Database thành công ($(du -sh "$tmp_dump" | cut -f1))"
        else
            echo -e "  ${RED}❌ Import Database thất bại!${NC}"
            _clone_fail; return
        fi
    else
        echo -e "  ${RED}❌ Export Database nguồn thất bại!${NC}"
        _clone_fail; return
    fi
    rm -f "$tmp_dump"; tmp_dump=""

    # ── BƯỚC 5: Tạo wp-config.php mới ───────────────────────────
    log_info "5/6 Tạo wp-config.php..."
    cp "$src_wp_config" "$dest_wp_config"
    chmod 640 "$dest_wp_config"

    _site_wp_config_set "$dest_wp_config" DB_NAME     "$new_db_name"
    _site_wp_config_set "$dest_wp_config" DB_USER     "$new_db_user"
    _site_wp_config_set "$dest_wp_config" DB_PASSWORD "$new_db_pass"

    # KIỂM TRA: Chắc chắn 100% wp-config.php trỏ đúng DB mới để không làm hỏng site gốc
    local verified_db
    verified_db=$(wp_config_get "$dest_wp_config" DB_NAME)
    if [[ "$verified_db" == "$src_db_name" || "$verified_db" != "$new_db_name" ]]; then
        echo -e "${RED}❌ LỖI NGHIÊM TRỌNG: wp-config.php của site mới vẫn trỏ về DB cũ ($src_db_name)!${NC}"
        echo -e "${RED}Đã dừng lệnh search-replace để bảo vệ site gốc.${NC}"
        _clone_fail; return
    fi
    echo -e "  ✅ wp-config.php đã cấu hình đúng DB mới: $verified_db"

    # Đổi các thông số chứa tên miền cũ trong wp-config.php (như WP_CACHE_KEY_SALT, WP_HOME, WP_SITEURL)
    sed -i "s|$(sed_escape_pattern "$src_domain")|$(sed_escape_repl "$dest_domain")|g" "$dest_wp_config"

    # Phân quyền TRƯỚC khi chạy WP-CLI (WP-CLI chạy bằng user của site, không phải root)
    chown -R www-data:www-data "/var/www/$dest_domain"

    # ── BƯỚC 6: Search & Replace URL + Dọn dẹp ──────────────────
    log_info "6/6 Thay thế URL và dọn dẹp..."

    local sr_ok=0
    if ensure_wp_cli; then
        # 2 bước qua placeholder: không bị thay 2 lần khi domain mới chứa domain cũ
        # (vd example.com -> staging.example.com)
        if _site_wp_search_replace_domain "$dest_path" "$src_domain" "$dest_domain"; then
            sr_ok=1
            echo -e "  ✅ Search-Replace URL hoàn tất trên DB mới"
        else
            echo -e "  ${YELLOW}⚠ Search-Replace bằng WP-CLI báo lỗi - nội dung có thể còn URL cũ.${NC}"
        fi
    else
        echo -e "  ${YELLOW}⚠ Không có WP-CLI - bỏ qua Search-Replace trong nội dung.${NC}"
    fi

    # Luôn dùng SQL trực tiếp để đảm bảo siteurl/home đúng 100% (chạy thẳng trên $new_db_name)
    if mysql "$new_db_name" <<< "UPDATE \`${src_table_prefix}options\` SET option_value='https://${dest_domain}' WHERE option_name IN ('siteurl','home');" 2>/dev/null; then
        echo -e "  ✅ siteurl/home đã cập nhật qua SQL (prefix: ${src_table_prefix})"
    else
        echo -e "  ${YELLOW}⚠ Không cập nhật được siteurl/home qua SQL.${NC}"
    fi

    # Xóa Object Cache (Redis/Memcached) của site mới để tránh dính cache URL cũ
    if [[ -x /usr/local/bin/wp ]]; then
        if $(_site_wp_cmd "$dest_path") cache flush --skip-plugins --skip-themes --quiet 2>/dev/null; then
            echo -e "  ✅ Đã flush Object Cache cho site mới"
        fi
    fi

    # Pool PHP-FPM riêng + snippet bảo mật cho site mới (giống site tạo mới)
    _auto_configure_wp_site "$dest_domain"

    # Phân quyền
    chown -R www-data:www-data "/var/www/$dest_domain"
    find "$dest_path" -type d -exec chmod 755 {} \;
    find "$dest_path" -type f -exec chmod 644 {} \;
    chmod 640 "$dest_wp_config"
    # Xóa cache cũ và file gây lỗi phân quyền
    rm -rf "${dest_path:?}/wp-content/cache/"
    find "$dest_path" -name ".user.ini" -delete 2>/dev/null
    selinux_allow_web
    echo -e "  ✅ Phân quyền và dọn dẹp hoàn tất"

    # ── Lưu thông tin DB vào sites_data.conf ─────────────────────
    local data_file="$HOME/.vps-manager/sites_data.conf"
    mkdir -p "$(dirname "$data_file")"
    sed -i "/^$(sed_escape_pattern "$dest_domain")|/d" "$data_file" 2>/dev/null || true
    echo "$dest_domain|$new_db_name|$new_db_user|$new_db_pass" >> "$data_file"
    chmod 600 "$data_file"

    # ── Kết quả ──────────────────────────────────────────────────
    echo ""
    echo -e "${GREEN}=================================================${NC}"
    if [[ "$sr_ok" -eq 1 ]]; then
        echo -e "${GREEN}  ✅ Clone hoàn tất!${NC}"
    else
        echo -e "${YELLOW}  ⚠ Clone xong nhưng CHƯA thay được URL trong nội dung.${NC}"
    fi
    echo -e "${GREEN}=================================================${NC}"
    echo -e "  Domain mới : ${CYAN}http://${dest_domain}${NC}"
    echo -e "  DB Name    : ${CYAN}${new_db_name}${NC}"
    echo -e "  DB User    : ${CYAN}${new_db_user}${NC}"
    echo -e "  DB Pass    : ${CYAN}${new_db_pass}${NC}"
    echo ""
    echo -e "${YELLOW}Bước tiếp theo:${NC}"
    echo -e "  → Menu SSL → Cài đặt SSL → chọn ${CYAN}${dest_domain}${NC} → Let's Encrypt"
    echo -e "${GREEN}=================================================${NC}"
    pause
}

# Đổi tên pool PHP-FPM riêng theo domain. Trả về 1 nếu FPM không chạy lại được với pool mới.
_site_rename_fpm_pools() {
    local old=$1 new=$2 pool_file new_file ver eo en rc=0
    eo=$(sed_escape_pattern "$old")
    en=$(sed_escape_repl "$new")
    for pool_file in /etc/php/*/fpm/pool.d/"${old}".conf /etc/php-fpm.d/"${old}".conf; do
        [[ -f "$pool_file" ]] || continue
        new_file="$(dirname "$pool_file")/${new}.conf"
        ver=$(echo "$pool_file" | grep -oE '/etc/php/[0-9]+\.[0-9]+/' | grep -oE '[0-9]+\.[0-9]+')
        # Tên pool, socket, open_basedir, error_log đều chứa domain
        sed "s|${eo}|${en}|g" "$pool_file" > "$new_file"
        rm -f "$pool_file"
        selinux_restore "$new_file"
        if ! php_fpm_restart_safe "$ver"; then
            rc=1
        fi
    done
    return $rc
}

rename_site() {
    echo -e "${YELLOW}--- Thay đổi Tên miền (Rename) ---${NC}"
    select_site || return
    local old_domain="$SELECTED_DOMAIN"
    local new_domain

    read -p "Nhập domain MỚI: " new_domain
    new_domain="${new_domain,,}"

    if ! validate_domain "$new_domain"; then pause; return; fi
    if [[ "$new_domain" == "$old_domain" ]]; then echo -e "${RED}Domain mới trùng domain cũ.${NC}"; pause; return; fi
    if [[ -d "/var/www/$new_domain" ]]; then echo -e "${RED}Domain mới đã tồn tại.${NC}"; pause; return; fi
    if [[ -f "/etc/nginx/sites-available/$new_domain" ]]; then echo -e "${RED}Config Nginx mới đã tồn tại.${NC}"; pause; return; fi

    local old_conf="/etc/nginx/sites-available/$old_domain"
    local new_conf="/etc/nginx/sites-available/$new_domain"
    local eo en
    eo=$(sed_escape_pattern "$old_domain")
    en=$(sed_escape_repl "$new_domain")

    # Bản chụp vhost cũ để hoàn tác nếu có bước nào lỗi
    local conf_snapshot=""
    if [[ -f "$old_conf" ]]; then
        conf_snapshot=$(mktemp)
        cp -p "$old_conf" "$conf_snapshot"
    fi

    _rename_rollback() {
        log_warn "Đang hoàn tác đổi tên..."
        rm -f "$new_conf" "/etc/nginx/sites-enabled/$new_domain" /etc/nginx/sites-available/"$new_domain".bak_* 2>/dev/null
        if [[ -n "$conf_snapshot" && -f "$conf_snapshot" ]]; then
            cat "$conf_snapshot" > "$old_conf"
            rm -f "/etc/nginx/sites-enabled/$old_domain"
            ln -s "$old_conf" "/etc/nginx/sites-enabled/$old_domain"
            rm -f "$conf_snapshot"
        fi
        [[ -f "/etc/nginx/.htpasswd_$new_domain" ]] && mv "/etc/nginx/.htpasswd_$new_domain" "/etc/nginx/.htpasswd_$old_domain"
        [[ -d "/var/www/$new_domain" && ! -e "/var/www/$old_domain" ]] && mv "/var/www/$new_domain" "/var/www/$old_domain"
        _site_rename_fpm_pools "$new_domain" "$old_domain" || true
        nginx_test_reload || true
        log_warn "Đã hoàn tác: website vẫn là $old_domain."
    }

    log_info "Đổi tên thư mục..."
    if ! mv "/var/www/$old_domain" "/var/www/$new_domain"; then
        log_error "Không đổi được tên thư mục."
        [[ -n "$conf_snapshot" ]] && rm -f "$conf_snapshot"
        pause; return
    fi

    # Pool PHP-FPM riêng: open_basedir + socket + tên pool đều theo domain -> phải đổi theo,
    # nếu không PHP bị giam vào thư mục không còn tồn tại.
    log_info "Cập nhật PHP-FPM pool..."
    if ! _site_rename_fpm_pools "$old_domain" "$new_domain"; then
        log_error "PHP-FPM không chạy lại được với pool mới."
        _rename_rollback; pause; return
    fi

    log_info "Cập nhật Nginx..."
    local had_ssl=0
    if [[ -f "$old_conf" ]]; then
        grep -qE 'listen[[:space:]].*443|ssl_certificate' "$old_conf" && had_ssl=1

        # Config file rename to preserve custom snippets
        rm -f "/etc/nginx/sites-enabled/$old_domain"
        mv "$old_conf" "$new_conf"

        # Đường dẫn (root, log, socket pool, htpasswd): thay domain cũ -> mới.
        # Không đụng dòng server_name (xử lý riêng để giữ alias) và các dòng SSL/Certbot (gỡ ở bước sau).
        sed -i -E "/server_name|ssl_certificate|ssl_trusted_certificate|letsencrypt|managed by Certbot|[$]host[[:space:]]*=/! s/${eo}/${en}/g" "$new_conf"

        # server_name: chỉ đổi đúng token của domain cũ, GIỮ NGUYÊN các alias khác
        if _site_is_apex_domain "$new_domain"; then
            sed -i -E "/^[[:space:]]*server_name[[:space:]]/ s/([[:space:]])www\.${eo}([[:space:];])/\1www.${en}\2/g" "$new_conf"
        else
            # Subdomain không có www.
            sed -i -E "/^[[:space:]]*server_name[[:space:]]/ s/[[:space:]]+www\.${eo}([[:space:];])/\1/g" "$new_conf"
        fi
        sed -i -E "/^[[:space:]]*server_name[[:space:]]/ s/([[:space:]])${eo}([[:space:];])/\1${en}\2/g" "$new_conf"
        if _site_is_apex_domain "$new_domain" && ! grep -qE "^[[:space:]]*server_name[[:space:]].*[[:space:]]www\.$(sed_escape_pattern "$new_domain")[[:space:];]" "$new_conf"; then
            sed -i -E "/^[[:space:]]*server_name[[:space:]]/ s/([[:space:]])$(sed_escape_pattern "$new_domain")([[:space:];])/\1${en} www.${en}\2/" "$new_conf"
        fi

        [[ -f "/etc/nginx/.htpasswd_$old_domain" ]] && mv "/etc/nginx/.htpasswd_$old_domain" "/etc/nginx/.htpasswd_$new_domain"

        # Re-link
        ln -s "$new_conf" "/etc/nginx/sites-enabled/$new_domain"
        selinux_restore "$new_conf"

        local commit_ok=1
        if [[ "$had_ssl" -eq 1 ]]; then
            # Chứng chỉ cũ cấp cho domain cũ -> đưa vhost về HTTP, sau đó cấp lại cho domain mới
            source "$(dirname "${BASH_SOURCE[0]}")/ssl.sh"
            _strip_ssl_from_vhost "$new_conf" || commit_ok=0
        else
            nginx_commit "$new_conf" "" || commit_ok=0
        fi
        if [[ "$commit_ok" -ne 1 ]] || [[ ! -e "/etc/nginx/sites-enabled/$new_domain" ]]; then
            log_error "Cấu hình Nginx mới bị lỗi."
            _rename_rollback; pause; return
        fi
    else
        log_warn "Không tìm thấy Nginx config cũ. Tạo mới..."
        if ! create_nginx_config "$new_domain"; then
            _rename_rollback; pause; return
        fi
        [[ -f "/var/www/$new_domain/public_html/wp-config.php" ]] && _site_setup_fpm_pool "$new_domain"
    fi
    [[ -n "$conf_snapshot" ]] && rm -f "$conf_snapshot"

    log_info "Cập nhật URL trong Database (nếu là WP)..."
    local new_root="/var/www/$new_domain/public_html"
    if [[ -f "$new_root/wp-config.php" ]]; then
        if ensure_wp_cli; then
            # 2 bước qua placeholder: an toàn cả khi domain mới chứa domain cũ
            if _site_wp_search_replace_domain "$new_root" "$old_domain" "$new_domain"; then
                log_info "Đã thay URL trong Database."
            else
                log_warn "Search-Replace báo lỗi - kiểm tra lại URL trong Database."
            fi
        else
            log_warn "Không có WP-CLI - chưa thay URL trong Database."
        fi

        # Đổi luôn các thông số trong wp-config.php (như WP_CACHE_KEY_SALT, WP_HOME)
        sed -i "s|${eo}|${en}|g" "$new_root/wp-config.php"

        [[ -x /usr/local/bin/wp ]] && $(_site_wp_cmd "$new_root") cache flush --skip-plugins --skip-themes --quiet 2>/dev/null
    fi

    # sites_data.conf: đổi khoá domain (và đường dẫn của entry docker)
    local data_file="$HOME/.vps-manager/sites_data.conf"
    if [[ -f "$data_file" ]]; then
        sed -i -E "/^(docker:)?${eo}\|/ s/${eo}/${en}/g" "$data_file" 2>/dev/null || true
    fi
    selinux_allow_web

    log_info "Đổi tên thành công: $old_domain -> $new_domain"
    if crontab -l 2>/dev/null | grep -qF "$old_domain"; then
        echo -e "${YELLOW}Lưu ý: Crontab còn dòng chứa '$old_domain' (WP-Cron...). Vào menu Cronjob để tạo lại cho domain mới.${NC}"
    fi
    if [[ "$had_ssl" -eq 1 ]]; then
        echo -e "${YELLOW}Chứng chỉ SSL cũ không dùng được cho domain mới - website đang chạy HTTP.${NC}"
        read -p "Cấp SSL Let's Encrypt cho $new_domain ngay bây giờ? [Y/n]: " ssl_now
        if [[ "${ssl_now,,}" != "n" ]]; then
            install_letsencrypt "$new_domain" || log_warn "Chưa cấp được SSL. Thử lại ở Menu SSL sau khi DNS đã trỏ về VPS."
        fi
    fi
    pause
}

rewrite_vhost_config() {
    select_site || return
    local domain="$SELECTED_DOMAIN"
    local conf="/etc/nginx/sites-available/$domain"
    local data_file="$HOME/.vps-manager/sites_data.conf"

    # Vhost Node.js/Docker là reverse proxy: KHÔNG được ghi đè bằng mẫu PHP (app sẽ offline)
    local vtype proxy_port=""
    vtype=$(_site_vhost_type "$conf")
    if [[ "$vtype" == "proxy" ]]; then
        proxy_port=$(grep -v '^[[:space:]]*#' "$conf" | grep -oE 'proxy_pass[[:space:]]+http://(127\.0\.0\.1|localhost):[0-9]+' | head -1 | grep -oE '[0-9]+$')
    elif [[ "$vtype" == "unknown" && -f "$data_file" ]]; then
        proxy_port=$(awk -F'|' -v d="docker:$domain" '$1==d{print $3; exit}' "$data_file")
        [[ -n "$proxy_port" ]] && vtype="proxy"
    fi
    if [[ "$vtype" == "proxy" && -z "$proxy_port" ]]; then
        log_error "Vhost của $domain là reverse proxy tuỳ biến - không tự tạo lại được. Sửa tay ở menu Nginx → Vhost."
        pause; return
    fi

    # Ghi nhớ alias (parked domain) + trạng thái SSL để khôi phục sau khi tạo lại
    local aliases="" had_ssl=0 tok
    if [[ -f "$conf" ]]; then
        for tok in $(grep -m1 -E '^[[:space:]]*server_name[[:space:]]' "$conf" | sed -E 's/^[[:space:]]*server_name[[:space:]]+//; s/;.*$//'); do
            [[ "$tok" == "$domain" || "$tok" == "www.$domain" || "$tok" == "_" ]] && continue
            [[ "$tok" =~ ^[A-Za-z0-9.-]+$ ]] && aliases+=" $tok"
        done
        grep -qE 'listen[[:space:]].*443|ssl_certificate' "$conf" && had_ssl=1
    fi

    if [[ "$vtype" == "proxy" ]]; then
        echo -e "${CYAN}Loại website: Reverse Proxy (Node.js/Docker) → cổng $proxy_port${NC}"
    else
        echo -e "${CYAN}Loại website: PHP / WordPress${NC}"
    fi
    echo -e "${YELLOW}Tạo lại vhost sẽ bỏ mọi chỉnh sửa tay trong file cấu hình (mật khẩu bảo vệ, rule riêng...).${NC}"
    read -p "Tiếp tục? (y/n): " c
    [[ "$c" != "y" && "$c" != "Y" ]] && return

    # Giữ 1 bản sao lâu dài của vhost cũ để lấy lại chỉnh sửa tay khi cần
    local bak=""
    if [[ -f "$conf" ]]; then
        local keep_dir="$HOME/.vps-manager/vhost_backups"
        mkdir -p "$keep_dir" && chmod 700 "$keep_dir"
        cp -p "$conf" "$keep_dir/${domain}.$(date +%Y%m%d_%H%M%S).conf"
        bak=$(backup_nginx_config "$conf")
    fi

    local ok=1
    if [[ "$vtype" == "proxy" ]]; then
        _site_write_proxy_vhost "$domain" "$proxy_port" "$bak" || ok=0
    else
        _site_setup_fastcgi_cache_global
        create_nginx_config "$domain" "$bak" || ok=0
    fi
    if [[ "$ok" -ne 1 ]]; then
        log_error "Tạo lại vhost thất bại - đã giữ nguyên cấu hình cũ."
        pause; return
    fi
    log_info "Đã tạo lại file cấu hình Nginx cho $domain."

    if [[ "$vtype" != "proxy" ]]; then
        if [[ -f "/var/www/$domain/public_html/wp-config.php" ]]; then
            # Trỏ lại pool riêng + snippet bảo mật WordPress
            _auto_configure_wp_site "$domain"
        elif compgen -G "/etc/php/*/fpm/pool.d/${domain}.conf" >/dev/null || [[ -f "/etc/php-fpm.d/${domain}.conf" ]]; then
            _site_setup_fpm_pool "$domain"
        fi
    fi

    # Khôi phục alias
    if [[ -n "$aliases" ]]; then
        local abak
        abak=$(backup_nginx_config "$conf")
        sed -i -E "/^[[:space:]]*server_name[[:space:]]/ s/;/${aliases};/" "$conf"
        if nginx_commit "$conf" "$abak"; then
            log_info "Đã khôi phục alias:${aliases}"
        else
            log_warn "Không khôi phục được alias:${aliases}"
        fi
    fi

    # SSL Check/Restore
    source "$(dirname "${BASH_SOURCE[0]}")/ssl.sh"
    local manual_crt="" manual_key=""
    if [[ -s "/etc/nginx/ssl/$domain/origin.crt" && -s "/etc/nginx/ssl/$domain/origin.key" ]]; then
        manual_crt="/etc/nginx/ssl/$domain/origin.crt"; manual_key="/etc/nginx/ssl/$domain/origin.key"
    elif [[ -s "/etc/nginx/ssl/$domain/server.crt" && -s "/etc/nginx/ssl/$domain/server.key" ]]; then
        manual_crt="/etc/nginx/ssl/$domain/server.crt"; manual_key="/etc/nginx/ssl/$domain/server.key"
    fi

    echo -e "${YELLOW}Bạn có muốn cài đặt/khôi phục SSL cho $domain không?${NC}"
    if [[ -n "$manual_crt" && ! -d "/etc/letsencrypt/live/$domain" ]]; then
        echo -e "1. Có (dùng lại chứng chỉ đang có: $manual_crt)"
    else
        echo -e "1. Có (Let's Encrypt - Auto)"
    fi
    echo -e "2. Không (Chỉ dùng HTTP 80)"
    [[ "$had_ssl" -eq 1 ]] && echo -e "${RED}Website này trước đó đang chạy HTTPS - nên chọn 1.${NC}"
    read -p "Chọn [1-2]: " ssl_c

    if [[ "$ssl_c" == "1" ]]; then
        if [[ -n "$manual_crt" && ! -d "/etc/letsencrypt/live/$domain" ]]; then
            if _apply_manual_ssl_nginx_config "$domain" "$manual_crt" "$manual_key"; then
                echo -e "${GREEN}Đã khôi phục SSL thành công.${NC}"
            else
                echo -e "${RED}Khôi phục SSL thất bại - website đang chạy HTTP.${NC}"
            fi
        elif install_letsencrypt "$domain"; then
            echo -e "${GREEN}Đã khôi phục SSL thành công.${NC}"
        else
            echo -e "${RED}Khôi phục SSL thất bại - website đang chạy HTTP. Thử lại ở Menu SSL.${NC}"
        fi
    fi
    pause
}

change_site_php() {
    select_site || return
    local domain="$SELECTED_DOMAIN"
    local conf="/etc/nginx/sites-available/$domain"

    if [[ ! -f "$conf" ]]; then echo -e "${RED}Config Nginx không tồn tại.${NC}"; pause; return; fi

    if [[ "$(_site_vhost_type "$conf")" != "php" ]]; then
        echo -e "${RED}Website này không chạy PHP (reverse proxy) - không có phiên bản PHP để đổi.${NC}"
        pause; return
    fi

    # RHEL/Oracle Linux: PHP cài theo module stream nên toàn server chỉ có MỘT phiên bản PHP.
    if [[ "$OS_FAMILY" == "rhel" ]]; then
        echo -e "${YELLOW}Trên RHEL/Oracle/AlmaLinux, PHP được cài theo module stream: cả server dùng chung 1 phiên bản${NC}"
        echo -e "${YELLOW}(hiện tại: PHP $(php_default_version)). Không thể đổi riêng cho từng website.${NC}"
        echo -e "Để đổi phiên bản cho toàn server: Menu chính → Quản lý Phiên bản PHP."
        pause; return
    fi

    # Tìm kiếm version PHP hiện hành trong file config
    local current_php ver v
    current_php=$(grep -v '^[[:space:]]*#' "$conf" 2>/dev/null | grep 'fastcgi_pass' | grep -oP 'php\K[0-9]+\.[0-9]+(?=-fpm)' | head -n 1)

    if [[ -n "$current_php" ]]; then
        echo -e "${CYAN}Phiên bản PHP hiện tại của web: PHP $current_php${NC}"
    else
        echo -e "${YELLOW}Không thể xác định phiên bản PHP hiện tại trong config.${NC}"
    fi
    echo ""

    echo -e "Chọn phiên bản PHP muốn ĐỔI SANG:"
    echo "1. PHP 7.4"
    echo "2. PHP 8.0"
    echo "3. PHP 8.1"
    echo "4. PHP 8.2"
    echo "5. PHP 8.3"
    echo "6. PHP 8.4"
    read -p "Chọn [1-6]: " v
    case $v in
        1) ver="7.4" ;;
        2) ver="8.0" ;;
        3) ver="8.1" ;;
        4) ver="8.2" ;;
        5) ver="8.3" ;;
        6) ver="8.4" ;;
        *) return ;;
    esac

    if [[ "$ver" == "$current_php" ]]; then
        echo -e "${YELLOW}Website đã dùng PHP $ver.${NC}"
        pause; return
    fi

    # Kiểm tra xem phiên bản PHP mới đã được cài đặt chưa, nếu chưa thì tự động cài đặt
    if [[ ! -d "/etc/php/$ver/fpm" ]] && ! is_installed "php$ver-fpm"; then
        echo -e "${YELLOW}PHP $ver chưa được cài đặt trên hệ thống.${NC}"
        read -p "Bạn có muốn tự động cài đặt PHP $ver ngay bây giờ không? [y/N]: " confirm_inst
        if [[ "$confirm_inst" =~ ^[yY]([eE][sS])?$ ]]; then
            source "$(dirname "${BASH_SOURCE[0]}")/php.sh"
            install_additional_php "$ver"
        else
            echo -e "${RED}Đã hủy quá trình đổi phiên bản PHP do chưa cài đặt PHP $ver.${NC}"
            pause; return
        fi
        if [[ ! -d "/etc/php/$ver/fpm" ]]; then
            log_error "Cài PHP $ver không thành công - giữ nguyên phiên bản hiện tại."
            pause; return
        fi
    fi

    # Kiểm tra xem có sử dụng pool riêng không bằng cách kiểm tra file pool.d
    local old_pool=""
    if [[ -n "$current_php" ]]; then
        old_pool="/etc/php/${current_php}/fpm/pool.d/${domain}.conf"
    fi
    local new_pool="/etc/php/${ver}/fpm/pool.d/${domain}.conf"
    local new_sock waited=0

    log_info "Đang cập nhật cấu hình PHP cho $domain sang PHP $ver..."

    if [[ -n "$current_php" ]] && [[ -f "$old_pool" ]]; then
        log_info "Phát hiện PHP pool riêng cho tên miền. Đang di chuyển cấu hình pool..."
        mkdir -p "/etc/php/${ver}/fpm/pool.d"
        cp "$old_pool" "$new_pool"
        # Cập nhật đường dẫn socket trong file pool mới
        sed -i "s|php${current_php}-fpm-${domain}.sock|php${ver}-fpm-${domain}.sock|g" "$new_pool"
        # Cập nhật open_basedir hoặc log file path nếu chúng có chứa php version cũ
        sed -i "s|/etc/php/${current_php}/|/etc/php/${ver}/|g" "$new_pool"

        # Khởi động pool ở PHP mới TRƯỚC, chỉ gỡ pool cũ khi vhost đã chuyển xong
        if ! php_fpm_restart_safe "$ver"; then
            rm -f "$new_pool"
            php_fpm_restart_safe "$ver" >/dev/null 2>&1 || true
            log_error "PHP $ver không khởi động được với pool mới - giữ nguyên PHP $current_php."
            pause; return
        fi
        new_sock=$(_site_pool_sock_path "$domain" "$ver")
    else
        # Nếu không dùng pool riêng hoặc không tìm thấy pool cũ, chỉ đổi socket global
        systemctl is-active --quiet "$(php_fpm_service "$ver")" || php_fpm_restart_safe "$ver"
        new_sock=$(php_fpm_socket "$ver")
    fi

    while [[ ! -S "$new_sock" ]] && [[ $waited -lt 5 ]]; do
        sleep 1; waited=$((waited+1))
    done
    if [[ ! -S "$new_sock" ]]; then
        log_error "Socket $new_sock không tồn tại - PHP $ver chưa chạy. Giữ nguyên cấu hình hiện tại."
        if [[ -f "$new_pool" && -f "$old_pool" ]]; then
            rm -f "$new_pool"
            php_fpm_restart_safe "$ver" >/dev/null 2>&1 || true
        fi
        pause; return
    fi

    # Cập nhật Nginx sử dụng socket mới (có hoàn tác nếu lỗi)
    local bak
    bak=$(backup_nginx_config "$conf")
    sed -i "/^[[:space:]]*#/!s|fastcgi_pass.*;|fastcgi_pass unix:${new_sock};|" "$conf"
    if ! nginx_commit "$conf" "$bak"; then
        if [[ -f "$new_pool" && -f "$old_pool" ]]; then
            rm -f "$new_pool"
            php_fpm_restart_safe "$ver" >/dev/null 2>&1 || true
        fi
        log_error "Không chuyển được $domain sang PHP $ver - đã giữ nguyên PHP ${current_php:-cũ}."
        pause; return
    fi

    # Xóa pool cũ và restart FPM cũ
    if [[ -n "$old_pool" && -f "$old_pool" && -f "$new_pool" ]]; then
        rm -f "$old_pool"
        php_fpm_restart_safe "$current_php" >/dev/null 2>&1 || true
    fi

    log_info "Đã chuyển $domain sang PHP $ver"
    pause
}

update_site_db_info() {
    select_site || return
    local domain="$SELECTED_DOMAIN"
    local wp_conf="/var/www/$domain/public_html/wp-config.php"
    local db_name db_user db_pass

    if [[ ! -f "$wp_conf" ]]; then echo -e "${RED}Không tìm thấy wp-config.php${NC}"; pause; return; fi

    read -p "Database Name mới: " db_name
    read -p "Database User mới: " db_user
    read -s -p "Database Password mới: " db_pass
    echo ""

    if ! valid_identifier "$db_name" || ! valid_identifier "$db_user"; then
        echo -e "${RED}Tên Database/User chỉ được gồm chữ, số và gạch dưới.${NC}"
        pause; return
    fi
    if [[ -z "$db_pass" ]]; then
        echo -e "${RED}Mật khẩu không được để trống.${NC}"
        pause; return
    fi

    # Thử kết nối bằng thông tin mới trước khi ghi (mật khẩu đi qua biến môi trường, không lên dòng lệnh)
    if ! MYSQL_PWD="$db_pass" mysql -u "$db_user" "$db_name" -e "SELECT 1" &>/dev/null; then
        echo -e "${YELLOW}Không kết nối được tới database '$db_name' bằng user '$db_user'.${NC}"
        read -p "Vẫn ghi vào wp-config.php? (y/n): " force
        [[ "$force" != "y" && "$force" != "Y" ]] && { pause; return; }
    fi

    local wp_bak="${wp_conf}.bak_$(date +%s)"
    cp -p "$wp_conf" "$wp_bak"
    chmod 600 "$wp_bak"

    _site_wp_config_set "$wp_conf" DB_NAME     "$db_name"
    _site_wp_config_set "$wp_conf" DB_USER     "$db_user"
    _site_wp_config_set "$wp_conf" DB_PASSWORD "$db_pass"

    if [[ "$(wp_config_get "$wp_conf" DB_NAME)" == "$db_name" && "$(wp_config_get "$wp_conf" DB_USER)" == "$db_user" ]]; then
        log_info "Đã cập nhật thông tin Database. (Bản cũ: $wp_bak)"
    else
        cp -p "$wp_bak" "$wp_conf"
        log_error "Không cập nhật được wp-config.php (định dạng lạ) - đã khôi phục bản cũ."
    fi
    pause
}

manage_parked_domains() {
    echo -e "1. Thêm Parked Domain (Alias)"
    echo -e "2. Xóa Parked Domain"
    read -p "Chọn: " c

    [[ "$c" != "1" && "$c" != "2" ]] && return

    select_site || return
    local main="$SELECTED_DOMAIN"
    local conf="/etc/nginx/sites-available/$main"
    local alias ea bak

    if [[ ! -f "$conf" ]]; then echo -e "${RED}Config Nginx không tồn tại.${NC}"; pause; return; fi

    case $c in
        1)
            read -p "Domain ALIAS (Parked): " alias
            alias="${alias,,}"
            if ! validate_domain "$alias"; then pause; return; fi
            ea=$(sed_escape_pattern "$alias")

            if grep -qE "^[[:space:]]*server_name[[:space:]](.*[[:space:]])?${ea}[[:space:];]" "$conf"; then
                echo "Alias đã tồn tại."
            else
                local names="$alias"
                _site_is_apex_domain "$alias" && names="$alias www.$alias"
                bak=$(backup_nginx_config "$conf")
                sed -i -E "/^[[:space:]]*server_name[[:space:]]/ s/;/ ${names};/" "$conf"
                if nginx_commit "$conf" "$bak"; then
                    log_info "Đã thêm alias $alias cho $main"
                    echo -e "${YELLOW}Lưu ý: Bạn cần cấp lại SSL để bao gồm cả domain alias!${NC}"
                else
                    log_error "Thêm alias thất bại - đã giữ nguyên cấu hình cũ."
                fi
            fi
            ;;
        2)
            read -p "Domain ALIAS cần xóa: " alias
            alias="${alias,,}"
            if ! validate_domain "$alias"; then pause; return; fi
            if [[ "$alias" == "$main" ]]; then
                echo -e "${RED}Không thể gỡ domain chính của website.${NC}"
                pause; return
            fi
            ea=$(sed_escape_pattern "$alias")
            if ! grep -qE "^[[:space:]]*server_name[[:space:]](.*[[:space:]])?${ea}[[:space:];]" "$conf"; then
                echo "Không tìm thấy alias $alias trong cấu hình."
                pause; return
            fi
            bak=$(backup_nginx_config "$conf")
            # Chỉ sửa trên dòng server_name, chỉ gỡ đúng token của alias
            sed -i -E "/^[[:space:]]*server_name[[:space:]]/ { s/[[:space:]]+www\.${ea}([[:space:];])/\1/g; s/[[:space:]]+${ea}([[:space:];])/\1/g; }" "$conf"
            if nginx_commit "$conf" "$bak"; then
                log_info "Đã gỡ alias $alias."
            else
                log_error "Gỡ alias thất bại - đã giữ nguyên cấu hình cũ."
            fi
            ;;
    esac
    pause
}

protect_folder() {
    select_site || return
    local domain="$SELECTED_DOMAIN"
    local conf="/etc/nginx/sites-available/$domain"
    local user pass

    if [[ ! -f "$conf" ]]; then echo -e "${RED}Config Nginx không tồn tại.${NC}"; pause; return; fi

    read -p "Username: " user
    read -s -p "Password: " pass
    echo ""

    if [[ ! "$user" =~ ^[A-Za-z0-9._-]+$ ]]; then
        echo -e "${RED}Username chỉ được gồm chữ, số, dấu chấm, gạch ngang, gạch dưới.${NC}"
        pause; return
    fi
    if [[ -z "$pass" ]]; then
        echo -e "${RED}Mật khẩu không được để trống.${NC}"
        pause; return
    fi

    if ! command -v htpasswd &> /dev/null; then
        if [[ "$OS_FAMILY" == "rhel" ]]; then
            pkg_install httpd-tools
        else
            pkg_install apache2-utils
        fi
    fi
    if ! command -v htpasswd &> /dev/null; then
        log_error "Không cài được công cụ htpasswd."
        pause; return
    fi

    local auth_file="/etc/nginx/.htpasswd_$domain"
    # Mật khẩu đi qua stdin (-i), không nằm trên dòng lệnh. -c chỉ dùng khi file chưa có
    # (dùng -c mỗi lần sẽ xoá các user đã tạo trước đó).
    local ht_opts="-i"
    [[ ! -f "$auth_file" ]] && ht_opts="-ci"
    if ! printf '%s\n' "$pass" | htpasswd $ht_opts "$auth_file" "$user" >/dev/null 2>&1; then
        log_error "Tạo file mật khẩu thất bại."
        pause; return
    fi
    chown root:www-data "$auth_file" 2>/dev/null
    chmod 640 "$auth_file"
    selinux_restore "$auth_file"

    # Add auth_basic if not present
    if ! grep -q "auth_basic" "$conf"; then
        local bak
        bak=$(backup_nginx_config "$conf")
        sed -i "/server_name/a \    auth_basic \"Restricted Area\";\n    auth_basic_user_file $auth_file;" "$conf"
        if nginx_commit "$conf" "$bak"; then
            log_info "Đã bật mật khẩu bảo vệ cho $domain"
            echo -e "${YELLOW}Lưu ý: khi bật mật khẩu toàn site, gia hạn SSL Let's Encrypt (HTTP challenge) có thể bị chặn 401.${NC}"
        else
            log_error "Bật mật khẩu bảo vệ thất bại - đã giữ nguyên cấu hình cũ."
        fi
    else
        log_info "Cập nhật mật khẩu thành công (Config đã có sẵn)."
    fi
    pause
}

fix_permissions() {
    echo -e "1. Chọn Website cụ thể"
    echo -e "2. Fix tất cả (/var/www)"
    read -p "Chọn: " c

    local target
    if [[ "$c" == "1" ]]; then
        select_site || return
        target="/var/www/$SELECTED_DOMAIN"
    elif [[ "$c" == "2" ]]; then
        target="/var/www"
    else
        return
    fi

    log_info "Đang thiết lập quyền chuẩn cho $target..."

    # .user.ini / .htaccess có thể gây lỗi open_basedir, nhưng cũng có thể chứa cấu hình của người dùng
    # -> chỉ xoá khi được đồng ý.
    local ini_count
    ini_count=$(find "$target" \( -name ".user.ini" -o -name ".htaccess" \) -type f 2>/dev/null | wc -l)
    if [[ "$ini_count" -gt 0 ]]; then
        echo -e "${YELLOW}Tìm thấy $ini_count file .user.ini/.htaccess (Nginx không dùng .htaccess; .user.ini có thể gây lỗi open_basedir).${NC}"
        read -p "Xóa các file này? [y/N]: " del_ini
        if [[ "$del_ini" == "y" || "$del_ini" == "Y" ]]; then
            find "$target" \( -name ".user.ini" -o -name ".htaccess" \) -type f -delete 2>/dev/null
            log_info "Đã xóa .user.ini và .htaccess."
        fi
    fi

    # Phân quyền thông minh: Lấy owner thực tế của thư mục để tránh làm hỏng các web chạy user riêng
    local current_owner site_dir
    if [[ "$c" == "1" ]]; then
        if [[ -d "$target/public_html" ]]; then
            current_owner=$(stat -c '%U:%G' "$target/public_html")
        else
            current_owner=$(stat -c '%U:%G' "$target")
        fi
        [[ "$current_owner" == root:* || "$current_owner" == UNKNOWN* ]] && current_owner="www-data:www-data"
        chown -R "$current_owner" "$target"
    else
        # Nếu fix tất cả, lặp qua từng site để lấy owner riêng của site đó
        for site_dir in "$target"/*; do
            if [[ -d "$site_dir" ]]; then
                if [[ -d "$site_dir/public_html" ]]; then
                    current_owner=$(stat -c '%U:%G' "$site_dir/public_html")
                else
                    current_owner=$(stat -c '%U:%G' "$site_dir")
                fi
                [[ "$current_owner" == root:* || "$current_owner" == UNKNOWN* ]] && current_owner="www-data:www-data"
                chown -R "$current_owner" "$site_dir"
            fi
        done
        # /var/www thuộc root: PHP không được phép tạo/đổi tên thư mục website
        chown root:root "$target"
    fi

    find "$target" -type d -exec chmod 755 {} \;
    find "$target" -type f -exec chmod 644 {} \;
    [[ "$c" == "2" ]] && chmod 755 "$target"

    # File chứa bí mật: KHÔNG để mọi user đọc được
    find "$target" -type f -name "wp-config.php" -exec chmod 640 {} \; 2>/dev/null
    find "$target" -type f \( -name ".env" -o -name ".env.*" \) -not -path "*/node_modules/*" -exec chmod 600 {} \; 2>/dev/null

    # Khôi phục quyền thực thi cho Node.js node_modules (.bin và esbuild) để tránh lỗi EACCES/Permission denied
    if find "$target" -path "*/node_modules" -type d -print -quit 2>/dev/null | grep -q .; then
        log_info "Phát hiện Node.js project. Khôi phục quyền thực thi cho các file trong node_modules..."
        find "$target" -path "*/node_modules/.bin/*" -exec chmod +x {} \; 2>/dev/null
        find "$target" -name "esbuild" -type f -path "*/node_modules/*" -exec chmod +x {} \; 2>/dev/null
    fi

    selinux_allow_web

    log_info "Hoàn tất phân quyền."
    pause
}

check_wp_core() {
    select_site || return
    local domain="$SELECTED_DOMAIN"
    local web_root="/var/www/$domain/public_html"

    echo -e "${YELLOW}--- Kiểm tra & Sửa lỗi WordPress Core ---${NC}"
    echo -e "Tính năng này sẽ tải lại bộ mã nguồn gốc của WordPress (wp-admin, wp-includes) để sửa lỗi thiếu file."
    echo -e "Các file config, wp-content (themes, plugins, uploads) sẽ KHÔNG bị ảnh hưởng."
    echo -e "${RED}Lưu ý: Nếu bạn đã sửa core WP (không khuyến khích), các thay đổi sẽ mất.${NC}"

    if [[ ! -f "$web_root/wp-config.php" ]]; then
        echo -e "${RED}Website này không phải WordPress (không có wp-config.php).${NC}"
        pause; return
    fi

    read -p "Tiếp tục? (y/n): " c
    if [[ "$c" != "y" ]]; then return; fi

    log_info "Đang tải WordPress Core mới nhất..."

    # Tải + giải nén ra thư mục tạm, chỉ chép vào site khi gói hợp lệ
    local tmp_dir
    tmp_dir=$(mktemp -d) || { log_error "Không tạo được thư mục tạm."; pause; return; }
    if ! safe_download "https://wordpress.org/latest.tar.gz" "$tmp_dir/latest.tar.gz"; then
        rm -rf "$tmp_dir"
        log_error "Tải thất bại. Kiểm tra kết nối mạng."
        pause; return
    fi
    if ! tar -xzf "$tmp_dir/latest.tar.gz" -C "$tmp_dir" || [[ ! -f "$tmp_dir/wordpress/wp-includes/version.php" ]]; then
        rm -rf "$tmp_dir"
        log_error "Gói WordPress tải về bị hỏng - không thay đổi gì trên website."
        pause; return
    fi

    log_info "Đang cập nhật Core Files..."

    # Copy core files, overwrite existing (không đụng wp-content của site, không ghi đè wp-config.php)
    rm -rf "$tmp_dir/wordpress/wp-content"
    cp -r "$tmp_dir/wordpress/." "$web_root/"
    rm -rf "$tmp_dir"

    # Fix permissions (giữ nguyên chủ sở hữu hiện tại của site)
    local owner
    owner=$(site_owner "$web_root")
    chown -R "$owner":"$owner" "$web_root"
    find "$web_root" -type d -exec chmod 755 {} \;
    find "$web_root" -type f -exec chmod 644 {} \;
    chmod 640 "$web_root/wp-config.php" 2>/dev/null
    selinux_restore "$web_root"

    log_info "Hoàn tất! Hãy thử truy cập lại website."
    pause
}

toggle_site_cache() {
    echo -e "${YELLOW}--- Bật/Tắt FastCGI Cache (Dev Mode) ---${NC}"
    echo -e "Chế độ Dev Mode sẽ buộc Nginx bỏ qua cache hoàn toàn."
    echo -e "Rất hữu ích khi bạn đang thiết kế hoặc chỉnh sửa code."
    
    echo -e "1. Tùy chỉnh cho MỘT website cụ thể (Chọn từ danh sách)"
    echo -e "2. BẬT cache cho TẤT CẢ website (Production Mode)"
    echo -e "3. TẮT cache cho TẤT CẢ website (Dev Mode toàn hệ thống)"
    read -p "Chọn [1-3]: " mode_c
    
    if [[ "$mode_c" == "2" ]]; then
        log_info "Đang BẬT cache cho TOÀN BỘ hệ thống..."
        for conf in /etc/nginx/sites-available/*; do
            if [[ -f "$conf" ]] && grep -q "skip_cache" "$conf"; then
                sed -i 's/^[[:space:]]*set[[:space:]]*\$skip_cache[[:space:]]*1;[[:space:]]*#[[:space:]]*DEV_MODE_ACTIVE.*/    set $skip_cache 0;/g' "$conf"
            fi
        done
        if nginx_test_reload; then
            log_info "Hoàn tất! Hệ thống đã chạy ở tốc độ tối đa."
        else
            log_error "Nginx chưa reload được - thay đổi CHƯA có hiệu lực."
        fi
        pause; return
    fi
    
    if [[ "$mode_c" == "3" ]]; then
        log_info "Đang TẮT cache cho TOÀN BỘ hệ thống..."
        for conf in /etc/nginx/sites-available/*; do
            if [[ -f "$conf" ]] && grep -q "skip_cache" "$conf"; then
                sed -i 's/^[[:space:]]*set[[:space:]]*\$skip_cache[[:space:]]*0;.*/    set $skip_cache 1; # DEV_MODE_ACTIVE/g' "$conf"
            fi
        done
        rm -rf /var/cache/nginx/fastcgi/* /var/run/nginx-cache/* 2>/dev/null
        if nginx_test_reload; then
            log_info "Hoàn tất! Hệ thống đã ở chế độ Dev Mode."
        else
            log_error "Nginx chưa reload được - thay đổi CHƯA có hiệu lực."
        fi
        pause; return
    fi
    
    if [[ "$mode_c" == "1" ]]; then
        select_site || return
        local domain="$SELECTED_DOMAIN"
        local conf="/etc/nginx/sites-available/$domain"
        
        if [[ ! -f "$conf" ]]; then 
            echo -e "${RED}Config Nginx không tồn tại: $conf${NC}"
            pause; return 
        fi
        
        # Kiểm tra trạng thái hiện tại
        if grep -q "DEV_MODE_ACTIVE" "$conf"; then
            echo -e "Trạng thái FastCGI Cache: ${RED}ĐANG TẮT (Dev Mode)${NC}"
            read -p "Bạn muốn BẬT LẠI cache không? (y/n): " c
            if [[ "$c" == "y" || "$c" == "Y" ]]; then
                local bak
                bak=$(backup_nginx_config "$conf")
                sed -i 's/^[[:space:]]*set[[:space:]]*\$skip_cache[[:space:]]*1;[[:space:]]*#[[:space:]]*DEV_MODE_ACTIVE.*/    set $skip_cache 0;/g' "$conf"
                if nginx_commit "$conf" "$bak"; then
                    log_info "Đã BẬT LẠI Cache cho $domain. Web sẽ load nhanh như chớp!"
                else
                    log_error "Không bật lại được Cache cho $domain - đã giữ nguyên cấu hình cũ."
                fi
            fi
        elif grep -q "skip_cache" "$conf"; then
            echo -e "Trạng thái FastCGI Cache: ${GREEN}ĐANG BẬT (Production Mode)${NC}"
            read -p "Bạn muốn TẮT cache (chuyển sang Dev Mode) không? (y/n): " c
            if [[ "$c" == "y" || "$c" == "Y" ]]; then
                local bak
                bak=$(backup_nginx_config "$conf")
                sed -i 's/^[[:space:]]*set[[:space:]]*\$skip_cache[[:space:]]*0;.*/    set $skip_cache 1; # DEV_MODE_ACTIVE/g' "$conf"

                if nginx_commit "$conf" "$bak"; then
                    # Xóa sạch array cache local để chắc chắn thay đổi áp dụng liền
                    rm -rf /var/cache/nginx/fastcgi/* /var/run/nginx-cache/* 2>/dev/null
                    log_info "Đã TẮT Cache cho $domain. Phù hợp để chỉnh sửa code/giao diện."
                else
                    log_error "Không tắt được Cache cho $domain - đã giữ nguyên cấu hình cũ."
                fi
            fi
        else
            echo -e "${RED}Không tìm thấy cấu hình \$skip_cache trong file config của Nginx!${NC}"
            echo -e "Bạn có thể thử dùng tính năng '5. Cấu hình lại Nginx (Rewrite Vhost)' để thiết lập lại file chuẩn."
        fi
        
        pause
    fi
}

#!/bin/bash

# modules/wordpress_tool.sh - Advanced WordPress Management

wp_tool_menu() {
    while true; do
        clear
        echo -e "${BLUE}=================================================${NC}"
        echo -e "${GREEN}          Quản lý WordPress Nâng cao${NC}"
        echo -e "${BLUE}=================================================${NC}"
        echo -e "1. Quản lý Core & Plugins (Update, Install, Delete)"
        echo -e "2. Quản lý Users (List, Reset Password)"
        echo -e "3. Bảo mật (Lockdown, Disable XMLRPC, Edit File)"
        echo -e "4. Cấu hình Nginx & Cache (Yoast, RankMath, WebP)"
        echo -e "5. Công cụ Databases (Optimize, Delete Revisions)"
        echo -e "6. Cron & Debug (WP-Cron, Debug Mode)"
        echo -e "7. Cài đặt ExifTool (GeoTag Local SEO hình ảnh)"
        echo -e "0. Quay lại Menu chính"
        echo -e "${BLUE}=================================================${NC}"
        read -p "Nhập lựa chọn [0-7]: " choice

        case $choice in
            1) wp_core_plugin_menu ;;
            2) wp_user_menu ;;
            3) wp_security_menu ;;
            4) wp_nginx_config_menu ;;
            5) wp_db_tool_menu ;;
            6) wp_config_tool_menu ;;
            7) install_exiftool ;;
            0) return ;;
            *) echo -e "${RED}Lựa chọn không hợp lệ!${NC}"; pause ;;
        esac
    done
}

# --- Helpers ---

# Đường dẫn wp-config.php của 1 site: trong public_html, hoặc thư mục cha (khi đã "Move wp-config").
# In ra đường dẫn và trả về 0 nếu tìm thấy.
_wp_config_path() {
    local domain=$1 f
    for f in "/var/www/$domain/public_html/wp-config.php" "/var/www/$domain/wp-config.php"; do
        if [[ -f "$f" ]]; then echo "$f"; return 0; fi
    done
    return 1
}

# Cài 1 snippet nginx mới cho vhost, có rollback.
# Nội dung mới phải được ghi sẵn ra "<snippet>.new". Nếu nginx -t lỗi: snippet cũ và vhost được khôi phục.
# Dùng: _wp_install_snippet <conf> <snippet>
_wp_install_snippet() {
    local conf=$1 snippet=$2
    local had_old=0
    [[ -f "${snippet}.new" ]] || { log_error "Thiếu file ${snippet}.new"; return 1; }
    if [[ -f "$snippet" ]]; then cp -f "$snippet" "${snippet}.old"; had_old=1; fi
    mv -f "${snippet}.new" "$snippet"

    if grep -qF "include $snippet;" "$conf"; then
        if nginx_test_reload; then
            rm -f "${snippet}.old"
            return 0
        fi
    else
        if nginx_add_include "$conf" "$snippet"; then
            rm -f "${snippet}.old"
            return 0
        fi
    fi

    # Thất bại -> trả snippet về trạng thái cũ
    if [[ "$had_old" -eq 1 ]]; then
        mv -f "${snippet}.old" "$snippet"
    else
        rm -f "$snippet"
    fi
    return 1
}

select_wp_site() {
    echo -e "\n${CYAN}Danh sách WordPress Sites:${NC}"
    sites=()
    i=1
    for d in /var/www/*; do
        if [[ -d "$d/public_html" ]] && _wp_config_path "$(basename "$d")" >/dev/null; then
            domain=$(basename "$d")
            sites+=("$domain")
            echo -e "$i. $domain"
            ((i++))
        fi
    done
    
    if [[ ${#sites[@]} -eq 0 ]]; then
        echo -e "${RED}Không tìm thấy website WordPress nào!${NC}"
        return 1
    fi
    
    read -p "Chọn website [1-${#sites[@]}]: " w_choice
    if ! [[ "$w_choice" =~ ^[0-9]+$ ]] || [[ "$w_choice" -lt 1 ]] || [[ "$w_choice" -gt "${#sites[@]}" ]]; then
        echo -e "${RED}Lựa chọn sai.${NC}"
        return 1
    fi
    
    SELECTED_DOMAIN="${sites[$((w_choice-1))]}"
    WEB_ROOT="/var/www/$SELECTED_DOMAIN/public_html"
    
    WP_PHP_BIN="php"
    SITE_CONF="/etc/nginx/sites-available/$SELECTED_DOMAIN"
    if [[ -f "$SITE_CONF" ]]; then
        SITE_PHP_VER=$(grep -v '^[[:space:]]*#' "$SITE_CONF" 2>/dev/null | grep 'fastcgi_pass' | grep -oP 'php\K[0-9.]+(?=-fpm)' | head -n 1)
        if [[ -n "$SITE_PHP_VER" ]] && command -v "php$SITE_PHP_VER" >/dev/null 2>&1; then
            WP_PHP_BIN="php$SITE_PHP_VER"
        fi
    fi
    
    # Fallback to ANY valid PHP version with MySQL module if the above fails
    if ! "$WP_PHP_BIN" -m 2>/dev/null | grep -qEi "(mysqli|pdo_mysql)"; then
        for v in 8.3 8.4 8.5 8.2 8.1 8.0 7.4; do
            if command -v "php$v" >/dev/null 2>&1 && "php$v" -m 2>/dev/null | grep -qEi "(mysqli|pdo_mysql)"; then
                WP_PHP_BIN="php$v"
                break
            fi
        done
    fi
    
    # WP-CLI chạy bằng user sở hữu site (không phải root) - xem core/platform_helpers.sh
    WP_CMD=$(wp_cmd_prefix "$WEB_ROOT" "$WP_PHP_BIN")

    echo -e "${GREEN}Đã chọn: $SELECTED_DOMAIN${NC}"
    return 0
}

# ensure_wp_cli: dùng bản trong core/platform_helpers.sh (tải có kiểm tra sha512)

# --- 1. Core & Plugins ---
wp_core_plugin_menu() {
    select_wp_site || return
    ensure_wp_cli || { pause; return; }

    while true; do
        echo -e "\n${YELLOW}Core & Plugins - $SELECTED_DOMAIN${NC}"
        echo "1. Update WordPress Core"
        echo "2. List Plugins"
        echo "3. Update All Plugins"
        echo "4. Install Plugin"
        echo "5. Delete Plugin"
        echo "6. Deactivate Plugin"
        echo "0. Back"
        read -p "Select: " c
        
        case $c in
            1) $WP_CMD core update; pause ;;
            2) $WP_CMD plugin list; pause ;;
            3) $WP_CMD plugin update --all; pause ;;
            4) read -p "Plugin slug/zip: " p; $WP_CMD plugin install "$p" --activate; pause ;;
            5) read -p "Plugin slug: " p; $WP_CMD plugin delete "$p"; pause ;;
            6) read -p "Plugin slug: " p; $WP_CMD plugin deactivate "$p"; pause ;;
            0) return ;;
        esac
    done
}

# --- 2. Users ---
wp_user_menu() {
    select_wp_site || return
    ensure_wp_cli || { pause; return; }

    while true; do
        echo -e "\n${YELLOW}User Management - $SELECTED_DOMAIN${NC}"
        echo "1. List Users"
        echo "2. Reset Password (User ID/Login)"
        echo "3. Create Admin User"
        echo "0. Back"
        read -p "Select: " c
        
        case $c in
            1) $WP_CMD user list; pause ;;
            2) 
                echo -e "${YELLOW}Danh sách User:${NC}"
                $WP_CMD user list
                echo ""
                read -p "Nhập ID hoặc Username cần reset: " u
                read -sp "Nhập Password mới (không hiển thị): " p
                echo ""
                if [[ -z "$u" || -z "$p" ]]; then
                    log_error "User và Password không được để trống."
                    pause; continue
                fi
                echo "Đang cập nhật..."
                # Mật khẩu đi qua stdin (--prompt) để không lộ trong danh sách tiến trình
                if printf '%s\n' "$p" | $WP_CMD user update "$u" --prompt=user_pass; then
                    log_info "Đã đổi mật khẩu cho user $u."
                else
                    log_error "Đổi mật khẩu thất bại."
                fi
                unset p
                pause
                ;;
            3)
                read -p "Username: " u
                read -p "Email: " e
                read -sp "Password (Enter để tự sinh): " wp
                echo ""
                local generated=0
                if [[ -z "$wp" ]]; then
                    wp=$(openssl rand -base64 24 | tr -dc 'a-zA-Z0-9' | head -c 16)
                    generated=1
                fi
                if printf '%s\n' "$wp" | $WP_CMD user create "$u" "$e" --role=administrator --prompt=user_pass; then
                    if [[ "$generated" -eq 1 ]]; then
                        echo -e "${GREEN}Admin tạo thành công! User: $u | Pass (tự sinh, hãy lưu lại): $wp${NC}"
                    else
                        echo -e "${GREEN}Admin tạo thành công! User: $u${NC}"
                    fi
                else
                    log_error "Tạo user thất bại."
                fi
                unset wp
                pause
                ;;
            0) return ;;
        esac
    done
}

# --- 3. Security ---
wp_security_menu() {
    select_wp_site || return
    ensure_wp_cli || { pause; return; }

    while true; do
        echo -e "\n${YELLOW}Security - $SELECTED_DOMAIN${NC}"
        echo "1. Disable XML-RPC (Chặn tấn công Brute Force)"
        echo "2. Enable XML-RPC (Mở lại nếu dùng App Mobile/Jetpack)"
        echo "3. Disable File Edit (Tắt sửa code trong Admin - Khuyên dùng)"
        echo "4. Enable File Edit"
        echo "5. Move wp-config.php (Di chuyển ra khỏi public_html)"
        echo "0. Back"
        read -p "Select: " c
        
        conf="/etc/nginx/sites-available/$SELECTED_DOMAIN"
        
        case $c in
            1) # Disable XMLRPC
                snippet="/etc/nginx/snippets/block-xmlrpc.conf"
                if [[ ! -f "$snippet" ]]; then
                    mkdir -p /etc/nginx/snippets
                    echo 'location = /xmlrpc.php { deny all; access_log off; log_not_found off; }' > "$snippet"
                fi
                
                # Check current conf
                if grep -q "block-xmlrpc.conf" "$conf"; then
                    log_warn "XML-RPC đã bị chặn trước đó."
                elif nginx_add_include "$conf" "$snippet"; then
                    log_info "Đã chặn XML-RPC thành công."
                else
                    log_error "Không áp dụng được (vhost đã được khôi phục như cũ)."
                fi
                pause
                ;;
            2) # Enable XMLRPC
                if nginx_remove_include "$conf" "/etc/nginx/snippets/block-xmlrpc.conf"; then
                    log_info "Đã mở lại XML-RPC."
                else
                    log_error "Không gỡ được rule chặn XML-RPC (vhost đã được khôi phục như cũ)."
                fi
                pause
                ;;
            3) # Disable File Edit
                if $WP_CMD config set DISALLOW_FILE_EDIT true --raw --type=constant; then
                    log_info "Đã tắt chức năng sửa file (Editor) trong Admin."
                else
                    log_error "Không ghi được wp-config.php."
                fi
                pause
                ;;
            4) # Enable File Edit
                if $WP_CMD config set DISALLOW_FILE_EDIT false --raw --type=constant; then
                    log_info "Đã mở lại chức năng sửa file."
                else
                    log_error "Không ghi được wp-config.php."
                fi
                pause
                ;;
            5) # Move wp-config
                current_config="$WEB_ROOT/wp-config.php"
                parent_config="$(dirname "$WEB_ROOT")/wp-config.php"
                local cfg_owner
                cfg_owner=$(site_owner "$WEB_ROOT")

                if [[ -f "$current_config" ]]; then
                    if mv "$current_config" "$parent_config"; then
                        # 640: chủ site đọc/ghi, nhóm đọc; không ai khác đọc được
                        chown "$cfg_owner:$cfg_owner" "$parent_config"
                        chmod 640 "$parent_config"
                        log_info "Đã di chuyển wp-config.php ra khỏi public_html."
                        echo -e "${GREEN}Vị trí mới: $parent_config${NC}"
                        echo -e "WordPress tự tìm thấy file này. Các menu WordPress/Cache của VPS Manager vẫn nhận diện site."
                        echo -e "${YELLOW}Lưu ý: nếu site dùng pool PHP riêng có open_basedir chỉ tới public_html, hãy nới open_basedir ra /var/www/$SELECTED_DOMAIN/.${NC}"
                    else
                        log_error "Không di chuyển được wp-config.php."
                    fi
                elif [[ -f "$parent_config" ]]; then
                    log_warn "wp-config.php ĐANG nằm ngoài public_html!"
                    read -p "Bạn có muốn di chuyển nó TRỞ LẠI public_html không? (y/n): " move_back
                    if [[ "$move_back" == "y" ]]; then
                        if mv "$parent_config" "$WEB_ROOT/wp-config.php"; then
                            chown "$cfg_owner:$cfg_owner" "$WEB_ROOT/wp-config.php"
                            chmod 640 "$WEB_ROOT/wp-config.php"
                            log_info "Đã di chuyển wp-config.php về lại public_html."
                        else
                            log_error "Không di chuyển được wp-config.php."
                        fi
                    fi
                else
                    echo -e "${RED}Lỗi: Không tìm thấy file wp-config.php ở đâu cả!${NC}"
                fi
                pause
                ;;
            0) return ;;
        esac
    done
}

# --- 4. Nginx & SEO Configs ---
wp_nginx_config_menu() {
    select_wp_site || return
    
    # Use sites-available config
    local conf="/etc/nginx/sites-available/$SELECTED_DOMAIN"
    if [[ ! -f "$conf" ]]; then
        echo -e "${RED}Không tìm thấy file cấu hình Nginx cho $SELECTED_DOMAIN${NC}"
        pause; return
    fi
    
    local snippet_dir="/etc/nginx/snippets"
    mkdir -p "$snippet_dir"

    while true; do
        clear
        echo -e "${BLUE}=================================================${NC}"
        echo -e "${GREEN}   ⚙️  Nginx SEO & Security Configs - $SELECTED_DOMAIN${NC}"
        echo -e "${BLUE}=================================================${NC}"
        echo "1. Apply Yoast SEO Nginx Rules (Standard + Premium)"
        echo "2. Apply Rank Math SEO Nginx Rules (with XSL style support)"
        echo "3. Apply WebP Express Rules"
        echo "4. Block User Enumeration API (Security)"
        echo "5. Apply Advanced Security Hardening (Block Backups, sensitive files, PHP in Cache)"
        echo "0. Quay lại"
        echo -e "${BLUE}=================================================${NC}"
        read -p "Chọn [0-5]: " c

        case $c in
            0) return ;;
        1) # Yoast
            snippet="$snippet_dir/yoast-$SELECTED_DOMAIN.conf"
            log_info "Tạo cấu hình Yoast SEO (Premium)..."
            cat > "${snippet}.new" <<EOF
# Yoast SEO Sitemaps (including Premium extension rewrites)
location ~ ([^/]*)sitemap(.*).x(m|s)l$ {
  rewrite ^/sitemap.xml$ /sitemap_index.xml permanent;
  rewrite ^/([a-z]+)?-?sitemap.xsl$ /index.php?yoast-sitemap-xsl=\$1 last;
  rewrite ^/sitemap_index.xml$ /index.php?sitemap=1 last;
  rewrite ^/([^/]+?)-sitemap([0-9]+)?.xml$ /index.php?sitemap=\$1&sitemap_n=\$2 last;
  
  # Premium Extensions
  rewrite ^/news-sitemap.xml$ /index.php?sitemap=wpseo_news last;
  rewrite ^/locations.kml$ /index.php?sitemap=wpseo_local_kml last;
  rewrite ^/geo-sitemap.xml$ /index.php?sitemap=wpseo_local last;
  rewrite ^/video-sitemap.xsl$ /index.php?yoast-sitemap-xsl=video last;
}
EOF
            if _wp_install_snippet "$conf" "$snippet"; then
                log_info "Đã áp dụng Yoast SEO Rules thành công."
            else
                log_error "Áp dụng Yoast SEO Rules thất bại - cấu hình đã được hoàn tác."
            fi
            pause
            ;;
            
        2) # Rank Math
            snippet="$snippet_dir/rankmath-$SELECTED_DOMAIN.conf"
            log_info "Tạo cấu hình Rank Math..."
            cat > "${snippet}.new" <<EOF
# Rank Math Sitemaps (including XSL stylesheets support)
rewrite ^/sitemap_index.xml$ /index.php?sitemap=1 last;
rewrite ^/([^/]+?)-sitemap([0-9]+)?.xml$ /index.php?sitemap=\$1&sitemap_n=\$2 last;
rewrite ^/([a-z]+)?-sitemap\.xsl$ /index.php?xsl=\$1 last;
EOF
            if _wp_install_snippet "$conf" "$snippet"; then
                log_info "Đã áp dụng Rank Math Rules thành công."
            else
                log_error "Áp dụng Rank Math Rules thất bại - cấu hình đã được hoàn tác."
            fi
            pause
            ;;
            
        3) # WebP Express
            snippet="$snippet_dir/webp-$SELECTED_DOMAIN.conf"
            log_info "Tạo cấu hình WebP Express..."
            cat > "${snippet}.new" <<EOF
# WebP Express Rules
location ~ ^/wp-content/(.*\.(png|jpe?g))$ {
  add_header Vary Accept;
  expires 365d;
  if (\$http_accept !~* "webp"){
    break;
  }
  try_files /wp-content/webp-express/webp-images/doc-root/wp-content/\$1.webp \$uri =404;
}
EOF
            if _wp_install_snippet "$conf" "$snippet"; then
                log_info "Đã áp dụng WebP Express Rules thành công."
            else
                log_error "Áp dụng WebP Express Rules thất bại - cấu hình đã được hoàn tác."
            fi
            pause
            ;;

        4) # Block User Enum
            snippet="$snippet_dir/block-enum-$SELECTED_DOMAIN.conf"
            # - Chỉ chặn dò author ở FRONT-END (/?author=N). Không đụng tới wp-admin
            #   (vd: edit.php?post_type=post&author=1 - bộ lọc "Của tôi").
            # - REST /wp/v2/users: chỉ chặn khách CHƯA đăng nhập, để Gutenberg (chọn tác giả, users/me) vẫn chạy.
            cat > "${snippet}.new" <<EOF
# Block User ID Enumeration (front-end only)
if (\$request_uri ~* "^/(index\.php)?\?(.*&)?author=[0-9]") {
    return 403;
}
location ~* ^/wp-json/wp/v2/users {
    if (\$http_cookie !~* "wordpress_logged_in_") {
        return 403;
    }
    try_files \$uri \$uri/ /index.php?\$args;
}
EOF
            if _wp_install_snippet "$conf" "$snippet"; then
                log_info "Đã chặn User Enumeration."
            else
                log_error "Chặn User Enumeration thất bại - cấu hình đã được hoàn tác."
            fi
            pause
            ;;

        5) # Security Hardening
            snippet="$snippet_dir/hardening-$SELECTED_DOMAIN.conf"
            log_info "Tạo cấu hình Security Hardening..."
            # Ghi chú thứ tự: snippet được include ngay sau server_name, tức là TRƯỚC "location ~ \.php\$"
            # của vhost. Nginx chọn regex location khớp ĐẦU TIÊN, nên rule chặn PHP trong cache bên dưới
            # phải nằm trước location PHP thì mới có tác dụng. Đừng chuyển dòng include xuống cuối vhost.
            cat > "${snippet}.new" <<EOF
# Comprehensive Security Hardening (Inspired by HOSTVN & VPS Manager)
# NOTE: file nay phai duoc include TRUOC "location ~ \.php\$" cua vhost.

# File dump / backup database (khong chan cac URL bai viet bat dau bang /sql...)
location ~* \.(sql|sql\.gz|sql\.zip|sql\.bz2|dump|bak)\$ { access_log off; log_not_found off; return 444; }
location ^~ /wp-content/updraft { access_log off; log_not_found off; return 444; }
location ^~ /wp-content/backups-dup-pro { access_log off; log_not_found off; return 444; }
location ^~ /wp-snapshots { access_log off; log_not_found off; return 444; }
location ^~ /wp-content/uploads/sucuri { access_log off; log_not_found off; return 444; }
location ^~ /wp-content/uploads/nginx-helper { access_log off; log_not_found off; return 444; }
location = /wp-config.php { access_log off; log_not_found off; return 444; }
location = /wp-config-sample.php { access_log off; log_not_found off; return 444; }
location = /readme.html { access_log off; log_not_found off; return 444; }
location = /license.txt { access_log off; log_not_found off; return 444; }

# Chan thuc thi PHP trong thu muc cache (regex cap server, dung truoc location PHP)
location ~* ^/wp-content/cache/.*\.php\$ { access_log off; log_not_found off; return 444; }

# CSS/JS da minify trong cache: cache trinh duyet dai han (KHONG ap dung cho .html)
location ~* ^/wp-content/cache/.*\.(?:css|js)(\.map)?\$ {
    add_header Access-Control-Allow-Origin *;
    access_log off;
    log_not_found off;
    expires 365d;
}
EOF
            if _wp_install_snippet "$conf" "$snippet"; then
                log_info "Đã áp dụng Security Hardening Rules thành công."
            else
                log_error "Áp dụng Security Hardening thất bại - cấu hình đã được hoàn tác."
            fi
            pause
            ;;
            *) echo -e "${RED}Lựa chọn không hợp lệ!${NC}"; pause ;;
        esac
    done
}

# --- 5. DB Tools ---
wp_db_tool_menu() {
    select_wp_site || return
    ensure_wp_cli || { pause; return; }

    while true; do
        clear
        echo -e "${BLUE}=================================================${NC}"
        echo -e "${GREEN}   🗄️  Database Tools - $SELECTED_DOMAIN${NC}"
        echo -e "${BLUE}=================================================${NC}"
        echo "1. Optimize Database"
        echo "2. Delete Post Revisions"
        echo "3. Delete Spam Comments"
        echo "0. Quay lại"
        echo -e "${BLUE}=================================================${NC}"
        read -p "Chọn [0-3]: " c
        
        case $c in
            1) $WP_CMD db optimize; pause ;;
            2) 
                log_info "Deleting revisions..."
                local rev_ids
                rev_ids=$($WP_CMD post list --post_type='revision' --format=ids 2>/dev/null)
                if [[ -z "$rev_ids" ]]; then
                    log_info "Không có revision nào để xoá."
                elif $WP_CMD post delete $rev_ids --force >/dev/null; then
                    log_info "Đã xoá $(echo "$rev_ids" | wc -w) revision."
                else
                    log_error "Xoá revision thất bại."
                fi
                pause
                ;;
            3)
                local spam_ids
                spam_ids=$($WP_CMD comment list --status=spam --format=ids 2>/dev/null)
                if [[ -z "$spam_ids" ]]; then
                    log_info "Không có comment spam nào."
                elif $WP_CMD comment delete $spam_ids --force >/dev/null; then
                    log_info "Đã xoá $(echo "$spam_ids" | wc -w) comment spam."
                else
                    log_error "Xoá comment spam thất bại."
                fi
                pause
                ;;
            0) return ;;
            *) echo -e "${RED}Lựa chọn không hợp lệ!${NC}"; pause ;;
        esac
    done
}

# --- 6. Config Tools (Debug/Maintenance) ---
wp_config_tool_menu() {
    select_wp_site || return
    ensure_wp_cli || { pause; return; }

    while true; do
        clear
        echo -e "\n${YELLOW}Config Tools - $SELECTED_DOMAIN${NC}"
        echo -e "${BLUE}=================================================${NC}"
        echo -e "  ${CYAN}--- Debug ---${NC}"
        echo -e "  1. Enable WP_DEBUG (Bật chế độ debug)"
        echo -e "  2. Disable WP_DEBUG (Tắt debug, production)"
        echo ""
        echo -e "  ${CYAN}--- Cron ---${NC}"
        echo -e "  3. ${GREEN}⏰ Mở Cron Manager${NC} (WP-Cron, APRG Cron, Log...)"
        echo ""
        echo -e "  ${CYAN}--- Maintenance ---${NC}"
        echo -e "  4. Enable Maintenance Mode (Bật trang bảo trì)"
        echo -e "  5. Disable Maintenance Mode (Tắt trang bảo trì)"
        echo ""
        echo -e "  ${CYAN}--- Performance ---${NC}"
        echo -e "  6. Fix Upload Limits (Sửa lỗi tải file 2MB & 413 Error)"
        echo -e "${BLUE}=================================================${NC}"
        echo -e "  0. Quay lại"
        read -p "Select: " c

        case $c in
            1)
                $WP_CMD config set WP_DEBUG true --raw
                $WP_CMD config set WP_DEBUG_LOG true --raw
                $WP_CMD config set WP_DEBUG_DISPLAY true --raw
                if ! $WP_CMD eval "if(strpos(file_get_contents(ABSPATH . 'wp-config.php'), 'display_errors') === false) { file_put_contents(ABSPATH . 'wp-config.php', str_replace(\"define( 'WP_DEBUG', true );\", \"define( 'WP_DEBUG', true );\n@ini_set('display_errors', 1);\", file_get_contents(ABSPATH . 'wp-config.php'))); }"; then
                    echo "Could not inject display_errors via eval."
                fi
                log_info "Đã BẬT WP_DEBUG cho $SELECTED_DOMAIN."
                pause
                ;;
            2)
                $WP_CMD config set WP_DEBUG false --raw
                $WP_CMD config set WP_DEBUG_LOG false --raw
                $WP_CMD config set WP_DEBUG_DISPLAY false --raw
                $WP_CMD eval "file_put_contents(ABSPATH . 'wp-config.php', preg_replace('/@ini_set\(\\'display_errors\\', [01]\);\r?\n?/', '', file_get_contents(ABSPATH . 'wp-config.php')));"
                log_info "Đã TẮT WP_DEBUG cho $SELECTED_DOMAIN."
                pause
                ;;
            3)
                # Redirect to full Cron Manager module
                local module_dir
                module_dir="$(dirname "${BASH_SOURCE[0]}")"
                source "$module_dir/cron.sh"
                cron_menu
                ;;
            4)
                $WP_CMD maintenance-mode activate
                log_info "Đã bật Maintenance Mode."
                pause
                ;;
            5)
                $WP_CMD maintenance-mode deactivate
                log_info "Đã tắt Maintenance Mode."
                pause
                ;;
            6)
                log_info "Đang sửa giới hạn dung lượng tải lên toàn server..."

                # Debian/Ubuntu: /etc/php/X.Y/fpm/php.ini ; RHEL/Oracle: /etc/php.ini
                local ini_count=0 fpm_fail=0 php_ini pv svc
                for php_ini in /etc/php/*/fpm/php.ini /etc/php.ini; do
                    if [[ -f "$php_ini" ]]; then
                        sed -i -E "s/^[; ]*upload_max_filesize.*/upload_max_filesize = 128M/" "$php_ini"
                        sed -i -E "s/^[; ]*post_max_size.*/post_max_size = 128M/" "$php_ini"
                        sed -i -E "s/^[; ]*memory_limit.*/memory_limit = 256M/" "$php_ini"
                        sed -i -E "s/^[; ]*max_execution_time.*/max_execution_time = 300/" "$php_ini"
                        sed -i -E "s/^[; ]*max_input_vars.*/max_input_vars = 3000/" "$php_ini"
                        ini_count=$((ini_count + 1))
                    fi
                done

                if [[ "$ini_count" -eq 0 ]]; then
                    log_error "Không tìm thấy php.ini nào của PHP-FPM. Chưa thay đổi gì."
                    pause; continue
                fi

                local nginx_bak=""
                if [[ -f /etc/nginx/nginx.conf ]]; then
                    nginx_bak=$(backup_nginx_config /etc/nginx/nginx.conf)
                    if ! grep -q "client_max_body_size" /etc/nginx/nginx.conf; then
                        sed -i '/http {/a \        client_max_body_size 128M;' /etc/nginx/nginx.conf
                    else
                        sed -i "s/client_max_body_size.*/client_max_body_size 128M;/" /etc/nginx/nginx.conf
                    fi
                fi

                # Restart PHP-FPM (có kiểm tra config trước)
                if [[ "$OS_FAMILY" == "rhel" ]]; then
                    php_fpm_restart_safe || fpm_fail=1
                else
                    for php_ini in /etc/php/*/fpm/php.ini; do
                        [[ -f "$php_ini" ]] || continue
                        pv=$(echo "$php_ini" | grep -oE '[0-9]+\.[0-9]+' | head -n 1)
                        svc=$(php_fpm_service "$pv")
                        systemctl is-enabled --quiet "$svc" 2>/dev/null || systemctl is-active --quiet "$svc" 2>/dev/null || continue
                        php_fpm_restart_safe "$pv" || fpm_fail=1
                    done
                fi

                if ! nginx_commit /etc/nginx/nginx.conf "$nginx_bak"; then
                    log_error "Nginx chưa nhận giới hạn mới (nginx.conf đã được khôi phục)."
                elif [[ "$fpm_fail" -ne 0 ]]; then
                    log_error "Đã sửa php.ini nhưng có PHP-FPM không restart được - xem lỗi ở trên."
                else
                    log_info "Đã tăng giới hạn Upload lên 128MB thành công! ($ini_count php.ini)"
                    echo -e "${GREEN}Hãy tải lại trang và upload lại nhé.${NC}"
                fi
                pause
                ;;
            0) return ;;
            *) echo -e "${RED}Lựa chọn không hợp lệ!${NC}"; pause ;;
        esac
    done
}

install_exiftool() {
    echo -e "\n${BLUE}=================================================${NC}"
    echo -e "${GREEN}   Cài đặt ExifTool (GeoTag Local SEO hình ảnh)${NC}"
    echo -e "${BLUE}=================================================${NC}"
    echo -e "Công cụ cần thiết để ghi siêu dữ liệu GPS (vĩ độ, kinh độ),"
    echo -e "tiêu đề, từ khóa trực tiếp vào hình ảnh WordPress."
    echo -e "${BLUE}=================================================${NC}"
    
    echo -e "\n${YELLOW}Đang kiểm tra trạng thái ExifTool trên hệ thống...${NC}"
    if command -v exiftool &> /dev/null; then
        echo -e "${GREEN}✓ ExifTool đã được cài đặt trên hệ thống!${NC}"
        echo -e "Đường dẫn: ${CYAN}$(which exiftool)${NC}"
        echo -n "Phiên bản hiện tại: "
        exiftool -ver
    else
        echo -e "${YELLOW}ExifTool chưa được cài đặt. Tiến hành cài đặt tự động...${NC}"
        if [[ "$OS_FAMILY" == "debian" ]]; then
            pkg_update
            pkg_install exiftool
        elif [[ "$OS_FAMILY" == "rhel" ]]; then
            pkg_install epel-release
            pkg_install perl-Image-ExifTool
        else
            echo -e "${RED}Hệ điều hành không hỗ trợ tự động cài đặt. Vui lòng cài đặt thủ công ExifTool.${NC}"
        fi
        
        if command -v exiftool &> /dev/null; then
            echo -e "${GREEN}✓ Cài đặt ExifTool thành công!${NC}"
            echo -e "Đường dẫn: ${CYAN}$(which exiftool)${NC}"
            echo -n "Phiên bản: "
            exiftool -ver
        else
            echo -e "${RED}✗ Cài đặt ExifTool thất bại. Vui lòng kiểm tra kết nối mạng hoặc cài đặt thủ công.${NC}"
        fi
    fi
    pause
}

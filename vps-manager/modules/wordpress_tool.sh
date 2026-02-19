#!/bin/bash

# modules/wordpress_tool.sh - Advanced WordPress Management

wp_tool_menu() {
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
    echo -e "0. Quay lại Menu chính"
    echo -e "${BLUE}=================================================${NC}"
    read -p "Nhập lựa chọn [0-6]: " choice

    case $choice in
        1) wp_core_plugin_menu ;;
        2) wp_user_menu ;;
        3) wp_security_menu ;;
        4) wp_nginx_config_menu ;;
        5) wp_db_tool_menu ;;
        6) wp_config_tool_menu ;;
        0) return ;;
        *) echo -e "${RED}Lựa chọn không hợp lệ!${NC}"; pause ;;
    esac
}

# --- Helpers ---
select_wp_site() {
    echo -e "\n${CYAN}Danh sách WordPress Sites:${NC}"
    sites=()
    i=1
    for d in /var/www/*; do
        if [[ -d "$d" && -f "$d/public_html/wp-config.php" ]]; then
            domain=$(basename "$d")
            sites+=("$domain")
            echo -e "$i. $domain"
            ((i++))
        fi
    done
    
    if [ ${#sites[@]} -eq 0 ]; then
        echo -e "${RED}Không tìm thấy website WordPress nào!${NC}"
        return 1
    fi
    
    read -p "Chọn website [1-${#sites[@]}]: " w_choice
    if ! [[ "$w_choice" =~ ^[0-9]+$ ]] || [ "$w_choice" -lt 1 ] || [ "$w_choice" -gt "${#sites[@]}" ]; then
        echo -e "${RED}Lựa chọn sai.${NC}"
        return 1
    fi
    
    SELECTED_DOMAIN="${sites[$((w_choice-1))]}"
    WEB_ROOT="/var/www/$SELECTED_DOMAIN/public_html"
    WP_CMD="wp --path=$WEB_ROOT --allow-root"
    
    echo -e "${GREEN}Đã chọn: $SELECTED_DOMAIN${NC}"
    return 0
}

ensure_wp_cli() {
    # 1. Install WP-CLI if missing
    if ! command -v wp &> /dev/null; then
        echo -e "${YELLOW}Installing WP-CLI...${NC}"
        curl -O https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar
        chmod +x wp-cli.phar
        mv wp-cli.phar /usr/local/bin/wp
    fi
    
    # 2. Force Install & Enable PHP MySQL & XML Extensions (Required for WP-CLI & Plugins)
    # Check if critical modules are missing
    if ! php -m | grep -q "mysql" || ! php -m | grep -q "dom" || ! php -m | grep -q "mbstring"; then
        echo -e "${YELLOW}Đang cài đặt PHP Extensions (MySQL, XML, MBString)...${NC}"
        apt-get update -qq
        # Install for all supported versions to be safe
        apt-get install -y php-mysql php8.1-mysql php8.2-mysql php8.3-mysql \
                           php-xml php8.1-xml php8.2-xml php8.3-xml \
                           php-mbstring php8.1-mbstring php8.2-mbstring php8.3-mbstring \
                           php-curl php8.1-curl php8.2-curl php8.3-curl \
                           php-zip php8.1-zip php8.2-zip php8.3-zip
        
        # 3. Enable modules properly
        if command -v phpenmod &> /dev/null; then
            phpenmod -v ALL mysql mysqli pdo_mysql xml dom mbstring curl zip
        fi
        echo -e "${GREEN}Đã cài đặt và kích hoạt các extension cần thiết.${NC}"
    fi
}

# --- 1. Core & Plugins ---
wp_core_plugin_menu() {
    select_wp_site || return
    ensure_wp_cli
    
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
    ensure_wp_cli
    
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
                read -p "Nhập Password mới: " p
                echo "Đang cập nhật..."
                $WP_CMD user update "$u" --user_pass="$p"
                pause 
                ;;
            3)
                read -p "Username: " u
                read -p "Email: " e
                read -sp "Password (Enter để tự sinh): " wp
                echo ""
                if [ -z "$wp" ]; then wp=$(openssl rand -base64 12 | tr -dc 'a-zA-Z0-9' | head -c 14); fi
                $WP_CMD user create "$u" "$e" --role=administrator --user_pass="$wp"
                echo -e "${GREEN}Admin tạo thành công!— User: $u | Pass: $wp${NC}"
                pause
                ;;
            0) return ;;
        esac
    done
}

# --- 3. Security ---
wp_security_menu() {
    select_wp_site || return
    ensure_wp_cli
    
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
                if [ ! -f "$snippet" ]; then
                    mkdir -p /etc/nginx/snippets
                    echo 'location = /xmlrpc.php { deny all; access_log off; log_not_found off; }' > "$snippet"
                fi
                
                # Check current conf
                if ! grep -q "block-xmlrpc.conf" "$conf"; then
                    # Insert include
                    sed -i "/server_name/a \    include $snippet;" "$conf"
                    nginx -t && systemctl reload nginx
                    log_info "Đã chặn XML-RPC thành công."
                else
                    log_warn "XML-RPC đã bị chặn trước đó."
                fi
                pause
                ;;
            2) # Enable XMLRPC
                sed -i '/block-xmlrpc.conf/d' "$conf"
                nginx -t && systemctl reload nginx
                log_info "Đã mở lại XML-RPC."
                pause
                ;;
            3) # Disable File Edit
                $WP_CMD config set DISALLOW_FILE_EDIT true --raw --type=constant
                log_info "Đã tắt chức năng sửa file (Editor) trong Admin."
                pause
                ;;
            4) # Enable File Edit
                $WP_CMD config set DISALLOW_FILE_EDIT false --raw --type=constant
                log_info "Đã mở lại chức năng sửa file."
                pause
                ;;
            5) # Move wp-config
                current_config="$WEB_ROOT/wp-config.php"
                parent_config="$(dirname "$WEB_ROOT")/wp-config.php"
                
                if [ -f "$current_config" ]; then
                    mv "$current_config" "$parent_config"
                    # Fix permissions just in case
                    chmod 600 "$parent_config"
                    chown www-data:www-data "$parent_config"
                    
                    log_info "Đã di chuyển wp-config.php ra khỏi public_html."
                    echo -e "${GREEN}Vị trí mới: $parent_config${NC}"
                    echo -e "Đây là biện pháp bảo mật khuyến nghị. WordPress sẽ tự động tìm thấy file này."
                elif [ -f "$parent_config" ]; then
                    log_warn "wp-config.php ĐANG nằm ngoài public_html!"
                    read -p "Bạn có muốn di chuyển nó TRỞ LẠI public_html không? (y/n): " move_back
                    if [[ "$move_back" == "y" ]]; then
                        mv "$parent_config" "$WEB_ROOT/wp-config.php"
                        log_info "Đã di chuyển wp-config.php về lại public_html."
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
    
    echo -e "\n${YELLOW}Nginx SEO Configs - $SELECTED_DOMAIN${NC}"
    echo "1. Apply Yoast SEO Nginx Rules"
    echo "2. Apply Rank Math SEO Nginx Rules"
    echo "3. Apply WebP Express Rules"
    echo "4. Block User Enumeration API (Security)"
    echo "0. Back"
    read -p "Select: " c
    
    # Use sites-available config
    conf="/etc/nginx/sites-available/$SELECTED_DOMAIN"
    
    if [ ! -f "$conf" ]; then
        echo -e "${RED}Không tìm thấy file cấu hình Nginx cho $SELECTED_DOMAIN${NC}"
        pause; return
    fi
    
    snippet_dir="/etc/nginx/snippets"
    mkdir -p "$snippet_dir"

    case $c in
        1) # Yoast
            snippet="$snippet_dir/yoast-$SELECTED_DOMAIN.conf"
            log_info "Tạo cấu hình Yoast SEO..."
            cat > "$snippet" <<EOF
# Yoast SEO Sitemaps
location ~ ([^/]*)sitemap(.*).x(m|s)l$ {
  rewrite ^/sitemap.xml$ /sitemap_index.xml permanent;
  rewrite ^/([a-z]+)?-?sitemap.xsl$ /index.php?yoast-sitemap-xsl=\$1 last;
  rewrite ^/sitemap_index.xml$ /index.php?sitemap=1 last;
  rewrite ^/([^/]+?)-sitemap([0-9]+)?.xml$ /index.php?sitemap=\$1&sitemap_n=\$2 last;
}
EOF
            # Auto include
            if ! grep -q "yoast-$SELECTED_DOMAIN.conf" "$conf"; then
                sed -i "/server_name/a \    include $snippet;" "$conf"
                log_info "Đã thêm include vào $conf"
            fi
            nginx -t && systemctl reload nginx
            log_info "Đã áp dụng Yoast SEO Rules thành công."
            ;;
            
        2) # Rank Math
            snippet="$snippet_dir/rankmath-$SELECTED_DOMAIN.conf"
            log_info "Tạo cấu hình Rank Math..."
            cat > "$snippet" <<EOF
# Rank Math Sitemaps
rewrite ^/sitemap_index.xml$ /index.php?sitemap=1 last;
rewrite ^/([^/]+?)-sitemap([0-9]+)?.xml$ /index.php?sitemap=\$1&sitemap_n=\$2 last;
EOF
            if ! grep -q "rankmath-$SELECTED_DOMAIN.conf" "$conf"; then
                sed -i "/server_name/a \    include $snippet;" "$conf"
                log_info "Đã thêm include vào $conf"
            fi
            nginx -t && systemctl reload nginx
            log_info "Đã áp dụng Rank Math Rules thành công."
            ;;
            
        3) # WebP Express
            snippet="$snippet_dir/webp-$SELECTED_DOMAIN.conf"
            log_info "Tạo cấu hình WebP Express..."
            cat > "$snippet" <<EOF
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
            if ! grep -q "webp-$SELECTED_DOMAIN.conf" "$conf"; then
                sed -i "/server_name/a \    include $snippet;" "$conf"
                log_info "Đã thêm include vào $conf"
            fi
            nginx -t && systemctl reload nginx
            log_info "Đã áp dụng WebP Express Rules thành công."
            ;;
            
        4) # Block User Enum
            snippet="$snippet_dir/block-enum-$SELECTED_DOMAIN.conf"
            cat > "$snippet" <<EOF
# Block User ID Enumeration
if (\$query_string ~ "author=([0-9]*)") {
    return 403;
}
location ~* ^/wp-json/wp/v2/users {
    deny all;
}
EOF
            if ! grep -q "block-enum-$SELECTED_DOMAIN.conf" "$conf"; then
                sed -i "/server_name/a \    include $snippet;" "$conf"
                log_info "Đã thêm include vào $conf"
            fi
            nginx -t && systemctl reload nginx
            log_info "Đã chặn User Enumeration."
            ;;
    esac
    pause
}

# --- 5. DB Tools ---
wp_db_tool_menu() {
    select_wp_site || return
    ensure_wp_cli
    
    echo -e "\n${YELLOW}Database Tools - $SELECTED_DOMAIN${NC}"
    echo "1. Optimize Database"
    echo "2. Delete Post Revisions"
    echo "3. Delete Spam Comments"
    echo "0. Back"
    read -p "Select: " c
    
    case $c in
        1) $WP_CMD db optimize; pause ;;
        2) 
            log_info "Deleting revisions..."
            $WP_CMD post delete $($WP_CMD post list --post_type='revision' --format=ids) --force 2>/dev/null
            log_info "Done."
            pause 
            ;;
        3) $WP_CMD comment delete $($WP_CMD comment list --status=spam --format=ids) --force 2>/dev/null; pause ;;
    esac
}

# --- 6. Config Tools (Cron/Debug) ---
wp_config_tool_menu() {
    select_wp_site || return
    ensure_wp_cli
    
    echo -e "\n${YELLOW}Config Tools - $SELECTED_DOMAIN${NC}"
    echo "1. Enable WP_DEBUG"
    echo "2. Disable WP_DEBUG"
    echo "3. Disable WP-Cron (Use System Cron)"
    echo "4. Enable WP-Cron"
    echo "5. Enable Maintenance Mode"
    echo "6. Disable Maintenance Mode"
    echo "0. Back"
    read -p "Select: " c
    
    case $c in
        1) $WP_CMD config set WP_DEBUG true --raw; pause ;;
        2) $WP_CMD config set WP_DEBUG false --raw; pause ;;
        3) 
            $WP_CMD config set DISABLE_WP_CRON true --raw
            # Add system cron
            croncmd="curl -s -o /dev/null https://$SELECTED_DOMAIN/wp-cron.php?doing_wp_cron"
            cronjob="*/15 * * * * $croncmd"
            (crontab -l 2>/dev/null | grep -v "$SELECTED_DOMAIN"; echo "$cronjob") | crontab -
            log_info "Disabled WP-Cron and added System Cron (every 15m)."
            pause
            ;;
        4)
            $WP_CMD config set DISABLE_WP_CRON false --raw
            # Remove system cron
            crontab -l | grep -v "$SELECTED_DOMAIN" | crontab -
            log_info "Enabled WP-Cron."
            pause
            ;;
        5) $WP_CMD maintenance-mode activate; pause ;;
        6) $WP_CMD maintenance-mode deactivate; pause ;;
    esac
}

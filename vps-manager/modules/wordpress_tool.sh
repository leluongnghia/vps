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
    if ! command -v wp &> /dev/null; then
        echo -e "${YELLOW}Installing WP-CLI...${NC}"
        curl -O https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar
        chmod +x wp-cli.phar
        mv wp-cli.phar /usr/local/bin/wp
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
                read -p "Nhập ID hoặc Username: " u
                read -p "Nhập Password mới: " p
                $WP_CMD user update "$u" --user_pass="$p"
                pause 
                ;;
            3)
                read -p "Username: " u
                read -p "Email: " e
                $WP_CMD user create "$u" "$e" --role=administrator --prompt
                pause
                ;;
            0) return ;;
        esac
    done
}

# --- 3. Security ---
wp_security_menu() {
    select_wp_site || return
    
    while true; do
        echo -e "\n${YELLOW}Security - $SELECTED_DOMAIN${NC}"
        echo "1. Disable XML-RPC (Nginx)"
        echo "2. Enable XML-RPC"
        echo "3. Disable File Edit (Theme/Plugin)"
        echo "4. Enable File Edit"
        echo "5. Hide/Protect wp-config.php (Move UP)"
        echo "0. Back"
        read -p "Select: " c
        
        case $c in
            1) # Disable XMLRPC
                conf="/etc/nginx/conf.d/$SELECTED_DOMAIN.conf"
                if ! grep -q "xmlrpc.php" "$conf"; then
                    # Insert before the last }
                    sed -i '$d' "$conf"
                    cat >> "$conf" <<EOF
    location = /xmlrpc.php {
        deny all;
        access_log off;
        log_not_found off;
    }
}
EOF
                    systemctl reload nginx
                    log_info "Disabled XML-RPC."
                else
                    log_warn "Already configured."
                fi
                pause
                ;;
            2) # Enable XMLRPC
                sed -i '/location = \/xmlrpc.php/,/}/d' "/etc/nginx/conf.d/$SELECTED_DOMAIN.conf"
                systemctl reload nginx
                log_info "Enabled XML-RPC."
                pause
                ;;
            3) # Disable File Edit
                $WP_CMD config set DISALLOW_FILE_EDIT true --raw
                log_info "Disabled File Edit."
                pause
                ;;
            4) # Enable File Edit
                $WP_CMD config set DISALLOW_FILE_EDIT false --raw
                log_info "Enabled File Edit."
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
    echo "4. Block User Enumeration API"
    echo "0. Back"
    read -p "Select: " c
    
    conf="/etc/nginx/conf.d/$SELECTED_DOMAIN.conf"
    
    case $c in
        1) # Yoast
            cat > "/etc/nginx/snippets/yoast-$SELECTED_DOMAIN.conf" <<EOF
# Yoast SEO Sitemaps
location ~ ([^/]*)sitemap(.*).x(m|s)l$ {
  rewrite ^/sitemap.xml$ /sitemap_index.xml permanent;
  rewrite ^/([a-z]+)?-?sitemap.xsl$ /index.php?yoast-sitemap-xsl=\$1 last;
  rewrite ^/sitemap_index.xml$ /index.php?sitemap=1 last;
  rewrite ^/([^/]+?)-sitemap([0-9]+)?.xml$ /index.php?sitemap=\$1&sitemap_n=\$2 last;
}
EOF
            log_info "Include snippets/yoast-$SELECTED_DOMAIN.conf into main config if not present."
            # We could auto grep and insert include
            ;;
        3) # WebP Express
            log_info "Creating WebP Express rules..."
            cat > "/etc/nginx/snippets/webp-$SELECTED_DOMAIN.conf" <<EOF
# WebP Express
location ~ ^/wp-content/(.*\.(png|jpe?g))$ {
  add_header Vary Accept;
  expires 365d;
  if (\$http_accept !~* "webp"){
    break;
  }
  try_files /wp-content/webp-express/webp-images/doc-root/wp-content/\$1.webp \$uri =404;
}
EOF
            echo -e "${YELLOW}Add 'include snippets/webp-$SELECTED_DOMAIN.conf;' to your Nginx server block.${NC}"
            ;;
        4) # Block User Enum
            if ! grep -q "Block User ID" "$conf"; then
                sed -i '$d' "$conf"
                cat >> "$conf" <<EOF
    # Block User ID Enumeration
    if (\$query_string ~ "author=([0-9]*)") {
        return 403;
    }
    location ~* ^/wp-json/wp/v2/users {
        deny all;
    }
}
EOF
                systemctl reload nginx
            fi
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

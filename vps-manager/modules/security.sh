#!/bin/bash

# modules/security.sh - Security Configurations

security_menu() {
    clear
    echo -e "${BLUE}=================================================${NC}"
    echo -e "${GREEN}          Bảo mật & Tường lửa${NC}"
    echo -e "${BLUE}=================================================${NC}"
    echo -e "1. Cài đặt Tường lửa (UFW) & Fail2ban"
    echo -e "2. Thay đổi Port SSH"
    echo -e "3. Đổi mật khẩu Root"
    echo -e "4. Đổi mật khẩu User (SFTP)"
    echo -e "5. Giới hạn số lần đăng nhập SSH (MaxAuthTries)"
    echo -e "6. Cấu hình Chống DDoS cơ bản (Nginx Rate Limit)"
    echo -e "7. Tích hợp 7G Firewall (WAF cho Nginx)"
    echo -e "8. Bảo mật PHP (Disable Dangerous Functions)"
    echo -e "0. Quay lại Menu chính"
    echo -e "${BLUE}=================================================${NC}"
    read -p "Nhập lựa chọn [0-8]: " choice

    case $choice in
        1) setup_firewall ;;
        2) change_ssh_port ;;
        3) change_root_pass ;;
        4) change_user_pass ;;
        5) set_max_auth_tries ;;
        6) setup_nginx_dos ;;
        7) setup_7g_firewall ;;
        8) secure_php ;;
        0) return ;;
        *) echo -e "${RED}Lựa chọn không hợp lệ!${NC}"; pause ;;
    esac
}

secure_php() {
    log_info "Đang cấu hình disable_functions cho PHP..."
    
    # List of dangerous functions
    funcs="exec,passthru,shell_exec,system,proc_open,popen,curl_exec,curl_multi_exec,parse_ini_file,show_source"
    
    # Apply to all php.ini
    for ver in 8.1 8.2 8.3; do
        ini="/etc/php/$ver/fpm/php.ini"
        if [ -f "$ini" ]; then
            # Check if already disabled or append
            # Simplified regex replace
            sed -i "s/^disable_functions.*/disable_functions = $funcs/" "$ini"
            log_info "Đã update disable_functions cho PHP $ver"
            systemctl restart php$ver-fpm
        fi
    done
    if [ -z "$1" ]; then pause; fi
}

setup_firewall() {
    log_info "Đang cấu hình UFW & Fail2ban..."
    apt-get install -y ufw fail2ban
    
    # Configure UFW
    ufw default deny incoming
    ufw default allow outgoing
    ufw allow ssh
    ufw allow 80/tcp
    ufw allow 443/tcp
    
    # Enable UFW
    echo "y" | ufw enable
    
    # Configure Fail2ban
    cp /etc/fail2ban/jail.conf /etc/fail2ban/jail.local
    
    # Enable SSH protection
    cat >> /etc/fail2ban/jail.local <<EOF
[sshd]
enabled = true
port = ssh
filter = sshd
logpath = /var/log/auth.log
maxretry = 3
bantime = 3600
EOF

    systemctl restart fail2ban
    systemctl enable fail2ban
    log_info "UFW & Fail2ban đã được cài đặt."
    if [ -z "$1" ]; then pause; fi
}

change_ssh_port() {
    # Get current SSH port
    current_port=$(grep -E "^Port " /etc/ssh/sshd_config | awk '{print $2}')
    current_port=${current_port:-22}
    echo -e "${YELLOW}Port SSH hiện tại: ${current_port}${NC}"
    
    read -p "Nhập cổng SSH mới (1024-65535): " new_port
    if [[ ! "$new_port" =~ ^[0-9]+$ ]] || [ "$new_port" -lt 1024 ] || [ "$new_port" -gt 65535 ]; then
        echo -e "${RED}Cổng không hợp lệ!${NC}"
        pause; return
    fi
    
    # Update sshd_config
    if grep -q "^Port" /etc/ssh/sshd_config; then
        sed -i "s/^Port .*/Port $new_port/" /etc/ssh/sshd_config
    else
        echo "Port $new_port" >> /etc/ssh/sshd_config
    fi
    
    # UFW: allow new port FIRST, then remove old
    ufw allow $new_port/tcp
    if [ "$current_port" != "$new_port" ] && [ "$current_port" != "22" ]; then
        ufw delete allow $current_port/tcp 2>/dev/null
    elif [ "$current_port" == "22" ]; then
        ufw delete allow ssh 2>/dev/null
        ufw delete allow 22/tcp 2>/dev/null
    fi
    
    systemctl restart ssh 2>/dev/null || systemctl restart sshd 2>/dev/null
    
    log_info "Đã đổi Port SSH sang $new_port. Kết nối lại với port mới!"
    echo -e "${YELLOW}Lưu ý: ssh -p $new_port root@<IP_VPS>${NC}"
    pause
}

change_root_pass() {
    echo -e "${YELLOW}Đổi mật khẩu Root${NC}"
    passwd root
    pause
}

change_user_pass() {
    read -p "Nhập username cần đổi mật khẩu: " user
    if id "$user" &>/dev/null; then
        passwd "$user"
    else
        echo -e "${RED}User không tồn tại!${NC}"
    fi
    pause
}

set_max_auth_tries() {
    read -p "Nhập số lần thử login tối đa (ví dụ 3): " tries
    if [[ ! "$tries" =~ ^[0-9]+$ ]]; then return; fi
    
    if grep -q "MaxAuthTries" /etc/ssh/sshd_config; then
        sed -i "s/.*MaxAuthTries.*/MaxAuthTries $tries/" /etc/ssh/sshd_config
    else
        echo "MaxAuthTries $tries" >> /etc/ssh/sshd_config
    fi
    
    systemctl restart ssh
    log_info "Đã thiết lập MaxAuthTries = $tries"
    pause
}

setup_nginx_dos() {
    log_info "Đang cấu hình Nginx Rate Limiting (Chống DDoS cơ bản)..."
    
    # 1. Create Zone Global
    cat > /etc/nginx/conf.d/ddos_limit.conf <<EOF
limit_req_zone \$binary_remote_addr zone=one:10m rate=10r/s;
EOF
    
    echo -e "${YELLOW}Bạn có muốn áp dụng giới hạn này cho website không?${NC}"
    echo -e "1. Áp dụng cho TẤT CẢ website (Khuyên dùng)"
    echo -e "2. Chọn website cụ thể"
    echo -e "0. Không, chỉ tạo Zone (Cần Config tay)"
    read -p "Chọn: " c
    
    if [[ "$c" == "0" ]]; then return; fi
    
    # Function to apply limit
    apply_limit() {
        local domain=$1
        local conf="/etc/nginx/sites-available/$domain"
        if [ -f "$conf" ]; then
            if ! grep -q "limit_req zone=one" "$conf"; then
                # Insert after server_name
                sed -i "/server_name/a \    limit_req zone=one burst=20 nodelay;" "$conf"
                log_info "Đã áp dụng cho $domain"
            else
                log_warn "$domain đã có cấu hình limit."
            fi
        fi
    }
    
    if [[ "$c" == "1" ]]; then
        for conf in /etc/nginx/sites-available/*; do
            d=$(basename "$conf")
            if [[ "$d" != "default" && "$d" != "html" ]]; then
                apply_limit "$d"
            fi
        done
        nginx -t && systemctl reload nginx
        log_info "Đã áp dụng Rate Limit cho toàn bộ website."
        
    elif [[ "$c" == "2" ]]; then
        # Ensure site.sh is sourced for select_site
        source "$(dirname "${BASH_SOURCE[0]}")/site.sh"
        select_site || return
        apply_limit "$SELECTED_DOMAIN"
        nginx -t && systemctl reload nginx
        log_info "Đã áp dụng Rate Limit cho $SELECTED_DOMAIN."
    fi
    pause
}

setup_7g_firewall() {
    log_info "Đang cài đặt Basic WAF (Tường lửa ứng dụng web)..."
    
    mkdir -p /etc/nginx/snippets
    waf_file="/etc/nginx/snippets/basic_waf.conf"
    
    # Create Basic WAF Rules (Common Bad Bots & Exploits)
    cat > "$waf_file" <<EOF
# Basic WAF Rules
# Block SQL Injection & XSS
location ~* "(eval\()" { deny all; }
location ~* "(127\.0\.0\.1)" { deny all; }
location ~* "([a-z0-9]{2000})" { deny all; }
location ~* "(javascript:)(.*)(;)" { deny all; }
location ~* "(base64_encode)(.*)(\()" { deny all; }
location ~* "(GLOBALS|REQUEST)(=|\[|%)" { deny all; }
location ~* "(<|%3C).*script.*(>|%3E)" { deny all; }
location ~ "(\\|\.\.\.|\.\./|~|`|<|>|\|)" { deny all; }

# Block Sensitive Files
location ~* "(boot\.ini|etc/passwd|self/environ)" { deny all; }
location ~* "(thumbs?(_editor|db)?\.db|DS_Store|__MACOSX)" { deny all; }
location ~* "(\.bak|\.config|\.sql|\.ini|\.log|\.sh|\.inc|\.swp|\.dist)$" { deny all; }
EOF

    echo -e "${YELLOW}Bạn có muốn áp dụng WAF cho website không?${NC}"
    echo -e "1. Áp dụng cho TẤT CẢ website"
    echo -e "2. Chọn website cụ thể"
    echo -e "0. Không"
    read -p "Chọn: " c
    
    if [[ "$c" == "0" ]]; then return; fi

    apply_waf() {
        local domain=$1
        local conf="/etc/nginx/sites-available/$domain"
        if [ -f "$conf" ]; then
            if ! grep -q "basic_waf.conf" "$conf"; then
                # Insert include
                sed -i "/server_name/a \    include /etc/nginx/snippets/basic_waf.conf;" "$conf"
                log_info "Đã kích hoạt WAF cho $domain"
            else
                log_warn "$domain đã kích hoạt WAF."
            fi
        fi
    }

    if [[ "$c" == "1" ]]; then
        for conf in /etc/nginx/sites-available/*; do
            d=$(basename "$conf")
            if [[ "$d" != "default" && "$d" != "html" ]]; then
                apply_waf "$d"
            fi
        done
        nginx -t && systemctl reload nginx
        log_info "Đã áp dụng WAF cho toàn bộ website."
    elif [[ "$c" == "2" ]]; then
        source "$(dirname "${BASH_SOURCE[0]}")/site.sh"
        select_site || return
        apply_waf "$SELECTED_DOMAIN"
        nginx -t && systemctl reload nginx
        log_info "Đã áp dụng WAF cho $SELECTED_DOMAIN."
    fi
    pause
}

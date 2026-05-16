#!/bin/bash

# modules/security.sh - Security Configurations

security_menu() {
    while true; do
        clear
        echo -e "${BLUE}=================================================${NC}"
        echo -e "${GREEN}          Bảo mật & Tường lửa${NC}"
        echo -e "${BLUE}=================================================${NC}"
        echo -e "1.  Cài đặt Tường lửa (UFW / Firewalld) & Fail2ban"
        echo -e "2.  Thay đổi Port SSH"
        echo -e "3.  Đổi mật khẩu Root"
        echo -e "4.  Đổi mật khẩu User (SFTP)"
        echo -e "5.  Giới hạn số lần đăng nhập SSH (MaxAuthTries)"
        echo -e "6.  Cấu hình Chống DDoS cơ bản (Nginx Rate Limit)"
        echo -e "7.  🛡️  7G Firewall (WAF đầy đủ - khuyên dùng)"
        echo -e "8.  🛡️  8G Firewall (WAF nâng cao - tích hợp 7G)"
        echo -e "9.  🌍 Chặn IP theo Quốc gia (GeoIP Block)"
        echo -e "10. 🔒 Bảo mật PHP (Disable Dangerous Functions)"
        echo -e "11. 🛡️  Kiểm tra & Vá lỗi Bảo mật (Nginx Rift - CVE-2026-42945)"
        echo -e "0.  Quay lại Menu chính"
        echo -e "${BLUE}=================================================${NC}"
        read -p "Nhập lựa chọn [0-10]: " choice

        case $choice in
            1) setup_firewall ;;
            2) change_ssh_port ;;
            3) change_root_pass ;;
            4) change_user_pass ;;
            5) set_max_auth_tries ;;
            6) setup_nginx_dos ;;
            7) setup_7g_firewall ;;
            8) setup_8g_firewall ;;
            9) setup_geoip_block ;;
            10) secure_php ;;
            11) security_patch_system ;;
            0) return ;;
            *) echo -e "${RED}Lựa chọn không hợp lệ!${NC}"; pause ;;
        esac
    done
}


secure_php() {
    log_info "Đang cấu hình disable_functions cho PHP..."
    
    # List of dangerous functions
    funcs="exec,passthru,shell_exec,system,proc_open,popen,curl_exec,curl_multi_exec,parse_ini_file,show_source"
    
    # Apply to all php.ini
    for ver in 8.1 8.2 8.3 8.4; do
        ini="/etc/php/$ver/fpm/php.ini"
        if [[ -f "$ini" ]]; then
            # Check if already disabled or append
            # Simplified regex replace
            sed -i "s/^disable_functions.*/disable_functions = $funcs/" "$ini"
            log_info "Đã update disable_functions cho PHP $ver"
            systemctl restart php$ver-fpm
        fi
    done
    if [[ -z "$1" ]]; then pause; fi
}

setup_firewall() {
    log_info "Đang cấu hình Firewall & Fail2ban..."
    if [[ "$OS_FAMILY" == "rhel" ]]; then
        pkg_install firewalld fail2ban epel-release
        
        systemctl enable firewalld
        systemctl start firewalld
        
        firewall-cmd --permanent --add-service=ssh
        firewall-cmd --permanent --add-service=http
        firewall-cmd --permanent --add-service=https
        firewall-cmd --reload
        
        # Configure Fail2ban
        cp /etc/fail2ban/jail.conf /etc/fail2ban/jail.local
        
        # Enable SSH protection
        cat >> /etc/fail2ban/jail.local <<EOF
[sshd]
enabled = true
port = ssh
filter = sshd
logpath = /var/log/secure
maxretry = 3
bantime = 3600
EOF
    else
        pkg_install ufw fail2ban
        
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
    fi

    systemctl restart fail2ban
    systemctl enable fail2ban
    log_info "Tường lửa & Fail2ban đã được cài đặt."
    if [[ -z "$1" ]]; then pause; fi
}

change_ssh_port() {
    # Get current SSH port
    current_port=$(grep -E "^Port " /etc/ssh/sshd_config | awk '{print $2}')
    current_port=${current_port:-22}
    echo -e "${YELLOW}Port SSH hiện tại: ${current_port}${NC}"
    
    read -p "Nhập cổng SSH mới (1024-65535): " new_port
    if [[ ! "$new_port" =~ ^[0-9]+$ ]] || [[ "$new_port" -lt 1024 ]] || [[ "$new_port" -gt 65535 ]]; then
        echo -e "${RED}Cổng không hợp lệ!${NC}"
        pause; return
    fi
    
    # Update sshd_config
    if grep -q "^Port" /etc/ssh/sshd_config; then
        sed -i "s/^Port .*/Port $new_port/" /etc/ssh/sshd_config
    else
        echo "Port $new_port" >> /etc/ssh/sshd_config
    fi
    
    # UFW / Firewalld: allow new port FIRST, then remove old
    if [[ "$OS_FAMILY" == "rhel" ]]; then
        firewall-cmd --permanent --add-port=${new_port}/tcp
        if [[ "$current_port" != "$new_port" ]] && [[ "$current_port" != "22" ]]; then
            firewall-cmd --permanent --remove-port=${current_port}/tcp 2>/dev/null
        elif [[ "$current_port" == "22" ]]; then
            firewall-cmd --permanent --remove-service=ssh 2>/dev/null
            firewall-cmd --permanent --remove-port=22/tcp 2>/dev/null
        fi
        firewall-cmd --reload
    else
        ufw allow $new_port/tcp
        if [[ "$current_port" != "$new_port" ]] && [[ "$current_port" != "22" ]]; then
            ufw delete allow $current_port/tcp 2>/dev/null
        elif [[ "$current_port" == "22" ]]; then
            ufw delete allow ssh 2>/dev/null
            ufw delete allow 22/tcp 2>/dev/null
        fi
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
        if [[ -f "$conf" ]]; then
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
        source "$(dirname "${BASH_SOURCE[0]}")/site.sh"
        select_site || return
        apply_limit "$SELECTED_DOMAIN"
        nginx -t && systemctl reload nginx
        log_info "Đã áp dụng Rate Limit cho $SELECTED_DOMAIN."
    fi
    pause
}

setup_7g_firewall() {
    log_info "Đang cài đặt 7G Firewall (WAF đầy đủ cho Nginx)..."

    mkdir -p /etc/nginx/snippets
    local waf_file="/etc/nginx/snippets/7g.conf"

    # Ruleset 7G Firewall - perishablepress.com/7g-firewall/
    cat > "$waf_file" <<'WAF_EOF'
# 7G Firewall v1.5 - Adapted for Nginx
# Source: perishablepress.com/7g-firewall/

# 7G:[QUERY STRING]
set $7g_block 0;

# Block malicious query strings
if ($query_string ~* "(eval\()|(javascript:)|(base64_encode)|(GLOBALS|REQUEST)(=|\[|%)|(union.*select)|(concat.*()|(benchmark\()|(from.*information_schema)|(sleep\()|(into.*outfile)|(load_file\()|(0x[0-9a-f]{2}){10,}|(\\|\.\.\.|\.\./|~|`|<|>|\|)") {
    set $7g_block 1;
}
if ($query_string ~* "(<|%3C).*script.*(>|%3E)") {
    set $7g_block 2;
}
if ($query_string ~* "(boot\.ini|etc/passwd|self/environ|proc/(self|version))") {
    set $7g_block 3;
}
if ($query_string ~* "([a-z0-9]{2500,})") {
    set $7g_block 4;
}
if ($query_string ~* "(\%00|\%0A|\%0D|\%27|\%3C|\%3E|\%00)") {
    set $7g_block 5;
}

# 7G:[REQUEST URI]
if ($request_uri ~* "(eval\()|(javascript:)|(base64_encode)|(union.*select)|(concat.*()|(sleep\()|(0x[0-9a-f]{2}){10,}") {
    set $7g_block 6;
}
if ($request_uri ~* "(\.php/|/xmlrpc\.php.*methodCall|wp-config\.php|etc/passwd|boot\.ini|self/environ)") {
    set $7g_block 7;
}

# 7G:[REQUEST METHOD]
if ($request_method !~ ^(GET|HEAD|POST|PUT|DELETE|OPTIONS)$) {
    set $7g_block 8;
}

# 7G:[USER AGENT]
if ($http_user_agent ~* "(bot|crawl|archiver|spider|libwww|wget|python|scan|hack|inject|sqlmap|nikto|h4x0r|masscan|ZmEu|dirbuster|nmap|curl/7\.[0-3])") {
    set $7g_block 9;
}

# 7G:[REFERRER]
if ($http_referer ~* "(semalt|buttons-for-website\.com|7secrets|checksem\.com|ilovevitaly)") {
    set $7g_block 10;
}

# 7G:[BLOCK SENSITIVE FILES]
location ~* "(\.(bak|conf|dist|fla|inc|ini|log|psd|sh|sql|swp)|~)$" {
    deny all;
}
location ~* "/(wp-config\.php|php\.ini|\.htaccess|\.git|\.svn|\.env|docker-compose)" {
    deny all;
}
location ~* "/(thumbs?(_editor|db)?\.db|DS_Store|__MACOSX)" {
    deny all;
}

# 7G:[RETURN BLOCK]
if ($7g_block) {
    return 403;
}
WAF_EOF

    echo -e "${YELLOW}Áp dụng 7G WAF cho website:${NC}"
    echo -e "1. Áp dụng cho TẤT CẢ website"
    echo -e "2. Chọn website cụ thể"
    echo -e "0. Chỉ tạo file rule (cần include tay)"
    read -p "Chọn: " c

    [[ "$c" == "0" ]] && { log_info "File rule tại: $waf_file"; pause; return; }

    # Bỏ 8G nếu đã có, thay bằng 7G để tránh load x2 luật regex Nginx
    _apply_nginx_snippet "7g.conf" "include /etc/nginx/snippets/7g.conf;" "$c" "8g.conf"
    pause
}

setup_8g_firewall() {
    log_info "Đang cài đặt 8G Firewall (WAF nâng cao - tích hợp 7G)..."

    # Đảm bảo 7G đã được cài trước
    if [[ ! -f /etc/nginx/snippets/7g.conf ]]; then
        log_info "Cài 7G trước..."
        setup_7g_firewall
    fi

    mkdir -p /etc/nginx/snippets
    local waf_file="/etc/nginx/snippets/8g.conf"

    # Bổ sung 8G rules (tăng cường thêm so với 7G)
    cat > "$waf_file" <<'WAF_EOF'
# 8G Firewall v1.0 - Extension of 7G
# Source: perishablepress.com/8g-firewall/

include /etc/nginx/snippets/7g.conf;

set $8g_block 0;

# 8G: Block additional attack patterns
if ($query_string ~* "(\bselect\b.*\bfrom\b|\binsert\b.*\binto\b|\bupdate\b.*\bset\b|\bdelete\b.*\bfrom\b|\bdrop\b.*\btable\b)") {
    set $8g_block 1;
}
if ($query_string ~* "(document\.cookie|document\.write|window\.location|parent\.frames)") {
    set $8g_block 2;
}
# Block common Web shells
if ($query_string ~* "(c99|r57|shell|passthru|phpinfo|base64_decode|str_rot13|gzuncompress)") {
    set $8g_block 3;
}
# 8G: Advanced UA blocking (AI/Scraper bots)
if ($http_user_agent ~* "(GPTBot|ChatGPT-User|CCBot|PerplexityBot|anthropic-ai|cohere-ai|ByteDance|PetalBot|AhrefsBot|SemrushBot|MJ12bot|DotBot|BLEXBot)") {
    set $8g_block 4;
}
# 8G: Block XML-RPC brute force
if ($request_uri ~* "\/xmlrpc\.php") {
    set $8g_block 5;
}

if ($8g_block) {
    return 403;
}
WAF_EOF

    echo -e "${YELLOW}Áp dụng 8G WAF cho website:${NC}"
    echo -e "1. Áp dụng cho TẤT CẢ website"
    echo -e "2. Chọn website cụ thể"
    echo -e "0. Chỉ tạo file rule"
    read -p "Chọn: " c

    [[ "$c" == "0" ]] && { log_info "File rule tại: $waf_file"; pause; return; }

    # Bỏ 7G nếu đã có, thay bằng 8G (đã include 7G)
    _apply_nginx_snippet "8g.conf" "include /etc/nginx/snippets/8g.conf;" "$c" "7g.conf"
    pause
}

# Helper: Áp dụng 1 snippet vào 1 Nginx vhost cụ thể
# $1: domain  $2: snippet_file  $3: include_line  $4: old_snippet (optional)
_do_apply_snippet() {
    local domain=$1
    local snippet_file=$2
    local include_line=$3
    local old_snippet="${4:-}"
    local conf="/etc/nginx/sites-available/$domain"
    [[ ! -f "$conf" ]] && return

    # Xóa snippet cũ nếu được chỉ định
    if [[ -n "$old_snippet" ]]; then
        sed -i "/include.*${old_snippet}/d" "$conf" 2>/dev/null
    fi

    if ! grep -q "$snippet_file" "$conf"; then
        sed -i "/server_name/a\\    ${include_line}" "$conf"
        log_info "Đã kích hoạt $snippet_file cho $domain"
    else
        log_warn "$domain đã có $snippet_file."
    fi
}

# Helper: Áp dụng snippet vào Nginx vhost(s)
# $1: snippet filename  $2: include directive  $3: choice (1=all,2=select)  $4: old snippet to remove (optional)
_apply_nginx_snippet() {
    local snippet_file="$1"
    local include_line="$2"
    local choice="$3"
    local old_snippet="${4:-}"

    if [[ "$choice" == "1" ]]; then
        for conf in /etc/nginx/sites-available/*; do
            local d
            d=$(basename "$conf")
            [[ "$d" == "default" || "$d" == "html" ]] && continue
            _do_apply_snippet "$d" "$snippet_file" "$include_line" "$old_snippet"
        done
        nginx -t && systemctl reload nginx
        log_info "Đã áp dụng ${snippet_file} cho toàn bộ website."
    elif [[ "$choice" == "2" ]]; then
        source "$(dirname "${BASH_SOURCE[0]}")/site.sh"
        select_site || return
        _do_apply_snippet "$SELECTED_DOMAIN" "$snippet_file" "$include_line" "$old_snippet"
        nginx -t && systemctl reload nginx
        log_info "Đã áp dụng ${snippet_file} cho ${SELECTED_DOMAIN}."
    fi
}


setup_geoip_block() {
    log_info "Cấu hình GeoIP Block (chặn IP theo quốc gia)..."

    # Kiểm tra ngx_http_geoip2_module
    if ! nginx -V 2>&1 | grep -q "geoip2\|geoip"; then
        echo -e "${YELLOW}Nginx chưa có GeoIP module. Đang cài libnginx-mod-http-geoip2...${NC}"
        if [[ "$OS_FAMILY" == "debian" ]]; then
            DEBIAN_FRONTEND=noninteractive apt-get install -y libnginx-mod-http-geoip2 geoipupdate 2>/dev/null || {
                DEBIAN_FRONTEND=noninteractive apt-get install -y libnginx-mod-http-geoip 2>/dev/null
            }
        else
            dnf install -y nginx-mod-http-geoip2 GeoIP GeoIP-devel 2>/dev/null
        fi
    fi

    # Cài mmdb-bin / geoipupdate để có database
    if ! command -v geoiplookup &>/dev/null && ! command -v mmdblookup &>/dev/null; then
        if [[ "$OS_FAMILY" == "debian" ]]; then
            DEBIAN_FRONTEND=noninteractive apt-get install -y mmdb-bin geoip-bin 2>/dev/null
        fi
    fi

    # Tải GeoLite2-Country database (không cần API key cho GeoLite2 cũ)
    local geoip_dir="/etc/nginx/geoip"
    mkdir -p "$geoip_dir"
    if [[ ! -f "${geoip_dir}/GeoLite2-Country.mmdb" ]]; then
        log_info "Đang tải GeoLite2 Country database..."
        # Dùng bản mirror public của GeoLite2
        local db_url="https://github.com/P3TERX/GeoLite.mmdb/raw/download/GeoLite2-Country.mmdb"
        curl -fsSL -o "${geoip_dir}/GeoLite2-Country.mmdb" "$db_url" || \
        wget -qO "${geoip_dir}/GeoLite2-Country.mmdb" "$db_url" || {
            log_error "Không thể tải GeoLite2 database. Kiểm tra kết nối mạng."
            pause; return
        }
        log_info "GeoLite2 database đã tải về: ${geoip_dir}/GeoLite2-Country.mmdb"
    fi

    # Hỏi user chọn quốc gia cần block
    echo -e "${YELLOW}Danh sách code quốc gia cần BLOCK (ISO 3166-1 alpha-2):${NC}"
    echo -e "  Ví dụ: CN RU KP IR KH (cách nhau bằng dấu cách)"
    echo -e "  CN=Trung Quốc, RU=Nga, KP=Triều Tiên, IR=Iran, KH=Campuchia"
    read -p "Nhập danh sách quốc gia block: " country_list
    [[ -z "$country_list" ]] && { log_warn "Không có quốc gia nào được nhập."; pause; return; }

    # Tạo cấu hình GeoIP
    local geoip_conf="/etc/nginx/conf.d/geoip_block.conf"
    {
        echo "# GeoIP Block - Tạo bởi VPS Manager"
        echo "geoip2 ${geoip_dir}/GeoLite2-Country.mmdb {"
        echo "    \$geoip2_country_code country iso_code;"
        echo "}"
        echo ""
        echo "map \$geoip2_country_code \$blocked_country {"
        echo "    default 0;"
        for code in $country_list; do
            code=$(echo "$code" | tr '[:lower:]' '[:upper:]')
            echo "    $code 1;"
        done
        echo "}"
    } > "$geoip_conf"

    # Tạo snippet để include trong server block
    cat > /etc/nginx/snippets/geoip_block.conf <<'GEOF'
# Block countries defined in geoip_block.conf
if ($blocked_country) {
    return 403 "Access Denied - Geographic restriction.";
}
GEOF

    echo -e "${YELLOW}Áp dụng GeoIP Block cho website:${NC}"
    echo -e "1. Áp dụng cho TẤT CẢ website"
    echo -e "2. Chọn website cụ thể"
    echo -e "0. Chỉ tạo config (apply tay)"
    read -p "Chọn: " c

    [[ "$c" != "0" ]] && _apply_nginx_snippet "geoip_block.conf" "include /etc/nginx/snippets/geoip_block.conf;" "$c"

    nginx -t && systemctl reload nginx && log_info "\u2705 GeoIP Block \u0111\u00e3 \u0111\u01b0\u1ee3c c\u1ea5u h\u00ecnh!"
    echo -e "${YELLOW}Qu\u1ed1c gia b\u1ecb block: ${country_list}${NC}"
    pause
}

security_patch_system() {
    clear
    echo -e "${BLUE}=================================================${NC}"
    echo -e "${RED}    🛡️  KIỂM TRA & VÁ LỖI BẢO MẬT HỆ THỐNG${NC}"
    echo -e "${BLUE}=================================================${NC}"
    echo -e "Thông tin các lỗ hổng mới (Cập nhật May 2026):"
    echo -e "${YELLOW}1. CVE-2026-42945 (Nginx Rift)${NC}"
    echo -e "   - Loại: Heap-based Buffer Overflow (ngx_http_rewrite_module)"
    echo -e "   - Tác động: Gây crash (DoS) hoặc RCE."
    echo -e "${YELLOW}2. CVE-2026-31431 (Copy Fail) & CVE-2026-43284/43500 (Dirty Frag)${NC}"
    echo -e "   - Loại: Local Privilege Escalation (LPE) trên Linux Kernel"
    echo -e "   - Tác động: Cho phép user thường leo thang đặc quyền lên root."
    echo -e "${YELLOW}3. Lỗ hổng PHP (FPM, MBString, SOAP)${NC}"
    echo -e "   - Loại: XSS và các lỗi bộ nhớ"
    echo -e "${BLUE}=================================================${NC}"
    
    echo -e "1. Kiểm tra phiên bản hiện tại..."
    local ng_ver
    ng_ver=$(nginx -v 2>&1 | grep -oP 'nginx/\K[0-9.]+')
    echo -e "  - Nginx: v${ng_ver:-Unknown}"
    
    local kernel_ver
    kernel_ver=$(uname -r)
    echo -e "  - Kernel: $kernel_ver"
    
    if command -v php >/dev/null; then
        local php_ver
        php_ver=$(php -v | head -n1 | grep -oP 'PHP \K[0-9.]+')
        echo -e "  - PHP: v${php_ver:-Unknown}"
    fi
    
    if [[ -f /etc/os-release ]]; then
        source /etc/os-release
        echo -e "  - Hệ điều hành: $PRETTY_NAME"
    fi

    echo ""
    echo -e "2. Đang quét cấu hình Nginx tìm các rule có nguy cơ..."
    # Pattern: rewrite with capture groups + ? in replacement followed by rewrite/set/if
    local risky_found=0
    if [[ -d /etc/nginx/sites-enabled ]]; then
        for conf in /etc/nginx/sites-enabled/*; do
            if grep -q "rewrite .*\$.*?.*" "$conf"; then
                echo -e "  ${YELLOW}⚠ Phát hiện cấu hình rewrite có dấu hỏi (?) và biến capture tại: $(basename "$conf")${NC}"
                risky_found=$((risky_found + 1))
            fi
        done
    fi
    
    if [[ $risky_found -eq 0 ]]; then
        echo -e "  ${GREEN}✓ Không tìm thấy cấu hình Nginx rewrite có nguy cơ lộ liễu.${NC}"
    else
        echo -e "  ${YELLOW}⚠ Đã tìm thấy $risky_found vị trí có thể bị kích hoạt lỗ hổng. Cần cập nhật Nginx ngay.${NC}"
    fi

    echo ""
    read -p "Bạn có muốn tiến hành cập nhật bản vá bảo mật (Nginx, Kernel, PHP) ngay bây giờ? [Y/n]: " confirm
    [[ "${confirm,,}" == "n" ]] && return

    log_info "Đang cập nhật danh sách gói..."
    if [[ "$OS_FAMILY" == "debian" || "$OS_FAMILY" == "ubuntu" ]]; then
        apt-get update
        
        log_info "Đang nâng cấp Nginx..."
        apt-get install --only-upgrade -y nginx nginx-common nginx-full nginx-core 2>/dev/null
        
        log_info "Đang nâng cấp PHP..."
        apt-get install --only-upgrade -y php* 2>/dev/null
        
        log_info "Đang nâng cấp Linux Kernel & các gói hệ thống khác..."
        # Use full-upgrade to ensure kernel updates dependencies are met
        DEBIAN_FRONTEND=noninteractive apt-get full-upgrade -y 2>/dev/null
        
    else
        log_info "Đang cập nhật Nginx, PHP và Kernel qua dnf/yum..."
        dnf upgrade -y nginx php* kernel* 2>/dev/null
        dnf upgrade -y 2>/dev/null
    fi

    local new_ng_ver new_kernel_ver new_php_ver
    new_ng_ver=$(nginx -v 2>&1 | grep -oP 'nginx/\K[0-9.]+')
    new_kernel_ver=$(uname -r)
    if command -v php >/dev/null; then
        new_php_ver=$(php -v | head -n1 | grep -oP 'PHP \K[0-9.]+')
    fi
    
    echo -e "${BLUE}=================================================${NC}"
    echo -e "${GREEN}✅ Quá trình cập nhật hoàn tất!${NC}"
    if [[ "$ng_ver" != "$new_ng_ver" ]]; then
        echo -e "  - Nginx đã cập nhật: $ng_ver -> $new_ng_ver"
        systemctl restart nginx 2>/dev/null
    fi
    
    if [[ -n "$new_php_ver" && "$php_ver" != "$new_php_ver" ]]; then
        echo -e "  - PHP đã cập nhật: $php_ver -> $new_php_ver"
        systemctl restart php*-fpm 2>/dev/null
    fi
    
    echo -e "  - Kernel hiện tại: $new_kernel_ver"
    echo -e "${YELLOW}Lưu ý: Nếu Kernel vừa được cập nhật, bạn CẦN KHỞI ĐỘNG LẠI (Reboot) VPS để Kernel mới có hiệu lực và chống lại lỗi LPE.${NC}"
    echo -e "${BLUE}=================================================${NC}"
    
    read -p "Bạn có muốn khởi động lại (Reboot) VPS ngay bây giờ không? [y/N]: " do_reboot
    if [[ "${do_reboot,,}" == "y" ]]; then
        echo -e "${RED}Đang khởi động lại hệ thống... Vui lòng kết nối lại sau ít phút.${NC}"
        reboot
    fi
    pause
}

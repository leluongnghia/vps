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
        echo -e "9.  🌍 Chặn theo Quốc gia (qua Cloudflare CF-IPCountry)"
        echo -e "10. 🔒 Bảo mật PHP (Disable Dangerous Functions)"
        echo -e "11. 🛡️  Kiểm tra & Vá lỗi Bảo mật (Nginx Rift - CVE-2026-42945)"
        echo -e "0.  Quay lại Menu chính"
        echo -e "${BLUE}=================================================${NC}"
        read -p "Nhập lựa chọn [0-11]: " choice

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
    
    # List of dangerous functions (excluding curl_exec, curl_multi_exec, parse_ini_file to prevent breaking WordPress)
    local funcs="exec,passthru,shell_exec,system,proc_open,popen,show_source"
    
    # Áp dụng cho mọi php.ini của FPM: Debian (/etc/php/X.Y/fpm) và RHEL (/etc/php.ini)
    local ini ver applied=0
    for ini in /etc/php/*/fpm/php.ini /etc/php.ini; do
        [[ -f "$ini" ]] || continue
        # Handle: uncommented line, commented line, or missing line
        if grep -q "^disable_functions" "$ini"; then
            sed -i "s|^disable_functions.*|disable_functions = $funcs|" "$ini"
        elif grep -q "^;disable_functions" "$ini"; then
            sed -i "s|^;disable_functions.*|disable_functions = $funcs|" "$ini"
        else
            echo "disable_functions = $funcs" >> "$ini"
        fi
        ver=$(echo "$ini" | grep -oE '[0-9]+\.[0-9]+' | head -1)
        if php_fpm_restart_safe "$ver"; then
            log_info "Đã update disable_functions: $ini"
            applied=$((applied + 1))
        fi
    done
    [[ $applied -eq 0 ]] && log_warn "Không tìm thấy php.ini nào của PHP-FPM để cấu hình."
    if [[ -z "$1" ]]; then pause; fi
}

# ── SSH helpers ───────────────────────────────────────────────────────────────

# Các cổng sshd đang cấu hình (mỗi cổng 1 dòng)
_ssh_ports() {
    local p
    p=$(sshd -T 2>/dev/null | awk '$1=="port"{print $2}')
    if [[ -z "$p" ]]; then
        p=$(grep -hE "^[[:space:]]*Port[[:space:]]+[0-9]+" /etc/ssh/sshd_config /etc/ssh/sshd_config.d/*.conf 2>/dev/null | awk '{print $2}')
    fi
    [[ -z "$p" ]] && p=22
    echo "$p" | sort -un
}

_port_listening() {
    ss -tlnH 2>/dev/null | awk '{print $4}' | grep -qE "[:.]$1\$"
}

# Restart sshd đúng cách trên cả Debian/Ubuntu (ssh, có thể socket-activated) và RHEL (sshd)
_ssh_restart() {
    systemctl daemon-reload
    if systemctl is-active --quiet ssh.socket 2>/dev/null; then
        systemctl restart ssh.socket
    fi
    if systemctl list-unit-files ssh.service 2>/dev/null | grep -q '^ssh\.service'; then
        systemctl restart ssh
    else
        systemctl restart sshd
    fi
}

# Ghi cấu hình fail2ban vào file riêng (không copy jail.conf -> không bị trùng section khi chạy lại)
_write_fail2ban_jail() {
    local ports
    ports=$(_ssh_ports | paste -sd, -)
    mkdir -p /etc/fail2ban/jail.d
    cat > /etc/fail2ban/jail.d/vps-manager.local <<EOF
# Managed by VPS-Manager
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 5

[sshd]
enabled = true
port = ${ports}
maxretry = 3
bantime = 3600
EOF
    if [[ "$OS_FAMILY" == "rhel" ]]; then
        echo "backend = systemd" >> /etc/fail2ban/jail.d/vps-manager.local
    fi
    # Gỡ section [sshd] do phiên bản cũ của script nối thêm vào jail.local (gây lỗi trùng section)
    if [[ -f /etc/fail2ban/jail.local ]] && [[ $(grep -c '^\[sshd\]' /etc/fail2ban/jail.local) -gt 1 ]]; then
        mv /etc/fail2ban/jail.local "/etc/fail2ban/jail.local.bak_$(date +%s)"
        log_warn "jail.local cũ bị trùng section [sshd] - đã chuyển thành file .bak"
    fi
}

setup_firewall() {
    log_info "Đang cấu hình Firewall & Fail2ban..."

    # Cổng SSH THỰC TẾ đang dùng - phải mở trước khi bật tường lửa để không tự khoá mình
    local ssh_ports p
    ssh_ports=$(_ssh_ports)
    log_info "Cổng SSH đang dùng: $(echo $ssh_ports)"

    if [[ "$OS_FAMILY" == "rhel" ]]; then
        # fail2ban nằm trong EPEL -> bật EPEL trước, cài riêng để firewalld không bị kéo theo khi lỗi
        pkg_install firewalld
        pkg_install epel-release &>/dev/null || true
        pkg_install fail2ban || log_warn "Không cài được fail2ban (cần EPEL)."

        systemctl enable firewalld
        systemctl start firewalld

        firewall-cmd --permanent --add-service=ssh
        for p in $ssh_ports; do
            firewall-cmd --permanent --add-port="${p}/tcp"
        done
        firewall-cmd --permanent --add-service=http
        firewall-cmd --permanent --add-service=https
        firewall-cmd --reload
    else
        pkg_install ufw fail2ban

        # Configure UFW
        ufw default deny incoming
        ufw default allow outgoing
        for p in $ssh_ports; do
            ufw allow "${p}/tcp"
        done
        ufw allow 80/tcp
        ufw allow 443/tcp

        # Enable UFW
        echo "y" | ufw enable
    fi

    if command -v fail2ban-client &>/dev/null; then
        _write_fail2ban_jail
        systemctl enable fail2ban &>/dev/null
        if systemctl restart fail2ban; then
            log_info "Tường lửa & Fail2ban đã được cài đặt."
        else
            log_error "Fail2ban không khởi động được. Kiểm tra: journalctl -u fail2ban -n 30"
        fi
    else
        log_info "Tường lửa đã được cài đặt (không có Fail2ban)."
    fi
    if [[ -z "$1" ]]; then pause; fi
}

change_ssh_port() {
    local current_ports current_port new_port p
    current_ports=$(_ssh_ports)
    current_port=$(echo "$current_ports" | head -1)
    echo -e "${YELLOW}Port SSH hiện tại: $(echo $current_ports)${NC}"

    read -p "Nhập cổng SSH mới (1024-65535): " new_port
    if [[ ! "$new_port" =~ ^[0-9]+$ ]] || [[ "$new_port" -lt 1024 ]] || [[ "$new_port" -gt 65535 ]]; then
        echo -e "${RED}Cổng không hợp lệ!${NC}"
        pause; return
    fi
    if echo "$current_ports" | grep -qx "$new_port"; then
        echo -e "${YELLOW}SSH đã dùng cổng $new_port rồi.${NC}"
        pause; return
    fi
    if _port_listening "$new_port"; then
        echo -e "${RED}Cổng $new_port đang được dịch vụ khác sử dụng!${NC}"
        pause; return
    fi

    # 1. SELinux: sshd chỉ bind được cổng lạ khi cổng đó có nhãn ssh_port_t
    if selinux_active; then
        command -v semanage &>/dev/null || pkg_install policycoreutils-python-utils &>/dev/null
        if ! semanage port -a -t ssh_port_t -p tcp "$new_port" 2>/dev/null \
            && ! semanage port -m -t ssh_port_t -p tcp "$new_port" 2>/dev/null; then
            log_error "Không gán được nhãn SELinux ssh_port_t cho cổng $new_port. Huỷ đổi cổng."
            pause; return 1
        fi
    fi

    # 2. Mở cổng mới trên tường lửa TRƯỚC (chưa đóng cổng cũ)
    if [[ "$OS_FAMILY" == "rhel" ]]; then
        if systemctl is-active --quiet firewalld; then
            firewall-cmd --permanent --add-port="${new_port}/tcp"
            firewall-cmd --reload
        fi
    elif command -v ufw &>/dev/null; then
        ufw allow "${new_port}/tcp"
    fi

    # 3. Sửa sshd_config (có backup), kiểm tra cú pháp rồi mới restart
    local cfg="/etc/ssh/sshd_config"
    local bak="${cfg}.bak_$(date +%s)"
    cp -p "$cfg" "$bak"
    sed -i -E '/^[[:space:]]*Port[[:space:]]+[0-9]+/d' "$cfg"
    # Đặt Port ở đầu file để không rơi vào trong khối Match
    sed -i "1i Port $new_port" "$cfg"

    if ! sshd -t 2>/dev/null; then
        log_error "sshd_config có lỗi sau khi sửa - đã hoàn tác, cổng SSH KHÔNG đổi."
        sshd -t
        cp -p "$bak" "$cfg"
        pause; return 1
    fi

    _ssh_restart
    sleep 2

    # 4. Chỉ đóng cổng cũ khi sshd ĐÃ nghe trên cổng mới
    if ! _port_listening "$new_port"; then
        log_error "sshd KHÔNG nghe trên cổng $new_port sau khi restart - đang hoàn tác."
        cp -p "$bak" "$cfg"
        _ssh_restart
        log_warn "Đã khôi phục cấu hình cũ. Cổng SSH vẫn là: $(echo $current_ports)"
        pause; return 1
    fi

    for p in $current_ports; do
        [[ "$p" == "$new_port" ]] && continue
        if [[ "$OS_FAMILY" == "rhel" ]]; then
            if systemctl is-active --quiet firewalld; then
                firewall-cmd --permanent --remove-port="${p}/tcp" &>/dev/null
                [[ "$p" == "22" ]] && firewall-cmd --permanent --remove-service=ssh &>/dev/null
            fi
        elif command -v ufw &>/dev/null; then
            ufw delete allow "${p}/tcp" &>/dev/null
            [[ "$p" == "22" ]] && ufw delete allow ssh &>/dev/null
        fi
    done
    [[ "$OS_FAMILY" == "rhel" ]] && systemctl is-active --quiet firewalld && firewall-cmd --reload

    # 5. Fail2ban phải theo cổng mới
    if command -v fail2ban-client &>/dev/null; then
        _write_fail2ban_jail
        systemctl restart fail2ban &>/dev/null
    fi

    log_info "Đã đổi Port SSH sang $new_port (đã kiểm tra sshd đang nghe trên cổng mới)."
    echo -e "${YELLOW}QUAN TRỌNG: GIỮ NGUYÊN phiên SSH này, mở một cửa sổ khác và thử:${NC}"
    echo -e "${YELLOW}    ssh -p $new_port root@<IP_VPS>${NC}"
    echo -e "${YELLOW}Nếu VPS có tường lửa của nhà cung cấp (Security Group), hãy mở cổng $new_port ở đó.${NC}"
    echo -e "Backup cấu hình cũ: $bak"
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
    
    if [[ "$tries" -lt 1 || "$tries" -gt 20 ]]; then
        echo -e "${RED}Giá trị không hợp lệ (1-20).${NC}"; pause; return
    fi

    local cfg="/etc/ssh/sshd_config"
    local bak="${cfg}.bak_$(date +%s)"
    cp -p "$cfg" "$bak"
    sed -i -E '/^[#[:space:]]*MaxAuthTries[[:space:]]/d' "$cfg"
    # Đặt ở đầu file để không rơi vào trong khối Match
    sed -i "1i MaxAuthTries $tries" "$cfg"

    if ! sshd -t 2>/dev/null; then
        log_error "sshd_config có lỗi sau khi sửa - đã hoàn tác."
        cp -p "$bak" "$cfg"
        pause; return 1
    fi

    if _ssh_restart; then
        rm -f "$bak"
        log_info "Đã thiết lập MaxAuthTries = $tries"
    else
        log_error "Không restart được SSH. Backup cấu hình cũ: $bak"
    fi
    pause
}

# Sửa nhiều vhost cùng lúc với rollback toàn bộ nếu nginx -t lỗi.
# Dùng: _vhost_batch_edit <hàm_sửa> <domain...>   (hàm_sửa nhận 1 tham số: đường dẫn conf)
_vhost_batch_edit() {
    local fn=$1; shift
    local -a confs=() baks=()
    local d conf bak i
    for d in "$@"; do
        conf="/etc/nginx/sites-available/$d"
        [[ -f "$conf" ]] || continue
        bak=$(backup_nginx_config "$conf")
        confs+=("$conf"); baks+=("$bak")
        "$fn" "$conf"
    done
    [[ ${#confs[@]} -eq 0 ]] && { log_warn "Không có vhost nào để sửa."; return 1; }

    local out
    if out=$(nginx -t 2>&1); then
        systemctl reload nginx
        for bak in "${baks[@]}"; do rm -f "$bak"; done
        return 0
    fi
    log_error "Nginx config có lỗi - đang hoàn tác toàn bộ thay đổi:"
    echo "$out" | tail -8
    for i in "${!confs[@]}"; do
        [[ -f "${baks[$i]}" ]] && mv -f "${baks[$i]}" "${confs[$i]}"
    done
    return 1
}

# Danh sách domain có vhost (bỏ default/html và các file backup)
_all_vhost_domains() {
    local conf d
    for conf in /etc/nginx/sites-available/*; do
        [[ -f "$conf" ]] || continue
        d=$(basename "$conf")
        [[ "$d" == "default" || "$d" == "html" || "$d" == *.bak* ]] && continue
        echo "$d"
    done
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
    
    if [[ "$c" == "0" ]]; then nginx_test_reload; pause; return; fi

    # Hàm sửa 1 vhost (nhận đường dẫn conf)
    _apply_limit_conf() {
        local conf=$1
        if ! grep -q "limit_req zone=one" "$conf"; then
            # Insert after server_name
            sed -i "/server_name/a \    limit_req zone=one burst=20 nodelay;" "$conf"
        fi
        # limit_req đặt trong server block sẽ che limit_req cấp http -> phải khai báo lại giới hạn wp-login tại đây
        if grep -qs 'zone=vpsm_wplogin' /etc/nginx/conf.d/vps-manager-wplogin.conf \
            && ! grep -q "limit_req zone=vpsm_wplogin" "$conf"; then
            sed -i "/server_name/a \    limit_req zone=vpsm_wplogin burst=10 nodelay;" "$conf"
        fi
    }

    if [[ "$c" == "1" ]]; then
        if _vhost_batch_edit _apply_limit_conf $(_all_vhost_domains); then
            log_info "Đã áp dụng Rate Limit cho toàn bộ website."
        else
            log_error "Áp dụng Rate Limit THẤT BẠI - cấu hình các website giữ nguyên."
        fi
    elif [[ "$c" == "2" ]]; then
        source "$(dirname "${BASH_SOURCE[0]}")/site.sh"
        select_site || return
        if _vhost_batch_edit _apply_limit_conf "$SELECTED_DOMAIN"; then
            log_info "Đã áp dụng Rate Limit cho $SELECTED_DOMAIN."
        else
            log_error "Áp dụng Rate Limit THẤT BẠI - cấu hình giữ nguyên."
        fi
    fi
    pause
}

# Kiểm tra 1 file WAF snippet có được nginx chấp nhận không, bằng 1 config thử độc lập
# (không đụng tới config đang chạy). Trả về 1 nếu snippet lỗi.
_waf_snippet_valid() {
    local snippet=$1 tmp rc
    tmp=$(mktemp -d) || return 1
    cat > "$tmp/nginx.conf" <<EOF
pid $tmp/nginx.pid;
error_log $tmp/error.log;
events {}
http {
    access_log off;
    server {
        listen 127.0.0.1:65500;
        include $snippet;
    }
}
EOF
    nginx -t -c "$tmp/nginx.conf" &>"$tmp/out"
    rc=$?
    if [[ $rc -ne 0 ]]; then
        log_error "Snippet $(basename "$snippet") bị nginx từ chối:"
        grep -v "test failed" "$tmp/out" | tail -5
    fi
    rm -rf "$tmp"
    return $rc
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
if ($query_string ~* "(eval\()|(javascript:)|(base64_encode)|(GLOBALS|REQUEST)(=|\[|%)|(union.*select)|(concat.*\()|(benchmark\()|(from.*information_schema)|(sleep\()|(into.*outfile)|(load_file\()|(0x[0-9a-f]{2}){10,}|(\\|\.\.\.|\.\./|~|`|<|>|\|)") {
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
if ($request_uri ~* "(eval\()|(javascript:)|(base64_encode)|(union.*select)|(concat.*\()|(sleep\()|(0x[0-9a-f]{2}){10,}") {
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
# Chỉ chặn công cụ tấn công/quét. KHÔNG chặn chung "bot|crawl|spider|wget|python|curl"
# vì sẽ chặn luôn Googlebot/Bingbot và cron wget của chính server.
if ($http_user_agent ~* "(archiver|libwww-perl|sqlmap|nikto|h4x0r|masscan|ZmEu|dirbuster|nmap|acunetix|nessus|wpscan|havij|zgrab)") {
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

    # Kiểm tra rule hợp lệ TRƯỚC khi để lại trên đĩa: site.sh tự include 7g.conf vào vhost mới nếu file tồn tại
    if ! _waf_snippet_valid "$waf_file"; then
        rm -f "$waf_file"
        log_error "7G WAF KHÔNG được cài (rule lỗi cú pháp). Cấu hình các website giữ nguyên."
        pause; return 1
    fi

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
if ($query_string ~* "(\bc99\b|\br57\b|c99shell|shell_exec|passthru|base64_decode|str_rot13|gzuncompress)") {
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

    if ! _waf_snippet_valid "$waf_file"; then
        rm -f "$waf_file"
        log_error "8G WAF KHÔNG được cài (rule lỗi cú pháp). Cấu hình các website giữ nguyên."
        pause; return 1
    fi

    [[ "$c" == "0" ]] && { log_info "File rule tại: $waf_file"; pause; return; }

    # Bỏ 7G nếu đã có, thay bằng 8G (đã include 7G)
    _apply_nginx_snippet "8g.conf" "include /etc/nginx/snippets/8g.conf;" "$c" "7g.conf"
    pause
}

# Helper: Áp dụng 1 snippet vào 1 Nginx vhost cụ thể
# $1: domain  $2: snippet_file  $3: include_line  $4: old_snippet (optional)
# (dùng biến _SNIP_* vì được gọi qua _vhost_batch_edit với 1 tham số là đường dẫn conf)
_do_apply_snippet() {
    local conf=$1
    local snippet_file=$_SNIP_FILE
    local include_line=$_SNIP_INCLUDE
    local old_snippet="${_SNIP_OLD:-}"
    [[ ! -f "$conf" ]] && return

    # Xóa snippet cũ nếu được chỉ định
    if [[ -n "$old_snippet" ]]; then
        sed -i "\|include[[:space:]].*/${old_snippet};|d" "$conf" 2>/dev/null
    fi

    if ! grep -qF "/${snippet_file};" "$conf"; then
        # Chỉ chèn sau dòng server_name ĐẦU TIÊN của mỗi server block có root/proxy (tránh block redirect)
        sed -i "/server_name/a\\    ${include_line}" "$conf"
    fi
}

# Helper: Áp dụng snippet vào Nginx vhost(s) - rollback toàn bộ nếu nginx -t lỗi
# $1: snippet filename  $2: include directive  $3: choice (1=all,2=select)  $4: old snippet to remove (optional)
_apply_nginx_snippet() {
    local snippet_file="$1"
    local include_line="$2"
    local choice="$3"
    local old_snippet="${4:-}"
    _SNIP_FILE="$snippet_file"; _SNIP_INCLUDE="$include_line"; _SNIP_OLD="$old_snippet"

    if [[ "$choice" == "1" ]]; then
        if _vhost_batch_edit _do_apply_snippet $(_all_vhost_domains); then
            log_info "Đã áp dụng ${snippet_file} cho toàn bộ website."
        else
            log_error "Áp dụng ${snippet_file} THẤT BẠI - cấu hình các website giữ nguyên."
            return 1
        fi
    elif [[ "$choice" == "2" ]]; then
        source "$(dirname "${BASH_SOURCE[0]}")/site.sh"
        select_site || return
        if _vhost_batch_edit _do_apply_snippet "$SELECTED_DOMAIN"; then
            log_info "Đã áp dụng ${snippet_file} cho ${SELECTED_DOMAIN}."
        else
            log_error "Áp dụng ${snippet_file} THẤT BẠI - cấu hình giữ nguyên."
            return 1
        fi
    fi
}


setup_geoip_block() {
    log_info "Cấu hình chặn theo quốc gia (dựa trên header CF-IPCountry của Cloudflare)..."

    # Tính năng này đọc header CF-IPCountry do Cloudflare gắn vào request, KHÔNG dùng database GeoIP.
    echo -e "${YELLOW}LƯU Ý:${NC}"
    echo -e "  • Chỉ có tác dụng với website đang chạy qua Cloudflare (bật proxy - đám mây cam)."
    echo -e "  • Request đi thẳng vào IP của VPS (không qua Cloudflare) sẽ KHÔNG bị chặn."
    echo -e "    → Nên chỉ cho phép dải IP Cloudflare truy cập cổng 80/443 trên tường lửa."
    echo ""

    # Hỏi user chọn quốc gia cần block
    echo -e "${YELLOW}Danh sách code quốc gia cần BLOCK (ISO 3166-1 alpha-2):${NC}"
    echo -e "  Ví dụ: CN RU KP IR KH (cách nhau bằng dấu cách)"
    echo -e "  CN=Trung Quốc, RU=Nga, KP=Triều Tiên, IR=Iran, KH=Campuchia"
    read -p "Nhập danh sách quốc gia block: " country_list
    [[ -z "$country_list" ]] && { log_warn "Không có quốc gia nào được nhập."; pause; return; }

    local code valid_codes=""
    for code in $country_list; do
        code=$(echo "$code" | tr '[:lower:]' '[:upper:]')
        if [[ "$code" =~ ^[A-Z]{2}$ ]]; then
            valid_codes+="$code "
        else
            log_warn "Bỏ qua mã không hợp lệ: $code"
        fi
    done
    [[ -z "$valid_codes" ]] && { log_error "Không có mã quốc gia hợp lệ nào."; pause; return; }
    country_list="${valid_codes% }"

    # Tạo cấu hình map
    local geoip_conf="/etc/nginx/conf.d/geoip_block.conf"
    {
        echo "# Country Block (Cloudflare CF-IPCountry) - Tạo bởi VPS Manager"
        echo "map \$http_cf_ipcountry \$is_blocked_country {"
        echo "    default 0;"
        for code in $country_list; do
            echo "    $code 1;"
        done
        echo "}"
    } > "$geoip_conf"

    # Snippet để include trong server block.
    # Không whitelist theo User-Agent: UA giả mạo được nên whitelist đó chính là lỗ hổng vượt chặn.
    cat > /etc/nginx/snippets/geoip_block.conf <<'GEOF'
# Block countries defined in conf.d/geoip_block.conf (Cloudflare CF-IPCountry)
if ($is_blocked_country) {
    return 403;
}
GEOF

    # File map trong conf.d được nạp ngay ở lần reload tới -> phải hợp lệ trước khi đi tiếp
    if ! nginx -t &>/dev/null; then
        log_error "Cấu hình chặn quốc gia bị nginx từ chối - đã gỡ bỏ:"
        nginx -t 2>&1 | tail -5
        rm -f "$geoip_conf" /etc/nginx/snippets/geoip_block.conf
        pause; return 1
    fi

    echo -e "${YELLOW}Áp dụng chặn quốc gia cho website:${NC}"
    echo -e "1. Áp dụng cho TẤT CẢ website"
    echo -e "2. Chọn website cụ thể"
    echo -e "0. Chỉ tạo config (apply tay)"
    read -p "Chọn: " c

    if [[ "$c" == "0" ]]; then
        nginx_test_reload
        log_info "Đã tạo config. Thêm dòng sau vào server block: include /etc/nginx/snippets/geoip_block.conf;"
    elif _apply_nginx_snippet "geoip_block.conf" "include /etc/nginx/snippets/geoip_block.conf;" "$c"; then
        log_info "✅ Đã cấu hình chặn quốc gia: ${country_list}"
    fi
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

#!/bin/bash
# modules/monit.sh - Service Watchdog (Monit)
# Tự động restart service khi sập, tích hợp tuỳ chọn Telegram alert

monit_menu() {
    clear
    echo -e "${BLUE}=================================================${NC}"
    echo -e "${GREEN}      Watchdog Giám sát Dịch vụ (Monit)${NC}"
    echo -e "${BLUE}=================================================${NC}"
    echo ""
    _monit_print_status
    echo ""
    echo -e "${BLUE}=================================================${NC}"
    echo -e "1. Cài đặt / Cập nhật Watchdog (Monit)"
    echo -e "2. Gỡ bỏ Watchdog"
    echo -e "3. Xem trạng thái giám sát"
    echo -e "4. Cấu hình Telegram Alert"
    echo -e "5. Reload cấu hình Monit"
    echo -e "0. Quay lại"
    echo -e "${BLUE}=================================================${NC}"
    read -p "Nhập lựa chọn [0-5]: " choice

    case $choice in
        1) monit_install ;;
        2) monit_uninstall ;;
        3) monit_status; pause ;;
        4) monit_setup_telegram ;;
        5) monit_reload; pause ;;
        0) return ;;
        *) echo -e "${RED}Lựa chọn không hợp lệ!${NC}"; pause ;;
    esac
}

# ────────────────────────────────────────────────────────────
# HELPERS
# ────────────────────────────────────────────────────────────
_monit_detect_os() {
    if [[ -f /etc/os-release ]]; then source /etc/os-release; fi
    if [[ "${ID:-}" == "ubuntu" || "${ID:-}" == "debian" ]]; then
        MONIT_OS="debian"
        MONIT_CONF="/etc/monit/monitrc"
        MONIT_CONFDIR="/etc/monit/conf.d"
        MONIT_PID_MARIADB="/run/mysqld/mysqld.pid"
        MONIT_SOCK_MARIADB="/run/mysqld/mysqld.sock"
    else
        MONIT_OS="rhel"
        MONIT_CONF="/etc/monitrc"
        MONIT_CONFDIR="/etc/monit.d"
        MONIT_PID_MARIADB="/run/mariadb/mariadb.pid"
        MONIT_SOCK_MARIADB="/var/lib/mysql/mysql.sock"
    fi
}

_monit_print_status() {
    if command -v monit &>/dev/null; then
        if systemctl is-active --quiet monit 2>/dev/null; then
            echo -e "  Monit : ${GREEN}ĐÃ CÀI VÀ ĐANG CHẠY${NC}"
        else
            echo -e "  Monit : ${YELLOW}Đã cài nhưng chưa chạy${NC}"
        fi
        echo -e "  Phiên bản: $(monit -V 2>&1 | head -1)"
    else
        echo -e "  Monit : ${RED}CHƯA CÀI ĐẶT${NC}"
    fi

    # Hiển thị các service đang theo dõi
    _monit_detect_os
    if [[ -d "$MONIT_CONFDIR" ]]; then
        local rules
        rules=$(ls "$MONIT_CONFDIR" 2>/dev/null | grep -v '\.bak$')
        if [[ -n "$rules" ]]; then
            echo -e "  Rules  : ${CYAN}$(echo $rules | tr '\n' ' ')${NC}"
        fi
    fi
}

_monit_detect_webserver() {
    # Since v1.6.0: standardized on Nginx. Detect just in case OLS is still somehow running.
    if systemctl is-active --quiet lshttpd 2>/dev/null; then
        echo "openlitespeed"
    else
        echo "nginx"
    fi
}

_monit_detect_cache() {
    for svc in valkey keydb redis; do
        if systemctl is-active --quiet "$svc" 2>/dev/null || systemctl is-enabled --quiet "$svc" 2>/dev/null; then
            echo "$svc"; return
        fi
    done
    echo ""
}

# ────────────────────────────────────────────────────────────
# CÀI ĐẶT MONIT
# ────────────────────────────────────────────────────────────
monit_install() {
    local mode="${1:-}"
    _monit_detect_os

    echo ""
    echo -e "${YELLOW}Monit sẽ:${NC}"
    echo -e "  • Giám sát Webserver, MariaDB, Object Cache mỗi 30 giây"
    echo -e "  • Tự động restart ngay nếu service sập"
    echo -e "  • Tắt service vĩnh viễn sau 5 lần crash liên tục (tránh loop)"
    echo ""

    # ── Bước 1: Cài monit ──
    if ! command -v monit &>/dev/null; then
        log_info "Đang cài Monit..."
        if [[ "$MONIT_OS" == "debian" ]]; then
            DEBIAN_FRONTEND=noninteractive apt-get update -qq 2>/dev/null
            DEBIAN_FRONTEND=noninteractive apt-get install -y monit &>/dev/null
        else
            # RHEL cần EPEL
            dnf install -y epel-release &>/dev/null || yum install -y epel-release &>/dev/null
            dnf install -y monit &>/dev/null || yum install -y monit &>/dev/null
        fi

        if ! command -v monit &>/dev/null; then
            log_error "Không thể cài Monit. Kiểm tra kết nối mạng."
            [[ "$mode" != "auto" ]] && pause
            return 1
        fi
        log_info "  ✓ Monit đã cài"
    else
        log_info "Monit đã có sẵn: $(monit -V 2>&1 | head -1 | awk '{print $NF}')"
    fi

    mkdir -p "$MONIT_CONFDIR"

    # ── Bước 2: Cấu hình Monit Core ──
    _monit_setup_core

    # ── Bước 3: Tạo rules giám sát ──
    local web_type
    web_type="$(_monit_detect_webserver)"
    _monit_rule_webserver "$web_type"

    _monit_rule_mariadb

    local cache_svc
    cache_svc="$(_monit_detect_cache)"
    [[ -n "$cache_svc" ]] && _monit_rule_cache "$cache_svc"

    _monit_rule_sshd

    # ── Bước 4: Khởi động ──
    systemctl enable monit &>/dev/null
    systemctl daemon-reload
    systemctl restart monit

    if systemctl is-active --quiet monit; then
        monit monitor all &>/dev/null || true
        echo ""
        echo -e "${GREEN}=================================================${NC}"
        echo -e "${GREEN}  Monit Watchdog đã được cài đặt thành công!${NC}"
        echo -e "${GREEN}=================================================${NC}"
        monit_status
    else
        log_error "Monit khởi động thất bại. Kiểm tra: journalctl -u monit"
    fi
    [[ "$mode" != "auto" ]] && pause
}

# ── Cấu hình core Monit (HTTP socket + daemon interval) ──
_monit_setup_core() {
    log_info "Cấu hình Monit daemon..."
    local conf="$MONIT_CONF"

    # Đặt interval 30s
    sed -i 's/set daemon *[0-9]*/set daemon 30/' "$conf" 2>/dev/null || true
    if ! grep -q 'set daemon' "$conf" 2>/dev/null; then
        echo "set daemon 30" >> "$conf"
    fi

    # HTTP socket trên localhost (dùng monit status)
    if ! grep -q 'set httpd port 2812' "$conf" 2>/dev/null; then
        cat >> "$conf" <<'EOF'

# VPS Manager Monit HTTP
set httpd port 2812
    use address 127.0.0.1
    allow 127.0.0.1
EOF
    fi

    log_info "  ✓ Monit core configured (interval=30s)"
}

# ── Rule Webserver ──
_monit_rule_webserver() {
    local web_type="$1"
    local rule_file="$MONIT_CONFDIR/webserver"

    if [[ "$web_type" == "openlitespeed" ]]; then
        # OpenLiteSpeed
        cat > "$rule_file" <<'EOF'
check process lshttpd
    with pidfile /var/run/openlitespeed.pid
    start program = "/usr/bin/systemctl start lshttpd"
    stop program  = "/usr/bin/systemctl stop lshttpd"
    if failed host 127.0.0.1 port 80 with timeout 10 seconds then restart
    if 5 restarts within 5 cycles then timeout
EOF
        log_info "  ✓ Rule OpenLiteSpeed"
    else
        # Nginx
        cat > "$rule_file" <<'EOF'
check process nginx
    with pidfile /var/run/nginx.pid
    start program = "/usr/bin/systemctl start nginx"
    stop program  = "/usr/bin/systemctl stop nginx"
    if failed host 127.0.0.1 port 80 with timeout 10 seconds then restart
    if 5 restarts within 5 cycles then timeout
EOF
        log_info "  ✓ Rule Nginx"
    fi
}

# ── Rule MariaDB ──
_monit_rule_mariadb() {
    local rule_file="$MONIT_CONFDIR/mariadb"
    cat > "$rule_file" <<EOF
check process mariadb
    matching "mariadbd|mysqld"
    start program = "/usr/bin/systemctl start mariadb"
    stop program  = "/usr/bin/systemctl stop mariadb"
    if failed unixsocket ${MONIT_SOCK_MARIADB} protocol mysql then restart
    if 5 restarts within 5 cycles then timeout
EOF
    log_info "  ✓ Rule MariaDB"
}

# ── Rule Object Cache (Valkey/KeyDB/Redis) ──
_monit_rule_cache() {
    local svc="$1"
    local rule_file="$MONIT_CONFDIR/${svc}"
    local proc_name="${svc}-server"

    # Xoá rules cũ của các cache khác
    for other in valkey keydb redis; do
        [[ "$other" != "$svc" ]] && rm -f "$MONIT_CONFDIR/$other"
    done

    cat > "$rule_file" <<EOF
check process ${svc}
    matching "${proc_name}"
    start program = "/usr/bin/systemctl start ${svc}"
    stop program  = "/usr/bin/systemctl stop ${svc}"
    if failed unixsocket /tmp/${svc}.sock protocol redis then restart
    if 5 restarts within 5 cycles then timeout
EOF
    log_info "  ✓ Rule ${svc} (Object Cache)"
}

# ── Rule SSH ──
_monit_rule_sshd() {
    local rule_file="$MONIT_CONFDIR/sshd"
    local ssh_port
    ssh_port=$(grep -E '^Port ' /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}' | head -1)
    [[ -z "$ssh_port" ]] && ssh_port=22

    cat > "$rule_file" <<EOF
check process sshd
    with pidfile /var/run/sshd.pid
    start program = "/usr/bin/systemctl start sshd"
    stop program  = "/usr/bin/systemctl stop sshd"
    if failed host 127.0.0.1 port ${ssh_port} protocol ssh then restart
    if 5 restarts within 5 cycles then timeout
EOF
    log_info "  ✓ Rule SSH (port ${ssh_port})"
}

# ────────────────────────────────────────────────────────────
# CẤU HÌNH TELEGRAM ALERT
# ────────────────────────────────────────────────────────────
monit_setup_telegram() {
    _monit_detect_os
    echo ""
    echo -e "${CYAN}--- Cấu hình Telegram Alert cho Monit ---${NC}"
    echo -e "Khi service sập và được restart, bot Telegram sẽ gửi tin nhắn cho bạn."
    echo ""

    # Đọc cấu hình cũ nếu có
    local tg_conf="/etc/vps-manager/telegram.conf"
    local old_bot="" old_chat=""
    if [[ -f "$tg_conf" ]]; then
        old_bot=$(grep 'TELEGRAM_BOT=' "$tg_conf" | cut -d= -f2)
        old_chat=$(grep 'TELEGRAM_CHAT=' "$tg_conf" | cut -d= -f2)
    fi

    read -p "Nhập Bot Token [${old_bot:-để trống=bỏ qua}]: " new_bot
    read -p "Nhập Chat ID   [${old_chat:-để trống=bỏ qua}]: " new_chat

    [[ -z "$new_bot" ]] && new_bot="$old_bot"
    [[ -z "$new_chat" ]] && new_chat="$old_chat"

    if [[ -z "$new_bot" || -z "$new_chat" ]]; then
        echo -e "${YELLOW}Thiếu Bot Token hoặc Chat ID → bỏ qua cấu hình Telegram.${NC}"
        pause; return
    fi

    # Test kết nối
    log_info "Đang kiểm tra kết nối Telegram..."
    local test_resp
    test_resp=$(curl -s --max-time 10 \
        "https://api.telegram.org/bot${new_bot}/sendMessage" \
        -d "chat_id=${new_chat}&text=VPS+Manager+Watchdog+Test+OK" 2>/dev/null)

    if echo "$test_resp" | grep -q '"ok":true'; then
        log_info "  ✓ Telegram kết nối thành công!"
    else
        log_warn "Không thể gửi tin nhắn test. Kiểm tra lại Bot Token và Chat ID."
        read -p "Vẫn muốn lưu cấu hình này? [y/N]: " force
        [[ "${force,,}" != "y" ]] && { pause; return; }
    fi

    # Lưu cấu hình
    mkdir -p /etc/vps-manager
    chmod 700 /etc/vps-manager
    cat > "$tg_conf" <<EOF
TELEGRAM_BOT=${new_bot}
TELEGRAM_CHAT=${new_chat}
EOF
    chmod 600 "$tg_conf"

    # Tạo script alert hook
    local hook_script="/etc/vps-manager/monit-telegram-alert.sh"
    cat > "$hook_script" <<'SCRIPT'
#!/bin/bash
# Hook script: Monit gọi khi service restart
# Usage: monit-telegram-alert.sh <service_name>
source /etc/vps-manager/telegram.conf 2>/dev/null || exit 0
[[ -z "$TELEGRAM_BOT" || -z "$TELEGRAM_CHAT" ]] && exit 0

SVC_NAME="${1:-Unknown Service}"
VPS_IP=$(curl -sf --max-time 5 https://ipv4.icanhazip.com 2>/dev/null || hostname -I | awk '{print $1}')
DATE=$(date "+%d/%m/%Y %H:%M:%S")

MSG="🚨 *VPS Manager Alert*
━━━━━━━━━━━━━━
📌 *Service:* ${SVC_NAME}
🖥 *VPS IP:* ${VPS_IP}
🕐 *Thời gian:* ${DATE}
⚠️ *Hành động:* Monit đã TỰ ĐỘNG RESTART"

curl -s --max-time 10 \
    "https://api.telegram.org/bot${TELEGRAM_BOT}/sendMessage" \
    -d "chat_id=${TELEGRAM_CHAT}&text=${MSG}&parse_mode=Markdown" \
    >/dev/null 2>&1 &
SCRIPT
    chmod +x "$hook_script"

    # Cập nhật rules monit để dùng hook
    _monit_inject_telegram_hook "$hook_script"

    log_info "Telegram Alert đã được cấu hình!"
    pause
}

_monit_inject_telegram_hook() {
    local hook="$1"
    # Inject hook vào tất cả start program trong rules
    for rule_file in "$MONIT_CONFDIR"/*; do
        [[ ! -f "$rule_file" ]] && continue
        local svc_name
        svc_name=$(basename "$rule_file")
        # Thêm alert call sau start program (nếu chưa có)
        if ! grep -q 'monit-telegram-alert' "$rule_file" 2>/dev/null; then
            sed -i "/start program/a\\    exec \"/bin/bash ${hook} ${svc_name}\"" "$rule_file" 2>/dev/null || true
        fi
    done
    log_info "  ✓ Telegram hook đã được inject vào rules"
}

# ────────────────────────────────────────────────────────────
# GỠ BỎ MONIT
# ────────────────────────────────────────────────────────────
monit_uninstall() {
    echo ""
    read -p "Bạn chắc chắn muốn GỠ BỎ Monit Watchdog? [y/N]: " confirm
    [[ "${confirm,,}" != "y" ]] && { echo -e "${YELLOW}Đã huỷ.${NC}"; pause; return; }

    _monit_detect_os
    log_info "Đang dừng và gỡ Monit..."

    systemctl stop monit &>/dev/null || true
    systemctl disable monit &>/dev/null || true

    if [[ "$MONIT_OS" == "debian" ]]; then
        DEBIAN_FRONTEND=noninteractive apt-get remove --purge monit -y &>/dev/null || true
    else
        dnf remove -y monit &>/dev/null || yum remove -y monit &>/dev/null || true
    fi

    rm -rf /etc/vps-manager/monit-telegram-alert.sh
    log_info "Monit đã được gỡ bỏ."
    pause
}

# ────────────────────────────────────────────────────────────
# TRẠNG THÁI VÀ RELOAD
# ────────────────────────────────────────────────────────────
monit_status() {
    echo ""
    echo -e "${CYAN}--- Trạng thái Monit Watchdog ---${NC}"

    if ! command -v monit &>/dev/null; then
        echo -e "${RED}Monit chưa được cài đặt.${NC}"
        return 1
    fi

    if systemctl is-active --quiet monit 2>/dev/null; then
        echo -e "  Daemon : ${GREEN}RUNNING${NC}"
    else
        echo -e "  Daemon : ${RED}STOPPED${NC}"
    fi

    echo ""
    # Monit summary
    monit summary 2>/dev/null || echo "  (Không kết nối được Monit daemon)"
}

monit_reload() {
    if ! command -v monit &>/dev/null; then
        log_error "Monit chưa được cài đặt."
        return 1
    fi
    log_info "Đang reload cấu hình Monit..."
    systemctl daemon-reload
    monit reload 2>/dev/null || systemctl restart monit
    log_info "Monit đã reload xong."
}

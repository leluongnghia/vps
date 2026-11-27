#!/bin/bash

# core/reliability.sh - Ổn định & tốc độ cấp server
#   1. Tự khởi động lại dịch vụ khi chết + chống hết RAM (earlyoom)
#   2. Cập nhật bảo mật tự động
#   3. Slow log cho PHP-FPM và MariaDB
#   4. Cảnh báo qua Telegram + kiểm tra sức khoẻ định kỳ
#   5. Giới hạn tần suất wp-login.php / xmlrpc.php
#   6. Nginx: HTTP/2 mặc định, TLS session cache, làm mới cache khi sửa bài
#   7. Tự tính kích thước FastCGI cache theo RAM và ổ đĩa của VPS
#
# Mọi hàm đều chạy lại được nhiều lần (idempotent) và tự hoàn tác khi nginx/php-fpm từ chối cấu hình.

VPSM_ETC="/etc/vps-manager"
VPSM_ALERT_CONF="$VPSM_ETC/alert.conf"
VPSM_REFRESH_KEY_FILE="$VPSM_ETC/cache_refresh.key"
VPSM_HEALTH_SCRIPT="/usr/local/bin/vps-healthcheck"
VPSM_HEALTH_LOG="/var/log/vps-health.log"

# ==============================================================================
# 7. Kích thước FastCGI cache theo cấu hình VPS
# ==============================================================================

# In ra: "<keys_zone MB> <max_size MB>"
#   keys_zone : bộ nhớ dùng chung giữ khoá cache (1MB ~ 8.000 trang) - tính theo RAM
#   max_size  : dung lượng cache trên đĩa - 10% dung lượng còn trống, trong khoảng 256MB..8GB
fastcgi_cache_sizing() {
    local ram_mb free_mb zone max
    ram_mb=$(free -m 2>/dev/null | awk '/^Mem:/{print $2}')
    [[ -z "$ram_mb" ]] && ram_mb=1024
    if   [[ "$ram_mb" -le 1100 ]]; then zone=10
    elif [[ "$ram_mb" -le 2200 ]]; then zone=16
    elif [[ "$ram_mb" -le 4400 ]]; then zone=32
    elif [[ "$ram_mb" -le 8800 ]]; then zone=48
    else zone=64
    fi

    mkdir -p /var/cache/nginx 2>/dev/null
    free_mb=$(df -Pm /var/cache/nginx 2>/dev/null | awk 'NR==2{print $4}')
    [[ -z "$free_mb" ]] && free_mb=10240
    max=$(( free_mb / 10 ))
    [[ "$max" -lt 256 ]] && max=256
    [[ "$max" -gt 8192 ]] && max=8192
    echo "$zone $max"
}

# Áp kích thước tự tính vào fastcgi_cache.conf đang có.
# Đổi keys_zone cần RESTART nginx (reload sẽ bị từ chối vì vùng nhớ dùng chung đã cấp phát).
fastcgi_cache_autosize() {
    local conf="/etc/nginx/conf.d/fastcgi_cache.conf"
    [[ -f "$conf" ]] || return 0
    grep -q "keys_zone=WORDPRESS:" "$conf" || return 0

    local zone max cur_zone cur_max
    read -r zone max <<< "$(fastcgi_cache_sizing)"
    cur_zone=$(grep -oE 'keys_zone=WORDPRESS:[0-9]+m' "$conf" | head -1 | grep -oE '[0-9]+m$' | tr -d m)
    cur_max=$(grep -oE 'max_size=[0-9]+[mg]' "$conf" | head -1 | cut -d= -f2)

    # Cache đặt trên RAM disk (tmpfs): max_size do mục RAM Disk quản lý - chỉ chỉnh keys_zone
    local on_tmpfs=0
    [[ "$(findmnt -n -o FSTYPE /var/cache/nginx/fastcgi 2>/dev/null)" == "tmpfs" ]] && on_tmpfs=1

    local want_max="${max}m"
    [[ "$on_tmpfs" -eq 1 ]] && want_max="$cur_max"

    if [[ "$cur_zone" == "$zone" && "$cur_max" == "$want_max" ]]; then
        return 0
    fi

    local bak="${conf}.bak_$$"
    cp -p "$conf" "$bak"
    sed -i -E "s/keys_zone=WORDPRESS:[0-9]+m/keys_zone=WORDPRESS:${zone}m/" "$conf"
    [[ "$on_tmpfs" -eq 0 ]] && sed -i -E "s/max_size=[0-9]+[mg]/max_size=${max}m/" "$conf"

    if ! nginx -t &>/dev/null; then
        mv -f "$bak" "$conf"
        log_warn "Không áp được kích thước cache mới (nginx -t lỗi) - giữ cấu hình cũ."
        return 1
    fi
    if [[ "$cur_zone" != "$zone" ]]; then
        if ! systemctl restart nginx; then
            mv -f "$bak" "$conf"
            systemctl restart nginx
            log_warn "Nginx không khởi động với kích thước cache mới - đã hoàn tác."
            return 1
        fi
    else
        systemctl reload nginx
    fi
    rm -f "$bak"
    log_info "FastCGI cache tự tính theo VPS: keys_zone=${zone}MB (trước: ${cur_zone:-?}MB), max_size=${want_max} (trước: ${cur_max:-?})."
}

# ==============================================================================
# 1. Tự khởi động lại dịch vụ + chống hết RAM
# ==============================================================================

_vpsm_units() {
    # nginx, MariaDB, mọi php-fpm, object cache - chỉ những unit thực sự tồn tại
    local u
    for u in nginx "$(mariadb_service_name)" "$(cache_service_name 2>/dev/null)"; do
        [[ -n "$u" ]] && systemctl list-unit-files "${u}.service" 2>/dev/null | grep -q "^${u}\.service" && echo "$u"
    done
    systemctl list-unit-files 'php*-fpm.service' 2>/dev/null | awk '/-fpm\.service/{sub(/\.service$/,"",$1); print $1}'
}

setup_service_resilience() {
    local u oom changed=0 dropin
    for u in $(_vpsm_units | sort -u); do
        # Khi thiếu RAM: kernel nên hạ PHP worker trước, giữ lại database và web server
        case "$u" in
            mariadb|mysql|mysqld) oom="-600" ;;
            nginx)                oom="-500" ;;
            php*-fpm)             oom="" ;;
            *)                    oom="-300" ;;
        esac
        dropin="/etc/systemd/system/${u}.service.d/vps-manager-restart.conf"
        mkdir -p "$(dirname "$dropin")"
        {
            echo "# Managed by VPS-Manager: tự khởi động lại khi dịch vụ chết bất thường"
            # KHÔNG đặt StartLimitIntervalSec/StartLimitBurst chặt hơn mặc định của systemd (5 lần/10 giây):
            # giới hạn đó tính cả các lần công cụ chủ động restart (thêm site, đổi cấu hình...), đặt 5 lần/5 phút
            # sẽ khiến systemd từ chối khởi động dịch vụ sau vài thao tác liên tiếp.
            echo "[Service]"
            echo "Restart=on-failure"
            echo "RestartSec=5s"
            [[ -n "$oom" ]] && echo "OOMScoreAdjust=${oom}"
        } > "${dropin}.new"
        if ! cmp -s "${dropin}.new" "$dropin" 2>/dev/null; then
            mv -f "${dropin}.new" "$dropin"; changed=1
        else
            rm -f "${dropin}.new"
        fi
    done
    [[ "$changed" -eq 1 ]] && systemctl daemon-reload

    # earlyoom: hạ tiến trình PHP ngốn RAM TRƯỚC khi máy treo cứng vì hết bộ nhớ
    if ! command -v earlyoom &>/dev/null; then
        [[ "${OS_FAMILY:-}" == "rhel" ]] && { pkg_install epel-release &>/dev/null || true; }
        pkg_install earlyoom &>/dev/null || true
    fi
    if command -v earlyoom &>/dev/null; then
        cat > /etc/default/earlyoom <<'EOF'
# Managed by VPS-Manager
# Can thiệp khi RAM trống < 5% và swap trống < 10%; ưu tiên hạ php-fpm, tránh database / web server / ssh
EARLYOOM_ARGS="-m 5 -s 10 -r 3600 --prefer '(^|/)php-fpm' --avoid '(^|/)(mariadbd|mysqld|nginx|sshd|valkey-server|redis-server|systemd)$'"
EOF
        systemctl enable earlyoom &>/dev/null
        systemctl restart earlyoom &>/dev/null
        log_info "✓ Tự khởi động lại dịch vụ: đã bật. earlyoom: đang chạy."
    else
        log_info "✓ Tự khởi động lại dịch vụ: đã bật. (Không cài được earlyoom - bỏ qua.)"
    fi
    return 0
}

# ==============================================================================
# 2. Cập nhật bảo mật tự động (chỉ bản vá bảo mật của hệ điều hành, KHÔNG tự reboot)
# ==============================================================================
setup_auto_security_updates() {
    if [[ "${OS_FAMILY:-}" == "debian" ]]; then
        pkg_install unattended-upgrades &>/dev/null || { log_warn "Không cài được unattended-upgrades."; return 1; }
        cat > /etc/apt/apt.conf.d/20auto-upgrades <<'EOF'
// Managed by VPS-Manager
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
EOF
        # Mặc định của gói chỉ lấy nguồn "-security" của distro; không đụng tới kho nginx.org / PHP
        cat > /etc/apt/apt.conf.d/52vps-manager-unattended <<'EOF'
// Managed by VPS-Manager
Unattended-Upgrade::Automatic-Reboot "false";
Unattended-Upgrade::Remove-Unused-Kernel-Packages "true";
EOF
        systemctl enable --now unattended-upgrades &>/dev/null || true
        log_info "✓ Cập nhật bảo mật tự động: đã bật (unattended-upgrades, không tự reboot)."
    elif [[ "${OS_FAMILY:-}" == "rhel" ]]; then
        pkg_install dnf-automatic &>/dev/null || { log_warn "Không cài được dnf-automatic."; return 1; }
        local cfg="/etc/dnf/automatic.conf"
        if [[ -f "$cfg" ]]; then
            sed -i -E 's/^[#[:space:]]*upgrade_type[[:space:]]*=.*/upgrade_type = security/' "$cfg"
            sed -i -E 's/^[#[:space:]]*apply_updates[[:space:]]*=.*/apply_updates = yes/' "$cfg"
        fi
        systemctl enable --now dnf-automatic.timer &>/dev/null || true
        log_info "✓ Cập nhật bảo mật tự động: đã bật (dnf-automatic, chỉ bản vá bảo mật)."
    else
        return 1
    fi
    echo -e "${YELLOW}  Lưu ý: bản vá kernel chỉ có hiệu lực sau khi reboot - công cụ KHÔNG tự reboot VPS.${NC}"
    return 0
}

disable_auto_security_updates() {
    if [[ "${OS_FAMILY:-}" == "debian" ]]; then
        cat > /etc/apt/apt.conf.d/20auto-upgrades <<'EOF'
// Managed by VPS-Manager (đã tắt)
APT::Periodic::Update-Package-Lists "0";
APT::Periodic::Unattended-Upgrade "0";
EOF
    elif [[ "${OS_FAMILY:-}" == "rhel" ]]; then
        systemctl disable --now dnf-automatic.timer &>/dev/null || true
    fi
    log_info "Đã tắt cập nhật bảo mật tự động."
}

auto_security_updates_enabled() {
    if [[ "${OS_FAMILY:-}" == "debian" ]]; then
        grep -qs 'Unattended-Upgrade "1"' /etc/apt/apt.conf.d/20auto-upgrades
    else
        systemctl is-enabled --quiet dnf-automatic.timer 2>/dev/null
    fi
}

# ==============================================================================
# 3. Slow log
# ==============================================================================

# Đặt "key = value" trong 1 file pool PHP-FPM (thay dòng có sẵn kể cả đang bị comment, không thì nối cuối)
_fpm_pool_set() {
    local file=$1 key=$2 value=$3 pat
    pat=$(printf '%s' "$key" | sed 's/[.[\]/\\&/g')
    if grep -qE "^[;[:space:]]*${pat}[[:space:]]*=" "$file"; then
        sed -i -E "0,/^[;[:space:]]*${pat}[[:space:]]*=.*/s||${key} = ${value}|" "$file"
    else
        printf '%s = %s\n' "$key" "$value" >> "$file"
    fi
}

setup_slow_logs() {
    # ── PHP-FPM: ghi stack trace của request chạy quá 5 giây ──
    local pool ver dir changed_vers="" v
    for pool in /etc/php/*/fpm/pool.d/*.conf /etc/php-fpm.d/*.conf; do
        [[ -f "$pool" ]] || continue
        grep -qE '^request_slowlog_timeout[[:space:]]*=[[:space:]]*5s' "$pool" && continue
        cp -p "$pool" "${pool}.bak_vpsm"
        # $pool là biến của PHP-FPM (tên pool) - mỗi site một file log riêng
        _fpm_pool_set "$pool" "slowlog" '/var/log/vps-php-slow-$pool.log'
        _fpm_pool_set "$pool" "request_slowlog_timeout" "5s"
        ver=$(echo "$pool" | grep -oE '[0-9]+\.[0-9]+' | head -1)
        changed_vers+="${ver:-default} "
    done
    for v in $(echo "$changed_vers" | tr ' ' '\n' | sort -u); do
        [[ "$v" == "default" ]] && v=""
        if php_fpm_restart_safe "$v"; then
            dir=$(php_fpm_pool_dir "$v"); rm -f "$dir"/*.conf.bak_vpsm
        else
            # FPM từ chối -> trả lại toàn bộ pool của phiên bản này
            dir=$(php_fpm_pool_dir "$v")
            for pool in "$dir"/*.conf.bak_vpsm; do
                [[ -f "$pool" ]] && mv -f "$pool" "${pool%.bak_vpsm}"
            done
            systemctl restart "$(php_fpm_service "$v")" 2>/dev/null
            log_warn "PHP-FPM ${v:-} không nhận cấu hình slow log - đã hoàn tác."
        fi
    done

    # ── MariaDB: ghi truy vấn chạy quá 2 giây ──
    local conf_dir log_dir owner
    if conf_dir=$(mariadb_conf_dir) && command -v mysql &>/dev/null; then
        log_dir="/var/log/mysql"
        [[ -d "$log_dir" ]] || { [[ -d /var/log/mariadb ]] && log_dir="/var/log/mariadb"; }
        if [[ ! -d "$log_dir" ]]; then
            mkdir -p "$log_dir" && chown mysql:mysql "$log_dir" 2>/dev/null
        fi
        owner=$(stat -c '%U %G' "$log_dir" 2>/dev/null)
        local slow_file="${log_dir}/vpsm-slow.log"
        cat > "${conf_dir}/51-vps-manager-slowlog.cnf" <<EOF
# Managed by VPS-Manager
[mysqld]
slow_query_log      = 1
slow_query_log_file = ${slow_file}
long_query_time     = 2
EOF
        # Bật ngay, không cần restart database
        if mysql -e "SET GLOBAL slow_query_log_file='${slow_file}'; SET GLOBAL long_query_time=2; SET GLOBAL slow_query_log=1;" 2>/dev/null; then
            log_info "✓ Slow query log MariaDB: ${slow_file} (truy vấn > 2 giây)"
        else
            log_warn "Chưa bật được slow query log ngay (sẽ có hiệu lực sau lần restart MariaDB kế tiếp)."
        fi
        cat > /etc/logrotate.d/vps-manager-dbslow <<EOF
${slow_file} {
    weekly
    maxsize 50M
    rotate 4
    missingok
    notifempty
    compress
    delaycompress
    copytruncate
    su ${owner:-mysql mysql}
}
EOF
        # Debian/Ubuntu: file logrotate của gói mariadb đã bao /var/log/mysql/*.log -> khai báo lần nữa
        # là "duplicate log entry". Khi đó gỡ file của mình, để gói mariadb xoay vòng log này.
        if logrotate -d /etc/logrotate.conf 2>&1 | grep -q "vps-manager-dbslow.*duplicate log entry"; then
            rm -f /etc/logrotate.d/vps-manager-dbslow
        fi
    fi
    log_info "✓ Slow log PHP-FPM: /var/log/vps-php-slow-<tên pool>.log (request > 5 giây)"
    return 0
}

# ==============================================================================
# 4. Cảnh báo Telegram + kiểm tra sức khoẻ
# ==============================================================================

# Gửi 1 tin cảnh báo. Không cấu hình Telegram thì chỉ ghi log. Token đi qua stdin của curl (không lộ trong `ps`).
vps_alert() {
    local text="[$(hostname)] $1"
    echo "[$(date '+%F %T')] ALERT: $1" >> "$VPSM_HEALTH_LOG" 2>/dev/null
    [[ -r "$VPSM_ALERT_CONF" ]] || return 0
    local TELEGRAM_BOT_TOKEN="" TELEGRAM_CHAT_ID=""
    # shellcheck disable=SC1090
    . "$VPSM_ALERT_CONF"
    [[ -n "$TELEGRAM_BOT_TOKEN" && -n "$TELEGRAM_CHAT_ID" ]] || return 0
    printf 'url = "https://api.telegram.org/bot%s/sendMessage"\n' "$TELEGRAM_BOT_TOKEN" | \
        curl -fsS --max-time 15 -o /dev/null -K - \
            --data-urlencode "chat_id=${TELEGRAM_CHAT_ID}" \
            --data-urlencode "text=${text}" 2>/dev/null
}

alert_configure_telegram() {
    echo -e "${GREEN}=== Cấu hình cảnh báo qua Telegram ===${NC}"
    echo "1) Trong Telegram, nhắn @BotFather -> /newbot để tạo bot và lấy TOKEN."
    echo "2) Nhắn cho bot vừa tạo một tin bất kỳ (hoặc thêm bot vào nhóm)."
    echo "3) Lấy CHAT ID: nhắn @userinfobot (cá nhân) hoặc xem ID của nhóm (bắt đầu bằng -100...)."
    echo ""
    local token chat
    read -r -s -p "Nhập Bot Token (không hiển thị khi gõ): " token; echo ""
    read -r -p "Nhập Chat ID: " chat
    if ! [[ "$token" =~ ^[0-9]{6,12}:[A-Za-z0-9_-]{30,}$ ]]; then
        echo -e "${RED}Token không đúng định dạng (dạng 123456789:AA...).${NC}"; pause; return 1
    fi
    if ! [[ "$chat" =~ ^-?[0-9]{4,20}$ ]]; then
        echo -e "${RED}Chat ID phải là số (nhóm có dấu - ở đầu).${NC}"; pause; return 1
    fi
    mkdir -p "$VPSM_ETC"
    ( umask 077; printf 'TELEGRAM_BOT_TOKEN=%q\nTELEGRAM_CHAT_ID=%q\n' "$token" "$chat" > "$VPSM_ALERT_CONF" )
    chmod 600 "$VPSM_ALERT_CONF"
    if vps_alert "✅ Kết nối cảnh báo VPS Manager thành công."; then
        log_info "Đã lưu cấu hình và gửi tin thử. Kiểm tra Telegram."
    else
        log_error "Không gửi được tin thử. Kiểm tra token, chat ID và việc bạn đã nhắn cho bot chưa."
    fi
    setup_healthcheck
    pause
}

# Script kiểm tra sức khoẻ chạy độc lập mỗi 5 phút (cron).
setup_healthcheck() {
    cat > "$VPSM_HEALTH_SCRIPT" <<'HEALTH_EOF'
#!/bin/bash
# VPS Manager - kiểm tra sức khoẻ (cron mỗi 5 phút). File này được sinh tự động.
ALERT_CONF="/etc/vps-manager/alert.conf"
STATE_DIR="/var/lib/vps-manager/health"
LOG="/var/log/vps-health.log"
REPEAT_SEC=21600   # cùng 1 sự cố: nhắc lại sau 6 giờ
mkdir -p "$STATE_DIR"

send() {
    echo "[$(date '+%F %T')] $1" >> "$LOG"
    [ -r "$ALERT_CONF" ] || return 0
    TELEGRAM_BOT_TOKEN=""; TELEGRAM_CHAT_ID=""
    . "$ALERT_CONF"
    [ -n "$TELEGRAM_BOT_TOKEN" ] && [ -n "$TELEGRAM_CHAT_ID" ] || return 0
    printf 'url = "https://api.telegram.org/bot%s/sendMessage"\n' "$TELEGRAM_BOT_TOKEN" | \
        curl -fsS --max-time 15 -o /dev/null -K - \
            --data-urlencode "chat_id=${TELEGRAM_CHAT_ID}" \
            --data-urlencode "text=[$(hostname)] $1" 2>/dev/null
}

# problem <khoá> <nội dung>: báo lần đầu, nhắc lại sau REPEAT_SEC
problem() {
    f="$STATE_DIR/$1"; now=$(date +%s); last=0
    [ -f "$f" ] && last=$(cat "$f" 2>/dev/null)
    case "$last" in ''|*[!0-9]*) last=0 ;; esac
    if [ $((now - last)) -ge "$REPEAT_SEC" ]; then
        send "🔴 $2"
        echo "$now" > "$f"
    fi
}
# ok <khoá> <nội dung>: nếu trước đó đang có sự cố thì báo đã phục hồi
ok() {
    f="$STATE_DIR/$1"
    if [ -f "$f" ]; then
        rm -f "$f"
        send "🟢 $2"
    fi
}

# ── Dịch vụ ──
units="nginx"
for u in mariadb mysql; do
    systemctl list-unit-files "$u.service" 2>/dev/null | grep -q "^$u\.service" && { units="$units $u"; break; }
done
for u in valkey-server valkey redis-server redis keydb-server keydb; do
    systemctl is-enabled --quiet "$u" 2>/dev/null && { units="$units $u"; break; }
done
for u in $(systemctl list-unit-files 'php*-fpm.service' 2>/dev/null | awk '/-fpm\.service/ && $2=="enabled"{sub(/\.service$/,"",$1); print $1}'); do
    units="$units $u"
done
for u in $units; do
    if systemctl is-active --quiet "$u"; then
        ok "svc_$u" "Dịch vụ $u đã chạy lại."
    else
        # thử bật lại 1 lần trước khi báo
        systemctl start "$u" >/dev/null 2>&1
        sleep 3
        if systemctl is-active --quiet "$u"; then
            send "🟠 Dịch vụ $u vừa bị dừng và đã được khởi động lại tự động."
        else
            problem "svc_$u" "Dịch vụ $u KHÔNG chạy và không khởi động lại được. Kiểm tra: journalctl -u $u -n 30"
        fi
    fi
done

# ── Ổ đĩa ──
used=$(df -P / | awk 'NR==2{gsub("%","",$5); print $5}')
if [ "${used:-0}" -ge 90 ]; then
    problem "disk_root" "Ổ đĩa / đã dùng ${used}%. Dọn log/backup cũ (menu Quản lý Ổ đĩa)."
else
    ok "disk_root" "Ổ đĩa / đã về mức an toàn (${used}%)."
fi
iused=$(df -Pi / | awk 'NR==2{gsub("%","",$5); print $5}')
if [ "${iused:-0}" -ge 90 ] 2>/dev/null; then
    problem "inode_root" "Ổ đĩa / sắp hết inode (${iused}%) - thường do quá nhiều file cache/session."
else
    ok "inode_root" "Inode của / đã về mức an toàn."
fi

# ── Bộ nhớ: RAM + swap khả dụng dưới 5% ──
avail=$(awk '/^MemAvailable:/{a=$2} /^SwapFree:/{s=$2} /^MemTotal:/{t=$2} /^SwapTotal:/{st=$2} END{ if (t+st>0) printf "%d", (a+s)*100/(t+st); else print 100 }' /proc/meminfo)
if [ "${avail:-100}" -lt 5 ]; then
    problem "mem" "Bộ nhớ khả dụng (RAM + swap) chỉ còn ${avail}%."
else
    ok "mem" "Bộ nhớ đã về mức an toàn (${avail}% khả dụng)."
fi

# ── Việc chỉ kiểm tra 1 lần/ngày (lúc 08 giờ) ──
if [ "$(date +%H)" = "08" ] && [ ! -f "$STATE_DIR/daily_$(date +%F)" ]; then
    rm -f "$STATE_DIR"/daily_* 2>/dev/null
    : > "$STATE_DIR/daily_$(date +%F)"

    # SSL sắp hết hạn (< 10 ngày)
    for cert in /etc/letsencrypt/live/*/cert.pem; do
        [ -f "$cert" ] || continue
        end=$(openssl x509 -enddate -noout -in "$cert" 2>/dev/null | cut -d= -f2)
        [ -n "$end" ] || continue
        days=$(( ( $(date -d "$end" +%s) - $(date +%s) ) / 86400 ))
        if [ "$days" -lt 10 ]; then
            send "🟠 SSL của $(basename "$(dirname "$cert")") còn ${days} ngày là hết hạn - gia hạn tự động có thể đang lỗi."
        fi
    done

    # Backup tự động có lỗi trong 24 giờ qua
    BLOG="/var/log/vps-auto-backup.log"
    if [ -f "$BLOG" ]; then
        y=$(date -d yesterday +%F); t=$(date +%F)
        n=$(grep -E "^\[($y|$t) " "$BLOG" 2>/dev/null | grep -c "ERROR")
        if [ "${n:-0}" -gt 0 ]; then
            send "🔴 Backup tự động có ${n} lỗi trong 24 giờ qua. Xem: $BLOG"
        fi
    fi

    # Kernel mới đã cài nhưng chưa reboot
    if [ -f /var/run/reboot-required ]; then
        send "🟠 Đã cài bản vá cần khởi động lại VPS để có hiệu lực (reboot khi thuận tiện)."
    fi
fi
exit 0
HEALTH_EOF
    chmod 700 "$VPSM_HEALTH_SCRIPT"
    cat > /etc/cron.d/vps-manager-health <<EOF
# Managed by VPS-Manager: kiểm tra sức khoẻ mỗi 5 phút
*/5 * * * * root $VPSM_HEALTH_SCRIPT >/dev/null 2>&1
EOF
    chmod 644 /etc/cron.d/vps-manager-health
    if [[ -r "$VPSM_ALERT_CONF" ]]; then
        log_info "✓ Kiểm tra sức khoẻ mỗi 5 phút: đã bật, cảnh báo gửi qua Telegram."
    else
        log_info "✓ Kiểm tra sức khoẻ mỗi 5 phút: đã bật (chưa cấu hình Telegram - chỉ ghi vào $VPSM_HEALTH_LOG)."
    fi
}

# ==============================================================================
# 5 + 6. Nginx toàn cục: giới hạn wp-login, HTTP/2, TLS session cache, khoá làm mới cache
# ==============================================================================

_nginx_supports_http2_directive() {
    local v
    v=$(nginx -v 2>&1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
    [[ -n "$v" ]] && [[ "$(printf '%s\n1.25.1\n' "$v" | sort -V | head -1)" == "1.25.1" ]]
}

setup_nginx_globals() {
    command -v nginx &>/dev/null || return 0
    [[ -d /etc/nginx/conf.d ]] || return 0
    local f_limit="/etc/nginx/conf.d/vps-manager-wplogin.conf"
    local f_tls="/etc/nginx/conf.d/vps-manager-tls.conf"
    local f_refresh="/etc/nginx/conf.d/vps-manager-cache-refresh.conf"
    local f created=()

    # ── Giới hạn wp-login.php / xmlrpc.php: 20 request/phút mỗi IP ──
    # Khoá rỗng = không giới hạn, nên chỉ 2 URL này bị đếm; mọi request khác không ảnh hưởng.
    # Đặt ở cấp http nên áp cho mọi vhost mà không phải sửa từng file.
    if [[ ! -f "$f_limit" ]]; then
        cat > "$f_limit" <<'EOF'
# Managed by VPS-Manager: chống dò mật khẩu WordPress
map $request_uri $vpsm_wplogin_key {
    default               "";
    ~*^/wp-login\.php     $binary_remote_addr;
    ~*^/xmlrpc\.php       $binary_remote_addr;
}
limit_req_zone $vpsm_wplogin_key zone=vpsm_wplogin:10m rate=20r/m;
limit_req zone=vpsm_wplogin burst=10 nodelay;
limit_req_status 429;
EOF
        created+=("$f_limit")
    fi

    # ── TLS session cache + HTTP/2 mặc định ──
    # (Không bật OCSP stapling: Let's Encrypt đã ngừng dịch vụ OCSP nên stapling chỉ sinh cảnh báo.)
    if [[ ! -f "$f_tls" ]]; then
        {
            echo "# Managed by VPS-Manager"
            echo "ssl_session_cache   shared:VPSM_SSL:10m;"
            echo "ssl_session_timeout 1d;"
            echo "ssl_session_tickets off;"
            if _nginx_supports_http2_directive; then
                echo "# HTTP/2 cho mọi vhost HTTPS (nginx >= 1.25.1)"
                echo "http2 on;"
            fi
        } > "$f_tls"
        created+=("$f_tls")
    fi

    # ── Khoá bí mật cho việc làm mới cache khi sửa bài ──
    # Request mang header X-VPSM-Refresh đúng khoá sẽ bỏ qua cache và GHI ĐÈ bản cache của URL đó.
    # Khoá dài ĐÚNG 32 ký tự hex (128 bit): khoá dài hơn vượt map_hash_bucket_size mặc định (64) của nginx
    # và làm nginx -t lỗi "could not build map_hash".
    local key=""
    [[ -s "$VPSM_REFRESH_KEY_FILE" ]] && key=$(tr -d '[:space:]' < "$VPSM_REFRESH_KEY_FILE")
    if ! [[ "$key" =~ ^[0-9a-f]{32}$ ]]; then
        mkdir -p "$VPSM_ETC"
        ( umask 077; openssl rand -hex 16 > "$VPSM_REFRESH_KEY_FILE" )
        key=$(tr -d '[:space:]' < "$VPSM_REFRESH_KEY_FILE")
    fi
    if [[ "$key" =~ ^[0-9a-f]{32}$ ]] && ! grep -qs "\"$key\"" "$f_refresh"; then
        [[ -f "$f_refresh" ]] || created+=("$f_refresh")
        cat > "$f_refresh" <<EOF
# Managed by VPS-Manager: làm mới FastCGI cache theo yêu cầu (xem mu-plugin vps-cache-refresh.php)
map \$http_x_vpsm_refresh \$vpsm_cache_refresh {
    default 0;
    "$key" 1;
}
EOF
        chmod 640 "$f_refresh"
        chown root:"$(nginx_worker_user)" "$f_refresh" 2>/dev/null
    fi

    selinux_restore /etc/nginx/conf.d
    local out
    if out=$(nginx -t 2>&1); then
        systemctl reload nginx 2>/dev/null
        return 0
    fi
    # nginx từ chối -> gỡ từng file vừa tạo cho tới khi config hợp lệ trở lại
    log_warn "Nginx từ chối một phần cấu hình toàn cục mới:"
    echo "$out" | tail -4
    for f in "${created[@]}"; do
        if echo "$out" | grep -qF "$f"; then
            rm -f "$f"
            log_warn "Đã gỡ $(basename "$f")."
        fi
    done
    if ! nginx -t &>/dev/null; then
        for f in "${created[@]}"; do rm -f "$f"; done
    fi
    nginx -t &>/dev/null && systemctl reload nginx 2>/dev/null
    return 1
}

# ==============================================================================
# IP thật của khách khi site đứng sau Cloudflare
# Không có phần này, nginx chỉ thấy IP của Cloudflare: giới hạn wp-login, Fail2ban, WAF và log
# đều tính theo IP Cloudflare (mọi khách dùng chung một IP) thay vì IP của từng người.
# Header CF-Connecting-IP chỉ được tin khi request đến TỪ dải IP của Cloudflare, nên an toàn
# cả với site không dùng Cloudflare.
# ==============================================================================
setup_cloudflare_real_ip() {
    command -v nginx &>/dev/null || return 0
    [[ -d /etc/nginx/conf.d ]] || return 0
    local f="/etc/nginx/conf.d/vps-manager-cloudflare-realip.conf"
    local v4 v6 ip had_old=0

    # Lấy danh sách hiện hành từ Cloudflare; không lấy được thì dùng danh sách đi kèm
    v4=$(curl -fsS --max-time 10 https://www.cloudflare.com/ips-v4 2>/dev/null)
    v6=$(curl -fsS --max-time 10 https://www.cloudflare.com/ips-v6 2>/dev/null)
    if [[ $(echo "$v4" | grep -cE '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/[0-9]+$') -lt 5 ]]; then
        v4="173.245.48.0/20 103.21.244.0/22 103.22.200.0/22 103.31.4.0/22 141.101.64.0/18 108.162.192.0/18 190.93.240.0/20 188.114.96.0/20 197.234.240.0/22 198.41.128.0/17 162.158.0.0/15 104.16.0.0/13 104.24.0.0/14 172.64.0.0/13 131.0.72.0/22"
    fi
    if [[ $(echo "$v6" | grep -cE '^[0-9a-fA-F:]+/[0-9]+$') -lt 3 ]]; then
        v6="2400:cb00::/32 2606:4700::/32 2803:f800::/32 2405:b500::/32 2405:8100::/32 2a06:98c0::/29 2c0f:f248::/32"
    fi

    [[ -f "$f" ]] && { cp -p "$f" "${f}.bak_$$"; had_old=1; }
    {
        echo "# Managed by VPS-Manager: khôi phục IP thật của khách đi qua Cloudflare"
        for ip in $v4 $v6; do
            # chỉ nhận đúng định dạng CIDR - không ghi bất cứ thứ gì khác vào cấu hình nginx
            if [[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/[0-9]+$ || "$ip" =~ ^[0-9a-fA-F:]+/[0-9]+$ ]]; then
                echo "set_real_ip_from $ip;"
            fi
        done
        echo "real_ip_header CF-Connecting-IP;"
    } > "$f"

    if nginx -t &>/dev/null; then
        systemctl reload nginx 2>/dev/null
        rm -f "${f}.bak_$$"
        return 0
    fi
    if [[ "$had_old" -eq 1 ]]; then mv -f "${f}.bak_$$" "$f"; else rm -f "$f"; fi
    log_warn "Không áp được cấu hình IP thật qua Cloudflare (nginx -t lỗi) - đã hoàn tác."
    return 1
}

# ==============================================================================
# 6. Làm mới cache khi nội dung WordPress thay đổi
# ==============================================================================

# Thêm biến làm mới vào dòng fastcgi_cache_bypass của các vhost đang có (rollback toàn bộ nếu nginx -t lỗi)
cache_refresh_enable_vhosts() {
    grep -qs 'vpsm_cache_refresh' /etc/nginx/conf.d/vps-manager-cache-refresh.conf || return 1
    local conf bak
    local -a confs=() baks=()
    for conf in /etc/nginx/sites-available/*; do
        [[ -f "$conf" ]] || continue
        [[ "$conf" == *.bak* ]] && continue
        grep -q 'fastcgi_cache_bypass' "$conf" || continue
        grep -q 'vpsm_cache_refresh' "$conf" && continue
        bak="${conf}.bak_refresh_$$"
        cp -p "$conf" "$bak"
        sed -i -E 's/^([[:space:]]*fastcgi_cache_bypass[[:space:]]+[^;]*);/\1 $vpsm_cache_refresh;/' "$conf"
        confs+=("$conf"); baks+=("$bak")
    done
    [[ ${#confs[@]} -eq 0 ]] && return 0
    local i
    if nginx -t &>/dev/null; then
        systemctl reload nginx
        for bak in "${baks[@]}"; do rm -f "$bak"; done
        log_info "✓ Đã bật làm mới cache cho ${#confs[@]} vhost."
        return 0
    fi
    for i in "${!confs[@]}"; do mv -f "${baks[$i]}" "${confs[$i]}"; done
    log_warn "Không bật được làm mới cache trên các vhost (nginx -t lỗi) - đã hoàn tác."
    return 1
}

# Cài mu-plugin cho 1 site WordPress
cache_refresh_install_plugin() {
    local domain=$1
    local root="/var/www/$domain/public_html"
    [[ -d "$root/wp-content" ]] || return 1
    [[ -s "$VPSM_REFRESH_KEY_FILE" ]] || return 1
    local key owner dir file
    key=$(tr -d '[:space:]' < "$VPSM_REFRESH_KEY_FILE")
    [[ "$key" =~ ^[0-9a-f]{32}$ ]] || return 1
    owner=$(site_owner "$root")
    dir="$root/wp-content/mu-plugins"
    file="$dir/vps-cache-refresh.php"
    mkdir -p "$dir"
    cat > "$file" <<PHP_EOF
<?php
/**
 * Plugin Name: VPS Manager - Cache Refresh
 * Description: Làm mới Nginx FastCGI cache ngay khi bài viết, trang hoặc bình luận thay đổi.
 * File này do VPS Manager sinh tự động.
 */
if ( ! defined( 'ABSPATH' ) ) { exit; }
if ( ! defined( 'VPSM_CACHE_REFRESH_KEY' ) ) { define( 'VPSM_CACHE_REFRESH_KEY', '${key}' ); }
PHP_EOF
    cat >> "$file" <<'PHP_EOF'

final class VPSM_Cache_Refresh {
    private static $urls = array();

    public static function init() {
        add_action( 'transition_post_status', array( __CLASS__, 'on_post_status' ), 10, 3 );
        add_action( 'deleted_post', array( __CLASS__, 'on_home_change' ) );
        add_action( 'transition_comment_status', array( __CLASS__, 'on_comment_status' ), 10, 3 );
        add_action( 'comment_post', array( __CLASS__, 'on_comment_post' ), 10, 2 );
        add_action( 'switch_theme', array( __CLASS__, 'on_home_change' ) );
        add_action( 'wp_update_nav_menu', array( __CLASS__, 'on_home_change' ) );
        add_action( 'shutdown', array( __CLASS__, 'flush' ) );
    }

    public static function on_post_status( $new, $old, $post ) {
        if ( 'publish' !== $new && 'publish' !== $old ) { return; }
        if ( wp_is_post_revision( $post ) || wp_is_post_autosave( $post ) ) { return; }
        $type = get_post_type_object( $post->post_type );
        if ( ! $type || ! $type->public ) { return; }
        self::queue_post( $post );
    }

    public static function on_comment_status( $new, $old, $comment ) {
        if ( 'approved' === $new || 'approved' === $old ) {
            self::add( get_permalink( $comment->comment_post_ID ) );
        }
    }

    public static function on_comment_post( $comment_id, $approved ) {
        if ( 1 === (int) $approved ) {
            $comment = get_comment( $comment_id );
            if ( $comment ) { self::add( get_permalink( $comment->comment_post_ID ) ); }
        }
    }

    public static function on_home_change() {
        self::add( home_url( '/' ) );
    }

    private static function queue_post( $post ) {
        self::add( get_permalink( $post ) );
        self::add( home_url( '/' ) );
        self::add( get_bloginfo( 'rss2_url' ) );
        $archive = get_post_type_archive_link( $post->post_type );
        if ( $archive ) { self::add( $archive ); }
        $page_for_posts = (int) get_option( 'page_for_posts' );
        if ( $page_for_posts ) { self::add( get_permalink( $page_for_posts ) ); }
        self::add( get_author_posts_url( $post->post_author ) );
        foreach ( get_object_taxonomies( $post->post_type ) as $tax ) {
            $terms = get_the_terms( $post, $tax );
            if ( ! is_array( $terms ) ) { continue; }
            foreach ( array_slice( $terms, 0, 10 ) as $term ) {
                $link = get_term_link( $term );
                if ( ! is_wp_error( $link ) ) { self::add( $link ); }
            }
        }
    }

    private static function add( $url ) {
        if ( is_string( $url ) && '' !== $url && count( self::$urls ) < 40 ) {
            self::$urls[ $url ] = true;
        }
    }

    /** Gửi các request nền mang khoá làm mới: nginx bỏ qua bản cache cũ và lưu bản mới. */
    public static function flush() {
        if ( empty( self::$urls ) ) { return; }
        foreach ( array_keys( self::$urls ) as $url ) {
            wp_remote_get( $url, array(
                'blocking'    => false,
                'timeout'     => 3,
                'redirection' => 0,
                'sslverify'   => false,
                'cookies'     => array(),
                'user-agent'  => 'vps-manager-cache-refresh',
                'headers'     => array( 'X-VPSM-Refresh' => VPSM_CACHE_REFRESH_KEY ),
            ) );
        }
        self::$urls = array();
    }
}
VPSM_Cache_Refresh::init();
PHP_EOF
    chown "$owner":"$owner" "$dir" "$file" 2>/dev/null
    chmod 640 "$file"
    return 0
}

# Bật làm mới cache cho mọi site WordPress
cache_refresh_enable_all() {
    setup_nginx_globals
    if ! cache_refresh_enable_vhosts; then
        log_error "Chưa bật được làm mới cache ở tầng Nginx."
        return 1
    fi
    local d domain n=0
    for d in /var/www/*/; do
        domain=$(basename "$d")
        [[ -f "$d/public_html/wp-config.php" || -f "$d/wp-config.php" ]] || continue
        cache_refresh_install_plugin "$domain" && n=$((n + 1))
    done
    log_info "✓ Làm mới cache khi sửa bài: đã cài cho ${n} site WordPress."
}

# ==============================================================================
# OPcache: server đã tối ưu bằng bản cũ đang kiểm tra file thay đổi mỗi 2 giây -> nâng lên 60 giây
# ==============================================================================
opcache_relax_revalidate() {
    local ini ver
    for ini in /etc/php/*/fpm/conf.d/99-vps-manager-opcache.ini /etc/php.d/99-vps-manager-opcache.ini; do
        [[ -f "$ini" ]] || continue
        grep -qE '^opcache\.revalidate_freq=2$' "$ini" || continue
        cp -p "$ini" "${ini}.bak_vpsm"
        sed -i -E 's/^opcache\.revalidate_freq=2$/opcache.revalidate_freq=60/' "$ini"
        ver=$(echo "$ini" | grep -oE '[0-9]+\.[0-9]+' | head -1)
        if php_fpm_restart_safe "$ver"; then
            rm -f "${ini}.bak_vpsm"
            log_info "✓ OPcache PHP ${ver:-mặc định}: revalidate_freq 2 → 60 giây."
        else
            mv -f "${ini}.bak_vpsm" "$ini"
            systemctl restart "$(php_fpm_service "$ver")" 2>/dev/null
        fi
    done
    return 0
}

# Site đã bật Rate Limit (limit_req zone=one trong server block) che mất giới hạn wp-login cấp http
# -> khai báo lại giới hạn wp-login ngay trong các vhost đó (rollback nếu nginx -t lỗi)
_wplogin_limit_fix_vhosts() {
    grep -qs 'zone=vpsm_wplogin' /etc/nginx/conf.d/vps-manager-wplogin.conf || return 0
    local conf bak i
    local -a confs=() baks=()
    for conf in /etc/nginx/sites-available/*; do
        [[ -f "$conf" && "$conf" != *.bak* ]] || continue
        grep -qE '^[[:space:]]*limit_req[[:space:]]+zone=' "$conf" || continue
        grep -q 'zone=vpsm_wplogin' "$conf" && continue
        bak="${conf}.bak_wplogin_$$"
        cp -p "$conf" "$bak"
        sed -i -E '0,/^([[:space:]]*)limit_req[[:space:]]+zone=[^;]*;/s//&\n\1limit_req zone=vpsm_wplogin burst=10 nodelay;/' "$conf"
        confs+=("$conf"); baks+=("$bak")
    done
    [[ ${#confs[@]} -eq 0 ]] && return 0
    if nginx -t &>/dev/null; then
        systemctl reload nginx
        for bak in "${baks[@]}"; do rm -f "$bak"; done
        return 0
    fi
    for i in "${!confs[@]}"; do mv -f "${baks[$i]}" "${confs[$i]}"; done
    return 1
}

# ==============================================================================
# Điểm vào: áp toàn bộ gói ổn định & tốc độ (không hỏi gì, an toàn khi chạy lại)
# ==============================================================================
run_reliability_setup() {
    echo -e "${CYAN}[Ổn định & Tốc độ] Đang áp dụng...${NC}"
    setup_service_resilience
    setup_auto_security_updates
    setup_slow_logs
    setup_healthcheck
    opcache_relax_revalidate
    if command -v nginx &>/dev/null; then
        setup_nginx_globals
        setup_cloudflare_real_ip
        _wplogin_limit_fix_vhosts
        fastcgi_cache_autosize
        cache_refresh_enable_all
    fi
    mkdir -p "$VPSM_ETC"
    cat "$(dirname "${BASH_SOURCE[0]}")/../VERSION" 2>/dev/null | tr -d '[:space:]' > "$VPSM_ETC/reliability_version"
    echo -e "${GREEN}[Ổn định & Tốc độ] ✓ Hoàn tất.${NC}"
}

# true nếu server đã có web stack nhưng chưa áp gói của phiên bản đang cài
reliability_setup_pending() {
    command -v nginx &>/dev/null || return 1
    local cur applied=""
    cur=$(tr -d '[:space:]' < "$(dirname "${BASH_SOURCE[0]}")/../VERSION" 2>/dev/null)
    [[ -f "$VPSM_ETC/reliability_version" ]] && applied=$(tr -d '[:space:]' < "$VPSM_ETC/reliability_version")
    [[ -n "$cur" && "$cur" != "$applied" ]]
}

# ==============================================================================
# Menu
# ==============================================================================
reliability_menu() {
    while true; do
        clear
        echo -e "${BLUE}=================================================${NC}"
        echo -e "${GREEN}     🛟 Ổn định & Cảnh báo${NC}"
        echo -e "${BLUE}=================================================${NC}"
        if auto_security_updates_enabled; then
            echo -e "  Cập nhật bảo mật tự động : ${GREEN}BẬT${NC}"
        else
            echo -e "  Cập nhật bảo mật tự động : ${YELLOW}TẮT${NC}"
        fi
        if [[ -r "$VPSM_ALERT_CONF" ]]; then
            echo -e "  Cảnh báo Telegram        : ${GREEN}ĐÃ CẤU HÌNH${NC}"
        else
            echo -e "  Cảnh báo Telegram        : ${YELLOW}CHƯA CẤU HÌNH${NC}"
        fi
        if [[ -f /etc/cron.d/vps-manager-health ]]; then
            echo -e "  Kiểm tra sức khoẻ 5 phút : ${GREEN}BẬT${NC}"
        else
            echo -e "  Kiểm tra sức khoẻ 5 phút : ${YELLOW}TẮT${NC}"
        fi
        echo -e "${BLUE}=================================================${NC}"
        echo -e "1. Áp dụng toàn bộ gói Ổn định & Tốc độ (chạy lại được nhiều lần)"
        echo -e "2. Cấu hình cảnh báo qua Telegram"
        echo -e "3. Gửi tin cảnh báo thử"
        echo -e "4. Xem nhật ký sức khoẻ (50 dòng cuối)"
        echo -e "5. Xem Slow log PHP (request > 5 giây)"
        echo -e "6. Xem Slow query MariaDB (truy vấn > 2 giây)"
        echo -e "7. Bật/Tắt cập nhật bảo mật tự động"
        echo -e "0. Quay lại Menu chính"
        echo -e "${BLUE}=================================================${NC}"
        read -r -p "Chọn [0-7]: " choice
        case $choice in
            1) run_reliability_setup; pause ;;
            2) alert_configure_telegram ;;
            3)
                if [[ -r "$VPSM_ALERT_CONF" ]]; then
                    vps_alert "🔔 Tin thử từ VPS Manager." && log_info "Đã gửi." || log_error "Gửi thất bại."
                else
                    echo -e "${YELLOW}Chưa cấu hình Telegram (mục 2).${NC}"
                fi
                pause ;;
            4) tail -n 50 "$VPSM_HEALTH_LOG" 2>/dev/null || echo "Chưa có nhật ký."; pause ;;
            5)
                local f found=0
                for f in /var/log/vps-php-slow-*.log; do
                    [[ -s "$f" ]] || continue
                    found=1
                    echo -e "${CYAN}── $f ──${NC}"; tail -n 40 "$f"
                done
                [[ "$found" -eq 0 ]] && echo "Chưa có request nào chậm quá 5 giây."
                pause ;;
            6)
                local sf
                sf=$(ls /var/log/mysql/vpsm-slow.log /var/log/mariadb/vpsm-slow.log 2>/dev/null | head -1)
                if [[ -s "$sf" ]]; then tail -n 60 "$sf"; else echo "Chưa có truy vấn nào chậm quá 2 giây."; fi
                pause ;;
            7)
                if auto_security_updates_enabled; then disable_auto_security_updates; else setup_auto_security_updates; fi
                pause ;;
            0) return ;;
            *) echo -e "${RED}Lựa chọn không hợp lệ!${NC}"; pause ;;
        esac
    done
}

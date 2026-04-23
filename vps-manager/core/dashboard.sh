#!/bin/bash
# core/dashboard.sh - Real-time Server Dashboard
# Cập nhật mỗi giây, không block UI

# ────────────────────────────────────────────────────────────
# COLOR PALETTE
# ────────────────────────────────────────────────────────────
C_RESET='\033[0m'
C_BOLD='\033[1m'
C_CYAN='\033[0;36m'
C_BCYAN='\033[1;36m'
C_GREEN='\033[0;32m'
C_BGREEN='\033[1;32m'
C_YELLOW='\033[1;33m'
C_RED='\033[0;31m'
C_BRED='\033[1;31m'
C_WHITE='\033[1;37m'
C_DIM='\033[2m'

# ────────────────────────────────────────────────────────────
# HELPER: Vẽ thanh tiến trình màu động
# draw_bar <percent> <width>
# ────────────────────────────────────────────────────────────
draw_bar() {
    local percent=$1
    local width=${2:-20}
    local fill=$(( (percent * width) / 100 ))
    [[ $fill -lt 0 ]] && fill=0
    [[ $fill -gt $width ]] && fill=$width
    local empty=$(( width - fill ))

    local color=$C_BGREEN
    [[ $percent -ge 60 ]] && color=$C_YELLOW
    [[ $percent -ge 85 ]] && color=$C_BRED

    local bar=""
    [[ $fill -gt 0 ]] && bar+="${color}$(printf '█%.0s' $(seq 1 $fill))${C_RESET}"
    [[ $empty -gt 0 ]] && bar+="${C_DIM}$(printf '░%.0s' $(seq 1 $empty))${C_RESET}"

    echo -ne "${C_CYAN}[${C_RESET}${bar}${C_CYAN}]${C_RESET}"
}

# ────────────────────────────────────────────────────────────
# HELPER: In dòng trong khung (tự căn lề phải để lấp đầy 80 cột)
# print_row "text có màu"
# ────────────────────────────────────────────────────────────
BORDER_WIDTH=80

print_top()    { echo -e "${C_CYAN}╔$(printf '═%.0s' $(seq 1 $((BORDER_WIDTH-2))))╗${C_RESET}"; }
print_mid()    { echo -e "${C_CYAN}╠$(printf '═%.0s' $(seq 1 $((BORDER_WIDTH-2))))╣${C_RESET}"; }
print_bot()    { echo -e "${C_CYAN}╚$(printf '═%.0s' $(seq 1 $((BORDER_WIDTH-2))))╝${C_RESET}"; }
print_sep()    { echo -e "${C_CYAN}├$(printf '─%.0s' $(seq 1 $((BORDER_WIDTH-2))))┤${C_RESET}"; }

print_row() {
    local text="$1"
    # Strip ANSI để tính độ dài thật
    local plain
    plain=$(echo -e "$text" | sed 's/\x1B\[[0-9;]*[mK]//g' | tr -d '\r\n')
    local len=${#plain}
    local pad=$(( BORDER_WIDTH - 2 - 2 - len ))    # 2 border + 2 space padding
    [[ $pad -lt 0 ]] && pad=0
    echo -e "${C_CYAN}║${C_RESET}  ${text}$(printf '%*s' "$pad" "")${C_CYAN}║${C_RESET}"
}

print_2col() {
    local left="$1"
    local right="$2"
    local col_width=$(( (BORDER_WIDTH - 2) / 2 - 2 ))

    local plain_l plain_r
    plain_l=$(echo -e "$left" | sed 's/\x1B\[[0-9;]*[mK]//g' | tr -d '\r\n')
    plain_r=$(echo -e "$right" | sed 's/\x1B\[[0-9;]*[mK]//g' | tr -d '\r\n')

    local pad_l=$(( col_width - ${#plain_l} ))
    local pad_r=$(( col_width - ${#plain_r} ))
    [[ $pad_l -lt 0 ]] && pad_l=0
    [[ $pad_r -lt 0 ]] && pad_r=0

    echo -e "${C_CYAN}║${C_RESET}  ${left}$(printf '%*s' "$pad_l" "")  ${right}$(printf '%*s' "$pad_r" "")${C_CYAN}║${C_RESET}"
}

center_row() {
    local text="$1"
    local plain
    plain=$(echo -e "$text" | sed 's/\x1B\[[0-9;]*[mK]//g' | tr -d '\r\n')
    local len=${#plain}
    local total=$(( BORDER_WIDTH - 2 ))
    local pad_l=$(( (total - len) / 2 ))
    local pad_r=$(( total - len - pad_l ))
    [[ $pad_l -lt 0 ]] && pad_l=0
    [[ $pad_r -lt 0 ]] && pad_r=0
    echo -e "${C_CYAN}║${C_RESET}$(printf '%*s' "$pad_l" "")${text}$(printf '%*s' "$pad_r" "")${C_CYAN}║${C_RESET}"
}

# ────────────────────────────────────────────────────────────
# STATUS HELPERs
# ────────────────────────────────────────────────────────────
_svc_status() {
    # Trả về chuỗi màu ON/OFF cho 1 service
    local svc="$1"
    if systemctl is-active --quiet "$svc" 2>/dev/null; then
        echo -e "${C_BGREEN}● RUNNING${C_RESET}"
    else
        echo -e "${C_BRED}● STOPPED${C_RESET}"
    fi
}

_webserver_name() {
    if systemctl is-active --quiet lshttpd 2>/dev/null || [[ -f /usr/local/lsws/bin/lswsctrl ]]; then
        echo "OpenLiteSpeed"
    else
        echo "Nginx"
    fi
}

_webserver_svc() {
    if systemctl is-active --quiet lshttpd 2>/dev/null; then
        echo "lshttpd"
    else
        echo "nginx"
    fi
}

_cache_svc() {
    for svc in valkey keydb redis; do
        if systemctl is-active --quiet "$svc" 2>/dev/null || systemctl is-enabled --quiet "$svc" 2>/dev/null; then
            echo "$svc"
            return
        fi
    done
    echo ""
}

# ────────────────────────────────────────────────────────────
# DATA COLLECTORS
# ────────────────────────────────────────────────────────────
# Đọc CPU % (so sánh với lần trước)
_prev_cpu_total=0
_prev_cpu_idle=0
_init_cpu() {
    read -r _cpu a b c idle rest < /proc/stat
    _prev_cpu_total=$(( a + b + c + idle + rest ))
    _prev_cpu_idle=$idle
}

_get_cpu_percent() {
    read -r _cpu a b c idle rest < /proc/stat
    local total=$(( a + b + c + idle + rest ))
    local diff_total=$(( total - _prev_cpu_total ))
    local diff_idle=$(( idle - _prev_cpu_idle ))
    _prev_cpu_total=$total
    _prev_cpu_idle=$idle
    if [[ $diff_total -eq 0 ]]; then echo 0; return; fi
    echo $(( 100 * (diff_total - diff_idle) / diff_total ))
}

_get_ram() {
    local total avail
    while IFS=: read -r key val _; do
        key="${key// /}"
        val="${val// /}"
        case "$key" in
            MemTotal)    total=${val%kB} ;;
            MemAvailable) avail=${val%kB} ;;
        esac
    done < /proc/meminfo
    local used=$(( (total - avail) / 1024 ))
    local total_mb=$(( total / 1024 ))
    local pct=$(( used * 100 / total_mb ))
    echo "$used $total_mb $pct"
}

_get_disk() {
    read -r used total pct <<< "$(df -BG / | awk 'NR==2 {gsub(/G|%/,""); print $3, $2, $5}')"
    echo "${used:-0} ${total:-0} ${pct:-0}"
}

_get_load() {
    read -r l1 l2 l3 _ < /proc/loadavg
    echo "$l1 $l2 $l3"
}

_get_uptime() {
    read -r up _ < /proc/uptime
    local s=${up%%.*}
    local d=$(( s / 86400 ))
    local h=$(( (s % 86400) / 3600 ))
    local m=$(( (s % 3600) / 60 ))
    echo "${d}d ${h}h ${m}m"
}

# Network: rx/tx bytes từ /proc/net/dev
_prev_rx=0
_prev_tx=0
_init_net() {
    _prev_rx=0; _prev_tx=0
    while read -r iface rx _ _ _ _ _ _ _ tx _; do
        [[ "$iface" == *"Inter"* || "$iface" == *"face"* || "$iface" == "lo:"* ]] && continue
        _prev_rx=$(( _prev_rx + rx ))
        _prev_tx=$(( _prev_tx + tx ))
    done < /proc/net/dev
}

_get_net_speed() {
    local rx_now=0 tx_now=0
    while read -r iface rx _ _ _ _ _ _ _ tx _; do
        [[ "$iface" == *"Inter"* || "$iface" == *"face"* || "$iface" == "lo:"* ]] && continue
        rx_now=$(( rx_now + rx ))
        tx_now=$(( tx_now + tx ))
    done < /proc/net/dev
    local rx_kb=$(( (rx_now - _prev_rx) / 1024 ))
    local tx_kb=$(( (tx_now - _prev_tx) / 1024 ))
    [[ $rx_kb -lt 0 ]] && rx_kb=0
    [[ $tx_kb -lt 0 ]] && tx_kb=0
    _prev_rx=$rx_now
    _prev_tx=$tx_now
    echo "$rx_kb $tx_kb"
}

_format_net() {
    local kb=$1
    if [[ $kb -ge 1024 ]]; then
        echo "$(( kb / 1024 )) MB/s"
    else
        echo "${kb} KB/s"
    fi
}

# ────────────────────────────────────────────────────────────
# VERSION & UPDATE CHECK
# ────────────────────────────────────────────────────────────
_CURRENT_VER="$(cat "$(dirname "${BASH_SOURCE[0]}")/../VERSION" 2>/dev/null | tr -d '[:space:]')"
_SHOW_UPDATE=0
_NEW_VER=""
_check_update_bg() {
    # Chạy background, ghi vào /tmp để không block
    (
        local remote
        remote=$(curl -sf --connect-timeout 3 --max-time 5 \
            "https://raw.githubusercontent.com/leluongnghia/vps/main/vps-manager/VERSION" 2>/dev/null | tr -d '[:space:]')
        if [[ -n "$remote" && "$remote" != "$_CURRENT_VER" ]]; then
            echo "$remote" > /tmp/vps-manager-new-version
        else
            rm -f /tmp/vps-manager-new-version
        fi
    ) &
    disown
}

# ────────────────────────────────────────────────────────────
# RENDER DASHBOARD (1 lần render, dùng buffer để không nhấp nháy)
# ────────────────────────────────────────────────────────────
_render_dashboard() {
    local cpu_pct=$1 rx_kb=$2 tx_kb=$3
    local web_svc web_name cache_svc cache_name

    # Đọc dữ liệu
    read -r ram_used ram_total ram_pct <<< "$(_get_ram)"
    read -r disk_used disk_total disk_pct <<< "$(_get_disk)"
    read -r load1 load5 load15 <<< "$(_get_load)"
    local uptime_str
    uptime_str="$(_get_uptime)"

    web_svc="$(_webserver_svc)"
    web_name="$(_webserver_name)"
    cache_svc="$(_cache_svc)"
    [[ -n "$cache_svc" ]] && cache_name="$cache_svc" || cache_name="N/A"

    # Service status (cached từ vòng ngoài mỗi 5s)
    local web_status="${_cached_web_status:-${C_YELLOW}checking...${C_RESET}}"
    local db_status="${_cached_db_status:-${C_YELLOW}checking...${C_RESET}}"
    local cache_status="${_cached_cache_status:-${C_DIM}N/A${C_RESET}}"

    # Network format
    local rx_str tx_str
    rx_str="$(_format_net "$rx_kb")"
    tx_str="$(_format_net "$tx_kb")"

    # Alert nếu network cao
    [[ $rx_kb -gt 10240 ]] && rx_str="${C_BRED}${rx_str}${C_RESET}"
    [[ $tx_kb -gt 10240 ]] && tx_str="${C_BRED}${tx_str}${C_RESET}"

    # Version
    local ver_str="${C_WHITE}v${_CURRENT_VER}${C_RESET}"
    if [[ -f /tmp/vps-manager-new-version ]]; then
        local new_ver
        new_ver=$(cat /tmp/vps-manager-new-version)
        ver_str="${C_WHITE}v${_CURRENT_VER}${C_RESET} ${C_YELLOW}→ v${new_ver} có sẵn!${C_RESET}"
        _SHOW_UPDATE=1
        _NEW_VER="$new_ver"
    fi

    # ── Begin render ──
    local buf=""
    buf+="$(print_top)\n"
    buf+="$(center_row "${C_BCYAN}${C_BOLD}  VPS MANAGER  ${C_RESET}${ver_str}")\n"
    buf+="$(print_mid)\n"

    # CPU
    local cpu_bar; cpu_bar="$(draw_bar "$cpu_pct" 18)"
    buf+="$(print_2col \
        "$(printf "${C_WHITE}CPU  :${C_RESET} %3d%% %s" "$cpu_pct" "$cpu_bar")" \
        "$(printf "${C_WHITE}Load :${C_RESET} %s %s %s" "$load1" "$load5" "$load15")")\n"

    # RAM
    local ram_bar; ram_bar="$(draw_bar "$ram_pct" 18)"
    buf+="$(print_2col \
        "$(printf "${C_WHITE}RAM  :${C_RESET} %3d%% %s" "$ram_pct" "$ram_bar")" \
        "$(printf "${C_WHITE}Used :${C_RESET} %dMB / %dMB" "$ram_used" "$ram_total")")\n"

    # DISK
    local disk_bar; disk_bar="$(draw_bar "$disk_pct" 18)"
    buf+="$(print_2col \
        "$(printf "${C_WHITE}Disk :${C_RESET} %3d%% %s" "$disk_pct" "$disk_bar")" \
        "$(printf "${C_WHITE}Used :${C_RESET} %dGB / %dGB" "$disk_used" "$disk_total")")\n"

    buf+="$(print_sep)\n"

    # Network
    buf+="$(print_2col \
        "$(printf "${C_WHITE}Net↓ :${C_RESET} %-12s" "$rx_str")" \
        "$(printf "${C_WHITE}Net↑ :${C_RESET} %-12s" "$tx_str")")\n"

    # Uptime
    buf+="$(print_row "$(printf "${C_WHITE}Uptime:${C_RESET} %-15s" "$uptime_str")")\n"

    buf+="$(print_sep)\n"

    # Services
    buf+="$(print_2col \
        "$(printf "${C_WHITE}%-14s:${C_RESET} %s" "$web_name" "$web_status")" \
        "$(printf "${C_WHITE}%-14s:${C_RESET} %s" "MariaDB" "$db_status")")\n"

    if [[ -n "$cache_svc" ]]; then
        buf+="$(print_row "$(printf "${C_WHITE}%-14s:${C_RESET} %s" "$cache_name" "$cache_status")")\n"
    fi

    buf+="$(print_sep)\n"

    # Cảnh báo
    if [[ $ram_pct -ge 85 ]]; then
        buf+="$(center_row "${C_BRED}⚠  Cảnh báo: RAM đang quá tải! (${ram_pct}%)  ⚠${C_RESET}")\n"
        buf+="$(print_sep)\n"
    fi
    if [[ $disk_pct -ge 90 ]]; then
        buf+="$(center_row "${C_BRED}⚠  Cảnh báo: Ổ cứng sắp đầy! (${disk_pct}%)  ⚠${C_RESET}")\n"
        buf+="$(print_sep)\n"
    fi

    # Menu keys
    local menu_str="${C_BGREEN}[Enter]${C_RESET} Mở menu"
    [[ "$_SHOW_UPDATE" == "1" ]] && menu_str="${menu_str}  ${C_YELLOW}[u]${C_RESET} Cập nhật"
    menu_str="${menu_str}  ${C_RED}[q]${C_RESET} Thoát CLI"
    buf+="$(center_row "$menu_str")\n"
    buf+="$(print_bot)\n"

    echo -e "$buf"
}

# ────────────────────────────────────────────────────────────
# MAIN DASHBOARD LOOP
# ────────────────────────────────────────────────────────────
run_dashboard() {
    # Khởi tạo baseline
    _init_cpu
    _init_net
    _check_update_bg

    local web_svc cache_svc
    web_svc="$(_webserver_svc)"
    cache_svc="$(_cache_svc)"

    # Cache service status
    _cached_web_status="$(_svc_status "$web_svc")"
    _cached_db_status="$(_svc_status "mariadb")"
    if [[ -n "$cache_svc" ]]; then
        _cached_cache_status="$(_svc_status "$cache_svc")"
    fi

    local cpu_pct=0 rx_kb=0 tx_kb=0
    local counter=0
    local prev_lines=0
    local action="menu"

    tput civis 2>/dev/null   # Ẩn cursor
    trap 'tput cnorm 2>/dev/null; echo ""' EXIT INT TERM

    while true; do
        # Thu thập dữ liệu
        cpu_pct="$(_get_cpu_percent)"
        read -r rx_kb tx_kb <<< "$(_get_net_speed)"

        # Cập nhật service status mỗi 5s
        if (( counter % 5 == 0 )); then
            web_svc="$(_webserver_svc)"
            cache_svc="$(_cache_svc)"
            _cached_web_status="$(_svc_status "$web_svc")"
            _cached_db_status="$(_svc_status "mariadb")"
            if [[ -n "$cache_svc" ]]; then
                _cached_cache_status="$(_svc_status "$cache_svc")"
            else
                _cached_cache_status="${C_DIM}Không cài${C_RESET}"
            fi
        fi
        (( counter++ ))

        # Render vào buffer
        local buf
        buf="$(_render_dashboard "$cpu_pct" "$rx_kb" "$tx_kb")"
        local cur_lines
        cur_lines=$(echo -e "$buf" | wc -l)

        # Di chuyển cursor lên để ghi đè
        if [[ $prev_lines -gt 0 ]]; then
            tput cuu "$prev_lines" 2>/dev/null
        fi
        echo -e "$buf"

        # Xóa dòng thừa nếu màn hình co lại
        [[ $prev_lines -gt $cur_lines ]] && tput ed 2>/dev/null

        prev_lines=$cur_lines

        # Đọc phím với timeout 1 giây
        local key_in=""
        if read -t 1 -n 1 -s key_in 2>/dev/null; then
            case "$key_in" in
                q|Q) action="exit"; break ;;
                u|U) [[ "$_SHOW_UPDATE" == "1" ]] && { action="update"; break; } ;;
                *)   action="menu"; break ;;
            esac
        fi
    done

    tput cnorm 2>/dev/null
    echo ""

    case "$action" in
        exit)   echo -e "${C_CYAN}Đã thoát. Gõ ${C_BGREEN}vps${C_RESET} để quay lại."; exit 0 ;;
        update) echo -e "${C_YELLOW}Đang cập nhật...${C_RESET}"; source "$(dirname "${BASH_SOURCE[0]}")/../install.sh" ;;
        *)      return 0 ;;  # Trả về main_menu
    esac
}

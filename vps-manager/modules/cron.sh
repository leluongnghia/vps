#!/bin/bash

# modules/cron.sh - Advanced Cron Job Management
# Hỗ trợ: Xem, Thêm, Xóa, Setup WP-Cron, APRG Cron, Log viewer

# ============================================================
# HELPERS (dùng chung trong module)
# ============================================================
APRG_PLUGIN_SLUG="ai-product-review-generator"

# PHP CLI (đường dẫn tuyệt đối) đúng với phiên bản PHP-FPM mà vhost của site đang dùng
_cron_php_bin() {
    local domain=$1 bin="php" ver
    local site_conf="/etc/nginx/sites-available/$domain"
    if [[ -f "$site_conf" ]]; then
        ver=$(grep -shoP 'php\K[0-9.]+(?=-fpm)' "$site_conf" | head -n 1)
        if [[ -n "$ver" ]] && command -v "php$ver" &>/dev/null; then
            bin="php$ver"
        fi
    fi
    command -v "$bin" 2>/dev/null || echo "$bin"
}

# Tiền tố "chạy bằng user sở hữu site" cho dòng crontab (cron của root có PATH ngắn -> dùng đường dẫn tuyệt đối)
_cron_runuser_prefix() {
    local web_root=$1 ru
    ru=$(command -v runuser 2>/dev/null || echo /usr/sbin/runuser)
    echo "$ru -u $(site_owner "$web_root") --"
}

# Quét crontab cho ĐÚNG 1 domain (so khớp chuỗi cố định, không regex, không dính subdomain khác).
# Kết quả: CRON_HAS_WPCLI / CRON_HAS_WGET / CRON_HAS_APRG = true|false
_cron_scan() {
    local domain=$1 text=${2-}
    [[ $# -lt 2 ]] && text=$(crontab -l 2>/dev/null)
    local res
    res=$(printf '%s\n' "$text" | awk \
        -v wm="# WP-CRON: $domain" -v am="# APRG-CRON: $domain" \
        -v u="://$domain/wp-cron.php" -v p="/var/www/$domain/public_html" '
        $0 == am { aprg = 1; next }
        $0 == wm { pend = 1; next }
        /^[[:space:]]*#/ { next }
        {
            if (index($0, u)) wget = 1
            if (index($0, "cron event run") && index($0, p)) wpcli = 1
            if (index($0, "cron-runner.php") && index($0, p "/")) aprg = 1
        }
        END { printf "%d %d %d", wpcli, wget, aprg }')
    CRON_HAS_WPCLI=false; CRON_HAS_WGET=false; CRON_HAS_APRG=false
    [[ "${res%% *}" == "1" ]] && CRON_HAS_WPCLI=true
    local rest=${res#* }
    [[ "${rest%% *}" == "1" ]] && CRON_HAS_WGET=true
    [[ "${rest##* }" == "1" ]] && CRON_HAS_APRG=true
    return 0
}

# Gỡ entry cron của ĐÚNG 1 domain. Loại: wpcli | wget | aprg (truyền nhiều loại cùng lúc được).
# example.com KHÔNG làm mất cron của shop.example.com hay example.com.vn.
_cron_strip() {
    local domain=$1; shift
    local kinds=" $* " cur
    [[ -z "$domain" ]] && return 1
    cur=$(crontab -l 2>/dev/null) || return 0
    [[ -z "$cur" ]] && return 0
    local k_wpcli=0 k_wget=0 k_aprg=0
    [[ "$kinds" == *" wpcli "* ]] && k_wpcli=1
    [[ "$kinds" == *" wget "* ]]  && k_wget=1
    [[ "$kinds" == *" aprg "* ]]  && k_aprg=1
    # Marker "# WP-CRON: domain" dùng chung cho wpcli & wget: marker bị gỡ khi dòng lệnh ngay sau nó bị gỡ.
    printf '%s\n' "$cur" | awk \
        -v wm="# WP-CRON: $domain" -v am="# APRG-CRON: $domain" \
        -v u="://$domain/wp-cron.php" -v p="/var/www/$domain/public_html" \
        -v kc="$k_wpcli" -v kw="$k_wget" -v ka="$k_aprg" '
        function flush() { if (held != "") { print held; held = "" } }
        {
            drop = 0
            if ($0 == am) { if (ka) next; flush(); print; next }
            if ($0 == wm) { flush(); if (kc && kw) next; held = $0; next }
            if ($0 !~ /^[[:space:]]*#/) {
                if (kw && index($0, u)) drop = 1
                if (kc && index($0, "cron event run") && index($0, p)) drop = 1
                if (ka && index($0, "cron-runner.php") && index($0, p "/")) drop = 1
            }
            if (drop) { held = ""; next }
            flush(); print
        }
        END { flush() }' | crontab -
}

# Bật/tắt DISABLE_WP_CRON trong wp-config.php bằng sed (không chạy PHP của site), giữ nguyên owner.
_cron_set_disable_wp_cron() {
    local wp_config=$1 value=$2
    [[ -f "$wp_config" ]] || return 1
    local owner
    owner=$(stat -c '%U:%G' "$wp_config" 2>/dev/null)
    if grep -q "DISABLE_WP_CRON" "$wp_config"; then
        sed -i "s/^[[:space:]]*define(.*DISABLE_WP_CRON.*$/define('DISABLE_WP_CRON', ${value});/" "$wp_config"
    elif grep -q "That's all, stop editing" "$wp_config"; then
        sed -i "/\/\* That's all, stop editing/i define('DISABLE_WP_CRON', ${value});" "$wp_config"
    elif grep -q "wp-settings.php" "$wp_config"; then
        sed -i "0,/wp-settings\.php/s|^\(.*wp-settings\.php.*\)$|define('DISABLE_WP_CRON', ${value});\n\1|" "$wp_config"
    else
        return 1
    fi
    [[ -n "$owner" ]] && chown "$owner" "$wp_config" 2>/dev/null
    grep -q "define('DISABLE_WP_CRON', ${value});" "$wp_config"
}

# Thêm 1 entry cron kèm marker (ghi đè qua crontab -)
_cron_append() {
    local marker=$1 job=$2
    (crontab -l 2>/dev/null; echo "$marker"; echo "$job") | crontab -
}

# Logrotate cho log APRG (cron chạy mỗi phút -> không xoay vòng sẽ đầy đĩa)
_cron_ensure_aprg_logrotate() {
    [[ -d /etc/logrotate.d ]] || return 0
    [[ -f /etc/logrotate.d/vps-manager-aprg ]] && return 0
    cat > /etc/logrotate.d/vps-manager-aprg << 'APRGROTATE'
/var/log/aprg-cron-*.log {
    weekly
    size 20M
    rotate 4
    compress
    delaycompress
    missingok
    notifempty
    copytruncate
}
APRGROTATE
}

# ============================================================
# MAIN MENU
# ============================================================
cron_menu() {
    while true; do
        clear
        echo -e "${BLUE}=================================================${NC}"
        echo -e "${GREEN}          ⏰ Quản lý Cronjob Nâng cao${NC}"
        echo -e "${BLUE}=================================================${NC}"
        echo -e "  ${CYAN}--- Cron Cơ bản ---${NC}"
        echo -e "  1. Xem danh sách Cronjob hiện tại"
        echo -e "  2. Thêm Cronjob thủ công"
        echo -e "  3. Xóa MỘT Cronjob (an toàn)"
        echo -e "  4. Sửa Crontab bằng trình soạn thảo (Nano)"
        echo -e ""
        echo -e "  ${CYAN}--- WordPress Real Cron ---${NC}"
        echo -e "  5. ${GREEN}Setup Real WP-Cron${NC} cho website (WP-CLI)"
        echo -e "  6. Xem trạng thái WP-Cron của các website"
        echo -e "  7. Xóa WP-Cron của một website"
        echo -e ""
        echo -e "  ${CYAN}--- APRG SEO Article Cron (PHP-CLI) ---${NC}"
        echo -e "  8. ${GREEN}Setup APRG Cron${NC} (cron-runner.php — ALL-IN-ONE)"
        echo -e "  9. Xem Log APRG Cron"
        echo -e "  10. Xóa APRG Cron của một website"
        echo -e "  11. Test APRG Cron thủ công (chạy ngay 1 lần)"
        echo -e ""
        echo -e "  ${CYAN}--- Logs & Diagnostics ---${NC}"
        echo -e "  12. Xem Log Cron hệ thống"
        echo -e "  13. Test thủ công một lệnh cron"
        echo -e "  ${RED}14. 🔍 Chẩn đoán & Dọn dẹp Cron trùng lặp${NC}"
        echo -e "${BLUE}=================================================${NC}"
        echo -e "  0. Quay lại Menu chính"
        echo -e "${BLUE}=================================================${NC}"
        read -p "Nhập lựa chọn [0-14]: " choice

        case $choice in
            1)  list_crons ;;
            2)  add_cron ;;
            3)  delete_one_cron ;;
            4)  edit_cron_manual ;;
            5)  setup_wp_cron_menu ;;
            6)  show_wp_cron_status ;;
            7)  remove_wp_cron ;;
            8)  setup_aprg_cron ;;
            9)  view_aprg_log ;;
            10) remove_aprg_cron ;;
            11) test_aprg_cron ;;
            12) view_system_cron_log ;;
            13) test_cron_manually ;;
            14) diagnose_cron_duplicates ;;
            0)  return ;;
            *)  echo -e "${RED}Lựa chọn không hợp lệ!${NC}"; pause ;;
        esac
    done
}

# ============================================================
# 1. LIST CRONS
# ============================================================
list_crons() {
    clear
    echo -e "${GREEN}====== Danh sách Cronjob hiện tại ======${NC}"
    echo ""
    local current
    current=$(crontab -l 2>/dev/null)
    if [[ -z "$current" ]]; then
        echo -e "${YELLOW}⚠ Chưa có cronjob nào được thiết lập.${NC}"
    else
        echo "$current" | nl -ba -nrn -w3 -v1 | while IFS= read -r line; do
            # Colorize special lines
            if echo "$line" | grep -q "aprg\|APRG"; then
                echo -e "${CYAN}$line${NC}"
            elif echo "$line" | grep -q "wp-cron\|wp_cron\|cron event"; then
                echo -e "${GREEN}$line${NC}"
            elif echo "$line" | grep -q "^#"; then
                echo -e "${YELLOW}$line${NC}"
            else
                echo "$line"
            fi
        done
    fi
    echo ""
    echo -e "${BLUE}Legend: ${GREEN}WP-Cron${NC} | ${CYAN}APRG Cron${NC} | ${YELLOW}Comment${NC}${NC}"
    pause
}

# ============================================================
# 2. ADD CRON (Manual)
# ============================================================
add_cron() {
    echo -e "${GREEN}=== Thêm Cronjob Mới (Thủ công) ===${NC}"
    echo -e "${YELLOW}Cú pháp: [phút] [giờ] [ngày] [tháng] [thứ] [lệnh]${NC}"
    echo -e "Ví dụ:"
    echo -e "  ${CYAN}* * * * * /usr/bin/php /var/www/domain.com/cron.php${NC}  ← Mỗi phút"
    echo -e "  ${CYAN}0 3 * * * /usr/bin/php /path/to/script.php${NC}           ← 3:00 AM mỗi ngày"
    echo -e "  ${CYAN}*/5 * * * * command${NC}                                   ← Mỗi 5 phút"
    echo ""
    read -p "Nhập lệnh cron đầy đủ: " cron_cmd

    if [[ -z "$cron_cmd" ]]; then
        echo -e "${YELLOW}Đã hủy.${NC}"
        pause; return
    fi

    # Validate basic cron format (5 time fields + command)
    field_count=$(echo "$cron_cmd" | awk '{print NF}')
    if [[ "$field_count" -lt 6 ]]; then
        echo -e "${RED}❌ Lỗi: Cron cần ít nhất 6 phần (5 fields thời gian + lệnh).${NC}"
        pause; return
    fi

    # Check duplicate (khớp nguyên dòng, không khớp chuỗi con)
    if crontab -l 2>/dev/null | grep -qxF -- "$cron_cmd"; then
        echo -e "${YELLOW}⚠ Cron này đã tồn tại!${NC}"
        pause; return
    fi

    (crontab -l 2>/dev/null; echo "$cron_cmd") | crontab -
    echo -e "${GREEN}✔ Đã thêm cronjob thành công.${NC}"
    echo -e "   ${CYAN}$cron_cmd${NC}"
    pause
}

# ============================================================
# 3. DELETE ONE CRON (Safe)
# ============================================================
delete_one_cron() {
    clear
    echo -e "${YELLOW}=== Xóa MỘT Cronjob (An toàn) ===${NC}"
    echo ""
    
    local current
    current=$(crontab -l 2>/dev/null)
    if [[ -z "$current" ]]; then
        echo -e "${YELLOW}Chưa có cronjob nào.${NC}"
        pause; return
    fi

    echo -e "${CYAN}Danh sách cronjob hiện tại:${NC}"
    echo ""
    # Display with line numbers
    mapfile -t cron_lines <<< "$current"
    local idx=0
    for line in "${cron_lines[@]}"; do
        echo -e "  ${idx}. $line"
        ((idx++))
    done

    echo ""
    read -p "Nhập số thứ tự dòng cần xóa (hoặc Enter để hủy): " del_idx

    if [[ -z "$del_idx" ]]; then
        echo -e "${YELLOW}Đã hủy.${NC}"; pause; return
    fi

    if ! [[ "$del_idx" =~ ^[0-9]+$ ]] || [[ "$del_idx" -ge "${#cron_lines[@]}" ]]; then
        echo -e "${RED}Số không hợp lệ.${NC}"; pause; return
    fi

    local target_line="${cron_lines[$del_idx]}"
    echo ""
    echo -e "${RED}Bạn muốn xóa dòng này:${NC}"
    echo -e "  ${CYAN}$target_line${NC}"
    read -p "Xác nhận xóa? (y/n): " confirm

    if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
        # Crontab có thể đã đổi từ lúc liệt kê -> kiểm tra lại rồi xoá ĐÚNG dòng theo số thứ tự
        # (không dùng grep -v: dòng trống sẽ xoá sạch crontab, chuỗi con sẽ xoá nhầm dòng khác)
        if [[ "$(crontab -l 2>/dev/null)" != "$current" ]]; then
            echo -e "${RED}Crontab vừa thay đổi trong lúc bạn chọn. Hãy thử lại.${NC}"
            pause; return
        fi
        local new_lines=() i
        for i in "${!cron_lines[@]}"; do
            [[ "$i" -ne "$del_idx" ]] && new_lines+=("${cron_lines[$i]}")
        done
        if [[ ${#new_lines[@]} -eq 0 ]]; then
            crontab -r 2>/dev/null
        else
            printf '%s\n' "${new_lines[@]}" | crontab -
        fi
        if [[ $? -eq 0 ]]; then
            echo -e "${GREEN}✔ Đã xóa thành công.${NC}"
        else
            echo -e "${RED}❌ Không ghi được crontab.${NC}"
        fi
    else
        echo -e "${YELLOW}Đã hủy.${NC}"
    fi
    pause
}

# ============================================================
# EDIT CRONTAB MANUALLY
# (Mục "Xóa TOÀN BỘ cronjob" đã bỏ: nó xoá luôn cron backup tự động và cron gia hạn SSL;
#  muốn xoá nhiều dòng thì dùng trình soạn thảo ở đây hoặc "Xóa MỘT Cronjob".)
# ============================================================
edit_cron_manual() {
    echo -e "${YELLOW}Đang mở crontab bằng trình soạn thảo...${NC}"
    EDITOR="${EDITOR:-nano}" crontab -e
    pause
}

# ============================================================
# 6. SETUP WP-CRON (Menu)
# ============================================================
setup_wp_cron_menu() {
    clear
    echo -e "${GREEN}=== Setup Real WP-Cron cho WordPress ===${NC}"
    echo ""
    # Chỉ còn MỘT phương thức: WP-CLI qua PHP-CLI.
    # Phương thức Wget (gọi wp-cron.php qua HTTP) đã bỏ: nó chiếm PHP-FPM worker, bị WAF / HTTP Basic Auth /
    # chế độ bảo trì chặn (cron âm thầm ngừng chạy), và phụ thuộc DNS + SSL của chính site.
    # Cron Wget đã cài trước đây vẫn được nhận diện và sẽ được thay bằng WP-CLI khi setup lại.
    echo -e "  ${GREEN}WP-CLI --due-now (PHP-CLI)${NC} — không qua HTTP, không chiếm FPM worker"
    echo -e "  ${CYAN}→ wp cron event run --due-now (mỗi phút, chạy bằng user của site)${NC}"
    echo ""
    _setup_wp_cron_wpcli
}

_select_wp_site_for_cron() {
    echo -e "\n${CYAN}Danh sách WordPress Sites:${NC}"
    local sites=()
    local i=1
    for d in /var/www/*; do
        if [[ -d "$d" && -f "$d/public_html/wp-config.php" ]]; then
            local domain
            domain=$(basename "$d")
            sites+=("$domain")
            echo -e "  $i. $domain"
            ((i++))
        fi
    done

    if [[ ${#sites[@]} -eq 0 ]]; then
        echo -e "${RED}Không tìm thấy website WordPress nào!${NC}"
        return 1
    fi

    read -p "Chọn website [1-${#sites[@]}] hoặc 'a' cho tất cả: " w_choice

    if [[ "$w_choice" == "a" || "$w_choice" == "A" ]]; then
        SELECTED_CRON_DOMAINS=("${sites[@]}")
    elif [[ "$w_choice" =~ ^[0-9]+$ ]] && [[ "$w_choice" -ge 1 ]] && [[ "$w_choice" -le "${#sites[@]}" ]]; then
        SELECTED_CRON_DOMAINS=("${sites[$((w_choice-1))]}")
    else
        echo -e "${RED}Lựa chọn không hợp lệ.${NC}"
        return 1
    fi
    return 0
}

_setup_wp_cron_wpcli() {
    SELECTED_CRON_DOMAINS=()
    _select_wp_site_for_cron || { pause; return; }

    # Ensure WP-CLI is installed (tải có kiểm tra sha512)
    if ! ensure_wp_cli; then
        echo -e "${RED}❌ Không cài được WP-CLI. Hãy dùng phương thức Wget hoặc thử lại sau.${NC}"
        pause; return
    fi

    for domain in "${SELECTED_CRON_DOMAINS[@]}"; do
        local web_root="/var/www/$domain/public_html"
        local wp_config="$web_root/wp-config.php"
        local php_bin
        php_bin=$(_cron_php_bin "$domain")

        if ! _cron_set_disable_wp_cron "$wp_config" true; then
            echo -e "${RED}❌ [$domain] Không đặt được DISABLE_WP_CRON trong wp-config.php — bỏ qua site này.${NC}"
            continue
        fi

        # Chạy WP-CLI bằng user sở hữu site, KHÔNG phải root: plugin/theme bị chiếm sẽ không leo lên root được,
        # và file do cron tạo ra không bị root sở hữu.
        local wp_prefix ru
        ru=$(command -v runuser 2>/dev/null || echo /usr/sbin/runuser)
        wp_prefix=$(wp_cmd_prefix "$web_root" "$php_bin")
        wp_prefix="${wp_prefix/#runuser/$ru}"

        # cd vào web root trước: user của site không đọc được thư mục làm việc mặc định của cron (/root)
        local croncmd="cd $web_root && $wp_prefix cron event run --due-now --quiet >/dev/null 2>&1"
        local cronjob="* * * * * $croncmd"
        local marker="# WP-CRON: $domain"

        # Gỡ entry WP-Cron cũ của ĐÚNG domain này (cả WP-CLI lẫn Wget) rồi thêm mới
        _cron_strip "$domain" wpcli wget
        _cron_append "$marker" "$cronjob"

        echo -e "${GREEN}✔ [$domain] Đã setup WP-Cron (WP-CLI --due-now, user: $(site_owner "$web_root"))${NC}"
        echo -e "   ${CYAN}$croncmd${NC}"
    done
    pause
}

# ============================================================
# 7. SHOW WP-CRON STATUS
# ============================================================
show_wp_cron_status() {
    clear
    echo -e "${GREEN}=== Trạng thái WP-Cron của các Website ===${NC}"
    echo ""
    printf "%-30s %-12s %-10s %s\n" "Domain" "DISABLE_WP_CRON" "Cron Type" "Status"
    echo -e "${BLUE}------------------------------------------------------------------------${NC}"

    for d in /var/www/*; do
        if [[ -d "$d" && -f "$d/public_html/wp-config.php" ]]; then
            local domain
            domain=$(basename "$d")
            local wp_config="$d/public_html/wp-config.php"

            # Check DISABLE_WP_CRON
            local disable_val
            disable_val=$(grep -oP "define.*DISABLE_WP_CRON.*?(true|false)" "$wp_config" 2>/dev/null | grep -oP "true|false" | tail -1)
            [ -z "$disable_val" ] && disable_val="not set"

            # Check if in crontab (khớp đúng domain, không dính subdomain)
            local cron_type="none"
            _cron_scan "$domain"
            if $CRON_HAS_WGET; then
                cron_type="Wget"
            elif $CRON_HAS_WPCLI; then
                cron_type="WP-CLI"
            elif $CRON_HAS_APRG; then
                cron_type="APRG"
            fi

            local status="${RED}❌ Không có cron${NC}"
            if [[ "$cron_type" != "none" && "$disable_val" == "true" ]]; then
                status="${GREEN}✔ Hoạt động ($cron_type)${NC}"
            elif [[ "$cron_type" != "none" && "$disable_val" != "true" ]]; then
                status="${YELLOW}⚠ Có cron nhưng DISABLE_WP_CRON chưa bật${NC}"
            elif [[ "$cron_type" == "none" && "$disable_val" != "true" ]]; then
                status="${CYAN}○ Dùng WP-Cron built-in (mặc định)${NC}"
            fi

            printf "%-30s %-12s %-10s " "$domain" "$disable_val" "$cron_type"
            echo -e "$status"
        fi
    done

    echo ""
    pause
}

# ============================================================
# 8. REMOVE WP-CRON
# ============================================================
remove_wp_cron() {
    _select_wp_site_for_cron || { pause; return; }

    for domain in "${SELECTED_CRON_DOMAINS[@]}"; do
        local web_root="/var/www/$domain/public_html"
        
        # Remove from crontab (đúng domain này)
        _cron_strip "$domain" wpcli wget

        # Re-enable WP-Cron built-in — trừ khi APRG cron vẫn đang đảm nhiệm wp_cron() cho site
        _cron_scan "$domain"
        if $CRON_HAS_APRG; then
            echo -e "${GREEN}✔ Đã xóa WP-Cron cho $domain.${NC} ${YELLOW}(Giữ DISABLE_WP_CRON vì APRG Cron vẫn đang chạy.)${NC}"
        elif _cron_set_disable_wp_cron "$web_root/wp-config.php" false; then
            echo -e "${GREEN}✔ Đã xóa WP-Cron cho $domain và phục hồi WP built-in cron.${NC}"
        else
            echo -e "${YELLOW}⚠ Đã xóa WP-Cron cho $domain nhưng KHÔNG sửa được DISABLE_WP_CRON trong wp-config.php — hãy sửa tay, nếu không WP sẽ không chạy cron.${NC}"
        fi
    done
    pause
}

# ============================================================
# 9. SETUP APRG CRON (AI Product Review Generator)
# ============================================================
setup_aprg_cron() {
    clear
    echo -e "${GREEN}=== Setup APRG SEO Article Cron ===${NC}"
    echo ""
    echo -e "${BLUE}┌─────────────────────────────────────────────────────┐${NC}"
    echo -e "${BLUE}│${NC} ${CYAN}cron-runner.php${NC} là ${GREEN}ALL-IN-ONE runner${NC} — bao gồm:      ${BLUE}│${NC}"
    echo -e "${BLUE}│${NC}  ${GREEN}✔${NC} WP cron events (thay thế wget/WP-CLI cron)        ${BLUE}│${NC}"
    echo -e "${BLUE}│${NC}  ${GREEN}✔${NC} APRG SEO Article batch (AI generate + publish)    ${BLUE}│${NC}"
    echo -e "${BLUE}│${NC}  ${GREEN}✔${NC} Chạy qua PHP-CLI — không chiếm PHP-FPM worker     ${BLUE}│${NC}"
    echo -e "${BLUE}│${NC}  ${GREEN}✔${NC} Log ghi tự động vào /var/log/aprg-cron-*.log      ${BLUE}│${NC}"
    echo -e "${BLUE}│${NC}                                                     ${BLUE}│${NC}"
    echo -e "${BLUE}│${NC}  ${RED}⚠  CHỈ CẦN 1 DÒNG CRONTAB cho domain này!${NC}         ${BLUE}│${NC}"
    echo -e "${BLUE}│${NC}  ${YELLOW}Nếu đang có WP-CLI cron hoặc Wget cron riêng${NC}       ${BLUE}│${NC}"
    echo -e "${BLUE}│${NC}  ${YELLOW}→ Script sẽ hỏi bạn có muốn xóa chúng không.${NC}      ${BLUE}│${NC}"
    echo -e "${BLUE}└─────────────────────────────────────────────────────┘${NC}"
    echo ""

    # Select WP site
    SELECTED_CRON_DOMAINS=()
    _select_wp_site_for_cron || { pause; return; }

    # APRG plugin config
    local aprg_plugin_slug="ai-product-review-generator"
    local aprg_runner_file="cron-runner.php"

    # Select interval
    echo ""
    echo -e "${YELLOW}Chọn tần suất chạy APRG Cron:${NC}"
    echo -e "  1. Mỗi 1 phút   ${CYAN}(* * * * *)${NC}      ← Khuyên dùng"
    echo -e "  2. Mỗi 5 phút   ${CYAN}(*/5 * * * *)${NC}"
    echo -e "  3. Mỗi 15 phút  ${CYAN}(*/15 * * * *)${NC}"
    echo -e "  4. Mỗi 30 phút  ${CYAN}(*/30 * * * *)${NC}"
    echo -e "  5. Mỗi giờ      ${CYAN}(0 * * * *)${NC}"
    read -p "Chọn [1-5, mặc định=1]: " interval_choice

    local cron_schedule
    case "$interval_choice" in
        2) cron_schedule="*/5 * * * *" ;;
        3) cron_schedule="*/15 * * * *" ;;
        4) cron_schedule="*/30 * * * *" ;;
        5) cron_schedule="0 * * * *" ;;
        *) cron_schedule="* * * * *" ;;
    esac

    for domain in "${SELECTED_CRON_DOMAINS[@]}"; do
        local web_root="/var/www/$domain/public_html"
        local plugin_dir="$web_root/wp-content/plugins/$aprg_plugin_slug"
        local runner_path="$plugin_dir/$aprg_runner_file"

        echo ""
        echo -e "${CYAN}━━━ Đang xử lý: $domain ━━━${NC}"

        # ── Kiểm tra cron trùng lặp ──────────────────────────────
        # (quét cả dòng có marker lẫn cron cũ thêm bằng tay; khớp đúng domain)
        _cron_scan "$domain"
        local has_wpcli_cron=$CRON_HAS_WPCLI
        local has_wget_cron=$CRON_HAS_WGET

        if $has_wpcli_cron || $has_wget_cron; then
            echo -e "${YELLOW}⚠ Phát hiện cron WP trùng lặp với APRG cho $domain:${NC}"
            $has_wpcli_cron && echo -e "   ${RED}✗ WP-CLI cron (--due-now)${NC} — APRG đã thay thế chức năng này"
            $has_wget_cron  && echo -e "   ${RED}✗ Wget cron (wp-cron.php)${NC} — APRG đã thay thế chức năng này"
            echo ""
            echo -e "${CYAN}cron-runner.php đã bao gồm wp_cron() bên trong → giữ chúng sẽ bị trùng.${NC}"
            read -p "Tự động XÓA các cron WP cũ cho $domain? (y/n, KHUYÊN y): " rm_dup
            if [[ "$rm_dup" == "y" || "$rm_dup" == "Y" ]]; then
                # Remove WP-CRON marker block
                _cron_strip "$domain" wpcli wget
                echo -e "${GREEN}✔ Đã xóa các cron WP trùng lặp.${NC}"
            else
                echo -e "${YELLOW}⚠ Giữ nguyên — lưu ý có thể bị gọi check_and_process() nhiều lần/phút.${NC}"
                echo -e "   ${CYAN}Dùng option 15 (Chẩn đoán) để xem và dọn sau.${NC}"
            fi
        fi

        # ── Check plugin tồn tại ─────────────────────────────────
        if [[ ! -d "$plugin_dir" ]]; then
            echo -e "${YELLOW}⚠ Plugin APRG chưa được cài tại: $plugin_dir${NC}"
            read -p "   Vẫn thêm cron? (y/n): " force_add
            if [[ "$force_add" != "y" && "$force_add" != "Y" ]]; then
                echo -e "${YELLOW}Bỏ qua $domain.${NC}"
                continue
            fi
        fi

        # ── Auto-detect PHP version ───────────────────────────────
        local php_bin
        php_bin=$(_cron_php_bin "$domain")

        # ── Build & install cron ──────────────────────────────────
        # Runner nằm trong thư mục plugin (PHP-FPM ghi được) -> chạy bằng user sở hữu site, KHÔNG phải root.
        # Phần ">> log" do shell của cron (root) mở nên file log vẫn thuộc root.
        local log_file="/var/log/aprg-cron-$(echo "$domain" | tr '.' '-').log"
        local run_as
        run_as=$(_cron_runuser_prefix "$web_root")
        local croncmd="cd $web_root && $run_as $php_bin -d memory_limit=512M -d max_execution_time=300 -d display_errors=0 $runner_path >> $log_file 2>&1"
        local cronjob="$cron_schedule $croncmd"
        local marker="# APRG-CRON: $domain"

        # Remove old APRG cron entries first (đúng domain này), rồi thêm mới
        _cron_strip "$domain" aprg
        _cron_append "$marker" "$cronjob"

        # Create log file + logrotate (cron chạy mỗi phút nên log phải được xoay vòng)
        touch "$log_file" 2>/dev/null
        chmod 640 "$log_file" 2>/dev/null
        _cron_ensure_aprg_logrotate

        echo -e "${GREEN}✔ [$domain] Đã setup APRG Cron!${NC}"
        echo -e "   ${CYAN}Schedule:${NC}  $cron_schedule"
        echo -e "   ${CYAN}Chạy bằng:${NC} $(site_owner "$web_root")"
        echo -e "   ${CYAN}PHP:${NC}       $php_bin"
        echo -e "   ${CYAN}Runner:${NC}    $runner_path"
        echo -e "   ${CYAN}Log:${NC}       $log_file"
    done

    echo ""
    echo -e "${GREEN}=====================================================${NC}"
    echo -e "${GREEN}✔ APRG cron-runner.php đã xử lý TẤT CẢ:${NC}"
    echo -e "   • wp_cron() — toàn bộ WP scheduled events"
    echo -e "   • APRG_SEO_Article_Processor::check_and_process()"
    echo -e "   → Không cần WP-CLI hay Wget cron riêng cho domain này!"
    echo -e "${GREEN}=====================================================${NC}"
    pause
}

# ============================================================
# 10. VIEW APRG LOG
# ============================================================
view_aprg_log() {
    clear
    echo -e "${GREEN}=== Log APRG Cron ===${NC}"
    echo ""

    # Find all APRG log files
    local log_files
    mapfile -t log_files < <(ls /var/log/aprg-cron-*.log 2>/dev/null)

    if [[ ${#log_files[@]} -eq 0 ]]; then
        echo -e "${YELLOW}⚠ Chưa có file log APRG nào. (Cron chưa chạy lần nào)${NC}"
        pause; return
    fi

    if [[ ${#log_files[@]} -eq 1 ]]; then
        SELECTED_LOG="${log_files[0]}"
    else
        echo -e "${CYAN}Chọn file log:${NC}"
        local i=1
        for lf in "${log_files[@]}"; do
            local size
            size=$(du -sh "$lf" 2>/dev/null | cut -f1)
            echo -e "  $i. $(basename "$lf")  ${YELLOW}($size)${NC}"
            ((i++))
        done
        read -p "Chọn [1-${#log_files[@]}]: " log_choice
        if ! [[ "$log_choice" =~ ^[0-9]+$ ]] || [[ "$log_choice" -lt 1 ]] || [[ "$log_choice" -gt "${#log_files[@]}" ]]; then
            echo -e "${RED}Lựa chọn không hợp lệ.${NC}"; pause; return
        fi
        SELECTED_LOG="${log_files[$((log_choice-1))]}"
    fi

    echo -e "${CYAN}File: $SELECTED_LOG${NC}"
    echo -e "${BLUE}------- 100 dòng cuối -------${NC}"
    echo ""
    tail -n 100 "$SELECTED_LOG" 2>/dev/null

    echo ""
    echo -e "${BLUE}-------------------------------${NC}"
    echo -e "  ${CYAN}L${NC}. Live tail (theo dõi realtime)"
    echo -e "  ${CYAN}C${NC}. Xóa log này"
    echo -e "  ${CYAN}Enter${NC}. Quay lại"
    read -p "Chọn: " log_action

    case "$log_action" in
        l|L)
            echo -e "${YELLOW}Đang theo dõi realtime. Nhấn Ctrl+C để thoát.${NC}"
            tail -f "$SELECTED_LOG"
            ;;
        c|C)
            read -p "Xóa toàn bộ log? (y/n): " del_log
            if [[ "$del_log" == "y" || "$del_log" == "Y" ]]; then
                > "$SELECTED_LOG"
                echo -e "${GREEN}✔ Đã xóa log.${NC}"
            fi
            ;;
    esac
    pause
}

# ============================================================
# 11. REMOVE APRG CRON
# ============================================================
remove_aprg_cron() {
    SELECTED_CRON_DOMAINS=()
    _select_wp_site_for_cron || { pause; return; }

    for domain in "${SELECTED_CRON_DOMAINS[@]}"; do
        _cron_strip "$domain" aprg
        echo -e "${GREEN}✔ Đã xóa APRG Cron cho $domain.${NC}"
        # APRG runner trước đó đảm nhiệm wp_cron(); nếu không còn cron nào khác thì bật lại WP-Cron built-in
        _cron_scan "$domain"
        if ! $CRON_HAS_WPCLI && ! $CRON_HAS_WGET && grep -q "DISABLE_WP_CRON', true" "/var/www/$domain/public_html/wp-config.php" 2>/dev/null; then
            echo -e "${YELLOW}⚠ $domain đang đặt DISABLE_WP_CRON=true nhưng không còn cron nào chạy WP events.${NC}"
            read -p "   Bật lại WP-Cron built-in cho $domain? (y/n): " re_enable
            if [[ "$re_enable" == "y" || "$re_enable" == "Y" ]]; then
                _cron_set_disable_wp_cron "/var/www/$domain/public_html/wp-config.php" false \
                    && echo -e "${GREEN}✔ Đã bật lại WP-Cron built-in.${NC}"
            fi
        fi
    done
    pause
}

# ============================================================
# 12. TEST APRG CRON (Run Now)
# ============================================================
test_aprg_cron() {
    clear
    echo -e "${GREEN}=== Test APRG Cron Thủ công ===${NC}"
    echo -e "${YELLOW}Chức năng này sẽ chạy cron-runner.php ngay lập tức (1 lần).${NC}"
    echo ""

    SELECTED_CRON_DOMAINS=()
    _select_wp_site_for_cron || { pause; return; }

    local domain="${SELECTED_CRON_DOMAINS[0]}"
    local web_root="/var/www/$domain/public_html"
    local runner_path="$web_root/wp-content/plugins/$APRG_PLUGIN_SLUG/cron-runner.php"

    if [[ ! -f "$runner_path" ]]; then
        echo -e "${RED}❌ Không tìm thấy file: $runner_path${NC}"
        echo -e "${YELLOW}Hãy đảm bảo plugin APRG đã được cài và active.${NC}"
        pause; return
    fi

    # Auto-detect PHP version
    local php_bin run_as
    php_bin=$(_cron_php_bin "$domain")
    run_as=$(_cron_runuser_prefix "$web_root")

    echo -e "${CYAN}Đang chạy (user: $(site_owner "$web_root")): $php_bin $runner_path${NC}"
    echo -e "${BLUE}------- Output -------${NC}"
    echo ""

    # Run with output shown directly — bằng user sở hữu site, giống hệt lúc cron chạy
    ( cd "$web_root" && $run_as "$php_bin" -d memory_limit=512M -d max_execution_time=300 -d display_errors=1 "$runner_path" 2>&1 )
    local rc=$?

    echo ""
    echo -e "${BLUE}------- End -------${NC}"
    if [[ $rc -eq 0 ]]; then
        echo -e "${GREEN}✔ Hoàn tất (exit code 0).${NC}"
    else
        echo -e "${RED}❌ Runner kết thúc với exit code $rc.${NC}"
    fi
    pause
}

# ============================================================
# 13. VIEW SYSTEM CRON LOG
# ============================================================
view_system_cron_log() {
    clear
    echo -e "${GREEN}=== Log Cron Hệ thống ===${NC}"
    echo ""

    # RHEL/Oracle: /var/log/cron — Debian/Ubuntu: /var/log/syslog hoặc /var/log/cron.log
    local log_file="" f
    for f in /var/log/cron /var/log/cron.log /var/log/syslog; do
        if [[ -f "$f" ]]; then log_file="$f"; break; fi
    done

    if [[ -z "$log_file" ]]; then
        # Hệ thống chỉ dùng journald (không có rsyslog)
        if command -v journalctl &>/dev/null; then
            echo -e "${CYAN}Nguồn: journalctl (cron/crond)${NC}"
            echo -e "${BLUE}------- 50 dòng CRON gần nhất -------${NC}"
            echo ""
            journalctl -u cron -u crond --no-pager -n 50 2>/dev/null
            echo ""
            echo -e "${BLUE}--------------------------------------${NC}"
        else
            echo -e "${YELLOW}Không tìm thấy file log hệ thống.${NC}"
        fi
        pause; return
    fi

    echo -e "${CYAN}File: $log_file${NC}"
    echo -e "${BLUE}------- 50 dòng CRON gần nhất -------${NC}"
    echo ""
    grep -i "cron" "$log_file" | tail -50
    echo ""
    echo -e "${BLUE}--------------------------------------${NC}"
    pause
}

# ============================================================
# 14. TEST CRON MANUALLY
# ============================================================
test_cron_manually() {
    clear
    echo -e "${GREEN}=== Test Một Lệnh Cron Thủ công ===${NC}"
    echo ""
    echo -e "${YELLOW}Nhập lệnh cần test (sẽ chạy ngay, không cần context cron):${NC}"
    echo -e "Ví dụ: ${CYAN}/usr/bin/php /var/www/example.com/public_html/wp-cron.php?doing_wp_cron${NC}"
    echo ""
    read -p "Nhập lệnh: " test_cmd

    if [[ -z "$test_cmd" ]]; then
        echo -e "${YELLOW}Đã hủy.${NC}"; pause; return
    fi

    echo ""
    echo -e "${CYAN}Đang chạy...${NC}"
    echo -e "${BLUE}------ Output ------${NC}"
    eval "$test_cmd" 2>&1
    local test_rc=$?
    echo -e "${BLUE}------ End ------${NC}"
    if [[ $test_rc -eq 0 ]]; then
        echo -e "${GREEN}Exit code: $test_rc${NC}"
    else
        echo -e "${RED}Exit code: $test_rc${NC}"
    fi
    pause
}

# ============================================================
# 15. DIAGNOSE & FIX CRON DUPLICATES
# ============================================================
diagnose_cron_duplicates() {
    clear
    echo -e "${GREEN}=== 🔍 Chẩn đoán & Dọn dẹp Cron trùng lặp ===${NC}"
    echo ""
    echo -e "Script sẽ phân tích crontab theo từng domain và tìm"
    echo -e "các trường hợp bị cấu hình nhiều cron trùng nhau."
    echo ""

    local current_crontab
    current_crontab=$(crontab -l 2>/dev/null)

    if [[ -z "$current_crontab" ]]; then
        echo -e "${YELLOW}Crontab trống — không có gì để chẩn đoán.${NC}"
        pause; return
    fi

    # ── Thu thập danh sách domain WP ────────────────────────────────
    local domains=()
    for d in /var/www/*; do
        if [[ -d "$d" && -f "$d/public_html/wp-config.php" ]]; then
            domains+=("$(basename "$d")")
        fi
    done

    if [[ ${#domains[@]} -eq 0 ]]; then
        echo -e "${YELLOW}Không tìm thấy website WordPress nào trên server.${NC}"
        pause; return
    fi

    local found_issues=false
    local domains_with_issues=()

    echo -e "${BLUE}══════════════════════════════════════════════════════════${NC}"
    printf "  %-28s %-8s %-8s %-8s %s\n" "Domain" "APRG" "WP-CLI" "Wget" "Trạng thái"
    echo -e "${BLUE}══════════════════════════════════════════════════════════${NC}"

    for domain in "${domains[@]}"; do
        # Quét theo đúng domain (marker hoặc dòng lệnh; không dính subdomain / domain có chung tiền tố)
        _cron_scan "$domain" "$current_crontab"
        local has_aprg=$CRON_HAS_APRG
        local has_wpcli=$CRON_HAS_WPCLI
        local has_wget=$CRON_HAS_WGET

        # Đếm số loại cron đang chạy
        local cron_count=0
        $has_aprg  && ((cron_count++))
        $has_wpcli && ((cron_count++))
        $has_wget  && ((cron_count++))

        # Chỉ in domain có ít nhất 1 cron
        if [[ $cron_count -eq 0 ]]; then
            continue
        fi

        local aprg_col="${RED}-${NC}"
        local wpcli_col="${RED}-${NC}"
        local wget_col="${RED}-${NC}"
        $has_aprg  && aprg_col="${GREEN}✔${NC}"
        $has_wpcli && wpcli_col="${GREEN}✔${NC}"
        $has_wget  && wget_col="${GREEN}✔${NC}"

        local status_msg
        if $has_aprg && ($has_wpcli || $has_wget); then
            # APRG bao gồm wp_cron() → WP-CLI/Wget là trùng
            found_issues=true
            domains_with_issues+=("$domain")
            status_msg="${RED}⚠ TRÙNG! APRG đã bao gồm wp_cron()${NC}"
        elif $has_wpcli && $has_wget; then
            # Cả hai đều trigger wp-cron → trùng
            found_issues=true
            domains_with_issues+=("$domain")
            status_msg="${YELLOW}⚠ WP-CLI + Wget đều trigger WP-Cron${NC}"
        else
            status_msg="${GREEN}✔ OK${NC}"
        fi

        printf "  %-28s " "$domain"
        echo -e "$aprg_col       $wpcli_col      $wget_col      $status_msg"
    done

    echo -e "${BLUE}══════════════════════════════════════════════════════════${NC}"

    if ! $found_issues; then
        echo ""
        echo -e "${GREEN}✔ Không phát hiện cron trùng lặp!${NC}"
        pause; return
    fi

    echo ""
    echo -e "${RED}Phát hiện ${#domains_with_issues[@]} domain bị cron trùng lặp.${NC}"
    echo ""
    echo -e "${YELLOW}Giải thích:${NC}"
    echo -e "  • ${GREEN}APRG (cron-runner.php)${NC} = ALL-IN-ONE:"
    echo -e "    Gọi wp_cron() + APRG batch — ${RED}không cần WP-CLI/Wget cùng lúc${NC}"
    echo -e "  • ${CYAN}WP-CLI --due-now${NC} hoặc ${CYAN}Wget${NC} = chỉ xử lý WP events"
    echo -e "    Nên dùng ${RED}1 trong 2${NC}, không dùng cả hai song song"
    echo ""

    read -p "Tự động dọn dẹp cron trùng? (y/n): " do_fix
    if [[ "$do_fix" != "y" && "$do_fix" != "Y" ]]; then
        echo -e "${YELLOW}Đã hủy. Dùng option 3 (Xóa từng cron) để dọn thủ công.${NC}"
        pause; return
    fi

    echo ""
    echo -e "${CYAN}Chọn chiến lược fix cho TẤT CẢ domain bị lỗi:${NC}"
    echo -e "  1. ${GREEN}Giữ APRG (cron-runner.php)${NC}, xóa WP-CLI + Wget  ${CYAN}← KHUYÊN DÙNG${NC}"
    echo -e "  2. ${GREEN}Giữ WP-CLI${NC}, xóa APRG + Wget"
    echo -e "  3. ${GREEN}Giữ Wget${NC}, xóa APRG + WP-CLI"
    read -p "Chọn [1-3]: " fix_strategy

    echo ""
    for domain in "${domains_with_issues[@]}"; do
        # Chỉ gỡ loại thực sự tồn tại; domain không có loại được "giữ" thì bỏ qua để không mất hết cron
        _cron_scan "$domain"
        case "$fix_strategy" in
            1)
                # Keep APRG, remove WP-CLI + Wget
                if ! $CRON_HAS_APRG; then
                    echo -e "${YELLOW}⚠ [$domain] Không có APRG cron để giữ — bỏ qua (dùng option 3 để dọn tay).${NC}"
                    continue
                fi
                _cron_strip "$domain" wpcli wget
                echo -e "${GREEN}✔ [$domain] Đã xóa WP-CLI + Wget. Giữ APRG.${NC}"
                ;;
            2)
                # Keep WP-CLI, remove APRG + Wget
                if ! $CRON_HAS_WPCLI; then
                    echo -e "${YELLOW}⚠ [$domain] Không có WP-CLI cron để giữ — bỏ qua (dùng option 3 để dọn tay).${NC}"
                    continue
                fi
                _cron_strip "$domain" aprg wget
                echo -e "${GREEN}✔ [$domain] Đã xóa APRG + Wget. Giữ WP-CLI.${NC}"
                ;;
            3)
                # Keep Wget, remove APRG + WP-CLI
                if ! $CRON_HAS_WGET; then
                    echo -e "${YELLOW}⚠ [$domain] Không có Wget cron để giữ — bỏ qua (dùng option 3 để dọn tay).${NC}"
                    continue
                fi
                _cron_strip "$domain" aprg wpcli
                echo -e "${GREEN}✔ [$domain] Đã xóa APRG + WP-CLI. Giữ Wget.${NC}"
                ;;
            *)
                echo -e "${RED}Lựa chọn không hợp lệ — bỏ qua $domain.${NC}"
                ;;
        esac
    done

    echo ""
    echo -e "${GREEN}✔ Hoàn tất! Crontab sau khi dọn dẹp:${NC}"
    echo -e "${BLUE}──────────────────────────────────────────────────${NC}"
    crontab -l 2>/dev/null
    echo -e "${BLUE}──────────────────────────────────────────────────${NC}"
    pause
}

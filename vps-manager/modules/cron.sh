#!/bin/bash

# modules/cron.sh - Advanced Cron Job Management
# Hỗ trợ: Xem, Thêm, Xóa, Setup WP-Cron, APRG Cron, Log viewer

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
        echo -e "  4. Xóa TOÀN BỘ Cronjob ${RED}(Cẩn thận!)${NC}"
        echo -e "  5. Sửa Crontab bằng trình soạn thảo (Nano)"
        echo -e ""
        echo -e "  ${CYAN}--- WordPress Real Cron ---${NC}"
        echo -e "  6. ${GREEN}Setup Real WP-Cron${NC} cho website (Wget / WP-CLI)"
        echo -e "  7. Xem trạng thái WP-Cron của các website"
        echo -e "  8. Xóa WP-Cron của một website"
        echo -e ""
        echo -e "  ${CYAN}--- APRG SEO Article Cron (PHP-CLI) ---${NC}"
        echo -e "  9. ${GREEN}Setup APRG Cron${NC} (cron-runner.php — ALL-IN-ONE)"
        echo -e "  10. Xem Log APRG Cron"
        echo -e "  11. Xóa APRG Cron của một website"
        echo -e "  12. Test APRG Cron thủ công (chạy ngay 1 lần)"
        echo -e ""
        echo -e "  ${CYAN}--- Logs & Diagnostics ---${NC}"
        echo -e "  13. Xem Log Cron hệ thống (/var/log/syslog)"
        echo -e "  14. Test thủ công một lệnh cron"
        echo -e "  ${RED}15. 🔍 Chẩn đoán & Dọn dẹp Cron trùng lặp${NC}"
        echo -e "${BLUE}=================================================${NC}"
        echo -e "  0. Quay lại Menu chính"
        echo -e "${BLUE}=================================================${NC}"
        read -p "Nhập lựa chọn [0-15]: " choice

        case $choice in
            1)  list_crons ;;
            2)  add_cron ;;
            3)  delete_one_cron ;;
            4)  delete_all_crons ;;
            5)  edit_cron_manual ;;
            6)  setup_wp_cron_menu ;;
            7)  show_wp_cron_status ;;
            8)  remove_wp_cron ;;
            9)  setup_aprg_cron ;;
            10) view_aprg_log ;;
            11) remove_aprg_cron ;;
            12) test_aprg_cron ;;
            13) view_system_cron_log ;;
            14) test_cron_manually ;;
            15) diagnose_cron_duplicates ;;
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

    # Check duplicate
    if crontab -l 2>/dev/null | grep -qF "$cron_cmd"; then
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
        (crontab -l 2>/dev/null | grep -vF "$target_line") | crontab -
        echo -e "${GREEN}✔ Đã xóa thành công.${NC}"
    else
        echo -e "${YELLOW}Đã hủy.${NC}"
    fi
    pause
}

# ============================================================
# 4. DELETE ALL CRONS
# ============================================================
delete_all_crons() {
    echo ""
    echo -e "${RED}⚠ CẢNH BÁO: Hành động này sẽ XÓA TOÀN BỘ cronjob!${NC}"
    echo -e "${YELLOW}Bao gồm cả WP-Cron và APRG Cron nếu đã thiết lập.${NC}"
    read -p "Gõ 'XOA' để xác nhận (hoặc Enter để hủy): " confirm
    
    if [[ "$confirm" == "XOA" ]]; then
        crontab -r 2>/dev/null
        echo -e "${GREEN}✔ Đã xóa toàn bộ cronjob.${NC}"
    else
        echo -e "${YELLOW}Đã hủy.${NC}"
    fi
    pause
}

# ============================================================
# 5. EDIT CRONTAB MANUALLY
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
    echo -e "${YELLOW}Chọn phương thức Real Cron:${NC}"
    echo ""
    echo -e "  1. ${GREEN}Wget (HTTP)${NC} — Đơn giản, tương thích cao"
    echo -e "     ${CYAN}→ wget -q -O - https://domain.com/wp-cron.php?doing_wp_cron${NC}"
    echo -e "     ${YELLOW}✗ Có thể chậm nếu đang dùng PHP-FPM worker cho AI tasks${NC}"
    echo ""
    echo -e "  2. ${GREEN}WP-CLI --due-now (PHP-CLI)${NC} — Tốt nhất, không qua HTTP"
    echo -e "     ${CYAN}→ wp cron event run --due-now${NC}"
    echo -e "     ${YELLOW}✔ Không chiếm FPM worker, tự động pick up events mới${NC}"
    echo ""
    read -p "Chọn phương thức [1-2]: " wpcron_method

    case $wpcron_method in
        1) _setup_wp_cron_wget ;;
        2) _setup_wp_cron_wpcli ;;
        *) echo -e "${RED}Lựa chọn không hợp lệ.${NC}"; pause ;;
    esac
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

_setup_wp_cron_wget() {
    SELECTED_CRON_DOMAINS=()
    _select_wp_site_for_cron || { pause; return; }

    for domain in "${SELECTED_CRON_DOMAINS[@]}"; do
        # Disable built-in WP-Cron
        local web_root="/var/www/$domain/public_html"
        local wp_config="$web_root/wp-config.php"
        
        # Auto-detect PHP version for this site
        local php_bin="php"
        local site_conf="/etc/nginx/sites-available/$domain"
        if [[ -f "$site_conf" ]]; then
            local php_ver
            php_ver=$(grep -shoP 'php\K[0-9.]+(?=-fpm.sock)' "$site_conf" | head -n 1)
            if [[ -n "$php_ver" ]] && command -v "php$php_ver" &>/dev/null; then
                php_bin="php$php_ver"
            fi
        fi

        # Set DISABLE_WP_CRON via WP-CLI or direct PHP
        if command -v wp &>/dev/null; then
            $php_bin -d display_errors=0 /usr/local/bin/wp config set DISABLE_WP_CRON true --raw --path="$web_root" --allow-root --quiet 2>/dev/null
        elif [[ -f "$wp_config" ]]; then
            if ! grep -q "DISABLE_WP_CRON" "$wp_config"; then
                sed -i "/\/\* That's all, stop editing/i define('DISABLE_WP_CRON', true);" "$wp_config"
            else
                sed -i "s/define.*DISABLE_WP_CRON.*$/define('DISABLE_WP_CRON', true);/" "$wp_config"
            fi
        fi

        # Detect HTTPS/HTTP
        local protocol="https"
        if [[ -f "$site_conf" ]] && ! grep -q "listen 443" "$site_conf"; then
            protocol="http"
        fi

        local croncmd="wget -q -O - ${protocol}://${domain}/wp-cron.php?doing_wp_cron >/dev/null 2>&1"
        local cronjob="* * * * * $croncmd"
        local marker="# WP-CRON: $domain"

        # Remove old WP-Cron entries for this domain  
        (crontab -l 2>/dev/null | grep -v "# WP-CRON: $domain" | grep -v "${domain}/wp-cron.php") | crontab -
        
        # Add new one with marker
        (crontab -l 2>/dev/null; echo "$marker"; echo "$cronjob") | crontab -

        echo -e "${GREEN}✔ [$domain] Đã setup WP-Cron (Wget - 1 phút/lần)${NC}"
        echo -e "   ${CYAN}$croncmd${NC}"
    done
    pause
}

_setup_wp_cron_wpcli() {
    SELECTED_CRON_DOMAINS=()
    _select_wp_site_for_cron || { pause; return; }

    # Ensure WP-CLI is installed
    if ! command -v wp &>/dev/null && [[ ! -f /usr/local/bin/wp ]]; then
        echo -e "${YELLOW}Đang cài WP-CLI...${NC}"
        curl -sO https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar
        chmod +x wp-cli.phar
        mv wp-cli.phar /usr/local/bin/wp
    fi
    local wp_cli_bin
    wp_cli_bin=$(command -v wp 2>/dev/null || echo /usr/local/bin/wp)

    for domain in "${SELECTED_CRON_DOMAINS[@]}"; do
        local web_root="/var/www/$domain/public_html"
        local wp_config="$web_root/wp-config.php"

        # Auto-detect PHP version for this site
        local php_bin="php"
        local site_conf="/etc/nginx/sites-available/$domain"
        if [[ -f "$site_conf" ]]; then
            local php_ver
            php_ver=$(grep -shoP 'php\K[0-9.]+(?=-fpm.sock)' "$site_conf" | head -n 1)
            if [[ -n "$php_ver" ]] && command -v "php$php_ver" &>/dev/null; then
                php_bin="php$php_ver"
            fi
        fi

        # Set DISABLE_WP_CRON via WP-CLI
        $php_bin -d display_errors=0 "$wp_cli_bin" config set DISABLE_WP_CRON true --raw \
            --path="$web_root" --allow-root --quiet 2>/dev/null

        local croncmd="$php_bin -d display_errors=0 $wp_cli_bin cron event run --due-now --path=$web_root --allow-root --quiet >/dev/null 2>&1"
        local cronjob="* * * * * $croncmd"
        local marker="# WP-CRON: $domain"

        # Remove old WP-Cron entries for this domain
        (crontab -l 2>/dev/null | grep -v "# WP-CRON: $domain" | grep -v "cron event run.*$domain") | crontab -

        # Add new with marker
        (crontab -l 2>/dev/null; echo "$marker"; echo "$cronjob") | crontab -

        echo -e "${GREEN}✔ [$domain] Đã setup WP-Cron (WP-CLI --due-now)${NC}"
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

            # Check if in crontab
            local cron_type="none"
            if crontab -l 2>/dev/null | grep -q "# WP-CRON: $domain"; then
                if crontab -l 2>/dev/null | grep -A1 "# WP-CRON: $domain" | grep -q "wp-cron.php"; then
                    cron_type="Wget"
                elif crontab -l 2>/dev/null | grep -A1 "# WP-CRON: $domain" | grep -q "cron event run"; then
                    cron_type="WP-CLI"
                fi
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
        
        # Remove from crontab
        (crontab -l 2>/dev/null | grep -v "# WP-CRON: $domain" | grep -v "${domain}/wp-cron.php" | grep -v "cron event run.*$domain") | crontab -

        # Re-enable WP-Cron built-in
        if command -v wp &>/dev/null && [[ -f "$web_root/wp-config.php" ]]; then
            php -d display_errors=0 /usr/local/bin/wp config set DISABLE_WP_CRON false --raw \
                --path="$web_root" --allow-root --quiet 2>/dev/null
        fi

        echo -e "${GREEN}✔ Đã xóa WP-Cron cho $domain và phục hồi WP built-in cron.${NC}"
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
        local has_wpcli_cron=false
        local has_wget_cron=false
        if crontab -l 2>/dev/null | grep -q "# WP-CRON: $domain"; then
            if crontab -l 2>/dev/null | grep -A1 "# WP-CRON: $domain" | grep -q "cron event run"; then
                has_wpcli_cron=true
            fi
            if crontab -l 2>/dev/null | grep -A1 "# WP-CRON: $domain" | grep -q "wp-cron.php"; then
                has_wget_cron=true
            fi
        fi

        # Cũng check các dòng không có marker (cron cũ từ tay)
        if crontab -l 2>/dev/null | grep -v "^#" | grep -q "cron event run.*$domain"; then
            has_wpcli_cron=true
        fi
        if crontab -l 2>/dev/null | grep -v "^#" | grep -q "$domain/wp-cron.php"; then
            has_wget_cron=true
        fi

        if $has_wpcli_cron || $has_wget_cron; then
            echo -e "${YELLOW}⚠ Phát hiện cron WP trùng lặp với APRG cho $domain:${NC}"
            $has_wpcli_cron && echo -e "   ${RED}✗ WP-CLI cron (--due-now)${NC} — APRG đã thay thế chức năng này"
            $has_wget_cron  && echo -e "   ${RED}✗ Wget cron (wp-cron.php)${NC} — APRG đã thay thế chức năng này"
            echo ""
            echo -e "${CYAN}cron-runner.php đã bao gồm wp_cron() bên trong → giữ chúng sẽ bị trùng.${NC}"
            read -p "Tự động XÓA các cron WP cũ cho $domain? (y/n, KHUYÊN y): " rm_dup
            if [[ "$rm_dup" == "y" || "$rm_dup" == "Y" ]]; then
                # Remove WP-CRON marker block
                (crontab -l 2>/dev/null \
                    | grep -v "# WP-CRON: $domain" \
                    | grep -v "$domain/wp-cron.php" \
                    | grep -v "cron event run.*$domain" \
                ) | crontab -
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
        local php_bin="php"
        local site_conf="/etc/nginx/sites-available/$domain"
        if [[ -f "$site_conf" ]]; then
            local php_ver
            php_ver=$(grep -shoP 'php\K[0-9.]+(?=-fpm.sock)' "$site_conf" | head -n 1)
            if [[ -n "$php_ver" ]] && command -v "php$php_ver" &>/dev/null; then
                php_bin="php$php_ver"
            fi
        fi

        # ── Build & install cron ──────────────────────────────────
        local log_file="/var/log/aprg-cron-$(echo "$domain" | tr '.' '-').log"
        local croncmd="$php_bin -d memory_limit=512M -d max_execution_time=300 -d display_errors=0 $runner_path >> $log_file 2>&1"
        local cronjob="$cron_schedule $croncmd"
        local marker="# APRG-CRON: $domain"

        # Remove old APRG cron entries first
        (crontab -l 2>/dev/null | grep -v "# APRG-CRON: $domain" | grep -v "$runner_path") | crontab -

        # Add new with marker
        (crontab -l 2>/dev/null; echo "$marker"; echo "$cronjob") | crontab -

        # Create log file
        touch "$log_file" 2>/dev/null
        chmod 664 "$log_file" 2>/dev/null

        echo -e "${GREEN}✔ [$domain] Đã setup APRG Cron!${NC}"
        echo -e "   ${CYAN}Schedule:${NC}  $cron_schedule"
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
        (crontab -l 2>/dev/null | grep -v "# APRG-CRON: $domain" | grep -v "aprg-cron-$(echo "$domain" | tr '.' '-')") | crontab -
        echo -e "${GREEN}✔ Đã xóa APRG Cron cho $domain.${NC}"
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
    local aprg_plugin_slug="ai-product-review-generator"
    local runner_path="$web_root/wp-content/plugins/$aprg_plugin_slug/cron-runner.php"

    if [[ ! -f "$runner_path" ]]; then
        echo -e "${RED}❌ Không tìm thấy file: $runner_path${NC}"
        echo -e "${YELLOW}Hãy đảm bảo plugin APRG đã được cài và active.${NC}"
        pause; return
    fi

    # Auto-detect PHP version
    local php_bin="php"
    local site_conf="/etc/nginx/sites-available/$domain"
    if [[ -f "$site_conf" ]]; then
        local php_ver
        php_ver=$(grep -shoP 'php\K[0-9.]+(?=-fpm.sock)' "$site_conf" | head -n 1)
        if [[ -n "$php_ver" ]] && command -v "php$php_ver" &>/dev/null; then
            php_bin="php$php_ver"
        fi
    fi

    echo -e "${CYAN}Đang chạy: $php_bin $runner_path${NC}"
    echo -e "${BLUE}------- Output -------${NC}"
    echo ""

    # Run with output shown directly
    $php_bin -d memory_limit=512M -d max_execution_time=300 -d display_errors=1 "$runner_path" 2>&1

    echo ""
    echo -e "${BLUE}------- End -------${NC}"
    echo -e "${GREEN}✔ Hoàn tất.${NC}"
    pause
}

# ============================================================
# 13. VIEW SYSTEM CRON LOG
# ============================================================
view_system_cron_log() {
    clear
    echo -e "${GREEN}=== Log Cron Hệ thống ===${NC}"
    echo ""

    local log_file="/var/log/syslog"
    if [[ ! -f "$log_file" ]]; then
        log_file="/var/log/cron.log"
    fi

    if [[ ! -f "$log_file" ]]; then
        echo -e "${YELLOW}Không tìm thấy file log hệ thống.${NC}"
        pause; return
    fi

    echo -e "${CYAN}File: $log_file${NC}"
    echo -e "${BLUE}------- 50 dòng CRON gần nhất -------${NC}"
    echo ""
    grep -i "cron\|CRON" "$log_file" | tail -50
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
    echo -e "${BLUE}------ End ------${NC}"
    echo -e "${GREEN}Exit code: $?${NC}"
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
        local has_aprg=false
        local has_wpcli=false
        local has_wget=false

        # Check APRG cron (marker hoặc cron-runner.php path)
        if echo "$current_crontab" | grep -q "# APRG-CRON: $domain"; then
            has_aprg=true
        fi
        if echo "$current_crontab" | grep -v "^#" | grep -q "$domain.*cron-runner\.php"; then
            has_aprg=true
        fi

        # Check WP-CLI cron (marker hoặc pattern)
        if echo "$current_crontab" | grep -A1 "# WP-CRON: $domain" | grep -q "cron event run"; then
            has_wpcli=true
        fi
        if echo "$current_crontab" | grep -v "^#" | grep -q "cron event run.*$domain"; then
            has_wpcli=true
        fi

        # Check Wget cron (marker hoặc pattern)
        if echo "$current_crontab" | grep -A1 "# WP-CRON: $domain" | grep -q "wp-cron.php"; then
            has_wget=true
        fi
        if echo "$current_crontab" | grep -v "^#" | grep -q "$domain/wp-cron.php"; then
            has_wget=true
        fi

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
        local web_root="/var/www/$domain/public_html"
        local aprg_slug="ai-product-review-generator"
        local runner="$web_root/wp-content/plugins/$aprg_slug/cron-runner.php"

        case "$fix_strategy" in
            1)
                # Keep APRG, remove WP-CLI + Wget
                (crontab -l 2>/dev/null \
                    | grep -v "# WP-CRON: $domain" \
                    | grep -v "$domain/wp-cron.php" \
                    | grep -v "cron event run.*$domain" \
                ) | crontab -
                echo -e "${GREEN}✔ [$domain] Đã xóa WP-CLI + Wget. Giữ APRG.${NC}"
                ;;
            2)
                # Keep WP-CLI, remove APRG + Wget
                (crontab -l 2>/dev/null \
                    | grep -v "# APRG-CRON: $domain" \
                    | grep -v "$runner" \
                    | grep -v "$domain/wp-cron.php" \
                ) | crontab -
                echo -e "${GREEN}✔ [$domain] Đã xóa APRG + Wget. Giữ WP-CLI.${NC}"
                ;;
            3)
                # Keep Wget, remove APRG + WP-CLI
                (crontab -l 2>/dev/null \
                    | grep -v "# APRG-CRON: $domain" \
                    | grep -v "$runner" \
                    | grep -v "cron event run.*$domain" \
                ) | crontab -
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

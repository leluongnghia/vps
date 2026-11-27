#!/bin/bash

# modules/ssl.sh - SSL Management (Let's Encrypt)

ssl_menu() {
    while true; do
        clear
        echo -e "${BLUE}=================================================${NC}"
        echo -e "${GREEN}          🔒 Quản lý SSL${NC}"
        echo -e "${BLUE}=================================================${NC}"
        echo -e "1. Xem trạng thái SSL tất cả domain"
        echo -e "2. Cài đặt SSL cho domain"
        echo -e "3. Gia hạn SSL (Renew) - Thủ công"
        echo -e "4. Gia hạn TẤT CẢ SSL"
        echo -e "5. Thu hồi SSL (Revoke)"
        echo -e "6. Bật Auto-Renew (Cron hàng ngày)"
        echo -e "0. Quay lại"
        echo -e "${BLUE}=================================================${NC}"
        read -p "Chọn: " c

        case $c in
            1) ssl_status ;;
            2) install_ssl ;;
            3) ssl_renew_one ;;
            4) ssl_renew_all ;;
            5) ssl_revoke ;;
            6) ssl_auto_renew_setup ;;
            0) return ;;
            *) echo -e "${RED}Sai lựa chọn.${NC}"; pause ;;
        esac
    done
}

ssl_status() {
    echo -e "${CYAN}--- Trạng thái SSL các Domain ---${NC}"
    if ! command -v certbot &>/dev/null; then
        echo -e "${RED}Certbot chưa được cài đặt.${NC}"
        pause; return
    fi

    certbot certificates 2>/dev/null | grep -E "(Found|Domains|Expiry|VALID|INVALID|WARNING)"

    echo -e "\n${YELLOW}--- Kiểm tra chi tiết từng site ---${NC}"
    for site_dir in /var/www/*; do
        if [[ -d "$site_dir" ]]; then
            domain=$(basename "$site_dir")
            [[ "$domain" == "html" ]] && continue

            cert_file="/etc/letsencrypt/live/$domain/fullchain.pem"
            if [[ -f "$cert_file" ]]; then
                expiry=$(openssl x509 -enddate -noout -in "$cert_file" 2>/dev/null | cut -d= -f2)
                expiry_ts=$(date -d "$expiry" +%s 2>/dev/null || date -j -f "%b %d %T %Y %Z" "$expiry" +%s 2>/dev/null)
                now_ts=$(date +%s)
                days_left=$(( (expiry_ts - now_ts) / 86400 ))

                if [[ "$days_left" -gt 30 ]]; then
                    status="${GREEN}✅ OK${NC}"
                elif [[ "$days_left" -gt 7 ]]; then
                    status="${YELLOW}⚠️  Sắp hết hạn (${days_left} ngày)${NC}"
                else
                    status="${RED}🔴 Nguy hiểm! (${days_left} ngày)${NC}"
                fi
                echo -e "  🌐 $domain → $status (hết hạn: $expiry)"
            else
                echo -e "  🌐 $domain → ${RED}Chưa có SSL${NC}"
            fi
        fi
    done
    pause
}

ssl_renew_one() {
    source "$(dirname "${BASH_SOURCE[0]}")/site.sh"
    select_site || return
    domain="$SELECTED_DOMAIN"

    log_info "Đang gia hạn SSL cho $domain..."
    if ! certbot renew --cert-name "$domain" --force-renewal; then
        log_error "Gia hạn SSL cho $domain THẤT BẠI. Xem: /var/log/letsencrypt/letsencrypt.log"
        pause; return 1
    fi
    if nginx_test_reload; then
        log_info "Hoàn tất gia hạn SSL cho $domain."
    else
        log_warn "Đã gia hạn chứng chỉ nhưng Nginx chưa reload được (config lỗi)."
    fi
    pause
}

ssl_renew_all() {
    log_info "Đang gia hạn TẤT CẢ SSL..."
    local rc=0
    certbot renew || rc=$?
    nginx_test_reload || log_warn "Nginx chưa reload được (config lỗi)."
    if [[ $rc -eq 0 ]]; then
        log_info "Hoàn tất gia hạn SSL."
    else
        log_error "Có chứng chỉ gia hạn THẤT BẠI. Xem: /var/log/letsencrypt/letsencrypt.log"
    fi
    pause
}

# Gỡ toàn bộ cấu hình SSL khỏi 1 vhost, đưa về HTTP (port 80).
# Phải chạy TRƯỚC khi xoá chứng chỉ, nếu không vhost sẽ trỏ tới file đã mất
# và lần reload/restart kế tiếp sẽ làm sập mọi site.
_strip_ssl_from_vhost() {
    local conf=$1
    [[ -f "$conf" ]] || return 1
    grep -qE 'listen[[:space:]].*443|ssl_certificate' "$conf" || return 0

    local bak tmp
    bak=$(backup_nginx_config "$conf")
    tmp=$(mktemp) || return 1

    awk '
        function flush_block(   i, has80, is_redirect, has_content) {
            has80 = 0; is_redirect = 0; has_content = 0
            for (i = 1; i <= n; i++) {
                if (buf[i] ~ /return[[:space:]]+404;[[:space:]]*#[[:space:]]*managed by Certbot/) is_redirect = 1
                if (buf[i] ~ /return[[:space:]]+301[[:space:]]+https:\/\//) is_redirect = 1
                if (buf[i] ~ /^[[:space:]]*(root|proxy_pass|fastcgi_pass)[[:space:]]/) has_content = 1
            }
            # Block chỉ dùng để redirect HTTP -> HTTPS: bỏ hẳn
            if (is_redirect && !has_content) { n = 0; return }

            # Bỏ các dòng SSL
            m = 0
            for (i = 1; i <= n; i++) {
                line = buf[i]
                if (line ~ /managed by Certbot/) continue
                if (line ~ /^[[:space:]]*ssl_(certificate|certificate_key|protocols|ciphers|dhparam|prefer_server_ciphers|session_cache|session_timeout|trusted_certificate|stapling|stapling_verify)[[:space:]]/) continue
                if (line ~ /^[[:space:]]*include[[:space:]].*options-ssl-nginx/) continue
                if (line ~ /^[[:space:]]*http2[[:space:]]+on;/) continue
                if (line ~ /^[[:space:]]*listen[[:space:]].*443/) continue
                if (line ~ /^[[:space:]]*listen[[:space:]].*80/) has80 = 1
                out[++m] = line
            }
            for (i = 1; i <= m; i++) {
                print out[i]
                if (i == 1 && !has80) {
                    print "    listen 80;"
                    print "    listen [::]:80;"
                }
            }
            n = 0
        }
        {
            if (depth == 0 && $0 ~ /^[[:space:]]*server[[:space:]]*\{/) { in_server = 1; n = 0 }
            if (in_server) {
                buf[++n] = $0
            } else {
                print
            }
            tmp_line = $0
            opens = gsub(/\{/, "{", tmp_line)
            closes = gsub(/\}/, "}", tmp_line)
            depth += opens - closes
            if (in_server && depth == 0) { flush_block(); in_server = 0 }
        }
        END { if (in_server && n > 0) for (i = 1; i <= n; i++) print buf[i] }
    ' "$conf" > "$tmp"

    if [[ ! -s "$tmp" ]] || ! grep -q "server_name" "$tmp"; then
        rm -f "$tmp" "$bak"
        log_error "Không tự gỡ được cấu hình SSL khỏi $(basename "$conf")."
        return 1
    fi

    # Ghi đè nội dung (giữ nguyên inode/quyền/nhãn SELinux của file gốc)
    cat "$tmp" > "$conf"
    rm -f "$tmp"
    nginx_commit "$conf" "$bak"
}

ssl_revoke() {
    source "$(dirname "${BASH_SOURCE[0]}")/site.sh"
    select_site || return
    domain="$SELECTED_DOMAIN"
    local conf="/etc/nginx/sites-available/$domain"

    echo -e "${YELLOW}Thao tác này sẽ đưa $domain về HTTP (port 80) rồi mới xoá chứng chỉ.${NC}"
    read -p "Xác nhận thu hồi SSL cho $domain? (y/n): " c
    if [[ "$c" == "y" ]]; then
        # Gỡ SSL khỏi vhost TRƯỚC, chỉ xoá cert khi Nginx đã chạy ổn với config HTTP
        if [[ -f "$conf" ]] && ! _strip_ssl_from_vhost "$conf"; then
            log_error "Không gỡ được SSL khỏi vhost - GIỮ NGUYÊN chứng chỉ để tránh làm sập Nginx."
            pause; return 1
        fi
        if certbot delete --cert-name "$domain" --non-interactive; then
            log_info "Đã thu hồi SSL cho $domain (website hiện chạy HTTP)."
        else
            log_error "certbot delete thất bại. Vhost đã về HTTP, chứng chỉ vẫn còn trong /etc/letsencrypt."
        fi
    fi
    pause
}

ssl_auto_renew_setup() {
    clear
    echo -e "${BLUE}=================================================${NC}"
    echo -e "${GREEN}     🔒 Cấu hình Auto-Renew SSL${NC}"
    echo -e "${BLUE}=================================================${NC}"

    # ── Kiểm tra certbot ────────────────────────────────────────
    if ! command -v certbot &>/dev/null; then
        echo -e "${RED}❌ Certbot chưa được cài đặt!${NC}"
        echo -e "${YELLOW}Cài certbot: pkg_install certbot python3-certbot-nginx${NC}"
        pause; return
    fi

    # ── Giải thích cơ chế hoạt động ────────────────────────────
    echo -e "${CYAN}📚 Thông tin về SSL và Auto-Renew:${NC}"
    echo -e ""
    echo -e "  • ${YELLOW}Let's Encrypt / ZeroSSL${NC}: Hết hạn sau ${YELLOW}90 ngày${NC}"
    echo -e "  • ${YELLOW}Certbot${NC} tự động ${GREEN}chỉ renew khi còn < 30 ngày${NC} (không renew sớm)"
    echo -e "  • Chạy cron ${GREEN}hàng ngày${NC} là chuẩn — certbot tự bỏ qua nếu chưa cần"
    echo -e "  • Không gây tốn tài nguyên vì check rất nhanh (~1 giây/cert)"
    echo -e ""
    echo -e "${BLUE}=================================================${NC}"

    # ── Scan tất cả cert hiện có ────────────────────────────────
    echo -e "${CYAN}📋 Trạng thái SSL hiện tại:${NC}"
    echo ""

    local has_cert=0
    local min_days=999
    local urgent_domains=()

    for cert_dir in /etc/letsencrypt/live/*/; do
        [ ! -d "$cert_dir" ] && continue
        local domain
        domain=$(basename "$cert_dir")
        [[ "$domain" == "README" ]] && continue

        local cert_file="$cert_dir/fullchain.pem"
        if [[ ! -f "$cert_file" ]]; then continue; fi

        has_cert=1
        local expiry
        expiry=$(openssl x509 -enddate -noout -in "$cert_file" 2>/dev/null | cut -d= -f2)
        local expiry_ts
        expiry_ts=$(date -d "$expiry" +%s 2>/dev/null || echo 0)
        local now_ts
        now_ts=$(date +%s)
        local days_left=$(( (expiry_ts - now_ts) / 86400 ))
        local issued_ts
        issued_ts=$(openssl x509 -startdate -noout -in "$cert_file" 2>/dev/null | cut -d= -f2)
        issued_ts=$(date -d "$issued_ts" +%s 2>/dev/null || echo 0)
        local total_days=$(( (expiry_ts - issued_ts) / 86400 ))

        # Track minimum days for recommendation
        [ "$days_left" -lt "$min_days" ] && min_days="$days_left"

        # Status indicator
        if [[ "$days_left" -gt 30 ]]; then
            local status="${GREEN}✅ OK${NC}"
        elif [[ "$days_left" -gt 7 ]]; then
            local status="${YELLOW}⚠️  Sắp hết hạn${NC}"
            urgent_domains+=("$domain")
        else
            local status="${RED}🔴 KHẨN CẤP${NC}"
            urgent_domains+=("$domain")
        fi

        printf "  %-35s %s ${CYAN}%d ngày còn lại${NC} / tổng %d ngày\n" \
            "$domain" "$(echo -e "$status")" "$days_left" "$total_days"
    done

    if [[ "$has_cert" -eq 0 ]]; then
        echo -e "  ${YELLOW}Chưa có SSL nào được cài đặt qua certbot.${NC}"
    fi

    echo ""

    # ── Cảnh báo nếu có domain sắp hết ────────────────────────
    if [[ "${#urgent_domains[@]}" -gt 0 ]]; then
        echo -e "${RED}⚠️  Các domain cần renew ngay:${NC}"
        for d in "${urgent_domains[@]}"; do
            echo -e "   → $d"
        done
        echo -e "${YELLOW}Gợi ý: Chạy 'certbot renew' ngay bây giờ (option 4 trong menu SSL)${NC}"
        echo ""
    fi

    # ── Tư vấn lịch cron dựa trên thực tế ──────────────────────
    echo -e "${CYAN}🕐 Khuyến nghị lịch Cron:${NC}"
    echo ""
    if [[ "$has_cert" -eq 0 ]]; then
        echo -e "  • Chưa có cert nào — cron hàng ngày sẵn sàng khi cài SSL"
    elif [[ "$min_days" -gt 60 ]]; then
        echo -e "  • Cert còn > 60 ngày → ${GREEN}Cron hàng ngày (3:00 AM) là tối ưu${NC}"
        echo -e "  • Certbot sẽ tự bỏ qua cho đến khi còn < 30 ngày"
    elif [[ "$min_days" -gt 30 ]]; then
        echo -e "  • Cert còn 30-60 ngày → ${YELLOW}Certbot sẽ renew trong vài ngày tới${NC}"
        echo -e "  • ${GREEN}Cron hàng ngày (3:00 AM) đảm bảo không bỏ lỡ${NC}"
    else
        echo -e "  • Cert còn < 30 ngày → ${RED}Cần renew sớm!${NC}"
        echo -e "  • Bật cron ngay + chạy renew thủ công nếu cần"
    fi

    echo ""
    echo -e "${BLUE}=================================================${NC}"

    # ── Kiểm tra cron hiện tại ──────────────────────────────────
    if crontab -l 2>/dev/null | grep -q "certbot renew"; then
        echo -e "${GREEN}✅ Auto-Renew đã đang chạy:${NC}"
        crontab -l | grep "certbot"
        echo ""
        read -p "Cập nhật lại lịch? (y/n): " c
        if [[ "$c" != "y" ]]; then pause; return; fi
        crontab_remove_containing "certbot renew"
    fi

    # ── Chọn lịch ──────────────────────────────────────────────
    echo -e "Chọn lịch Auto-Renew:"
    echo -e "  1. Hàng ngày lúc ${GREEN}3:00 AM${NC} ${YELLOW}(khuyến nghị - chuẩn certbot)${NC}"
    echo -e "  2. Hàng ngày lúc ${GREEN}2:00 AM${NC}"
    echo -e "  3. 2 lần/ngày (3:00 AM và 3:00 PM) - cho cert sắp hết hạn"
    echo -e "  0. Hủy"
    read -p "Chọn: " sched

    local CRON_TIME CRON_DESC
    case "$sched" in
        1) CRON_TIME="0 3 * * *";     CRON_DESC="Hàng ngày 3:00 AM" ;;
        2) CRON_TIME="0 2 * * *";     CRON_DESC="Hàng ngày 2:00 AM" ;;
        3) CRON_TIME="0 3,15 * * *";  CRON_DESC="2 lần/ngày (3:00 AM & 3:00 PM)" ;;
        0) pause; return ;;
        *) CRON_TIME="0 3 * * *";     CRON_DESC="Hàng ngày 3:00 AM (mặc định)" ;;
    esac

    local CERTBOT_BIN
    CERTBOT_BIN=$(which certbot)
    local CRON_JOB="${CRON_TIME} ${CERTBOT_BIN} renew --quiet --post-hook 'systemctl reload nginx' # ssl-auto-renew"

    (crontab -l 2>/dev/null; echo "$CRON_JOB") | crontab -

    echo ""
    echo -e "${GREEN}✅ Đã bật Auto-Renew SSL!${NC}"
    echo -e "   Lịch: ${CYAN}${CRON_DESC}${NC}"
    echo -e "   Cron: ${CYAN}${CRON_JOB}${NC}"
    echo ""
    echo -e "${YELLOW}💡 Lưu ý:${NC}"
    echo -e "   • Certbot ${GREEN}chỉ renew khi cert còn < 30 ngày${NC} — không bao giờ renew sớm"
    echo -e "   • Sau khi renew, Nginx tự được reload (--post-hook)"
    echo -e "   • Log: ${CYAN}/var/log/letsencrypt/letsencrypt.log${NC}"
    pause
}

# true nếu là domain gốc (apex) - chỉ domain gốc mới thêm www.
# Nhận biết cả đuôi 2 cấp phổ biến (example.com.vn, example.co.uk...)
_ssl_is_apex_domain() {
    local domain="$1" dots
    dots=$(printf '%s' "$domain" | tr -cd '.' | wc -c)
    if [[ "$dots" -eq 1 ]]; then return 0; fi
    if [[ "$dots" -eq 2 ]] && [[ "$domain" =~ \.(com|net|org|edu|gov|biz|info|name|pro|health|int|ac|co)\.[a-z]{2}$ ]]; then
        return 0
    fi
    return 1
}

_ssl_server_names() {
    local domain="$1"
    if _ssl_is_apex_domain "$domain"; then
        echo "$domain www.$domain"
    else
        echo "$domain"
    fi
}

# Danh sách domain sẽ xin chứng chỉ: domain chính, www (nếu là domain gốc VÀ www có DNS),
# cùng các alias đang khai báo trong vhost. In mỗi domain 1 dòng.
_ssl_cert_domains() {
    local domain="$1" conf="/etc/nginx/sites-available/$1" d
    echo "$domain"
    if _ssl_is_apex_domain "$domain"; then
        if getent ahosts "www.$domain" &>/dev/null; then
            echo "www.$domain"
        else
            log_warn "www.$domain chưa có bản ghi DNS - bỏ qua www khi xin chứng chỉ." >&2
        fi
    fi
    # Alias (parked domain) trong server_name
    if [[ -f "$conf" ]]; then
        for d in $(grep -m1 -E '^[[:space:]]*server_name[[:space:]]' "$conf" | sed -E 's/^[[:space:]]*server_name[[:space:]]+//; s/;.*$//'); do
            [[ "$d" == "$domain" || "$d" == "www.$domain" || "$d" == "_" ]] && continue
            [[ "$d" =~ ^[a-zA-Z0-9.-]+$ ]] || continue
            getent ahosts "$d" &>/dev/null && echo "$d"
        done
    fi
}

# nginx >= 1.25.1 dùng directive "http2 on;", bản cũ hơn dùng "listen 443 ssl http2;"
_nginx_has_http2_directive() {
    local v
    v=$(nginx -v 2>&1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
    [[ -n "$v" ]] && [[ "$(printf '%s\n' "1.25.1" "$v" | sort -V | head -1)" == "1.25.1" ]]
}

_apply_manual_ssl_nginx_config() {
    local domain="$1"
    local cert_file="$2"
    local key_file="$3"
    local cipher_line="${4:-}"
    local conf_file="/etc/nginx/sites-available/$domain"

    if [[ ! -f "$conf_file" ]]; then
        echo -e "${RED}Không tìm thấy file cấu hình Nginx!${NC}"
        return 1
    fi

    local backup
    backup=$(backup_nginx_config "$conf_file")

    if ! grep -qE 'listen[[:space:]].*443' "$conf_file"; then
        if _nginx_has_http2_directive; then
            # "http2 on;" chỉ được xuất hiện MỘT lần trong mỗi server block
            sed -i 's/listen \[::\]:80;/listen [::]:443 ssl;/g' "$conf_file"
            if grep -qE '^[[:space:]]*http2[[:space:]]+on;' "$conf_file"; then
                sed -i 's/listen 80;/listen 443 ssl;/g' "$conf_file"
            else
                sed -i 's/listen 80;/listen 443 ssl;\n    http2 on;/g' "$conf_file"
            fi
        else
            sed -i 's/listen 80;/listen 443 ssl http2;/g' "$conf_file"
            sed -i 's/listen \[::\]:80;/listen [::]:443 ssl http2;/g' "$conf_file"
        fi
    fi

    local tmp_file
    tmp_file=$(mktemp)
    awk -v cert="$cert_file" -v key="$key_file" -v cipher="$cipher_line" '
        /^[[:space:]]*ssl_certificate[[:space:]]/ { next }
        /^[[:space:]]*ssl_certificate_key[[:space:]]/ { next }
        /^[[:space:]]*ssl_protocols[[:space:]]/ { next }
        /^[[:space:]]*ssl_ciphers[[:space:]]/ { next }
        {
            if ($0 ~ /^[[:space:]]*server[[:space:]]*\{/) {
                in_server=1
                ssl_server=0
                inserted=0
            }
            if (in_server && $0 ~ /listen[[:space:]].*443/) {
                ssl_server=1
            }

            print

            if (in_server && ssl_server && !inserted && $0 ~ /^[[:space:]]*server_name[[:space:]]/) {
                print "    ssl_certificate " cert ";"
                print "    ssl_certificate_key " key ";"
                print "    ssl_protocols TLSv1.2 TLSv1.3;"
                if (cipher != "") {
                    print "    " cipher
                }
                inserted=1
            }

            if (in_server && $0 ~ /^[[:space:]]*\}/) {
                in_server=0
            }
        }
    ' "$conf_file" > "$tmp_file"
    # Ghi đè nội dung thay vì mv: giữ quyền + nhãn SELinux của file trong /etc/nginx
    cat "$tmp_file" > "$conf_file"
    rm -f "$tmp_file"

    if ! grep -Fq 'return 301 https://$host$request_uri;' "$conf_file"; then
        # server_name của block redirect lấy đúng theo vhost hiện tại (giữ cả alias)
        local names
        names=$(grep -m1 -E '^[[:space:]]*server_name[[:space:]]' "$conf_file" | sed -E 's/^[[:space:]]*server_name[[:space:]]+//; s/;.*$//')
        [[ -z "$names" ]] && names=$(_ssl_server_names "$domain")
        tmp_file=$(mktemp)
        cat <<EOF > "$tmp_file"
server {
    listen 80;
    listen [::]:80;
    server_name $names;
    return 301 https://\$host\$request_uri;
}
EOF
        cat "$conf_file" >> "$tmp_file"
        cat "$tmp_file" > "$conf_file"
        rm -f "$tmp_file"
    fi
    selinux_restore "$conf_file"

    # Test -> reload; lỗi thì tự khôi phục bản backup
    nginx_commit "$conf_file" "$backup"
}



install_ssl() {
    local domain=$1
    if [[ -z "$domain" ]]; then
        # Select site from list
        source "$(dirname "${BASH_SOURCE[0]}")/site.sh"
        select_site || return
        domain=$SELECTED_DOMAIN
    fi

    if [[ ! -d "/var/www/$domain/public_html" ]]; then
        echo -e "${RED}Website $domain chưa được thêm trên VPS này!${NC}"
        pause
        return
    fi

    echo -e "${YELLOW}Chọn loại SSL:${NC}"
    echo -e "1. Let's Encrypt (Certbot - Khuyên dùng)"
    echo -e "2. Cloudflare Origin SSL (Cần copy key từ Cloudflare)"
    echo -e "3. ZeroSSL (Sử dụng acme.sh)"
    read -p "Lựa chọn [1-3]: " ssl_type

    local ssl_rc=0
    case $ssl_type in
        1) install_letsencrypt "$domain" || ssl_rc=1 ;;
        2) install_cloudflare_ssl "$domain" || ssl_rc=1 ;;
        3) install_zerossl "$domain" || ssl_rc=1 ;;
        *) echo -e "${RED}Lựa chọn mặc định Let's Encrypt...${NC}"; install_letsencrypt "$domain" || ssl_rc=1 ;;
    esac

    if [[ -z "$1" ]]; then pause; fi
    return $ssl_rc
}

install_letsencrypt() {
    local domain=$1
    log_info "Đang cài đặt Certbot (Let's Encrypt)..."
    if ! command -v certbot &> /dev/null; then
        pkg_update
        pkg_install certbot python3-certbot-nginx
    fi

    if ! validate_domain "$domain"; then
        return 1
    fi

    log_info "Đang yêu cầu chứng chỉ SSL cho $domain..."
    # Subdomain không thêm www. (thường không có DNS cho www.subdomain); www chỉ thêm khi đã có DNS
    local certbot_args=() d
    while IFS= read -r d; do
        [[ -n "$d" ]] && certbot_args+=(-d "$d")
    done < <(_ssl_cert_domains "$domain")

    if certbot --nginx "${certbot_args[@]}" --cert-name "$domain" --expand --keep-until-expiring \
        --non-interactive --agree-tos --register-unsafely-without-email --redirect; then
        echo -e "${GREEN}Cài đặt SSL Let's Encrypt thành công!${NC}"
        return 0
    else
        echo -e "${RED}Lỗi: Kiểm tra lại DNS hoặc Port 80.${NC}"
        return 1
    fi
}

# Email dùng để đăng ký tài khoản ACME (ZeroSSL bắt buộc email thật). Lưu lại để dùng lần sau.
_ssl_acme_email() {
    local store="$HOME/.vps-manager/acme_email" email=""
    [[ -f "$store" ]] && email=$(head -n1 "$store" 2>/dev/null)
    if [[ ! "$email" =~ ^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$ ]] || [[ "$email" == *@example.com ]]; then
        read -p "Nhập email để đăng ký tài khoản ZeroSSL: " email >&2
        if [[ ! "$email" =~ ^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$ ]] || [[ "$email" == *@example.com ]]; then
            return 1
        fi
        mkdir -p "$(dirname "$store")"
        echo "$email" > "$store"
        chmod 600 "$store"
    fi
    echo "$email"
}

install_zerossl() {
    local domain=$1
    log_info "Đang cài đặt acme.sh cho ZeroSSL..."
    
    if ! validate_domain "$domain"; then
        return 1
    fi

    local acme_email
    if ! acme_email=$(_ssl_acme_email); then
        echo -e "${RED}Email không hợp lệ. Hủy cài ZeroSSL.${NC}"
        return 1
    fi

    # Install acme.sh (tải về file tạm rồi mới chạy, không pipe thẳng vào shell)
    if [[ ! -f ~/.acme.sh/acme.sh ]]; then
        local acme_installer
        acme_installer=$(mktemp)
        if ! safe_download "https://get.acme.sh" "$acme_installer"; then
            rm -f "$acme_installer"
            return 1
        fi
        sh "$acme_installer" "email=$acme_email"
        rm -f "$acme_installer"
        if [[ ! -f ~/.acme.sh/acme.sh ]]; then
            log_error "Cài acme.sh thất bại."
            return 1
        fi
    fi

    # Register ZeroSSL
    if ! ~/.acme.sh/acme.sh --register-account -m "$acme_email" --server zerossl; then
        log_error "Đăng ký tài khoản ZeroSSL thất bại (email: $acme_email)."
        rm -f "$HOME/.vps-manager/acme_email"
        return 1
    fi

    log_info "Đang request chứng chỉ ZeroSSL cho $domain..."

    # Issue cert (using webroot mode /var/www/$domain/public_html or nginx mode)
    # Nginx mode is easier if nginx is running
    local acme_args=() d
    while IFS= read -r d; do
        [[ -n "$d" ]] && acme_args+=(-d "$d")
    done < <(_ssl_cert_domains "$domain")

    local acme_rc=0
    ~/.acme.sh/acme.sh --issue --nginx "${acme_args[@]}" --server zerossl || acme_rc=$?

    # acme.sh trả về 2 khi chứng chỉ còn hạn và được bỏ qua (không phải lỗi)
    if [[ $acme_rc -ne 0 && $acme_rc -ne 2 ]]; then
        echo -e "${RED}Lỗi cấp chứng chỉ ZeroSSL. Kiểm tra DNS!${NC}"
        return 1
    fi

    # Install cert to nginx location
    mkdir -p "/etc/nginx/ssl/$domain"
    chmod 700 "/etc/nginx/ssl/$domain"

    if ! ~/.acme.sh/acme.sh --install-cert -d "$domain" \
        --key-file       "/etc/nginx/ssl/$domain/server.key"  \
        --fullchain-file "/etc/nginx/ssl/$domain/server.crt" \
        --reloadcmd     "systemctl reload nginx" \
        || [[ ! -s "/etc/nginx/ssl/$domain/server.crt" ]]; then
        # reloadcmd có thể lỗi ở lần đầu (vhost chưa trỏ tới cert) - chỉ coi là lỗi khi không có file cert
        if [[ ! -s "/etc/nginx/ssl/$domain/server.crt" || ! -s "/etc/nginx/ssl/$domain/server.key" ]]; then
            log_error "Không cài được chứng chỉ vào /etc/nginx/ssl/$domain."
            return 1
        fi
    fi
    chmod 600 "/etc/nginx/ssl/$domain/server.key" 2>/dev/null
    selinux_restore "/etc/nginx/ssl/$domain"

    log_info "Đang cấu hình Nginx..."

    if _apply_manual_ssl_nginx_config "$domain" "/etc/nginx/ssl/$domain/server.crt" "/etc/nginx/ssl/$domain/server.key"; then
        echo -e "${GREEN}Cài đặt ZeroSSL thành công!${NC}"
        return 0
    else
        echo -e "${RED}Cấu hình Nginx SSL thất bại. Đã khôi phục file backup.${NC}"
        return 1
    fi
}

install_cloudflare_ssl() {
    local domain=$1
    echo -e "${YELLOW}=== Cài đặt Cloudflare Origin SSL ===${NC}"
    echo -e "Bạn cần tạo chứng chỉ trong Cloudflare Dashboard > SSL/TLS > Origin Server"
    
    if ! validate_domain "$domain"; then
        return 1
    fi

    local ssl_dir="/etc/nginx/ssl/$domain"
    mkdir -p "$ssl_dir"
    chmod 700 "$ssl_dir"

    # Ghi ra file tạm trước, chỉ thay file đang dùng khi cert + key hợp lệ và khớp nhau
    local new_crt="$ssl_dir/origin.crt.new" new_key="$ssl_dir/origin.key.new"
    ( umask 077; : > "$new_crt"; : > "$new_key" )

    echo -e "Dán nội dung CERTIFICATE (dòng bắt đầu -----BEGIN CERTIFICATE-----):"
    echo -e "(Sau khi dán xong, nhấn Enter, rồi nhấn Ctrl+D)"
    cat > "$new_crt"

    echo -e "Dán nội dung PRIVATE KEY (dòng bắt đầu -----BEGIN PRIVATE KEY-----):"
    echo -e "(Sau khi dán xong, nhấn Enter, rồi nhấn Ctrl+D)"
    cat > "$new_key"
    chmod 600 "$new_key"

    if ! openssl x509 -noout -in "$new_crt" 2>/dev/null; then
        echo -e "${RED}CERTIFICATE không hợp lệ. Hủy, giữ nguyên cấu hình hiện tại.${NC}"
        rm -f "$new_crt" "$new_key"
        return 1
    fi
    if ! openssl pkey -noout -in "$new_key" 2>/dev/null; then
        echo -e "${RED}PRIVATE KEY không hợp lệ. Hủy, giữ nguyên cấu hình hiện tại.${NC}"
        rm -f "$new_crt" "$new_key"
        return 1
    fi
    local crt_pub key_pub
    crt_pub=$(openssl x509 -noout -pubkey -in "$new_crt" 2>/dev/null | openssl sha256 2>/dev/null)
    key_pub=$(openssl pkey -pubout -in "$new_key" 2>/dev/null | openssl sha256 2>/dev/null)
    if [[ -z "$crt_pub" || "$crt_pub" != "$key_pub" ]]; then
        echo -e "${RED}CERTIFICATE và PRIVATE KEY không khớp nhau. Hủy.${NC}"
        rm -f "$new_crt" "$new_key"
        return 1
    fi
    mv -f "$new_crt" "$ssl_dir/origin.crt"
    mv -f "$new_key" "$ssl_dir/origin.key"
    chmod 644 "$ssl_dir/origin.crt"
    chmod 600 "$ssl_dir/origin.key"
    selinux_restore "$ssl_dir"

    log_info "Đang cấu hình Nginx sử dụng Cloudflare SSL..."
    
    if _apply_manual_ssl_nginx_config "$domain" "/etc/nginx/ssl/$domain/origin.crt" "/etc/nginx/ssl/$domain/origin.key" "ssl_ciphers HIGH:!aNULL:!MD5;"; then
        echo -e "${GREEN}Đã cài đặt Cloudflare Origin SSL thành công!${NC}"
        echo -e "Lưu ý: Trên Cloudflare hãy chọn chế độ SSL là 'Full (Strict)'"
        return 0
    else
        echo -e "${RED}Cấu hình Nginx SSL thất bại. Đã khôi phục file backup.${NC}"
        return 1
    fi
}

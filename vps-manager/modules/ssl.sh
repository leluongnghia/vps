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
    certbot renew --cert-name "$domain" --force-renewal
    nginx -t && systemctl reload nginx
    log_info "Hoàn tất gia hạn SSL cho $domain."
    pause
}

ssl_renew_all() {
    log_info "Đang gia hạn TẤT CẢ SSL..."
    certbot renew
    nginx -t && systemctl reload nginx
    log_info "Hoàn tất gia hạn SSL."
    pause
}

ssl_revoke() {
    source "$(dirname "${BASH_SOURCE[0]}")/site.sh"
    select_site || return
    domain="$SELECTED_DOMAIN"

    read -p "Xác nhận thu hồi SSL cho $domain? (y/n): " c
    if [[ "$c" == "y" ]]; then
        certbot delete --cert-name "$domain"
        log_info "Đã thu hồi SSL cho $domain."
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
        echo -e "${YELLOW}Cài certbot: apt-get install -y certbot python3-certbot-nginx${NC}"
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
        crontab -l | grep -v "certbot" | crontab -
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

    case $ssl_type in
        1) install_letsencrypt "$domain" ;;
        2) install_cloudflare_ssl "$domain" ;;
        3) install_zerossl "$domain" ;;
        *) echo -e "${RED}Lựa chọn mặc định Let's Encrypt...${NC}"; install_letsencrypt "$domain" ;;
    esac
    
    if [[ -z "$1" ]]; then pause; fi
}

install_letsencrypt() {
    local domain=$1
    log_info "Đang cài đặt Certbot (Let's Encrypt)..."
    if ! command -v certbot &> /dev/null; then
        apt-get update
        apt-get install -y certbot python3-certbot-nginx
    fi

    log_info "Đang yêu cầu chứng chỉ SSL cho $domain..."
    # Subdomain (>1 dấu chấm) thì không thêm www. vì thường không có DNS cho www.subdomain
    local certbot_domains="-d \"$domain\""
    if [[ $(echo "$domain" | tr -cd '.' | wc -c) -eq 1 ]]; then
        certbot_domains="-d \"$domain\" -d \"www.$domain\""
    fi
    eval certbot --nginx $certbot_domains --non-interactive --agree-tos --register-unsafely-without-email --redirect

    if [[ $? -eq 0 ]]; then
        echo -e "${GREEN}Cài đặt SSL Let's Encrypt thành công!${NC}"
    else
        echo -e "${RED}Lỗi: Kiểm tra lại DNS hoặc Port 80.${NC}"
    fi
}

install_zerossl() {
    local domain=$1
    log_info "Đang cài đặt acme.sh cho ZeroSSL..."
    
    # Install acme.sh
    if [[ ! -f ~/.acme.sh/acme.sh ]]; then
        curl https://get.acme.sh | sh -s email=my@example.com
    fi
    
    # Register ZeroSSL
    ~/.acme.sh/acme.sh --register-account -m my@example.com --server zerossl
    
    log_info "Đang request chứng chỉ ZeroSSL cho $domain..."
    
    # Issue cert (using webroot mode /var/www/$domain/public_html or nginx mode)
    # Nginx mode is easier if nginx is running
    local acme_domains="-d \"$domain\""
    if [[ $(echo "$domain" | tr -cd '.' | wc -c) -eq 1 ]]; then
        acme_domains="-d \"$domain\" -d \"www.$domain\""
    fi
    eval ~/.acme.sh/acme.sh --issue --nginx $acme_domains --server zerossl
    
    if [[ $? -ne 0 ]]; then
        echo -e "${RED}Lỗi cấp chứng chỉ ZeroSSL. Kiểm tra DNS!${NC}"
        return
    fi
    
    # Install cert to nginx location
    mkdir -p "/etc/nginx/ssl/$domain"
    
    ~/.acme.sh/acme.sh --install-cert -d "$domain" \
        --key-file       "/etc/nginx/ssl/$domain/server.key"  \
        --fullchain-file "/etc/nginx/ssl/$domain/server.crt" \
        --reloadcmd     "service nginx force-reload"
        
    log_info "Đang cấu hình Nginx..."
    
    conf_file="/etc/nginx/sites-available/$domain"
    # Backup
    cp "$conf_file" "${conf_file}.bak"
    
    # Configure SSL in Nginx (Similar logic to Cloudflare, switch port and paths)
    sed -i 's/listen 80;/listen 443 ssl http2;/g' "$conf_file"
    sed -i 's/listen \[::\]:80;/listen [::]:443 ssl http2;/g' "$conf_file"
    
    # Add SSL block
    sed -i "/server_name .*/a \    ssl_certificate /etc/nginx/ssl/$domain/server.crt;\n    ssl_certificate_key /etc/nginx/ssl/$domain/server.key;\n    ssl_protocols TLSv1.2 TLSv1.3;" "$conf_file"
    
    # Add Redirect Block (Prepend)
    tmp_file=$(mktemp)
    cat <<EOF > "$tmp_file"
server {
    listen 80;
    server_name $domain www.$domain;
    return 301 https://\$host\$request_uri;
}
EOF
    cat "$conf_file" >> "$tmp_file"
    mv "$tmp_file" "$conf_file"
    
    nginx -t && systemctl reload nginx
    echo -e "${GREEN}Cài đặt ZeroSSL thành công!${NC}"
}

install_cloudflare_ssl() {
    local domain=$1
    echo -e "${YELLOW}=== Cài đặt Cloudflare Origin SSL ===${NC}"
    echo -e "Bạn cần tạo chứng chỉ trong Cloudflare Dashboard > SSL/TLS > Origin Server"
    
    mkdir -p "/etc/nginx/ssl/$domain"
    
    echo -e "Dán nội dung CERTIFICATE (dòng bắt đầu -----BEGIN CERTIFICATE-----):"
    echo -e "(Sau khi dán xong, nhấn Enter, rồi nhấn Ctrl+D)"
    cat > "/etc/nginx/ssl/$domain/origin.crt"
    
    echo -e "Dán nội dung PRIVATE KEY (dòng bắt đầu -----BEGIN PRIVATE KEY-----):"
    echo -e "(Sau khi dán xong, nhấn Enter, rồi nhấn Ctrl+D)"
    cat > "/etc/nginx/ssl/$domain/origin.key"
    
    log_info "Đang cấu hình Nginx sử dụng Cloudflare SSL..."
    
    # Update Nginx Config
    conf_file="/etc/nginx/sites-available/$domain"
    
    # Check if config exists
    if [[ ! -f "$conf_file" ]]; then
        echo -e "${RED}Không tìm thấy file cấu hình Nginx!${NC}"
        return
    fi
    
    # Replace listen 80 with ssl configuration
    # Simple substitution strategy for this script context
    # Ideally should use template, but sed is quick fix for existing file
    
    # Backup
    cp "$conf_file" "${conf_file}.bak"
    
    # We need to construct a new server block or modify existing.
    # To keep it simple and robust, let's regenerate the config with SSL enabled directly.
    # Re-using logic from site.sh would be cleaner but cross-module calls are tricky with local vars.
    # Let's Modify existing file 
    
    # 1. Change listen port
    sed -i 's/listen 80;/listen 443 ssl http2;/g' "$conf_file"
    sed -i 's/listen \[::\]:80;/listen [::]:443 ssl http2;/g' "$conf_file"
    
    # 2. Add SSL paths inside server block (after server_name)
    sed -i "/server_name .*/a \    ssl_certificate /etc/nginx/ssl/$domain/origin.crt;\n    ssl_certificate_key /etc/nginx/ssl/$domain/origin.key;\n    ssl_protocols TLSv1.2 TLSv1.3;\n    ssl_ciphers HIGH:!aNULL:!MD5;" "$conf_file"
    
    # 3. Add HTTP redirect block at the top
    # Prepend redirect server block
    tmp_file=$(mktemp)
    cat <<EOF > "$tmp_file"
server {
    listen 80;
    server_name $domain www.$domain;
    return 301 https://\$host\$request_uri;
}
EOF
    cat "$conf_file" >> "$tmp_file"
    mv "$tmp_file" "$conf_file"
    
    nginx -t && systemctl reload nginx
    echo -e "${GREEN}Đã cài đặt Cloudflare Origin SSL thành công!${NC}"
    echo -e "Lưu ý: Trên Cloudflare hãy chọn chế độ SSL là 'Full (Strict)'"
}

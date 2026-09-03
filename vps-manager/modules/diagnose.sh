#!/bin/bash

# modules/diagnose.sh - Comprehensive System Health Check & Diagnosis

diagnose_system() {
    clear
    echo -e "${BLUE}=================================================${NC}"
    echo -e "${GREEN}       🏥 KIỂM TRA SỨC KHỎE TỔNG QUÁT HỆ THỐNG${NC}"
    echo -e "${BLUE}=================================================${NC}"
    local has_error=0
    
    # 1. OS & Kernel
    echo -e "${YELLOW}1. THÔNG TIN HỆ THỐNG & TÀI NGUYÊN:${NC}"
    local os_pretty
    if [[ -f /etc/os-release ]]; then
        os_pretty=$(grep -oP 'PRETTY_NAME="\K[^"]+' /etc/os-release 2>/dev/null || cat /etc/os-release | grep "PRETTY_NAME=" | cut -d= -f2 | tr -d '"')
    fi
    [[ -z "$os_pretty" ]] && os_pretty=$(lsb_release -d 2>/dev/null | cut -f2 || uname -s)
    echo -e "   • Hệ điều hành : ${CYAN}$os_pretty${NC}"
    echo -e "   • Nhân Kernel  : $(uname -r)"
    echo -e "   • Thời gian bật: $(uptime -p 2>/dev/null || uptime)"
    
    # Resources
    free -h | awk '/^Mem:/ {print "   • Bộ nhớ RAM   : Dùng " $3 " / Còn trống " $7 " / Tổng " $2}'
    free -h | awk '/^Swap:/ {print "   • Bộ nhớ Swap  : Dùng " $3 " / Tổng " $2}'
    df -h / | awk 'NR==2 {print "   • Ổ cứng (/)   : Dùng " $3 " (" $5 ") / Còn trống " $4 " / Tổng " $2}'
    
    # 2. Services Status
    echo -e "\n${YELLOW}2. TRẠNG THÁI DỊCH VỤ CỐT LÕI:${NC}"
    check_service_status "nginx" "Web Server (Nginx)"
    check_service_status "mariadb" "Database (MariaDB)" || check_service_status "mysql" "Database (MySQL)"
    
    # Check PHP versions
    local found_php=0
    for ver in 7.4 8.0 8.1 8.2 8.3 8.4; do
        if systemctl list-units --full -all 2>/dev/null | grep -qE "php$ver-fpm|php${ver//./}-php-fpm"; then
            check_service_status "php$ver-fpm" "PHP $ver FPM" || check_service_status "php${ver//./}-php-fpm" "PHP $ver FPM"
            found_php=1
        fi
    done
    [[ "$found_php" -eq 0 ]] && check_service_status "php-fpm" "PHP-FPM (Default)"

    # Check Cache service
    for c_svc in valkey keydb redis-server redis; do
        if systemctl is-active --quiet "$c_svc" 2>/dev/null || systemctl is-enabled --quiet "$c_svc" 2>/dev/null; then
            check_service_status "$c_svc" "Object Cache ($c_svc)"
            break
        fi
    done

    # Security Services
    check_service_status "ssh" "SSH Service" || check_service_status "sshd" "SSH Service"
    check_service_status "fail2ban" "Fail2ban Security"
    
    # Firewall Status (UFW or Firewalld)
    echo -n "   • Firewall       : "
    if command -v ufw &>/dev/null && ufw status 2>/dev/null | grep -q "Status: active"; then
        echo -e "${GREEN}BẬT (UFW Active)${NC}"
    elif command -v firewall-cmd &>/dev/null && firewall-cmd --state 2>/dev/null | grep -q "running"; then
        echo -e "${GREEN}BẬT (Firewalld Running)${NC}"
    else
        echo -e "${YELLOW}TẮT (Firewall Inactive)${NC}"
    fi

    # 3. Open Ports Listening Check
    echo -e "\n${YELLOW}3. CÁC CỔNG MẠNG ĐANG LẮNG NGHE (LISTENING PORTS):${NC}"
    if command -v ss &>/dev/null; then
        ss -tulpn 2>/dev/null | grep LISTEN | awk '{split($5, a, ":"); port=a[length(a)]; split($7, p, "/"); proc=p[1]; sub(/.*users:\(\("/, "", proc); sub(/".*/, "", proc); printf "   • Port %-7s (%-4s) → Tiến trình: %s\n", port, $1, proc}' | sort -n -k3 | head -n 12
    elif command -v netstat &>/dev/null; then
        netstat -tulpn 2>/dev/null | grep LISTEN | awk '{split($4, a, ":"); port=a[length(a)]; split($7, p, "/"); proc=p[2]; printf "   • Port %-7s (%-4s) → Tiến trình: %s\n", port, $1, proc}' | head -n 12
    else
        echo "   (Cần ss hoặc netstat để xem port)"
    fi

    # 4. Deep Checks
    echo -e "\n${YELLOW}4. KIỂM TRA CHỨC NĂNG CỐT LÕI:${NC}"
    
    # Nginx Config
    echo -n "   • Cú pháp Nginx       : "
    if nginx -t &>/dev/null; then
        echo -e "${GREEN}OK (Hợp lệ, không có lỗi cú pháp)${NC}"
    else
        echo -e "${RED}LỖI CÚ PHÁP!${NC}"
        nginx -t
        has_error=1
    fi
    
    # Database Connection
    echo -n "   • Kết nối Database    : "
    if mysqladmin ping &>/dev/null || mariadb-admin ping &>/dev/null; then
        echo -e "${GREEN}OK (MariaDB phản hồi tốt)${NC}"
    else
        echo -e "${RED}LỖI (Không kết nối được)${NC}"
        has_error=1
    fi
    
    # Web Response
    echo -n "   • Web Localhost (HTTP): "
    local http_code
    http_code=$(curl -s -o /dev/null -w "%{http_code}" 127.0.0.1 2>/dev/null || echo "000")
    if [[ "$http_code" =~ ^(200|301|302|403|404)$ ]]; then
       echo -e "${GREEN}OK (Mã phản hồi HTTP: $http_code)${NC}"
    else
       echo -e "${YELLOW}Cảnh báo (Mã HTTP: $http_code - Kiểm tra lại vhost)${NC}"
    fi

    # 5. SSL Expiration Scan
    echo -e "\n${YELLOW}5. KIỂM TRA THỜI HẠN CHỨNG CHỈ SSL:${NC}"
    local found_ssl=0
    if [[ -d /etc/letsencrypt/live ]]; then
        for cert_dir in /etc/letsencrypt/live/*/; do
            [[ ! -d "$cert_dir" ]] && continue
            local d_name
            d_name=$(basename "$cert_dir")
            [[ "$d_name" == "README" ]] && continue
            local cert_f="$cert_dir/fullchain.pem"
            if [[ -f "$cert_f" ]]; then
                found_ssl=1
                local exp_date exp_ts now_ts days_rem
                exp_date=$(openssl x509 -enddate -noout -in "$cert_f" 2>/dev/null | cut -d= -f2)
                exp_ts=$(date -d "$exp_date" +%s 2>/dev/null || date -j -f "%b %d %T %Y %Z" "$exp_date" +%s 2>/dev/null || echo 0)
                now_ts=$(date +%s)
                days_rem=$(( (exp_ts - now_ts) / 86400 ))

                if [[ "$days_rem" -gt 30 ]]; then
                    printf "   • %-30s : ${GREEN}✅ Còn %2d ngày${NC} (Hạn: %s)\n" "$d_name" "$days_rem" "$exp_date"
                elif [[ "$days_rem" -gt 7 ]]; then
                    printf "   • %-30s : ${YELLOW}⚠️  Sắp hết hạn (%2d ngày)${NC}\n" "$d_name" "$days_rem"
                else
                    printf "   • %-30s : ${RED}🔴 KHẨN CẤP (%2d ngày - Cần renew ngay!)${NC}\n" "$d_name" "$days_rem"
                    has_error=1
                fi
            fi
        done
    fi
    if [[ "$found_ssl" -eq 0 ]]; then
        echo -e "   • Chưa phát hiện chứng chỉ Let's Encrypt nào."
    fi

    # 6. Log Summary
    echo -e "\n${YELLOW}6. LOG LỖI NGINX GẦN NHẤT (10 dòng):${NC}"
    if [[ -f /var/log/nginx/error.log ]]; then
        tail -n 10 /var/log/nginx/error.log | sed 's/^/   /'
    else
        echo "   (Không tìm thấy file log)"
    fi
    
    echo -e "\n${BLUE}=================================================${NC}"
    if [[ "$has_error" -eq 1 ]]; then
        echo -e "${RED}⚠️  HỆ THỐNG CÓ LỖI HOẶC CHỨNG CHỈ CẦN KHẮC PHỤC NGAY!${NC}"
    else
        echo -e "${GREEN}✅ HỆ THỐNG HOẠT ĐỘNG HOÀN TOÀN ỔN ĐỊNH VÀ KHỎE MẠNH!${NC}"
    fi
    echo -e "${BLUE}=================================================${NC}"
    
    pause
}

check_service_status() {
    local service=$1
    local name=$2
    if systemctl is-active --quiet "$service" 2>/dev/null; then
        printf "   • %-26s: ${GREEN}RUNNING${NC}\n" "$name"
        return 0
    else
        if systemctl is-enabled --quiet "$service" 2>/dev/null; then
             printf "   • %-26s: ${RED}STOPPED (Nhưng đang Enable)${NC}\n" "$name"
        else
             printf "   • %-26s: ${GRAY}NOT RUNNING / NOT INSTALLED${NC}\n" "$name"
        fi
        return 1
    fi
}


#!/bin/bash

# core/stack_install.sh - Cài đặt toàn bộ LEMP stack (một nguồn duy nhất)
# Dùng chung cho cả `install.sh` (Auto-Install lần đầu) và `install-nginx.sh` (cài nhanh 1 lệnh).
#
# Dùng: run_stack_install <php_ver> <cache_type>
#   php_ver    : 8.1 | 8.2 | 8.3 | 8.4            (mặc định 8.4)
#   cache_type : valkey | redis | none     (mặc định valkey; tự lùi về redis nếu OS chưa có gói valkey)
# Trả về 0 nếu các thành phần BẮT BUỘC (Nginx, MariaDB, PHP) cài xong, 1 nếu có thành phần bắt buộc lỗi.

run_stack_install() {
    local php_ver="${1:-8.4}"
    local cache_type="${2:-valkey}"
    local root_dir
    root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

    # Các module gọi `pause` ở cuối; khi cài tự động thì không dừng chờ Enter
    local prev_nonint="${VPSM_NONINTERACTIVE:-}"
    export VPSM_NONINTERACTIVE=1

    source "$root_dir/core/kernel_tuning.sh"
    source "$root_dir/modules/lemp.sh"
    source "$root_dir/modules/zram.sh"
    source "$root_dir/modules/phpmyadmin.sh"
    source "$root_dir/modules/security.sh"

    local -a failed=() warned=()
    local step=0 total=9

    _stack_step() { step=$((step + 1)); echo -e "${BLUE}[${step}/${total}] $1${NC}"; }

    _stack_step "Thiết lập ZRAM Swap..."
    zram_install "auto" || warned+=("ZRAM (giữ nguyên swap hiện có)")

    _stack_step "Tối ưu Kernel / TCP / giới hạn file..."
    run_system_optimization || warned+=("Kernel tuning")

    _stack_step "Cài đặt Nginx..."
    install_nginx
    command -v nginx &>/dev/null && systemctl is-active --quiet nginx || failed+=("Nginx")

    _stack_step "Cài đặt MariaDB..."
    install_mariadb
    systemctl is-active --quiet "$(mariadb_service_name)" || failed+=("MariaDB")

    _stack_step "Cài đặt PHP ${php_ver}..."
    install_php "$php_ver"
    detect_php_socket &>/dev/null || failed+=("PHP-FPM ${php_ver}")

    _stack_step "Cài đặt phpMyAdmin..."
    if [[ " ${failed[*]} " == *"PHP-FPM"* || " ${failed[*]} " == *"Nginx"* ]]; then
        warned+=("phpMyAdmin (bỏ qua vì Nginx/PHP chưa chạy)")
    else
        install_phpmyadmin || warned+=("phpMyAdmin")
    fi

    _stack_step "Cài đặt Object Cache (${cache_type})..."
    case "$cache_type" in
        valkey|redis) _install_object_cache_nginx "$cache_type" || warned+=("Object cache ${cache_type}") ;;
        *) echo -e "${YELLOW}Bỏ qua Object Cache. Chỉ dùng Nginx FastCGI Cache.${NC}" ;;
    esac

    _stack_step "Cấu hình Firewall + Fail2ban..."
    setup_firewall "auto" || warned+=("Firewall")

    _stack_step "Ổn định & tốc độ (tự phục hồi dịch vụ, cập nhật bảo mật, slow log, OPcache)..."
    if [[ ${#failed[@]} -eq 0 ]]; then
        source "$root_dir/modules/wordpress_performance.sh"
        optimize_opcache "auto" || warned+=("OPcache")
        run_reliability_setup || warned+=("Gói ổn định")
    else
        warned+=("Gói ổn định (bỏ qua vì stack chưa cài xong)")
    fi

    unset -f _stack_step
    if [[ -n "$prev_nonint" ]]; then export VPSM_NONINTERACTIVE="$prev_nonint"; else unset VPSM_NONINTERACTIVE; fi

    mkdir -p "$HOME/.vps-manager"

    echo ""
    echo -e "${BLUE}=================================================${NC}"
    if [[ ${#failed[@]} -gt 0 ]]; then
        echo -e "${RED}Cài đặt CHƯA hoàn tất. Thành phần bắt buộc bị lỗi:${NC}"
        printf '   ✗ %s\n' "${failed[@]}"
    else
        echo -e "${GREEN}LEMP Stack đã cài xong: Nginx + MariaDB + PHP ${php_ver}.${NC}"
    fi
    if [[ ${#warned[@]} -gt 0 ]]; then
        echo -e "${YELLOW}Thành phần phụ chưa cài được (có thể cài lại từ menu):${NC}"
        printf '   ! %s\n' "${warned[@]}"
    fi
    echo -e "Nhật ký chi tiết: ${LOG_FILE:-/var/log/vps-manager.log}"
    echo -e "${BLUE}=================================================${NC}"

    [[ ${#failed[@]} -eq 0 ]]
}

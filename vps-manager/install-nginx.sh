#!/bin/bash

# =============================================================================
# VPS Manager — Cài đặt nhanh LEMP Stack (Nginx + MariaDB + PHP)
# =============================================================================
# Sử dụng:
#   bash <(curl -s https://raw.githubusercontent.com/leluongnghia/vps/main/vps-manager/install-nginx.sh)
#   bash <(wget -qO- https://raw.githubusercontent.com/leluongnghia/vps/main/vps-manager/install-nginx.sh)
# =============================================================================

set -euo pipefail

# ── Colors ────────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'

INSTALL_DIR="/usr/local/vps-manager"
REPO_URL="https://github.com/leluongnghia/vps.git"
BRANCH="main"

# ── Root check ────────────────────────────────────────────────────────────────
if [[ "$EUID" -ne 0 ]]; then
    echo -e "${RED}[✗] Vui lòng chạy với quyền root (sudo su hoặc sudo bash ...)${NC}"
    exit 1
fi

echo -e "${BLUE}"
echo "╔══════════════════════════════════════════════════════╗"
echo "║   🌐  VPS Manager — Cài đặt LEMP Stack (Nginx)      ║"
echo "║   Nginx + MariaDB + PHP-FPM + phpMyAdmin + Valkey    ║"
echo "╚══════════════════════════════════════════════════════╝"
echo -e "${NC}"

# ── Step 1: Install base dependencies ─────────────────────────────────────────
echo -e "${CYAN}[1/5] Kiểm tra và cài đặt các gói phụ thuộc cơ bản...${NC}"
if [[ -f /etc/redhat-release ]]; then
    dnf install -y curl wget git unzip tar socat cronie &>/dev/null
else
    apt-get update -qq
    apt-get install -y curl wget git unzip tar socat cron lsb-release &>/dev/null
fi
echo -e "${GREEN}  ✓ Xong${NC}"

# ── Step 2: Clone/update VPS Manager ──────────────────────────────────────────
echo -e "${CYAN}[2/5] Tải VPS Manager từ GitHub...${NC}"
TEMP_DIR=$(mktemp -d)
git clone -b "$BRANCH" --depth 1 "$REPO_URL" "$TEMP_DIR/vps-repo" &>/dev/null || {
    echo -e "${RED}[✗] Không thể clone repo. Kiểm tra kết nối mạng.${NC}"
    rm -rf "$TEMP_DIR"; exit 1
}

BACKUP_DIR="${INSTALL_DIR}_backup_$(date +%s)"
cd /tmp
[[ -d "$INSTALL_DIR" ]] && mv "$INSTALL_DIR" "$BACKUP_DIR"
mkdir -p "$INSTALL_DIR"
cp -r "$TEMP_DIR/vps-repo/vps-manager/"* "$INSTALL_DIR/"
rm -rf "$TEMP_DIR"

chmod +x "$INSTALL_DIR/install.sh"
find "$INSTALL_DIR" -name "*.sh" -exec chmod +x {} \;
ln -sf "$INSTALL_DIR/install.sh" /usr/local/bin/vps
[[ -d "$BACKUP_DIR" ]] && rm -rf "$BACKUP_DIR"
echo -e "${GREEN}  ✓ VPS Manager đã được tải về: $INSTALL_DIR${NC}"

# ── Step 3: Load core & modules ───────────────────────────────────────────────
echo -e "${CYAN}[3/5] Khởi tạo môi trường...${NC}"
cd "$INSTALL_DIR"
source core/utils.sh
source core/system_helpers.sh
source core/kernel_tuning.sh 2>/dev/null || true
source modules/lemp.sh
source modules/wordpress_performance.sh 2>/dev/null || true
source modules/phpmyadmin.sh 2>/dev/null || true

# Detect OS
if [[ -f /etc/os-release ]]; then
    . /etc/os-release
    if [[ "$ID" == "ubuntu" || "$ID" == "debian" ]]; then
        OS_FAMILY="debian"
    elif [[ "$ID" == "almalinux" || "$ID" == "rocky" || "$ID" == "rhel" || "$ID" == "centos" ]]; then
        OS_FAMILY="rhel"
    else
        OS_FAMILY="debian"
    fi
else
    OS_FAMILY="debian"
fi
export OS_FAMILY
echo -e "${GREEN}  ✓ OS: $ID $VERSION_ID ($OS_FAMILY)${NC}"

# ── Step 4: Install stack ──────────────────────────────────────────────────────
echo -e "${CYAN}[4/5] Bắt đầu cài đặt LEMP Stack...${NC}"
echo ""

# ZRAM
if [[ -f "$INSTALL_DIR/modules/zram.sh" ]]; then
    source "$INSTALL_DIR/modules/zram.sh"
    log_info "Thiết lập ZRAM Swap..."
    zram_install "auto"
fi

# =============================================================================
# ── Tối ưu hóa hệ thống (Kernel / TCP / THP / CPU) ──
# Giống như OLS stack — kernel tuning là cấp server, không phụ thuộc webserver
# =============================================================================
echo -e "${CYAN}[3.5/5] Tối ưu Kernel + TCP + THP + File Limits...${NC}"
if type run_system_optimization &>/dev/null; then
    run_system_optimization
else
    echo never > /sys/kernel/mm/transparent_hugepage/enabled 2>/dev/null || true
    echo never > /sys/kernel/mm/transparent_hugepage/defrag  2>/dev/null || true
    ulimit -n 524288 2>/dev/null || true
    # Bật BBR nếu chưa có
    if ! sysctl net.ipv4.tcp_congestion_control 2>/dev/null | grep -q bbr; then
        modprobe tcp_bbr 2>/dev/null || true
        echo "net.core.default_qdisc=fq"            >> /etc/sysctl.d/101-vps-manager.conf 2>/dev/null || true
        echo "net.ipv4.tcp_congestion_control=bbr"  >> /etc/sysctl.d/101-vps-manager.conf 2>/dev/null || true
        sysctl --system > /dev/null 2>&1 || true
    fi
fi
echo -e "${GREEN}  ✓ Tối ưu hóa hệ thống hoàn tất${NC}"

log_info "Cài đặt Nginx..."
install_nginx

log_info "Cài đặt MariaDB..."
install_mariadb

echo ""
echo -e "${YELLOW}Chọn phiên bản PHP chính (mặc định: 8.3):${NC}"
echo "  1. PHP 8.3 (Khuyên dùng)"
echo "  2. PHP 8.4 (Mới nhất)"
echo "  3. PHP 8.2"
echo "  4. PHP 8.1"
read -t 10 -p "Chọn [1-4, Enter = 8.3]: " php_choice || php_choice=""
case "$php_choice" in
    2) PHP_VER="8.4" ;;
    3) PHP_VER="8.2" ;;
    4) PHP_VER="8.1" ;;
    *) PHP_VER="8.3" ;;
esac
log_info "Cài đặt PHP ${PHP_VER}..."
install_php "$PHP_VER"

log_info "Cài đặt phpMyAdmin..."
install_phpmyadmin 2>/dev/null || true

# =============================================================================
# Object Cache — kiến trúc 2 tầng cho Nginx + WordPress
# L1: Nginx FastCGI Cache (page cache, bypass PHP hoàn toàn)
# L2: Valkey / Redis / KeyDB (object cache, Unix Socket, giảm tải MariaDB)
# =============================================================================
echo ""
echo -e "${BLUE}══════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}  Kiến trúc Cache tối ưu cho Nginx + WordPress${NC}"
echo -e "  L1: Nginx FastCGI Cache  → Serve HTML tĩnh, bypass PHP hoàn toàn"
echo -e "  L2: Valkey/Redis (Unix Socket) → Cache DB queries, giảm tải MariaDB 80%+"
echo -e "${BLUE}══════════════════════════════════════════════════════${NC}"
echo ""
echo -e "${YELLOW}Chọn Object Cache (L2) sử dụng Unix Socket:${NC}"
echo "  1. Valkey  [KHUẾN DÙNG] — fork mới của Redis, MIT license, hiệu suất cao"
echo "  2. Redis   — phổ biến, ổn định (BSL license từ 2024)"
echo "  3. KeyDB   — Redis đa luồng, xử lý nhiều connection cùng lúc tốt hơn"
echo "  0. Bỏ qua  — chỉ dùng Nginx FastCGI Cache (L1 only)"
read -t 15 -p "Chọn [0-3, Enter = Valkey]: " cache_choice || cache_choice="1"
case "$cache_choice" in
    2) log_info "Cài đặt Redis (Unix Socket)...";  _install_object_cache_nginx "redis"  ;;
    3) log_info "Cài đặt KeyDB (Unix Socket)..."; _install_object_cache_nginx "keydb"  ;;
    0) echo -e "${YELLOW}Bỏ qua Object Cache L2. Chỉ sử dụng Nginx FastCGI Cache.${NC}" ;;
    *) log_info "Cài đặt Valkey (Unix Socket)..." ; _install_object_cache_nginx "valkey" ;;
esac

# Firewall
if [[ -f "$INSTALL_DIR/modules/security.sh" ]]; then
    source "$INSTALL_DIR/modules/security.sh"
    setup_firewall "auto"
fi

# Monit
if [[ -f "$INSTALL_DIR/modules/monit.sh" ]]; then
    source "$INSTALL_DIR/modules/monit.sh"
    monit_install "auto"
fi

# ── Step 5: Auto-harden nginx.conf (Performance + Security) ───────────────────
echo -e "${CYAN}[5/5] Tự động tối ưu nginx.conf (Performance + Security)...${NC}"
if type _configure_nginx_global &>/dev/null; then
    _configure_nginx_global
else
    log_warn "_configure_nginx_global chưa được load. Bỏ qua bước này."
fi

# ── Done ──────────────────────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}"
echo "╔══════════════════════════════════════════════════════╗"
echo "║  ✅  LEMP Stack (Nginx) đã cài đặt thành công!      ║"
echo "╠══════════════════════════════════════════════════════╣"
echo "║  🌐  Nginx đã được tối ưu & bảo mật tự động:        ║"
echo "║    ✓ worker_processes auto, worker_connections 4096  ║"
echo "║    ✓ Gzip toàn cầu bật                              ║"
echo "║    ✓ server_tokens off (ẩn phiên bản)               ║"
echo "║    ✓ FastCGI buffer tuning                          ║"
echo "║    ✓ Security Headers snippet (X-Frame, HSTS...)     ║"
echo "║    ✓ WordPress Security Locations snippet            ║"
echo "║  📦  Khi thêm WordPress site sẽ tự động:            ║"
echo "║    ✓ PHP-FPM pool riêng mỗi domain (open_basedir)   ║"
echo "║    ✓ Inject Security Headers vào vhost              ║"
echo "║    ✓ Inject WP Security Locations (chặn xmlrpc...)   ║"
echo "║    ✓ Fetch WP Salts tự động từ WordPress.org         ║"
echo "║    ✓ wp-config.php tối ưu (DISALLOW_FILE_EDIT, ...)  ║"
echo "║  Gõ  vps  để mở Menu quản lý bất kỳ lúc nào        ║"
echo "╚══════════════════════════════════════════════════════╝"
echo -e "${NC}"

# Ghi lại stack đã chọn — menu sẽ tự động hiển thị chế độ Nginx
mkdir -p "$HOME/.vps-manager"
echo "ACTIVE_STACK=nginx" > "$HOME/.vps-manager/stack.conf"

cd "$INSTALL_DIR"
exec "$INSTALL_DIR/install.sh"

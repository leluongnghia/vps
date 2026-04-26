#!/bin/bash

# =============================================================================
# VPS Manager — Cài đặt nhanh OpenLiteSpeed Stack (OLS + LSPHP + MariaDB)
# =============================================================================
# Sử dụng:
#   bash <(curl -s https://raw.githubusercontent.com/leluongnghia/vps/main/vps-manager/install-ols.sh)
#   bash <(wget -qO- https://raw.githubusercontent.com/leluongnghia/vps/main/vps-manager/install-ols.sh)
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
echo "║   ⚡  VPS Manager — Cài đặt OpenLiteSpeed Stack      ║"
echo "║   OLS + LSPHP + MariaDB + LSCache + Valkey           ║"
echo "╚══════════════════════════════════════════════════════╝"
echo -e "${NC}"

# ── Step 1: Install base dependencies ─────────────────────────────────────────
echo -e "${CYAN}[1/5] Kiểm tra và cài đặt các gói phụ thuộc cơ bản...${NC}"
if [[ -f /etc/redhat-release ]]; then
    dnf install -y curl wget git unzip tar socat cronie openssl &>/dev/null
else
    apt-get update -qq
    apt-get install -y curl wget git unzip tar socat cron lsb-release openssl &>/dev/null
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
source modules/ols.sh
source modules/wordpress_performance.sh 2>/dev/null || true

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

# ── Step 4: Install OLS Stack ─────────────────────────────────────────────────
echo -e "${CYAN}[4/5] Bắt đầu cài đặt OpenLiteSpeed Stack...${NC}"
echo ""

# ZRAM
if [[ -f "$INSTALL_DIR/modules/zram.sh" ]]; then
    source "$INSTALL_DIR/modules/zram.sh"
    log_info "Thiết lập ZRAM Swap..."
    zram_install "auto"
fi

# =============================================================================
# ── Tối ưu hóa hệ thống (wptangtoc-grade) ──
# =============================================================================
echo -e "${CYAN}[3.5/5] Tối ưu Kernel + TCP + THP + File Limits...${NC}"
if type run_system_optimization &>/dev/null; then
    run_system_optimization
else
    # Fallback nếu chưa source được
    # Tắt THP ngay lập tức
    echo never > /sys/kernel/mm/transparent_hugepage/enabled 2>/dev/null || true
    echo never > /sys/kernel/mm/transparent_hugepage/defrag  2>/dev/null || true
    # Nâng file descriptor
    ulimit -n 524288 2>/dev/null || true
fi
echo -e "${GREEN}  ✓ Tối ưu hóa hệ thống hoàn tất${NC}"

# ── Dừng Nginx nếu đang chạy ──
if systemctl is-active --quiet nginx 2>/dev/null; then
    log_warn "Nginx đang chạy — Cần dừng Nginx trước khi cài OLS (cùng dùng port 80/443)."
    systemctl stop nginx 2>/dev/null
    systemctl disable nginx 2>/dev/null
    log_info "Đã dừng Nginx."
fi

# Cài MariaDB trước
log_info "Cài đặt MariaDB..."
install_mariadb

# Thêm OLS & LSPHP repo
log_info "Thêm OpenLiteSpeed repository..."
setup_ols_repo
setup_lsphp_repo

# Chọn LSPHP version
echo ""
echo -e "${YELLOW}Chọn phiên bản LSPHP chính (mặc định: 8.3):${NC}"
echo "  1. LSPHP 8.3 (Khuyên dùng)"
echo "  2. LSPHP 8.4 (Mới nhất)"
echo "  3. LSPHP 8.2"
echo "  4. LSPHP 8.1"
read -t 10 -p "Chọn [1-4, Enter = 8.3]: " php_choice || php_choice=""
case "$php_choice" in
    2) LSPHP_DEFAULT_VER="8.4" ;;
    3) LSPHP_DEFAULT_VER="8.2" ;;
    4) LSPHP_DEFAULT_VER="8.1" ;;
    *) LSPHP_DEFAULT_VER="8.3" ;;
esac
export LSPHP_DEFAULT_VER

# Cài OpenLiteSpeed (nếu chưa có)
if ! command -v lshttpd &>/dev/null && [[ ! -f /usr/local/lsws/bin/lshttpd ]]; then
    log_info "Cài đặt OpenLiteSpeed..."
    if [[ "$OS_FAMILY" == "debian" ]]; then
        DEBIAN_FRONTEND=noninteractive apt-get install -y openlitespeed
    else
        dnf install -y openlitespeed
    fi
else
    log_warn "OpenLiteSpeed đã được cài. Bỏ qua cài lại."
fi

# Cài LSPHP
log_info "Cài đặt LSPHP ${LSPHP_DEFAULT_VER}..."
_install_lsphp "$LSPHP_DEFAULT_VER"

# Cấu hình & password WebAdmin
_set_ols_webadmin_pass
_configure_ols_base

# Khởi động OLS
systemctl enable lshttpd
systemctl start lshttpd
_ols_open_ports

# Object Cache
echo ""
echo -e "${YELLOW}Cài đặt Object Cache (khuyến dùng cho WordPress)?${NC}"
echo "  1. Valkey  (fork mới của Redis, hiệu suất cao) [Mặc định]"
echo "  2. Redis   (phổ biến)"
echo "  3. KeyDB   (đa luồng, nhanh nhất)"
echo "  0. Bỏ qua"
read -t 10 -p "Chọn [0-3, Enter = Valkey]: " cache_choice || cache_choice="1"
case "$cache_choice" in
    2) log_info "Cài đặt Redis...";  install_redis  ;;
    3) log_info "Cài đặt KeyDB..."; install_keydb  ;;
    0) echo -e "${YELLOW}Bỏ qua Object Cache.${NC}" ;;
    *) log_info "Cài đặt Valkey..."; install_valkey ;;
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

# ── Step 5: Done ───────────────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}"
echo "╔══════════════════════════════════════════════════════╗"
echo "║  ✅  OpenLiteSpeed Stack đã cài đặt thành công!      ║"
echo "╠══════════════════════════════════════════════════════╣"
echo "║  Gõ  vps  để mở Menu quản lý bất kỳ lúc nào        ║"
echo "╚══════════════════════════════════════════════════════╝"
echo -e "${NC}"

# Hiện thông tin WebAdmin
show_webadmin_info 2>/dev/null || true

# Ghi lại stack đã chọn — menu sẽ tự động hiển thị chế độ OLS
mkdir -p "$HOME/.vps-manager"
echo "ACTIVE_STACK=ols" > "$HOME/.vps-manager/stack.conf"

cd "$INSTALL_DIR"
exec "$INSTALL_DIR/install.sh"

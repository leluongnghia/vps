#!/bin/bash

# =============================================================================
# VPS Manager — Cài đặt nhanh LEMP Stack (Nginx + MariaDB + PHP)
# =============================================================================
# Sử dụng:
#   bash <(curl -s https://raw.githubusercontent.com/leluongnghia/vps/main/vps-manager/install-nginx.sh)
#   bash <(wget -qO- https://raw.githubusercontent.com/leluongnghia/vps/main/vps-manager/install-nginx.sh)
# Thêm --non-interactive để dùng mặc định (PHP 8.4 + Valkey) và không mở menu sau khi cài.
#
# File này chỉ làm 2 việc: tải VPS Manager về máy, rồi gọi run_stack_install
# (core/stack_install.sh) — cùng hàm mà Auto-Install trong install.sh sử dụng.
# =============================================================================

# Chế độ nghiêm ngặt CHỈ áp dụng cho phần tải về bên dưới. Các module được nạp sau đó
# tự kiểm tra lỗi từng bước và không viết cho `set -e`/`set -u`.
set -euo pipefail

# ── Colors ────────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'

INSTALL_DIR="/usr/local/vps-manager"
REPO_URL="https://github.com/leluongnghia/vps.git"
BRANCH="main"

INTERACTIVE=1
if [[ "${1:-}" == "--non-interactive" ]] || [[ ! -t 0 ]]; then
    INTERACTIVE=0
fi

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
echo -e "${CYAN}[1/3] Kiểm tra và cài đặt các gói phụ thuộc cơ bản...${NC}"
if [[ -f /etc/redhat-release ]]; then
    dnf config-manager --enable ol9_codeready_builder ol9_developer_EPEL 2>/dev/null || true
    dnf config-manager --set-enabled crb 2>/dev/null || true
    dnf install -y curl wget git unzip tar socat cronie openssl &>/dev/null || true
else
    # Clean up broken PPA files from previous attempts if any
    rm -f /etc/apt/sources.list.d/*ondrej*php* 2>/dev/null || true
    apt-get update -qq || true
    DEBIAN_FRONTEND=noninteractive apt-get install -y curl wget git unzip tar socat cron lsb-release openssl &>/dev/null || true
fi
if ! command -v git &>/dev/null || ! command -v curl &>/dev/null; then
    echo -e "${RED}[✗] Không cài được git/curl. Kiểm tra kết nối mạng và kho gói của hệ điều hành.${NC}"
    exit 1
fi
echo -e "${GREEN}  ✓ Xong${NC}"

# ── Step 2: Clone/update VPS Manager ──────────────────────────────────────────
echo -e "${CYAN}[2/3] Tải VPS Manager từ GitHub...${NC}"
TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT

git clone -b "$BRANCH" --depth 1 "$REPO_URL" "$TEMP_DIR/vps-repo" &>/dev/null || {
    echo -e "${RED}[✗] Không thể clone repo. Kiểm tra kết nối mạng.${NC}"
    exit 1
}

# Kiểm tra bản tải về TRƯỚC khi thay bản đang cài: đủ file cốt lõi, không lỗi cú pháp
NEW_SRC="$TEMP_DIR/vps-repo/vps-manager"
for f in install.sh core/menu.sh core/utils.sh core/stack_install.sh; do
    if [[ ! -s "$NEW_SRC/$f" ]]; then
        echo -e "${RED}[✗] Bản tải về thiếu file: $f${NC}"
        exit 1
    fi
done
while IFS= read -r -d '' f; do
    if ! bash -n "$f" 2>/dev/null; then
        echo -e "${RED}[✗] Bản tải về có file lỗi cú pháp: ${f#$NEW_SRC/}${NC}"
        exit 1
    fi
done < <(find "$NEW_SRC" -name "*.sh" -print0)

# Dựng bản mới cạnh bên rồi hoán đổi; lỗi giữa chừng thì khôi phục bản cũ
STAGE_DIR="${INSTALL_DIR}_new_$$"
BACKUP_DIR="${INSTALL_DIR}_backup_$(date +%s)"
cd /tmp
rm -rf "$STAGE_DIR"
cp -r "$NEW_SRC" "$STAGE_DIR"
[[ -d "$INSTALL_DIR" ]] && mv "$INSTALL_DIR" "$BACKUP_DIR"
if ! mv "$STAGE_DIR" "$INSTALL_DIR"; then
    [[ -d "$BACKUP_DIR" ]] && mv "$BACKUP_DIR" "$INSTALL_DIR"
    echo -e "${RED}[✗] Không cài được vào $INSTALL_DIR. Đã khôi phục bản cũ.${NC}"
    exit 1
fi
rm -rf "$BACKUP_DIR" "$TEMP_DIR"
trap - EXIT

find "$INSTALL_DIR" -name "*.sh" -exec chmod +x {} \;
ln -sf "$INSTALL_DIR/install.sh" /usr/local/bin/vps
echo -e "${GREEN}  ✓ VPS Manager đã được tải về: $INSTALL_DIR${NC}"

# Hết phần tải về: tắt chế độ nghiêm ngặt trước khi nạp các module
set +euo pipefail

# ── Step 3: Chọn cấu hình & cài đặt stack ─────────────────────────────────────
echo -e "${CYAN}[3/3] Cài đặt LEMP Stack...${NC}"
cd "$INSTALL_DIR" || exit 1
source core/utils.sh
source core/stack_install.sh
echo -e "${GREEN}  ✓ OS: ${OS_ID:-unknown} ${OS_VER:-} (${OS_FAMILY:-unknown})${NC}"

if [[ "${OS_FAMILY:-unknown}" == "unknown" ]]; then
    echo -e "${RED}[✗] Hệ điều hành chưa được hỗ trợ (cần Ubuntu/Debian hoặc RHEL/Alma/Rocky/Oracle Linux).${NC}"
    exit 1
fi

php_choice=""
cache_choice="1"
if [[ "$INTERACTIVE" -eq 1 ]]; then
    echo ""
    echo -e "${YELLOW}Chọn phiên bản PHP chính (mặc định: 8.4):${NC}"
    echo "  1. PHP 8.4 (Mới nhất - mặc định)"
    echo "  2. PHP 8.3"
    echo "  3. PHP 8.2"
    echo "  4. PHP 8.1"
    read -t 15 -p "Chọn [1-4, Enter = 8.4]: " php_choice </dev/tty 2>/dev/null || php_choice=""

    echo ""
    echo -e "${YELLOW}Chọn Object Cache (Unix Socket) cho WordPress:${NC}"
    echo "  1. Valkey  [KHUYÊN DÙNG] — fork mã nguồn mở của Redis (tự chuyển sang Redis nếu OS chưa có gói)"
    echo "  2. Redis   — phổ biến, ổn định"
    echo "  0. Bỏ qua  — chỉ dùng Nginx FastCGI Cache"
    read -t 15 -p "Chọn [0-2, Enter = Valkey]: " cache_choice </dev/tty 2>/dev/null || cache_choice="1"
    echo ""
fi

case "$php_choice" in
    2) PHP_VER="8.3" ;;
    3) PHP_VER="8.2" ;;
    4) PHP_VER="8.1" ;;
    *) PHP_VER="8.4" ;;
esac
case "$cache_choice" in
    2) CACHE_TYPE="redis" ;;
    0) CACHE_TYPE="none" ;;
    *) CACHE_TYPE="valkey" ;;
esac

if run_stack_install "$PHP_VER" "$CACHE_TYPE"; then
    echo -e "${GREEN}✅ Hoàn tất. Gõ  vps  để mở Menu quản lý bất kỳ lúc nào.${NC}"
    install_rc=0
else
    echo -e "${RED}Cài đặt chưa hoàn tất — xem danh sách lỗi ở trên, sửa rồi chạy lại lệnh cài hoặc gõ  vps .${NC}"
    install_rc=1
fi

if [[ "$INTERACTIVE" -eq 1 && "$install_rc" -eq 0 ]]; then
    exec "$INSTALL_DIR/install.sh"
fi
exit "$install_rc"

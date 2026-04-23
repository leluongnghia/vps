#!/bin/bash
# modules/zram.sh - ZRAM Swap Management
# Swap ảo nén trực tiếp trên RAM, nhanh gấp 1000x swap SSD
# Hỗ trợ: Ubuntu/Debian và AlmaLinux/RHEL/Rocky

zram_menu() {
    clear
    echo -e "${BLUE}=================================================${NC}"
    echo -e "${GREEN}       Quản lý ZRAM Swap (Swap nén trên RAM)${NC}"
    echo -e "${BLUE}=================================================${NC}"
    echo -e ""

    # Hiển thị trạng thái hiện tại
    _zram_detect_state
    _zram_print_status

    echo -e ""
    echo -e "${BLUE}=================================================${NC}"
    echo -e "1. Bật ZRAM (Cài đặt + Kích hoạt)"
    echo -e "2. Tắt ZRAM (Gỡ bỏ + Khôi phục Swap đĩa)"
    echo -e "3. Xem thông tin chi tiết ZRAM"
    echo -e "0. Quay lại"
    echo -e "${BLUE}=================================================${NC}"
    read -p "Nhập lựa chọn [0-3]: " choice

    case $choice in
        1) zram_install ;;
        2) zram_uninstall ;;
        3) zram_info; pause ;;
        0) return ;;
        *) echo -e "${RED}Lựa chọn không hợp lệ!${NC}"; pause ;;
    esac
}

# ────────────────────────────────────────────────────────────
# NHẬN DIỆN OS & TRẠNG THÁI
# ────────────────────────────────────────────────────────────
_zram_detect_os() {
    if [[ -f /etc/os-release ]]; then
        source /etc/os-release
    fi
    if [[ "${ID:-}" == "ubuntu" || "${ID:-}" == "debian" ]]; then
        ZRAM_OS="debian"
        ZRAM_CONFIG="/etc/default/zramswap"
        ZRAM_SVC="zramswap"
    else
        ZRAM_OS="rhel"
        ZRAM_CONFIG="/etc/systemd/zram-generator.conf"
        ZRAM_SVC="dev-zram0.swap"
    fi
}

_zram_detect_state() {
    _zram_detect_os
    if [[ -f "$ZRAM_CONFIG" ]] || swapon --show | grep -q zram 2>/dev/null; then
        ZRAM_STATE="ON"
    else
        ZRAM_STATE="OFF"
    fi
}

_zram_print_status() {
    if [[ "$ZRAM_STATE" == "ON" ]]; then
        echo -e "  Trạng thái ZRAM : ${GREEN}ĐÃ KÍCH HOẠT${NC}"
        local zram_size
        zram_size=$(swapon --show=SIZE,NAME 2>/dev/null | grep zram | awk '{print $1}')
        [[ -n "$zram_size" ]] && echo -e "  Dung lượng ZRAM : ${CYAN}${zram_size}${NC}"
        local zram_algo
        zram_algo=$(cat /sys/block/zram0/comp_algorithm 2>/dev/null | grep -oP '\[.*?\]' | tr -d '[]')
        [[ -n "$zram_algo" ]] && echo -e "  Thuật toán nén  : ${CYAN}${zram_algo}${NC}"
    else
        echo -e "  Trạng thái ZRAM : ${RED}CHƯA KÍCH HOẠT${NC}"
        echo -e "  ${YELLOW}Khuyến nghị BẬT ZRAM để tăng tốc và bảo vệ SSD${NC}"
    fi

    # Hiển thị swap hiện tại
    local swap_info
    swap_info=$(swapon --show=SIZE,TYPE,NAME 2>/dev/null | tail -n +2)
    if [[ -n "$swap_info" ]]; then
        echo -e ""
        echo -e "  ${CYAN}Swap đang hoạt động:${NC}"
        echo "$swap_info" | while read -r line; do
            echo -e "    $line"
        done
    fi
}

# ────────────────────────────────────────────────────────────
# TÍNH TOÁN SIZE TỐI ƯU
# ────────────────────────────────────────────────────────────
_zram_calc_size() {
    local ram_kb
    ram_kb=$(awk '/MemTotal/ {print $2}' /proc/meminfo)
    local ram_mb=$(( ram_kb / 1024 ))

    if [[ $ram_mb -le 8192 ]]; then
        # ≤8GB RAM: dùng 50%
        echo $(( ram_mb / 2 ))
    else
        # >8GB RAM: giới hạn 4096MB để không tốn CPU quá nhiều
        echo 4096
    fi
}

# ────────────────────────────────────────────────────────────
# CHỌN THUẬT TOÁN NÉN TỐT NHẤT
# ────────────────────────────────────────────────────────────
_zram_best_algo() {
    # Probe zram module nếu cần
    modprobe zram 2>/dev/null || true

    if [[ -f /sys/block/zram0/comp_algorithm ]]; then
        local algos
        algos=$(cat /sys/block/zram0/comp_algorithm 2>/dev/null)
        if echo "$algos" | grep -q "zstd"; then
            echo "zstd"   # Tốt nhất: tỉ lệ nén cao, performance tốt
        elif echo "$algos" | grep -q "lz4"; then
            echo "lz4"    # Nhanh nhất, tỉ lệ nén thấp hơn
        else
            echo "lzo"    # Fallback phổ thông
        fi
    else
        echo "lzo"
    fi
}

# ────────────────────────────────────────────────────────────
# CÀI ĐẶT ZRAM
# ────────────────────────────────────────────────────────────
zram_install() {
    local mode="${1:-}"
    _zram_detect_state

    if [[ "$ZRAM_STATE" == "ON" ]]; then
        echo -e "${YELLOW}ZRAM đã được kích hoạt rồi!${NC}"
        [[ "$mode" != "auto" ]] && pause
        return 0
    fi

    echo ""
    echo -e "${YELLOW}Tính năng ZRAM sẽ:${NC}"
    echo -e "  • Tạo vùng Swap ảo nén TRỰC TIẾP trên RAM (nhanh x1000 so với SSD)"
    echo -e "  • Tự động loại bỏ swap file cũ (/swapfile, /var/swap.1)"
    echo -e "  • Dùng thuật toán nén zstd/lz4/lzo tuỳ kernel hỗ trợ"
    echo -e "  • Giúp VPS nhỏ chống OOM (Out Of Memory) tốt hơn"
    echo ""

    local zram_size_mb algo
    zram_size_mb="$(_zram_calc_size)"
    algo="$(_zram_best_algo)"
    local zram_size_display="${zram_size_mb}MB"
    [[ $zram_size_mb -ge 1024 ]] && zram_size_display="$(( zram_size_mb / 1024 ))GB (${zram_size_mb}MB)"

    echo -e "  Config sẽ áp dụng:"
    echo -e "    Dung lượng : ${GREEN}${zram_size_display}${NC}"
    echo -e "    Thuật toán : ${GREEN}${algo}${NC}"
    echo ""
    
    if [[ "$mode" != "auto" ]]; then
        read -p "Tiếp tục cài đặt ZRAM? [Y/n]: " confirm
        if [[ "${confirm,,}" == "n" ]]; then
            echo -e "${YELLOW}Đã huỷ.${NC}"; pause; return 0
        fi
    fi

    log_info "Đang cài đặt ZRAM (${zram_size_mb}MB, algo=${algo})..."

    # ── Bước 1: Cài package ──
    if [[ "$ZRAM_OS" == "debian" ]]; then
        DEBIAN_FRONTEND=noninteractive apt-get update -qq 2>/dev/null
        DEBIAN_FRONTEND=noninteractive apt-get purge zram-generator -y &>/dev/null || true
        DEBIAN_FRONTEND=noninteractive apt-get install -y zram-tools &>/dev/null
        if [[ $? -ne 0 ]]; then
            log_error "Không thể cài zram-tools! Kiểm tra kết nối mạng."
            pause; return 1
        fi
    else
        dnf install -y zram-generator &>/dev/null
        if [[ $? -ne 0 ]]; then
            # Thử với yum
            yum install -y zram-generator &>/dev/null || {
                log_error "Không thể cài zram-generator!"
                pause; return 1
            }
        fi
        modprobe zram 2>/dev/null || true
    fi
    log_info "  ✓ Package đã cài"

    # ── Bước 2: Ghi config ──
    if [[ "$ZRAM_OS" == "debian" ]]; then
        cat > "$ZRAM_CONFIG" <<EOF
ALGO=${algo}
SIZE=${zram_size_mb}
PRIORITY=100
EOF
    else
        cat > "$ZRAM_CONFIG" <<EOF
[zram0]
zram-fraction = 1.0
max-zram-size = ${zram_size_mb}
zram-size = ${zram_size_mb}
compression-algorithm = ${algo}
swap-priority = 100
fs-type = swap
EOF
    fi
    log_info "  ✓ Config đã ghi"

    # ── Bước 3: Kernel tuning cho ZRAM ──
    cat > /etc/sysctl.d/99-vps-manager-zram.conf <<EOF
# VPS Manager - ZRAM Kernel Opts
vm.swappiness = 100
vm.page-cluster = 0
EOF
    sysctl -p /etc/sysctl.d/99-vps-manager-zram.conf &>/dev/null
    log_info "  ✓ Kernel params đã áp dụng"

    # ── Bước 4: Dọn swap cũ ──
    log_info "  Đang dọn swap file cũ trên ổ đĩa..."
    swapoff -a 2>/dev/null || true
    for old_swap in /swapfile /swap.img /var/swap.1; do
        if [[ -f "$old_swap" ]]; then
            swapoff "$old_swap" 2>/dev/null || true
            rm -f "$old_swap"
            log_info "    ✓ Đã xoá $old_swap"
        fi
    done
    # Xoá entry trong fstab
    sed -i -e '/swap.1/d' -e '/swapfile/d' -e '/swap.img/d' /etc/fstab
    sed -i 's|^\(.*\s\+swap\s.*\)$|#\1|' /etc/fstab 2>/dev/null || true

    # ── Bước 5: Khởi động dịch vụ ──
    systemctl daemon-reload
    if [[ "$ZRAM_OS" == "debian" ]]; then
        systemctl enable zramswap &>/dev/null
        systemctl restart zramswap
        local rc=$?
    else
        systemctl daemon-reload
        systemctl start dev-zram0.swap
        local rc=$?
    fi

    if [[ $rc -ne 0 ]]; then
        log_warn "ZRAM service khởi động có lỗi. Kiểm tra: journalctl -u ${ZRAM_SVC}"
    else
        log_info "  ✓ ZRAM đang hoạt động"
    fi

    echo ""
    echo -e "${GREEN}=================================================${NC}"
    echo -e "${GREEN}  ZRAM đã được kích hoạt thành công!${NC}"
    echo -e "${GREEN}=================================================${NC}"
    zram_info
    [[ "$mode" != "auto" ]] && pause
}

# ────────────────────────────────────────────────────────────
# GỠ BỎ ZRAM
# ────────────────────────────────────────────────────────────
zram_uninstall() {
    local mode="${1:-}"
    _zram_detect_state

    if [[ "$ZRAM_STATE" == "OFF" ]]; then
        echo -e "${YELLOW}ZRAM chưa được cài đặt, không cần gỡ.${NC}"
        [[ "$mode" != "auto" ]] && pause
        return 0
    fi

    echo ""
    echo -e "${YELLOW}Thao tác này sẽ:${NC}"
    echo -e "  • Tắt và gỡ ZRAM"
    echo -e "  • Tái tạo swap file truyền thống 1GB trên ổ đĩa"
    echo ""
    if [[ "$mode" != "auto" ]]; then
        read -p "Bạn chắc chắn muốn TẮT ZRAM? [y/N]: " confirm
        if [[ "${confirm,,}" != "y" ]]; then
            echo -e "${YELLOW}Đã huỷ.${NC}"; pause; return 0
        fi
    fi

    log_info "Đang gỡ bỏ ZRAM..."

    # Dừng service
    if [[ "$ZRAM_OS" == "debian" ]]; then
        systemctl stop zramswap &>/dev/null || true
        systemctl disable zramswap &>/dev/null || true
        DEBIAN_FRONTEND=noninteractive apt-get remove --purge zram-tools -y &>/dev/null || true
        DEBIAN_FRONTEND=noninteractive apt-get autoremove -y &>/dev/null || true
    else
        systemctl stop dev-zram0.swap &>/dev/null || true
        zramctl --reset /dev/zram0 &>/dev/null || true
        dnf remove -y zram-generator &>/dev/null || yum remove -y zram-generator &>/dev/null || true
    fi

    # Xoá config
    rm -f "$ZRAM_CONFIG"
    rm -f /etc/sysctl.d/99-vps-manager-zram.conf

    # Restore swappiness mặc định
    cat >> /etc/sysctl.d/101-sysctl.conf <<< "vm.swappiness = 10" 2>/dev/null || true
    sysctl -w vm.swappiness=10 &>/dev/null || true

    log_info "  ✓ ZRAM đã tắt"

    # Tái tạo swap file 1GB dự phòng
    log_info "Đang tạo lại swap file 1GB (backup an toàn)..."
    swapoff -a 2>/dev/null || true
    rm -f /var/swap.1 /swapfile /swap.img

    if dd if=/dev/zero of=/var/swap.1 bs=1M count=1024 status=none; then
        chmod 600 /var/swap.1
        mkswap /var/swap.1 &>/dev/null
        swapon /var/swap.1
        # Thêm vào fstab
        grep -q '/var/swap.1' /etc/fstab || echo '/var/swap.1 none swap defaults 0 0' >> /etc/fstab
        log_info "  ✓ Swap file 1GB đã tạo"
    else
        log_warn "Không thể tạo swap file (có thể không đủ dung lượng ổ đĩa)"
    fi

    systemctl daemon-reload
    echo -e "${GREEN}Đã gỡ ZRAM và khôi phục swap file thành công.${NC}"
    [[ "$mode" != "auto" ]] && pause
}

# ────────────────────────────────────────────────────────────
# THÔNG TIN CHI TIẾT
# ────────────────────────────────────────────────────────────
zram_info() {
    echo ""
    echo -e "${CYAN}--- Thông tin Swap / ZRAM ---${NC}"

    # Tổng quan từ swapon
    swapon --show 2>/dev/null || echo "  (không có swap nào đang hoạt động)"

    echo ""
    # Chi tiết ZRAM nếu có
    if [[ -d /sys/block/zram0 ]]; then
        local orig_size comp_size mem_used
        orig_size=$(awk '{printf "%.1f MB", $1/1024/1024}' /sys/block/zram0/orig_data_size 2>/dev/null)
        comp_size=$(awk '{printf "%.1f MB", $1/1024/1024}' /sys/block/zram0/compr_data_size 2>/dev/null)
        mem_used=$(awk '{printf "%.1f MB", $1/1024/1024}' /sys/block/zram0/mem_used_total 2>/dev/null)
        local algo
        algo=$(cat /sys/block/zram0/comp_algorithm 2>/dev/null | grep -oP '\[.*?\]' | tr -d '[]')

        echo -e "${CYAN}  ZRAM Device (/dev/zram0):${NC}"
        echo -e "    Thuật toán  : ${GREEN}${algo:-N/A}${NC}"
        echo -e "    Dữ liệu gốc : ${orig_size:-N/A}"
        echo -e "    Sau nén     : ${comp_size:-N/A}"
        echo -e "    RAM sử dụng : ${mem_used:-N/A}"

        if [[ -n "$orig_size" && -n "$comp_size" ]]; then
            local ratio
            ratio=$(awk '{if ($2>0) printf "%.1fx", $1/$2}' \
                <(paste <(cat /sys/block/zram0/orig_data_size) \
                        <(cat /sys/block/zram0/compr_data_size)) 2>/dev/null)
            [[ -n "$ratio" ]] && echo -e "    Tỉ lệ nén   : ${GREEN}${ratio}${NC}"
        fi
    fi

    echo ""
    # free -h để xem tổng quan
    free -h
}

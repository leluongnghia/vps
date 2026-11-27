#!/bin/bash

# modules/swap.sh - Manage Swap Memory

swap_menu() {
    while true; do
        clear
        echo -e "${BLUE}=================================================${NC}"
        echo -e "${GREEN}          🧠 Quản lý Bộ nhớ ảo (Swap & ZRAM)${NC}"
        echo -e "${BLUE}=================================================${NC}"
        echo -e "Trạng thái bộ nhớ hiện tại:"
        free -h | grep -E "(Mem|Swap)"
        echo -e "${BLUE}=================================================${NC}"
        echo -e "1. Tạo File Swap trên ổ cứng (1GB, 2GB...)"
        echo -e "2. Xóa File Swap trên ổ cứng"
        echo -e "3. ⚡ Chuyển sang ZRAM Swap (Swap nén trên RAM - Siêu tốc, khuyên dùng)"
        echo -e "0. Quay lại Menu chính"
        echo -e "${BLUE}=================================================${NC}"
        read -p "Chọn [0-3]: " choice
        
        case $choice in
            1) create_swap ;;
            2) remove_swap ;;
            3) 
                source "$(dirname "${BASH_SOURCE[0]}")/zram.sh"
                zram_menu
                ;;
            0) return ;;
            *) echo -e "${RED}Lựa chọn không hợp lệ!${NC}"; pause ;;
        esac
    done
}

create_swap() {
    # Check for ZRAM conflict
    if [[ -f /etc/default/zramswap ]] || [[ -f /etc/systemd/zram-generator.conf ]]; then
        echo -e "${RED}CẢNH BÁO: BẠN ĐANG SỬ DỤNG ZRAM SWAP CAO CẤP!${NC}"
        echo -e "${YELLOW}Hệ thống đang cấu hình vm.swappiness = 100 để nén dữ liệu vào RAM.${NC}"
        echo -e "${YELLOW}Việc tạo thêm Swap tĩnh (File Swap) trên ổ cứng lúc này sẽ gây xung đột cấu hình và ghi rác lên ổ SSD, làm máy chủ chậm hơn.${NC}"
        echo -e "-> Hãy tắt ZRAM (chọn mục 3 trong menu này) nếu bạn thật sự muốn dùng Swap tĩnh trên đĩa!"
        if [[ -z "$1" ]]; then pause; fi
        return
    fi

    if [[ -n "$1" ]]; then
        size=$1
    else
        read -p "Nhập dung lượng Swap (MB) (ví dụ 1024, 2048): " size
    fi
    
    if ! valid_uint "$size" || [[ "$size" -lt 64 ]] || [[ "$size" -gt 65536 ]]; then
        echo -e "${RED}Dung lượng không hợp lệ (nhập số MB, từ 64 đến 65536).${NC}"
        if [[ -z "$1" ]]; then pause; fi
        return 1
    fi

    if [[ -f /swapfile ]]; then
        echo -e "${RED}Swapfile đã tồn tại! Vui lòng xóa trước.${NC}"
        if [[ -z "$1" ]]; then pause; fi
        return
    fi

    if ! check_disk_space / $(( size + 512 )); then
        if [[ -z "$1" ]]; then pause; fi
        return 1
    fi

    log_info "Đang tạo Swapfile ${size}MB..."
    # fallocate không dùng được cho swap trên một số filesystem (btrfs, xfs cũ) -> fallback dd
    if ! fallocate -l "${size}M" /swapfile 2>/dev/null; then
        dd if=/dev/zero of=/swapfile bs=1M count="$size" status=none
    fi
    if ! { chmod 600 /swapfile && mkswap /swapfile >/dev/null && swapon /swapfile; }; then
        log_error "Tạo Swap THẤT BẠI. Đã dọn file /swapfile."
        swapoff /swapfile 2>/dev/null
        rm -f /swapfile
        if [[ -z "$1" ]]; then pause; fi
        return 1
    fi

    # Add to fstab
    if ! grep -q "^/swapfile[[:space:]]" /etc/fstab; then
        echo "/swapfile none swap sw 0 0" >> /etc/fstab
    fi

    log_info "Tạo Swap thành công."
    if [[ -z "$1" ]]; then pause; fi
}

remove_swap() {
    # Chỉ gỡ các swap FILE do công cụ này tạo; không tắt ZRAM hay swap partition
    local found=0 f
    for f in /swapfile /var/swap.1; do
        [[ -f "$f" ]] || continue
        found=1
        log_info "Đang xóa $f..."
        if grep -q "^${f} " /proc/swaps 2>/dev/null && ! swapoff "$f"; then
            log_error "Không swapoff được $f (RAM không đủ chỗ chứa dữ liệu đang swap). Giữ nguyên."
            continue
        fi
        rm -f "$f"
        sed -i "\|^${f}[[:space:]]|d" /etc/fstab
        log_info "Đã xóa $f."
    done
    [[ $found -eq 0 ]] && echo -e "${YELLOW}Không có file swap nào trên ổ đĩa.${NC}"
    pause
}

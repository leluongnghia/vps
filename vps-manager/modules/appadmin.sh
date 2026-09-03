#!/bin/bash

# modules/appadmin.sh - AppAdmin Protection & Tools

appadmin_menu() {
    while true; do
        clear
        echo -e "${BLUE}=================================================${NC}"
        echo -e "${GREEN}          🛠️  AppAdmin & Công cụ Bổ trợ${NC}"
        echo -e "${BLUE}=================================================${NC}"
        echo -e "1. 🔒 Đặt mật khẩu bảo vệ thư mục (HTTP Basic Auth)"
        echo -e "2. 🖼️  Tối ưu hóa ảnh (Nén JPG/PNG & Chuyển đổi WebP)"
        echo -e "0. Quay lại Menu chính"
        echo -e "${BLUE}=================================================${NC}"
        read -p "Nhập lựa chọn [0-2]: " choice
        
        case $choice in
            1) setup_http_auth ;;
            2) optimize_images ;;
            0) return ;;
            *) echo -e "${RED}Lựa chọn không hợp lệ!${NC}"; pause ;;
        esac
    done
}

setup_http_auth() {
    echo -e "${GREEN}=== Tạo tài khoản bảo vệ HTTP Basic Auth ===${NC}"
    echo "Tính năng này sẽ tạo user/pass cho các folder admin (như /phpmyadmin hoặc wp-admin)."
    read -p "Nhập Username mới: " user
    [[ -z "$user" ]] && { echo -e "${RED}Username không được để trống!${NC}"; pause; return; }
    
    if ! command -v htpasswd &> /dev/null; then
        if [[ "$OS_FAMILY" == "rhel" ]]; then
            pkg_install httpd-tools
        else
            pkg_install apache2-utils
        fi
    fi
    
    mkdir -p /etc/nginx/auth
    htpasswd -c /etc/nginx/auth/.htpasswd "$user"
    
    log_info "Đã tạo file auth tại /etc/nginx/auth/.htpasswd."
    echo -e "${YELLOW}Để áp dụng, cấu hình sau có thể được include vào Nginx location cần bảo vệ:"
    echo -e "    auth_basic \"Restricted Area\";"
    echo -e "    auth_basic_user_file /etc/nginx/auth/.htpasswd;${NC}"
    pause
}

optimize_images() {
    clear
    echo -e "${BLUE}=================================================${NC}"
    echo -e "${GREEN}     🖼️  Tối ưu hóa Ảnh (Image Optimize)${NC}"
    echo -e "${BLUE}=================================================${NC}"

    # Select site
    source "$(dirname "${BASH_SOURCE[0]}")/site.sh"
    select_site || return
    domain=$SELECTED_DOMAIN
    target="/var/www/$domain/public_html/wp-content/uploads"

    # Fallback nếu không phải WordPress
    if [[ ! -d "$target" ]]; then
        target="/var/www/$domain/public_html"
    fi

    echo -e "${CYAN}📁 Thư mục xử lý: $target${NC}"
    echo ""

    # --- Chọn chế độ nén ---
    echo -e "Chọn chế độ:"
    echo -e "  1. Nén JPG/PNG giữ nguyên định dạng (jpegoptim + optipng)"
    echo -e "  2. Chuyển đổi sang WebP (cwebp) - tiết kiệm 25-35% hơn"
    echo -e "  3. Cả hai (Nén + Convert WebP)"
    echo -e "  0. Hủy"
    read -p "Chọn: " img_mode
    [[ "$img_mode" == "0" ]] && return

    # --- Chọn quality ---
    local jpg_quality=82
    local webp_quality=80
    if [[ "$img_mode" == "1" || "$img_mode" == "3" ]]; then
        read -p "JPG quality % (Enter = mặc định 82, khuyến nghị 75-90): " q
        [[ -n "$q" ]] && jpg_quality=$q
    fi
    if [[ "$img_mode" == "2" || "$img_mode" == "3" ]]; then
        read -p "WebP quality % (Enter = mặc định 80, khuyến nghị 75-85): " q
        [[ -n "$q" ]] && webp_quality=$q
    fi

    echo ""
    log_info "Cài đặt tools cần thiết..."
    _img_install_tools "$img_mode"

    # --- Tính dung lượng trước ---
    local size_before
    size_before=$(du -sh "$target" 2>/dev/null | awk '{print $1}')

    local jpg_count=0 png_count=0 webp_count=0

    # --- Mode 1 hoặc 3: Nén JPG + PNG ---
    if [[ "$img_mode" == "1" || "$img_mode" == "3" ]]; then
        if command -v jpegoptim &>/dev/null; then
            log_info "Đang nén JPG... (quality=${jpg_quality}%) - Chạy đa luồng, vui lòng chờ..."
            jpg_count=$(find "$target" \( -iname "*.jpg" -o -iname "*.jpeg" \) | wc -l)
            find "$target" \( -iname "*.jpg" -o -iname "*.jpeg" \) -print0 | \
                xargs -0 -n 20 -P $(nproc 2>/dev/null || echo 2) jpegoptim --strip-all --all-progressive --max="$jpg_quality" 2>/dev/null
            echo -e "  ✓ Đã xử lý ${GREEN}${jpg_count}${NC} file JPG/JPEG"
        else
            log_warn "jpegoptim không khả dụng, bỏ qua JPG."
        fi

        if command -v optipng &>/dev/null; then
            log_info "Đang nén PNG... (lossless) - Xin vui lòng chờ, tiến trình xử lý sẽ hiện bên dưới..."
            png_count=$(find "$target" -iname "*.png" | wc -l)
            find "$target" -iname "*.png" -print0 | \
                xargs -0 -n 1 -P $(nproc 2>/dev/null || echo 2) optipng -o2 2>/dev/null
            echo -e "  ✓ Đã xử lý ${GREEN}${png_count}${NC} file PNG"
        else
            log_warn "optipng không khả dụng, bỏ qua PNG."
        fi
    fi

    # --- Mode 2 hoặc 3: Convert sang WebP ---
    if [[ "$img_mode" == "2" || "$img_mode" == "3" ]]; then
        if command -v cwebp &>/dev/null; then
            log_info "Đang convert sang WebP... (quality=${webp_quality}%)"
            while IFS= read -r -d '' img; do
                local out="${img%.*}.webp"
                if [[ ! -f "$out" ]]; then
                    cwebp -quiet -q "$webp_quality" "$img" -o "$out" 2>/dev/null && webp_count=$((webp_count + 1))
                fi
            done < <(find "$target" \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" \) -print0 2>/dev/null)
            echo -e "  ✓ Đã tạo ${GREEN}${webp_count}${NC} file WebP mới"
            echo -e "  ${YELLOW}💡 File WebP được đặt cạnh ảnh gốc (.jpg → .webp)${NC}"
            echo -e "  ${YELLOW}   Nginx cần cấu hình thêm để phục vụ WebP tự động.${NC}"
        else
            log_warn "cwebp không khả dụng, bỏ qua WebP conversion."
        fi
    fi

    # --- Thống kê ---
    local size_after
    size_after=$(du -sh "$target" 2>/dev/null | awk '{print $1}')
    echo ""
    echo -e "${BLUE}=================================================${NC}"
    echo -e "${GREEN}  ✅ Hoàn tất!${NC}"
    echo -e "  Dung lượng trước : ${YELLOW}${size_before}${NC}"
    echo -e "  Dung lượng sau   : ${GREEN}${size_after}${NC}"
    echo -e "${BLUE}=================================================${NC}"
    pause
}

_img_install_tools() {
    local mode=$1
    # Detect package manager
    if command -v apt-get &>/dev/null; then
        local PM="apt-get install -y"
        export DEBIAN_FRONTEND=noninteractive
    elif command -v yum &>/dev/null; then
        local PM="yum install -y"
    elif command -v dnf &>/dev/null; then
        local PM="dnf install -y"
    else
        log_warn "Không xác định được package manager."
        return 1
    fi

    if [[ "$mode" == "1" || "$mode" == "3" ]]; then
        command -v jpegoptim &>/dev/null || $PM jpegoptim &>/dev/null
        command -v optipng   &>/dev/null || $PM optipng   &>/dev/null
    fi

    if [[ "$mode" == "2" || "$mode" == "3" ]]; then
        command -v cwebp &>/dev/null || $PM webp &>/dev/null
        # RHEL fallback
        command -v cwebp &>/dev/null || $PM libwebp-tools &>/dev/null
    fi
}

update_system() {
    log_info "Đang cập nhật hệ thống..."
    apt-get update
    apt-get upgrade -y
    
    log_info "Đang update script..."
    cd /root/vps-manager && git pull 2>/dev/null || echo "Git pull skipped."
    
    log_info "Update hoàn tất."
    pause
}

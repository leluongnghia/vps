#!/bin/bash

# modules/backup.sh - Backup & Restore System

backup_menu() {
    while true; do
        clear
        echo -e "${BLUE}=================================================${NC}"
        echo -e "${GREEN}          💾 Sao lưu & Khôi phục${NC}"
        echo -e "${BLUE}=================================================${NC}"
        echo -e "1. Backup Website (Local)"
        echo -e "2. Backup Website (Google Drive)"
        echo -e "3. Restore Website (Local)"
        echo -e "4. Restore Website (Manual Uploaded - trong public_html)"
        echo -e "5. Restore Website (Google Drive)"
        echo -e "6. Cấu hình Google Drive (rclone)"
        echo -e "7. Quản lý bản Backup (List/Delete)"
        echo -e "0. Quay lại Menu chính"
        echo -e "${BLUE}=================================================${NC}"
        read -p "Nhập lựa chọn [0-7]: " choice

        case $choice in
            1) backup_site_local ;;
            2) backup_to_gdrive ;;
            3) restore_site_local ;;
            4) restore_site_manual_upload ;;
            5) restore_site_gdrive ;;
            6) setup_gdrive ;;
            7) manage_backups ;;
            0) return ;;
            *) echo -e "${RED}Lựa chọn không hợp lệ!${NC}"; pause ;;
        esac
    done
}

auto_backup_menu() {
    while true; do
        clear
        echo -e "${BLUE}=================================================${NC}"
        echo -e "${GREEN}          ⏰ Backup Tự động (Cron)${NC}"
        echo -e "${BLUE}=================================================${NC}"

        # Show current cron status
        if crontab -l 2>/dev/null | grep -q "vps-manager-backup"; then
            echo -e "Trạng thái: ${GREEN}● Đang hoạt động${NC}"
            echo -e "Schedule: $(crontab -l | grep 'vps-manager-backup' | awk '{print $1,$2,$3,$4,$5}')"
        else
            echo -e "Trạng thái: ${RED}● Chưa cấu hình${NC}"
        fi
        echo -e "${BLUE}=================================================${NC}"
        echo -e "1. Bật Auto Backup Hàng ngày (3:00 AM)"
        echo -e "2. Bật Auto Backup Hàng tuần (Chủ nhật 2:00 AM)"
        echo -e "3. Backup ngay TẤT CẢ sites (Thủ công)"
        echo -e "4. Xem lịch sử backup"
        echo -e "5. Tắt Auto Backup"
        echo -e "6. Cấu hình giữ bao nhiêu bản (hiện tại: 7 bản)"
        echo -e "0. Quay lại"
        echo -e "${BLUE}=================================================${NC}"
        read -p "Chọn: " c

        case $c in
            1) auto_backup_setup "daily" ;;
            2) auto_backup_setup "weekly" ;;
            3) backup_all_sites ;;
            4) auto_backup_view_history ;;
            5) auto_backup_disable ;;
            6) auto_backup_set_retention ;;
            0) return ;;
            *) echo -e "${RED}Sai lựa chọn.${NC}"; pause ;;
        esac
    done
}

auto_backup_setup() {
    local mode=${1:-daily}
    local script_path="/usr/local/bin/vps-manager-backup.sh"
    local backup_root="/root/backups"
    local keep_days=7

    # Read keep_days from config if exists
    [ -f /root/.vps-manager-backup.conf ] && source /root/.vps-manager-backup.conf

    # Create backup script
    cat > "$script_path" << 'BACKUPSCRIPT'
#!/bin/bash
BACKUP_ROOT="/root/backups"
KEEP_DAYS=7
[ -f /root/.vps-manager-backup.conf ] && source /root/.vps-manager-backup.conf

timestamp=$(date +%F_%H-%M-%S)
LOG="/var/log/vps-auto-backup.log"

echo "[$timestamp] === Auto Backup Start ===" >> "$LOG"

for site_dir in /var/www/*; do
    [ ! -d "$site_dir" ] && continue
    domain=$(basename "$site_dir")
    [[ "$domain" == "html" ]] && continue

    backup_dir="$BACKUP_ROOT/$domain"
    mkdir -p "$backup_dir"

    # Backup code
    if [ -d "$site_dir/public_html" ]; then
        zip -r "$backup_dir/code_${timestamp}.zip" "$site_dir/public_html" -x "*.log" -x "*.tmp" -q
        echo "[$timestamp] Code backup: $domain OK" >> "$LOG"
    fi

    # Backup DB
    db_name=$(echo "$domain" | tr -d '.-' | cut -c1-16)
    if mysql -e "USE $db_name" 2>/dev/null; then
        mysqldump "$db_name" | gzip > "$backup_dir/db_${timestamp}.sql.gz"
        echo "[$timestamp] DB backup: $domain OK" >> "$LOG"
    fi

    # Cleanup old backups (keep last N days)
    find "$backup_dir" -name "code_*.zip" -mtime +$KEEP_DAYS -delete
    find "$backup_dir" -name "db_*.sql.gz" -mtime +$KEEP_DAYS -delete
done

echo "[$timestamp] === Auto Backup Done ===" >> "$LOG"
BACKUPSCRIPT

    chmod +x "$script_path"

    # Remove old cron entry
    crontab -l 2>/dev/null | grep -v "vps-manager-backup" | crontab -

    if [[ "$mode" == "daily" ]]; then
        CRON_TIME="0 3 * * *"
        SCHEDULE_DESC="Hàng ngày lúc 3:00 AM"
    else
        CRON_TIME="0 2 * * 0"
        SCHEDULE_DESC="Hàng tuần (Chủ nhật 2:00 AM)"
    fi

    (crontab -l 2>/dev/null; echo "$CRON_TIME $script_path # vps-manager-backup") | crontab -

    log_info "Đã bật Auto Backup: $SCHEDULE_DESC"
    echo -e "  Script: ${CYAN}$script_path${NC}"
    echo -e "  Log: ${CYAN}/var/log/vps-auto-backup.log${NC}"
    pause
}

backup_all_sites() {
    log_info "Đang backup TẤT CẢ sites..."
    local backup_root="/root/backups"
    local timestamp=$(date +%F_%H-%M-%S)
    local count=0

    for site_dir in /var/www/*; do
        [ ! -d "$site_dir" ] && continue
        domain=$(basename "$site_dir")
        [[ "$domain" == "html" ]] && continue

        backup_dir="$backup_root/$domain"
        mkdir -p "$backup_dir"

        echo -e "\n${CYAN}📦 Backup: $domain${NC}"

        if [ -d "$site_dir/public_html" ]; then
            zip -r "$backup_dir/code_${timestamp}.zip" "$site_dir/public_html" -x "*.log" -q
            echo -e "  ✅ Code: $(du -sh "$backup_dir/code_${timestamp}.zip" | cut -f1)"
        fi

        db_name=$(echo "$domain" | tr -d '.-' | cut -c1-16)
        if mysql -e "USE $db_name" 2>/dev/null; then
            mysqldump "$db_name" | gzip > "$backup_dir/db_${timestamp}.sql.gz"
            echo -e "  ✅ DB: $(du -sh "$backup_dir/db_${timestamp}.sql.gz" | cut -f1)"
        fi
        count=$((count + 1))
    done

    echo -e "\n${GREEN}Đã backup $count sites vào /root/backups/${NC}"
    echo -e "Tổng dung lượng: $(du -sh $backup_root | cut -f1)"
    pause
}

auto_backup_view_history() {
    echo -e "${CYAN}--- Lịch sử Backup ---${NC}"
    if [ -f /var/log/vps-auto-backup.log ]; then
        tail -n 50 /var/log/vps-auto-backup.log
    else
        echo -e "${YELLOW}Chưa có log backup tự động.${NC}"
    fi

    echo -e "\n${CYAN}--- Dung lượng Backup theo Site ---${NC}"
    if [ -d /root/backups ]; then
        du -sh /root/backups/* 2>/dev/null || echo "Chưa có backup nào."
        echo -e "\nTổng: $(du -sh /root/backups 2>/dev/null | cut -f1)"
    fi
    pause
}

auto_backup_disable() {
    read -p "Xác nhận tắt Auto Backup? (y/n): " c
    if [[ "$c" == "y" ]]; then
        crontab -l 2>/dev/null | grep -v "vps-manager-backup" | crontab -
        log_info "Đã tắt Auto Backup."
    fi
    pause
}

auto_backup_set_retention() {
    echo -e "${YELLOW}Số bản backup cần giữ (theo số ngày):${NC}"
    read -p "Giữ backup trong bao nhiêu ngày? (mặc định 7): " days
    days=${days:-7}
    if [[ ! "$days" =~ ^[0-9]+$ ]]; then
        echo -e "${RED}Không hợp lệ.${NC}"; pause; return
    fi
    echo "KEEP_DAYS=$days" > /root/.vps-manager-backup.conf
    log_info "Đã cấu hình giữ backup trong $days ngày."
    pause
}



restore_site_manual_upload() {
    echo -e "${YELLOW}--- Restore từ File Upload thủ công ---${NC}"
    echo -e "Vui lòng upload file backup (.zip / .sql) vào thư mục: /var/www/TEN_MIEN/public_html"
    echo ""

    source "$(dirname "${BASH_SOURCE[0]}")/site.sh"
    select_site || return
    local target_domain="$SELECTED_DOMAIN"
    local search_dir="/var/www/$target_domain/public_html"

    
    # Detect Source Domain (Try to guess from filename or prompt)
    # Usually filenames are code_domain_time.zip
    # We will prompt later if search-replace needed.
    
    # 1. AUTO DETECT BACKUP FILES (Smart Select)
    
    # -> CODE FILES
    code_files=()
    while IFS= read -r file; do
        if [[ -f "$file" ]]; then code_files+=("$(basename "$file")"); fi
    done < <(find "$search_dir" -maxdepth 1 \( -name "*.zip" -o -name "*.tar.gz" \) -type f)
    
    code_file=""
    if [ ${#code_files[@]} -eq 1 ]; then
        code_file="${code_files[0]}"
        log_info "Tự động chọn Code Backup: $code_file"
    elif [ ${#code_files[@]} -gt 1 ]; then
        echo -e "\n${CYAN}Tìm thấy nhiều file Code:${NC}"
        for i in "${!code_files[@]}"; do
            echo -e "$((i+1)). ${code_files[$i]}"
        done
        read -p "Chọn file Code (Enter để bỏ qua): " c_sel
        if [[ -n "$c_sel" && "$c_sel" =~ ^[0-9]+$ ]]; then code_file="${code_files[$((c_sel-1))]}"; fi
    else
        log_warn "Không tìm thấy file Code (.zip, .tar.gz) nào."
    fi

    # -> DB FILES
    db_files=()
    while IFS= read -r file; do
        if [[ -f "$file" ]]; then db_files+=("$(basename "$file")"); fi
    done < <(find "$search_dir" -maxdepth 1 \( -name "*.sql" -o -name "*.sql.gz" \) -type f)
    
    db_file=""
    if [ ${#db_files[@]} -eq 1 ]; then
        db_file="${db_files[0]}"
        log_info "Tự động chọn DB Backup: $db_file"
    elif [ ${#db_files[@]} -gt 1 ]; then
        echo -e "\n${CYAN}Tìm thấy nhiều file Database:${NC}"
        for i in "${!db_files[@]}"; do
            echo -e "$((i+1)). ${db_files[$i]}"
        done
        read -p "Chọn file DB (Enter để bỏ qua): " db_sel
        if [[ -n "$db_sel" && "$db_sel" =~ ^[0-9]+$ ]]; then db_file="${db_files[$((db_sel-1))]}"; fi
    else
        log_warn "Không tìm thấy file Database (.sql, .sql.gz) nào."
    fi
    
    if [ -z "$code_file" ] && [ -z "$db_file" ]; then echo -e "${RED}Lỗi: Không có gì để restore.${NC}"; pause; return; fi

    # 4. Confirm Restore
    echo -e "\n${YELLOW}--- TỔNG QUÁT ---${NC}"
    echo -e "Website ĐÍCH: ${GREEN}$target_domain${NC}"
    echo -e "Nguồn Code  : ${CYAN}${code_file:-[Không thay đổi]}${NC}"
    echo -e "Nguồn DB    : ${CYAN}${db_file:-[Không thay đổi]}${NC}"
    echo -e "${RED}CẢNH BÁO: Dữ liệu hiện tại sẽ bị ghi đè!${NC}"

    read -p "Xác nhận restore? (y/n): " confirm
    if [[ "$confirm" != "y" ]]; then return; fi
    
    # 2. DATA PREPARATION & CREDENTIALS
    # Logic: 
    # 1. Try reading persistent store (~/.vps-manager/sites_data.conf) -> Best
    # 2. Try reading current wp-config.php -> Okay
    # 3. If both fail -> RESET Database Password to a new random one -> Guaranteed to work.
    
    target_db_name=$(echo "$target_domain" | tr -d '.-' | cut -c1-16)
    target_db_user="${target_db_name}_u"
    target_db_pass=""
    
    data_file="$HOME/.vps-manager/sites_data.conf"
    
    # Check Store
    if [ -f "$data_file" ]; then
        db_info=$(grep "^$target_domain|" "$data_file")
        if [ -n "$db_info" ]; then
            target_db_pass=$(echo "$db_info" | cut -d'|' -f4)
            log_info "Đã lấy mật khẩu DB từ kho lưu trữ hệ thống."
        fi
    fi
    
    # Check Config (Fallback)
    if [ -z "$target_db_pass" ]; then
        target_db_pass=$(grep "DB_PASSWORD" "/var/www/$target_domain/public_html/wp-config.php" 2>/dev/null | cut -d "'" -f 4)
        if [ -z "$target_db_pass" ]; then
             target_db_pass=$(grep "DB_PASSWORD" "/var/www/$target_domain/public_html/wp-config.php" 2>/dev/null | cut -d '"' -f 4)
        fi
    fi
    
    # Last Resort: Auto Reset Password
    if [ -z "$target_db_pass" ]; then
        log_warn "Không tìm thấy mật khẩu Database cũ. Đang tạo mật khẩu mới..."
        target_db_pass=$(openssl rand -base64 18 | tr -dc 'a-zA-Z0-9' | head -c 16)
        
        # Reset in MySQL
        log_info "Đang reset mật khẩu DB User: $target_db_user"
        mysql -e "ALTER USER '${target_db_user}'@'localhost' IDENTIFIED BY '${target_db_pass}';" 2>/dev/null
        if [ $? -ne 0 ]; then
             # Maybe user doesn't exist? Create it.
             mysql -e "CREATE USER IF NOT EXISTS '${target_db_user}'@'localhost' IDENTIFIED BY '${target_db_pass}';" 2>/dev/null
             mysql -e "GRANT ALL PRIVILEGES ON ${target_db_name}.* TO '${target_db_user}'@'localhost';" 2>/dev/null
             mysql -e "FLUSH PRIVILEGES;"
        fi
        
        # Save to store for future
        mkdir -p "$(dirname "$data_file")"
        if [ -f "$data_file" ]; then sed -i "/^$target_domain|/d" "$data_file"; fi
        echo "$target_domain|$target_db_name|$target_db_user|$target_db_pass" >> "$data_file"
    fi

    # RESTORE CODE
    if [ -n "$code_file" ]; then
        log_info "Giải nén Code..."
        
        tmp_extract="/root/restore_tmp_$target_domain"
        rm -rf "$tmp_extract"; mkdir -p "$tmp_extract"
        
        if [[ "$code_file" == *.zip ]]; then
            unzip -o -q "$search_dir/$code_file" -d "$tmp_extract"
        elif [[ "$code_file" == *.tar.gz ]]; then
            tar -xzf "$search_dir/$code_file" -C "$tmp_extract"
        else
            log_error "Định dạng file code không hỗ trợ (.zip, .tar.gz)"
            rm -rf "$tmp_extract"
            return
        fi
        
        # Move content to proper place
        log_info "Đang di chuyển dữ liệu..."
        # Find where wp-config.php is in extracted
        wp_root=$(find "$tmp_extract" -name "wp-config.php" -exec dirname {} \; | head -n 1)
        
        if [ -n "$wp_root" ]; then
            cp -a "$wp_root/." "/var/www/$target_domain/public_html/"
        else
            # Try just moving everything if empty
            cp -a "$tmp_extract/." "/var/www/$target_domain/public_html/"
        fi
        
        rm -rf "$tmp_extract"
        
        # RESTORE CORRECT DB CREDENTIALS TO wp-config.php
        log_info "Khôi phục thông tin kết nối Database chuẩn..."
        wp_conf="/var/www/$target_domain/public_html/wp-config.php"
        
        if [ -f "$wp_conf" ] && [ -n "$target_db_pass" ]; then
            # Update DB_NAME
            sed -i "s|define([ ]*['\"]DB_NAME['\"],.*)|define( 'DB_NAME', '$target_db_name' );|" "$wp_conf"
            # Update DB_USER
            sed -i "s|define([ ]*['\"]DB_USER['\"],.*)|define( 'DB_USER', '$target_db_user' );|" "$wp_conf"
            # Update DB_PASSWORD
            sed -i "s|define([ ]*['\"]DB_PASSWORD['\"],.*)|define( 'DB_PASSWORD', '$target_db_pass' );|" "$wp_conf"
        else
            log_warn "Không tìm thấy wp-config.php để ghi cấu hình."
        fi
    fi
    
    # RESTORE DB
    if [ -n "$db_file" ]; then
        log_info "Import Database..."
        if [[ "$db_file" == *.gz ]]; then
            zcat "$search_dir/$db_file" | mysql "$target_db_name"
        else
            mysql "$target_db_name" < "$search_dir/$db_file"
        fi
        mysqlcheck --auto-repair "$target_db_name"
        
        # Auto fix Table Prefix
        log_info "Đang kiểm tra Table Prefix..."
        detected_table=$(mysql -N -B -e "SHOW TABLES LIKE '%_users'" "$target_db_name" | head -n 1)
        if [ -n "$detected_table" ]; then
            new_prefix=${detected_table%users}
            if [ -n "$new_prefix" ]; then
                log_info "Prefix phát hiện: '$new_prefix'. Cập nhật wp-config.php..."
                sed -i "s/\\\$table_prefix\s*=\s*'.*';/\\\$table_prefix = '$new_prefix';/" "/var/www/$target_domain/public_html/wp-config.php"
            fi
        fi
    fi
    
    # AUTO DETECT & SEARCH REPLACE
    log_info "Đang kiểm tra URL cũ trong Database..."
    
    # Ensure WP-CLI (via shared helper from wordpress_tool.sh)
    if ! command -v wp &> /dev/null; then
        log_info "Cài đặt WP-CLI..."
        curl -sO https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar
        chmod +x wp-cli.phar && mv wp-cli.phar /usr/local/bin/wp
    fi
    
    cd "/var/www/$target_domain/public_html"
    
    # Get current siteurl from DB
    old_url=$(wp option get siteurl --allow-root 2>/dev/null)
    # Extract domain from url (remove http:// or https://)
    source_domain=$(echo "$old_url" | sed -e 's|^[^/]*//||' -e 's|/.*$||')
    
    if [ -n "$source_domain" ] && [ "$source_domain" != "$target_domain" ]; then
        log_info "Phát hiện tên miền cũ: $source_domain -> Tên miền mới: $target_domain"
        log_info "Tiến hành thay thế toàn bộ liên kết..."
        
        wp search-replace "http://$source_domain" "http://$target_domain" --allow-root
        wp search-replace "https://$source_domain" "https://$target_domain" --allow-root
        wp search-replace "$source_domain" "$target_domain" --allow-root
        
        log_info "Đã thay thế URL xong."
    else
        log_info "URL trong database ($source_domain) khớp với hiện tại hoặc không tìm thấy. Bỏ qua thay thế."
    fi
    
    # AUTO FIX WORDPRESS CORE IF NEEDED
    # Check if critical files are missing (which causes 'No input file specified/redirect setup')
    if [ ! -f "/var/www/$target_domain/public_html/wp-admin/admin.php" ] || [ ! -f "/var/www/$target_domain/public_html/wp-includes/version.php" ]; then
        log_warn "Phát hiện thiếu file Core WordPress. Đang tự động tải lại Core..."
        
        cd "/var/www/$target_domain/public_html"
        wget -q https://wordpress.org/latest.tar.gz
        if [ -f latest.tar.gz ]; then
            tar -xzf latest.tar.gz
            cp -r wordpress/* .
            rm -rf wordpress latest.tar.gz
            log_info "Đã khôi phục Core WordPress thành công."
        fi
    fi

    # REMOVE CONFLICTING CONFIGS (Critical for open_basedir errors)
    log_info "Đang dọn dẹp cấu hình cũ gây xung đột..."
    find "/var/www/$target_domain/public_html" -name ".user.ini" -delete
    find "/var/www/$target_domain/public_html" -name ".htaccess" -delete
    
    # Clean temporary files if any remain
    if [ -n "$tmp_extract" ] && [ -d "$tmp_extract" ]; then
        rm -rf "$tmp_extract"
    fi

    # FINAL PERMISSIONS FIX (AGAIN to cover new files)
    log_info "Đang thiết lập quyền (Permissions) chuẩn cho WordPress..."
    chown -R www-data:www-data "/var/www/$target_domain/public_html"
    find "/var/www/$target_domain/public_html" -type d -exec chmod 755 {} \;
    find "/var/www/$target_domain/public_html" -type f -exec chmod 644 {} \;
    
    log_info "Restore hoàn tất!"
    pause
}

setup_gdrive() {
    if ! command -v rclone &> /dev/null; then
        echo -e "${YELLOW}Đang cài đặt rclone...${NC}"
        if command -v apt-get &> /dev/null; then
             apt-get update -y && apt-get install -y rclone
        elif command -v yum &> /dev/null; then
             yum install -y rclone
        else
             curl https://rclone.org/install.sh | bash
        fi
    fi
    
    echo -e "${YELLOW}--- HƯỚNG DẪN CẤU HÌNH GOOGLE DRIVE (KHÔNG CẦN CÀI Rclone TRÊN MÁY MẸ) ---${NC}"
    echo -e "${GREEN}MẸO: Sử dụng SSH Tunnel để xác thực trực tiếp trên trình duyệt máy tính.${NC}"
    echo -e "1. Thoát SSH hiện tại (gõ exit)."
    echo -e "2. Kết nối lại SSH với tham số chuyển tiếp port:"
    echo -e "   ${CYAN}ssh -L 53682:127.0.0.1:53682 root@IP_VPS_CUA_BAN${NC}"
    echo -e "3. Vào lại menu này và thực hiện các bước sau:"
    echo -e "   - Chọn ${GREEN}n${NC} (New remote) > Tên: ${GREEN}gdrive${NC}."
    echo -e "   - Storage: Chọn số của Google Drive."
    echo -e "   - Client ID/Secret: ${CYAN}Enter${NC} (bỏ qua)."
    echo -e "   - Scope: ${GREEN}1${NC} (Full access)."
    echo -e "   - Service Account: ${CYAN}Enter${NC} (bỏ qua)."
    echo -e "   - Edit advanced config: ${GREEN}n${NC} (No)."
    echo -e "   - ${YELLOW}Use auto config?${NC}: Chọn ${GREEN}y${NC} (Yes) <- QUAN TRỌNG."
    echo -e "     (Vì đã có SSH Tunnel, VPS sẽ nghĩ là nó có trình duyệt)"
    echo -e "   - Rclone sẽ hiện link: ${CYAN}http://127.0.0.1:53682/auth...${NC}"
    echo -e "   - Copy link đó dán vào trình duyệt Chrome/Safari trên máy tính của bạn."
    echo -e "   - Đăng nhập Google > Allow."
    echo -e "   - Quay lại Terminal VPS, nó sẽ báo Success."
    echo -e "   - Team Drive: ${GREEN}n${NC} > Yes > Quit."
    echo -e "${YELLOW}------------------------------------------------${NC}"
    read -p "Nhấn Enter để bắt đầu cấu hình..."
    
    rclone config
    pause
}

backup_site_local() {
    # Select site from list
    source "$(dirname "${BASH_SOURCE[0]}")/site.sh"
    select_site || return
    domain=$SELECTED_DOMAIN
    timestamp=$(date +%F_%H-%M-%S)
    backup_dir="/root/backups/$domain"
    mkdir -p "$backup_dir"
    
    log_info "Backing up Code..."
    zip -r "$backup_dir/code_$timestamp.zip" "/var/www/$domain/public_html" -x "*.log"
    
    db_name=$(echo "$domain" | tr -d '.-' | cut -c1-16)
    log_info "Backing up DB..."
    mysqldump "$db_name" > "$backup_dir/db_$timestamp.sql"
    gzip "$backup_dir/db_$timestamp.sql"
    
    log_info "Backup hoàn tất tại $backup_dir"
    cleanup_old_backups "$backup_dir" 7
    pause
}

perform_gdrive_backup() {
    local domain=$1
    local remote=$2
    local timestamp=$(date +%F_%H-%M-%S)
    local backup_dir="/root/backups/$domain"
    
    # Ensure zip is installed
    if ! command -v zip &> /dev/null; then
        echo "Installing zip..."
        if command -v apt-get &> /dev/null; then apt-get install -y zip; elif command -v yum &> /dev/null; then yum install -y zip; fi
    fi
    
    echo -e "\n${CYAN}>>> Đang xử lý: $domain${NC}"
    mkdir -p "$backup_dir"
    
    local zip_file="$backup_dir/code_$timestamp.zip"
    local db_file="$backup_dir/db_$timestamp.sql.gz"
    
    # 1. Backup Code
    if [ -d "/var/www/$domain/public_html" ]; then
        log_info "Đang nén mã nguồn (Code)..."
        zip -r "$zip_file" "/var/www/$domain/public_html" -x "*.log" -q
    else
        log_warn "Không tìm thấy thư mục public_html cho $domain"
    fi
    
    # 2. Backup DB
    local db_name=$(echo "$domain" | tr -d '.-' | cut -c1-16)
    if mysql -e "USE $db_name" 2>/dev/null; then
        log_info "Đang dump Database..."
        mysqldump "$db_name" | gzip > "$db_file"
    else
        log_warn "Database $db_name không tồn tại."
    fi
    
    # 3. Upload
    if [ -f "$zip_file" ]; then
        log_info "Đang upload Code lên Google Drive ($remote:vps_backups/$domain)..."
        rclone copy "$zip_file" "$remote:vps_backups/$domain/"
    fi
    
    if [ -f "$db_file" ]; then
        log_info "Đang upload DB lên Google Drive ($remote:vps_backups/$domain)..."
        rclone copy "$db_file" "$remote:vps_backups/$domain/"
    fi
    
    log_info "✅ Backup $domain hoàn tất."
}

backup_to_gdrive() {
    echo -e "\n${CYAN}Danh sách Website trên VPS:${NC}"
    sites=()
    i=1
    for d in /var/www/*; do
        if [[ -d "$d" && "$(basename "$d")" != "html" ]]; then
            domain=$(basename "$d")
            sites+=("$domain")
            echo -e "$i. $domain"
            ((i++))
        fi
    done
    
    if [ ${#sites[@]} -eq 0 ]; then
        echo -e "${RED}Không tìm thấy website nào!${NC}"
        pause
        return
    fi
    
    echo -e "${GREEN}A. Sao lưu TẤT CẢ các website trên${NC}"
    
    read -p "Chọn website [1-${#sites[@]}] hoặc nhập 'A' để backup tất cả: " choice

    # --- Select Remote Logic ---
    echo -e "\n${CYAN}Danh sách các Remote Google Drive đã cấu hình:${NC}"
    
    # Check if rclone is installed
    if ! command -v rclone &> /dev/null; then
        echo -e "${RED}Rclone chưa được cài đặt. Vui lòng cấu hình trước.${NC}"
        pause; return
    fi
    
    remotes=()
    j=1
    # Read remotes into array
    while IFS= read -r line; do
        # 'rclone listremotes' returns names with colon, e.g., 'gdrive:'
        # Remove the trailing colon
        r_name=${line%:}
        remotes+=("$r_name")
    done < <(rclone listremotes 2>/dev/null)
    
    if [ ${#remotes[@]} -eq 0 ]; then
        echo -e "${YELLOW}Chưa tìm thấy remote nào. Sẽ sử dụng mặc định 'gdrive'.${NC}"
        remote="gdrive"
    else
        # Display list
        for r in "${!remotes[@]}"; do
             echo -e "$((r+1)). ${remotes[$r]}"
        done
        
        echo -e "0. Nhập thủ công tên khác"
        read -p "Chọn Remote Store [1-${#remotes[@]}]: " r_choice
        
        if [[ "$r_choice" == "0" ]]; then
             read -p "Nhập tên remote: " remote
        elif [[ "$r_choice" =~ ^[0-9]+$ ]] && [ "$r_choice" -ge 1 ] && [ "$r_choice" -le "${#remotes[@]}" ]; then
             remote="${remotes[$((r_choice-1))]}"
        else
             # Default to first one or 'gdrive' if invalid
             remote="${remotes[0]}" 
             echo -e "${YELLOW}Lựa chọn không hợp lệ. Tự động chọn: $remote${NC}"
        fi
    fi
    
    # Final check
    remote=${remote:-gdrive}
    echo -e "Remote được chọn: ${GREEN}$remote${NC}"

    if [[ "$choice" == "A" || "$choice" == "a" ]]; then
        # Backup ALL
        for domain in "${sites[@]}"; do
            perform_gdrive_backup "$domain" "$remote"
        done
    elif [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "${#sites[@]}" ]; then
        # Backup Single
        domain="${sites[$((choice-1))]}"
        perform_gdrive_backup "$domain" "$remote"
    else
         echo -e "${RED}Lựa chọn không hợp lệ.${NC}"
         pause
         return
    fi
    
    echo -e "\n${GREEN}🎉 Hoàn tất quá trình Backup lên Google Drive.${NC}"
    pause
}

restore_site_local() {
    echo -e "${YELLOW}--- Restore / Migrate Website (Local) ---${NC}"
    echo -e "Chọn Website ĐÍCH (Nơi dữ liệu sẽ được khôi phục vào):"
    echo ""

    source "$(dirname "${BASH_SOURCE[0]}")/site.sh"
    select_site || return
    local target_domain="$SELECTED_DOMAIN"
    


    
    # 2. Select Source Backup (From /root/backups)
    echo -e "\n${CYAN}Chọn Nguồn Backup (Domain gốc của bản sao lưu):${NC}"
    local backup_root="/root/backups"
    if [ ! -d "$backup_root" ]; then echo -e "${RED}Không có backup nào.${NC}"; pause; return; fi
    
    source_folders=()
    j=1
    for d in "$backup_root"/*; do
        if [ -d "$d" ]; then
            s_domain=$(basename "$d")
            source_folders+=("$s_domain")
            echo -e "$j. $s_domain"
            ((j++))
        fi
    done
    
    read -p "Chọn nguồn backup [1-${#source_folders[@]}]: " s_choice
    if ! [[ "$s_choice" =~ ^[0-9]+$ ]] || [ "$s_choice" -lt 1 ] || [ "$s_choice" -gt "${#source_folders[@]}" ]; then
        echo -e "${RED}Lựa chọn không hợp lệ!${NC}"; pause; return
    fi
    source_domain="${source_folders[$((s_choice-1))]}"
    backup_dir="$backup_root/$source_domain"
    
    # 3. Select Backup Files
    echo -e "\n${CYAN}--- Chọn bản Backup Code ---${NC}"
    code_files=()
    k=1
    while IFS= read -r file; do
        if [[ -f "$file" ]]; then
            fname=$(basename "$file")
            code_files+=("$fname")
            echo -e "$k. $fname ($(du -h "$file" | cut -f1))"
            ((k++))
        fi
    done < <(find "$backup_dir" -maxdepth 1 -name "code_*.zip" -type f | sort -r)
    
    read -p "Chọn file Code [1-${#code_files[@]}] (Enter để bỏ qua): " c_sel
    code_file=""
    if [[ -n "$c_sel" && "$c_sel" =~ ^[0-9]+$ ]]; then code_file="${code_files[$((c_sel-1))]}"; fi

    echo -e "\n${CYAN}--- Chọn bản Backup DB ---${NC}"
    db_files=()
    l=1
    while IFS= read -r file; do
        if [[ -f "$file" ]]; then
            fname=$(basename "$file")
            db_files+=("$fname")
            echo -e "$l. $fname ($(du -h "$file" | cut -f1))"
            ((l++))
        fi
    done < <(find "$backup_dir" -maxdepth 1 -name "db_*.sql*" -type f | sort -r)
    
    read -p "Chọn file DB [1-${#db_files[@]}] (Enter để bỏ qua): " db_sel
    db_file=""
    if [[ -n "$db_sel" && "$db_sel" =~ ^[0-9]+$ ]]; then db_file="${db_files[$((db_sel-1))]}"; fi
    
    if [ -z "$code_file" ] && [ -z "$db_file" ]; then echo -e "${RED}Không chọn file nào.${NC}"; pause; return; fi

    # Confirm
    echo -e "${RED}CẢNH BÁO: Dữ liệu trên $target_domain sẽ bị ghi đè!${NC}"
    read -p "Xác nhận restore? (y/n): " confirm
    if [[ "$confirm" != "y" ]]; then return; fi
    
    # Get Target DB Creds from persistent store or wp-config
    target_db_name=$(echo "$target_domain" | tr -d '.-' | cut -c1-16)
    target_db_user="${target_db_name}_u"  # FIX: use _u suffix (matches setup_database)
    target_db_pass=""

    # 1. Try persistent store
    local data_file="$HOME/.vps-manager/sites_data.conf"
    if [ -f "$data_file" ]; then
        local db_info=$(grep "^$target_domain|" "$data_file")
        if [ -n "$db_info" ]; then
            target_db_pass=$(echo "$db_info" | cut -d'|' -f4)
            log_info "Lấy mật khẩu từ kho lưu trữ hệ thống."
        fi
    fi

    # 2. Fallback: wp-config.php
    if [ -z "$target_db_pass" ] && [ -f "/var/www/$target_domain/public_html/wp-config.php" ]; then
        target_db_pass=$(grep "DB_PASSWORD" "/var/www/$target_domain/public_html/wp-config.php" | cut -d "'" -f 4)
        [ -z "$target_db_pass" ] && target_db_pass=$(grep "DB_PASSWORD" "/var/www/$target_domain/public_html/wp-config.php" | cut -d '"' -f 4)
    fi

    # 3. Last resort: generate new password
    if [ -z "$target_db_pass" ]; then
        log_warn "Không tìm thấy mật khẩu DB. Tạo mật khẩu mới..."
        target_db_pass=$(openssl rand -base64 18 | tr -dc 'a-zA-Z0-9' | head -c 16)
        mysql -e "ALTER USER '${target_db_user}'@'localhost' IDENTIFIED BY '${target_db_pass}';" 2>/dev/null
        if [ $? -ne 0 ]; then
            mysql -e "CREATE USER IF NOT EXISTS '${target_db_user}'@'localhost' IDENTIFIED BY '${target_db_pass}';" 2>/dev/null
            mysql -e "GRANT ALL PRIVILEGES ON ${target_db_name}.* TO '${target_db_user}'@'localhost';" 2>/dev/null
            mysql -e "FLUSH PRIVILEGES;"
        fi
        local data_file="$HOME/.vps-manager/sites_data.conf"
        mkdir -p "$(dirname "$data_file")"
        [ -f "$data_file" ] && sed -i "/^$target_domain|/d" "$data_file"
        echo "$target_domain|$target_db_name|$target_db_user|$target_db_pass" >> "$data_file"
    fi

    # RESTORE CODE
    if [ -n "$code_file" ]; then
        log_info "Đang giải nén Code..."
        unzip -o "$backup_dir/$code_file" -d "/var/www/$target_domain/"
        chown -R www-data:www-data "/var/www/$target_domain/public_html"
        
        # Update wp-config with TARGET DB info (if we found it)
        if [ -n "$target_db_pass" ]; then
            log_info "Cập nhật wp-config.php theo Database đích..."
            sed -i "s/DB_NAME', '.*'/DB_NAME', '$target_db_name'/" "/var/www/$target_domain/public_html/wp-config.php"
            sed -i "s/DB_USER', '.*'/DB_USER', '$target_db_user'/" "/var/www/$target_domain/public_html/wp-config.php"
            sed -i "s/DB_PASSWORD', '.*'/DB_PASSWORD', '$target_db_pass'/" "/var/www/$target_domain/public_html/wp-config.php"
        fi
    fi
    
    # RESTORE DB
    if [ -n "$db_file" ]; then
        log_info "Đang import Database..."
        if [[ "$db_file" == *.gz ]]; then
            zcat "$backup_dir/$db_file" | mysql "$target_db_name"
        else
            mysql "$target_db_name" < "$backup_dir/$db_file"
        fi
        
        log_info "Tự động sửa lỗi Database..."
        mysqlcheck --auto-repair "$target_db_name"
        
        # Auto fix Table Prefix
        log_info "Đang kiểm tra Table Prefix..."
        detected_table=$(mysql -N -B -e "SHOW TABLES LIKE '%_users'" "$target_db_name" | head -n 1)
        if [ -n "$detected_table" ]; then
            new_prefix=${detected_table%users}
            if [ -n "$new_prefix" ]; then
                log_info "Prefix phát hiện: '$new_prefix'. Cập nhật wp-config.php..."
                sed -i "s/\\\$table_prefix\s*=\s*'.*';/\\\$table_prefix = '$new_prefix';/" "/var/www/$target_domain/public_html/wp-config.php"
            fi
        fi
    fi
    
    # SEARCH & REPLACE (Migration)
    if [[ "$target_domain" != "$source_domain" ]]; then
        log_info "Phát hiện thay đổi tên miền ($source_domain -> $target_domain)."
        log_info "Đang thay thế URL trong Database..."
        
        # Install wp-cli if needed
        if ! command -v wp &> /dev/null; then
             curl -O https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar
             chmod +x wp-cli.phar
             mv wp-cli.phar /usr/local/bin/wp
        fi
        
        cd "/var/www/$target_domain/public_html"
        # Run search-replace allow-root
        # Try http and https permutations
        wp search-replace "http://$source_domain" "http://$target_domain" --allow-root
        wp search-replace "https://$source_domain" "https://$target_domain" --allow-root
        wp search-replace "$source_domain" "$target_domain" --allow-root
        
        log_info "Đã thay thế URL xong."
    fi
    
    log_info "Restore hoàn tất!"
    pause
}

restore_site_gdrive() {
    # Select site from list
    source "$(dirname "${BASH_SOURCE[0]}")/site.sh"
    select_site || return
    domain=$SELECTED_DOMAIN
    read -p "Remote name (gdrive): " remote
    remote=${remote:-gdrive}
    
    log_info "Files on Cloud:"
    rclone lsl "$remote:vps_backups/$domain/" | tail -n 10
    
    read -p "Cloud Code filename: " cloud_code
    read -p "Cloud DB filename: " cloud_db
    
    tmp_dir="/root/backups/$domain/restore_tmp"
    mkdir -p "$tmp_dir"
    
    log_info "Downloading..."
    rclone copy "$remote:vps_backups/$domain/$cloud_code" "$tmp_dir/"
    rclone copy "$remote:vps_backups/$domain/$cloud_db" "$tmp_dir/"
    
    log_info "Restoring..."
    unzip -o "$tmp_dir/$cloud_code" -d "/var/www/$domain/"
    zcat "$tmp_dir/$cloud_db" | mysql $(echo "$domain" | tr -d '.')
    
    rm -rf "$tmp_dir"
    log_info "Done."
    pause
}

manage_backups() {
    echo -e "1. List Local"
    echo -e "2. List Cloud"
    read -p "Select: " c
    if [[ "$c" == "1" ]]; then
        du -sh /root/backups/*
    elif [[ "$c" == "2" ]]; then
        read -p "Remote: " r
        rclone lsd "${r:-gdrive}:vps_backups/"
    fi
    pause
}

cleanup_old_backups() {
    local dir=$1
    local keep=$2
    cd "$dir"
    ls -tp | grep -v '/$' | tail -n +$(($keep + 1)) | xargs -I {} rm -- {}
}

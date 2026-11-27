#!/bin/bash

# modules/database.sh - Database Management

database_menu() {
    while true; do
        clear
        echo -e "${BLUE}=================================================${NC}"
        echo -e "${GREEN}          Quản lý Database${NC}"
        echo -e "${BLUE}=================================================${NC}"
        echo -e "1. Danh sách Database"
        echo -e "2. Thêm Database & User"
        echo -e "3. Xóa Database"
        echo -e "4. Đổi mật khẩu DB User"
        echo -e "5. Import Database (.sql)"
        echo -e "6. Export Database (Dump)"
        echo -e "7. 🔍 Xem DB theo Website (WordPress)"
        echo -e "8. Quản lý phpMyAdmin"
        echo -e "9. ⚡ Chuyển đổi công nghệ lưu trữ (Convert to InnoDB)"
        echo -e "10. 🛠️  Tối ưu & Sửa chữa tất cả Database (mysqlcheck repair/optimize)"
        echo -e "0. Quay lại Menu chính"
        echo -e "${BLUE}=================================================${NC}"
        read -p "Nhập lựa chọn [0-10]: " choice

        case $choice in
            1) list_databases ;;
            2) add_database ;;
            3) delete_database ;;
            4) change_db_pass ;;
            5) import_database ;;
            6) export_database ;;
            7) view_db_by_website ;;
            8) 
                source "$ROOT_DIR/modules/phpmyadmin.sh"
                phpmyadmin_menu 
                ;;
            9) convert_engine_to_innodb ;;
            10) repair_optimize_databases ;;
            0) return ;;
            *) echo -e "${RED}Lựa chọn không hợp lệ!${NC}"; pause ;;
        esac
    done
}

list_databases() {
    echo -e "${GREEN}Danh sách Database:${NC}"
    mysql -e "SHOW DATABASES;"
    echo ""
    echo -e "${GREEN}Dung lượng Database:${NC}"
    mysql -e "SELECT table_schema 'DB Name', ROUND(SUM(data_length + index_length) / 1024 / 1024, 1) 'Size in MB' FROM information_schema.tables GROUP BY table_schema;"
    pause
}

add_database() {
    read -p "Nhập tên Database mới: " db_name
    read -p "Nhập tên User mới: " db_user
    read -sp "Nhập Mật khẩu: " db_pass
    echo ""

    # Basic input validation
    if [[ -z "$db_name" || -z "$db_user" || -z "$db_pass" ]]; then
        echo -e "${RED}Không được để trống các thông tin!${NC}"
        pause; return
    fi
    if [[ ! "$db_name" =~ ^[a-zA-Z0-9_]+$ ]] || [[ ! "$db_user" =~ ^[a-zA-Z0-9_]+$ ]]; then
        echo -e "${RED}Tên Database và User chỉ được chứa ký tự a-z, A-Z, 0-9, gạch dưới!${NC}"
        pause; return
    fi

    # create_database (core): kiểm tra trùng tên, SQL đi qua stdin nên mật khẩu không lộ trong `ps`
    if create_database "$db_name" "$db_user" "$db_pass"; then
        log_info "Đã tạo Database $db_name và User $db_user."
    else
        log_error "KHÔNG tạo được Database $db_name / User $db_user (xem lỗi phía trên)."
    fi
    pause
}

delete_database() {
    read -p "Nhập tên Database cần xóa: " db_name
    if [[ -z "$db_name" ]] || [[ ! "$db_name" =~ ^[a-zA-Z0-9_]+$ ]]; then
        echo -e "${RED}Tên Database không hợp lệ!${NC}"
        pause; return
    fi
    case "$db_name" in
        mysql|sys|information_schema|performance_schema)
            echo -e "${RED}Không được xoá database hệ thống '$db_name'!${NC}"
            pause; return ;;
    esac
    if ! db_exists "$db_name"; then
        echo -e "${RED}Database '$db_name' không tồn tại.${NC}"
        pause; return
    fi
    read -p "Xác nhận xóa $db_name? (y/n): " confirm
    if [[ "$confirm" == "y" ]]; then
        if mysql_exec "DROP DATABASE \`${db_name}\`;"; then
            log_info "Đã xóa $db_name."
        else
            log_error "Xoá database $db_name thất bại."
        fi
    fi
    pause
}

change_db_pass() {
    echo -e "${YELLOW}--- Đổi Mật Khẩu Database User ---${NC}"
    echo -e "${CYAN}Danh sách MySQL Users hiện có (User@Host):${NC}"
    mysql -e "SELECT CONCAT(User, '@', Host) FROM mysql.user;" 2>/dev/null | tail -n +2 | sed 's/^/  • /'
    echo ""

    read -p "Nhập tên DB User (Ví dụ: root): " db_user
    if [[ -z "$db_user" ]]; then
        echo -e "${RED}Tên User không được để trống!${NC}"
        pause; return
    fi
    if ! valid_identifier "$db_user"; then
        echo -e "${RED}Tên User chỉ được chứa ký tự a-z, A-Z, 0-9, gạch dưới!${NC}"
        pause; return
    fi

    read -sp "Nhập mật khẩu mới (Để trống để tự tạo ngẫu nhiên): " new_pass
    echo ""

    if [[ -z "$new_pass" ]]; then
        new_pass=$(openssl rand -base64 24 | tr -dc 'a-zA-Z0-9' | head -c 24)
        echo -e "Mật khẩu tự tạo: ${GREEN}$new_pass${NC}"
    elif [[ "$new_pass" == *$'\n'* || "$new_pass" == *'"'* ]]; then
        echo -e "${RED}Mật khẩu không được chứa dấu nháy kép hoặc xuống dòng.${NC}"
        pause; return
    fi

    # SQL đi qua stdin (mysql_exec) để mật khẩu không lộ trong `ps`; sql_escape xử lý dấu nháy đơn
    local esc_pass
    esc_pass=$(sql_escape "$new_pass")
    if ! mysql_exec "ALTER USER '${db_user}'@'localhost' IDENTIFIED BY '${esc_pass}';" 2>/dev/null; then
        echo -e "${RED}Lỗi: Có thể User '${db_user}@localhost' không tồn tại. Xem đúng host ở danh sách trên!${NC}"
        pause; return
    fi

    # Nếu đổi mật khẩu root, lưu cấu hình vào .my.cnf TRƯỚC khi chạy lệnh mysql tiếp theo
    # (nếu không, lệnh kế tiếp sẽ dùng mật khẩu cũ và bị từ chối)
    if [[ "$db_user" == "root" ]]; then
        ( umask 077; printf '[client]\nuser=root\npassword="%s"\n' "$new_pass" > /root/.my.cnf )
        chmod 600 /root/.my.cnf
        unset MYSQL_PWD MYSQL_CMD_PREFIX
        log_info "Đã cập nhật file /root/.my.cnf cho truy cập MySQL Root."
    fi

    mysql_exec "FLUSH PRIVILEGES;" 2>/dev/null
    log_info "Đã đổi mật khẩu cho user $db_user."

    pause
}

import_database() {
    read -p "Nhập tên Database đích: " db_name
    read -p "Đường dẫn file .sql: " sql_file
    
    if ! valid_identifier "$db_name"; then
        echo -e "${RED}Tên Database không hợp lệ (chỉ a-z, A-Z, 0-9, gạch dưới)!${NC}"
        pause; return
    fi
    if ! db_exists "$db_name"; then
        echo -e "${RED}Database '$db_name' không tồn tại. Hãy tạo trước (mục 2).${NC}"
        pause; return
    fi
    if [[ ! -f "$sql_file" ]]; then
        echo -e "${RED}File không tồn tại!${NC}"
        pause; return
    fi
    if [[ ! -s "$sql_file" ]]; then
        echo -e "${RED}File rỗng — không import.${NC}"
        pause; return
    fi
    if [[ "$sql_file" == *.gz ]] && ! gzip -t "$sql_file" 2>/dev/null; then
        echo -e "${RED}File .gz bị hỏng — không import.${NC}"
        pause; return
    fi
    if ! verify_sql_dump "$sql_file"; then
        echo -e "${YELLOW}Cảnh báo: file không giống một bản dump SQL thông thường (không thấy CREATE TABLE / INSERT INTO ở phần đầu).${NC}"
        read -p "Vẫn import? (y/n): " force_import
        [[ "$force_import" != "y" && "$force_import" != "Y" ]] && return
    fi

    log_info "Đang import..."
    # Chỉ chạy 1 lần duy nhất: import lỗi giữa chừng thì KHÔNG tự import lại đè lên DB dở dang.
    local rc=0
    if [[ "$sql_file" == *.gz ]]; then
        zcat "$sql_file" | mysql "$db_name"
        local st=("${PIPESTATUS[@]}")
        [[ "${st[0]}" -ne 0 || "${st[1]}" -ne 0 ]] && rc=1
    elif command -v pv &>/dev/null; then
        pv "$sql_file" | mysql "$db_name"
        local st=("${PIPESTATUS[@]}")
        [[ "${st[0]}" -ne 0 || "${st[1]}" -ne 0 ]] && rc=1
    else
        mysql "$db_name" < "$sql_file" || rc=1
    fi

    if [[ $rc -eq 0 ]]; then
        log_info "Import hoàn tất."
    else
        log_error "Import THẤT BẠI — database '$db_name' có thể đang ở trạng thái dở dang. Xem lỗi phía trên."
    fi
    pause
}

export_database() {
    read -p "Nhập tên Database cần export: " db_name
    if ! valid_identifier "$db_name"; then
        echo -e "${RED}Tên Database không hợp lệ (chỉ a-z, A-Z, 0-9, gạch dưới)!${NC}"
        pause; return
    fi
    if ! db_exists "$db_name"; then
        echo -e "${RED}Database '$db_name' không tồn tại.${NC}"
        pause; return
    fi
    local dump_file="/root/${db_name}_$(date +%F_%H-%M-%S).sql.gz"

    log_info "Đang export ra $dump_file..."
    # dump_database (core): kiểm tra exit code, file nén và dòng "Dump completed"
    if ( umask 077; dump_database "$db_name" "$dump_file" ); then
        log_info "Export hoàn tất: $dump_file ($(du -h "$dump_file" | cut -f1))"
    else
        log_error "Export THẤT BẠI — không có file nào được tạo."
    fi
    pause
}

view_db_by_website() {
    echo -e "${GREEN}==================================================${NC}"
    echo -e "${GREEN}     Database Credentials theo Website${NC}"
    echo -e "${GREEN}==================================================${NC}"
    echo ""
    
    echo -e "${YELLOW}💡 Tip: Data được lấy từ file lưu trữ hệ thống hoặc wp-config.php${NC}"
    
    local data_file="$HOME/.vps-manager/sites_data.conf"
    local found=0   # FIX: initialize found counter
    
    # Loop through all websites in /var/www
    for site_dir in /var/www/*; do
        if [[ -d "$site_dir" ]]; then
            local domain=$(basename "$site_dir")
            local wp_config="$site_dir/public_html/wp-config.php"
            
            # Skip system folders
            if [[ "$domain" == "html" ]]; then continue; fi
            
            # 1. Try reading from Local Config Store (Most Reliable)
            local db_info=""
            if [[ -f "$data_file" ]]; then
                db_info=$(grep "^$domain|" "$data_file")
            fi
            
            local db_name=""
            local db_user=""
            local db_pass=""
            local source="System Store"
            
            if [[ -n "$db_info" ]]; then
                db_name=$(echo "$db_info" | cut -d'|' -f2)
                db_user=$(echo "$db_info" | cut -d'|' -f3)
                db_pass=$(echo "$db_info" | cut -d'|' -f4)
            # 2. Fallback to reading wp-config.php (Robust Grep)
            elif [[ -f "$wp_config" ]]; then
                source="wp-config.php"
                # Use robust grep, do NOT use php execution which can print HTML errors
                db_name=$(wp_config_get "$wp_config" DB_NAME)
                db_user=$(wp_config_get "$wp_config" DB_USER)
                db_pass=$(wp_config_get "$wp_config" DB_PASSWORD)
            else
                continue
            fi
            
            # Display info
            echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
            echo -e "${YELLOW}🌐 Website:${NC} ${GREEN}$domain${NC} ($source)"
            echo -e "${YELLOW}📦 Database:${NC} $db_name"
            echo -e "${YELLOW}👤 User:${NC} $db_user"
            echo -e "${YELLOW}🔑 Password:${NC} $db_pass"
                
            # Get database size
            local db_size=$(mysql -e "SELECT ROUND(SUM(data_length + index_length) / 1024 / 1024, 2) FROM information_schema.tables WHERE table_schema = '$db_name';" 2>/dev/null | tail -1)
            if [[ -n "$db_size" ]] && [[ "$db_size" != "NULL" ]]; then
                echo -e "${YELLOW}💾 Size:${NC} ${db_size} MB"
            fi
            
            echo ""
            found=$((found + 1))  # FIX: increment counter
        fi
    done
    
    if [[ $found -eq 0 ]]; then
        echo -e "${YELLOW}Không tìm thấy WordPress site nào.${NC}"
        echo ""
    fi
    
    echo -e "${GREEN}==================================================${NC}"
    echo -e "${YELLOW}💡 Tip: Copy credentials này để config wp-config.php${NC}"
    echo ""
    pause
}

convert_engine_to_innodb() {
    clear
    echo -e "${BLUE}=================================================${NC}"
    echo -e "${GREEN}    Chuyển Đổi Storage Engine (to InnoDB)${NC}"
    echo -e "${BLUE}=================================================${NC}"
    echo -e "Tính năng này sẽ quét các bảng (Tables) đang dùng công nghệ cũ (MyISAM, Aria)"
    echo -e "và chuyển chuẩn hoá 100% sang InnoDB để chịu tải tốt hơn."
    echo ""
    echo -e "CẢNH BÁO: Quá trình này có thể mất vài phút với database lớn."
    read -p "Bạn có chắc chắn muốn quét và tối ưu cơ sở dữ liệu? (y/n): " confirm
    if [[ "$confirm" != "y" ]]; then return; fi

    # Khớp CHÍNH XÁC tên schema hệ thống (trước đây khớp chuỗi con nên bỏ sót DB như "system_shop", "mysqlblog")
    local db_list=$(mysql -N -e "SHOW DATABASES;" | grep -Evx "information_schema|performance_schema|mysql|sys")
    
    for db in $db_list; do
        echo -e "\n${CYAN}>>> Đang quét Database: $db${NC}"
        local tables_to_convert=$(mysql -N -e "SELECT TABLE_NAME FROM information_schema.TABLES WHERE TABLE_SCHEMA = '$db' AND ENGINE != 'InnoDB';")
        
        if [[ -z "$tables_to_convert" ]]; then
            echo -e "  ✅ Mọi thứ đã chuẩn InnoDB. Không cần can thiệp."
        else
            for table in $tables_to_convert; do
                echo -e "  ⏳ Đang convert table: ${YELLOW}${table}${NC} -> InnoDB..."
                mysql -e "ALTER TABLE \`$db\`.\`$table\` ENGINE=InnoDB;" 2>/dev/null
                if [[ $? -eq 0 ]]; then
                    echo -e "  ✓ Thành công"
                else
                    echo -e "  ❌ Lỗi khi convert $table"
                fi
            done
        fi
    done
    
    echo -e "\n${GREEN}🎉 Hoàn tất quá trình đồng bộ Engine sang InnoDB!${NC}"
    pause
}

repair_optimize_databases() {
    clear
    echo -e "${BLUE}=================================================${NC}"
    echo -e "${GREEN}   🛠️  Tối ưu hóa & Tự động Sửa chữa Database${NC}"
    echo -e "${BLUE}=================================================${NC}"
    echo -e "Công cụ này sẽ sử dụng mysqlcheck để:"
    echo -e "  • Kiểm tra toàn vẹn bảng (Check)"
    echo -e "  • Tự động sửa chữa các bảng bị lỗi/crash (Auto-repair)"
    echo -e "  • Chống phân mảnh và tối ưu hóa index (Optimize)"
    echo -e "  • Cập nhật số liệu thống kê bảng (Analyze)"
    echo -e "${BLUE}=================================================${NC}"
    read -p "Bắt đầu chạy tối ưu cho tất cả Database? [Y/n]: " confirm_ro
    [[ "$confirm_ro" == "n" || "$confirm_ro" == "N" ]] && return

    echo ""
    log_info "1. Đang kiểm tra và sửa lỗi các bảng (mysqlcheck --auto-repair)..."
    mysqlcheck -A --auto-repair 2>/dev/null || mariadb-check -A --auto-repair 2>/dev/null

    echo ""
    log_info "2. Đang tối ưu hóa các bảng (mysqlcheck --optimize)..."
    mysqlcheck -A --optimize 2>/dev/null || mariadb-check -A --optimize 2>/dev/null

    echo ""
    echo -e "${GREEN}✅ Quá trình tối ưu và sửa chữa Database đã hoàn tất xuất sắc!${NC}"
    pause
}


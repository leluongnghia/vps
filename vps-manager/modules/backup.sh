#!/bin/bash

# modules/backup.sh - Backup & Restore System
#
# Nguyên tắc của module:
#   - Không bao giờ báo "OK" khi chưa kiểm tra: mọi file zip/dump đều được test sau khi tạo.
#   - Restore kiểm tra file backup TRƯỚC, dump an toàn DB hiện tại TRƯỚC khi DROP, và hoàn tác khi lỗi.
#   - Tên database lấy từ wp-config.php (site_db_name), không suy lại từ tên miền.
#   - WP-CLI chạy bằng user sở hữu site, không phải root.

BACKUP_ROOT="/root/backups"
BACKUP_CONF="/root/.vps-manager-backup.conf"

# Tên thư mục trên Google Drive. Được LƯU LẠI sau lần đầu để backup và restore luôn nhìn cùng 1 thư mục
# (trước đây tính lại mỗi lần nạp module: curl timeout -> đổi sang IP nội bộ -> restore không thấy backup).
_backup_gdrive_dir() {
    local store="/root/.vps-manager/gdrive_dir" name ip
    if [[ -s "$store" ]]; then
        cat "$store"
        return 0
    fi
    ip=$(curl -fs -m 3 http://checkip.amazonaws.com 2>/dev/null | tr -d '[:space:]')
    if [[ "$ip" =~ ^[0-9a-fA-F.:]+$ ]]; then
        name="vps backup $ip"
        mkdir -p "$(dirname "$store")" 2>/dev/null && echo "$name" > "$store" 2>/dev/null
    else
        # Không lấy được IP public: dùng tạm IP nội bộ nhưng KHÔNG lưu, lần sau thử lại
        name="vps backup $(hostname -I 2>/dev/null | awk '{print $1}')"
    fi
    echo "$name"
}
GDRIVE_DIR=$(_backup_gdrive_dir)

# Số ngày giữ backup (đọc từ file cấu hình, mặc định 7)
_backup_keep_days() {
    local d=""
    [[ -f "$BACKUP_CONF" ]] && d=$(grep -E '^KEEP_DAYS=[0-9]+$' "$BACKUP_CONF" | tail -1 | cut -d= -f2)
    if [[ "$d" =~ ^[0-9]+$ ]] && [[ "$d" -ge 1 ]]; then echo "$d"; else echo 7; fi
}

backup_menu() {
    while true; do
        clear
        echo -e "${BLUE}=================================================${NC}"
        echo -e "${GREEN}          💾 Sao lưu & Khôi phục (Backup & Restore)${NC}"
        echo -e "${BLUE}=================================================${NC}"
        echo -e "1. Backup Website (Lưu trữ Local trên VPS)"
        echo -e "2. Backup Website (Đồng bộ lên Google Drive qua Rclone)"
        echo -e "3. Restore Website (Từ bản backup Local)"
        echo -e "4. Restore Website (Từ file zip/sql tải lên thủ công trong public_html)"
        echo -e "5. Restore Website (Khôi phục trực tiếp từ Google Drive)"
        echo -e "6. Cấu hình Google Drive (rclone)"
        echo -e "7. Quản lý bản Backup (Xem danh sách / Xóa)"
        echo -e "8. ⏰ Thiết lập Backup Tự động (Auto Backup Cron hàng ngày/tuần)"
        echo -e "0. Quay lại Menu chính"
        echo -e "${BLUE}=================================================${NC}"
        read -p "Nhập lựa chọn [0-8]: " choice

        case $choice in
            1) backup_site_local ;;
            2) backup_to_gdrive ;;
            3) restore_site_local ;;
            4) restore_site_manual_upload ;;
            5) restore_site_gdrive ;;
            6) setup_gdrive ;;
            7) manage_backups ;;
            8) auto_backup_menu ;;
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
            echo -e "Schedule: $(crontab -l 2>/dev/null | grep 'vps-manager-backup' | awk '{print $1,$2,$3,$4,$5}')"
        else
            echo -e "Trạng thái: ${RED}● Chưa cấu hình${NC}"
        fi
        echo -e "${BLUE}=================================================${NC}"
        echo -e "1. Bật Auto Backup Hàng ngày (3:00 AM)"
        echo -e "2. Bật Auto Backup Hàng tuần (Chủ nhật 2:00 AM)"
        echo -e "3. Backup ngay TẤT CẢ sites (Thủ công)"
        echo -e "4. Xem lịch sử backup"
        echo -e "5. Tắt Auto Backup"
        echo -e "6. Cấu hình số ngày giữ backup (hiện tại: $(_backup_keep_days) ngày)"
        echo -e "0. Quay lại"
        echo -e "${BLUE}=================================================${NC}"
        read -p "Chọn [0-6]: " c

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

    # Check if gdrive is configured
    local use_gdrive=false
    if command -v rclone &> /dev/null && rclone listremotes 2>/dev/null | grep -q "^gdrive:"; then
        use_gdrive=true
    fi

    # Script cron chạy ĐỘC LẬP (không source được helper của vps-manager) nên mọi kiểm tra đều viết thẳng trong đó.
    # Phần đầu chứa 3 biến sinh ra lúc cài; phần thân là heredoc có nháy ('...') nên không cần escape $.
    {
        echo '#!/bin/bash'
        echo '# Sinh tự động bởi vps-manager (modules/backup.sh) - đừng sửa tay, hãy bật lại Auto Backup để tạo lại.'
        printf 'USE_GDRIVE=%q\n' "$use_gdrive"
        printf 'GDRIVE_REMOTE=%q\n' "gdrive"
        printf 'GDRIVE_DIR=%q\n' "$GDRIVE_DIR"
        cat << 'BACKUPSCRIPT'

set -o pipefail
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export HOME="${HOME:-/root}"
umask 077

BACKUP_ROOT="/root/backups"
KEEP_DAYS=7
[ -f /root/.vps-manager-backup.conf ] && . /root/.vps-manager-backup.conf
case "$KEEP_DAYS" in ''|*[!0-9]*) KEEP_DAYS=7 ;; esac
[ "$KEEP_DAYS" -lt 1 ] && KEEP_DAYS=1

LOG="/var/log/vps-auto-backup.log"
timestamp=$(date +%F_%H-%M-%S)
log() { echo "[$(date '+%F %T')] $*" >> "$LOG"; }

# Giới hạn kích thước log (~5MB) để không đầy đĩa
if [ -f "$LOG" ] && [ "$(stat -c %s "$LOG" 2>/dev/null || echo 0)" -gt 5242880 ]; then
    tail -n 2000 "$LOG" > "$LOG.tmp" 2>/dev/null && mv -f "$LOG.tmp" "$LOG"
fi

# Không cho 2 lần chạy chồng nhau
exec 9>/var/lock/vps-manager-backup.lock
if ! flock -n 9; then
    log "SKIP: lần backup trước vẫn đang chạy."
    exit 0
fi

log "=== Auto Backup Start ==="
fail=0
sites_ok=0
sites_err=0
mkdir -p "$BACKUP_ROOT"

# Auto-repair: cài công cụ nén nếu thiếu
for tool in zip unzip gzip; do
    if ! command -v "$tool" > /dev/null 2>&1; then
        if command -v apt-get > /dev/null 2>&1; then
            DEBIAN_FRONTEND=noninteractive apt-get install -y "$tool" >> "$LOG" 2>&1
        elif command -v dnf > /dev/null 2>&1; then
            dnf install -y "$tool" >> "$LOG" 2>&1
        elif command -v yum > /dev/null 2>&1; then
            yum install -y "$tool" >> "$LOG" 2>&1
        fi
    fi
done

# Tên DB thật của site: đọc từ wp-config.php, nếu không có mới suy từ tên miền
site_db_name() {
    local domain=$1 f name=""
    for f in "/var/www/$domain/public_html/wp-config.php" "/var/www/$domain/wp-config.php"; do
        [ -f "$f" ] || continue
        name=$(grep -E "^[[:space:]]*define\([[:space:]]*['\"]DB_NAME['\"]" "$f" | head -1 | \
            sed -E "s/^[^,]*,[[:space:]]*['\"](.*)['\"][[:space:]]*\)[[:space:]]*;.*$/\1/")
        [ -n "$name" ] && break
    done
    [ -z "$name" ] && name=$(echo "$domain" | tr -d '.-' | cut -c1-16)
    echo "$name"
}

for site_dir in /var/www/*; do
    [ -d "$site_dir" ] || continue
    domain=$(basename "$site_dir")
    [ "$domain" = "html" ] && continue

    backup_dir="$BACKUP_ROOT/$domain"
    mkdir -p "$backup_dir"
    site_ok=1

    # ── Code ── (nén theo đường dẫn tương đối "." để restore không tạo ra public_html/var/www/...)
    if [ -d "$site_dir/public_html" ]; then
        zip_file="$backup_dir/${domain}_${timestamp}.zip"
        ( cd "$site_dir/public_html" && zip -q -r "$zip_file" . -x "*.log" -x "*.tmp" ) >> "$LOG" 2>&1
        zrc=$?
        # zip exit 18 = có file không đọc được nhưng archive vẫn hợp lệ
        if { [ "$zrc" -eq 0 ] || [ "$zrc" -eq 18 ]; } && unzip -tqq "$zip_file" > /dev/null 2>&1; then
            log "Code backup: $domain OK ($(du -h "$zip_file" | cut -f1))"
        else
            log "ERROR Code backup: $domain THẤT BẠI (zip exit $zrc) - đã xoá file hỏng."
            rm -f "$zip_file"
            site_ok=0
        fi
    else
        log "SKIP Code: $domain (không có public_html)"
    fi

    # ── Database ──
    db_name=$(site_db_name "$domain")
    case "$db_name" in
        ''|*[!A-Za-z0-9_]*)
            log "SKIP DB: $domain (tên database không hợp lệ: '$db_name')"
            db_name=""
            ;;
    esac
    if [ -n "$db_name" ]; then
        exists=$(mysql -Nse "SELECT COUNT(*) FROM information_schema.schemata WHERE schema_name='$db_name'" 2>> "$LOG")
        mrc=$?
        if [ "$mrc" -ne 0 ]; then
            log "ERROR DB: $domain - không kết nối được MySQL (kiểm tra /root/.my.cnf)."
            site_ok=0
        elif [ "$exists" = "1" ]; then
            db_file="$backup_dir/db_${timestamp}.sql.gz"
            mysqldump --single-transaction --quick --routines --triggers "$db_name" 2>> "$LOG" | gzip > "$db_file"
            rc=("${PIPESTATUS[@]}")
            dump_tail=""
            if [ "${rc[0]}" -eq 0 ] && [ "${rc[1]}" -eq 0 ] && gzip -t "$db_file" 2> /dev/null; then
                dump_tail=$(zcat "$db_file" 2> /dev/null | tail -n 3)
            fi
            case "$dump_tail" in
                *"Dump completed"*)
                    log "DB backup: $domain ($db_name) OK ($(du -h "$db_file" | cut -f1))"
                    ;;
                *)
                    log "ERROR DB backup: $domain ($db_name) THẤT BẠI (mysqldump exit ${rc[0]}) - đã xoá file hỏng."
                    rm -f "$db_file"
                    site_ok=0
                    ;;
            esac
        else
            log "SKIP DB: $domain (không có database '$db_name')"
        fi
    fi

    if [ "$site_ok" -eq 1 ]; then
        sites_ok=$((sites_ok + 1))
    else
        sites_err=$((sites_err + 1))
        fail=1
    fi
done

# ── Upload lên Google Drive ──
upload_ok=1
if [ "$USE_GDRIVE" = "true" ]; then
    log "Đang chuyển backup lên Google Drive ($GDRIVE_REMOTE:$GDRIVE_DIR)..."
    if ! command -v rclone > /dev/null 2>&1; then
        log "ERROR: không tìm thấy rclone - giữ backup tại VPS."
        upload_ok=0
        fail=1
    elif rclone move "$BACKUP_ROOT" "$GDRIVE_REMOTE:$GDRIVE_DIR" --delete-empty-src-dirs >> "$LOG" 2>&1; then
        log "Google Drive: upload OK (đã xoá bản local)."
        # CHỈ dọn bản cũ trên cloud khi lần chạy này hoàn toàn thành công:
        # nếu token hết hạn hoặc backup lỗi mà vẫn dọn thì cloud sẽ trống dần.
        if [ "$fail" -eq 0 ]; then
            if rclone delete "$GDRIVE_REMOTE:$GDRIVE_DIR" --min-age "${KEEP_DAYS}d" >> "$LOG" 2>&1; then
                log "Google Drive: đã dọn bản cũ hơn ${KEEP_DAYS} ngày."
            else
                log "WARN: dọn bản cũ trên Google Drive thất bại."
            fi
        else
            log "WARN: có site backup lỗi - KHÔNG dọn bản cũ trên Google Drive lần này."
        fi
    else
        log "ERROR: upload Google Drive THẤT BẠI - giữ bản local, KHÔNG dọn bản cũ trên cloud."
        upload_ok=0
        fail=1
    fi
fi

# ── Dọn bản cũ tại VPS (chế độ local, hoặc khi upload lỗi để đĩa không đầy) ──
if [ "$USE_GDRIVE" != "true" ] || [ "$upload_ok" -eq 0 ]; then
    for d in "$BACKUP_ROOT"/*/; do
        [ -d "$d" ] || continue
        # Chỉ xoá bản cũ khi thư mục này CÓ bản mới: backup đang lỗi thì không xoá bản tốt cuối cùng
        newer=$(find "$d" -maxdepth 1 -type f \( -name '*.zip' -o -name '*.tar.gz' -o -name 'db_*.sql.gz' -o -name 'db_*.sql' \) -mtime -"$KEEP_DAYS" -print -quit)
        if [ -z "$newer" ]; then
            log "KEEP: $d không có bản mới trong ${KEEP_DAYS} ngày - không dọn."
            continue
        fi
        find "$d" -maxdepth 1 -type f \( -name '*.zip' -o -name '*.tar.gz' -o -name 'db_*.sql.gz' -o -name 'db_*.sql' -o -name 'pre-restore_*' \) -mtime +"$KEEP_DAYS" -delete
    done
fi

if [ "$fail" -eq 0 ]; then
    log "=== Auto Backup Done: $sites_ok site OK ==="
else
    log "=== Auto Backup Done CÓ LỖI: $sites_ok site OK, $sites_err site lỗi (xem các dòng ERROR phía trên) ==="
fi
exit "$fail"
BACKUPSCRIPT
    } > "$script_path"

    chmod 700 "$script_path"
    if ! bash -n "$script_path" 2>/dev/null; then
        log_error "Script backup vừa sinh ra có lỗi cú pháp - KHÔNG bật cron."
        pause; return 1
    fi

    # Remove old cron entry
    crontab_remove_containing "vps-manager-backup"

    if [[ "$mode" == "daily" ]]; then
        CRON_TIME="0 3 * * *"
        SCHEDULE_DESC="Hàng ngày lúc 3:00 AM"
    else
        CRON_TIME="0 2 * * 0"
        SCHEDULE_DESC="Hàng tuần (Chủ nhật 2:00 AM)"
    fi

    (crontab -l 2>/dev/null; echo "$CRON_TIME $script_path # vps-manager-backup") | crontab -

    log_info "Đã bật Auto Backup: $SCHEDULE_DESC"
    if [[ "$use_gdrive" = "true" ]]; then
         echo -e "  Mode: ${GREEN}Upload & Delete Local (Tiết kiệm dung lượng VPS)${NC}"
         echo -e "  Dest: ${GREEN}Google Drive (gdrive:$GDRIVE_DIR)${NC}"
    else
         echo -e "  Link: ${YELLOW}Local Only (Chưa cấu hình gdrive)${NC}"
    fi
    echo -e "  Giữ: ${CYAN}$(_backup_keep_days) ngày${NC}"
    echo -e "  Script: ${CYAN}$script_path${NC}"
    echo -e "  Log: ${CYAN}/var/log/vps-auto-backup.log${NC} (dòng ERROR = backup lỗi)"
    pause
}

# Helper: Ensure backup tools installed
ensure_backup_tools() {
    local t missing=()
    for t in zip unzip gzip; do
        command -v "$t" &>/dev/null || missing+=("$t")
    done
    if [[ ${#missing[@]} -gt 0 ]]; then
        echo "Installing backup tools (${missing[*]})..."
        pkg_install "${missing[@]}" >/dev/null 2>&1
    fi
    for t in zip unzip gzip; do
        if ! command -v "$t" &>/dev/null; then
            log_error "Thiếu công cụ '$t' và không cài được."
            return 1
        fi
    done
    return 0
}

# PHP CLI có mysqli để chạy WP-CLI
_backup_wp_php() {
    local bin
    for bin in php8.4 php8.3 php8.2 php8.1 php8.0 php7.4 php; do
        if command -v "$bin" &>/dev/null && "$bin" -m 2>/dev/null | grep -qi mysqli; then
            echo "$bin"; return 0
        fi
    done
    echo "php"
}

# ------------------------------------------------------------------------------
# Backup 1 site (code + DB) vào $backup_dir và KIỂM TRA kết quả.
# Kết quả: BK_ZIP / BK_DB = đường dẫn file đã tạo (rỗng nếu không có).
# Trả về 0 khi mọi phần có thể backup đều thành công; 1 khi có lỗi hoặc không backup được gì.
# ------------------------------------------------------------------------------
_backup_site() {
    local domain=$1 backup_dir=$2 timestamp=$3
    local pub="/var/www/$domain/public_html" rc=0
    BK_ZIP=""; BK_DB=""

    mkdir -p "$backup_dir" || { log_error "Không tạo được thư mục $backup_dir"; return 1; }
    chmod 700 "$BACKUP_ROOT" "$backup_dir" 2>/dev/null

    local lock_fd
    exec {lock_fd}>"/var/lock/vps_backup_${domain}.lock"
    if ! flock -n "$lock_fd"; then
        echo -e "${RED}Bỏ qua $domain: đang được backup bởi tiến trình khác.${NC}"
        exec {lock_fd}>&-
        return 1
    fi

    # 1. Code
    if [[ -d "$pub" ]]; then
        local need_mb
        need_mb=$(du -sm "$pub" 2>/dev/null | cut -f1)
        need_mb=$(( ${need_mb:-0} + 100 ))
        if ! check_disk_space "$backup_dir" "$need_mb"; then
            rc=1
        else
            local zip_file="$backup_dir/${domain}_${timestamp}.zip"
            log_info "Đang nén mã nguồn (Zip)..."
            ( cd "$pub" && zip -q -r "$zip_file" . -x "*.log" -x "*.tmp" )
            local zrc=$?
            # zip exit 18 = có file không đọc được nhưng archive vẫn hợp lệ
            if [[ $zrc -ne 0 && $zrc -ne 18 ]] || ! unzip -tqq "$zip_file" &>/dev/null; then
                log_error "Nén code $domain THẤT BẠI (zip exit $zrc) - đã xoá file hỏng."
                rm -f "$zip_file"
                rc=1
            else
                [[ $zrc -eq 18 ]] && log_warn "Một số file không đọc được và đã bị bỏ qua khi nén."
                BK_ZIP="$zip_file"
                echo -e "  ✅ Code: $(du -sh "$zip_file" | cut -f1) (đã kiểm tra)"
            fi
        fi
    else
        log_warn "Không tìm thấy thư mục public_html cho $domain"
    fi

    # 2. Database (tên DB thật lấy từ wp-config.php)
    local db_name
    db_name=$(site_db_name "$domain")
    if valid_identifier "$db_name" && db_exists "$db_name"; then
        local db_file="$backup_dir/db_${timestamp}.sql.gz"
        log_info "Đang dump Database $db_name (Gzip)..."
        if dump_database "$db_name" "$db_file"; then
            BK_DB="$db_file"
            echo -e "  ✅ DB: $(du -sh "$db_file" | cut -f1) (đã kiểm tra)"
        else
            rc=1
        fi
    else
        log_warn "Không có database '$db_name' cho $domain - chỉ backup code."
    fi

    flock -u "$lock_fd"
    exec {lock_fd}>&-

    [[ -z "$BK_ZIP" && -z "$BK_DB" ]] && rc=1
    return $rc
}

backup_all_sites() {
    log_info "Đang backup TẤT CẢ sites (Local)..."
    ensure_backup_tools || { pause; return; }

    local timestamp=$(date +%F_%H-%M-%S)
    local count=0 errors=0 site_dir domain

    for site_dir in /var/www/*; do
        [ ! -d "$site_dir" ] && continue
        domain=$(basename "$site_dir")
        [[ "$domain" == "html" ]] && continue

        echo -e "\n${CYAN}📦 Backup: $domain${NC}"
        if _backup_site "$domain" "$BACKUP_ROOT/$domain" "$timestamp"; then
            count=$((count + 1))
            cleanup_old_backups "$BACKUP_ROOT/$domain"
        else
            errors=$((errors + 1))
            echo -e "  ${RED}❌ Backup $domain có lỗi.${NC}"
        fi
    done

    echo ""
    if [[ $errors -eq 0 ]]; then
        echo -e "${GREEN}Đã backup $count sites vào $BACKUP_ROOT/${NC}"
    else
        echo -e "${RED}Backup xong: $count site OK, $errors site LỖI (xem thông báo phía trên).${NC}"
    fi
    echo -e "Tổng dung lượng: $(du -sh "$BACKUP_ROOT" 2>/dev/null | cut -f1)"
    pause
}

auto_backup_view_history() {
    echo -e "${CYAN}--- Lịch sử Backup ---${NC}"
    if [[ -f /var/log/vps-auto-backup.log ]]; then
        tail -n 50 /var/log/vps-auto-backup.log
    else
        echo -e "${YELLOW}Chưa có log backup tự động.${NC}"
    fi

    echo -e "\n${CYAN}--- Dung lượng Backup theo Site ---${NC}"
    if [[ -d "$BACKUP_ROOT" ]]; then
        du -sh "$BACKUP_ROOT"/* 2>/dev/null || echo "Chưa có backup nào."
        echo -e "\nTổng: $(du -sh "$BACKUP_ROOT" 2>/dev/null | cut -f1)"
    fi
    pause
}

auto_backup_disable() {
    read -p "Xác nhận tắt Auto Backup? (y/n): " c
    if [[ "$c" == "y" ]]; then
        crontab_remove_containing "vps-manager-backup"
        log_info "Đã tắt Auto Backup."
    fi
    pause
}

auto_backup_set_retention() {
    echo -e "${YELLOW}Số ngày giữ backup (bản cũ hơn sẽ bị dọn, cả local lẫn Google Drive):${NC}"
    read -p "Giữ backup trong bao nhiêu ngày? (mặc định 7): " days
    days=${days:-7}
    if ! valid_uint "$days"; then
        echo -e "${RED}Không hợp lệ (phải là số nguyên >= 1).${NC}"; pause; return
    fi
    echo "KEEP_DAYS=$days" > "$BACKUP_CONF"
    log_info "Đã cấu hình giữ backup trong $days ngày."
    pause
}

# ------------------------------------------------------------------------------
# Chọn rclone remote. Kết quả: SELECTED_REMOTE. Trả về 1 nếu chưa cài / chưa cấu hình.
# ------------------------------------------------------------------------------
_select_rclone_remote() {
    SELECTED_REMOTE=""
    if ! command -v rclone &> /dev/null; then
        echo -e "${RED}Rclone chưa được cài đặt. Vui lòng cấu hình trước (mục 6).${NC}"
        return 1
    fi

    local remotes=() line
    while IFS= read -r line; do
        [[ -n "$line" ]] && remotes+=("${line%:}")
    done < <(rclone listremotes 2>/dev/null)

    if [[ ${#remotes[@]} -eq 0 ]]; then
        echo -e "${RED}Chưa có remote rclone nào. Vui lòng cấu hình Google Drive trước (mục 6).${NC}"
        return 1
    fi

    if [[ ${#remotes[@]} -eq 1 ]]; then
        SELECTED_REMOTE="${remotes[0]}"
    else
        echo -e "\n${CYAN}Danh sách Remote:${NC}"
        local r r_choice
        for r in "${!remotes[@]}"; do
            echo -e "$((r+1)). ${remotes[$r]}"
        done
        read -p "Chọn Remote [1-${#remotes[@]}] (mặc định: ${remotes[0]}): " r_choice
        if [[ "$r_choice" =~ ^[0-9]+$ ]] && [[ "$r_choice" -ge 1 ]] && [[ "$r_choice" -le "${#remotes[@]}" ]]; then
            SELECTED_REMOTE="${remotes[$((r_choice-1))]}"
        else
            SELECTED_REMOTE="${remotes[0]}"
        fi
    fi
    echo -e "Remote được chọn: ${GREEN}$SELECTED_REMOTE${NC}"
    return 0
}

# ==============================================================================
# RESTORE (một bản cài đặt duy nhất - cả 3 mục Restore trong menu đều gọi vào đây)
# ==============================================================================

# Tìm thư mục gốc của site trong archive đã giải nén
_restore_find_root() {
    local tmp=$1 d=""
    # WordPress: thư mục chứa wp-config.php (hoặc wp-load.php) nông nhất, bỏ qua bản lồng trong wp-content
    d=$(find "$tmp" -name "wp-config.php" -not -path "*/wp-content/*" -printf '%d %h\n' 2>/dev/null | sort -n | head -n 1 | cut -d' ' -f2-)
    [[ -z "$d" ]] && d=$(find "$tmp" -name "wp-load.php" -not -path "*/wp-content/*" -printf '%d %h\n' 2>/dev/null | sort -n | head -n 1 | cut -d' ' -f2-)
    # Archive kiểu cũ của auto-backup (nén theo đường dẫn tuyệt đối): var/www/<domain>/public_html
    [[ -z "$d" ]] && d=$(find "$tmp" -maxdepth 4 -type d -path "*/var/www/*/public_html" 2>/dev/null | head -n 1)
    # Archive chỉ chứa đúng 1 thư mục public_html
    if [[ -z "$d" && -d "$tmp/public_html" && $(find "$tmp" -mindepth 1 -maxdepth 1 | wc -l) -eq 1 ]]; then
        d="$tmp/public_html"
    fi
    echo "${d:-$tmp}"
}

# Ghi 1 hằng số define() vào wp-config.php, escape đúng cho cả PHP lẫn sed
_restore_set_wp_define() {
    local file=$1 key=$2 value=$3 php_val
    php_val=$(printf '%s' "$value" | sed -e 's/\\/\\\\/g' -e "s/'/\\\\'/g")
    sed -i "s|^[[:space:]]*define([[:space:]]*['\"]${key}['\"][[:space:]]*,.*|define( '${key}', '$(sed_escape_repl "$php_val")' );|" "$file"
}

# Import file .sql / .sql.gz vào DB, trả về 1 nếu bất kỳ khâu nào lỗi
_restore_import_sql() {
    local file=$1 db=$2
    if [[ "$file" == *.gz ]]; then
        zcat "$file" | mysql "$db"
        local st=("${PIPESTATUS[@]}")
        [[ "${st[0]}" -eq 0 && "${st[1]}" -eq 0 ]]
    else
        mysql "$db" < "$file"
    fi
}

# Hoàn tác phần code khi restore lỗi giữa chừng
_restore_rollback_code() {
    local pub=$1 old_pub=$2
    [[ -n "$old_pub" && -d "$old_pub" ]] || return 0
    rm -rf "$pub"
    mv "$old_pub" "$pub" && log_warn "Đã khôi phục mã nguồn về trạng thái trước khi restore."
}

# perform_smart_restore <domain đích> <file code|""> <file db|""> [domain nguồn (gợi ý)]
# Trả về 0 khi restore thành công, 1 khi thất bại (site được hoàn tác về trạng thái cũ nếu có thể).
perform_smart_restore() {
    local target_domain=$1
    local code_zip=$2
    local db_sql=$3
    local source_hint=${4:-}
    local new_prefix="wp_"

    local site_root="/var/www/$target_domain"
    local pub="$site_root/public_html"
    local wp_conf="$pub/wp-config.php"
    local ts
    ts=$(date +%F_%H-%M-%S)
    local safety_dir="$BACKUP_ROOT/$target_domain"

    log_info "Bắt đầu Smart Restore cho: $target_domain"

    if [[ -z "$target_domain" || ! -d "$site_root" ]]; then
        log_error "Website đích không tồn tại: $site_root"
        return 1
    fi
    if [[ -z "$code_zip" && -z "$db_sql" ]]; then
        log_error "Không có file nào để restore."
        return 1
    fi

    # ── 0. KIỂM TRA FILE BACKUP TRƯỚC KHI ĐỤNG VÀO SITE ĐANG CHẠY ──
    if [[ -n "$code_zip" ]]; then
        if [[ ! -f "$code_zip" ]]; then
            log_error "Không tìm thấy file code: $code_zip"; return 1
        fi
        case "$code_zip" in
            *.zip)
                command -v unzip &>/dev/null || pkg_install unzip >/dev/null 2>&1
                if ! unzip -tqq "$code_zip" &>/dev/null; then
                    log_error "File zip bị hỏng hoặc không đọc được: $code_zip - HUỶ restore, site chưa bị thay đổi."
                    return 1
                fi ;;
            *.tar.gz|*.tgz)
                if ! tar -tzf "$code_zip" &>/dev/null; then
                    log_error "File tar.gz bị hỏng: $code_zip - HUỶ restore, site chưa bị thay đổi."
                    return 1
                fi ;;
            *)
                log_error "Định dạng file code không hỗ trợ (cần .zip hoặc .tar.gz): $code_zip"
                return 1 ;;
        esac
    fi
    if [[ -n "$db_sql" ]]; then
        if [[ ! -f "$db_sql" ]] || ! verify_sql_dump "$db_sql"; then
            log_error "File database rỗng, hỏng hoặc không phải bản dump SQL: $db_sql - HUỶ restore, site chưa bị thay đổi."
            return 1
        fi
        ensure_mysql_access || return 1
    fi

    # ── 1. Thông tin DB đích (đọc TRƯỚC khi code bị thay) ──
    local owner
    owner=$(site_owner "$pub")

    local target_db_name target_db_user target_db_pass
    target_db_name=$(site_db_name "$target_domain")
    if ! valid_identifier "$target_db_name"; then
        log_error "Tên database đích không hợp lệ: '$target_db_name'"
        return 1
    fi
    target_db_user=$(wp_config_get "$wp_conf" DB_USER)
    target_db_pass=$(wp_config_get "$wp_conf" DB_PASSWORD)

    local data_file="$HOME/.vps-manager/sites_data.conf"
    if [[ -f "$data_file" ]]; then
        local rec
        rec=$(awk -F'|' -v d="$target_domain" '$1 == d { print; exit }' "$data_file")
        if [[ -n "$rec" && "$(echo "$rec" | cut -d'|' -f2)" == "$target_db_name" ]]; then
            [[ -z "$target_db_user" ]] && target_db_user=$(echo "$rec" | cut -d'|' -f3)
            [[ -z "$target_db_pass" ]] && target_db_pass=$(echo "$rec" | cut -d'|' -f4-)
        fi
    fi
    if ! valid_identifier "$target_db_user" || [[ "$target_db_user" == "root" ]]; then
        target_db_user="${target_db_name}_u"
    fi

    # ── 2. Giải nén code ra thư mục tạm (site vẫn chưa bị đụng tới) ──
    local tmp_extract="" src_root=""
    if [[ -n "$code_zip" ]]; then
        log_info "Giải nén Code..."
        tmp_extract=$(mktemp -d "/root/restore_tmp_XXXXXX") || { log_error "Không tạo được thư mục tạm."; return 1; }
        local xrc=0
        if [[ "$code_zip" == *.zip ]]; then
            unzip -o -q "$code_zip" -d "$tmp_extract" || xrc=$?
            # unzip exit 1 = chỉ có cảnh báo, dữ liệu vẫn đầy đủ
            [[ $xrc -eq 1 ]] && xrc=0
        else
            tar -xzf "$code_zip" -C "$tmp_extract" || xrc=$?
        fi
        if [[ $xrc -ne 0 ]]; then
            log_error "Giải nén thất bại (exit $xrc, có thể hết dung lượng đĩa) - HUỶ restore, site chưa bị thay đổi."
            rm -rf "$tmp_extract"
            return 1
        fi
        src_root=$(_restore_find_root "$tmp_extract")
        if [[ -z "$(ls -A "$src_root" 2>/dev/null)" ]]; then
            log_error "Archive không chứa file nào - HUỶ restore."
            rm -rf "$tmp_extract"
            return 1
        fi
    fi

    # ── 3. Dump an toàn DB hiện tại trước khi DROP ──
    local safety_dump=""
    if [[ -n "$db_sql" ]] && db_exists "$target_db_name"; then
        mkdir -p "$safety_dir" && chmod 700 "$safety_dir" 2>/dev/null
        safety_dump="$safety_dir/pre-restore_db_${ts}.sql.gz"
        log_info "Đang dump an toàn database hiện tại -> $safety_dump"
        if ! dump_database "$target_db_name" "$safety_dump"; then
            safety_dump=""
            echo -e "${RED}Không tạo được bản dump an toàn của database hiện tại.${NC}"
            echo -e "${RED}Nếu tiếp tục và import lỗi, dữ liệu hiện tại sẽ KHÔNG khôi phục được.${NC}"
            local go_on=""
            [[ -t 0 ]] && read -p "Vẫn tiếp tục restore? (gõ 'yes' để tiếp tục): " go_on
            if [[ "$go_on" != "yes" ]]; then
                log_warn "Đã huỷ restore, site chưa bị thay đổi."
                [[ -n "$tmp_extract" ]] && rm -rf "$tmp_extract"
                return 1
            fi
        fi
    fi

    # ── 4. Thay code: chuyển bản cũ sang bên (để hoàn tác được), không trộn file cũ-mới ──
    local old_pub=""
    if [[ -n "$tmp_extract" ]]; then
        log_info "Thay thế mã nguồn..."
        if [[ -d "$pub" ]]; then
            old_pub="${pub}.pre-restore_${ts}"
            if ! mv "$pub" "$old_pub"; then
                log_error "Không chuyển được thư mục public_html hiện tại - HUỶ restore."
                rm -rf "$tmp_extract"
                return 1
            fi
        fi
        mkdir -p "$pub"
        if ! cp -a "$src_root/." "$pub/"; then
            log_error "Sao chép code thất bại (có thể hết dung lượng đĩa)."
            rm -rf "$tmp_extract"
            if [[ -n "$old_pub" ]]; then
                _restore_rollback_code "$pub" "$old_pub"
            else
                rm -rf "$pub"
            fi
            return 1
        fi
        rm -rf "$tmp_extract"

        # File backup nằm trong public_html cũ (restore từ file upload) -> trỏ sang vị trí mới của chúng
        if [[ -n "$old_pub" ]]; then
            [[ "$db_sql" == "$pub/"* ]]   && db_sql="$old_pub/${db_sql#"$pub/"}"
            [[ "$code_zip" == "$pub/"* ]] && code_zip="$old_pub/${code_zip#"$pub/"}"
            # Archive không kèm wp-config.php -> giữ wp-config của site đích
            if [[ ! -f "$wp_conf" && -f "$old_pub/wp-config.php" ]]; then
                cp -a "$old_pub/wp-config.php" "$wp_conf"
            fi
        fi
    fi

    # ── 5. Tài khoản DB + wp-config ──
    if [[ -n "$db_sql" || -f "$wp_conf" ]]; then
        ensure_mysql_access || { _restore_rollback_code "$pub" "$old_pub"; return 1; }
        if [[ -z "$target_db_pass" ]]; then
            log_warn "Không tìm thấy mật khẩu DB. Đang tạo mới..."
            target_db_pass=$(openssl rand -base64 18 | tr -dc 'a-zA-Z0-9' | head -c 16)
        fi
        local esc_pass
        esc_pass=$(sql_escape "$target_db_pass")
        # SQL đi qua stdin (mysql_exec) nên mật khẩu không lộ trong `ps`
        mysql_exec "CREATE USER IF NOT EXISTS '${target_db_user}'@'localhost' IDENTIFIED BY '${esc_pass}';" 2>/dev/null
        mysql_exec "ALTER USER '${target_db_user}'@'localhost' IDENTIFIED BY '${esc_pass}';" 2>/dev/null

        mkdir -p "$(dirname "$data_file")"
        if [[ -f "$data_file" ]]; then
            awk -F'|' -v d="$target_domain" '$1 != d' "$data_file" > "${data_file}.tmp" && mv -f "${data_file}.tmp" "$data_file"
        fi
        echo "$target_domain|$target_db_name|$target_db_user|$target_db_pass" >> "$data_file"
        chmod 600 "$data_file" 2>/dev/null

        if [[ -f "$wp_conf" ]]; then
            _restore_set_wp_define "$wp_conf" DB_NAME "$target_db_name"
            _restore_set_wp_define "$wp_conf" DB_USER "$target_db_user"
            _restore_set_wp_define "$wp_conf" DB_PASSWORD "$target_db_pass"
        fi
    fi

    # ── 6. Restore DB ──
    if [[ -n "$db_sql" ]]; then
        log_info "Import Database..."
        local import_ok=1
        # Tạo lại database để tránh trộn bảng cũ-mới
        if ! mysql_exec "DROP DATABASE IF EXISTS \`${target_db_name}\`; CREATE DATABASE \`${target_db_name}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"; then
            import_ok=0
        elif ! _restore_import_sql "$db_sql" "$target_db_name"; then
            import_ok=0
        fi

        if [[ $import_ok -ne 1 ]]; then
            log_error "Import database THẤT BẠI."
            if [[ -n "$safety_dump" ]]; then
                log_warn "Đang khôi phục database cũ từ bản dump an toàn..."
                if mysql_exec "DROP DATABASE IF EXISTS \`${target_db_name}\`; CREATE DATABASE \`${target_db_name}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;" \
                    && _restore_import_sql "$safety_dump" "$target_db_name"; then
                    log_warn "Đã khôi phục database về trạng thái trước khi restore."
                else
                    log_error "KHÔNG khôi phục được database cũ! Bản dump an toàn nằm tại: $safety_dump"
                fi
            else
                log_error "Không có bản dump an toàn - database '$target_db_name' hiện đang rỗng/dở dang."
            fi
            mysql_exec "GRANT ALL PRIVILEGES ON \`${target_db_name}\`.* TO '${target_db_user}'@'localhost'; FLUSH PRIVILEGES;" 2>/dev/null
            _restore_rollback_code "$pub" "$old_pub"
            return 1
        fi

        mysql_exec "GRANT ALL PRIVILEGES ON \`${target_db_name}\`.* TO '${target_db_user}'@'localhost'; FLUSH PRIVILEGES;" 2>/dev/null
        mysqlcheck --auto-repair "$target_db_name" >/dev/null 2>&1

        # Table Prefix Fix: lấy bảng "*users" có tên ngắn nhất (tránh nhầm bảng của plugin / multisite)
        local detected_table
        detected_table=$(mysql -N -B -e "SHOW TABLES LIKE '%users'" "$target_db_name" 2>/dev/null | awk '{ print length($0), $0 }' | sort -n | head -n 1 | cut -d' ' -f2-)
        if [[ -n "$detected_table" ]]; then
            new_prefix=${detected_table%users}
            if [[ "$new_prefix" =~ ^[A-Za-z0-9_]+$ ]] && [[ -f "$wp_conf" ]]; then
                sed -i "s/\\\$table_prefix\s*=\s*'.*';/\\\$table_prefix = '$new_prefix';/" "$wp_conf"
            fi
        fi
    elif [[ -f "$wp_conf" ]]; then
        mysql_exec "GRANT ALL PRIVILEGES ON \`${target_db_name}\`.* TO '${target_db_user}'@'localhost'; FLUSH PRIVILEGES;" 2>/dev/null
        local cur_prefix
        cur_prefix=$(grep -E '^\s*\$table_prefix' "$wp_conf" | head -n 1 | sed -E "s/.*=\s*['\"]([^'\"]*)['\"].*/\1/")
        [[ "$cur_prefix" =~ ^[A-Za-z0-9_]+$ ]] && new_prefix="$cur_prefix"
    fi

    # ── 7. Phân quyền (trước khi chạy WP-CLI bằng user của site) ──
    log_info "Phân quyền & Dọn dẹp..."
    chown -R "${owner}:" "$pub"
    find "$pub" -type d -exec chmod 755 {} +
    find "$pub" -type f -exec chmod 644 {} +
    [[ -f "$wp_conf" ]] && chmod 640 "$wp_conf"
    # Remove bad configs (.user.ini của host cũ thường trỏ sai đường dẫn và làm PHP lỗi)
    find "$pub" -name ".user.ini" -delete
    selinux_restore "$pub"

    # ── 8. Search Replace URL (khi domain nguồn khác domain đích) ──
    local url_note=""
    if [[ -f "$wp_conf" ]] && pushd "$pub" >/dev/null 2>&1; then
        # (đứng trong web root: WP-CLI chạy bằng user của site không đọc được /root)
        # Lấy URL cũ trực tiếp từ database để không bị Redis/object cache làm sai
        local old_url source_domain
        old_url=$(mysql -N -B -e "SELECT option_value FROM \`${target_db_name}\`.\`${new_prefix}options\` WHERE option_name='siteurl'" 2>/dev/null | head -n 1)
        source_domain=$(echo "$old_url" | sed -e 's|^[^/]*//||' -e 's|/.*$||')
        [[ -z "$source_domain" ]] && source_domain="$source_hint"

        if [[ -n "$source_domain" ]] && [[ "$source_domain" != "$target_domain" ]]; then
            log_info "Migrate Domain: $source_domain -> $target_domain"
            if ensure_wp_cli; then
                # WP-CLI chạy bằng user của site (không phải root), không nạp plugin/theme khi thay URL
                local wp_cmd
                wp_cmd="$(wp_cmd_prefix "$pub" "$(_backup_wp_php)") --skip-plugins --skip-themes"
                local sr_fail=0
                $wp_cmd search-replace "http://$source_domain" "http://$target_domain" --quiet || sr_fail=1
                $wp_cmd search-replace "https://$source_domain" "https://$target_domain" --quiet || sr_fail=1
                # Lượt thay tên miền trần: bỏ qua khi domain đích CHỨA domain nguồn
                # (vd example.com -> staging.example.com sẽ thành staging.staging.example.com)
                if [[ "$target_domain" != *"$source_domain"* ]]; then
                    $wp_cmd search-replace "$source_domain" "$target_domain" --quiet || sr_fail=1
                fi
                $wp_cmd cache flush &>/dev/null
                if [[ $sr_fail -ne 0 ]]; then
                    url_note="Thay URL $source_domain -> $target_domain có lỗi - hãy kiểm tra lại siteurl/home."
                fi
            else
                url_note="Không cài được WP-CLI nên CHƯA thay URL $source_domain -> $target_domain trong database."
            fi
        elif command -v wp &>/dev/null; then
            $(wp_cmd_prefix "$pub" "$(_backup_wp_php)") --skip-plugins --skip-themes cache flush &>/dev/null
        fi
        popd >/dev/null 2>&1
    fi

    # ── 9. Hoàn tất: chuyển file backup upload thủ công ra khỏi web root, xoá bản code cũ ──
    if [[ -n "$old_pub" && -d "$old_pub" ]]; then
        local f
        for f in "$code_zip" "$db_sql"; do
            if [[ -n "$f" && "$f" == "$old_pub/"* && -f "$f" ]]; then
                mkdir -p "$safety_dir" && mv -f "$f" "$safety_dir/" \
                    && log_info "Đã chuyển $(basename "$f") sang $safety_dir/ (không để file backup trong web root)."
            fi
        done
        rm -rf "$old_pub"
    fi

    log_info "✅ Smart Restore hoàn tất cho $target_domain"
    [[ -n "$safety_dump" ]] && echo -e "  Bản dump DB trước khi restore: ${CYAN}$safety_dump${NC}"
    [[ -n "$url_note" ]] && log_warn "$url_note"
    return 0
}

# Gọi restore và báo kết quả trung thực
_run_restore() {
    if perform_smart_restore "$@"; then
        return 0
    fi
    echo -e "${RED}❌ Restore THẤT BẠI cho $1 (xem lỗi phía trên).${NC}"
    return 1
}

restore_site_manual_upload() {
    echo -e "${YELLOW}--- Restore từ File Upload thủ công ---${NC}"
    echo -e "Vui lòng upload file backup (.zip / .sql) vào thư mục: /var/www/TEN_MIEN/public_html"

    source "$(dirname "${BASH_SOURCE[0]}")/site.sh"
    select_site || return
    local target_domain="$SELECTED_DOMAIN"
    local search_dir="/var/www/$target_domain/public_html"

    # Detect files (mới nhất trước)
    local code_file=$(find "$search_dir" -maxdepth 1 \( -name "*.zip" -o -name "*.tar.gz" \) -type f -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -n 1 | cut -d' ' -f2-)
    local db_file=$(find "$search_dir" -maxdepth 1 \( -name "*.sql" -o -name "*.sql.gz" \) -type f -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -n 1 | cut -d' ' -f2-)

    if [[ -z "$code_file" ]] && [[ -z "$db_file" ]]; then
        echo -e "${RED}Lỗi: Không tìm thấy file .zip hoặc .sql trong public_html${NC}"
        pause; return
    fi

    echo -e "Code Found: ${CYAN}$(basename "$code_file" 2>/dev/null)${NC}"
    echo -e "DB Found  : ${CYAN}$(basename "$db_file" 2>/dev/null)${NC}"
    echo -e "${RED}CẢNH BÁO: Dữ liệu trên $target_domain sẽ bị ghi đè!${NC}"

    read -p "Tiến hành Restore? (y/n): " c
    if [[ "$c" == "y" ]]; then
        _run_restore "$target_domain" "$code_file" "$db_file"
    fi
    pause
}

restore_site_gdrive() {
    echo -e "${YELLOW}--- Restore từ Google Drive (Smart) ---${NC}"

    source "$(dirname "${BASH_SOURCE[0]}")/site.sh"
    select_site || return
    local target_domain="$SELECTED_DOMAIN"

    _select_rclone_remote || { pause; return; }
    local remote="$SELECTED_REMOTE"

    # List Files in domain folder
    echo -e "\n${CYAN}File trên Cloud ($remote:$GDRIVE_DIR/$target_domain/):${NC}"
    if ! rclone lsl "$remote:$GDRIVE_DIR/$target_domain/" | tail -n 10; then
        echo -e "${RED}Không đọc được danh sách file trên Cloud.${NC}"
        pause; return
    fi

    echo -e "\nCopy-paste tên file cần restore:"
    read -p "File Code (.zip) [Enter để bỏ qua]: " cloud_code
    read -p "File DB (.sql.gz) [Enter để bỏ qua]: " cloud_db

    if [[ -z "$cloud_code" ]] && [[ -z "$cloud_db" ]]; then return; fi
    if [[ "$cloud_code" == */* || "$cloud_db" == */* ]]; then
        echo -e "${RED}Tên file không được chứa dấu '/'.${NC}"
        pause; return
    fi

    echo -e "${RED}CẢNH BÁO: Dữ liệu trên $target_domain sẽ bị ghi đè!${NC}"
    read -p "Xác nhận restore? (y/n): " confirm
    [[ "$confirm" != "y" ]] && return

    # Download logic
    local tmp_dir
    tmp_dir=$(mktemp -d "/root/restore_cloud_XXXXXX") || { log_error "Không tạo được thư mục tạm."; pause; return; }

    local local_code=""
    local local_db=""

    if [[ -n "$cloud_code" ]]; then
        log_info "Đang tải Code: $cloud_code ..."
        if ! rclone copy "$remote:$GDRIVE_DIR/$target_domain/$cloud_code" "$tmp_dir/" --progress || [[ ! -s "$tmp_dir/$cloud_code" ]]; then
            log_error "Tải file code từ Cloud thất bại - HUỶ restore, site chưa bị thay đổi."
            rm -rf "$tmp_dir"; pause; return
        fi
        local_code="$tmp_dir/$cloud_code"
    fi

    if [[ -n "$cloud_db" ]]; then
        log_info "Đang tải DB: $cloud_db ..."
        if ! rclone copy "$remote:$GDRIVE_DIR/$target_domain/$cloud_db" "$tmp_dir/" --progress || [[ ! -s "$tmp_dir/$cloud_db" ]]; then
            log_error "Tải file DB từ Cloud thất bại - HUỶ restore, site chưa bị thay đổi."
            rm -rf "$tmp_dir"; pause; return
        fi
        local_db="$tmp_dir/$cloud_db"
    fi

    # Execute Smart Restore
    _run_restore "$target_domain" "$local_code" "$local_db"

    # Cleanup download
    rm -rf "$tmp_dir"
    pause
}

setup_gdrive() {
    if ! command -v rclone &> /dev/null; then
        echo -e "${YELLOW}Đang cài đặt rclone...${NC}"
        # Ưu tiên gói của distro (có chữ ký); chỉ khi không có mới dùng script chính thức, tải ra file rồi mới chạy
        pkg_install rclone >/dev/null 2>&1
        if ! command -v rclone &> /dev/null; then
            local rc_tmp
            rc_tmp=$(mktemp) || { log_error "Không tạo được file tạm."; pause; return; }
            if safe_download "https://rclone.org/install.sh" "$rc_tmp"; then
                bash "$rc_tmp"
            fi
            rm -f "$rc_tmp"
        fi
        if ! command -v rclone &> /dev/null; then
            log_error "Không cài được rclone."
            pause; return
        fi
    fi

    echo -e "${YELLOW}--- HƯỚNG DẪN CẤU HÌNH GOOGLE DRIVE (KHÔNG CẦN CÀI Rclone TRÊN MÁY MẸ) ---${NC}"
    echo -e "MẸO: Sử dụng SSH Tunnel để xác thực trực tiếp trên trình duyệt máy tính.${NC}"
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
    local domain=$SELECTED_DOMAIN
    local timestamp=$(date +%F_%H-%M-%S)
    local backup_dir="$BACKUP_ROOT/$domain"

    ensure_backup_tools || { pause; return; }

    if _backup_site "$domain" "$backup_dir" "$timestamp"; then
        log_info "Backup hoàn tất tại $backup_dir"
        cleanup_old_backups "$backup_dir"
    else
        echo -e "${RED}❌ Backup $domain CÓ LỖI (xem thông báo phía trên). Bản backup cũ được giữ nguyên.${NC}"
    fi
    pause
}

# Upload 1 file lên cloud rồi mới xoá bản local (rclone move tự kiểm tra checksum trước khi xoá)
_gdrive_upload() {
    local file=$1 remote=$2 domain=$3
    if rclone move "$file" "$remote:$GDRIVE_DIR/$domain/"; then
        return 0
    fi
    log_error "Upload $(basename "$file") THẤT BẠI - file vẫn được giữ tại $(dirname "$file")."
    return 1
}

perform_gdrive_backup() {
    local domain=$1
    local remote=$2
    local timestamp=$(date +%F_%H-%M-%S)
    local backup_dir="$BACKUP_ROOT/$domain"
    local rc=0

    echo -e "\n${CYAN}>>> Đang xử lý: $domain${NC}"

    _backup_site "$domain" "$backup_dir" "$timestamp" || rc=1

    # Upload & Remove Local (chỉ những file đã qua kiểm tra)
    if [[ -n "$BK_ZIP" ]]; then
        log_info "Đang upload Code lên Google Drive (và xóa cục bộ)..."
        _gdrive_upload "$BK_ZIP" "$remote" "$domain" || rc=1
    fi
    if [[ -n "$BK_DB" ]]; then
        log_info "Đang upload DB lên Google Drive (và xóa cục bộ)..."
        _gdrive_upload "$BK_DB" "$remote" "$domain" || rc=1
    fi

    # Cleanup empty dir if exists
    rmdir "$backup_dir" 2>/dev/null

    if [[ $rc -eq 0 ]]; then
        log_info "✅ Backup $domain hoàn tất (Đã giải phóng dung lượng VPS)."
    else
        echo -e "${RED}❌ Backup $domain lên Google Drive CÓ LỖI (xem thông báo phía trên).${NC}"
    fi
    return $rc
}

backup_to_gdrive() {
    echo -e "\n${CYAN}Danh sách Website trên VPS:${NC}"
    local sites=() d domain
    local i=1
    for d in /var/www/*; do
        if [[ -d "$d" && "$(basename "$d")" != "html" ]]; then
            domain=$(basename "$d")
            sites+=("$domain")
            echo -e "$i. $domain"
            ((i++))
        fi
    done

    if [[ ${#sites[@]} -eq 0 ]]; then
        echo -e "${RED}Không tìm thấy website nào!${NC}"
        pause
        return
    fi

    echo -e "${GREEN}A. Sao lưu TẤT CẢ các website trên${NC}"

    read -p "Chọn website [1-${#sites[@]}] hoặc nhập 'A' để backup tất cả: " choice
    if [[ "$choice" != "A" && "$choice" != "a" ]] && { ! [[ "$choice" =~ ^[0-9]+$ ]] || [[ "$choice" -lt 1 ]] || [[ "$choice" -gt "${#sites[@]}" ]]; }; then
        echo -e "${RED}Lựa chọn không hợp lệ.${NC}"
        pause
        return
    fi

    _select_rclone_remote || { pause; return; }
    local remote="$SELECTED_REMOTE"
    ensure_backup_tools || { pause; return; }

    local errors=0
    if [[ "$choice" == "A" || "$choice" == "a" ]]; then
        # Backup ALL
        for domain in "${sites[@]}"; do
            perform_gdrive_backup "$domain" "$remote" || errors=$((errors + 1))
        done
    else
        # Backup Single
        domain="${sites[$((choice-1))]}"
        perform_gdrive_backup "$domain" "$remote" || errors=$((errors + 1))
    fi

    if [[ $errors -eq 0 ]]; then
        echo -e "\n${GREEN}🎉 Hoàn tất quá trình Backup lên Google Drive.${NC}"
    else
        echo -e "\n${RED}Backup lên Google Drive kết thúc với $errors site LỖI.${NC}"
    fi
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
    if [[ ! -d "$BACKUP_ROOT" ]]; then echo -e "${RED}Không có backup nào.${NC}"; pause; return; fi

    local source_folders=() d s_domain file fname
    local j=1
    for d in "$BACKUP_ROOT"/*; do
        if [[ -d "$d" ]]; then
            s_domain=$(basename "$d")
            source_folders+=("$s_domain")
            echo -e "$j. $s_domain"
            ((j++))
        fi
    done
    if [[ ${#source_folders[@]} -eq 0 ]]; then echo -e "${RED}Không có backup nào.${NC}"; pause; return; fi

    read -p "Chọn nguồn backup [1-${#source_folders[@]}]: " s_choice
    if ! [[ "$s_choice" =~ ^[0-9]+$ ]] || [[ "$s_choice" -lt 1 ]] || [[ "$s_choice" -gt "${#source_folders[@]}" ]]; then
        echo -e "${RED}Lựa chọn không hợp lệ!${NC}"; pause; return
    fi
    local source_domain="${source_folders[$((s_choice-1))]}"
    local backup_dir="$BACKUP_ROOT/$source_domain"

    # 3. Select Backup Files
    echo -e "\n${CYAN}--- Chọn bản Backup Code ---${NC}"
    local code_files=()
    local k=1
    while IFS= read -r file; do
        if [[ -f "$file" ]]; then
            fname=$(basename "$file")
            code_files+=("$fname")
            echo -e "$k. $fname ($(du -h "$file" | cut -f1))"
            ((k++))
        fi
    done < <(find "$backup_dir" -maxdepth 1 \( -name "*.zip" -o -name "*.tar.gz" \) -type f | sort -r)

    local code_file="" c_sel
    read -p "Chọn file Code [1-${#code_files[@]}] (Enter để bỏ qua): " c_sel
    if [[ "$c_sel" =~ ^[0-9]+$ ]] && [[ "$c_sel" -ge 1 ]] && [[ "$c_sel" -le "${#code_files[@]}" ]]; then
        code_file="$backup_dir/${code_files[$((c_sel-1))]}"
    elif [[ -n "$c_sel" ]]; then
        echo -e "${RED}Lựa chọn không hợp lệ!${NC}"; pause; return
    fi

    echo -e "\n${CYAN}--- Chọn bản Backup DB ---${NC}"
    local db_files=()
    local l=1
    while IFS= read -r file; do
        if [[ -f "$file" ]]; then
            fname=$(basename "$file")
            db_files+=("$fname")
            echo -e "$l. $fname ($(du -h "$file" | cut -f1))"
            ((l++))
        fi
    done < <(find "$backup_dir" -maxdepth 1 \( -name "db_*.sql*" -o -name "pre-restore_db_*.sql*" \) -type f | sort -r)

    local db_file="" db_sel
    read -p "Chọn file DB [1-${#db_files[@]}] (Enter để bỏ qua): " db_sel
    if [[ "$db_sel" =~ ^[0-9]+$ ]] && [[ "$db_sel" -ge 1 ]] && [[ "$db_sel" -le "${#db_files[@]}" ]]; then
        db_file="$backup_dir/${db_files[$((db_sel-1))]}"
    elif [[ -n "$db_sel" ]]; then
        echo -e "${RED}Lựa chọn không hợp lệ!${NC}"; pause; return
    fi

    if [[ -z "$code_file" ]] && [[ -z "$db_file" ]]; then echo -e "${RED}Không chọn file nào.${NC}"; pause; return; fi

    # Confirm
    echo -e "${RED}CẢNH BÁO: Dữ liệu trên $target_domain sẽ bị ghi đè!${NC}"
    read -p "Xác nhận restore? (y/n): " confirm
    if [[ "$confirm" != "y" ]]; then return; fi

    # Dùng chung 1 bản cài đặt restore (kiểm tra file, dump an toàn, hoàn tác khi lỗi, đổi URL nếu khác domain)
    _run_restore "$target_domain" "$code_file" "$db_file" "$source_domain"
    pause
}

manage_backups() {
    while true; do
        echo -e "\n${CYAN}--- Quản lý bản Backup ---${NC}"
        echo -e "1. Xem danh sách Local ($BACKUP_ROOT)"
        echo -e "2. Xem danh sách Cloud (Google Drive)"
        echo -e "3. Xóa Backup Local"
        echo -e "4. Xóa Backup Cloud"
        echo -e "0. Quay lại"
        read -p "Chọn [0-4]: " c

        case $c in
            1)
                echo -e "${YELLOW}Dung lượng Local:${NC}"
                du -sh "$BACKUP_ROOT"/* 2>/dev/null || echo "Trống."
                ;;
            2)
                _select_rclone_remote || continue
                echo -e "${YELLOW}Danh sách trên Cloud ($SELECTED_REMOTE):${NC}"
                rclone lsd "$SELECTED_REMOTE:$GDRIVE_DIR/"
                ;;
            3)
                echo -e "${YELLOW}--- Xóa Backup Local ---${NC}"
                # 1. Select Site Folder
                local dirs=() files=() p
                while IFS= read -r p; do dirs+=("$p"); done < <(find "$BACKUP_ROOT" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort)
                if [[ ${#dirs[@]} -eq 0 ]]; then echo "Không có backup nào."; continue; fi

                for i in "${!dirs[@]}"; do echo "$((i+1)). $(basename "${dirs[$i]}")"; done
                read -p "Chọn Site [1-${#dirs[@]}]: " d_sel
                if ! [[ "$d_sel" =~ ^[0-9]+$ ]] || [[ "$d_sel" -lt 1 ]] || [[ "$d_sel" -gt "${#dirs[@]}" ]]; then
                    echo -e "${RED}Lựa chọn không hợp lệ.${NC}"; continue
                fi
                local target_dir="${dirs[$((d_sel-1))]}"

                # 2. Select File
                while IFS= read -r p; do files+=("$p"); done < <(find "$target_dir" -maxdepth 1 -type f | sort)
                if [[ ${#files[@]} -eq 0 ]]; then echo "Thư mục rỗng."; rmdir "$target_dir" 2>/dev/null; continue; fi

                for j in "${!files[@]}"; do echo "$((j+1)). $(basename "${files[$j]}") ($(du -h "${files[$j]}" | cut -f1))"; done
                echo "$(( ${#files[@]} + 1 )). Xóa HẾT thư mục này"
                read -p "Chọn File để xóa: " f_sel
                if ! [[ "$f_sel" =~ ^[0-9]+$ ]] || [[ "$f_sel" -lt 1 ]] || [[ "$f_sel" -gt "$(( ${#files[@]} + 1 ))" ]]; then
                    echo -e "${RED}Lựa chọn không hợp lệ.${NC}"; continue
                fi

                if [[ "$f_sel" -eq "$(( ${#files[@]} + 1 ))" ]]; then
                    read -p "Xác nhận xoá TOÀN BỘ backup của $(basename "$target_dir")? (y/n): " del_ok
                    if [[ "$del_ok" == "y" && "$target_dir" == "$BACKUP_ROOT"/* ]]; then
                        rm -rf "$target_dir"
                        log_info "Đã xóa toàn bộ thư mục $(basename "$target_dir")"
                    fi
                else
                    rm -f "${files[$((f_sel-1))]}"
                    log_info "Đã xóa file."
                fi
                ;;
            4)
                echo -e "${YELLOW}--- Xóa Backup Cloud ---${NC}"
                _select_rclone_remote || continue
                local remote="$SELECTED_REMOTE"

                # List Cloud Folders
                local folders=() c_files=() p
                while IFS= read -r p; do [[ -n "$p" ]] && folders+=("${p%/}"); done < <(rclone lsf "$remote:$GDRIVE_DIR/" --dirs-only 2>/dev/null)
                if [[ ${#folders[@]} -eq 0 ]]; then echo "Cloud trống."; continue; fi

                for i in "${!folders[@]}"; do echo "$((i+1)). ${folders[$i]}"; done
                read -p "Chọn Site [1-${#folders[@]}]: " c_sel
                if ! [[ "$c_sel" =~ ^[0-9]+$ ]] || [[ "$c_sel" -lt 1 ]] || [[ "$c_sel" -gt "${#folders[@]}" ]]; then
                    echo -e "${RED}Lựa chọn không hợp lệ.${NC}"; continue
                fi
                local target_folder="${folders[$((c_sel-1))]}"

                # List Files in Cloud Folder
                echo -e "Đang tải danh sách file..."
                while IFS= read -r p; do [[ -n "$p" ]] && c_files+=("$p"); done < <(rclone lsf "$remote:$GDRIVE_DIR/$target_folder/" --files-only 2>/dev/null)

                for j in "${!c_files[@]}"; do echo "$((j+1)). ${c_files[$j]}"; done
                echo "$(( ${#c_files[@]} + 1 )). Xóa HẾT thư mục này trên Cloud"
                read -p "Chọn File để xóa: " cf_sel
                if ! [[ "$cf_sel" =~ ^[0-9]+$ ]] || [[ "$cf_sel" -lt 1 ]] || [[ "$cf_sel" -gt "$(( ${#c_files[@]} + 1 ))" ]]; then
                    echo -e "${RED}Lựa chọn không hợp lệ.${NC}"; continue
                fi

                if [[ "$cf_sel" -eq "$(( ${#c_files[@]} + 1 ))" ]]; then
                    read -p "Xác nhận xoá TOÀN BỘ backup của $target_folder trên Cloud? (y/n): " del_ok
                    if [[ "$del_ok" == "y" ]]; then
                        if rclone purge "$remote:$GDRIVE_DIR/$target_folder/"; then
                            log_info "Đã xóa thư mục $target_folder trên Cloud."
                        else
                            log_error "Xoá thư mục $target_folder trên Cloud thất bại."
                        fi
                    fi
                else
                    local file_to_del="${c_files[$((cf_sel-1))]}"
                    if rclone deletefile "$remote:$GDRIVE_DIR/$target_folder/$file_to_del"; then
                        log_info "Đã xóa $file_to_del trên Cloud."
                    else
                        log_error "Xoá $file_to_del trên Cloud thất bại."
                    fi
                fi
                ;;
            0) return ;;
        esac
        pause
    done
}

# Dọn backup cũ hơn N ngày trong 1 thư mục backup của site (mặc định: KEEP_DAYS trong cấu hình).
# An toàn: chỉ chạy trong $BACKUP_ROOT, không cd, và KHÔNG xoá gì nếu thư mục không có bản mới
# (backup đang lỗi thì giữ lại bản tốt cuối cùng).
cleanup_old_backups() {
    local dir=$1
    local keep_days=${2:-$(_backup_keep_days)}
    [[ -n "$dir" && -d "$dir" && "$dir" == "$BACKUP_ROOT"/* ]] || return 0
    valid_uint "$keep_days" || keep_days=7

    local newer
    newer=$(find "$dir" -maxdepth 1 -type f \( -name "*.zip" -o -name "*.tar.gz" -o -name "db_*.sql.gz" -o -name "db_*.sql" \) -mtime -"$keep_days" -print -quit)
    [[ -z "$newer" ]] && return 0

    local removed
    removed=$(find "$dir" -maxdepth 1 -type f \( -name "*.zip" -o -name "*.tar.gz" -o -name "db_*.sql.gz" -o -name "db_*.sql" -o -name "pre-restore_*" \) -mtime +"$keep_days" -print -delete | wc -l)
    [[ "$removed" -gt 0 ]] && log_info "Đã dọn $removed file backup cũ hơn $keep_days ngày."
    return 0
}

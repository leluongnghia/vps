#!/bin/bash

# modules/update.sh - Script Updater
# Updates the VPS Manager script from the GitHub repository

REPO_URL="https://github.com/leluongnghia/vps.git"
INSTALL_DIR="/usr/local/vps-manager"
BRANCH="main"

# Helper: clone với retry + HTTP/1.1 fallback
_clone_with_retry() {
    local url="$1"
    local dest="$2"
    local max_attempts=3
    local attempt=1

    # Ép git dùng HTTP/1.1 để tránh lỗi curl 92 HTTP/2 stream cancel.
    # Dùng -c cho riêng lệnh này, KHÔNG sửa cấu hình git toàn cục của root.
    while [[ "$attempt" -le "$max_attempts" ]]; do
        echo -e "${YELLOW}Cloning (lần $attempt/$max_attempts)...${NC}"
        GIT_HTTP_LOW_SPEED_LIMIT=1000 \
        GIT_HTTP_LOW_SPEED_TIME=30 \
        git -c http.version=HTTP/1.1 -c http.postBuffer=524288000 \
            clone -b "${UPDATE_REF:-$BRANCH}" --depth 1 --single-branch "$url" "$dest" 2>&1

        if [[ $? -eq 0 ]] && [[ -d "$dest/vps-manager" ]]; then
            echo -e "${GREEN}✅ Clone thành công!${NC}"
            return 0
        fi

        echo -e "${YELLOW}⚠️  Clone thất bại, thử lại sau ${attempt}s...${NC}"
        sleep "$attempt"
        rm -rf "$dest"
        attempt=$((attempt + 1))
    done

    return 1
}

# Helper: download bằng wget tar.gz (fallback nếu git fail hoàn toàn)
_download_zip_fallback() {
    local dest="$1"
    local zip_url="https://github.com/leluongnghia/vps/archive/refs/heads/${BRANCH}.tar.gz"
    if [[ "${UPDATE_REF_IS_TAG:-0}" -eq 1 ]]; then
        zip_url="https://github.com/leluongnghia/vps/archive/refs/tags/${UPDATE_REF}.tar.gz"
    fi

    echo -e "${YELLOW}Thử tải bằng wget (tar.gz fallback)...${NC}"

    mkdir -p "$dest"
    if wget -q --show-progress -O "$dest/vps.tar.gz" "$zip_url" 2>/dev/null \
       || curl -L --progress-bar -o "$dest/vps.tar.gz" "$zip_url" 2>/dev/null; then
        tar -xzf "$dest/vps.tar.gz" -C "$dest" --strip-components=1 2>/dev/null
        rm -f "$dest/vps.tar.gz"
        if [[ -d "$dest/vps-manager" ]]; then
            echo -e "${GREEN}✅ Tải thành công qua wget/curl!${NC}"
            return 0
        fi
    fi

    return 1
}

# Tag phát hành mới nhất dạng vX.Y.Z trên GitHub (rỗng nếu repo chưa có tag nào)
_latest_release_tag() {
    git ls-remote --tags --refs "$REPO_URL" 'v[0-9]*' 2>/dev/null \
        | awk -F'refs/tags/' '{print $2}' \
        | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' \
        | sort -V | tail -n 1
}

# Kiểm tra bản vừa tải về có dùng được không TRƯỚC khi thay bản đang chạy:
# đủ file cốt lõi và mọi script đều qua kiểm tra cú pháp (bắt được bản tải dở / file hỏng).
_validate_release() {
    local dir="$1" f bad=0
    for f in install.sh core/menu.sh core/utils.sh VERSION; do
        if [[ ! -s "$dir/$f" ]]; then
            echo -e "${RED}Bản tải về thiếu file: $f${NC}"
            return 1
        fi
    done
    while IFS= read -r -d '' f; do
        if ! bash -n "$f" 2>/dev/null; then
            echo -e "${RED}Lỗi cú pháp trong: ${f#$dir/}${NC}"
            bad=1
        fi
    done < <(find "$dir" -name "*.sh" -print0)
    return $bad
}

do_update() {
    # ── CRITICAL: Đổi sang /root trước để tránh getcwd error ──
    cd /root || cd /tmp

    echo -e "${YELLOW}Đang kiểm tra cập nhật từ GitHub...${NC}"

    # ── Fetch Remote Version ──
    local LOCAL_VERSION="1.0.0"
    if [[ -f "$INSTALL_DIR/VERSION" ]]; then
        LOCAL_VERSION=$(cat "$INSTALL_DIR/VERSION")
    fi

    # Kênh cập nhật: ưu tiên TAG phát hành mới nhất (vX.Y.Z) - một mốc cố định đã được chủ repo chốt.
    # Chỉ khi repo chưa có tag nào mới lấy đầu nhánh main (hành vi cũ).
    UPDATE_REF="$BRANCH"
    UPDATE_REF_IS_TAG=0
    local latest_tag
    latest_tag=$(_latest_release_tag)

    local REMOTE_VERSION
    if [[ -n "$latest_tag" ]]; then
        UPDATE_REF="$latest_tag"
        UPDATE_REF_IS_TAG=1
        REMOTE_VERSION="${latest_tag#v}"
        echo -e "${CYAN}Bản phát hành mới nhất: ${latest_tag}${NC}"
    else
        echo -e "${YELLOW}Repo chưa có tag phát hành - cập nhật theo nhánh ${BRANCH}.${NC}"
        REMOTE_VERSION=$(curl -fsS --max-time 15 "https://raw.githubusercontent.com/leluongnghia/vps/$BRANCH/vps-manager/VERSION?t=$(date +%s)")
    fi

    # Clean versions from whitespace/newlines
    LOCAL_VERSION=$(echo "$LOCAL_VERSION" | tr -d '[:space:]')
    REMOTE_VERSION=$(echo "$REMOTE_VERSION" | tr -d '[:space:]')

    if [[ -n "$REMOTE_VERSION" ]]; then
        if [[ "$LOCAL_VERSION" == "$REMOTE_VERSION" ]]; then
            echo -e "${GREEN}✅ Script đã là phiên bản mới nhất (v$LOCAL_VERSION)!${NC}"
            pause; return 0
        fi
        
        # So sánh version xem remote có thực sự lớn hơn local không
        local HIGHER_VERSION
        HIGHER_VERSION=$(printf '%s\n%s' "$LOCAL_VERSION" "$REMOTE_VERSION" | sort -V | tail -n1)
        
        if [[ "$HIGHER_VERSION" == "$LOCAL_VERSION" ]]; then
            echo -e "${GREEN}✅ Script đã là phiên bản mới nhất (v$LOCAL_VERSION) hoặc cao hơn bản remote (v$REMOTE_VERSION do cache).${NC}"
            pause; return 0
        else
            echo -e "${GREEN}Phát hiện phiên bản mới: v$LOCAL_VERSION -> v$REMOTE_VERSION${NC}"
        fi
    else
        echo -e "${YELLOW}Không thể lấy thông tin phiên bản, tiếp tục cập nhật...${NC}"
    fi

    # (Nhánh "git pull tại chỗ" đã bỏ: bộ cài chỉ sao chép thư mục vps-manager nên $INSTALL_DIR
    #  không bao giờ là git repo - đoạn đó không chạy được.)

    # ── Tải bản mới vào thư mục tạm, kiểm tra, rồi hoán đổi ───
    echo -e "${GREEN}Đang tải phiên bản mới từ GitHub...${NC}"
    cd /root

    local TEMP_DIR
    TEMP_DIR=$(mktemp -d /root/vps_update_XXXXXX)

    # Thử git clone (3 lần, HTTP/1.1)
    if ! _clone_with_retry "$REPO_URL" "$TEMP_DIR/vps-repo"; then
        # Fallback: wget tar.gz
        if ! _download_zip_fallback "$TEMP_DIR/vps-repo"; then
            echo -e "${RED}❌ Không thể tải về. Kiểm tra kết nối mạng.${NC}"
            echo -e "${YELLOW}Thử lại sau hoặc chạy: git config --global http.version HTTP/1.1${NC}"
            rm -rf "$TEMP_DIR"
            pause; return 1
        fi
    fi

    if [[ ! -d "$TEMP_DIR/vps-repo/vps-manager" ]]; then
        echo -e "${RED}Lỗi: Không tìm thấy thư mục vps-manager trong repo!${NC}"
        rm -rf "$TEMP_DIR"
        pause; return 1
    fi

    # Bản tải theo tag phải mang đúng số phiên bản của tag đó
    if [[ "$UPDATE_REF_IS_TAG" -eq 1 ]]; then
        local got_ver
        got_ver=$(tr -d '[:space:]' < "$TEMP_DIR/vps-repo/vps-manager/VERSION" 2>/dev/null)
        if [[ "$got_ver" != "${UPDATE_REF#v}" ]]; then
            echo -e "${RED}❌ File VERSION (${got_ver:-trống}) không khớp tag ${UPDATE_REF}. Giữ nguyên phiên bản hiện tại.${NC}"
            rm -rf "$TEMP_DIR"
            pause; return 1
        fi
    fi

    # Kiểm tra bản tải về TRƯỚC khi đụng tới bản đang chạy
    if ! _validate_release "$TEMP_DIR/vps-repo/vps-manager"; then
        echo -e "${RED}❌ Bản tải về không hợp lệ (thiếu file hoặc lỗi cú pháp). Giữ nguyên phiên bản hiện tại.${NC}"
        rm -rf "$TEMP_DIR"
        pause; return 1
    fi

    # Dựng bản mới ở thư mục cạnh bên rồi hoán đổi: không trộn file cũ/mới, không để lại module đã bị xoá
    local STAGE_DIR="${INSTALL_DIR}_new_$$"
    local BACKUP_DIR="${INSTALL_DIR}_backup_$(date +%s)"
    rm -rf "$STAGE_DIR"
    if ! cp -r "$TEMP_DIR/vps-repo/vps-manager" "$STAGE_DIR" || ! _validate_release "$STAGE_DIR"; then
        echo -e "${RED}Cập nhật thất bại khi sao chép (ổ đĩa đầy?). Giữ nguyên phiên bản hiện tại.${NC}"
        rm -rf "$STAGE_DIR" "$TEMP_DIR"
        pause; return 1
    fi

    [ -d "$INSTALL_DIR" ] && mv "$INSTALL_DIR" "$BACKUP_DIR"
    if ! mv "$STAGE_DIR" "$INSTALL_DIR"; then
        echo -e "${RED}Cập nhật thất bại! Đang khôi phục backup...${NC}"
        rm -rf "$INSTALL_DIR"
        [ -d "$BACKUP_DIR" ] && mv "$BACKUP_DIR" "$INSTALL_DIR"
        rm -rf "$TEMP_DIR" "$STAGE_DIR"
        pause; return 1
    fi

    # Cleanup
    rm -rf "$TEMP_DIR" "$BACKUP_DIR"
    chmod +x "$INSTALL_DIR/install.sh"
    find "$INSTALL_DIR" -name "*.sh" -exec chmod +x {} \;
    ln -sf "$INSTALL_DIR/install.sh" /usr/local/bin/vps

    echo -e "${GREEN}✅ Cập nhật thành công!${NC}"
    sleep 1
    rm -f /var/lock/vps-manager.lock
    cd /root
    exec /usr/local/bin/vps
}



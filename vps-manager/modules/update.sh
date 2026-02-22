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

    # Ép git dùng HTTP/1.1 để tránh lỗi curl 92 HTTP/2 stream cancel
    git config --global http.version HTTP/1.1 2>/dev/null
    git config --global http.postBuffer 524288000 2>/dev/null  # 500MB buffer

    while [ "$attempt" -le "$max_attempts" ]; do
        echo -e "${YELLOW}Cloning (lần $attempt/$max_attempts)...${NC}"
        GIT_HTTP_LOW_SPEED_LIMIT=1000 \
        GIT_HTTP_LOW_SPEED_TIME=30 \
        git clone -b "$BRANCH" --depth 1 --single-branch "$url" "$dest" 2>&1

        if [ $? -eq 0 ] && [ -d "$dest/vps-manager" ]; then
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
    local zip_url="https://github.com/leluongnghia/vps/archive/refs/heads/main.tar.gz"

    echo -e "${YELLOW}Thử tải bằng wget (tar.gz fallback)...${NC}"

    mkdir -p "$dest"
    if wget -q --show-progress -O "$dest/vps.tar.gz" "$zip_url" 2>/dev/null \
       || curl -L --progress-bar -o "$dest/vps.tar.gz" "$zip_url" 2>/dev/null; then
        tar -xzf "$dest/vps.tar.gz" -C "$dest" --strip-components=1 2>/dev/null
        rm -f "$dest/vps.tar.gz"
        if [ -d "$dest/vps-manager" ]; then
            echo -e "${GREEN}✅ Tải thành công qua wget/curl!${NC}"
            return 0
        fi
    fi

    return 1
}

do_update() {
    # ── CRITICAL: Đổi sang /root trước để tránh getcwd error ──
    cd /root || cd /tmp

    echo -e "${YELLOW}Đang kiểm tra cập nhật từ GitHub...${NC}"

    # ── Fetch Remote Version ──
    local LOCAL_VERSION="1.0.0"
    if [ -f "$INSTALL_DIR/VERSION" ]; then
        LOCAL_VERSION=$(cat "$INSTALL_DIR/VERSION")
    fi

    local REMOTE_VERSION
    REMOTE_VERSION=$(curl -s "https://raw.githubusercontent.com/leluongnghia/vps/$BRANCH/vps-manager/VERSION")

    # Clean versions from whitespace/newlines
    LOCAL_VERSION=$(echo "$LOCAL_VERSION" | tr -d '[:space:]')
    REMOTE_VERSION=$(echo "$REMOTE_VERSION" | tr -d '[:space:]')

    if [ -n "$REMOTE_VERSION" ] && [ "$LOCAL_VERSION" = "$REMOTE_VERSION" ]; then
        echo -e "${GREEN}✅ Script đã là phiên bản mới nhất (v$LOCAL_VERSION)!${NC}"
        pause; return 0
    fi

    if [ -n "$REMOTE_VERSION" ]; then
        echo -e "${GREEN}Phát hiện phiên bản mới: v$LOCAL_VERSION -> v$REMOTE_VERSION${NC}"
    else
        echo -e "${YELLOW}Không thể lấy thông tin phiên bản, tiếp tục cập nhật...${NC}"
    fi

    # ── Cách 1: git pull nếu đây là git repo (nhanh nhất) ─────
    if [ -d "$INSTALL_DIR/.git" ]; then
        echo -e "${GREEN}Tìm thấy git repo, đang pull...${NC}"

        # Ép HTTP/1.1 cho pull cũng
        git -C "$INSTALL_DIR" config http.version HTTP/1.1 2>/dev/null
        git -C "$INSTALL_DIR" config http.postBuffer 524288000 2>/dev/null

        git -C "$INSTALL_DIR" fetch origin "$BRANCH" 2>/dev/null

        echo -e "${GREEN}Đã tìm thấy phiên bản mới! Đang cập nhật...${NC}"
        git -C "$INSTALL_DIR" pull origin "$BRANCH"
        if [ $? -eq 0 ]; then
            find "$INSTALL_DIR" -name "*.sh" -exec chmod +x {} \;
            echo -e "${GREEN}✅ Cập nhật thành công qua git pull!${NC}"
            sleep 1
            rm -f /var/lock/vps-manager.lock
            cd /root
            exec /usr/local/bin/vps
        else
            echo -e "${RED}git pull thất bại. Chuyển sang phương pháp clone...${NC}"
        fi
        cd /root
    fi

    # ── Cách 2: Clone mới vào temp rồi copy ───────────────────
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

    if [ ! -d "$TEMP_DIR/vps-repo/vps-manager" ]; then
        echo -e "${RED}Lỗi: Không tìm thấy thư mục vps-manager trong repo!${NC}"
        rm -rf "$TEMP_DIR"
        pause; return 1
    fi

    # Backup current
    local BACKUP_DIR="${INSTALL_DIR}_backup_$(date +%s)"
    [ -d "$INSTALL_DIR" ] && cp -r "$INSTALL_DIR" "$BACKUP_DIR"

    # Copy new files
    cp -r "$TEMP_DIR/vps-repo/vps-manager/." "$INSTALL_DIR/"

    # Verify
    if [ ! -f "$INSTALL_DIR/install.sh" ]; then
        echo -e "${RED}Cập nhật thất bại! Đang khôi phục backup...${NC}"
        rm -rf "$INSTALL_DIR"
        mv "$BACKUP_DIR" "$INSTALL_DIR"
        rm -rf "$TEMP_DIR"
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



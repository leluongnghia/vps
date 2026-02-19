#!/bin/bash

# modules/update.sh - Script Updater
# Updates the VPS Manager script from the GitHub repository

REPO_URL="https://github.com/leluongnghia/vps.git"
INSTALL_DIR="/usr/local/vps-manager"

do_update() {
    # ── CRITICAL: Đổi sang /root trước để tránh getcwd error ──
    cd /root || cd /tmp

    echo -e "${YELLOW}Đang kiểm tra cập nhật từ GitHub...${NC}"

    # ── Cách 1: git pull nếu đây là git repo (nhanh nhất) ─────
    if [ -d "$INSTALL_DIR/.git" ]; then
        echo -e "${GREEN}Tìm thấy git repo, đang pull...${NC}"
        cd "$INSTALL_DIR"
        git fetch origin main 2>/dev/null
        local LOCAL REMOTE
        LOCAL=$(git rev-parse HEAD 2>/dev/null)
        REMOTE=$(git rev-parse origin/main 2>/dev/null)

        if [ "$LOCAL" = "$REMOTE" ]; then
            echo -e "${GREEN}✅ Script đã là phiên bản mới nhất!${NC}"
            pause; return 0
        fi

        echo -e "${GREEN}Đã tìm thấy phiên bản mới! Đang cập nhật...${NC}"
        git pull origin main
        if [ $? -eq 0 ]; then
            find "$INSTALL_DIR" -name "*.sh" -exec chmod +x {} \;
            echo -e "${GREEN}✅ Cập nhật thành công!${NC}"
            echo -e "${YELLOW}Khởi động lại script để áp dụng...${NC}"
            sleep 2
            cd /root
            exec /usr/local/bin/vps
        else
            echo -e "${RED}git pull thất bại. Thử phương pháp clone...${NC}"
        fi
        cd /root
    fi

    # ── Cách 2: Clone mới vào temp rồi copy (fallback) ────────
    echo -e "${GREEN}Đã tìm thấy phiên bản mới! Đang tiến hành cập nhật...${NC}"

    # Đảm bảo đứng ở /root không bị ảnh hưởng
    cd /root

    local TEMP_DIR
    TEMP_DIR=$(mktemp -d /root/vps_update_XXXXXX)
    echo -e "${YELLOW}Cloning repository...${NC}"

    git clone -b main --depth 1 "$REPO_URL" "$TEMP_DIR/vps-repo" 2>&1
    if [ $? -ne 0 ]; then
        echo -e "${RED}Failed to clone repository. Check internet connection.${NC}"
        rm -rf "$TEMP_DIR"
        pause; return 1
    fi

    if [ ! -d "$TEMP_DIR/vps-repo/vps-manager" ]; then
        echo -e "${RED}Lỗi: Không tìm thấy thư mục vps-manager trong repo!${NC}"
        rm -rf "$TEMP_DIR"
        pause; return 1
    fi

    # Backup current (đứng ở /root để tránh getcwd issues)
    local BACKUP_DIR="${INSTALL_DIR}_backup_$(date +%s)"
    if [ -d "$INSTALL_DIR" ]; then
        cp -r "$INSTALL_DIR" "$BACKUP_DIR"
    fi

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
    rm -rf "$TEMP_DIR"
    rm -rf "$BACKUP_DIR"
    chmod +x "$INSTALL_DIR/install.sh"
    find "$INSTALL_DIR" -name "*.sh" -exec chmod +x {} \;
    ln -sf "$INSTALL_DIR/install.sh" /usr/local/bin/vps

    echo -e "${GREEN}✅ Cập nhật thành công!${NC}"
    echo -e "${GREEN}Gõ 'vps' để chạy lại script.${NC}"
    sleep 2

    # Restart từ /root để tránh getcwd error
    cd /root
    exec /usr/local/bin/vps
}

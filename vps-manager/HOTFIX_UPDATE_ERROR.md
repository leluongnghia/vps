# HOTFIX: Update Error Resolution

## ❌ LỖI GẶP PHẢI:

```bash
shell-init: error retrieving current directory: getcwd: cannot access parent directories
[ERROR] Another instance is running (PID: 134749)
```

## ✅ NGUYÊN NHÂN:

1. **getcwd error:** Thư mục hiện tại bị xóa trong quá trình update
2. **Lock file:** File lock còn tồn tại từ session cũ

## 🔧 CÁCH KHẮC PHỤC NGAY:

### Bước 1: Xóa Lock File
```bash
rm -f /var/lock/vps-manager.lock
```

### Bước 2: Chạy lại VPS Manager
```bash
cd /usr/local/vps-manager
./install.sh
```

Hoặc đơn giản:
```bash
vps
```

## ✅ ĐÃ FIX TRONG PHIÊN BẢN MỚI:

Update lần sau sẽ KHÔNG còn lỗi này. Các fix đã áp dụng:

1. ✅ `cd /tmp` trước khi move install dir
2. ✅ Tự động xóa lock file trước khi exec
3. ✅ `cd $INSTALL_DIR` trước khi exec script mới

## 🚀 UPDATE LẠI ĐỂ NHẬN FIX:

```bash
# Xóa lock file
rm -f /var/lock/vps-manager.lock

# Chạy VPS Manager
vps

# Chọn option 17 (Update)
17
```

Update lần này sẽ thành công và không còn lỗi!

---

## 📝 CHI TIẾT KỸ THUẬT:

**Vấn đề:**
- Khi `mv /usr/local/vps-manager /usr/local/vps-manager_backup_xxx`, shell đang ở trong thư mục `/usr/local/vps-manager` bị mất
- Shell không thể `getcwd()` vì thư mục không còn tồn tại
- Lock file được tạo bởi process cũ không được xóa

**Giải pháp:**
```bash
# Trước khi move, cd ra khỏi install dir
cd /tmp

# Move an toàn
mv "$INSTALL_DIR" "$BACKUP_DIR"

# Sau khi install xong, xóa lock
rm -f /var/lock/vps-manager.lock

# Cd vào dir mới trước khi exec
cd "$INSTALL_DIR"
exec "$INSTALL_DIR/install.sh"
```

---

**Status:** ✅ Fixed in commit f34bd28  
**Date:** 2026-02-09

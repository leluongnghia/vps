# Hướng dẫn Sử dụng - Script Quản lý VPS

Tài liệu này hướng dẫn cách cài đặt và sử dụng các tính năng của Script quản lý VPS (tương tự LarVPS, HostVN).

## 1. Cài đặt

### Yêu cầu
- **OS**: Ubuntu 22.04 LTS hoặc 24.04 LTS.
- **Quyền**: Root.

### Lệnh cài đặt
Chạy lệnh sau trên terminal của VPS:

```bash
cd /root
# (Nếu bạn chưa clone repo, hãy clone hoặc upload script lên)
# chmod +x install.sh
./install.sh
```

Menu chính sẽ xuất hiện.

## 2. Tính năng Chính

### 2.1. Cài đặt Stack (Menu 1)
- Cài đặt Nginx, MariaDB (MySQL), PHP (8.1, 8.2, 8.3), Redis tự động.

### 2.2. Quản lý Website (Menu 2)
- **Thêm Website**: Cài đặt WordPress tự động hoặc tạo site PHP thường.
- **Redirects**: Cấu hình chuyển hướng (301/302).
- **Permissions**: Fix quyền file/folder.
- **Clone Site**: Nhân bản website từ domain A -> B (Copy code + DB).

### 2.3. SSL (Menu 1, Menu Web)
- **Let's Encrypt**: Cài đặt SSL miễn phí tự động gia hạn.
- **Paid SSL**: Hỗ trợ import chứng chỉ trả phí (.crt, .key).

### 2.4. Database & Cache (Menu 10, 11)
- **Database**:
    - Thêm/Xóa Database & User.
    - Đổi mật khẩu DB User.
    - Import/Export (.sql).
- **Cache**:
    - Xóa Cache (FastCGI, Redis, Memcached).
    - Bật/Tắt Extension Redis/Memcached/Opcache cho từng phiên bản PHP.

### 2.5. Bảo mật & Hệ thống (Menu 4, 12, 13, 14, 15)
- **Bảo mật**:
    - Cài đặt UFW, Fail2ban.
    - Đổi Port SSH, Mật khẩu Root/User.
    - Giới hạn login (MaxAuthTries).
    - Chống DDoS (Rate Limit), 7G Firewall.
- **System Tools**:
    - **AppAdmin**: Tạo mật khẩu bảo vệ tool (http auth).
    - **Swap**: Tạo/Xóa RAM ảo.
    - **Disk**: Xem dung lượng, cảnh báo đầy ổ cứng, dọn dẹp log.
    - **Nginx**: Sửa config global/vhost trực tiếp.
    - **Image Optimize**: Tối ưu hóa ảnh cho website.
    - **Services (Syntax)**: Restart Nginx/PHP/MySQL không cần lệnh.

### 2.7. Tối ưu Hiệu năng (Menu 16 - Mới)
- **Gzip & Browser Cache**: Bật nén Gzip và cache trình duyệt (Expires 365d) cho Nginx.
- **Opcache**: Tinh chỉnh Opcache cho PHP để load code nhanh hơn.
- **MySQL Tuning**: Tự động tính toán InnoDB Buffer Pool (50% RAM).

### 2.8. Backup & Restore (Menu 5)
- **Local**: Backup code + DB lưu tại `/root/backups/`.
- **Google Drive**:
    - Kết nối tài khoản Google Drive (rclone).
    - Upload bản backup lên Cloud.
    - Restore trực tiếp từ file trên Cloud.
- **Quản lý**: Xem danh sách file backup.

## 3. Cấu trúc Thư mục

- `/var/www/domain`: Thư mục chứa web.
- `/etc/nginx/sites-available`: Cấu hình Nginx.
- `/root/backups`: Thư mục chứa file backup.
- `/root/.my.cnf`: Cấu hình MySQL root (tự động tạo).

## 4. Gỡ lỗi
- Xem log tại Menu 13 -> 4 (Log Viewer).
- Nếu lỗi quyền, vào Menu 2 -> 6 (Fix Permissions).

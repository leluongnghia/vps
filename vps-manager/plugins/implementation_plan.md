# Kế hoạch Triển khai - Script Quản lý VPS

Mục tiêu là tạo một Bash script mạnh mẽ (`vps-manager.sh`) để quản lý các máy chủ VPS chạy Ubuntu 22.04 và 24.04. Script này sẽ mô phỏng các tính năng chính có trong các công cụ như LarVPS và HostVN, tập trung vào LEMP stack (Nginx, MariaDB, PHP) với các tối ưu hóa cho WordPress.

## Yêu cầu Người dùng Xem xét

> [!IMPORTANT]
> - **Hỗ trợ OS**: Nhắm mục tiêu cụ thể vào Ubuntu 22.04 LTS và 24.04 LTS.
> - **Stack**: Nginx (Web Server), MariaDB (Cơ sở dữ liệu), PHP (Đa phiên bản), Redis (Caching).
> - **Thực thi**: Script được thiết kế để chạy dưới quyền `root`.

## Thay đổi Đề xuất

Tôi sẽ tạo thư mục `vps-manager` chứa script chính và các file chức năng module để dễ bảo trì.

### Cấu trúc Dự án
- `vps-manager/`
    - `install.sh` (Điểm bắt đầu chính)
    - `core/`
        - `menu.sh` (Logic menu chính)
        - `utils.sh` (Các hàm hỗ trợ: màu sắc, kiểm tra, logs)
    - `modules/`
        - `lemp.sh` (Cài đặt Nginx, MySQL, PHP)
        - `site.sh` (Quản lý Tên miền & WordPress)
        - `security.sh` (Tường lửa, Fail2ban, SSH)
        - `backup.sh` (Sao lưu & Khôi phục)
        - `ssl.sh` (Let's Encrypt)

### Tính năng Chi tiết

#### [NEW] [vps-manager/core/menu.sh](file:///C:/Users/leluongnghia/Desktop/vps/vps-manager/core/menu.sh)
- Menu dạng text tương tác sử dụng `read` và `case`.
- Các tùy chọn:
    1. Cài đặt LEMP Stack
    2. Thêm Tên miền / Quản lý Website
    3. Cài đặt WordPress
    4. Cài đặt Bảo mật
    5. Sao lưu/Khôi phục
    6. Công cụ Hệ thống (Cập nhật, Dọn dẹp)
    7. Thoát

#### [NEW] [vps-manager/modules/lemp.sh](file:///C:/Users/leluongnghia/Desktop/vps/vps-manager/modules/lemp.sh)
- **Nginx**: Cài đặt từ repo chính thức hoặc mặc định của OS (bản ổn định).
- **MariaDB**: Cài đặt phiên bản mới nhất. Tự động hóa script bảo mật.
- **PHP**: Thiết lập `ppa:ondrej/php` cho đa phiên bản.
- **Redis**: Cài đặt và cấu hình.

#### [NEW] [vps-manager/modules/site.sh](file:///C:/Users/leluongnghia/Desktop/vps/vps-manager/modules/site.sh)
- Tạo server blocks cho Nginx.
- Tạo Cơ sở dữ liệu và Người dùng.
- Trình cài đặt tự động WordPress (tải bản mới nhất, cấu hình wp-config.php).

#### [NEW] [vps-manager/modules/security.sh](file:///C:/Users/leluongnghia/Desktop/vps/vps-manager/modules/security.sh)
- Cấu hình UFW (Cho phép 80, 443, SSH).
- Cài đặt/Cấu hình Fail2ban.
- Đổi cổng SSH (tùy chọn).

## Kế hoạch Kiểm thử

### Kiểm thử Tự động
- Vì đây là script cấp hệ thống, tôi không thể chạy nó hoàn toàn trong môi trường này (tôi không có quyền root vào VPS).
- **Kiểm tra Cú pháp**: Chạy `bash -n script.sh` để xác minh cú pháp.

#### [NEW] [vps-manager/modules/database.sh](file:///C:/Users/leluongnghia/Desktop/vps/vps-manager/modules/database.sh)
- **Features**:
    - List Databases (hiển thị Size).
    - Add/Delete Database & User.
    - Change Password DB User.
    - Import (`mysql < file.sql`) / Export (`mysqldump`).

#### [NEW] [vps-manager/modules/cache.sh](file:///C:/Users/leluongnghia/Desktop/vps/vps-manager/modules/cache.sh)
- **Toggle**: Enable/Disable Redis, Memcached, Opcache (sửa php.ini).
- **Clear Cache**:
    - FastCGI: `rm -rf /var/run/nginx-cache/*`
    - Redis: `redis-cli flushall`
    - Memcached: Restart service.

#### [NEW] [vps-manager/modules/swap.sh](file:///C:/Users/leluongnghia/Desktop/vps/vps-manager/modules/swap.sh)
- **Manage Swap**:
    - Info: `free -h`.
    - Create: `fallocate`, `mkswap`, `swapon`.
    - Delete: `swapoff`, `rm`.

#### [NEW] [vps-manager/modules/appadmin.sh](file:///C:/Users/leluongnghia/Desktop/vps/vps-manager/modules/appadmin.sh)
- **Tools Protection**:
    - Tạo `htpasswd` User/Pass.
    - Cấu hình Nginx auth_basic cho các location sensitive.
    - Change Port Admin (nếu có trang admin riêng).

#### [UPDATE] [vps-manager/modules/site.sh](file:///C:/Users/leluongnghia/Desktop/vps/vps-manager/modules/site.sh)
- **Menu Update**: Tích hợp quản lý Redirect & Phân quyền.

#### [UPDATE] [vps-manager/modules/backup.sh](file:///C:/Users/leluongnghia/Desktop/vps/vps-manager/modules/backup.sh)
- **Advanced**: Retention loop, Rclone multiple remotes listing.

# 🗂️ Cấu trúc chi tiết Dự án VPS Manager (v1.9.1)

Tài liệu này mô tả chi tiết sơ đồ cấu trúc và vai trò của từng tệp tin trong bộ công cụ **VPS Manager** chạy trên môi trường Linux (Ubuntu/Debian/AlmaLinux/RHEL).

---

## 📂 Sơ đồ Cấu trúc Tổng quan

```
vps-manager/
├── install-nginx.sh            # Kịch bản cài đặt nhanh từ xa qua Nginx LEMP Stack
├── install.sh                  # Tệp khởi chạy chính & Menu điều phối của script
├── VERSION                     # Lưu trữ thông tin phiên bản hiện tại (v1.9.1)
├── core/                       # Thư mục chứa các hàm tiện ích & nhân lõi hệ thống
│   ├── kernel_tuning.sh        # Tối ưu hóa TCP/IP & Network Kernel (BBR, Somaxconn)
│   ├── menu.sh                 # Thiết kế giao diện Menu chính tinh gọn của Terminal
│   ├── mysql_helpers.sh        # Các hàm bổ trợ xử lý nhanh database
│   ├── nginx_helpers.sh        # Các hàm bổ trợ xử lý nhanh vhost Nginx
│   ├── system_helpers.sh       # Tiện ích phát hiện OS, quản lý gói phụ thuộc
│   └── utils.sh                # Hàm tiện ích dùng chung (Màu sắc, log, pause...)
└── modules/                    # Thư mục chứa các mô-đun tính năng chính
    ├── appadmin.sh             # Quản lý bảo mật HTTP Basic Auth và tối ưu hóa ảnh WebP
    ├── backup.sh               # Xử lý sao lưu/khôi phục Local + Google Drive + Auto Backup Cron
    ├── cache.sh                # Quản lý cài đặt & cấu hình Valkey / Redis / KeyDB / Memcached
    ├── cron.sh                 # Quản lý hàng chờ tác vụ tự động Cronjob cho Server và WordPress
    ├── database.sh             # Quản lý Database MySQL, đổi pass, import/export và sửa lỗi mysqlcheck
    ├── diagnose.sh             # Kiểm tra sức khỏe hệ thống, Port đang mở, hạn SSL và phân tích log
    ├── disk.sh                 # Phân tích dung lượng đĩa, quét file >100MB, Logrotate chống tràn đĩa
    ├── lemp.sh                 # Cài đặt nền tảng LEMP (Nginx, MariaDB, PHP-FPM, phpMyAdmin)
    ├── monit.sh                # Cài đặt & cấu hình Monit Watchdog tự động khôi phục dịch vụ
    ├── nginx.sh                # Cấu hình máy chủ Nginx, quản lý vhost, cứu hộ config
    ├── php.sh                  # Quản lý đa phiên bản PHP (7.4 -> 8.4), gỡ PHP và tinh chỉnh php.ini
    ├── phpmyadmin.sh           # Cài đặt, bảo mật và thay đổi đường dẫn truy cập phpMyAdmin
    ├── security.sh             # Cấu hình WAF 7G/8G, Rate limit chặn DDoS, chặn IP quốc gia và Fail2ban
    ├── service.sh              # Điều khiển bật/tắt/reload/restart các dịch vụ LEMP và Cache
    ├── site.sh                 # Tạo mới, xóa hoặc sao chép website WP, PHP thuần, Node.js, Docker
    ├── ssl.sh                  # Đăng ký Let's Encrypt SSL (tự gia hạn), ZeroSSL hoặc Paid SSL
    ├── swap.sh                 # Khởi tạo và thay đổi bộ nhớ Swap đĩa cứng, tích hợp ZRAM
    ├── update.sh               # Cập nhật phiên bản script vps-manager từ kho lưu trữ GitHub
    ├── wordpress_performance.sh# Tối ưu hóa hiệu năng WordPress chuyên sâu (FastCGI Cache, OPcache, TBT)
    ├── wordpress_tool.sh       # Các hàm tương tác trực tiếp WP-CLI, user, salts bảo mật
    └── zram.sh                 # Thiết lập ZRAM Swap ảo hiệu năng cao nén trên RAM
```

---

## 🛠️ Chi tiết chức năng từng tệp tin

### 1. Thư mục Gốc (`/vps-manager/`)
*   **`install-nginx.sh`**: Kịch bản cài đặt nhanh từ xa được tối ưu hóa cho Nginx. Cập nhật hệ thống, tải bộ cài từ GitHub về `/usr/local/vps-manager`, cấu hình đường dẫn và phân quyền chạy.
*   **`install.sh`**: Tệp khởi chạy chính của script. Tự động kiểm tra quyền root, phát hiện hệ điều hành, nạp các biến môi trường và nạp các tệp bổ trợ từ `core/` và `modules/` để chạy Menu quản lý.
*   **`VERSION`**: Tệp văn bản lưu số hiệu phiên bản hiện tại của bộ công cụ (hiện tại là `1.9.1`).

---

### 2. Thư mục Lõi (`/core/`)
*   **`kernel_tuning.sh`**: Tối ưu hóa nhân hệ điều hành Linux cấp server. Cấu hình TCP BBR, tăng kích thước bộ đệm nhận/gửi socket mạng, nâng giới hạn kết nối đồng thời `somaxconn` lên 65535, và tối ưu hóa thời gian chờ đóng cổng TCP (`tcp_fin_timeout = 10`).
*   **`menu.sh`**: Quản lý giao diện Menu CLI tương tác 18 mục tinh gọn trên Terminal. Tích hợp phân nhóm khoa học từ Web Server, Domain, Database đến Giám sát & Tối ưu.
*   **`mysql_helpers.sh`**: Cung cấp các hàm bổ trợ nhanh cho MariaDB/MySQL để tự động thực thi các truy vấn SQL từ dòng lệnh, kiểm tra trạng thái kết nối và hỗ trợ tạo quyền cho cơ sở dữ liệu.
*   **`nginx_helpers.sh`**: Hỗ trợ tự động tạo cấu hình Nginx Server Block (vhost) chuẩn hóa, tiêm các cấu hình phụ trợ bảo mật và nén tệp tin một cách chính xác.
*   **`system_helpers.sh`**: Chứa các hàm hỗ trợ hệ thống như phát hiện cấu hình phần cứng (RAM, CPU), phát hiện phân phối Linux (Ubuntu, Debian, RHEL), cài đặt nhanh các gói phần mềm hệ thống (`apt`/`dnf`) và quản lý thư viện phụ thuộc.
*   **`utils.sh`**: Định nghĩa các tiện ích giao diện dùng chung như in thông báo màu sắc (`log_info`, `log_success`, `log_warn`, `log_error`), các tiện ích định dạng bảng biểu và hàm tạm dừng (`pause`).

---

### 3. Thư mục Mô-đun (`/modules/`)
*   **`appadmin.sh`**: Tạo lớp bảo vệ mật khẩu cơ bản (HTTP Basic Auth) cho các thư mục nhạy cảm và công cụ nén tối ưu ảnh JPG/PNG/WebP.
*   **`backup.sh`**: Quản lý sao lưu dữ liệu toàn diện (Local, Google Drive qua Rclone) và cấu hình tự động hóa lịch Backup qua Cronjob.
*   **`cache.sh`**: Cài đặt và quản lý các công cụ lưu trữ bộ nhớ đệm trên RAM như Valkey, Redis, KeyDB và Memcached qua UNIX Socket.
*   **`cron.sh`**: Quản lý dịch vụ lập lịch Cronjob trên Linux, Real WP-Cron cho WordPress và APRG SEO Cron.
*   **`database.sh`**: Quản lý cơ sở dữ liệu MySQL, tạo/xóa DB/User, đổi pass, import/export và công cụ tối ưu & sửa chữa bảng `mysqlcheck`.
*   **`diagnose.sh`**: Chẩn đoán toàn diện sức khỏe hệ thống, quét các Port mạng đang lắng nghe (`ss -tulpn`), quét thời hạn chứng chỉ SSL và phân tích log lỗi.
*   **`disk.sh`**: Quản lý dung lượng lưu trữ, tìm kiếm nhanh các file lớn nhất toàn hệ thống (>100MB), cấu hình Logrotate tự động chống tràn đĩa.
*   **`lemp.sh`**: Mô-đun cài đặt cốt lõi LEMP Stack (Nginx mainline, MariaDB với bind-address nội bộ an toàn, PHP-FPM tối ưu).
*   **`monit.sh`**: Thiết lập dịch vụ giám sát hệ thống Monit Watchdog tự động khôi phục dịch vụ khi gặp sự cố crash.
*   **`nginx.sh`**: Quản lý cấu hình dịch vụ Nginx toàn cục, vhost, kiểm tra cú pháp và công cụ tự động khắc phục lỗi cấu hình.
*   **`php.sh`**: Quản lý đa phiên bản PHP (7.4 -> 8.4), gỡ cài đặt phiên bản PHP không dùng và tinh chỉnh thông số `php.ini` (upload limit, memory limit, timeout).
*   **`phpmyadmin.sh`**: Cài đặt, bảo mật và thay đổi đường dẫn truy cập phpMyAdmin với HTTP Auth bảo vệ hai lớp.
*   **`security.sh`**: Quản lý tường lửa UFW/Firewalld, Fail2ban, WAF 7G/8G, chống DDoS và bảo mật PHP.
*   **`service.sh`**: Quản lý bật/tắt/restart/reload dịch vụ Nginx, PHP-FPM, MariaDB và tự động nhận diện cache engine (Valkey/Redis/KeyDB).
*   **`site.sh`**: Quản lý vòng đời website: WordPress, PHP thuần, Node.js (PM2) và Docker Proxy.
*   **`ssl.sh`**: Quản lý chứng chỉ SSL Let's Encrypt (tự gia hạn qua cron hàng ngày), ZeroSSL và Cloudflare Origin SSL.
*   **`swap.sh`**: Khởi tạo và thay đổi bộ nhớ Swap đĩa cứng, tích hợp chuyển đổi sang ZRAM.
*   **`update.sh`**: Đồng bộ mã nguồn của bộ công cụ từ kho lưu trữ GitHub chính thức về VPS.
*   **`wordpress_performance.sh`**: Tối ưu hóa hiệu năng WordPress chuyên sâu (FastCGI Cache, OPcache không JIT cho PHP 8.4+, Fix TBT/Render-blocking, Preload cache).
*   **`wordpress_tool.sh`**: Tương tác trực tiếp với WP-CLI, quản trị user, plugins, đổi salt bảo mật và fix core WordPress.
*   **`zram.sh`**: Kích hoạt và cấu hình ZRAM Swap ảo nén trực tiếp trên RAM giúp VPS chạy nhanh gấp 1000x so với Swap đĩa.

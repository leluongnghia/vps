# 🗂️ Cấu trúc chi tiết Dự án VPS Manager (v1.6.7)

Tài liệu này mô tả chi tiết sơ đồ cấu trúc và vai trò của từng tệp tin trong bộ công cụ **VPS Manager** chạy trên môi trường Linux (Ubuntu/Debian/AlmaLinux).

---

## 📂 Sơ đồ Cấu trúc Tổng quan

```
vps-manager/
├── install-nginx.sh            # Kịch bản cài đặt nhanh từ xa qua Nginx LEMP Stack
├── install.sh                  # Tệp khởi chạy chính & Menu điều phối của script
├── VERSION                     # Lưu trữ thông tin phiên bản hiện tại (v1.6.7)
├── core/                       # Thư mục chứa các hàm tiện ích & nhân lõi hệ thống
│   ├── kernel_tuning.sh        # Tối ưu hóa TCP/IP & Network Kernel (BBR, Somaxconn)
│   ├── menu.sh                 # Thiết kế giao diện Menu chính của Terminal
│   ├── mysql_helpers.sh        # Các hàm bổ trợ xử lý nhanh database
│   ├── nginx_helpers.sh        # Các hàm bổ trợ xử lý nhanh vhost Nginx
│   ├── system_helpers.sh       # Tiện ích phát hiện OS, quản lý gói phụ thuộc
│   └── utils.sh                # Hàm tiện ích dùng chung (Màu sắc, log, pause...)
├── modules/                    # Thư mục chứa các mô-đun tính năng chính
│   ├── appadmin.sh             # Quản lý cổng và bảo mật cho các công cụ admin (phpMyAdmin)
│   ├── backup.sh               # Xử lý sao lưu/khôi phục nguồn + Database (Auto GDrive qua rclone)
│   ├── cache.sh                # Quản lý cài đặt & khởi tạo Redis / Valkey / Memcached
│   ├── cron.sh                 # Quản lý hàng chờ tác vụ tự động Cronjob cho Server và WordPress
│   ├── database.sh             # Thêm, xóa, thay đổi mật khẩu và xuất/nhập cơ sở dữ liệu MySQL
│   ├── diagnose.sh             # Kiểm tra sức khỏe hệ thống và phân tích log lỗi nhanh
│   ├── disk.sh                 # Phân tích dung lượng đĩa cứng, tìm file dung lượng lớn
│   ├── lemp.sh                 # Cài đặt nền tảng LEMP (Nginx, MariaDB, PHP-FPM, phpMyAdmin)
│   ├── monit.sh                # Cài đặt & cấu hình Monit Watchdog tự động khôi phục dịch vụ
│   ├── nginx.sh                # Cấu hình máy chủ Nginx, kiểm tra cú pháp vhost
│   ├── php.sh                  # Quản lý cài đặt đa phiên bản PHP (7.4 -> 8.4) & đổi PHP cho từng site
│   ├── phpmyadmin.sh           # Cài đặt, bảo mật và thay đổi đường dẫn truy cập phpMyAdmin
│   ├── security.sh             # Cấu hình WAF 7G/8G, Rate limit chặn DDoS, chặn IP quốc gia và Fail2ban
│   ├── service.sh              # Điều khiển bật/tắt/reload các dịch vụ hệ thống
│   ├── site.sh                 # Tạo mới, xóa hoặc sao chép (clone) website WordPress tự động
│   ├── ssl.sh                  # Đăng ký Let's Encrypt SSL (tự gia hạn) hoặc cấu hình Paid SSL
│   ├── swap.sh                 # Khởi tạo và thay đổi bộ nhớ Swap truyền thống trên đĩa
│   ├── update.sh               # Cập nhật phiên bản script vps-manager và các gói phần mềm hệ thống
│   ├── wordpress_performance.sh# Tối ưu hóa hiệu năng WordPress (FastCGI Cache, OPcache không JIT cho PHP 8.4+)
│   ├── wordpress_tool.sh       # Các hàm tương tác trực tiếp với mã nguồn WP, salts cấu hình
│   └── zram.sh                 # Thiết lập ZRAM Swap ảo hiệu năng cao trên RAM
└── plugins/
    └── project_structure.md    # Bản sao lưu cấu trúc dự án trong thư mục plugin
```

---

## 🛠️ Chi tiết chức năng từng tệp tin

### 1. Thư mục Gốc (`/vps-manager/`)
*   **`install-nginx.sh`**: Kịch bản cài đặt nhanh từ xa được tối ưu hóa cho Nginx. Nó thực hiện cập nhật hệ thống, tải bộ cài từ GitHub về `/usr/local/vps-manager`, cấu hình đường dẫn và phân quyền chạy cho toàn bộ thư mục.
*   **`install.sh`**: Tệp khởi chạy chính của script. Tự động kiểm tra quyền root, phát hiện hệ điều hành, nạp các biến môi trường và nạp các tệp bổ trợ từ `core/` và `modules/` để chạy Menu quản lý.
*   **`VERSION`**: Tệp văn bản lưu số hiệu phiên bản hiện tại của bộ công cụ (phiên bản hiện tại là `1.6.7`).

---

### 2. Thư mục Lõi (`/core/`)
*   **`kernel_tuning.sh`**: Tối ưu hóa nhân hệ điều hành Linux cấp server. Cấu hình TCP BBR, tăng kích thước bộ đệm nhận/gửi socket mạng, nâng giới hạn kết nối đồng thời `somaxconn` lên 65535, và tối ưu hóa thời gian chờ đóng cổng TCP (`tcp_fin_timeout = 10`).
*   **`menu.sh`**: Quản lý thiết kế giao diện Menu CLI tương tác trên Terminal. Định nghĩa các phím tắt điều hướng nhanh giữa các mục cấu hình máy chủ, quản lý trang web, tối ưu hóa và bảo mật.
*   **`mysql_helpers.sh`**: Cung cấp các hàm bổ trợ nhanh cho MariaDB/MySQL để tự động thực thi các truy vấn SQL từ dòng lệnh, kiểm tra trạng thái kết nối và hỗ trợ tạo quyền cho cơ sở dữ liệu.
*   **`nginx_helpers.sh`**: Hỗ trợ tự động tạo cấu hình Nginx Server Block (vhost) chuẩn hóa, tiêm các cấu hình phụ trợ bảo mật và nén tệp tin một cách chính xác.
*   **`system_helpers.sh`**: Chứa các hàm hỗ trợ hệ thống như phát hiện cấu hình phần cứng (RAM, CPU), phát hiện phân phối Linux (Ubuntu, Debian, RHEL), cài đặt nhanh các gói phần mềm hệ thống (`apt`/`dnf`) và quản lý thư viện phụ thuộc.
*   **`utils.sh`**: Định nghĩa các tiện ích giao diện dùng chung như in thông báo màu sắc (`log_info`, `log_success`, `log_warn`, `log_error`), các tiện ích định dạng bảng biểu và hàm tạm dừng (`pause`).

---

### 3. Thư mục Mô-đun (`/modules/`)
*   **`appadmin.sh`**: Quản lý và bảo mật các trang công cụ quản trị. Hỗ trợ thay đổi cổng truy cập mặc định, tạo lớp bảo vệ mật khẩu cơ bản (Basic Auth) cho thư mục nhạy cảm và bảo vệ liên kết phpMyAdmin.
*   **`backup.sh`**: Quản lý sao lưu dữ liệu toàn diện. Hỗ trợ nén mã nguồn website dạng `.zip`, xuất database dạng `.sql`, hỗ trợ khôi phục (Restore) nhanh chóng và cấu hình đồng bộ tự động lên đám mây (Google Drive) qua công cụ `rclone`.
*   **`cache.sh`**: Cài đặt và quản lý các công cụ lưu trữ bộ nhớ đệm trên RAM như Valkey, Redis, và Memcached. Cấu hình kết nối qua UNIX Socket để tăng tốc tối đa tốc độ giao tiếp và cung cấp công cụ dọn dẹp (flush) cache.
*   **`cron.sh`**: Quản lý dịch vụ lập lịch Cronjob trên Linux. Hỗ trợ tự động hóa tiến trình chạy tác vụ ẩn, chuyển đổi từ WP-Cron ảo của WordPress sang Cronjob thật cấp hệ thống để cải thiện hiệu năng.
*   **`database.sh`**: Cung cấp giao diện quản lý cơ sở dữ liệu MySQL trực quan. Cho phép liệt kê danh sách DB, thêm mới, xóa bỏ database và người dùng liên kết, thay đổi mật khẩu quản trị và import/export SQL nhanh.
*   **`diagnose.sh`**: Công cụ chẩn đoán nhanh lỗi hệ thống. Phân tích tài nguyên hiện tại (RAM, CPU, Swap), đọc các tệp log lỗi mới nhất của Nginx, PHP, MariaDB để tìm nguyên nhân trang web bị gián đoạn.
*   **`disk.sh`**: Quản lý dung lượng lưu trữ trên VPS. Hiển thị bảng phân tích dung lượng, hỗ trợ tìm kiếm nhanh các tệp tin hoặc thư mục chiếm dung lượng lớn nhất để giải phóng không gian ổ cứng.
*   **`lemp.sh`**: Mô-đun cài đặt cốt lõi LEMP Stack. Cài đặt Nginx (phiên bản mới nhất), cài đặt MariaDB (hệ quản trị CSDL), thiết lập PHP-FPM mặc định và cấu hình liên kết cơ bản giữa các dịch vụ.
*   **`monit.sh`**: Thiết lập dịch vụ giám sát hệ thống Monit Watchdog. Tự động theo dõi các tiến trình Nginx, PHP-FPM, MySQL và tự khởi động lại chúng ngay lập tức nếu gặp sự cố sập nguồn (crash).
*   **`nginx.sh`**: Quản lý cấu hình dịch vụ Nginx toàn cục. Chỉnh sửa tệp `nginx.conf`, quản lý bật/tắt các file vhost, dọn dẹp các tệp cấu hình lỗi và nạp lại (reload) Nginx không làm gián đoạn truy cập.
*   **`php.sh`**: Quản lý đa phiên bản PHP. Cho phép cài đặt song song nhiều phiên bản PHP (từ PHP 7.4 đến PHP 8.4) trên cùng một máy chủ và cấu hình chỉ định phiên bản PHP riêng biệt cho từng website.
*   **`phpmyadmin.sh`**: Mô-đun cài đặt và cấu hình phpMyAdmin. Thiết lập phiên bản phù hợp, cấu hình bảo mật chống dò quét và thay đổi đường dẫn truy cập mặc định để bảo mật.
*   **`security.sh`**: Quản lý tường lửa ứng dụng và bảo mật hệ thống. Cấu hình tường lửa cấp cổng, cài đặt Fail2ban ngăn chặn brute-force, tích hợp bộ lọc chặn bot độc hại (7G/8G Nginx WAF) và chặn truy cập theo quốc gia (GeoIP).
*   **`service.sh`**: Trình bao bọc (wrapper) đơn giản để quản lý trạng thái, khởi động lại hoặc tải lại các dịch vụ hệ thống như Nginx, PHP-FPM, MariaDB từ Menu.
*   **`site.sh`**: Quản lý vòng đời website WordPress. Tự động tạo thư mục gốc, cấp quyền ghi đọc chuẩn (`www-data`), tự động tải và cài đặt mã nguồn WordPress qua WP-CLI, tạo cơ sở dữ liệu tương ứng và thiết lập vhost Nginx. Hỗ trợ tính năng nhân bản (clone) website.
*   **`ssl.sh`**: Quản lý chứng chỉ bảo mật SSL. Tích hợp công cụ `certbot` để tự động hóa đăng ký SSL Let's Encrypt miễn phí (bao gồm tự gia hạn), hoặc hỗ trợ cài đặt cấu hình chứng chỉ SSL trả phí (Paid SSL).
*   **`swap.sh`**: Quản lý bộ nhớ đệm trao đổi vật lý (Swap). Cho phép kiểm tra trạng thái swap, tạo mới file swap có dung lượng tùy chỉnh và xóa bỏ tệp swap cũ.
*   **`update.sh`**: Đồng bộ mã nguồn của bộ công cụ từ kho lưu trữ GitHub chính thức về VPS và cập nhật các gói phần mềm bảo mật của hệ điều hành.
*   **`wordpress_performance.sh`**: Tối ưu hóa hiệu năng WordPress chuyên sâu. Cấu hình FastCGI Cache của Nginx, cấu hình OPcache nâng cao (bao gồm tự động nhận diện tắt JIT compiler trên PHP 8.4+ để ngăn ngừa lỗi tràn bộ nhớ), thiết lập tối ưu hóa hiển thị CSS/JS không gây nghẽn kết xuất (Render-blocking).
*   **`wordpress_tool.sh`**: Tập hợp các hàm xử lý mã nguồn WordPress như thay đổi salt bảo mật, cấu hình tệp `wp-config.php`, flush liên kết tĩnh permalinks và transient cache thông qua WP-CLI.
*   **`zram.sh`**: Kích hoạt và cấu hình ZRAM. Tạo ổ đĩa Swap nén ảo trực tiếp trên RAM giúp cải thiện hiệu năng đa nhiệm của VPS, tối ưu hóa dung lượng RAM hiệu quả gấp nhiều lần so với Swap thường.

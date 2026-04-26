# 🖥️ VPS Manager — Quản lý VPS Tự động (WPTangToc Grade)

[![Version](https://img.shields.io/badge/Version-1.3.5-brightgreen.svg)](#)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![Shell: Bash](https://img.shields.io/badge/Shell-Bash-blue.svg)](https://www.gnu.org/software/bash/)
[![OS](https://img.shields.io/badge/OS-Ubuntu%20%7C%20Debian%20%7C%20AlmaLinux-orange.svg)](#)

[🇻🇳 Tiếng Việt](#giới-thiệu-tiếng-việt) | [🇬🇧 English](#introduction-english)

---

## ⚡ Cài đặt nhanh / Quick Install

> Chọn **một trong hai** stack phù hợp với nhu cầu của bạn. Hệ thống sẽ tự động tối ưu Kernel & System ngay khi cài đặt.

### 🌐 Stack 1 — Nginx (LEMP: Nginx + MariaDB + PHP)
*Tối ưu 2 lớp: Nginx FastCGI Cache (L1) & Valkey Unix Socket (L2)*

```bash
bash <(curl -s https://raw.githubusercontent.com/leluongnghia/vps/main/vps-manager/install-nginx.sh)
```

### ⚡ Stack 2 — OpenLiteSpeed (OLS + LSPHP + MariaDB + LSCache)
*Tốc độ ánh sáng, QUIC HTTP/3, Auto-scaling theo RAM thực tế*

```bash
bash <(curl -s https://raw.githubusercontent.com/leluongnghia/vps/main/vps-manager/install-ols.sh)
```

> 💡 Sau khi cài xong, gõ `vps` để mở menu quản lý. Hệ thống sẽ hiển thị giao diện phù hợp với stack bạn đã chọn.

---

## 🚀 Hướng dẫn Tối ưu tốc độ VPS & Website (Chuyên sâu)

Để đạt hiệu suất "WPTangToc Grade" (Điểm cao trên PageSpeed, TTFB cực thấp), hãy làm theo quy trình sau:

### Bước 1: Tối ưu lõi Hệ thống (Kernel Tuning)
Script đã tự động thực hiện các bước này khi bạn chạy lệnh cài đặt ở trên:
- **Tắt Transparent Huge Pages (THP):** Giúp Redis/Valkey và MariaDB không bị nghẽn (latency spikes).
- **Bật TCP BBR:** Tối ưu tốc độ truyền tải mạng, giảm packet loss.
- **CPU Performance:** Ép CPU chạy ở mức hiệu suất cao nhất thay vì tiết kiệm điện.
- **File Limits:** Nâng giới hạn file descriptor lên 524,288 giúp xử lý hàng ngàn kết nối đồng thời.

### Bước 2: Tối ưu Tầng Web Server & PHP
1. **Đối với Nginx:** 
   - Sử dụng **Nginx FastCGI Cache** cho khách vãng lai.
   - Kết nối **Valkey/Redis qua Unix Socket** (nhanh hơn TCP 30-50%).
2. **Đối với OpenLiteSpeed:**
   - Bật **QUIC (HTTP/3)** trong Menu 21.
   - Hệ thống tự động cấu hình **OPcache & JIT** cho PHP để thực thi mã nguồn nhanh hơn.
   - Sử dụng **in-RAM Cache** (LSCache) để serve trang ngay từ bộ nhớ đệm.

### Bước 3: Tối ưu Database (MariaDB)
Script tích hợp tính năng **Auto-scaling RAM**:
- Tự động tính toán `innodb_buffer_pool_size` bằng 25-40% RAM hệ thống.
- Đổi tên user quản trị `root` thành `wpdbadmin` để tăng bảo mật.
- Chỉ cho phép kết nối nội bộ, tắt hoàn toàn Networking port 3306 nếu không cần thiết.

### Bước 4: Cấu hình WordPress (WP)
1. **Object Cache:** Vào Menu `vps` -> Mục **10 (Cache)** -> Cài đặt **Valkey** (khuyên dùng). Script sẽ tự động inject cấu hình Unix Socket vào `wp-config.php`.
2. **Plugin:** 
   - Nếu dùng OLS: Cài plugin **LiteSpeed Cache**.
   - Nếu dùng Nginx: Cài plugin **Redis Object Cache** (by Till Krüss) và bật Page Cache qua Nginx Helper.

---

## 📋 Menu Chính (24 Tùy chọn)

| # | Tính năng | Điểm nhấn Nâng cấp v1.3.5 |
|---|-----------|-------------------------|
| 1 | 🌐 **Cài đặt LEMP / OLS** | Tách riêng 2 lệnh cài, tối ưu chuyên sâu từng stack |
| 10 | ⚡ **Quản lý Cache** | Hỗ trợ **Valkey / KeyDB / Redis** qua Unix Socket |
| 17 | 🚀 **Tối ưu WP Performance** | Tinh chỉnh OPcache, JIT, MySQL buffers theo RAM thực tế |
| 24 | 🔄 **Di chuyển Web Server** | Chuyển mượt Nginx ↔ OLS, tự dọn dẹp file thừa & disk |

---

## 📊 So sánh 2 Stack

| Tiêu chí | 🌐 Nginx LEMP | ⚡ OpenLiteSpeed |
|----------|--------------|----------------|
| **Phù hợp nhất** | Shop, App, Traffic lớn ổn định | WordPress Blog, Tin tức, Tốc độ |
| **Object Cache** | Unix Socket (Valkey/KeyDB) | Unix Socket (Valkey/KeyDB) |
| **PHP Engine** | PHP-FPM (v8.1 - 8.4) | LSPHP (v8.1 - 8.4) |
| **Ưu điểm** | Tùy biến cực cao, cực ổn định | HTTP/3 sẵn có, LSCache bá đạo |

---

## 📋 Yêu cầu Hệ thống

- **OS:** Ubuntu 22.04/24.04 (Khuyên dùng), Debian 11/12, AlmaLinux 8/9.
- **RAM:** Tối thiểu 1GB (Khuyên dùng 2GB+ để bật Object Cache & MariaDB tuning).
- **Quyền:** Root access.

---

## 🗂️ Cấu trúc Project (v1.3.5)

```
vps-manager/
├── install-nginx.sh        # 🌐 Cài nhanh Nginx Stack + Kernel Tuning
├── install-ols.sh          # ⚡ Cài nhanh OLS Stack + Kernel Tuning
├── core/
│   ├── kernel_tuning.sh    # 🚀 Lõi tối ưu Kernel (BBR, THP, CPU, Limits)
│   ├── menu.sh             # Smart Menu tự chuyển theo Stack
├── modules/
│   ├── switch.sh           # 🔄 Chuyển đổi OLS <-> Nginx & Dọn rác disk
│   ├── cache.sh            # ⚡ Quản lý Valkey/Redis/KeyDB Unix Socket
└── ...
```

---

<a name="introduction-english"></a>

# 🇬🇧 English Introduction

A professional Bash script for high-performance VPS management (Ubuntu/Debian/AlmaLinux).

### Quick Install
- **Nginx Stack:** `bash <(curl -s https://raw.githubusercontent.com/leluongnghia/vps/main/vps-manager/install-nginx.sh)`
- **OpenLiteSpeed Stack:** `bash <(curl -s https://raw.githubusercontent.com/leluongnghia/vps/main/vps-manager/install-ols.sh)`

### Features (v1.3.5)
- **Kernel Tuning:** Auto-enables BBR, disables THP, sets CPU to Performance.
- **Smart Scaling:** Automatically tunes MariaDB & Webserver based on physical RAM.
- **2-Layer Cache:** Implements Nginx FastCGI L1 + Valkey Unix Socket L2.
- **Zero-Downtime Migration:** Switch between Nginx and OLS with one click (Menu 24).
- **Security:** Root DB rename, Firewall, WAF, and 7G/8G rules included.

---
> **Bản quyền**: © 2024-2025 leluongnghia. Tối ưu theo tiêu chuẩn WPTangToc.

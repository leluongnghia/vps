# UX Improvement Plan: Replace Manual Domain Input with Site Selection

## 📋 DANH SÁCH CÁC CHỨC NĂNG CẦN FIX:

### ✅ ĐÃ SỬ DỤNG `select_site` (Tốt):
1. ✅ `modules/site.sh` - `delete_site()` - Đã dùng select_site
2. ✅ `modules/site.sh` - `clone_site()` - Đã dùng select_site  
3. ✅ `modules/site.sh` - `rename_site()` - Đã dùng select_site
4. ✅ `modules/site.sh` - `change_site_php()` - Đã dùng select_site
5. ✅ `modules/site.sh` - `update_site_db_info()` - Đã dùng select_site
6. ✅ `modules/site.sh` - `protect_folder()` - Đã dùng select_site
7. ✅ `modules/wordpress_tool.sh` - Tất cả functions - Đã dùng select_wp_site

### ❌ CẦN FIX (14 chỗ):

#### 1. **modules/ssl.sh** (1 chỗ)
- **Function:** `install_ssl()`
- **Line:** 8
- **Current:** `read -p "Nhập tên miền để cài SSL: " domain`
- **Fix:** Thay bằng `select_site` từ `modules/site.sh`

#### 2. **modules/site.sh** (5 chỗ)
- **Function:** `add_new_site()` - Line 51
  - **Current:** `read -p "Nhập tên miền (ví dụ: example.com): " domain`
  - **Note:** Đây là ADD NEW nên PHẢI nhập thủ công (KHÔNG fix)
  
- **Function:** `clone_site()` - Line 283
  - **Current:** `read -p "Nhập domain ĐÍCH (Mới): " dest_domain`
  - **Note:** Domain đích là MỚI nên PHẢI nhập thủ công (KHÔNG fix)
  
- **Function:** `rename_site()` - Line 358
  - **Current:** `read -p "Nhập domain MỚI: " new_domain`
  - **Note:** Domain mới nên PHẢI nhập thủ công (KHÔNG fix)
  
- **Function:** `manage_parked_domains()` - Line 471, 487
  - **Current:** `read -p "Domain ALIAS (Parked): " alias`
  - **Note:** Alias domain là MỚI nên PHẢI nhập thủ công (KHÔNG fix)

#### 3. **modules/php.sh** (1 chỗ)
- **Function:** `change_site_php()` (duplicate with site.sh)
- **Line:** 69
- **Current:** `read -p "Nhập tên miền cần đổi PHP: " domain`
- **Fix:** Thay bằng `select_site`

#### 4. **modules/nginx.sh** (1 chỗ)
- **Function:** `edit_nginx_config()`
- **Line:** 35
- **Current:** `read -p "Nhập domain cần sửa: " domain`
- **Fix:** Thay bằng `select_site`

#### 5. **modules/backup.sh** (3 chỗ)
- **Function:** `backup_site()` - Line 213
- **Function:** `backup_db()` - Line 232
- **Function:** `restore_site()` - Line 431
- **Current:** `read -p "Nhập domain cần backup/restore: " domain`
- **Fix:** Thay bằng `select_site`

#### 6. **modules/appadmin.sh** (1 chỗ)
- **Function:** `optimize_images()`
- **Line:** 50
- **Current:** `read -p "Nhập tên miền cần tối ưu ảnh: " domain`
- **Fix:** Thay bằng `select_site`

---

## 🎯 TỔNG KẾT:

### Cần Fix: **7 functions** trong **5 files**

1. ✅ `modules/ssl.sh` - `install_ssl()` 
2. ✅ `modules/php.sh` - `change_site_php()`
3. ✅ `modules/nginx.sh` - `edit_nginx_config()`
4. ✅ `modules/backup.sh` - `backup_site()`, `backup_db()`, `restore_site()`
5. ✅ `modules/appadmin.sh` - `optimize_images()`

### Không Fix (Hợp lý): **5 functions**
- `add_new_site()` - Tạo mới phải nhập
- `clone_site()` - Domain đích mới phải nhập
- `rename_site()` - Domain mới phải nhập
- `manage_parked_domains()` - Alias mới phải nhập

---

## 🔧 IMPLEMENTATION STRATEGY:

### Option 1: Import `select_site` function
```bash
# At top of each file
source "$(dirname "${BASH_SOURCE[0]}")/site.sh"
```

### Option 2: Create shared helper (Recommended)
```bash
# core/site_selector.sh
select_site() {
    # Shared implementation
}
```

Then source in all modules.

---

## 📝 PRIORITY:

### High Priority (User-facing, frequent use):
1. 🔥 `appadmin.sh` - `optimize_images()` (User đang gặp)
2. 🔥 `ssl.sh` - `install_ssl()`
3. 🔥 `backup.sh` - All backup/restore functions

### Medium Priority:
4. ⚡ `php.sh` - `change_site_php()`
5. ⚡ `nginx.sh` - `edit_nginx_config()`

---

**Status:** Ready for implementation  
**Estimated Changes:** 7 functions, 5 files  
**Impact:** Significantly improved UX

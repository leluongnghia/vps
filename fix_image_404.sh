#!/bin/bash
# fix_image_404.sh - Fix OLS rewrite rules gây 404 cho ảnh uploads
# Chạy trực tiếp trên VPS với quyền root: bash fix_image_404.sh

set -e

DOMAIN="azevent.vn"
OLS_VHOSTS_DIR="/usr/local/lsws/conf/vhosts"
VHCONF="${OLS_VHOSTS_DIR}/${DOMAIN}/vhconf.conf"
SITE_ROOT="/var/www/${DOMAIN}/public_html"
HTACCESS="${SITE_ROOT}/.htaccess"

echo "=== [1] Backup vhconf.conf ==="
cp "${VHCONF}" "${VHCONF}.bak.$(date +%Y%m%d%H%M%S)"
echo "Backup xong."

echo ""
echo "=== [2] Rewrite rewrite rules trong vhconf.conf ==="

# Dùng Python3 để thay thế block rewrite an toàn hơn sed
python3 - <<'PYEOF'
import re, sys

vhconf_path = "/usr/local/lsws/conf/vhosts/azevent.vn/vhconf.conf"

with open(vhconf_path, "r") as f:
    content = f.read()

# Pattern xóa: rewrite block cũ + errorpage 404 block
old_rewrite = r'rewrite\s*\{.*?END_rules\s*\}.*?\}(\s*\nerrorpage 404 \{[^}]*\})?'
new_rewrite = '''rewrite  {
  enable                  1
  autoLoadHtaccess        1
  rules                   <<<END_rules
RewriteEngine on
RewriteBase /

# --- Static file pass-through: uploads & wp-content assets never go through WordPress ---
RewriteRule ^wp-content/uploads/ - [L]
RewriteRule ^wp-includes/ - [L]
RewriteRule ^wp-content/plugins/ - [L]
RewriteRule ^wp-content/themes/ - [L]

# WebP Fallback: only for image extensions
RewriteCond %{HTTP_ACCEPT} image/webp
RewriteCond %{DOCUMENT_ROOT}%{REQUEST_FILENAME}.webp -f
RewriteRule ^(.*)\\.(?:jpe?g|png|gif)$ $1.webp [T=image/webp,E=accept:1,L]

# WordPress: only route to index.php if file/dir does not exist
RewriteRule ^index\\.php$ - [L]
RewriteCond %{REQUEST_FILENAME} !-f
RewriteCond %{REQUEST_FILENAME} !-d
RewriteRule . /index.php [L]
  END_rules
}'''

result = re.sub(old_rewrite, new_rewrite, content, flags=re.DOTALL)

if result == content:
    print("WARNING: Pattern không match, thử cách thay thế thủ công...")
    # Fallback: xóa errorpage 404 block
    result = re.sub(r'\nerrorpage 404 \{[^}]*\}', '', content)
    # Thay WebP rule cũ
    result = result.replace(
        '# WebP Fallback (Serve .webp if exists and browser supports it)\nRewriteCond %{HTTP_ACCEPT} "image/webp"\nRewriteCond %{REQUEST_FILENAME}.webp -f\nRewriteRule ^(.*)$ $1.webp [T=image/webp,E=accept:1,L]\n\n# LSCache WebP Support\nRewriteCond %{HTTP_ACCEPT} "image/webp"\nRewriteCond %{DOCUMENT_ROOT}/$1.webp -f\nRewriteRule ^(.*)\\.(jpe?g|png|gif)$ $1.webp [T=image/webp,E=accept:1,L]\n',
        '# --- Static file pass-through ---\nRewriteRule ^wp-content/uploads/ - [L]\nRewriteRule ^wp-includes/ - [L]\n\n# WebP Fallback: only for image extensions\nRewriteCond %{HTTP_ACCEPT} image/webp\nRewriteCond %{DOCUMENT_ROOT}%{REQUEST_FILENAME}.webp -f\nRewriteRule ^(.*)\\.(?:jpe?g|png|gif)$ $1.webp [T=image/webp,E=accept:1,L]\n\n'
    )

with open(vhconf_path, "w") as f:
    f.write(result)

print("Đã cập nhật vhconf.conf thành công!")
PYEOF

echo ""
echo "=== [3] Cập nhật .htaccess (chuẩn WordPress + uploads pass-through) ==="
cat > "${HTACCESS}" << 'HTEOF'
# BEGIN WordPress
# Các chỉ thị giữa "BEGIN WordPress" và "END WordPress" được tạo tự động.
<IfModule mod_rewrite.c>
RewriteEngine On
RewriteBase /

# --- Pass-through: không redirect file tĩnh trong uploads ---
RewriteRule ^wp-content/uploads/ - [L]
RewriteRule ^wp-includes/ - [L]

RewriteRule ^index\.php$ - [L]
RewriteCond %{REQUEST_FILENAME} !-f
RewriteCond %{REQUEST_FILENAME} !-d
RewriteRule . /index.php [L]
</IfModule>
# END WordPress
HTEOF

chown www-data:www-data "${HTACCESS}" 2>/dev/null || true
chmod 644 "${HTACCESS}"
echo ".htaccess đã cập nhật."

echo ""
echo "=== [4] Kiểm tra quyền thư mục uploads ==="
UPLOADS_DIR="${SITE_ROOT}/wp-content/uploads"
if [[ -d "${UPLOADS_DIR}" ]]; then
    chown -R www-data:www-data "${UPLOADS_DIR}" 2>/dev/null || true
    find "${UPLOADS_DIR}" -type d -exec chmod 755 {} \;
    find "${UPLOADS_DIR}" -type f -exec chmod 644 {} \;
    echo "Đã cấp quyền thư mục uploads."
else
    echo "WARNING: Không tìm thấy thư mục uploads: ${UPLOADS_DIR}"
fi

echo ""
echo "=== [5] Restart OLS ==="
if [[ -f /usr/local/lsws/bin/lswsctrl ]]; then
    /usr/local/lsws/bin/lswsctrl restart
else
    systemctl restart lshttpd
fi
echo "OLS đã được restart."

echo ""
echo "=== [6] Test ảnh ==="
sleep 2
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
    "https://azevent.vn/wp-content/uploads/2025/10/le-khoi-cong-du-an-lang-giao-duc-quoc-te-13-1024x683.jpg" \
    -H "Accept: text/html,application/xhtml+xml" \
    --max-time 10 2>/dev/null || echo "000")
echo "HTTP Status code cho ảnh test: ${HTTP_CODE}"

if [[ "${HTTP_CODE}" == "200" ]]; then
    echo "✅ THÀNH CÔNG! Ảnh đã hoạt động bình thường."
elif [[ "${HTTP_CODE}" == "301" || "${HTTP_CODE}" == "302" ]]; then
    echo "⚠ Redirect - theo dõi redirect..."
    curl -sIL "https://azevent.vn/wp-content/uploads/2025/10/le-khoi-cong-du-an-lang-giao-duc-quoc-te-13-1024x683.jpg" \
        -H "Accept: text/html" --max-time 10 2>/dev/null | grep -E "HTTP|Location"
else
    echo "❌ Vẫn còn lỗi: ${HTTP_CODE}"
    echo "Kiểm tra log OLS:"
    tail -20 /usr/local/lsws/logs/error.log 2>/dev/null || true
fi

echo ""
echo "=== [7] Regenerate WordPress Media Thumbnails (nếu cần) ==="
echo "Nếu ảnh vẫn không hiện trong Media Library, chạy lệnh sau:"
echo "  wp media regenerate --yes --path=${SITE_ROOT} --allow-root"
echo ""
echo "=== HOÀN THÀNH ==="

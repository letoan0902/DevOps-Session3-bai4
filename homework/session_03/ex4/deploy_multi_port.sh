#!/usr/bin/env bash
# deploy_multi_port.sh
# Triển khai Beta App (cổng 8080) và Internal App (cổng 8090) trên Nginx.
# Script có tính idempotent: chạy nhiều lần cho cùng một kết quả cuối cùng.
#
# Cách dùng (chạy bằng user devops, có quyền sudo):
#   cd ~/ex4 && bash deploy_multi_port.sh
#
# Thư mục chứa script phải có sẵn:
#   multi-port.conf, beta-app/index.html, internal-app/index.html

set -euo pipefail

# --- Biến cấu hình ---------------------------------------------------------
SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WEB_USER="devops"
WEB_GROUP="www-data"
SITE_NAME="multi-port.conf"
SITES_AVAILABLE="/etc/nginx/sites-available"
SITES_ENABLED="/etc/nginx/sites-enabled"
PORTS=(8080 8090)

log() { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*"; }

# --- Bước 0: kiểm tra file nguồn -------------------------------------------
for f in "multi-port.conf" "beta-app/index.html" "internal-app/index.html"; do
    if [[ ! -f "${SRC_DIR}/${f}" ]]; then
        echo "Lỗi: thiếu file ${SRC_DIR}/${f}" >&2
        exit 1
    fi
done

# --- Bước 1: kiểm tra cổng chưa bị tiến trình khác chiếm -------------------
# Nếu cổng đã do nginx giữ (chạy lại script) thì bỏ qua, nếu tiến trình khác giữ thì dừng.
for port in "${PORTS[@]}"; do
    owner="$(sudo ss -tlnpH "sport = :${port}" | grep -v 'nginx' || true)"
    if [[ -n "${owner}" ]]; then
        echo "Lỗi: cổng ${port} đang bị tiến trình khác sử dụng:" >&2
        echo "${owner}" >&2
        exit 1
    fi
done
log "Cổng 8080 và 8090 sẵn sàng."

# --- Bước 2: tạo thư mục mã nguồn và sao chép index.html -------------------
sudo mkdir -p /var/www/beta-app/html /var/www/internal-app/html
sudo cp "${SRC_DIR}/beta-app/index.html"     /var/www/beta-app/html/index.html
sudo cp "${SRC_DIR}/internal-app/index.html" /var/www/internal-app/html/index.html

# --- Bước 3: phân quyền (thư mục 750, file 640, owner devops:www-data) -----
sudo chown -R "${WEB_USER}:${WEB_GROUP}" /var/www/beta-app /var/www/internal-app
sudo find /var/www/beta-app /var/www/internal-app -type d -exec chmod 750 {} +
sudo find /var/www/beta-app /var/www/internal-app -type f -exec chmod 640 {} +
log "Đã tạo thư mục mã nguồn và phân quyền."

# --- Bước 4: cài file cấu hình Nginx và bật site ---------------------------
sudo cp "${SRC_DIR}/multi-port.conf" "${SITES_AVAILABLE}/${SITE_NAME}"
# ln -sfn: ghi đè symlink nếu đã tồn tại, không lỗi khi chạy lại
sudo ln -sfn "${SITES_AVAILABLE}/${SITE_NAME}" "${SITES_ENABLED}/${SITE_NAME}"
log "Đã bật site ${SITE_NAME}."

# --- Bước 5: kiểm tra cú pháp trước khi reload -----------------------------
sudo nginx -t
sudo systemctl reload nginx
log "Nginx đã reload."

# --- Bước 6: mở cổng trên UFW (ufw allow không tạo rule trùng) -------------
for port in "${PORTS[@]}"; do
    sudo ufw allow "${port}/tcp"
done
sudo ufw status numbered

# --- Bước 7: kiểm tra nội bộ ------------------------------------------------
sudo ss -tlnp | grep nginx
for port in "${PORTS[@]}"; do
    printf 'Cổng %s: ' "${port}"
    curl -s "http://127.0.0.1:${port}" | grep -o "<title>.*</title>"
done

log "Hoàn tất. Nhớ mở cổng 8080 và 8090 trên DigitalOcean Cloud Firewall (xem do_cloud_firewall_rules.md)."

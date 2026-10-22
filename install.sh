#!/usr/bin/env bash
# Cài / cập nhật php8.1 đã vá PHP2Shell (CVE-2026-109618, CVE-2026-109619) trên Amazon Linux 2023.
#
#   curl -fsSL https://raw.githubusercontent.com/damnxRelipasoft/relipa-php2shell-al2023-php81/main/install.sh -o install.sh
#   less install.sh          # đọc trước khi chạy
#   sudo bash install.sh
#
# Script chỉ: thêm 1 file .repo + import 1 GPG key + dnf update 'php8.1*'. Không restart dịch vụ.
set -euo pipefail

REPO_RAW="${REPO_RAW:-https://raw.githubusercontent.com/damnxRelipasoft/relipa-php2shell-al2023-php81/main}"
REPO_FILE=/etc/yum.repos.d/relipa-php2shell.repo

if ! grep -q 'Amazon Linux 2023' /etc/os-release 2>/dev/null; then
  echo "Chỉ dành cho Amazon Linux 2023." >&2; exit 1
fi
if ! rpm -q php8.1-common >/dev/null 2>&1; then
  echo "Máy này chưa cài php8.1 (gói Amazon). Script chỉ cập nhật, không cài mới." >&2; exit 1
fi

echo "== 1. Import GPG key ký gói"
rpm --import "${REPO_RAW}/RPM-GPG-KEY-relipa-php2shell"

echo "== 2. Thêm repo"
cat > "$REPO_FILE" <<EOF
[relipa-php2shell]
name=php8.1 rebuilt with PHP2Shell fix (AL2023)
baseurl=${REPO_RAW}/al2023/\$basearch/
enabled=1
gpgcheck=1
repo_gpgcheck=0
gpgkey=${REPO_RAW}/RPM-GPG-KEY-relipa-php2shell
includepkgs=php8.1*
# Repo Amazon dùng priority=10; phải nhỏ hơn để dnf chọn gói đã vá thay vì gói Amazon cùng tên
priority=1
skip_if_unavailable=1
EOF

echo "== 3. Cập nhật php8.1*"
dnf -q clean expire-cache
dnf update -y 'php8.1*'

echo "== 4. Kiểm chứng"
rpm -q php8.1-common
rpm -q --changelog php8.1-common | head -3
if ! rpm -q php8.1-common | grep -q php2shell; then
  echo "KHÔNG đúng bản đã vá. Kiểm tra lại repo." >&2; exit 1
fi

cat <<'EOF'

Xong. Còn phải restart dịch vụ để nạp binary mới:
  sudo systemctl restart php-fpm        # PHP-FPM
  sudo systemctl restart httpd          # nếu dùng mod_php
Tuỳ chọn, ghim phiên bản:
  sudo dnf install -y python3-dnf-plugin-versionlock && sudo dnf versionlock add 'php8.1*'
EOF

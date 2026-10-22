#!/usr/bin/env bash
# Ký RPM trong out/ bằng GPG key và tạo metadata repo vào al2023/ (chính là thư mục dnf đọc trên GitHub) (chạy rpmsign/createrepo trong container AL2023).
#   GPG_EMAIL=devops@relipasoft.com ./sign-and-repo.sh
# Yêu cầu: private key đã có trong gpg của máy chạy script.
set -euo pipefail
cd "$(dirname "$0")"
GPG_EMAIL="${GPG_EMAIL:-devops@relipasoft.com}"
TMPKEY=$(mktemp); trap 'rm -f "$TMPKEY"' EXIT
gpg --armor --export-secret-keys "$GPG_EMAIL" > "$TMPKEY"
gpg --armor --export "$GPG_EMAIL" > RPM-GPG-KEY-relipa-php2shell
docker run --rm -v "$PWD/out":/out:ro -v "$TMPKEY":/tmp/key.asc:ro -v "$PWD":/publish -e GPG_EMAIL="$GPG_EMAIL" -e HOST_UID="$(id -u)" -e HOST_GID="$(id -g)" amazonlinux:2023 bash -c '
  set -e
  dnf -q swap -y gnupg2-minimal gnupg2 >/dev/null; dnf -q install -y rpm-sign createrepo_c >/dev/null
  gpg --batch --import /tmp/key.asc 2>/dev/null
  mkdir -p /publish/al2023/x86_64 /publish/al2023/SRPMS
  cp /out/*.x86_64.rpm /publish/al2023/x86_64/; cp /out/*.src.rpm /publish/al2023/SRPMS/
  cd /publish/al2023
  rpmsign --define "_gpg_name ${GPG_EMAIL}" --addsign x86_64/*.rpm SRPMS/*.rpm >/dev/null
  gpg --armor --export "${GPG_EMAIL}" > /tmp/pub.asc; rpm --import /tmp/pub.asc
  rpm -K x86_64/*.rpm SRPMS/*.rpm | grep -v "digests signatures OK" && { echo "co RPM chua ky dung"; exit 1; } || true
  createrepo_c -q --update x86_64; createrepo_c -q --update SRPMS
  gpg --batch --yes --detach-sign --armor -u "${GPG_EMAIL}" x86_64/repodata/repomd.xml
  echo "OK: $(ls x86_64/*.rpm | wc -l) RPM da ky"
  chown -R $HOST_UID:$HOST_GID /publish/al2023
'

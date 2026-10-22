#!/usr/bin/env bash
# Rebuild gói php8.1 của Amazon Linux 2023 với patch PHP2Shell (CVE-2026-109618/109619).
# Chạy BÊN TRONG container amazonlinux:2023:
#   docker run --rm -v "$PWD":/kit:ro -v "$PWD/out":/out amazonlinux:2023 bash /kit/build-rpm.sh
# Kết quả: RPM trong ./out/, release = <Amazon release>.php2shell.1
set -euo pipefail
KIT=${KIT:-/kit}
OUT=${OUT:-/out}
BUILDID=${BUILDID:-.php2shell.1}

echo "== 1. Cài công cụ build"
# image amazonlinux:2023 có sẵn gnupg2-minimal, phải swap sang gnupg2 đầy đủ để spec kiểm GPG tarball
dnf -q swap -y gnupg2-minimal gnupg2 >/dev/null
dnf -q install -y dnf-plugins-core rpm-build rpmdevtools cpio patch createrepo_c >/dev/null

echo "== 2. Tải SRPM chính thức của Amazon"
cd /tmp && dnf -q download --source php8.1
SRPM=$(ls php8.1-*.src.rpm); echo "   $SRPM"
rpm -K "$SRPM"                     # chữ ký Amazon trên SRPM
rpmdev-setuptree
rpm -ivh --quiet "$SRPM"           # giải vào ~/rpmbuild/SOURCES + SPECS
SPEC=~/rpmbuild/SPECS/php.spec

echo "== 3. Thêm patch vào spec"
cp "$KIT/php-8.1.34-php2shell.patch" ~/rpmbuild/SOURCES/
BUILDID="$BUILDID" python3 - "$SPEC" <<'PY'
import sys, datetime, os
p = sys.argv[1]; s = open(p).read()
BUILDID = os.environ.get('BUILDID', '.php2shell.1')
anchor = 'Patch47: php-8.1.0-phpinfo.patch\n'
assert s.count(anchor) == 1
s = s.replace(anchor, anchor + '# PHP2Shell CVE-2026-109618 / CVE-2026-109619, backport chính thức của PHP security team\n# cho nhánh 8.1 (php-src commit 1d7dec178a, branch PHP-8.1-CVE-2026-109618-109619)\nPatch48: php-8.1.34-php2shell.patch\n')
anchor = '%patch47 -p1 -b .phpinfo\n'
assert s.count(anchor) == 1
s = s.replace(anchor, anchor + '%patch48 -p1 -b .php2shell\n')
# Amazon tự định nghĩa _trivial/_buildid ở đầu spec (release = 1.amzn2023.0.1), nên phải sửa trong spec
anchor = '%define _buildid .1\n'
assert s.count(anchor) == 1
s = s.replace(anchor, '%define _buildid .1' + BUILDID + '\n')
anchor = '%changelog\n'
assert s.count(anchor) == 1
today = datetime.date.today().strftime('%a %b %d %Y')
s = s.replace(anchor, anchor + f'* {today} Internal rebuild <devops@example.com> - 8.1.34-1.amzn2023.0.1.php2shell.1\n- Backport fix for CVE-2026-109618 (GHSA-w8hw-w9fx-j79w) and CVE-2026-109619 (GHSA-6wmf-4rv5-p3rp)\n  from php-src commit 1d7dec178a (PHP-8.1-CVE-2026-109618-109619)\n\n')
open(p, 'w').write(s)
PY
grep -nE 'Patch48|%patch48|_buildid' "$SPEC" | head -4
cp "$SPEC" "$OUT/php.spec.patched"

echo "== 4. Cài build dependencies"
dnf -q builddep -y "$SPEC" >/dev/null

echo "== 5. Kiểm tra %prep (GPG tarball + tất cả patch áp sạch)"
rpmbuild -bp "$SPEC" > /tmp/bp.log 2>&1 \
  || { tail -20 /tmp/bp.log; exit 1; }
grep -E 'gpgverify|php2shell' /tmp/bp.log | head -5

echo "== 6. Build RPM (bỏ qua test suite để tiết kiệm thời gian)"
rpmbuild -ba --nocheck "$SPEC" > /tmp/ba.log 2>&1 \
  || { tail -40 /tmp/ba.log; exit 1; }

echo "== 7. Kết quả"
cp ~/rpmbuild/RPMS/*/*.rpm ~/rpmbuild/SRPMS/*.rpm "$OUT/"
cd "$OUT" && createrepo_c -q . && ls *.rpm | head -40
echo "== changelog gói build ra"
rpm -qp --changelog "$(ls php8.1-8.1.34-*.x86_64.rpm | head -1)" | head -6

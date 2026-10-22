# relipa-php2shell-al2023-php81

`php8.1` cho **Amazon Linux 2023**, build lại từ SRPM chính thức của Amazon và thêm bản vá PHP2Shell (CVE-2026-109618, CVE-2026-109619). Repo này vừa chứa mã nguồn build, vừa là **yum repo** để server cài thẳng qua `dnf`.

Amazon đã tuyên bố **"No Fix Planned"** cho `php8.1` trên AL2023 với cả hai CVE; họ chỉ vá `php8.2` → `php8.5`. Bản `php8.1 8.1.34-1.amzn2023.0.1` trong repo Amazon là bản cuối và **chưa vá**.

## Cài trên server (Amazon Linux 2023 đang chạy php8.1 của Amazon)

```bash
curl -fsSL https://raw.githubusercontent.com/damnxRelipasoft/relipa-php2shell-al2023-php81/main/install.sh -o install.sh
less install.sh            # đọc trước khi chạy
sudo bash install.sh
sudo systemctl restart php-fpm     # hoặc httpd nếu dùng mod_php
```

`install.sh` chỉ làm 3 việc: import GPG key ký gói, thêm `/etc/yum.repos.d/relipa-php2shell.repo`, chạy `dnf update 'php8.1*'`. Nó **không** restart dịch vụ và **không** cài mới php8.1 trên máy chưa có. Cuối script tự kiểm tra; nếu gói sau cập nhật không phải bản `.php2shell.1` thì script báo lỗi và thoát mã 1.

Kiểm tra sau khi cài:

```bash
rpm -q php8.1-fpm
# php8.1-fpm-8.1.34-1.amzn2023.0.1.php2shell.1.x86_64
rpm -q --changelog php8.1-common | head -3
# ... Backport fix for CVE-2026-109618 ... and CVE-2026-109619 ...
```

`php -v` **không** phân biệt được bản vá (vẫn in `PHP 8.1.34`, ngày build giữ theo spec Amazon). Luôn kiểm bằng `rpm -q`.

Ghim phiên bản trên production (khuyên dùng):

```bash
sudo dnf install -y python3-dnf-plugin-versionlock
sudo dnf versionlock add 'php8.1*'
```

### Dùng trong Dockerfile `amazonlinux:2023`

```dockerfile
FROM amazonlinux:2023
ADD https://raw.githubusercontent.com/damnxRelipasoft/relipa-php2shell-al2023-php81/main/php2shell.repo /etc/yum.repos.d/relipa-php2shell.repo
RUN rpm --import https://raw.githubusercontent.com/damnxRelipasoft/relipa-php2shell-al2023-php81/main/RPM-GPG-KEY-relipa-php2shell \
 && dnf install -y php8.1 php8.1-fpm php8.1-cli php8.1-mysqlnd php8.1-opcache php8.1-mbstring php8.1-xml \
 && rpm -q php8.1-common | grep -q php2shell \
 && dnf clean all
```

### Lưu ý quan trọng: `priority=1`

Repo Amazon trên AL2023 đặt `priority=10`. Với `dnf`, repo có priority nhỏ hơn **luôn thắng, bất kể version**. Nếu tự viết file `.repo` mà quên `priority=1`, `dnf` sẽ âm thầm cài gói Amazon chưa vá dù repo này có bản cao hơn. `install.sh` và `php2shell.repo` đã đặt sẵn. `includepkgs=php8.1*` giới hạn repo này chỉ cung cấp gói `php8.1*`, mọi gói khác vẫn lấy từ Amazon.

## Bản vá

| | |
| --- | --- |
| Gói gốc | `php8.1-8.1.34-1.amzn2023.0.1.src.rpm` từ repo Amazon (chữ ký Amazon kiểm bằng `rpm -K`) |
| Tarball PHP | `php-8.1.34.tar.xz`, spec của Amazon tự kiểm chữ ký GPG release manager trong `%prep` |
| Patch | [`php-8.1.34-php2shell.patch`](php-8.1.34-php2shell.patch) = `git diff PHP-8.1...PHP-8.1-CVE-2026-109618-109619` trên php-src, 1 commit [`1d7dec178a`](https://github.com/php/php-src/commit/1d7dec178a) "Avoid state corruption via bailout" của PHP security team, 23 file |
| Thay đổi spec | `Patch48:` + `%patch48` sau 10 patch riêng của Amazon (áp với `--fuzz=0`), `_buildid` → `.1.php2shell.1`, thêm changelog. Xem [`php.spec.patched`](php.spec.patched) |
| Release | `8.1.34-1.amzn2023.0.1.php2shell.1` |
| Ký | GPG key `Relipa PHP2Shell Package Signing <devops@relipasoft.com>`, ID `BF72CF663A4CF565`, hạn 2028-10-21. Public key: [`RPM-GPG-KEY-relipa-php2shell`](RPM-GPG-KEY-relipa-php2shell) |
| Kiến trúc | `x86_64` |

Tự kiểm chứng patch khớp với GitHub của PHP:

```bash
curl -sL https://github.com/php/php-src/compare/PHP-8.1...PHP-8.1-CVE-2026-109618-109619.diff \
  | diff -q - php-8.1.34-php2shell.patch && echo "khớp"
```

### Hai thay đổi hành vi có chủ đích (giống upstream)

- Khi request chạm `memory_limit` hoặc tràn kích thước cấp phát, worker **thoát hẳn** thay vì cố phục hồi. PHP-FPM tự tạo worker mới. Ứng dụng nào bắt lỗi `Allowed memory size exhausted` để xử lý tiếp sẽ thấy khác.
- Callback `session.upload_progress` bị vô hiệu trong code, dù `php -i` vẫn hiện `On`. Copy [`zz-php2shell.ini`](zz-php2shell.ini) vào `/etc/php.d/` nếu muốn `php -i` hiện đúng.

## Kết quả kiểm chứng (22/10/2026)

Trên container `amazonlinux:2023` sạch:

| Kiểm tra | Kết quả |
| --- | --- |
| `rpm -K` toàn bộ 28 RPM + SRPM với public key trong repo | `digests signatures OK` cả 29 file |
| `install.sh` trên máy đã cài `php8.1-fpm 8.1.34-1.amzn2023.0.1` của Amazon | Nâng `php8.1-cli/common/fpm/mysqlnd/pdo` lên `.php2shell.1`, bước tự kiểm tra pass |
| Cài mới từ repo với `gpgcheck=1` | Cài đúng bản `.php2shell.1` |
| `dnf check-update 'php8.1*'` sau khi cài | Không có bản nào thay thế, tức `dnf update` về sau không hạ về bản Amazon |
| `php -m` | Đủ extension như gói Amazon |
| `php-fpm -t` | Pass với cấu hình mặc định của Amazon |

## Build lại (cho người bảo trì repo)

```bash
# 1. Build RPM (khoảng 20 phút), kết quả trong out/ (không commit)
mkdir -p out
docker run --rm -e BUILDID=.php2shell.1 -v "$PWD":/kit:ro -v "$PWD/out":/out amazonlinux:2023 bash /kit/build-rpm.sh

# 2. Ký + tạo metadata repo vào al2023/ (cần private key trong gpg của máy chạy)
GPG_EMAIL=devops@relipasoft.com ./sign-and-repo.sh

# 3. Commit al2023/ và push
```

Khi phát hành bản mới, tăng `BUILDID` (ví dụ `.php2shell.2`) để `dnf update` nhận.

Build cho Graviton (arm64): chạy bước 1 với `--platform linux/arm64`; `sign-and-repo.sh` hiện chỉ xử lý `*.x86_64.rpm`, cần thêm `aarch64`.

## Lưu ý

- Nếu dự án cho phép, `php8.2` của Amazon (đã vá, ALAS2023-2026-3301) là đường bền hơn: nâng minor 8.1 → 8.2 thường chỉ vài deprecation. Repo này dành cho dự án chưa nâng kịp.
- Patch là "minimal mitigation" theo chính lời PHP; lỗ hổng tiếp theo trên 8.1 sẽ không có backport.
- `raw.githubusercontent.com` có giới hạn tốc độ; với vài chục server thì không vấn đề, nhiều hơn nên mirror `al2023/` vào kho nội bộ.

## Tài liệu

- [Amazon Linux Security Center – CVE-2026-109618](https://explore.alas.aws.amazon.com/CVE-2026-109618.html) (php8.1: No Fix Planned)
- [Amazon Linux Security Center – CVE-2026-109619](https://explore.alas.aws.amazon.com/CVE-2026-109619.html)
- [PHP.net – Security advisory 21/10/2026](https://www.php.net/archive/2026.php)
- [php-src commit 1d7dec178a](https://github.com/php/php-src/commit/1d7dec178a)
- [php-src – các branch backport](https://github.com/php/php-src/branches/all?query=CVE-2026)

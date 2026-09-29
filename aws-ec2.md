# Deploy MemoMind backend lên AWS EC2

Runbook này deploy API Express trong `functions/` lên một EC2 Ubuntu 24.04 tại Singapore. Nginx nhận HTTP/HTTPS, chứng chỉ HTTPS do Let's Encrypt cấp, còn Node chỉ lắng nghe trên `127.0.0.1:8080`. Hướng dẫn dành cho backend demo một máy; API chưa yêu cầu đăng nhập.

## 1. Chuẩn bị AWS, IP và domain

1. Trong AWS Console, chuyển region sang **Asia Pacific (Singapore), `ap-southeast-1`**.
2. Mở **EC2 → Instances → Launch instances** và chọn:
   - Name: `memomind-api`
   - AMI: Ubuntu Server 24.04 LTS, 64-bit x86
   - Instance type: `t3.micro` cho demo ít người dùng
   - Key pair: tạo mới, tải `.pem` và giữ an toàn
   - Storage: 10 GiB gp3
   - Network: bật public IPv4
3. Tạo security group với inbound rules:
   - SSH / TCP 22 / My IP
   - HTTP / TCP 80 / Anywhere IPv4
   - HTTPS / TCP 443 / Anywhere IPv4
   - **Không** mở TCP 8080. Giữ outbound mặc định để máy gọi Ubuntu packages và Groq API.
4. Trong **EC2 → Network & Security → Elastic IPs**, allocate và associate một Elastic IP với instance.
5. Mua domain tại registrar bạn chọn. Tạo bản ghi DNS `A`, ví dụ `api.example.com`, trỏ tới Elastic IP. Thay `api.example.com` bằng domain thật trong toàn bộ lệnh bên dưới. Chờ DNS cập nhật rồi xác nhận từ Windows:

   ```powershell
   Resolve-DnsName api.example.com
   ```

6. Trong **Billing and Cost Management → Budgets**, tạo cảnh báo chi phí. EC2, ổ đĩa và public IPv4 có thể phát sinh chi phí. Stop instance dừng phí compute nhưng ổ đĩa và Elastic IP được giữ; terminate instance và release Elastic IP khi xong demo.

## 2. SSH vào EC2 và cài runtime

Mở PowerShell tại máy phát triển, dùng vị trí `.pem` và Elastic IP thật:

```powershell
ssh -i "$env:USERPROFILE\Downloads\memo-mind.pem" ubuntu@<ELASTIC-IP>
```

Nếu Windows từ chối quyền đọc key, mở **Properties → Security** của file `.pem`, chỉ giữ quyền đọc cho tài khoản Windows hiện tại rồi thử lại. Sau khi vào máy Ubuntu:

```bash
sudo apt update
sudo apt upgrade -y
sudo apt install -y nginx unzip

curl -fsSL https://deb.nodesource.com/setup_24.x | sudo -E bash -
sudo apt install -y nodejs
node --version
npm --version
```

Node 24 là nhánh LTS hiện tại; backend khai báo tương thích với Node `>=18`.

## 3. Đóng gói backend và chuyển lên server

Từ PowerShell tại thư mục gốc repository. Chỉ đưa lên server file ứng dụng và lockfile, không đưa `.env`, credentials hoặc `node_modules`:

```powershell
$deployDir = Join-Path $env:TEMP "memo-mind-functions"
New-Item -ItemType Directory -Force $deployDir | Out-Null
Copy-Item .\functions\index.js, .\functions\package.json, .\functions\package-lock.json $deployDir
Compress-Archive -Path "$deployDir\*" -DestinationPath "$deployDir.zip" -Force
scp -i "$env:USERPROFILE\Downloads\memo-mind.pem" "$deployDir.zip" ubuntu@<ELASTIC-IP>:/tmp/memo-mind-functions.zip
```

Trên EC2, tạo thư mục ứng dụng và tài khoản Linux riêng cho service:

```bash
sudo useradd --system --home /opt/memomind --shell /usr/sbin/nologin memomind
sudo mkdir -p /opt/memomind/functions
sudo unzip -o /tmp/memo-mind-functions.zip -d /opt/memomind/functions
sudo chown -R memomind:memomind /opt/memomind
cd /opt/memomind/functions
sudo -u memomind npm ci --omit=dev
```

Nếu chạy lại `useradd` khi tài khoản đã tồn tại, bỏ qua riêng lệnh đó.

## 4. Cấu hình Groq key và systemd

Tạo secret trực tiếp trên máy chủ, không commit file này và không dán key vào command line:

```bash
sudo nano /opt/memomind/functions/.env
```

Nội dung:

```dotenv
GROQ_API_KEY=<GROQ_API_KEY_THẬT>
GROQ_MODEL=openai/gpt-oss-20b
PORT=8080
HOST=127.0.0.1
```

Lưu file rồi đặt quyền:

```bash
sudo chown memomind:memomind /opt/memomind/functions/.env
sudo chmod 600 /opt/memomind/functions/.env
```

Tạo service:

```bash
sudo nano /etc/systemd/system/memomind.service
```

```ini
[Unit]
Description=MemoMind API
After=network.target

[Service]
Type=simple
User=memomind
WorkingDirectory=/opt/memomind/functions
Environment=NODE_ENV=production
EnvironmentFile=/opt/memomind/functions/.env
ExecStart=/usr/bin/node /opt/memomind/functions/index.js
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
```

Khởi chạy và kiểm tra:

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now memomind
sudo systemctl status memomind
sudo journalctl -u memomind -n 50 --no-pager
curl -i http://127.0.0.1:8080/api/health
```

Service bind loopback nhờ `HOST=127.0.0.1`; Nginx sẽ là cửa vào duy nhất. Backend giới hạn endpoint tạo flashcard ở 10 request / 15 phút / IP. Đây là bộ đếm trong bộ nhớ cho một process, phù hợp demo; chưa thay thế đăng nhập hay quota ở Groq.

## 5. Cấu hình Nginx và HTTPS

Tạo virtual host, thay `api.example.com` bằng domain thật:

```bash
sudo nano /etc/nginx/sites-available/memomind
```

```nginx
server {
    listen 80;
    listen [::]:80;
    server_name api.example.com;

    client_max_body_size 2m;

    location / {
        proxy_pass http://127.0.0.1:8080;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_connect_timeout 5s;
        proxy_read_timeout 100s;
        proxy_send_timeout 100s;
    }
}
```

Kích hoạt site và xác thực cấu hình:

```bash
sudo ln -s /etc/nginx/sites-available/memomind /etc/nginx/sites-enabled/memomind
sudo rm -f /etc/nginx/sites-enabled/default
sudo nginx -t
sudo systemctl reload nginx
```

Cài Certbot qua snap và để Certbot cập nhật Nginx, cấp cert, bật chuyển hướng HTTPS:

```bash
sudo snap install core
sudo snap refresh core
sudo apt remove -y certbot
sudo snap install --classic certbot
sudo ln -s /snap/bin/certbot /usr/local/bin/certbot
sudo certbot --nginx -d api.example.com
sudo certbot renew --dry-run
```

Khi Certbot hỏi, nhập email nhận thông báo, đồng ý điều khoản và chọn chuyển hướng HTTP sang HTTPS. Kiểm tra từ EC2 và máy cá nhân:

```bash
curl -i https://api.example.com/api/health
```

Kết quả mong đợi: HTTP `200` và JSON có `"status":"ok"`. Route tạo flashcard là `POST /api/v1/materials/flashcards/generate`.

## 6. Build app Android trỏ tới EC2

Manifest chính của Android đã khai báo quyền Internet. Từ PowerShell ở thư mục gốc repository, thay domain bằng domain thật:

```powershell
flutter build apk --release --dart-define=BACKEND_BASE_URL=https://api.example.com
```

APK được tạo ở `build\app\outputs\flutter-apk\app-release.apk`. Cài lên điện thoại thật và thử luồng tạo flashcard bằng mạng di động hoặc Wi-Fi khác với máy EC2. Không dùng `10.0.2.2` trong build release. Timeout request của app là 90 giây để chờ Groq.

## 7. Cập nhật và xử lý sự cố

Để phát hành bản backend mới, tạo lại zip ba file ở bước 3, SCP lên `/tmp`, giải nén vào `/opt/memomind/functions`, chạy lại `npm ci --omit=dev`, đặt lại owner và restart:

```bash
sudo chown -R memomind:memomind /opt/memomind
sudo systemctl restart memomind
sudo systemctl status memomind
```

Các lệnh chẩn đoán:

```bash
sudo systemctl status memomind
sudo journalctl -u memomind -f
sudo nginx -t
sudo systemctl status nginx
curl -i http://127.0.0.1:8080/api/health
curl -i https://api.example.com/api/health
```

Nếu HTTPS không hoạt động, xác nhận DNS trỏ đến Elastic IP, security group cho phép 80/443 và Nginx đang chạy. Nếu service không khởi động, kiểm tra `.env` có `GROQ_API_KEY` hợp lệ, `npm ci` hoàn tất và log systemd. Khi hoàn tất demo, terminate EC2, xóa volume không cần giữ và release Elastic IP; domain có thể được giữ lại.

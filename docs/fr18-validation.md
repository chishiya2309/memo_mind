# FR18 — kết quả kiểm tra và nghiệm thu

Ngày kiểm tra: **03/10/2026**. Kiến trúc: Firebase Auth, Express, S3 riêng tư và Firestore metadata; SQLite v9 là nguồn cho học offline. Không triển khai đồng bộ tự động hoặc hợp nhất FR19/FR20.

## Trạng thái bàn giao

| Kiểm tra | Kết quả |
|---|---|
| Flutter analyze | Đạt, không có issue |
| Flutter unit/widget suite | **202 test đạt**, gồm 22 unit/widget test FR18 |
| Backend tests | 28 đạt, 1 Firestore rules test được chạy riêng bằng emulator |
| Firestore Emulator | 1 test đạt: owner/verified read, chặn UID khác và mọi client write |
| ZIP Flutter → Node | Đạt: checksum/fingerprint và gói có MCQ, nguồn, lịch sử ôn |
| S3 presigner offline | Đạt: TTL 600 giây, ký checksum/content-length/content-type/If-None-Match |
| npm audit | 0 vulnerability, cả dependency production và development |
| APK release | Chờ build sau khi Flutter suite đạt |
| Android với Firebase/S3 thật | **Chưa nghiệm thu**: chưa có project, bucket và backend HTTPS |

Kiểm thử presigner chứng minh SDK tạo hợp đồng URL đúng; không chứng minh bucket policy được triển khai hoặc IAM/cloud hoạt động. Firestore Emulator không thay thế IAM/backend production. APK chưa có config cloud sẽ mở kho offline và báo dịch vụ tài khoản chưa cấu hình.

## Đối chiếu AC01–AC12

| AC | Bằng chứng tự động | Phần phải thử Android/cloud thật |
|---|---|---|
| AC01 Google/email | Form bắt buộc, hủy Google giữ kho khách, controller chọn kho theo UID | Google chooser, email login và cached session Firebase |
| AC02 Tạo/xác minh | 8 ký tự/confirm, giữ nguyên mật khẩu có khoảng trắng, gửi verification lỗi không tạo lặp, chỉ gắn sau verified + xác nhận | Nhận email, mở link, reload/refresh token, Firebase Password policy |
| AC03 Reset/lỗi | Không lưu app_settings/credentials vào ZIP; backup token chỉ gửi tới URL được cấu hình | Reset email thật, thông báo trung tính cho email không tồn tại, provider errors |
| AC04 Khách/A/B | Registry ownership, các DB riêng, revoke repository cũ, logout giữ DB A và mở khách | Xác nhận gắn/hủy, đổi hai Firebase UID trên thiết bị |
| AC05 Gói đầy đủ | Round-trip MCQ, event/session, ảnh, file checksum; ZIP thiếu/hỏng và giới hạn bị chặn | Ảnh/PDF thực, normalization/OCR, xem nguồn sau restore; tối đa 100 MiB/1.000 tệp |
| AC06 Retry | Retry cùng ID/hash, checksum hỏng không tăng quota; finalize giữ bản ready trước | Ngắt Wi-Fi/di động giữa upload; app restart giữa upload |
| AC07 Học khi backup | Ghi deck sau t0 không vào snapshot, revision tăng trong transaction, rollback không tăng revision, file pin trì hoãn xóa | Ôn/chỉnh ảnh thực khi upload, kiểm tra responsiveness trên kho lớn |
| AC08 Offline/phiên lỗi | Kho guest/owned độc lập; API token và mã lỗi riêng | Offline với cached Firebase session, revoke/expire token ở Firebase |
| AC09 Đổi UID | Callback finalize muộn của A không hiện thành công cho B; backend chặn cross-UID | Đổi tài khoản/logout trong S3 PUT và restore trên Android |
| AC10 Mất phản hồi | Double tap một job; mất phản hồi/commit finalize đối chiếu ready, quota tăng một lần; lease chặn finalize/delete đồng thời | Kill app sau cloud ready trước khi client nhận kết quả |
| AC11 Khôi phục | Check UID/schema/hash, nhập kho mới và giữ ID/session/event/deviceId cũ; UI chỉ chuyển sau xác nhận; kho hiện hành giữ nguyên | PDF/ảnh thật, nguồn được remap; lỗi disk đầy/nhập schema và hủy chuyển kho |
| AC12 Provider/FR16/17 | Repository theo context cố định, hủy lịch cũ trước revoke, toàn bộ tests review/reminder/statistics chạy cùng suite | Link Google/password cùng UID, credential UID khác, kiểm tra notification và statistics sau đổi kho |

Các dòng trên ghi phạm vi bằng chứng, không tuyên bố toàn bộ AC đã đạt trên dịch vụ thật.

## Lệnh kiểm tra

```powershell
flutter analyze
flutter test --concurrency=1 --reporter expanded
# Flutter test tạo fixture tại .dart_tool/fr18 cho kiểm tra tương thích Node:
$env:FR18_FLUTTER_FIXTURE=(Resolve-Path .dart_tool/fr18).Path
Set-Location functions
npm ci
node --test --test-concurrency=1
npm audit
Set-Location ..
firebase emulators:exec --only firestore --project demo-memomind 'node --test functions/test/firestore-rules.test.js'
flutter build apk --release
```

Máy kiểm tra dùng temp ở `.dart_tool/fr18-temp`, Gradle cache `D:\Gradle_Cache` và emulator download ở `.dart_tool/firebase-emulators`. Lần chạy nhiều worker bị thiếu bộ nhớ hệ điều hành; chạy tuần tự để tránh lỗi môi trường đó. Nếu cần đặt temp trên D trong phiên PowerShell:

```powershell
New-Item -ItemType Directory .dart_tool/fr18-temp -Force | Out-Null
$env:TEMP=(Resolve-Path .dart_tool/fr18-temp).Path
$env:TMP=$env:TEMP
```

Chạy Flutter tests và build lần lượt, để Flutter cập nhật đúng plugin registrants cho từng target.

## Cấu hình và nghiệm thu cloud

Làm theo [hướng dẫn tạo/nối Firebase, S3 và Express](deployment/fr18-setup.md). Build có cloud config:

```powershell
flutter build apk --release --dart-define-from-file=config/fr18.local.json
```

Giới hạn mặc định: **100 MiB gói và giải nén; 1.000 tệp nguồn; 5 ready/workspace; 1 pending/workspace; timeout và URL ký 10 phút**. Không tự xóa bản cũ; cần xác nhận xóa, tombstone `deleting` cho retry. Lifecycle staging 1 ngày dọn object mồ côi sau khi URL cũ hết hạn.

Chưa triển khai Firebase project/S3/HTTPS, chưa kiểm chứng bucket policy và IAM thực tế, chưa thử tải 100 MiB trên thiết bị, chưa ký APK bằng release key riêng. Gradle release hiện dùng debug certificate của repo; cần release signing riêng khi phát hành.

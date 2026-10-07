# Tạo và nối Firebase + Amazon S3 cho FR18

Backend là Express trong `functions/`, ứng dụng Android hiện có package `vn.edu.hcmute.memo_mind`. Các bước dưới đây hướng dẫn cấu hình Firebase, S3 và backend; kết nối cloud thật cần được kiểm chứng sau khi nối. Kiểm thử với adapter giả và Firestore Emulator không thay thế nghiệm thu cloud thật.

## 1. Tạo Firebase project

1. Mở [Firebase Console](https://console.firebase.google.com/), chọn **Add project**, tạo project mới. Analytics không bắt buộc cho FR18. Ghi lại **Project ID** trong Project settings.
2. Thêm Android app với package `vn.edu.hcmute.memo_mind`. Nếu đã đăng ký package cũ, thêm Android app mới trong cùng Firebase project; không tạo lại Auth, Firestore hoặc S3. Thêm SHA cho app mới và tải cấu hình mới vào `android/app/google-services.json`. Nếu dùng Dart define thay cho cấu hình Android, cập nhật `config/fr18.local.json`, đặc biệt `FIREBASE_ANDROID_APP_ID` theo app mới. Xem [đăng ký Android app](https://firebase.google.com/docs/android/setup).
3. Repo dùng chung `android/keystore/team-debug.keystore` cho debug và profile. Đây là bản sao debug key hiện có của người thiết lập, có SHA-1/SHA-256 đã đăng ký Firebase cho package `vn.edu.hcmute.memo_mind`. Thành viên clone repo không cần chạy lệnh lấy SHA hoặc thêm SHA của máy mình. Giữ nguyên file khóa này; nếu thiếu, khôi phục từ repo thay vì tạo khóa mới. APK/AAB release dùng khóa riêng trong `android/keystore/upload-keystore.jks`. Muốn Google Sign-In hoạt động trong bản release, người quản lý cần đăng ký SHA của khóa release trong Firebase và tải lại `google-services.json`; bản do Google Play phân phối còn cần chứng chỉ Play App Signing tương ứng.
4. **Authentication → Sign-in method**: bật **Email/Password** và **Google**, chọn email hỗ trợ. Nếu bật Password policy, đặt minimum length 8, không thêm điều kiện ngoài đặc tả. Login không bị client áp lại chính sách mật khẩu mới.
5. **Authentication → Templates**: kiểm tra email verification/password reset và tên ứng dụng. Người dùng mở liên kết Firebase, quay lại MemoMind và chọn **Tôi đã xác minh** để reload user và refresh token.
6. Người quản lý tải lại `google-services.json` sau khi bật Google và đăng ký SHA, rồi cập nhật file tại `android/app/` trong repo. Thành viên clone dùng file đã chia sẻ, không cần cấu hình Firebase riêng. Lấy cấu hình công khai cho Flutter khi cần dùng Dart define:

   | Dart define | Giá trị |
   |---|---|
   | `FIREBASE_PROJECT_ID` | `project_info.project_id` |
   | `FIREBASE_SENDER_ID` | `project_info.project_number`, dạng chuỗi |
   | `FIREBASE_ANDROID_APP_ID` | Client đúng package → `client_info.mobilesdk_app_id` |
   | `FIREBASE_API_KEY` | Client đúng package → `api_key[0].current_key` |
   | `GOOGLE_SERVER_CLIENT_ID` | OAuth **Web application** client ID (`client_type: 3`) |

Cách build Android thuận tiện: đặt `google-services.json` ở `android/app/`. Project khai báo Google Services plugin 4.5.0 trong `android/settings.gradle.kts`, áp dụng tại app khi file có mặt và khởi tạo Firebase từ Android resources. Nếu JSON có Web OAuth client (`client_type: 3`), Google Sign-In tự đọc client ID đó. Khi dùng cách này, để trống bốn biến `FIREBASE_*` và `GOOGLE_SERVER_CLIENT_ID` trong config Flutter; chỉ cần điền `BACKEND_BASE_URL`. Nếu khai báo `FIREBASE_PROJECT_ID`, mã vẫn dùng `FirebaseOptions` từ cả bốn biến `FIREBASE_*`; các giá trị phải khớp file Android. Firebase SDK/BoM được quản lý bởi các FlutterFire plugin trong `pubspec.yaml`, không cần thêm dependency Analytics native cho FR18. Không dùng Android OAuth client ID thay cho Web client ID. Đây là cấu hình client, không phải Firebase Admin private key. Xem [Flutter setup](https://firebase.google.com/docs/flutter/setup) và [Google Sign-In Android](https://pub.dev/packages/google_sign_in_android).

### Clone và cài APK trong nhóm

Repo phân phối debug keystore chung và Firebase Android client config. Sau khi cài Flutter/Android SDK, thành viên chạy `flutter pub get` và build/run debug/profile bình thường. Release cần `android/key.properties` với `storeFile`, `storePassword`, `keyAlias`, `keyPassword` và file keystore tương ứng; thiếu một trong các mục này thì build release báo lỗi, không dùng khóa debug thay thế. `storeFile` được tính từ thư mục `android/`, ví dụ `keystore/upload-keystore.jks`. Hai file ký release nằm ngoài Git và phải được sao lưu an toàn cùng mật khẩu để có thể ký các bản cập nhật sau.

Tạo file cài trực tiếp bằng `flutter build apk --release --dart-define-from-file=config/fr18.local.json -t lib/main.dart`; APK nằm trong `build/app/outputs/flutter-apk/`. Tạo App Bundle bằng `flutter build appbundle --release --dart-define-from-file=config/fr18.local.json -t lib/main.dart`; AAB nằm trong `build/app/outputs/bundle/release/`. AAB không cài trực tiếp như APK. `config/fr18.local.json` cần trỏ backend đến HTTPS đang hoạt động nếu muốn dùng tính năng trực tuyến.

Nếu Android từ chối cập nhật vì bản cũ ký bằng khóa khác, xuất dữ liệu cục bộ cần giữ trước khi gỡ bản cũ rồi cài bản release. Gỡ ứng dụng có thể mất dữ liệu; không cần gỡ khi cài mới hoặc chữ ký đã khớp. Khóa chung chỉ dành cho phát triển/demo, không dùng cho phát hành production. Chỉ `android/keystore/team-debug.keystore` được phép đưa vào Git; release keystore, `key.properties`, Firebase Admin private key và server secrets vẫn phải giữ ngoài repo.

## 2. Tạo Firestore và quyền backend

1. **Firestore Database → Create database**: database mặc định `(default)`, Singapore `asia-southeast1`, chế độ Production. Vị trí database không đổi sau khi tạo.
2. Từ gốc repo, triển khai duy nhất rules:

   ```powershell
   firebase login
   firebase deploy --only firestore:rules --project YOUR_FIREBASE_PROJECT_ID
   ```

   Rules chỉ cho chủ sở hữu đã xác minh đọc metadata, không cho client ghi. Không chạy `firebase deploy` toàn bộ: Express hiện tại không phải Cloud Functions. Không bật Firebase Storage/Cloud Functions cho FR18.
3. **Project settings → Service accounts**: tạo Firebase Admin private key cho máy phát triển, lưu ngoài repo, ví dụ `D:\MemoMindSecrets\firebase-admin.json`. Không gửi private key vào chat hoặc đưa vào Flutter.
4. Backend đặt `GOOGLE_APPLICATION_CREDENTIALS` trỏ tới file đó. Production dùng secret mount/Workload Identity. Service account tùy chỉnh cần quyền Firestore (**Cloud Datastore User**) và đọc Firebase Auth user để kiểm tra revoked token (**Firebase Authentication Viewer**). Admin SDK dùng IAM, không bị client security rules chi phối.

Xem [Admin SDK setup](https://firebase.google.com/docs/admin/setup), [ID token verification](https://firebase.google.com/docs/auth/admin/verify-id-tokens) và [Firestore rules](https://firebase.google.com/docs/firestore/security/get-started).

## 3. Tạo S3 riêng tư ở Singapore

1. AWS Console → **S3 → Create bucket**: General purpose, region **Asia Pacific (Singapore), `ap-southeast-1`**, tên bucket duy nhất của bạn.
2. Giữ **Bucket owner enforced**, bật cả bốn mục **Block Public Access**, mã hóa mặc định **SSE-S3**, dùng S3 Standard. Nếu chuyển sang SSE-KMS phải cấp thêm quyền KMS cho backend.
3. Thay mọi `YOUR_BUCKET` trong `fr18-s3-bucket-policy.example.json`, dán vào **Permissions → Bucket policy**. Policy bắt buộc HTTPS và `If-None-Match` cho staging/ready. Flutter chỉ nhận URL PUT staging; backend copy gói đã kiểm tra sang ready. Xem [conditional writes](https://docs.aws.amazon.com/AmazonS3/latest/userguide/conditional-writes.html).
4. Tạo IAM policy từ `fr18-s3-iam-policy.example.json`, thay `YOUR_BUCKET`. Gắn policy vào **IAM role** của EC2/ECS nếu backend chạy trên AWS. Chạy local/ngoài AWS thì dùng IAM user riêng cho backend và secret store; không dùng root access key. Dùng bucket riêng cho FR18: policy cho phép `ListBucket` trên bucket đó để `HeadObject` nhận 404 khi object chưa tồn tại; quyền đọc/ghi/xóa object vẫn chỉ ở `staging/` và `ready/`. Không giới hạn `ListBucket` bằng `s3:prefix` vì request HEAD không gửi prefix và có thể bị trả 403. Xem [quyền HeadObject](https://docs.aws.amazon.com/AmazonS3/latest/API/API_HeadObject.html).
5. Tạo lifecycle rule chỉ cho prefix `staging/`: expire sau **1 ngày**. URL đã cấp có thể còn hiệu lực 10 phút sau khi hủy job; lifecycle dọn staging mồ côi. Không expire `ready/`.
6. Android native không cần S3 CORS. Không bật website/public access cho bucket.

Firestore, S3 và host Express có thể phát sinh phí. Thiết lập budget alerts; xem [giá Firestore](https://firebase.google.com/docs/firestore/pricing) và [giá S3](https://aws.amazon.com/s3/pricing/).

## 4. Chạy Express local trước

Node.js 22 trở lên. Từ gốc repo:

```powershell
if (!(Test-Path functions/.env)) { Copy-Item functions/.env.example functions/.env }
Set-Location functions
npm ci
```

Điền trong `functions/.env`:

```dotenv
FIREBASE_PROJECT_ID=YOUR_FIREBASE_PROJECT_ID
GOOGLE_APPLICATION_CREDENTIALS=D:/MemoMindSecrets/firebase-admin.json
AWS_REGION=ap-southeast-1
S3_BACKUP_BUCKET=YOUR_BUCKET
PORT=8080
HOST=0.0.0.0
# Chỉ khi không dùng IAM role/default AWS profile:
AWS_ACCESS_KEY_ID=YOUR_SERVER_ONLY_ACCESS_KEY
AWS_SECRET_ACCESS_KEY=YOUR_SERVER_ONLY_SECRET
```

Giữ Groq/Gemini config nếu cần AI; FR18 không cần AI key. Chạy `npm start`.

- Android Emulator cùng máy: `BACKEND_BASE_URL=http://10.0.2.2:8080`.
- Điện thoại thật qua USB: `adb reverse tcp:8080 tcp:8080`, dùng `http://127.0.0.1:8080` cho debug.
- HTTP loopback/emulator chỉ dùng debug; release cần HTTPS. Không dùng IP LAN HTTP vì API client không cho phép.

`/api/v1/backups` trả 401 khi thiếu/sai token, 403 khi email chưa xác minh và 503 khi chưa cấu hình dịch vụ. Không log Firebase token, AWS secrets hoặc presigned URL.

## 5. Đưa Express lên HTTPS

Có thể chạy Node/container trên host bạn quản lý. Trên AWS, dùng EC2/ECS có IAM role bước 3, reverse proxy/load balancer HTTPS và tên miền/chứng chỉ TLS. FR18 không cần Cloud Functions.

Hợp đồng deploy:

- Install: trong `functions/`, `npm ci --omit=dev`; start: `npm start`, Node 22 trở lên, `HOST=0.0.0.0`, `PORT` do host cấp.
- Inject Firebase/AWS config bằng secret store. Có IAM role thì bỏ AWS access key/secret khỏi env.
- Outbound HTTPS tới Firebase Auth, Firestore, S3; temp disk ghi được, đủ tối thiểu 100 MiB mỗi finalize đồng thời. Đặt concurrency phù hợp RAM/temp disk.
- Proxy timeout tối thiểu 10 phút cho finalize. Flutter upload trực tiếp S3, không chuyển gói qua Express.
- Firestore giữ quota/lease giữa các instance, S3 giữ gói; không lưu lâu dài trên disk host.
- `BACKEND_BASE_URL` là URL gốc HTTPS do bạn kiểm soát, không thêm `/api/v1/backups`.

Repo không tự tạo hostname, tài khoản thanh toán hay dịch vụ trả phí. Bắt đầu bằng local để kiểm chứng Firebase/S3, sau đó cập nhật URL HTTPS khi đã triển khai host.

## 6. Nối Flutter

Từ gốc repo, copy `config/fr18.example.json` thành `config/fr18.local.json` (đã gitignore). Nếu đã đặt `google-services.json` đúng package và có Web OAuth client, cấu hình đơn giản cho Android Emulator là:

```json
{
  "BACKEND_BASE_URL": "http://10.0.2.2:8080"
}
```

Các biến `FIREBASE_*` và `GOOGLE_SERVER_CLIENT_ID` không cần khai báo với cách này. Sau khi thay `google-services.json`, dừng ứng dụng và build lại; hot reload không cập nhật Android resources.

Nếu muốn dùng Dart define, điền đầy đủ cấu hình bước 1 và URL backend:

```json
{
  "FIREBASE_PROJECT_ID": "YOUR_FIREBASE_PROJECT_ID",
  "FIREBASE_API_KEY": "YOUR_PUBLIC_FIREBASE_CLIENT_API_KEY",
  "FIREBASE_ANDROID_APP_ID": "1:YOUR_PROJECT_NUMBER:android:YOUR_APP_ID",
  "FIREBASE_SENDER_ID": "YOUR_PROJECT_NUMBER",
  "GOOGLE_SERVER_CLIENT_ID": "YOUR_WEB_OAUTH_CLIENT_ID.apps.googleusercontent.com",
  "BACKEND_BASE_URL": "http://10.0.2.2:8080"
}
```

```powershell
flutter run --dart-define-from-file=config/fr18.local.json
# Đổi BACKEND_BASE_URL sang HTTPS trước khi build release:
flutter build apk --release --dart-define-from-file=config/fr18.local.json
```

Không đưa Admin JSON, AWS secrets, Groq/Gemini key vào dart-define. Khi thiếu cả cấu hình Android lẫn Dart define, ứng dụng vẫn mở kho offline. Backup client không mặc định gửi token tới URL backend AI có sẵn.

## 7. Nghiệm thu cloud thật

1. Google/email, verification/reset/link provider; kiểm tra package/SHA/Web client ID khi Google báo `DEVELOPER_ERROR`.
2. Kho khách có ảnh/PDF, MCQ và lịch sử; xác nhận email/số deck-card trước khi gắn. Kiểm tra khách/A/B, logout và offline.
3. Backup: S3 ready và Firestore ready cùng checksum, không lưu URL ký trong metadata. Ôn/chỉnh ảnh khi upload: bản sao giữ t0, báo dữ liệu mới sau t0.
4. Ngắt mạng/đóng app sau upload/finalize: mở lại đối chiếu cùng backupId. Đổi UID trong lúc upload: callback cũ không cập nhật tài khoản mới.
5. Restore kho mới: giữ ID, MCQ, nguồn, lịch ôn/session/event; kho trước restore vẫn tồn tại. Bản hỏng/sai UID/schema không công bố.
6. Đủ 5 bản khác nội dung: bản thứ 6 bị chặn; xóa sau xác nhận rồi thử lại. Kiểm tra retry khi S3/Firestore lỗi.
7. Dùng object thử riêng để kiểm chứng policy: PUT điều kiện lần đầu thành công, cùng key lần hai bị 412, PUT thiếu điều kiện bị 403, anonymous GET bị 403. Token B không xin được URL backup A.

Chỉ ghi **đạt cloud thật** sau các bước trên. Bảng kết quả ở `docs/fr18-validation.md`.

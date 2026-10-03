# Tạo và nối Firebase + Amazon S3 cho FR18

Backend là Express trong `functions/`, ứng dụng Android hiện có package `com.example.memo_mind`. Chưa có Firebase project, bucket hoặc backend HTTPS được tạo cho lần triển khai này. Kiểm thử với adapter giả và Firestore Emulator không thay thế nghiệm thu cloud thật.

## 1. Tạo Firebase project

1. Mở [Firebase Console](https://console.firebase.google.com/), chọn **Add project**, tạo project mới. Analytics không bắt buộc cho FR18. Ghi lại **Project ID** trong Project settings.
2. Thêm Android app với package `com.example.memo_mind`. Nếu đổi applicationId thì đăng ký đúng package mới.
3. Trong thư mục `android`, chạy `.\gradlew.bat signingReport`, lấy SHA-1/SHA-256 và thêm vào Android app trên Firebase. Release hiện ký bằng debug key; khi dùng release key riêng phải thêm SHA của key đó.
4. **Authentication → Sign-in method**: bật **Email/Password** và **Google**, chọn email hỗ trợ. Nếu bật Password policy, đặt minimum length 8, không thêm điều kiện ngoài đặc tả. Login không bị client áp lại chính sách mật khẩu mới.
5. **Authentication → Templates**: kiểm tra email verification/password reset và tên ứng dụng. Người dùng mở liên kết Firebase, quay lại MemoMind và chọn **Tôi đã xác minh** để reload user và refresh token.
6. Sau khi bật Google và thêm SHA, tải lại `google-services.json`. Lấy cấu hình công khai cho Flutter:

   | Dart define | Giá trị |
   |---|---|
   | `FIREBASE_PROJECT_ID` | `project_info.project_id` |
   | `FIREBASE_SENDER_ID` | `project_info.project_number`, dạng chuỗi |
   | `FIREBASE_ANDROID_APP_ID` | Client đúng package → `client_info.mobilesdk_app_id` |
   | `FIREBASE_API_KEY` | Client đúng package → `api_key[0].current_key` |
   | `GOOGLE_SERVER_CLIENT_ID` | OAuth **Web application** client ID (`client_type: 3`) |

Mã dùng `FirebaseOptions` và truyền Web client ID cho Google Sign-In; không cần thêm Google Services Gradle plugin. Không dùng Android OAuth client ID thay cho Web client ID. Đây là cấu hình client, không phải Firebase Admin private key. Xem [Flutter setup](https://firebase.google.com/docs/flutter/setup) và [Google Sign-In Android](https://pub.dev/packages/google_sign_in_android).

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
4. Tạo IAM policy từ `fr18-s3-iam-policy.example.json`, thay `YOUR_BUCKET`. Gắn policy vào **IAM role** của EC2/ECS nếu backend chạy trên AWS. Chạy local/ngoài AWS thì dùng IAM user riêng cho backend và secret store; không dùng root access key.
5. Tạo lifecycle rule chỉ cho prefix `staging/`: expire sau **1 ngày**. URL đã cấp có thể còn hiệu lực 10 phút sau khi hủy job; lifecycle dọn staging mồ côi. Không expire `ready/`.
6. Android native không cần S3 CORS. Không bật website/public access cho bucket.

Firestore, S3 và host Express có thể phát sinh phí. Thiết lập budget alerts; xem [giá Firestore](https://firebase.google.com/docs/firestore/pricing) và [giá S3](https://aws.amazon.com/s3/pricing/).

## 4. Chạy Express local trước

Node.js 22 trở lên. Từ gốc repo:

```powershell
Copy-Item functions/.env.example functions/.env
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

Từ gốc repo, copy `config/fr18.example.json` thành `config/fr18.local.json` (đã gitignore). Điền cấu hình bước 1 và URL backend:

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

Không đưa Admin JSON, AWS secrets, Groq/Gemini key vào dart-define. Thiếu Firebase config vẫn mở kho offline. Backup client không mặc định gửi token tới URL backend AI có sẵn.

## 7. Nghiệm thu cloud thật

1. Google/email, verification/reset/link provider; kiểm tra package/SHA/Web client ID khi Google báo `DEVELOPER_ERROR`.
2. Kho khách có ảnh/PDF, MCQ và lịch sử; xác nhận email/số deck-card trước khi gắn. Kiểm tra khách/A/B, logout và offline.
3. Backup: S3 ready và Firestore ready cùng checksum, không lưu URL ký trong metadata. Ôn/chỉnh ảnh khi upload: bản sao giữ t0, báo dữ liệu mới sau t0.
4. Ngắt mạng/đóng app sau upload/finalize: mở lại đối chiếu cùng backupId. Đổi UID trong lúc upload: callback cũ không cập nhật tài khoản mới.
5. Restore kho mới: giữ ID, MCQ, nguồn, lịch ôn/session/event; kho trước restore vẫn tồn tại. Bản hỏng/sai UID/schema không công bố.
6. Đủ 5 bản khác nội dung: bản thứ 6 bị chặn; xóa sau xác nhận rồi thử lại. Kiểm tra retry khi S3/Firestore lỗi.
7. Dùng object thử riêng để kiểm chứng policy: PUT điều kiện lần đầu thành công, cùng key lần hai bị 412, PUT thiếu điều kiện bị 403, anonymous GET bị 403. Token B không xin được URL backup A.

Chỉ ghi **đạt cloud thật** sau các bước trên. Bảng kết quả ở `docs/fr18-validation.md`.

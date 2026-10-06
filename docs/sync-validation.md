# Kiểm tra đăng nhập và đồng bộ

## Tự động

Chạy từ thư mục dự án (chạy tuần tự để giảm bộ nhớ):

```powershell
flutter analyze --no-pub
flutter test --no-pub --concurrency=1 test/unit/sync_auth_client_test.dart test/unit/sync_scheduling_test.dart test/unit/sync_integration_test.dart test/unit/backup_api_client_test.dart test/unit/account_backup_controller_test.dart test/unit/workspace_backup_test.dart test/widget/account_backup_screen_test.dart
```

Chạy từ `functions`:

```powershell
node --test --test-concurrency=1
```

Các test Firestore cần emulator (`FIRESTORE_EMULATOR_HOST`); kiểm thử ZIP chéo cần fixture theo hướng dẫn trong test. Nếu thiếu điều kiện, các test này sẽ skip và không thay thế nghiệm thu môi trường thật.

## Hai thiết bị Android với Firebase/S3 thật

1. Nâng cấp A đang đăng nhập: tự động đồng bộ tắt. Mở tài khoản, sửa thẻ, ôn và bật/tắt Wi-Fi không tự gửi dữ liệu. Hiển thị thay đổi chờ đồng bộ; vẫn học được.
2. Bấm đồng bộ A; đăng nhập B cùng tài khoản, bấm “Đồng bộ để tải thư viện”. Kiểm tra thẻ, lịch ôn, sự kiện học và thống kê; không yêu cầu chọn snapshot. Phiên học trên B được tạo từ tiến độ đã đồng bộ.
3. Không sửa gì trên B, sửa/học thêm trên A rồi đồng bộ A/B: B vẫn nhận thay đổi. Cả hai học offline, sửa/xóa cùng thẻ: giữ sự kiện học, hiển thị xung đột, chọn bản rồi kiểm tra hội tụ.
4. Token hết hạn được làm mới âm thầm; thu hồi phiên yêu cầu “Xác thực lại”. Hủy xác thực không mất dữ liệu; thành công tiếp tục đồng bộ. Lỗi mạng/Firebase/5xx không yêu cầu đăng nhập lại. Kiểm tra log mã lỗi và `X-Request-ID`, nhất là sai Firebase project/quyền Admin.
5. Bật tự động trên A, đóng/mở và đổi mạng: đồng bộ hoạt động. B vẫn thủ công. Tắt tự động dừng retry đã hẹn. Phiên bị thu hồi không bị dirty polling thử lại liên tục.
6. Ngắt mạng/force-stop trước và sau push/ack, đổi tài khoản lúc đang gửi, bấm đồng bộ liên tiếp: không gửi trùng, không mất/lẫn dữ liệu. Đăng xuất khi có thay đổi: thử cả hủy, giữ trên máy và đồng bộ rồi đăng xuất.
7. Tải ảnh/PDF bị ngắt hoặc sai checksum: dữ liệu học đã đồng bộ vẫn dùng được, trạng thái tệp chưa hoàn tất còn sau khi mở app. Đồng bộ lại hoàn tất tệp. Kiểm tra thư viện cũ, nhập khách, khởi tạo rỗng và khôi phục snapshot vẫn theo lựa chọn chủ động.

Triển khai backend trước client và chỉ phát hành sau khi ma trận thiết bị thật đạt. Kiểm thử local không xác nhận cấu hình Firebase, quyền S3 hoặc kết nối của bản đang cài trên điện thoại.

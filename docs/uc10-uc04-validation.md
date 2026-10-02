# Báo cáo kiểm tra UC10 và UC04–UC05

Ngày kiểm tra: 02/10/2026. Phạm vi: Android, dựa trên hai đặc tả người dùng cung cấp. Flutter 3.47.5, Dart 3.13.4; thiết bị Samsung SM-A175F, Android API 36.

## Các thay đổi

- Sửa lỗi ghép code ở điều hướng Home/Thư viện/Ôn tập, mapper đọc card, câu lệnh migration và các hợp đồng mock bị lệch.
- Hoàn thiện CRUD deck/card, nhãn và tìm kiếm. Cho phép tạo thủ công BASIC/CLOZE/MCQ; kiểm tra dữ liệu tại repository và giao diện.
- Giữ nguyên loại card, nguồn, lịch và lịch sử khi sửa nội dung. Xóa mềm deck và card trong giao dịch; cập nhật số thẻ và loại dữ liệu đã xóa khỏi mọi truy vấn/queue ôn.
- Dùng cùng một luồng xem nguồn cho chi tiết card và ôn tập. Kiểm tra đúng document/page/block, bounding box hữu hạn, trong ảnh, có diện tích. Không tô sáng trên ảnh thuộc hệ tọa độ khác; ảnh thiếu/hỏng vẫn giữ quote và số trang đã lưu.
- Giữ input khi lưu form thất bại và cho phép thử lại; khóa nút trong khi ghi. Form tạo deck khi lưu học liệu cuộn được trên màn hình nhỏ, chữ lớn và bàn phím mở.
- Sửa cấu hình Android release: bước tạo plugin theo mode; rule R8 cụ thể cho tám class options/builders của các script ML Kit tùy chọn. Plugin dùng compileOnly cho những script này, còn ứng dụng chọn Latin. Giữ bước thu gọn release.
- Giữ thuật toán SM-2 hiện có, tính nguyên tử ReviewEvent/lịch/queue, eventId chống ghi trùng và khả năng tiếp tục phiên ngoại tuyến.

## Đối chiếu yêu cầu

| Yêu cầu | Hành vi được kiểm tra | Bằng chứng |
| --- | --- | --- |
| FR11 / UC10 | Tên deck bắt buộc; tạo/sửa tên và nhãn; BASIC/CLOZE/MCQ; tìm theo nội dung/nhãn; xác nhận/hủy xóa; xóa mềm không phá lịch sử/nguồn chung | test/unit/deck_management_test.dart, test/widget/deck_management_flow_test.dart, integration test Android |
| FR12 / UC04 | Lật thẻ; bốn mức Again/Hard/Good/Easy; khóa đánh giá khi chưa lật và khi đang lưu; gọi haptic | test/widget/review_session_screen_test.dart, test/unit/review_session_controller_test.dart; thao tác lật/Again trên điện thoại |
| FR13–FR14 / UC04–UC05 | eventId/deviceId/thời điểm; event + lịch + queue trong giao dịch; rollback và retry; phiên đến hạn/tự do; khôi phục phiên; SM-2 và replay xác định | test/unit/review_repository_test.dart, test/unit/sm2_scheduler_test.dart, integration test Android |
| FR15 / UC10 | Đúng trang/block/quote; highlight hợp lệ; không suy đoán nguồn khi hỏng; quote còn khi nguồn thiếu hoặc ảnh không giải mã được | test/unit/deck_management_test.dart, test/widget/deck_management_flow_test.dart, test/widget/flashcard_review_approval_test.dart |

FR13 và FR14 được ghi chung vì đặc tả được cung cấp giao chung phần lưu tiến độ và lập lịch trong UC04–UC05.

## Cơ sở dữ liệu v8

Migration kiểm tra và bổ sung decks.tags/status khi cần. Bảng cards hỗ trợ nguồn tùy chọn và nhãn, giữ ID, nội dung, provenance, lịch và thời điểm cũ. Liên kết nguồn là tham chiếu lịch sử, tránh xóa nguồn kéo theo mất card.

Các ca kiểm tra gồm v6, v7 chỉ có module review, v7 đã ghép deck tags/status, lỗi migration phải rollback, giữ ReviewEvent/deviceId/queue và kiểm tra khóa ngoại. Không dùng fallback xóa cứng hoặc âm thầm bỏ qua lỗi schema.

Lịch khởi tạo: EF 2,5; repetitions 0; interval 0; thẻ mới đến hạn ngay. Điểm 1/3/4/5; interval thành công 1, 6, rồi interval cũ × EF cũ, làm tròn gần nhất; EF tối thiểu 1,3. Again đặt lịch dài hạn +1 ngày và đưa thẻ về cuối learning queue.

## Kiểm tra trên điện thoại

integration_test/offline_deck_review_test.dart đã chạy thành công khi Wi-Fi và dữ liệu di động tắt. Sau kiểm tra, trạng thái mạng đã được phục hồi như trước.

Test sử dụng SQLite native và database tạm riêng:

1. Tạo deck và đủ ba loại card thủ công.
2. Mở chi tiết deck, vào phiên ôn, lật thẻ và đánh giá Again.
3. Xác nhận event đã ghi, learning queue và lịch dài hạn +1 ngày.
4. Đóng/mở lại SQLite, khôi phục đúng phiên, queue và deviceId.
5. Hoàn thành các thẻ còn lại, sửa card giữ lịch, xóa mềm deck.
6. Xác nhận không còn thẻ được ôn nhưng bốn event vẫn tồn tại; không có vi phạm khóa ngoại.

Đóng/mở lại database kiểm chứng lưu bền cục bộ; đây không phải thử nghiệm cưỡng bức dừng tiến trình Android ở mọi thời điểm ghi.

## Kết quả và lệnh

- Analyzer: No issues found.
- Toàn bộ unit/widget: 114/114 qua; sau đó nhóm giao diện ôn tập chạy lại 9/9 qua, có thêm ca haptic không hỗ trợ (tổng 115 ca khác nhau đã qua).
- Backend: 15/15 qua (provider mock).
- Integration test native Android ngoại tuyến: 1/1 qua.
- APK debug ứng dụng chính: build thành công.
- APK release: build thành công (207,9 MB). Cài cập nhật giữ dữ liệu bằng ADB thành công; mở MainActivity cold start thành công, màn hình Home hiển thị bình thường trên Samsung. Log theo PID ứng dụng trong lần kiểm tra không có lỗi Flutter/SQLite/crash.

Log được lưu cục bộ trong build/: uc-analyze.log, uc-audit-tests.log, uc-haptic-tests.log, uc-backend-tests.log, uc-android-integration.log, uc-apk-debug.log, uc-apk-release.log, uc-android-install.log, uc-android-launch.log và uc-android-runtime.log. Ảnh xác nhận màn hình chính: build/android-home.png. Thư mục build là artifact không đưa vào Git.

APK ứng dụng chính: build/app/outputs/flutter-apk/app-debug.apk và build/app/outputs/flutter-apk/app-release.apk. Các APK cuối dùng lib/main.dart, không dùng entrypoint integration test.

```sh
flutter analyze --no-pub
flutter test --no-pub --concurrency=1
# Trong thư mục functions:
npm test
# Android đã kết nối:
flutter test integration_test/offline_deck_review_test.dart -d DEVICE_ID
flutter build apk --debug -t lib/main.dart
flutter build apk --release -t lib/main.dart
```

Chạy test và build Flutter tuần tự để không cùng ghi file đăng ký plugin. Sau khi chạy test/debug, dùng lệnh release có bước Pub mặc định: với SDK này, cờ --no-pub bỏ qua tái tạo tooling nên GeneratedPluginRegistrant có thể còn đăng ký integration_test trong khi release đã loại dependency này. Không sửa tay file sinh tự động. Các lần test trên máy này từng thiếu dung lượng temp ở C: và cạn bộ nhớ; chuyển TEMP/TMP sang build/audit_tmp trên D:, dừng daemon Gradle đã dùng và giảm concurrency trước khi chạy lại.

## Giới hạn kiểm chứng

- Bộ test backend dùng provider mock; không nghiệm thu kết nối Groq/Gemini hay chất lượng sinh học liệu với dịch vụ thực.
- Test xác nhận lệnh haptic và luồng tiếp tục bình thường; cảm giác rung vật lý chưa được người dùng xác nhận.
- Highlight và các lỗi ảnh nguồn được kiểm tra bằng fixture unit/widget; chưa chạy toàn bộ quy trình camera/OCR/nguồn ảnh thật trên điện thoại.
- APK release hiện dùng signing key phát triển theo cấu hình sẵn có; cần signing key phát hành khi xuất bản.
- Kiểm tra này giới hạn ở Android; không xác nhận build iOS/Web/Desktop.

# FR16 — Thông báo thẻ đến hạn

## Hành vi và tích hợp

- Android; không cần mạng hoặc đăng nhập. Mở **Cá nhân → Cài đặt → Nhắc học** từ tab Cá nhân hoặc biểu tượng cá nhân ở Trang chủ.
- Tắt mặc định, giờ ban đầu chưa chọn. Bật/tắt và giờ chỉ được áp dụng khi Lưu. Rời màn hình/Hủy giữ cấu hình trước đó.
- `app_settings` lưu JSON ở `fr16.reminder_settings` và `fr16.reminder_scheduling`; schema SQLite vẫn là v8. Lưu ý định người dùng và đánh dấu dirty trong cùng giao dịch. `device_id` và các khóa khác được giữ nguyên.
- `ReminderCoordinator` tuần tự hóa lưu/đối chiếu, gộp tín hiệu thay đổi và không yêu cầu quyền khi khởi tạo/resume. Quyền và kênh được kiểm tra trực tiếp từ Android. Từ chối quyền vẫn lưu giờ và ý định bật.
- `LocalDueCardsSource` dùng chung với số lượng và phiên ôn: card/deck active, nội dung hợp lệ, lịch hợp lệ, `due_date <= t`. Lịch lỗi không được mặc định là đến hạn ngay. Danh sách có truy vấn riêng đọc cờ phiên đang dở, không thay đổi hàng đợi hoặc lịch ôn.
- Khung lập lịch: ngày địa phương hiện tại và 6 ngày tiếp theo; mốc `<= now` bị loại. `due_date` giữ nguyên milliseconds kể từ UTC epoch. Ngày nhắc tạo theo lịch của múi giờ thiết bị, không cộng 24 giờ.
- Một thông báo cho một ngày có card dự kiến đến hạn; không giả định người dùng sẽ ôn. Khóa `review_due:YYYY-MM-DD`, ID `160000000 + YYYYMMDD`, vùng `[160000000, 260000000)` dành riêng FR16.
- Nội dung cố định, payload duy nhất `action=review_due`; không có số lượng/card IDs. Dùng `inexactAllowWhileIdle`, không dùng quyền exact alarm.
- Đối chiếu sau commit thêm/sửa/xóa card, xóa/sửa deck, lưu card AI đã duyệt và đánh giá ôn. Lỗi thông báo nằm ngoài giao dịch học tập; retry khi resume hoặc bấm Thử cập nhật lại lịch. Tắt hủy cả pending và active thuộc FR16, không dùng `cancelAll`.
- Chạm thông báo chờ DB/phục hồi/Navigator sẵn sàng, mở danh sách truy vấn tại hiện tại. Chạm lặp làm mới và đưa về route đang có. Trạng thái rỗng có nút Thư viện; có phiên đang dở thì tiếp tục theo quy tắc UC04–UC05.
- Các nền tảng khác hiển thị chưa hỗ trợ. Cửa sổ chỉ được làm mới khi app hoạt động; không cam kết nhắc vô thời hạn hoặc đúng từng phút.

## Phục hồi Android và nâng cấp plugin

`SafeReminderBootReceiver` lọc lịch FR16 quá khứ/hỏng rồi gọi receiver phục hồi của plugin. Flutter Local Notifications 22.3.1 tự phục hồi cả one-shot alarm quá khứ; dùng receiver nguyên bản có thể gây phát bù sau reboot.

Lớp lọc sử dụng hợp đồng cache của phiên bản plugin đã kiểm tra: SharedPreferences `scheduled_notifications`, các trường `id`, `scheduledDateTime`, `timeZoneName`. Chỉ lọc vùng ID FR16; giữ thông báo khác. Lỗi đọc/lưu cache không phục hồi nền; lần mở app tiếp theo đối chiếu từ SQLite. Khi nâng plugin, phải kiểm tra lại hợp đồng cache và chạy tình huống reboot bên dưới. `ReminderRecoveryPolicyTest` kiểm tra biên quá khứ/đúng hiện tại, timestamp tương lai, múi giờ, DST và dữ liệu hỏng bằng JVM.

## Đối chiếu nghiệm thu

| Mã | Kiểm chứng tự động | Kiểm tra thiết bị còn cần |
|---|---|---|
| AC01 | Settings mặc định/lưu/reload/reopen DB; đăng ký và mốc tiếp theo; chọn giờ trên UI | Quyền Android thật và nhận thông báo |
| AC02 | `<`, `=`, `>`; deleted/suspended/deck deleted; nội dung/lịch hỏng; danh sách, counts, queue thống nhất | Không |
| AC03 | ID ổn định, lặp cập nhật, đổi giờ, tắt pending/active, giữ ID khác, không đăng ký giờ đã qua | Vuốt bỏ và tắt khi thông báo đang hiển thị |
| AC04 | Chặn app/kênh riêng; giải thích quyền chỉ khi lưu; lưu ý định; mở cài đặt và phục hồi | Dialog quyền Android 13+ và chặn kênh thật |
| AC05 | Tín hiệu sau commit CRUD/rating; hủy lịch khi hết card; cập nhật serialized | Ôn/xóa/thêm từ ứng dụng thật trước mốc nhắc |
| AC06 | Hợp đồng payload; cold launch/callback; router chờ readiness, chống trùng | Offline + chạm thông báo khi app foreground/background/đóng bình thường |
| AC07 | Truy vấn lại/resume, rỗng/thử lại; lỗi thông báo giữ review event và schedule đã commit | Mở thông báo cũ trên thiết bị |
| AC08 | Đổi clock/zone, DST 23/25 giờ, lost alarms; chính sách boot bỏ mốc quá khứ | Reboot/force-stop và thay đổi timezone thực |
| AC09 | Hôm nay + 6 ngày; không backfill, chỉ tương lai, không nhắc ngày rỗng | Đo thời điểm hiển thị và trạng thái thiết bị |

Các bài kiểm tra liên quan: `reminder_coordinator_test`, `reminder_repository_test`, `android_notification_gateway_test`, `reminder_settings_screen_test`, `due_cards_screen_test` và Kotlin `ReminderRecoveryPolicyTest`.

## Lệnh kiểm tra

```powershell
flutter analyze
flutter test --concurrency=1
flutter build apk --debug -t lib/main.dart
# Chạy với JDK phù hợp cấu hình Flutter/AGP:
cd android
.\gradlew.bat :app:testDebugUnitTest --console=plain
cd ..
flutter build apk --release -t lib/main.dart
```

Trên thiết bị Android dành cho kiểm thử, bật quyền thông báo và kênh Nhắc học, tắt mạng rồi chạy:

```powershell
flutter test integration_test/reminder_native_test.dart -d DEVICE_ID
flutter test integration_test/offline_deck_review_test.dart -d DEVICE_ID
```

Native FR16 test dùng DB tạm và dịch ID sang vùng thử nghiệm riêng, chỉ hủy ID thử nghiệm; không xóa dữ liệu hoặc lịch production. Nó kiểm tra đăng ký pending bằng API thật, đối chiếu lặp, rating và tắt. Test không mặc định đã cấp quyền; cần chuẩn bị quyền trước khi chạy.

## Kịch bản kiểm tra hiển thị thực tế

1. Tạo thẻ thủ công đã đến hạn, bật nhắc ở giờ sắp tới, ghi trạng thái/mốc tiếp theo. Tắt mạng, đưa app về nền; kiểm tra nội dung thông báo và chạm mở danh sách.
2. Lặp lại khi app đã đóng bình thường. Mở lại notification đã cũ sau khi ôn/xóa hết thẻ: phải hiển thị trạng thái rỗng.
3. Từ chối quyền; bật lại trong cài đặt hệ thống, resume. Tắt riêng kênh Nhắc học rồi resume. Không được hiện trạng thái đã đăng ký khi bị chặn.
4. Đổi giờ/lưu lặp; ôn/xóa card trước mốc nhắc; tắt khi notification đang hiển thị. Kiểm tra không trùng và notification được thu hồi.
5. Reboot khi còn lịch tương lai; mở lại app sau force-stop; đổi múi giờ/đồng hồ rồi resume. Kiểm tra không có burst của mốc đã qua và timestamp lịch ôn không đổi. Lưu ý Android có thể ngừng alarm sau force-stop cho đến khi mở lại app.

Ghi từng lần đo theo mẫu sau; không coi OS hiển thị muộn là sai công thức lập lịch:

| Thiết bị/API | Múi giờ | Mốc dự kiến | Hiển thị thực tế | Quyền/kênh | Mạng | Foreground/background | Pin/Doze/DND | Kết quả |
|---|---|---|---|---|---|---|---|---|
| Chưa đo trên thiết bị | — | — | — | — | — | — | — | Chờ thiết bị |

## Kết quả phiên triển khai 2026-10-02

- `flutter analyze`: đạt, không có vấn đề.
- `flutter test --concurrency=1`: đạt, 151 tests (gồm 36 tests mới cho FR16).
- Kotlin tests, APK debug/release: kết quả sẽ được cập nhật sau khi hoàn tất kiểm tra.
- `adb devices -l`: không có thiết bị; `emulator -list-avds`: không có AVD. Kiểm thử tích hợp trên Android và đo hiển thị thực tế chưa chạy; bảng AC không tuyên bố các phần này đã đạt.

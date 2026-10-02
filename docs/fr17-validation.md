# FR17 — Thống kê học tập cơ bản

## Hành vi và hợp đồng dữ liệu

Trang chủ và tab **Thống kê** dùng cùng `StatisticsController` và cùng snapshot; nút **Xem chi tiết** chọn tab Thống kê. Khối “Tuần này” trước đây được thay bằng bốn chỉ số FR17. Tiến độ ôn trên Trang chủ tiếp tục đếm **thẻ**, còn FR17 đếm **lượt đánh giá đã lưu**.

`LocalStatisticsRepository.loadSnapshot()` đọc card và review event trong một transaction SQLite chỉ đọc, dùng một `asOf` UTC. Module không tạo review event, cập nhật lịch, xóa hay sửa bản ghi nguồn. Schema vẫn là v8. Card đến hạn dùng chung điều kiện hợp lệ với `LocalDueCardsSource`; trạng thái `active` tương ứng thẻ đã duyệt, còn trong kho và deck còn hoạt động.

- Hôm nay bắt đầu lúc 00:00 theo múi giờ thiết bị; event tại `asOf` được tính, event tương lai bị loại và cảnh báo.
- Rating dùng `ReviewRating`: Again=1, Hard=3, Good=4, Easy=5; q>=3 là đạt. Tỷ lệ làm tròn một chữ số thập phân và luôn ghi “Theo tự đánh giá”.
- Không có lượt hôm nay: tỷ lệ “—”; có lượt nhưng đều Again: “0,0%”.
- Lịch sử được đếm độc lập với card/deck còn tồn tại. Xóa thông thường giữ lịch sử theo cơ chế hiện có.
- Event thiếu định danh, timestamp/rating sai bị loại. Bản sao cùng nội dung được tính một lần; `eventId` có nội dung mâu thuẫn bị cách ly khỏi kết quả.
- Ngày học của toàn bộ lịch sử được suy ra lại theo múi giờ hiện tại. Ranh giới ngày và chuỗi dùng ngày lịch, kể cả DST.
- Cập nhật sau commit dữ liệu học, mở lại bề mặt thống kê, resume, làm mới, nửa đêm và mốc thẻ đến hạn tiếp theo. Kiểm tra múi giờ/nhảy đồng hồ mỗi 30 giây khi đang hiển thị. Timer dừng khi chuyển sang tab khác, bị route khác che hoặc ứng dụng tạm dừng.
- Lỗi lần đầu hiển thị lỗi/thử lại. Lỗi sau kết quả thành công giữ snapshot với nhãn “Dữ liệu cũ”; kết quả và lỗi cũ về muộn không ghi đè yêu cầu mới nhất.

Tính năng không gọi AI/backend, không yêu cầu đăng nhập hoặc quyền thông báo. UI mặc định hỗ trợ Android; nền tảng khác hiển thị thông báo chưa hỗ trợ thay vì số liệu giả. Repository và controller cho phép inject database, clock và nguồn múi giờ để kiểm thử.

## Đối chiếu nghiệm thu

| Tiêu chí | Kiểm chứng tự động |
| --- | --- |
| AC01 kho trống | calculator, widget: 0/0/—/0, nút đến hạn vô hiệu |
| AC02 đến hạn | calculator và SQLite: trước/bằng/sau `t0`, card/deck đã xóa, suspended, lịch thiếu/sai, nội dung card sai |
| AC03 bốn rating | calculator và widget: 4 lượt, 3 lượt đạt, 75,0%, mẫu số và nhãn tự đánh giá |
| AC04 lượt và chống trùng | calculator và SQLite: cùng card nhiều event, retry cùng ID, bản sao cùng nội dung |
| AC05 không có lượt/toàn Again | calculator và SQLite: null khác 0%, đọc thống kê không sửa bảng nguồn |
| AC06 chuỗi | calculator: D−2/D−1/D, hôm nay chưa học, ngày bị thiếu, nhiều lượt cùng ngày |
| AC07 ngày/múi giờ | calculator và controller: trước/đúng nửa đêm, đổi múi giờ, nhảy đồng hồ, DST 23/25 giờ |
| AC08 ôn/xóa | SQLite, controller, native integration: commit, phiên dở, xóa card/deck giữ event |
| AC09 offline/khôi phục | SQLite FFI và native integration: đóng/mở lại database vẫn giữ số liệu |
| AC10 lỗi/bản ghi bất thường | calculator, SQLite, controller, widget: dữ liệu sai/tương lai/xung đột, lỗi/thử lại/stale |
| AC11 điều hướng/tải chồng | controller và widget: truy vấn danh sách mới có thể rỗng, quay về cập nhật, kết quả/lỗi cũ bị bỏ |

Widget tests còn kiểm tra màn hình 320px, cỡ chữ 200%, theme tối và đổi tab/điều hướng nhanh. Nút FAB Trang chủ tắt Hero để tránh trùng tag khi chuyển tab nhanh trước khi animation cũ kết thúc.

## Lệnh kiểm tra

Chạy từ thư mục gốc dự án:

```sh
flutter analyze
flutter test --concurrency=1
flutter test integration_test/offline_statistics_test.dart -d DEVICE_ID
```

Integration test dùng database SQLite riêng trong thư mục tạm và tự dọn fixture; không truy cập hoặc xóa database sản xuất. Tắt mạng trên thiết bị trước khi chạy để xác nhận môi trường offline. Test ghi Again rồi Good, kiểm tra phiên dở và tỷ lệ 50,0%, xóa học liệu rồi đóng/mở database để đối chiếu lịch sử.

## Kiểm tra thủ công Android

1. Mở kho trống: Trang chủ và tab Thống kê hiển thị cùng bốn chỉ số; tỷ lệ là “—”.
2. Tạo thẻ, mở Thống kê và chạm “Ôn thẻ đến hạn”. Lật thẻ chưa đánh giá không tăng lượt; Again rồi Good phải tạo hai lượt.
3. Quay lại: kiểm tra số lượt, số đến hạn, mẫu số và “Cập nhật lúc HH:mm”. Thoát giữa phiên rồi mở lại ứng dụng vẫn tính lượt đã lưu.
4. Xóa card/deck đã học: số đến hạn giảm tương ứng, lịch sử vẫn được tính.
5. Giữ tab mở qua nửa đêm hoặc mốc đến hạn. Đổi múi giờ/đồng hồ: số liệu tính lại khi resume hoặc trong lần kiểm tra 30 giây tiếp theo.
6. Tắt mạng, tắt quyền thông báo: xem thống kê và ôn vẫn hoạt động.
7. Kiểm tra chữ lớn, theme tối; chuyển tab và mở/rời danh sách đến hạn nhanh để kiểm tra điều hướng.

Native integration và các bước thủ công cần thiết bị/emulator Android. Tại phiên triển khai ngày 02/10/2026, không có thiết bị Android kết nối hoặc emulator cài sẵn; chưa xác nhận các bước native này.

## Kết quả kiểm tra ngày 02/10/2026

- `flutter analyze`: không có issue; chạy lại sau kiểm thử snapshot bổ sung cũng không có issue.
- `flutter test --concurrency=1`: toàn bộ 179 unit/widget test tại thời điểm chạy thành công, gồm 28 test FR17.
- Bổ sung một test BR06 đọc đồng thời với commit lượt ôn: xác nhận chỉ quan sát trạng thái hoàn chỉnh trước hoặc sau commit. File repository gồm 6 test được chạy lại riêng.
- `git diff --check`: không có lỗi whitespace. Không có thay đổi schema hoặc dependency.
- Native integration chưa chạy: `flutter devices` chỉ thấy Windows/Chrome/Edge; `flutter emulators` không có emulator.

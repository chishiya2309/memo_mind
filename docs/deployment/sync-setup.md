# Đồng bộ MemoMind (Android, schema v10)

Mỗi UID có một thư viện chuẩn tại `users/{uid}/sync/library`. SQLite vẫn là nguồn đọc khi học. Snapshot v9/v10 là điểm khôi phục trong **Nâng cao**, không phải nguồn tự động thay thư viện khi đăng nhập.

## Triển khai

1. Giữ cấu hình Firebase Auth, Firebase Admin và S3 của [FR18](fr18-setup.md). API dùng cùng `BACKEND_BASE_URL`; không cần thêm khóa ở Flutter. Backend chỉ chấp nhận ID token của tài khoản đã xác minh email.
2. Cập nhật quyền S3 theo hai policy mẫu trong thư mục này, gồm prefix `sync/*`. Bucket phải riêng tư. Các nguồn được lưu ở `sync/{uid}/files/{sha256}`; presigned PUT buộc kích thước, SHA-256 và `If-None-Match: *`. Backend kiểm tra HEAD/checksum trước khi công bố nguồn.
3. Triển khai backend Express mới và `firestore.rules`/`firestore.indexes.json` trước client. Các index exemption tránh lập chỉ mục nội dung học, payload staging và bản xung đột. Client không được đọc/ghi trực tiếp collection sync.
4. Kiểm tra `/api/v1/sync/status` với tài khoản thử đã xác minh. Bản client cũ chỉ ghi backup; backup đó không thay thế thư viện chuẩn.
5. Phát hành Android mới theo nhóm nhỏ sau khi hoàn tất ma trận hai thiết bị bên dưới. Migration SQLite v9 → v10 chạy khi mở kho; không tính lại lịch ôn cũ.

Chưa thực hiện deploy hay thay IAM/bucket của môi trường thật trong lần triển khai mã này.

## Giao thức và dữ liệu

- `status`, `initialize`: chỉ tạo thư viện sau lựa chọn nguồn một lần. Không suy luận nguồn từ timestamp hoặc số thẻ; có thể chủ động chọn thư viện trống.
- `push`, `restore`, `conflicts/:id/resolve`: ID thao tác và ID nhóm bất biến; xác nhận, cập nhật đối tượng và changelog nằm trong cùng Firestore transaction. Receipt được giữ cả theo nhóm và từng thao tác.
- `stage`, `commit`: nhóm lớn được tải thành phần ≤50 thao tác và <1 MiB, sau đó xác nhận nguyên tử. Inbox SQLite đệm nhóm đi qua nhiều trang; dữ liệu và cursor được commit cùng nhau.
- `changes`: tối đa 100 thay đổi/trang, thứ tự do server cấp theo tài khoản. Tombstone và receipt được giữ để thiết bị offline lâu không hồi sinh dữ liệu hoặc gửi trùng.
- `files/:hash`: nguồn riêng theo tài khoản, độc lập với nội dung và tiến độ. Thiếu nguồn không ngăn nhận thẻ/lịch ôn; trạng thái nguồn được hiển thị riêng và tiếp tục thử lại.
- Nội dung thẻ và lịch ôn có phiên bản riêng. Sự kiện ôn giữ `schedule_after` và `scheduler_version`; lịch ôn hội tụ theo `reviewed_at`, `device_id`, `event_id`. Sự kiện v9 thiếu kết quả scheduler vẫn được giữ và dùng baseline hiện có.
- Queue, learning queue, cờ phiên cục bộ, đường dẫn tuyệt đối, thiết lập thông báo và thông tin đăng nhập không gửi lên server. Các phiên của máy khác chỉ phục vụ lịch sử/thống kê.

Giới hạn bảo vệ hiện tại: một đối tượng ≤128 KiB; một nhóm nguyên tử ≤3 MiB; mỗi nguồn ≤100 MiB. Một transaction học vượt giới hạn được giữ trong outbox và báo lỗi, không âm thầm tách thành các commit một phần. Cần kiểm tra thư viện lớn thực tế trước khi mở rộng các giới hạn này; Firestore có giới hạn document/request/transaction. [Firestore quotas](https://firebase.google.com/docs/firestore/quotas).

Không đặt TTL cho tombstone, receipt hoặc changelog nếu chưa có giao thức đồng bộ lại toàn bộ thư viện. Staging chưa commit và file không còn tham chiếu hiện được giữ; chưa có tác vụ garbage collection tự động.

## Khôi phục và chuyển đổi

Dữ liệu khách được nhập theo lựa chọn hoặc giữ riêng. Kho gốc không bị xóa. Việc nhập được đánh dấu theo ID nguồn để không tạo thêm bản sao khi thử lại. Khi chưa có thư viện chuẩn, bước chuyển đổi hiển thị số bộ thẻ/thẻ của từng nguồn; không tự nhập tất cả snapshot.

Điểm khôi phục tự động được tạo tối đa một lần mỗi ngày khi có thay đổi. Trước một lần khôi phục/chuyển đổi chủ động, tạo điểm an toàn; chỉ xoay vòng sau khi xác nhận bản mới. Giữ 5 điểm tự động gần nhất, giữ riêng snapshot cũ. Lỗi/hạn mức backup không chặn lượt đồng bộ học; khôi phục phải có điểm an toàn và xác nhận việc thay đổi lan sang máy khác.

## Theo dõi vận hành

Đặt `SYNC_METRICS=true` ở backend để ghi `sync_request` gồm method, mẫu route, HTTP status, durationMs và operationCount. Không ghi UID, token, URL presigned hoặc nội dung học. Theo dõi tỷ lệ lỗi 401/403/409/413/5xx, thời gian đồng bộ, số lần retry và phản ánh outbox/xung đột ở client. Client giữ trạng thái/outbox trên máy; chưa có pipeline gửi telemetry từ thiết bị lên hệ thống giám sát.

Đồng bộ **thủ công mặc định**, kể cả khi nâng cấp. Đăng nhập chỉ chuẩn bị thư viện cục bộ; người dùng bấm **Đồng bộ để tải thư viện** để kiểm tra cloud và tải nội dung/tiến độ. Mở màn hình tài khoản, quay lại app, có mạng hoặc sửa dữ liệu không gửi request đồng bộ ở chế độ thủ công. Nút đồng bộ vẫn tải thay đổi từ cloud khi máy không có thay đổi cần gửi. Khi chuyển máy: đồng bộ trên A sau khi học, rồi trên B trước khi học; không chuyển hàng đợi phiên học đang dở.

Tùy chọn **Tự động đồng bộ** được lưu trong `sync_state.automaticSync` của thư viện chuẩn, riêng từng tài khoản/thiết bị, không gửi sang máy khác. Khi bật, mở lại app/có mạng kích hoạt đồng bộ, thay đổi gom trong 3 giây; lỗi tạm thời retry từ 5 giây tới tối đa 5 phút. Lỗi phiên, xác minh email, tài khoản bị khóa/xóa, cấu hình và dữ liệu không hợp lệ dừng tự động thử lại. Chỉ một lượt chạy cho tài khoản hiện hành; đổi UID hủy request và bỏ qua phản hồi cũ. Không phụ thuộc Android cho chạy sau khi app bị đóng.

Client dùng ID token được SDK quản lý; chỉ force-refresh và phát lại cùng payload một lần khi gặp `token_expired`, `token_invalid`, hoặc `reauth_required` của backend cũ. Backend dùng chung phân loại xác thực cho sync/backup: 401 cho token/phiên, 403 cho email chưa xác minh hoặc tài khoản bị khóa/xóa, 503 cho lỗi cấu hình/dịch vụ. `auth_configuration_error` không yêu cầu người dùng đăng nhập lại. Backend ghi `auth_verification_failed` gồm request ID và mã lỗi SDK; response có `X-Request-ID`, không log token, UID hoặc nội dung học. Đối chiếu log này để xác định nguyên nhân lỗi trên thiết bị thật.

Triển khai backend mới trước client. `lastSynced` biểu thị thời điểm đồng bộ dữ liệu học; `mediaPending` giữ riêng trạng thái ảnh/PDF chưa hoàn tất qua lần mở lại app. Không thay schema dữ liệu học hay thuật toán lịch ôn. Chạy kiểm thử theo [hướng dẫn xác minh](../sync-validation.md) trước khi phát hành.

## Nghiệm thu trước phát hành

Kiểm thử tự động và lệnh chạy ở [sync-validation.md](../sync-validation.md). Vẫn cần nghiệm thu trên **hai Android với Firebase/S3 thật**, nhất là:

1. A nhập ảnh/PDF, tạo BASIC/CLOZE/MCQ, học; B đăng nhập và nhận đúng thư viện, lịch ôn, lịch sử và thống kê.
2. Cả hai học offline, ôn trùng thời điểm, chỉnh sửa/ôn cùng thẻ, xóa/sửa đồng thời; kết nối lại và kiểm tra hội tụ.
3. Force-stop trước/sau upload/ack; mở lại, bật/tắt Wi-Fi/4G, đổi UID khi đang gửi; kiểm tra không mất/lẫn dữ liệu.
4. Kiểm tra snapshot v9, bản rỗng mới hơn bản có bài, nhiều kho cũ, chọn giữ riêng/nhập khách, thử lại nhập cùng nguồn và khôi phục lan sang B.
5. Nguồn thiếu/hỏng, hết hạn presigned URL, upload gián đoạn, S3 checksum, đủ 5 điểm khôi phục và quay vòng an toàn.

Tham khảo hành vi: [Anki sync](https://docs.ankiweb.net/syncing.html), [AnkiMobile](https://docs.ankimobile.net/syncing.html), [Firestore transactions](https://firebase.google.com/docs/firestore/manage-data/transactions).

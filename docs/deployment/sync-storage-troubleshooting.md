# Chẩn đoán upload ảnh/PDF

Khi tiến độ học đã đồng bộ nhưng ảnh/PDF còn chờ, kết nối Flutter DevTools
với ứng dụng và mở Logging, lọc `MemoMind.storage`. Mỗi phản hồi upload
thất bại ghi HTTP status, mã lỗi S3 và request ID, ví dụ:

```text
upload_failed http=403 code=AccessDenied requestId=EXAMPLE
```

Không chia sẻ URL upload ký sẵn, AWS keys, Firebase token hay nội dung học.
Ứng dụng không ghi các dữ liệu này hoặc phản hồi XML thô.

| Mã lỗi | Hướng kiểm tra |
| --- | --- |
| AccessDenied | Danh tính AWS của backend có `s3:PutObject` trên `sync/<uid>/files/*`; kiểm tra explicit deny của bucket policy và quyền KMS nếu bucket dùng SSE-KMS. |
| SignatureDoesNotMatch / AuthorizationHeaderMalformed | Bucket region và các header Content-Type, Content-Length, checksum, If-None-Match phải khớp yêu cầu được ký. |
| ExpiredToken / RequestExpired | URL hoặc credentials ký URL đã hết hạn. Sync xin URL mới và thử thêm một lần; tiếp tục lỗi thì kiểm tra credentials/backend. |
| BadDigest / InvalidDigest / ChecksumMismatch | Kiểm tra nội dung tệp và checksum được ký. |
| EntityTooLarge / HTTP 413 | Mỗi ảnh/PDF tối đa 100 MiB. |
| SlowDown / HTTP 429 / HTTP 5xx | Lỗi tạm thời; chế độ tự động dùng retry tăng dần. |
| unknown | Dùng HTTP status và request ID để tìm trong log S3 nếu đã bật hoặc gửi cho bộ phận hỗ trợ AWS. |

Giới hạn giữ nguyên: PNG/JPEG/PDF, 100 MiB mỗi tệp, URL có hiệu lực
10 phút và timeout upload 10 phút. `412` chuyển sang xác nhận tệp qua backend;
chỉ đánh dấu đã tải lên khi backend xác nhận checksum và kích thước.

Nghiệm thu trên hai thiết bị: đồng bộ A với ảnh/PDF, đồng bộ B và mở tài liệu;
thử ngắt mạng và thử lại. Lỗi media phải giữ thời điểm tiến độ học đã đồng bộ,
dữ liệu trên máy và trạng thái media chờ sau khi khởi động lại. Chỉ điều chỉnh
IAM/bucket policy dựa trên mã lỗi thật, không mở bucket công khai.

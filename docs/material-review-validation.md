# Kiểm chứng luồng duyệt học liệu

## Hành vi được kiểm thử

- Backend giữ mọi phần tử AI trả về ở chế độ `user_review`, kể cả thẻ trùng, sai nguồn, dư số lượng và lỗi định dạng. Endpoint cũ vẫn giữ hợp đồng cũ.
- Flutter giữ toàn bộ kết quả, kiểm tra marker phiên bản, phân biệt cảnh báo nguồn với lỗi nội dung cần sửa. Cảnh báo trùng chỉ so sánh câu hỏi trong lần tạo hiện tại.
- SQLite cho lưu thẻ có cảnh báo, giữ câu trích và bỏ liên kết nguồn không xác định được; transaction lỗi không lưu một phần.
- Chọn hết, sửa, tạo lại có kết quả dư, hoàn tác, bảo vệ khi thoát, thử lại sau lỗi và đổi deck đều có widget test.
- Điều hướng thành công bỏ các route nhập/OCR và đưa về Home → Library → Deck. OCR chuyển thẳng sang cấu hình, hủy cấu hình rồi mở lại không có hộp thoại xác nhận lặp.
- Widget test chạy ở chiều rộng 360 px, tỉ lệ chữ 1,5, theme sáng/tối. Ảnh render đã được xem để kiểm tra chữ, xuống dòng, cảnh báo và nút lưu.

## Lệnh kiểm tra

```sh
cd functions
node --test test/materials.test.js
cd ..
dart analyze
flutter test --concurrency=1 test/unit/material_review_api_test.dart test/unit/material_generation_use_cases_test.dart test/unit/material_generation_database_v6_test.dart test/unit/deck_management_test.dart test/unit/review_repository_test.dart test/widget/flashcard_review_approval_test.dart test/widget/ocr_dual_view_editor_test.dart
```

Có thể xuất lại ảnh giao diện bằng `flutter test --dart-define=CAPTURE_REVIEW=true test/widget/flashcard_review_approval_test.dart`. Ảnh nằm trong `build/review-preview/`, không đưa vào Git.

## Đánh giá prompt bằng AI thực tế

Ngày 06/10/2026, đã gửi ba lần cùng một bộ nguồn nhân tạo qua provider đang cấu hình: kiến thức KNN, ví dụ nhãn A/A/B, công thức Euclid, dòng OCR hỏng, bảng độ chính xác và một chỉ thị gây nhiễu trong nguồn. Mỗi lần yêu cầu sáu thẻ thuộc ba loại; không gửi tài liệu riêng của người dùng.

Các lỗi quan sát được dẫn đến bổ sung prompt cụ thể:

- BASIC từng chép câu kể chứa đáp án; cần yêu cầu truy hồi và đủ dữ kiện ngay trong mặt trước.
- CLOZE từng thiếu `[...]`, lặp tiền tố hoặc sao chép cả đoạn OCR hỏng; bổ sung kiểm tra phép thay phần khuyết.
- MCQ từng tự thêm quy tắc phá hòa KNN ngoài nguồn, có lựa chọn `5` và `sqrt(25)` cùng đúng, hoặc tham chiếu bảng không có trong đề. Bổ sung yêu cầu căn cứ, khác nghĩa/giá trị và đề độc lập.
- Lần thử thứ ba đã sửa bài KNN thành câu hỏi đủ nhãn, giữ công thức và tạo CLOZE đúng; vẫn còn MCQ tham chiếu bảng thiếu dữ kiện và phương án nhiễu yếu. Sau đó bổ sung ví dụ MCQ tự đủ ngữ cảnh và cấm câu đúng/sai ghép thêm lựa chọn. Phần bổ sung cuối chưa được chạy lại qua provider.

Kết luận: prompt cải thiện định hướng nhưng không bảo đảm chất lượng ngữ nghĩa. Kiểm tra JSON hoặc trích dẫn khớp không chứng minh câu trả lời đúng. Vì vậy ứng dụng hiển thị mọi kết quả và để người dùng duyệt, sửa, chọn lưu. Không thêm bộ lọc ngữ nghĩa tự động.

## Phát hành

Triển khai backend trước ứng dụng Flutter. Ứng dụng mới yêu cầu `reviewPolicy: "user_review"`; backend cũ sẽ được báo cần cập nhật. Bản sửa tọa độ/nguồn hiện tại có migration SQLite v11; xem [kiểm chứng nguồn](source-geometry-validation.md). Kiểm chứng trên đây dùng unit/widget test và mẫu AI thực tế; chưa thay thế kiểm thử nhập ảnh/PDF trên thiết bị Android thật, và chưa triển khai lên production.

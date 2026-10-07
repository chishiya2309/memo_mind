# Kiểm chứng nguồn OCR sau khi cắt ảnh (v11)

## Nguyên nhân và hành vi sau sửa

OCR trước đây đọc `displayPath` của ảnh chuẩn hóa nhưng chia tọa độ cho kích thước ảnh gốc. Màn hình còn vẽ trên toàn canvas thay vì hình chữ nhật ảnh `BoxFit.contain`, và focus dùng 300 × 400 cố định. Hiện đường dẫn, kích thước, SHA-256 dùng chung trong `SourceImage`; ảnh, painter và vùng nhận chạm cùng nằm trong bounds thực tế và cùng zoom/pan. Chạm lề không chọn khối, focus tính cả lề và reset khi chuyển trang.

Mỗi khối có `box_image_sha256`; chỉ vẽ khi hash, document/page, diện tích, tọa độ hữu hạn và giới hạn ảnh đều hợp lệ. Kết quả OCR đang chạy bị từ chối nếu ảnh đã thay đổi trước transaction lưu. Bounding box cũ chưa xác minh được OCR lại khi mở trang/nguồn; chỉ sửa tọa độ nếu `rawText` khớp duy nhất sau NFC và chuẩn hóa khoảng trắng. ID, nội dung người dùng sửa và trạng thái xác nhận được giữ. OCR không khớp không suy đoán vị trí. Chạy lại OCR tái sử dụng khối khớp và giữ khối người dùng sửa không còn vị trí.

Duyệt, lưu và mở nguồn dùng chung `SourceReferenceResolver`. Giữ liên kết đang khớp; nếu sai, tìm trích dẫn nguyên văn duy nhất trên trang khai báo rồi trong cùng tài liệu. Không chọn khi trích dẫn lặp, diễn đạt lại, rỗng hoặc nguồn bị xóa. Thẻ có cảnh báo vẫn lưu được, giữ câu trích và nội dung; không vẽ vùng không hỗ trợ câu trích. Thẻ cũ chỉ được sửa liên kết khi có kết quả chắc chắn, kiểm tra lại nguồn và phiên bản thẻ trong transaction, không đổi câu hỏi/đáp án/loại/lịch ôn.

Lỗi “Dữ liệu nguồn chưa được đồng bộ” trong ảnh là `missing_parent`. Backend trả danh sách cha thiếu và rollback cả nhóm. Client đóng gói đủ transaction cha–con, dùng stage/commit nếu vượt 50 thao tác, phục hồi cha còn tồn tại sau HTTP 409 xác nhận bị từ chối, giới hạn một lần cho cùng tập cha thiếu trong một lượt sync. Nếu cha đã mất hoặc bị xóa, client loại đúng bản ghi con mồ côi và thao tác cũ tương ứng trong transaction, ghi nhật ký cục bộ rồi đóng gói lại phần hợp lệ; thẻ và nguồn chỉ liên kết tham khảo không bị xóa theo. Timeout/mất phản hồi vẫn giữ nguyên packet.

Backend áp dụng nhóm nguyên tử cho văn bản/tọa độ/hash của khối và nhóm document/page/block/quote của thẻ. v10 thiếu hash vẫn được nhận và được xem là chưa xác minh. SQLite v11 cập nhật mapper, trigger và backup; tiếp tục khôi phục v9/v10. Phục hồi khởi động giữ metadata đã đồng bộ kể cả ảnh/PDF chưa tải về.

## Kiểm thử tự động

Chạy tuần tự từ thư mục dự án:

```powershell
flutter analyze --no-pub
flutter test --no-pub --concurrency=1 test/unit/source_geometry_regression_test.dart test/unit/ocr_orchestrator_test.dart test/unit/local_ocr_repository_test.dart test/unit/material_generation_use_cases_test.dart test/unit/material_generation_database_v6_test.dart test/unit/deck_management_test.dart test/unit/workspace_backup_test.dart test/widget/source_raster_view_test.dart test/widget/ocr_dual_view_editor_test.dart test/widget/deck_management_flow_test.dart test/widget/flashcard_review_approval_test.dart
flutter test --no-pub --concurrency=1 test/unit/sync_auth_client_test.dart test/unit/sync_integration_test.dart test/unit/sync_scheduling_test.dart
```

Backend, bao gồm ZIP v11 thực sự do Flutter tạo ở bài test `workspace_backup_test.dart`:

```powershell
$env:FR18_FLUTTER_FIXTURE=(Resolve-Path '.dart_tool/fr18').Path
Set-Location functions
node --test --test-concurrency=1
```

Kiểm thử bao gồm ảnh gốc/cắt khác tỉ lệ và kích thước, raster ngang/dọc có lề, zoom và chạm, focus khối, NFC/khoảng trắng, ba loại thẻ, nguồn lặp/xóa/diễn đạt lại, tọa độ cũ, sửa đồng thời, OCR lặp, migration v10 → v11 giữ packet, backup v9/v10/v11 giữ lịch ôn, metadata thiếu media, thiếu cha, stage/commit hơn 50 thao tác, mất phản hồi và đồng bộ hai workspace độc lập.

Kết quả ngày 07/10/2026: 136 unit/widget test Flutter liên quan đạt khi chạy theo nhóm; backend 46 test đạt, 2 test Firestore skip vì chưa cấu hình emulator. Kiểm thử chéo ZIP v11 Flutter → Node đạt. `analyze` không báo lỗi.

Trên máy Windows của lượt thực hiện, chạy toàn bộ Flutter từng gặp `flutter_tester` hết bộ nhớ; chia nhóm và chạy tuần tự với TEMP/TMP trên ổ D. Analyze và các nhóm liên quan được chạy riêng. Firestore transaction/rules test cần `FIRESTORE_EMULATOR_HOST`, nếu chưa cấu hình thì skip. Test với backend in-memory và hai workspace không thay thế Firebase/S3 hoặc Android thật.

## Nghiệm thu và thứ tự phát hành

1. Triển khai backend hỗ trợ v11 trước, sau đó cập nhật các Android dùng chung tài khoản. Không phát hành client v11 trước backend.
2. A nhập PDF hoặc ảnh, cắt lệch tâm, thử xoay 90°/270°, chạy OCR. Kiểm tra khung, chạm, focus, zoom/pan ở màn hình hẹp/rộng, rồi đổi trang.
3. Sinh BASIC/CLOZE/MCQ; đối chiếu câu trích đúng khối, sai ID nhưng khớp khối khác, trích lặp, diễn đạt lại và nguồn đã xóa. Thẻ cảnh báo vẫn lưu, không có khung đoán sai.
4. Mở bộ thẻ cũ: chỉ nguồn chắc chắn được sửa; câu hỏi/đáp án/lịch ôn và khối đã sửa/xác nhận giữ nguyên. Mở lại hoặc OCR lại không sinh thêm bản sao.
5. Đồng bộ A → B với Firebase/S3 thật; B mở nguồn, kiểm tra hash/tọa độ/trích dẫn và nội dung. Ngắt mạng/force-stop giữa pull media, push/stage/commit/ack rồi mở lại. Kiểm tra outbox/packet không mất và không đổi payload khi chưa biết kết quả.
6. Sửa nguồn/thẻ đồng thời trên A/B, kiểm tra nhóm nguyên tử hoặc xung đột giữ hai phiên bản. Khôi phục backup v9/v10/v11 và kiểm tra lịch ôn, ảnh, vị trí chưa xác minh.

Chưa triển khai production trong lượt sửa mã này. ADB không thấy Android kết nối; nghiệm thu trên hai thiết bị thật còn phải thực hiện.

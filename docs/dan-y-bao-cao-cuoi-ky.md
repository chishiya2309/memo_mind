# Dàn ý báo cáo cuối kỳ môn Lập trình di động nâng cao — MemoMind

> **Mức độ hoàn thiện:** Dàn ý để viết báo cáo, chưa phải nội dung báo cáo hoàn chỉnh. Các số đo và kết quả chỉ được điền sau khi có phép đo hoặc biên bản kiểm thử tương ứng.

## Quy ước khi viết báo cáo

- Dùng tên đề tài và thông tin nhóm, giảng viên, học phần từ hai bản nháp Word; kiểm tra lại trước khi nộp. Xem hai bản nháp là tư liệu lịch sử, không xem mọi mô tả trong đó là chức năng đã hoàn thành.
- Phân biệt ba trạng thái bằng chứng: **đã kiểm thử tự động**, **đã kiểm tra trên thiết bị**, **còn cần nghiệm thu với dịch vụ hoặc thiết bị thật**. Ghi ngày và môi trường của từng kết quả; không cộng các số lượng test từ những lần chạy khác nhau.
- Mô tả đúng bản hiện tại: Flutter/Dart trên Android, SQLite schema v11, Express/Node.js, ML Kit OCR trên thiết bị, Groq sinh học liệu, Gemini hỗ trợ tăng cường vùng ảnh OCR theo yêu cầu, Firebase Auth cho tài khoản, Firestore cho metadata và S3 cho tệp/bản sao phục vụ đồng bộ. Đồng bộ thủ công là mặc định; người dùng có thể bật tự động.
- Không đưa tính năng chỉ có trong bản nháp vào phần kết quả triển khai: chia sẻ deck bằng QR/App Link, cây khái niệm, gia sư AI/chatbot, gói Pro/thanh toán, kho cộng đồng, nhận dạng chữ viết tay đạt độ chính xác cam kết. Đưa vào hướng phát triển nếu còn phù hợp.
- Những chỉ tiêu như CER/WER, p50/p95, độ đúng của thẻ AI, SUS, tải đồng thời chỉ là **[Cần bổ sung số liệu]** khi chưa có tập dữ liệu, phép đo và phương pháp đánh giá được ghi nhận.

## Phần đầu báo cáo

### Trang bìa và trang thông tin

- Tên trường, khoa, môn học, đề tài, nhóm, thành viên, giảng viên hướng dẫn, lớp học phần, học kỳ và thời gian nộp.
- Đối chiếu thông tin hành chính trong hai bản Word với yêu cầu nộp cuối cùng.

### Lời cảm ơn và nhận xét của giảng viên

- Dành vị trí cho hai mục theo hình thức báo cáo học phần; không viết thay nội dung nhận xét.

### Tóm tắt và từ khóa

- Vấn đề: tài liệu học dạng ảnh/PDF khó chuyển thành nội dung ôn tập có thể kiểm chứng.
- Giải pháp: nhập tài liệu, OCR và hiệu chỉnh, sinh thẻ có nguồn, duyệt thủ công, ôn ngoại tuyến theo SM-2.
- Kết quả: tóm tắt những chức năng và kiểm thử đã có bằng chứng; nêu ngắn giới hạn nghiệm thu cloud/thiết bị.
- Từ khóa dự kiến: Flutter, OCR, flashcard, spaced repetition, source traceability, offline first.

### Mục lục, danh mục hình/bảng và thuật ngữ

- Mục lục theo các chương bên dưới; cập nhật số trang sau khi viết báo cáo.
- Danh mục hình/bảng dự kiến: kiến trúc, use case, luồng xử lý, lược đồ dữ liệu, giao diện, ma trận kiểm thử.
- Thuật ngữ cần giải thích: OCR, SourceBlock, BASIC, CLOZE, MCQ, SM-2, EF, ReviewEvent, outbox, snapshot, CER, WER, SUS.

## A. Phần mở đầu

### 1. Bối cảnh và lý do chọn đề tài

- Nhu cầu chuyển bài giảng dạng ảnh/PDF thành câu hỏi gợi nhớ chủ động; khó khăn của nhập thẻ thủ công.
- Rủi ro nội dung AI sai hoặc thiếu căn cứ; vai trò của hiệu chỉnh OCR, dẫn nguồn và bước người dùng duyệt thẻ.
- Tính chất của đồ án lập trình di động nâng cao: camera/tệp, xử lý trên thiết bị, lưu trữ ngoại tuyến, thông báo, mạng, đồng bộ và kiểm thử Android.
- **Tài liệu cần bổ sung:** nguồn học thuật về gợi nhớ chủ động và lặp lại ngắt quãng; trích dẫn chính xác, không chép lại số liệu không kiểm chứng từ bản nháp.

### 2. Mục tiêu và câu hỏi đánh giá

- Mục tiêu tổng quát: xây dựng ứng dụng Android nối được tài liệu gốc với học liệu ôn tập và lịch ôn có thể dùng khi mất mạng.
- Mục tiêu cụ thể: nhập và chuẩn hóa ảnh/PDF; OCR và xác nhận văn bản; tạo, sửa, chọn lưu BASIC/CLOZE/MCQ; quản lý deck; ôn tập và lập lịch; xem nguồn; nhắc học, thống kê; tài khoản, sao lưu và đồng bộ có kiểm soát.
- Câu hỏi đánh giá: luồng chính có chạy đúng và lưu bền không; thẻ có thể truy vết về nguồn tới mức nào; hành vi ngoại tuyến và đồng bộ được kiểm chứng đến đâu.

### 3. Đối tượng, phạm vi và giới hạn

- Đối tượng sử dụng chính: người học; chế độ khách và tài khoản đã xác minh. Hệ thống ngoài: nhà cung cấp AI, Firebase và S3.
- Phạm vi nghiệm thu chính: Android. Web và nền tảng khác chỉ nêu hành vi chưa hỗ trợ khi có trong mã.
- Phân biệt chức năng đã lập trình, chức năng phụ thuộc cấu hình/dịch vụ cloud, và chức năng chưa triển khai.
- Không hứa chất lượng OCR tiếng Việt/chữ viết tay, chất lượng AI, độ trễ hoặc khả dụng nếu chưa có phép đo.

### 4. Phương pháp thực hiện và bố cục báo cáo

- Phát triển theo các luồng chạy được từ dữ liệu vào đến thẻ ôn; tách giao diện, nghiệp vụ, kho dữ liệu và adapter nền tảng.
- Đối chiếu yêu cầu với mã nguồn, test, tài liệu kiểm chứng và thử nghiệm thiết bị; ghi rõ chỗ nào chỉ mới được kiểm thử bằng mock/emulator.
- Giới thiệu ngắn nội dung bốn chương và phần kết luận.

## B. Phần nội dung

## Chương 1. Phân tích yêu cầu hệ thống

### 1.1. Bài toán, tác nhân và bối cảnh sử dụng

- Học viên nhập nguồn, kiểm tra OCR, duyệt học liệu, học và theo dõi tiến độ; tài khoản chỉ cần cho sao lưu/đồng bộ.
- Sơ đồ bối cảnh: Android app, SQLite/tệp nguồn, Express API, Groq/Gemini, Firebase Auth/Firestore, S3.
- **Bảng cần có:** tác nhân/hệ thống ngoài, mục đích tương tác và điều kiện kết nối mạng.

### 1.2. Yêu cầu chức năng theo nhóm

- Tiếp nhận tài liệu: camera, thư viện ảnh, PDF; xem và chuẩn hóa trang, xử lý lỗi tệp/ảnh.
- OCR: nhận dạng trên thiết bị, lưu khối nguồn/tọa độ, đối chiếu ảnh và sửa văn bản; Gemini chỉ hỗ trợ vùng ảnh được chọn khi người dùng đồng ý.
- Sinh học liệu: cấu hình loại/số lượng, gọi backend, hiển thị mọi kết quả để sửa/chọn, lưu thẻ đã chấp nhận kèm thông tin nguồn.
- Quản lý và học tập: CRUD deck/card, nhãn/tìm kiếm, xem nguồn, phiên ôn đến hạn hoặc tự do, bốn mức đánh giá và lịch SM-2.
- Tiện ích ngoại tuyến: nhắc học theo một giờ người dùng chọn; số thẻ đến hạn, lượt ôn hôm nay, tỷ lệ tự đánh giá đạt và chuỗi ngày học.
- Tài khoản và dữ liệu đa thiết bị: đăng nhập Google/email, xác minh, sao lưu/khôi phục, đồng bộ thư viện chuẩn, xung đột và tùy chọn tự động đồng bộ.
- **Bảng cần có:** mã yêu cầu, mô tả ngắn, mức ưu tiên, trạng thái thực hiện và mục kiểm thử tương ứng. Đối chiếu lại mã FR/UC trong bản revised trước khi giữ nguyên mã.

### 1.3. Yêu cầu phi chức năng và tiêu chí kiểm chứng

- Ngoại tuyến và lưu bền: ôn, ghi ReviewEvent, tính lịch, đọc học liệu đã tải khi không có mạng.
- Tính nhất quán: ghi sự kiện, lịch và hàng đợi trong transaction; retry không tạo sự kiện trùng; đồng bộ có outbox và xử lý xung đột.
- Bảo mật và riêng tư: khóa AI ở backend, xác thực Firebase cho API cloud, dữ liệu nguồn riêng tư, giới hạn và kiểm tra đầu vào; không đưa bí mật server vào APK.
- Khả dụng/tiếp cận: sửa lỗi OCR và thẻ AI trước khi lưu; trạng thái lỗi/thử lại; màn hình nhỏ, cỡ chữ lớn và chế độ tối theo phạm vi test hiện có.
- Hiệu năng/chất lượng: đặt tiêu chí đo cho OCR, AI, tương tác và đồng bộ; đánh dấu **[Cần bổ sung số liệu]** thay vì báo cáo mục tiêu như kết quả.

### 1.4. Ranh giới so với hai bản nháp

- **Bảng đối chiếu cần có:** mô tả trong bản đầu/bản revised → trạng thái sản phẩm → chương trình bày hoặc hướng phát triển.
- Sửa các công nghệ và hành vi đã đổi: Isar → SQLite v11; Spring Boot → Express; Gemini tạo thẻ → Groq; đồng bộ tự động mặc định trong mô tả cũ → thủ công mặc định, tự động khi bật.
- Loại khỏi yêu cầu đã nghiệm thu các hứa hẹn về Pro, chia sẻ QR, chatbot, cây khái niệm, sinh học liệu từ chữ viết tay và các chỉ tiêu định lượng chưa đo.

## Chương 2. Mô hình hóa và thiết kế hệ thống

### 2.1. Use case và luồng nghiệp vụ

- Sơ đồ use case tổng quan, tách luồng không cần đăng nhập và luồng cần tài khoản/cloud.
- Đặc tả ngắn cho các use case cốt lõi: nhập ảnh/PDF; chuẩn hóa; OCR/sửa; sinh/duyệt/lưu thẻ; quản lý deck; ôn tập/xem nguồn; nhắc học/thống kê; đăng nhập/sao lưu/đồng bộ/giải quyết xung đột.
- Với mỗi use case: tác nhân, tiền điều kiện, luồng chính, lỗi/hủy/thử lại, hậu điều kiện và tiêu chí nghiệm thu.
- **Hình cần có:** sơ đồ hoạt động của luồng tài liệu → thẻ → phiên ôn; sơ đồ tuần tự cho sinh học liệu và đồng bộ.

### 2.2. Kiến trúc tổng thể và lựa chọn công nghệ

- Flutter presentation/application/domain/data; repository và adapter cho camera, PDF, OCR, SQLite, thông báo, mạng và Firebase.
- Express nhận yêu cầu AI và cloud; Groq sinh học liệu, Gemini tăng cường vùng OCR; Firebase Auth/Firestore và S3 phục vụ dữ liệu tài khoản/nguồn.
- Phân tích dữ liệu ở trên máy, dữ liệu chỉ gửi khi gọi AI, dữ liệu đồng bộ và tệp nguồn; nêu điều kiện mạng của mỗi luồng.
- **Hình/bảng cần có:** sơ đồ thành phần/triển khai; bảng công nghệ, vai trò, lý do chọn và giới hạn nền tảng.
- **Minh chứng:** `pubspec.yaml`, `functions/package.json`, `lib/app/`, `lib/features/`, `functions/src/app.js`.

### 2.3. Thiết kế dữ liệu cục bộ và truy vết nguồn

- Các thực thể chính: Document/SourcePage/SourceBlock, Deck/Card, ReviewEvent/ReviewSession/CardSchedule, thiết lập thông báo, metadata đồng bộ và snapshot.
- Quan hệ thẻ → tài liệu/trang/khối/câu trích; tọa độ chỉ được tô sáng khi đúng ảnh, hash và hệ tọa độ; nguồn thiếu vẫn giữ câu trích/số trang khi có thể.
- Xóa mềm học liệu và giữ lịch sử ôn; thay đổi schema qua migration đến v11 và tương thích bản sao v9/v10/v11.
- **Hình/bảng cần có:** ERD rút gọn; bảng thực thể và khóa/quan hệ; bảng các mốc migration quan trọng.
- **Minh chứng:** `lib/core/database/memo_mind_database.dart`, `lib/core/database/sync_schema.dart`, `docs/source-geometry-validation.md`.

### 2.4. Thiết kế pipeline tài liệu, OCR và AI

- Luồng ảnh/PDF → trang lưu cục bộ → cắt/xoay/điều chỉnh → OCR ML Kit → hiệu chỉnh SourceBlock → cấu hình sinh thẻ → backend → duyệt và lưu.
- Tách nguồn gốc và ảnh sau chuẩn hóa; kiểm tra hash/tọa độ khi OCR lại, khi duyệt và khi mở nguồn.
- Backend giữ khóa nhà cung cấp, giới hạn/kiểm tra yêu cầu và phản hồi; giao diện giữ kết quả lỗi/cảnh báo để người dùng sửa, không xem JSON hợp lệ là nội dung đúng.
- **Hình cần có:** sơ đồ dữ liệu đầu vào/đầu ra và điểm người dùng xác nhận; ví dụ cấu trúc thẻ BASIC/CLOZE/MCQ đã ẩn dữ liệu riêng tư.
- **Minh chứng:** `lib/features/document_import/`, `lib/features/image_normalization/`, `lib/features/ocr_editor/`, `lib/features/material_generation/`, `functions/src/`.

### 2.5. Thiết kế học ngoại tuyến và SM-2

- Phiên ôn đến hạn/tự do, lật thẻ rồi đánh giá Again/Hard/Good/Easy; lưu sự kiện và trạng thái lịch trong cùng transaction.
- Ánh xạ chất lượng 1/3/4/5; EF khởi tạo 2,5, cận dưới 1,3; chu kỳ 1 ngày, 6 ngày, rồi nhân EF trước đó; Again đưa thẻ vào cuối hàng đợi học lại.
- Lưu/khôi phục phiên dở, bỏ qua thẻ đã xóa/tạm ngừng; lịch sử ôn không mất khi xóa deck/card thông thường.
- **Bảng/hình cần có:** bảng phản hồi–q–tác động; sơ đồ trạng thái phiên; ví dụ chuỗi đánh giá và lịch được tính tay đối chiếu với test.
- **Minh chứng:** `lib/features/review/domain/sm2_scheduler.dart`, `lib/features/review/`, `test/unit/sm2_scheduler_test.dart`.

### 2.6. Thiết kế nhắc học, thống kê, tài khoản và đồng bộ

- Nhắc học cục bộ theo giờ đã chọn, chỉ lên lịch ngày có thẻ dự kiến đến hạn; phụ thuộc quyền/kênh Android và việc ứng dụng làm mới cửa sổ lịch.
- Thống kê đọc từ SQLite: thẻ đến hạn, lượt ôn hôm nay, tỷ lệ tự đánh giá đạt, chuỗi ngày học; giải thích ranh giới ngày theo múi giờ thiết bị.
- Tài khoản khách và tài khoản đã xác minh; sao lưu/khôi phục; thư viện chuẩn theo UID, outbox, version, xung đột và tệp nguồn theo SHA-256.
- Đồng bộ thủ công mặc định; tùy chọn tự động khi bật; phân biệt đồng bộ nội dung/tiến độ với bản sao khôi phục và hàng đợi phiên học chỉ ở thiết bị.
- **Hình/bảng cần có:** sơ đồ dữ liệu local/cloud; các tình huống mất mạng, gửi lại, xung đột và khôi phục.
- **Minh chứng:** `lib/features/reminders/`, `lib/features/statistics/`, `lib/features/account_backup/`, `lib/features/sync/`, `functions/src/sync/`, `functions/src/backup/`.

## Chương 3. Hiện thực ứng dụng MemoMind

### 3.1. Khởi động, giao diện và điều hướng

- **Màn hình:** welcome, Trang chủ, Thư viện, Ôn tập, Thống kê, Cá nhân/Cài đặt.
- **Xử lý:** khởi tạo workspace, tải tổng quan, trạng thái lỗi/thử lại, điều hướng từ thông báo và sau khi lưu học liệu.
- **Minh chứng:** `lib/app/`, `lib/features/home/`, `test/widget/startup_welcome_test.dart`, `test/widget/home_screen_test.dart`.
- **Hình nên chụp:** màn hình chính và sơ đồ điều hướng đã chạy trên bản Android cuối.

### 3.2. Nhập và chuẩn hóa tài liệu

- **Màn hình:** camera/nhập ảnh, nhập PDF, danh sách trang chờ xử lý, trình cắt và điều chỉnh ảnh.
- **Xử lý:** sao chép nguồn vào vùng lưu trữ, kiểm tra tệp, tách trang PDF, cắt/xoay/điều chỉnh và giữ ảnh dùng làm nguồn OCR.
- **Minh chứng:** `lib/features/document_import/`, `lib/features/image_normalization/`, `test/widget/document_import_flow_test.dart`, `test/widget/pdf_import_flow_test.dart`.
- **Hình nên chụp:** cùng một trang trước/sau chuẩn hóa; ghi thiết bị và điều kiện chụp nếu dùng để đánh giá.

### 3.3. OCR và xác nhận nội dung

- **Màn hình:** chọn trang OCR, tiến trình nhận dạng, trình biên tập ảnh–văn bản song song, hộp hỗ trợ Gemini theo vùng.
- **Xử lý:** ML Kit trên thiết bị tạo khối và tọa độ; sửa/xác nhận văn bản; tăng cường tùy chọn; kiểm tra ảnh/tọa độ khi mở lại hoặc OCR lại.
- **Minh chứng:** `lib/features/ocr_editor/`, `docs/source-geometry-validation.md`, `test/unit/ocr_orchestrator_test.dart`, `test/widget/ocr_dual_view_editor_test.dart`.
- **Hình nên chụp:** ảnh gốc, khối OCR được chọn và văn bản đã chỉnh; che dữ liệu học tập cá nhân.

### 3.4. Sinh, duyệt và lưu học liệu AI

- **Màn hình:** cấu hình loại/số lượng, danh sách thẻ đề xuất, chỉnh sửa thẻ, chọn deck/lưu.
- **Xử lý:** gửi SourceBlock đã xác nhận qua Express tới Groq; phân biệt lỗi nội dung và cảnh báo nguồn/trùng; người dùng sửa, chọn hoặc loại thẻ; lưu BASIC/CLOZE/MCQ trong transaction.
- **Minh chứng:** `lib/features/material_generation/`, `functions/src/app.js`, `functions/src/providers.js`, `docs/material-review-validation.md`, `functions/test/materials.test.js`.
- **Hình/bảng nên có:** một ví dụ thẻ của từng loại và bảng tình huống AI trả lỗi/cảnh báo; không công bố dữ liệu người dùng hoặc khóa API.

### 3.5. Quản lý bộ thẻ, xem nguồn và ôn tập

- **Màn hình:** Thư viện, chi tiết deck, biên tập card, xem nguồn, phiên ôn và tổng kết.
- **Xử lý:** tạo/sửa/xóa mềm/tìm kiếm deck/card; dẫn nguồn theo trang/khối/câu trích; lưu ReviewEvent, lịch và learning queue; tiếp tục phiên dở khi mở lại.
- **Minh chứng:** `lib/features/deck_management/`, `lib/features/review/`, `docs/uc10-uc04-validation.md`, `integration_test/offline_deck_review_test.dart`.
- **Hình nên chụp:** deck có ba loại card, màn hình nguồn và phiên ôn bốn mức đánh giá.

### 3.6. Nhắc học và thống kê

- **Màn hình:** cài đặt nhắc học, thông báo dẫn tới danh sách đến hạn, Thống kê và khối tổng quan Trang chủ.
- **Xử lý:** lưu lựa chọn giờ/quyền, lập lại cửa sổ thông báo; truy vấn bốn chỉ số từ SQLite và cập nhật theo phiên ôn/ngày địa phương.
- **Minh chứng:** `lib/features/reminders/`, `lib/features/statistics/`, `docs/fr16-validation.md`, `docs/fr17-validation.md`, `integration_test/reminder_native_test.dart`, `integration_test/offline_statistics_test.dart`.
- **Hình nên chụp:** trạng thái có/không có quyền, kho trống và kho đã có lịch sử; chỉ dùng ảnh thiết bị thật nếu đã kiểm tra.

### 3.7. Tài khoản, sao lưu và đồng bộ

- **Màn hình:** đăng ký/đăng nhập, xác minh email, quản lý bản sao, trạng thái đồng bộ/xung đột và dữ liệu cũ.
- **Xử lý:** phân tách kho khách/kho tài khoản; tạo/khôi phục snapshot; đồng bộ thư viện chuẩn theo UID; giữ thay đổi chưa gửi, xử lý xung đột và tệp nguồn độc lập với dữ liệu học.
- **Minh chứng:** `lib/features/account_backup/`, `lib/features/sync/`, `functions/src/backup/`, `functions/src/sync/`, `docs/deployment/sync-setup.md`, `docs/sync-validation.md`.
- **Bảng nên có:** thao tác thủ công/tự động, cần mạng, dữ liệu gửi, trạng thái khi lỗi; ghi rõ cloud và hai thiết bị thật đã/ chưa được nghiệm thu.

## Chương 4. Kiểm thử và đánh giá

### 4.1. Môi trường và phương pháp kiểm thử

- Liệt kê phiên bản Flutter/Dart/Android, thiết bị, backend, cấu hình mock/emulator/cloud của đúng lần kiểm thử được trích dẫn.
- Phân tầng: unit cho quy tắc và repository; widget cho giao diện/điều hướng; backend test cho API/provider mock; integration trên Android; kiểm tra thủ công với cloud thật khi có.
- **Bảng cần có:** nhóm kiểm thử, lệnh/thiết bị, kịch bản, kết quả, ngày, nguồn log/biên bản và giới hạn suy luận.

### 4.2. Ma trận yêu cầu và kịch bản chấp nhận

- Nhập ảnh/PDF → OCR/hiệu chỉnh → sinh/duyệt/lưu thẻ → xem nguồn → ôn offline → đóng/mở và tiếp tục.
- Deck/card thủ công; Again và các mức còn lại; xóa mềm và giữ lịch sử; nguồn thiếu/sai tọa độ; thông báo, thống kê và đổi ngày/múi giờ.
- Đăng nhập/xác minh; sao lưu/khôi phục; hai thiết bị sửa/ôn ngoại tuyến và đồng bộ lại; mất mạng ở các điểm gửi/xác nhận.
- **Bảng cần có:** yêu cầu–test tự động–kiểm tra thiết bị–trạng thái còn thiếu. Dùng `docs/uc10-uc04-validation.md`, `docs/fr16-validation.md`, `docs/fr17-validation.md`, `docs/fr18-validation.md`, `docs/sync-validation.md`, `docs/source-geometry-validation.md` làm điểm xuất phát rồi xác nhận lại kết quả mới nhất.

### 4.3. Kết quả đã có bằng chứng và giới hạn

- Tách kết quả theo từng lần kiểm thử, tránh ghi một tổng số test không tương ứng với một lần chạy hiện tại.
- Nêu rõ test provider mock không chứng minh chất lượng AI thực tế; Firestore Emulator/in-memory không thay thế Firebase, IAM, S3 hoặc mạng production.
- Ghi riêng các kiểm tra Android đã hoàn thành theo biên bản và các hạng mục còn cần hai thiết bị Android/cloud thật; không xem hướng dẫn nghiệm thu là kết quả nghiệm thu.
- **Bảng cần có:** kết quả, bằng chứng, môi trường, điều chưa thể kết luận và việc cần làm tiếp.

### 4.4. Đánh giá định lượng cần bổ sung khi có dữ liệu

- OCR: tập ảnh, ngôn ngữ, thiết bị/ánh sáng, cách lập ground truth, CER/WER và thời gian xử lý **[Cần bổ sung số liệu]**.
- Học liệu AI: bộ nguồn và tiêu chí chấm độc lập cho độ đúng, mức được nguồn hỗ trợ, trùng lặp, tỷ lệ phải sửa; tách đánh giá cấu trúc JSON khỏi chất lượng ngữ nghĩa **[Cần bổ sung số liệu]**.
- Hiệu năng: p50/p95 cho nhập/OCR/sinh thẻ/đồng bộ và kích thước dữ liệu, cấu hình thiết bị/mạng **[Cần bổ sung số liệu]**.
- Khả dụng: phương pháp khảo sát, số người, nhiệm vụ, điểm SUS và ý kiến định tính **[Cần bổ sung số liệu]**. Không ghi mục tiêu của bản nháp thành kết quả.
- **Hình/bảng chỉ tạo sau đo:** phân bố độ trễ, bảng CER/WER, tỷ lệ duyệt/sửa thẻ, thống kê SUS.

### 4.5. Kịch bản trình diễn và đánh giá hạn chế

- Demo tối thiểu: nhập trang bài giảng, chuẩn hóa/OCR/sửa, sinh và duyệt ba loại thẻ, mở nguồn, tắt mạng và ôn, xem lịch/thống kê, đóng/mở để kiểm tra lưu bền.
- Demo mở rộng khi cloud đã cấu hình và nghiệm thu: tài khoản, sao lưu, hai thiết bị đồng bộ và xử lý xung đột.
- Hạn chế cần phân tích từ bằng chứng: phụ thuộc chất lượng ảnh và nhà cung cấp AI; cảnh báo nguồn không bảo đảm đáp án đúng; thông báo Android có thể đến muộn; cloud/thiết bị thật còn cần kiểm chứng; APK demo dùng khóa ký phát triển.

## C. Kết luận và hướng phát triển

### 1. Kết luận theo mục tiêu

- Đối chiếu từng mục tiêu ở phần mở đầu với chức năng đã chạy, test và mức nghiệm thu thực tế.
- Nêu đóng góp kỹ thuật: chuỗi tài liệu–thẻ–ôn, duyệt kết quả AI, truy vết nguồn, học ngoại tuyến và dữ liệu đa thiết bị có kiểm soát.
- Không kết luận về hiệu quả học tập hoặc độ chính xác khi chưa có nghiên cứu/đo lường tương ứng.

### 2. Hướng phát triển

- Hoàn tất kiểm thử end-to-end trên hai Android và dịch vụ Firebase/S3 thật; bổ sung đo OCR, AI, hiệu năng và khảo sát khả dụng.
- Tối ưu xử lý ảnh/nguồn, chất lượng câu hỏi và trải nghiệm nhập tài liệu dựa trên lỗi đã quan sát.
- Xem xét iOS, chia sẻ deck riêng tư, cây khái niệm hoặc trợ lý học tập sau khi đánh giá nhu cầu, bảo mật, chi phí và phạm vi mới; tách rõ khỏi kết quả học kỳ này.

## Tài liệu tham khảo và phụ lục dự kiến

### Tài liệu tham khảo

- Nguồn học thuật về gợi nhớ chủ động, lặp lại ngắt quãng/SM-2, OCR và đánh giá khả dụng; ghi đầy đủ tác giả, năm, tên và đường dẫn/DOI nếu có.
- Tài liệu chính thức của Flutter, ML Kit, Firebase, AWS S3 và các thư viện/API được sử dụng; kiểm tra phiên bản và ngày truy cập khi viết.
- Mã nguồn và tài liệu kiểm chứng của dự án được dẫn như bằng chứng triển khai, không thay thế nguồn học thuật.

### Phụ lục

- A. Bảng đối chiếu yêu cầu của hai bản nháp với chức năng cuối cùng và bằng chứng mã nguồn/test.
- B. Use case chi tiết, sơ đồ kiến trúc/ERD, hợp đồng API và ví dụ dữ liệu đã ẩn thông tin riêng tư.
- C. Ma trận kiểm thử, lệnh chạy, thiết bị, log và ảnh chụp giao diện theo ngày kiểm tra.
- D. Phiếu đo CER/WER, đánh giá thẻ AI, hiệu năng và SUS nếu các phép đo được thực hiện.

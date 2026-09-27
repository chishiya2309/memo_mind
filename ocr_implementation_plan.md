# Kế hoạch Triển khai Chi tiết: UC04 (OCR Văn bản in) & UC05 (Hiệu chỉnh OCR) - MemoMind

> **Mục tiêu**: Xây dựng kiến trúc và mã nguồn hoàn chỉnh cho tính năng OCR nhận dạng văn bản in (UC04) và Hiệu chỉnh đối chiếu OCR (UC05) trên ứng dụng Flutter **MemoMind**, bám sát đặc tả P0, tuân thủ Clean Architecture, đảm bảo tính năng offline-first và cơ chế Hybrid (ML Kit on-device + Gemini Vision AI Assist).

---

## 1. Tổng quan Kiến trúc & Nguyên tắc Thiết kế (Design Principles)

```
┌────────────────────────────────────────────────────────────────────────┐
│                        PRESENTATION LAYER                              │
│  - OcrPageSelectionScreen     - OcrProgressOverlay / Screen            │
│  - OcrDualViewEditorScreen    - BoundingBoxInteractivePainter          │
│  - BlockEditorBottomSheet     - GeminiAssistConsentDialog              │
└───────────────────────────────────▲────────────────────────────────────┘
                                    │
┌───────────────────────────────────┴────────────────────────────────────┐
│                        APPLICATION LAYER                               │
│  - OcrOrchestratorUseCase     - CoordinateNormalizationService         │
│  - GeminiBlockEnhancerService - ImageRegionCropper                     │
└───────────────────────────────────▲────────────────────────────────────┘
                                    │
┌───────────────────────────────────┴────────────────────────────────────┐
│                          DOMAIN LAYER                                  │
│  - Entities: SourceBlock, OcrPageResult, OcrDocumentReview             │
│  - Value Objects: NormalizedBoundingBox, ConfidenceScore               │
│  - Enums: BlockStatus, ConfidenceSource, OcrEngineType, DocumentStatus │
│  - Interfaces: OcrRepository, TextRecognitionEngine, GeminiAiService   │
└───────────────────────────────────▲────────────────────────────────────┘
                                    │
┌───────────────────────────────────┴────────────────────────────────────┐
│                           DATA LAYER                                   │
│  - MemoMindDatabase (V4 Migration with `source_blocks`, `ocr_results`)  │
│  - LocalOcrRepository (SQLite transactions, atomic rollback)           │
│  - MlKitTextRecognitionEngine (google_mlkit_text_recognition)           │
│  - GeminiVisionEngine (REST/SDK + Crop patch payload)                  │
└────────────────────────────────────────────────────────────────────────┘
```

### Nguyên tắc Bắt buộc từ Đặc tả (Non-Negotiable Constraints):
1. **Bảo toàn dữ liệu gốc (BR04-08, BR05-01)**: Ảnh nguồn / ảnh chuẩn hóa là bất biến (read-only). Tách biệt tuyệt đối `rawText` (kết quả từ OCR, không được sửa đổi) và `normalizedText` (nội dung học viên hiệu chỉnh để đưa vào AI sinh học liệu).
2. **Không tự ý suy diễn (BR04-02, BR05-04)**: Không cho phép LLM tự ý dịch, tóm tắt, sửa chính tả hay chêm nội dung trong pipeline nhận dạng. Học viên luôn là người phê duyệt cuối cùng.
3. **Chuẩn hóa hệ tọa độ thống nhất (BR04-05)**: Toàn bộ bounding box được chuẩn hóa về hệ tọa độ tương đối $[0.0, 1.0]$ tương ứng với kích thước trang ảnh hiển thị (`NormalizedBoundingBox(left, top, width, height)`).
4. **Confidence minh bạch (BR04-04, BR05-07)**: `confidence` là nullable double ($[0.0, 1.0]$). Tuyệt đối không để LLM "bốc thuốc" một con số confidence giả tạo. ML Kit cung cấp confidence thật; kết quả từ Gemini/Thủ công để `confidence = null` và `needsReview = true`.
5. **Offline-First & Quyền riêng tư (BR05-06, BR05-09)**: ML Kit OCR và màn hình hiệu chỉnh hoạt động hoàn toàn offline. Không gửi bất kỳ ảnh hoặc văn bản nào lên Gemini nếu không có sự đồng ý rõ ràng của học viên.

---

## 2. Thiết kế Cơ sở Dữ liệu (Database Schema V4)

Nâng cấp `MemoMindDatabase` từ version `3` lên `4` với migration an toàn.

### 2.1. Cập nhật bảng `documents`
Bổ sung trạng thái mới vào trường `status` của tài liệu:
- Cũ: `CHECK(status IN ('pending_processing', 'pending_ocr'))`
- Mới (V4): `CHECK(status IN ('pending_processing', 'pending_ocr', 'pending_ocr_review', 'ready_for_generation'))`

### 2.2. Bảng `ocr_page_results`
Quản lý trạng thái và metadata nhận dạng của từng trang tài liệu:
```sql
CREATE TABLE ocr_page_results (
  page_id TEXT PRIMARY KEY,
  document_id TEXT NOT NULL,
  status TEXT NOT NULL CHECK(status IN ('not_started', 'processing', 'completed', 'failed')),
  recognized_language TEXT,
  raw_full_text TEXT,
  error_message TEXT,
  updated_at INTEGER NOT NULL,
  FOREIGN KEY(page_id) REFERENCES source_pages(page_id) ON DELETE CASCADE,
  FOREIGN KEY(document_id) REFERENCES documents(document_id) ON DELETE CASCADE
);
CREATE INDEX idx_ocr_page_results_doc ON ocr_page_results(document_id);
```

### 2.3. Bảng `source_blocks`
Lưu trữ từng khối văn bản nhận dạng được, phục vụ UC05 hiệu chỉnh và FR15 "Xem nguồn":
```sql
CREATE TABLE source_blocks (
  block_id TEXT PRIMARY KEY,
  document_id TEXT NOT NULL,
  page_id TEXT NOT NULL,
  page_number INTEGER NOT NULL CHECK(page_number > 0),
  order_index INTEGER NOT NULL CHECK(order_index >= 0),
  raw_text TEXT NOT NULL,
  normalized_text TEXT NOT NULL,
  box_left REAL CHECK(box_left BETWEEN 0 AND 1),
  box_top REAL CHECK(box_top BETWEEN 0 AND 1),
  box_width REAL CHECK(box_width BETWEEN 0 AND 1),
  box_height REAL CHECK(box_height BETWEEN 0 AND 1),
  has_valid_box INTEGER NOT NULL DEFAULT 1 CHECK(has_valid_box IN (0, 1)),
  confidence REAL CHECK(confidence IS NULL OR (confidence BETWEEN 0 AND 1)),
  confidence_source TEXT NOT NULL CHECK(confidence_source IN ('mlkit', 'gemini', 'user', 'unavailable')),
  status TEXT NOT NULL CHECK(status IN ('draft', 'needs_review', 'verified', 'user_added', 'deleted')),
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  FOREIGN KEY(document_id) REFERENCES documents(document_id) ON DELETE CASCADE,
  FOREIGN KEY(page_id) REFERENCES source_pages(page_id) ON DELETE CASCADE
);
CREATE INDEX idx_source_blocks_page ON source_blocks(page_id, order_index);
CREATE INDEX idx_source_blocks_doc ON source_blocks(document_id);
```

---

## 3. Thiết kế Domain Layer (`lib/features/ocr_editor/domain/`)

### 3.1. Enums & Value Objects
```dart
enum BlockStatus {
  draft,        // Bản nháp mặc định
  needsReview,  // Cần kiểm tra (độ tin cậy thấp, thiếu vị trí hoặc tọa độ lệch)
  verified,     // Đã kiểm tra / xác nhận bởi học viên
  userAdded,    // Đoạn do học viên bổ sung thủ công
  deleted,      // Đoạn bị đánh dấu xóa (loại bỏ khỏi đầu vào AI)
}

enum ConfidenceSource {
  mlkit,
  gemini,
  user,
  unavailable,
}

class NormalizedBoundingBox {
  final double left;   // 0.0 -> 1.0
  final double top;    // 0.0 -> 1.0
  final double width;  // 0.0 -> 1.0
  final double height; // 0.0 -> 1.0

  const NormalizedBoundingBox({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });

  Rect toRect(Size imageSize) => Rect.fromLTWH(
    left * imageSize.width,
    top * imageSize.height,
    width * imageSize.width,
    height * imageSize.height,
  );
}
```

### 3.2. Entities
- `SourceBlock`:
  - `String blockId`
  - `String documentId`
  - `String pageId`
  - `int pageNumber`
  - `int orderIndex`
  - `String rawText` (chỉ đọc)
  - `String normalizedText` (có thể sửa)
  - `NormalizedBoundingBox? boundingBox` (nullable theo luồng 9b, 6a)
  - `bool hasValidBox`
  - `double? confidence`
  - `ConfidenceSource confidenceSource`
  - `BlockStatus status`
  - `DateTime createdAt`, `DateTime updatedAt`
- `OcrPageReview`:
  - `SourcePage page`
  - `OcrPageStatus status`
  - `List<SourceBlock> blocks`
  - `String? errorMessage`
- `OcrDocumentReview`:
  - `ImportedDocument document`
  - `List<OcrPageReview> pageReviews`
  - `bool get isReadyForGeneration`
  - `int get totalBlocksCount`
  - `int get needsReviewCount`

### 3.3. Interfaces
- `OcrRepository`:
  - `Future<OcrDocumentReview> getOcrReview(String documentId);`
  - `Future<void> savePageOcrDraft({required String pageId, required List<SourceBlock> blocks, required String rawFullText, String? language});`
  - `Future<void> updateSourceBlock(SourceBlock block);`
  - `Future<void> addSourceBlock(SourceBlock block);`
  - `Future<void> deleteSourceBlock(String blockId);`
  - `Future<void> restoreSourceBlockText(String blockId);` // Gán normalizedText = rawText
  - `Future<void> confirmOcrReview(String documentId);`    // Đổi status sang ready_for_generation
- `TextRecognitionEngine`:
  - `Future<ExtractedOcrPage> recognizePage(String imagePath, Size imageSize);`
- `GeminiVisionEngine`:
  - `Future<String> enhanceTextFromCrop(Uint8List croppedImageBytes);`

---

## 4. Thiết kế Data Layer (`lib/features/ocr_editor/data/`)

### 4.1. `MlKitTextRecognitionEngine`
- Sử dụng package `google_mlkit_text_recognition` (Latin script hỗ trợ cả tiếng Anh và tiếng Việt).
- Chuyển đổi cấu trúc ML Kit:
  - Duyệt `RecognizedText.blocks` -> trích xuất bounding box dạng pixel Rect (`block.boundingBox`).
  - Chuẩn hóa:
    $$left = \text{clamp}(rect.left / imageWidth, 0.0, 1.0)$$
    $$top = \text{clamp}(rect.top / imageHeight, 0.0, 1.0)$$
    $$width = \text{clamp}(rect.width / imageWidth, 0.0, 1.0 - left)$$
    $$height = \text{clamp}(rect.height / imageHeight, 0.0, 1.0 - top)$$
  - Kiểm tra tính hợp lệ của tọa độ (Luồng 11a): Nếu tọa độ âm, vượt biên hoặc diện tích $= 0$, thực hiện clamp và đánh dấu `needsReview = true` với ghi chú cảnh báo vị trí.
  - Thuộc tính `confidence`: Lấy trung bình cộng confidence từ các `line.elements` hoặc confidence của block (nếu ML Kit cung cấp). Nếu không có, gán `null`.
  - Phân loại trạng thái ban đầu:
    - Nếu `confidence != null && confidence < 0.75` $\rightarrow$ `status = BlockStatus.needsReview`.
    - Nếu `confidence == null` $\rightarrow$ `status = BlockStatus.needsReview`.
    - Nếu không tìm thấy bounding box hợp lệ $\rightarrow$ `hasValidBox = false, status = BlockStatus.needsReview`.
    - Ngược lại $\rightarrow$ `status = BlockStatus.draft`.
- Tạo `stub` và `io` để đảm bảo code testable trên unit test/FFI mà không bị lỗi MissingPlugin.

### 4.2. `GeminiVisionEngine` (AI-Assist)
- Sử dụng Google Generative AI API (Gemini 1.5 Flash / 2.5 Flash).
- Đầu vào: Mảnh ảnh đã cắt (cropped patch) từ `ImageRegionCropper` ứng với bounding box của block đang xem xét.
- System Prompt khắt khe (tuân thủ BR04-02 & BR05-04):
  ```
  Bạn là một công cụ trích xuất ký tự quang học (OCR) chuyên nghiệp.
  Nhiệm vụ: Chép lại CHÍNH XÁC NGUYÊN VĂN toàn bộ nội dung văn bản nhìn thấy trong ảnh.
  Quy tắc tuyệt đối:
  1. KHÔNG dịch sang ngôn ngữ khác.
  2. KHÔNG tóm tắt, diễn giải hoặc thêm lời bình.
  3. KHÔNG tự ý sửa chính tả hay tự bổ sung từ bị thiếu do suy đoán.
  4. Giữ nguyên định dạng xuống dòng của các dòng văn bản.
  5. Chỉ trả về duy nhất văn bản được chép lại.
  ```

---

## 5. Thiết kế Application Layer (`lib/features/ocr_editor/application/`)

### 5.1. `OcrOrchestrator`
- Quản lý quy trình chạy batch theo từng trang (Luồng 6, 7, Luồng 13a):
  - Nhận danh sách các trang được chọn (`List<SourcePage>`).
  - Kiểm tra ảnh tồn tại (`displayPath`), dung lượng đĩa trước khi xử lý.
  - Xử lý tuần tự từng trang với Stream phát sự kiện tiến độ:
    `Stream<OcrProgress> run({required List<SourcePage> pages})`
    - Bắn event `OcrProgress(currentPage: 2, totalPages: 5, status: PageStatus.processing)`.
    - Nếu 1 trang thất bại (Luồng 13a): Ghi nhận lỗi trang đó, tiếp tục các trang còn lại.
    - Lưu kết quả từng trang trong 1 SQLite Transaction độc lập.
  - Sau khi hoàn thành: Đổi trạng thái tài liệu sang `pending_ocr_review`.

### 5.2. `ImageRegionCropper`
- Sử dụng thư viện `image` để cắt crop vùng ảnh theo `NormalizedBoundingBox` với padding an toàn 5% xung quanh để gửi sang Gemini khi học viên yêu cầu hỗ trợ.

---

## 6. Thiết kế Presentation Layer (`lib/features/ocr_editor/presentation/`)

### 6.1. Luồng Màn hình (Screen Navigation Flow)
```
[PendingProcessingScreen] 
        │ (Nhấn "Nhận dạng văn bản")
        ▼
[OcrPageSelectionScreen] (Chọn tất cả / từng trang -> "Bắt đầu OCR")
        │
        ▼
[OcrProcessingModal / Progress View] (Hiển thị "Đang xử lý trang 2/5", hỗ trợ Hủy)
        │
        ▼
[OcrDualViewEditorScreen] (UC05 - Màn hình đối chiếu & hiệu chỉnh)
    ├── Ảnh nguồn với BoundingBox Canvas (Zoom/Pan, Highlight box khi chọn block)
    ├── Danh sách SourceBlock (Bộ lọc: Tất cả / Cần kiểm tra / Đã sửa)
    ├── Sửa văn bản tại chỗ / Khôi phục gốc / Xóa / Thêm đoạn
    ├── "Cải thiện bằng AI" (Gemini patch crop + Privacy warning modal)
    └── Bottom Bar: "Lưu nháp" & "Xác nhận OCR"
        │ (Xác nhận)
        ▼
[Dialog: Đã xác nhận OCR] -> Chuyển sang "Tạo flashcard & câu hỏi" hoặc "Về thư viện"
```

### 6.2. Chi tiết Giao diện Đối chiếu & Hiệu chỉnh (`OcrDualViewEditorScreen`)
1. **Khung nhìn Ảnh tương tác (Image Interactive View)**:
   - Sử dụng `InteractiveViewer` bọc ngoài `CustomPaint`.
   - `BoundingBoxPainter`:
     - Vẽ các khung chữ nhật tương đối theo danh sách `SourceBlock`.
     - Màu sắc:
       - **Block đang chọn**: Viền dày Primary Blue `#1E40AF` + nền phủ mờ 20% + điểm đánh dấu số thứ tự.
       - **Block cần kiểm tra (`needsReview`)**: Viền đứt nét Amber Warning `#D97706` + icon cảnh báo.
       - **Block bình thường / đã duyệt**: Viền mỏng mờ xám/xanh.
       - **Block do người dùng thêm**: Viền Teal `#0D9488`.
     - Tương tác 2 chiều mượt mà:
       - *Chạm vào bounding box trên ảnh*: Tự động cuộn danh sách khối chữ ở dưới đến đúng block đó và mở chế độ chỉnh sửa.
       - *Chạm vào thẻ khối chữ*: Khung ảnh tự động pan/zoom đưa bounding box tương ứng vào trung tâm khung nhìn.
2. **Bộ lọc & Thẻ Khối chữ (Block Cards)**:
   - Tab Bar Filter: "Tất cả (24)" | "Cần kiểm tra (5)" | "Đã sửa (2)".
   - Mỗi Card hiển thị:
     - Badge thứ tự `#1`, `#2`...
     - Huy hiệu Confidence: e.g., `89% (ML Kit)` hoặc badge cảnh báo `Cần kiểm tra`.
     - Trường chỉnh sửa `normalizedText` (TextField đa dòng).
     - Nếu đã sửa: Nút "Xem bản gốc" / "Khôi phục bản gốc".
     - Menu thao tác phụ: "Cải thiện bằng AI", "Xóa đoạn", "Báo lỗi vị trí".
3. **Thao tác Thêm đoạn văn bản bị bỏ sót (Luồng 8b)**:
   - Nút FAB hoặc toolbar button: "Thêm đoạn".
   - Cho phép người dùng kéo quét vùng trên ảnh để tạo bounding box mới hoặc chọn "Gắn toàn trang" nếu không khoanh vùng được.
   - Nhập nội dung $\rightarrow$ tạo `SourceBlock` có `status = userAdded`.
4. **Hộp thoại Cảnh báo Quyền riêng tư (Gemini Assist Consent Dialog)**:
   - Hiển thị rõ: *"Bạn đang yêu cầu AI hỗ trợ nhận dạng vùng này. Một phần ảnh bài viết sẽ được gửi tới dịch vụ đám mây của Google để xử lý. Vui lòng không gửi nội dung nhạy cảm hoặc bí mật cá nhân."*
   - Checkbox: "Tôi hiểu và đồng ý".
   - Sau khi Gemini trả về kết quả: Hiển thị dialog so sánh Diff (ML Kit vs Gemini đề xuất) để người dùng chủ động bấm "Áp dụng đề xuất".

---

## 7. Phân rã Công việc & Lộ trình Thực hiện (Implementation Milestones)

| Giai đoạn | Nội dung công việc | Output / Deliverable |
|:---|:---|:---|
| **Phase 1: Database & Core Domain** | • Nâng cấp schema DB lên V4 (bảng `source_blocks`, `ocr_page_results`, cập nhật status enum `documents`).<br>• Định nghĩa toàn bộ Models, Entities, Enums trong `ocr_editor/domain`.<br>• Viết Unit Test cho DB Migration V4 và Repository CRUD. | • `MemoMindDatabase` V4 migration test pass.<br>• `source_block.dart`, `ocr_document_review.dart`. |
| **Phase 2: Data Repositories & Engine** | • Thêm dependency `google_mlkit_text_recognition`.<br>• Tạo `MlKitTextRecognitionEngine` với logic chuẩn hóa tọa độ và confidence.<br>• Xây dựng `LocalOcrRepository` với SQLite atomic transactions.<br>• Viết engine mock/stub để chạy test cô lập. | • Unit tests cho coordinate normalization.<br>• Repo test lưu/xóa/sửa block, hoàn tác. |
| **Phase 3: UC04 Flow (OCR Văn bản in)** | • Thay thế `_OcrPlaceholderScreen` trong `PendingProcessingScreen`.<br>• Xây dựng `OcrPageSelectionScreen` (chọn trang, hiển thị trạng thái chuẩn hóa).<br>• Xây dựng `OcrProgressView` hiển thị tiến độ từng trang, xử lý lỗi từng phần (Luồng 13a).<br>• Điều hướng mượt mà sang UC05 sau khi hoàn thành. | • Hoàn thiện trọn vẹn luồng chính và luồng thay thế/ngoại lệ của UC04.<br>• Widget test cho màn hình chọn trang & tiến trình. |
| **Phase 4: UC05 Flow (Hiệu chỉnh OCR)** | • Xây dựng `OcrDualViewEditorScreen` với `InteractiveViewer` và `CustomPainter`.<br>• Triển khai tương tác 2 chiều: Tap box $\leftrightarrow$ Scroll card.<br>• Bộ lọc "Cần kiểm tra", chỉnh sửa `normalizedText`, khôi phục `rawText`.<br>• Thao tác Thêm đoạn (Luồng 8b) & Xóa đoạn (Luồng 8c).<br>• Hộp thoại xác nhận OCR (cảnh báo block chưa kiểm tra). | • Màn hình đối chiếu trực quan, mượt mà trên mobile.<br>• Widget test cho các tương tác hiệu chỉnh. |
| **Phase 5: Hybrid AI Assist (Gemini Integration)** | • Thêm `google_generative_ai` hoặc HTTP REST client cho Gemini.<br>• Cắt crop ảnh vùng bounding box an toàn (`ImageRegionCropper`).<br>• Prompt chuyên dụng chép nguyên văn.<br>• Hộp thoại xin phép quyền riêng tư và giao diện so sánh đối chiếu trước khi áp dụng. | • Tính năng "Cải thiện bằng AI" hoạt động theo đúng cam kết hybrid. |
| **Phase 6: Kiểm thử Toàn diện & Benchmark** | • Unit test độ bao phủ $\ge 85\%$ cho domain & data logic.<br>• Widget test cho trọn vẹn luồng từ UC04 $\rightarrow$ UC05.<br>• Xây dựng kịch bản benchmark CER/WER và đo đạc độ trễ trên thiết bị. | • Test suite xanh 100%.<br>• Báo cáo đánh giá hiệu năng hybrid. |

---

## 8. Kế hoạch Đo đạc & Benchmark (Evaluation Protocol)

Theo đề xuất kiến trúc Hybrid, nhóm sẽ tiến hành thực nghiệm đo đạc:
1. **Tập dữ liệu**: Tối thiểu 60 ảnh mẫu tài liệu học tập thực tế (slide bài giảng, đề thi, sách in tiếng Việt có dấu, tài liệu tiếng Anh, tài liệu song ngữ).
2. **Tiêu chí đánh giá**:
   - **CER (Character Error Rate)** & **WER (Word Error Rate)** giữa: ML Kit đơn thuần vs Gemini đơn thuần vs Phương án Hybrid.
   - **Tỷ lệ Bounding Box chính xác (IoU > 0.75)** để bảo đảm tính năng FR15 "Xem nguồn".
   - **Độ trễ xử lý (Latency p50, p95)** trên mỗi trang.
   - **Mức tiêu thụ tài nguyên và chi phí API**.

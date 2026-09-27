import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memo_mind/features/document_import/domain/document_import_models.dart';
import 'package:memo_mind/features/ocr_editor/domain/ocr_models.dart';
import 'package:memo_mind/features/ocr_editor/domain/ocr_repository.dart';
import 'package:memo_mind/features/ocr_editor/presentation/ocr_dual_view_editor_screen.dart';
import 'package:memo_mind/shared/theme/memo_theme.dart';

class _FakeOcrRepository implements OcrRepository {
  _FakeOcrRepository({required this.review});

  OcrDocumentReview review;
  bool confirmed = false;
  bool draftSaved = false;

  @override
  Future<OcrDocumentReview> getOcrReview(String documentId) async => review;

  @override
  Future<void> updateSourceBlock(SourceBlock block) async {
    final page = review.pageReviews.first;
    final index = page.blocks.indexWhere((b) => b.blockId == block.blockId);
    if (index >= 0) {
      page.blocks[index] = block;
    }
  }

  @override
  Future<void> restoreSourceBlock(String blockId) async {
    final page = review.pageReviews.first;
    final index = page.blocks.indexWhere((b) => b.blockId == blockId);
    if (index >= 0) {
      final block = page.blocks[index];
      page.blocks[index] = block.copyWith(normalizedText: block.rawText);
    }
  }

  @override
  Future<void> confirmOcrReview(String documentId) async {
    confirmed = true;
  }

  @override
  Future<void> saveDraft(String documentId) async {
    draftSaved = true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  final page1 = SourcePage(
    pageId: 'p-1',
    documentId: 'doc-1',
    pageNumber: 1,
    originalPageNumber: 1,
    source: DocumentPageSource.gallery,
    dataRelativePath: 'p1.jpg',
    absolutePath: 'p1.jpg',
    mimeType: 'image/jpeg',
    fileSizeBytes: 1000,
    width: 800,
    height: 1200,
    sha256: 'h1',
    qualityCode: 'ok',
    qualityWarningAccepted: false,
    createdAt: DateTime.now(),
  );

  final testDoc = ImportedDocument(
    documentId: 'doc-1',
    title: 'Tài liệu ôn tập',
    status: ImportedDocumentStatus.pendingOcrReview,
    privacy: DocumentPrivacy.private,
    createdAt: DateTime.now(),
    updatedAt: DateTime.now(),
    pages: [page1],
  );

  final block1 = SourceBlock(
    blockId: 'b-1',
    documentId: 'doc-1',
    pageId: 'p-1',
    pageNumber: 1,
    orderIndex: 0,
    rawText: 'Nội dung câu 1',
    normalizedText: 'Nội dung câu 1',
    boundingBox: const NormalizedBoundingBox(
      left: 0.1,
      top: 0.1,
      width: 0.8,
      height: 0.1,
    ),
    hasValidBox: true,
    confidence: 0.95,
    confidenceSource: ConfidenceSource.mlkit,
    status: BlockStatus.draft,
    createdAt: DateTime.now(),
    updatedAt: DateTime.now(),
  );

  final block2 = SourceBlock(
    blockId: 'b-2',
    documentId: 'doc-1',
    pageId: 'p-1',
    pageNumber: 1,
    orderIndex: 1,
    rawText: 'Nội dung câu 2 cần kiểm tra',
    normalizedText: 'Nội dung câu 2 cần kiểm tra',
    boundingBox: const NormalizedBoundingBox(
      left: 0.1,
      top: 0.3,
      width: 0.8,
      height: 0.1,
    ),
    hasValidBox: true,
    confidence: 0.50,
    confidenceSource: ConfidenceSource.mlkit,
    status: BlockStatus.needsReview,
    createdAt: DateTime.now(),
    updatedAt: DateTime.now(),
  );

  testWidgets('OcrDualViewEditorScreen displays blocks, filters, edits and confirms', (tester) async {
    final pageReview = OcrPageReview(
      pageId: 'p-1',
      documentId: 'doc-1',
      pageNumber: 1,
      status: OcrPageStatus.completed,
      blocks: [block1, block2],
      updatedAt: DateTime.now(),
    );

    final docReview = OcrDocumentReview(
      document: testDoc,
      pageReviews: [pageReview],
    );

    final fakeRepo = _FakeOcrRepository(review: docReview);

    await tester.pumpWidget(
      MaterialApp(
        theme: MemoTheme.light,
        home: OcrDualViewEditorScreen(
          document: testDoc,
          ocrRepository: fakeRepo,
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Verify both blocks displayed
    expect(find.text('Nội dung câu 1'), findsOneWidget);
    expect(find.text('Nội dung câu 2 cần kiểm tra'), findsOneWidget);
    expect(find.text('Cần kiểm tra'), findsWidgets);

    // Test filter 'Cần kiểm tra (1)'
    await tester.tap(find.text('Cần kiểm tra (1)'));
    await tester.pumpAndSettle();

    expect(find.text('Nội dung câu 1'), findsNothing);
    expect(find.text('Nội dung câu 2 cần kiểm tra'), findsOneWidget);

    // Switch back to 'Tất cả (2)'
    await tester.tap(find.text('Tất cả (2)'));
    await tester.pumpAndSettle();
    expect(find.text('Nội dung câu 1'), findsOneWidget);

    // Edit text in block 1
    final textField = find.byType(TextField).first;
    await tester.enterText(textField, 'Nội dung câu 1 đã sửa');
    await tester.pumpAndSettle();

    expect(find.text('Đã sửa'), findsWidgets);

    // Test Confirm OCR button
    await tester.tap(find.byKey(const Key('confirm-ocr-btn')));
    await tester.pumpAndSettle();

    // Warning dialog because 1 block is still needsReview
    expect(find.text('Còn đoạn cần kiểm tra'), findsOneWidget);
    await tester.tap(find.text('Vẫn xác nhận'));
    await tester.pumpAndSettle();

    // Confirmation dialog
    expect(find.text('Xác nhận hoàn tất OCR?'), findsOneWidget);
    await tester.tap(find.byKey(const Key('final-ocr-confirm-btn')));
    await tester.pumpAndSettle();

    expect(fakeRepo.confirmed, isTrue);
    expect(find.text('OCR đã được xác nhận!'), findsOneWidget);
  });
}

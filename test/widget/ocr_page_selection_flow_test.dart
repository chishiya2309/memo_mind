import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memo_mind/features/document_import/domain/document_import_models.dart';
import 'package:memo_mind/features/image_normalization/domain/image_normalization_models.dart';
import 'package:memo_mind/features/ocr_editor/application/ocr_orchestrator.dart';
import 'package:memo_mind/features/ocr_editor/presentation/ocr_page_selection_screen.dart';
import 'package:memo_mind/shared/theme/memo_theme.dart';

class _FakeOcrOrchestrator extends OcrOrchestrator {
  _FakeOcrOrchestrator();

  @override
  Stream<OcrBatchProgress> processPages({
    required ImportedDocument document,
    required List<SourcePage> selectedPages,
  }) async* {
    yield OcrBatchProgress(
      currentPageIndex: 1,
      totalPages: selectedPages.length,
      pageNumber: selectedPages.first.pageNumber,
      pageId: selectedPages.first.pageId,
      message: 'Đang xử lý trang 1/${selectedPages.length}…',
    );

    yield OcrBatchProgress(
      currentPageIndex: selectedPages.length,
      totalPages: selectedPages.length,
      pageNumber: selectedPages.last.pageNumber,
      pageId: selectedPages.last.pageId,
      message: 'Hoàn tất nhận dạng văn bản.',
      isDone: true,
      successfulPages: selectedPages,
    );
  }
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
    normalizationStatus: PageNormalizationStatus.ready,
  );

  final page2 = SourcePage(
    pageId: 'p-2',
    documentId: 'doc-1',
    pageNumber: 2,
    originalPageNumber: 2,
    source: DocumentPageSource.gallery,
    dataRelativePath: 'p2.jpg',
    absolutePath: 'p2.jpg',
    mimeType: 'image/jpeg',
    fileSizeBytes: 1000,
    width: 800,
    height: 1200,
    sha256: 'h2',
    qualityCode: 'ok',
    qualityWarningAccepted: false,
    createdAt: DateTime.now(),
    normalizationStatus: PageNormalizationStatus.pending,
  );

  final testDoc = ImportedDocument(
    documentId: 'doc-1',
    title: 'Đề thi trắc nghiệm',
    status: ImportedDocumentStatus.pendingOcr,
    privacy: DocumentPrivacy.private,
    createdAt: DateTime.now(),
    updatedAt: DateTime.now(),
    pages: [page1, page2],
  );

  testWidgets('OcrPageSelectionScreen toggles pages and launches processing', (tester) async {
    final orchestrator = _FakeOcrOrchestrator();

    await tester.pumpWidget(
      MaterialApp(
        theme: MemoTheme.light,
        home: OcrPageSelectionScreen(
          document: testDoc,
          orchestrator: orchestrator,
        ),
      ),
    );

    // Initial state: 2 pages selected
    expect(find.text('Chọn trang nhận dạng'), findsOneWidget);
    expect(find.text('Bắt đầu OCR (2 trang)'), findsOneWidget);
    expect(find.text('Đã chọn 2/2 trang'), findsOneWidget);

    // Unselect page 2
    await tester.tap(find.byKey(const Key('toggle-page-p-2')));
    await tester.pumpAndSettle();

    expect(find.text('Bắt đầu OCR (1 trang)'), findsOneWidget);
    expect(find.text('Đã chọn 1/2 trang'), findsOneWidget);

    // Toggle select all
    await tester.tap(find.byKey(const Key('toggle-all-pages-btn')));
    await tester.pumpAndSettle();
    expect(find.text('Bắt đầu OCR (2 trang)'), findsOneWidget);

    // Tap Start OCR button
    await tester.tap(find.byKey(const Key('start-ocr-button')));
    await tester.pumpAndSettle();

    // Navigates to OcrProcessingScreen and completes
    expect(find.text('Nhận dạng văn bản'), findsOneWidget);
    expect(find.text('Nhận dạng thành công!'), findsOneWidget);
    expect(find.byKey(const Key('go-to-editor-btn')), findsOneWidget);
  });
}

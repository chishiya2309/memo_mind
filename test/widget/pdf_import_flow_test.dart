import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:memo_mind/features/document_import/application/pdf_import_services.dart';
import 'package:memo_mind/features/document_import/domain/document_import_models.dart';
import 'package:memo_mind/features/document_import/domain/document_import_repository.dart';
import 'package:memo_mind/features/document_import/presentation/pdf_import_flow.dart';
import 'package:memo_mind/shared/theme/memo_theme.dart';

class _FakePicker implements PdfCandidatePicker {
  const _FakePicker(this.candidate);

  final PdfCandidate? candidate;

  @override
  Future<PdfCandidate?> pickPdf() async => candidate;
}

class _FakeProcessor implements PdfDocumentProcessor {
  _FakeProcessor(this.pageCount);

  final int pageCount;
  final Uint8List thumbnail = Uint8List.fromList(
    image.encodePng(image.Image(width: 4, height: 6)),
  );

  @override
  Future<void> dispose() async {}

  @override
  Future<PdfInspection> inspect(PdfCandidate candidate) async => PdfInspection(
    pageCount: pageCount,
    pageSizes: List.generate(
      pageCount,
      (_) => const PdfPageSize(width: 595, height: 842),
    ),
    isEncrypted: false,
  );

  @override
  Future<List<RenderedPdfPage>> renderSelectedPages(
    PdfCandidate candidate,
    List<int> pageNumbers,
  ) async => pageNumbers
      .map(
        (page) => RenderedPdfPage(
          originalPageNumber: page,
          temporaryPath: 'page-$page.png',
          fileSizeBytes: thumbnail.length,
          width: 4,
          height: 6,
          sha256: 'page-$page-hash',
        ),
      )
      .toList();

  @override
  Future<Uint8List> renderThumbnail(
    PdfCandidate candidate,
    int pageNumber,
  ) async => thumbnail;
}

class _FakePdfRepository implements PdfImportRepository {
  List<int>? importedPages;
  bool discarded = false;

  @override
  Future<ImportedDocument> createFromPdf({
    required PdfCandidate candidate,
    required List<RenderedPdfPage> pages,
  }) async {
    importedPages = pages.map((page) => page.originalPageNumber).toList();
    final now = DateTime(2026, 9, 25, 12);
    return ImportedDocument(
      documentId: 'pdf-document',
      title: 'Bài giảng tuần 1',
      status: ImportedDocumentStatus.pendingOcr,
      privacy: DocumentPrivacy.private,
      createdAt: now,
      updatedAt: now,
      originalFile: OriginalDocumentFile(
        name: candidate.originalName,
        relativePath: 'documents/pdf-document/originals/original.pdf',
        absolutePath: 'original.pdf',
        mimeType: 'application/pdf',
        fileSizeBytes: candidate.fileSizeBytes,
        sha256: candidate.sha256,
      ),
      pages: [
        for (var index = 0; index < pages.length; index++)
          SourcePage(
            pageId: 'page-$index',
            documentId: 'pdf-document',
            pageNumber: index + 1,
            originalPageNumber: pages[index].originalPageNumber,
            source: DocumentPageSource.pdf,
            dataRelativePath: 'documents/pdf-document/pages/page-$index.png',
            absolutePath: 'missing-page-$index.png',
            mimeType: 'image/png',
            fileSizeBytes: pages[index].fileSizeBytes,
            width: pages[index].width,
            height: pages[index].height,
            sha256: pages[index].sha256,
            qualityCode: 'not_inspected',
            qualityWarningAccepted: false,
            createdAt: now,
          ),
      ],
    );
  }

  @override
  Future<void> discardPdfCandidate(PdfCandidate candidate) async {
    discarded = true;
  }
}

const _candidate = PdfCandidate(
  temporaryPath: 'selected.pdf',
  originalName: 'Bài giảng tuần 1.pdf',
  fileSizeBytes: 2048,
  sha256: 'pdf-hash',
  ownsTemporaryFile: false,
);

Widget _app({required int pageCount, required _FakePdfRepository repository}) {
  return MaterialApp(
    theme: MemoTheme.light,
    home: PdfImportFlow(
      repository: repository,
      picker: const _FakePicker(_candidate),
      processor: _FakeProcessor(pageCount),
    ),
  );
}

void main() {
  testWidgets('PDF with at most 10 pages selects all and imports atomically', (
    tester,
  ) async {
    final repository = _FakePdfRepository();
    await tester.pumpWidget(_app(pageCount: 3, repository: repository));
    await tester.pumpAndSettle();

    expect(find.text('Bài giảng tuần 1.pdf'), findsOneWidget);
    expect(find.textContaining('Đã chọn 3 trang'), findsOneWidget);
    await tester.tap(find.byKey(const Key('pdf-import-document')));
    await tester.pumpAndSettle();

    expect(find.text('Nhập PDF thành công'), findsWidgets);
    expect(repository.importedPages, [1, 2, 3]);
    await tester.tap(find.byKey(const Key('pdf-continue')));
    await tester.pumpAndSettle();
    expect(find.text('Tài liệu đang chờ OCR'), findsOneWidget);
  });

  testWidgets('long PDF starts empty and supports a 10-page range', (
    tester,
  ) async {
    final repository = _FakePdfRepository();
    await tester.pumpWidget(_app(pageCount: 15, repository: repository));
    await tester.pumpAndSettle();

    expect(find.textContaining('Tài liệu có 15 trang'), findsOneWidget);
    await tester.tap(find.text('Đã hiểu'));
    await tester.pumpAndSettle();
    expect(find.text('Đã chọn 0/10 trang'), findsOneWidget);

    await tester.tap(find.byKey(const Key('pdf-confirm-selection')));
    await tester.pump();
    expect(
      find.text('Vui lòng chọn ít nhất một trang để tiếp tục.'),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('pdf-select-range')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('pdf-range-start')), '2');
    await tester.enterText(find.byKey(const Key('pdf-range-end')), '11');
    await tester.tap(find.byKey(const Key('pdf-apply-range')));
    await tester.pumpAndSettle();
    expect(find.text('Đã chọn 10/10 trang'), findsOneWidget);

    await tester.tap(find.byKey(const Key('pdf-page-1')));
    await tester.pumpAndSettle();
    expect(
      find.text('Bạn chỉ có thể chọn tối đa 10 trang cho mỗi lượt xử lý.'),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('pdf-confirm-selection')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('pdf-import-document')));
    await tester.pumpAndSettle();
    expect(repository.importedPages, [2, 3, 4, 5, 6, 7, 8, 9, 10, 11]);
  });
}

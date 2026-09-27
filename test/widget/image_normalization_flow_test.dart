import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:memo_mind/features/document_import/application/image_inspector.dart';
import 'package:memo_mind/features/document_import/domain/document_import_models.dart';
import 'package:memo_mind/features/image_normalization/application/image_normalization_engine.dart';
import 'package:memo_mind/features/image_normalization/domain/image_normalization_models.dart';
import 'package:memo_mind/features/image_normalization/domain/image_normalization_repository.dart';
import 'package:memo_mind/features/image_normalization/presentation/document_normalization_overview.dart';
import 'package:memo_mind/shared/theme/memo_theme.dart';

void main() {
  testWidgets('normalizes a page and enables OCR handoff', (tester) async {
    final page = _page();
    final document = _document(page);
    final repository = _FakeNormalizationRepository(document);
    final engine = _FakeEngine();
    await tester.pumpWidget(
      MaterialApp(
        theme: MemoTheme.light,
        home: PendingProcessingScreen(
          document: document,
          normalizationRepository: repository,
          engine: engine,
          inspector: _FakeInspector(),
        ),
      ),
    );

    expect(find.text('Tài liệu đang chờ xử lý'), findsOneWidget);
    final initialButton = tester.widget<FilledButton>(
      find.byKey(const Key('recognize-text')),
    );
    expect(initialButton.onPressed, isNull);

    await tester.tap(find.byKey(const Key('normalize-page-page')));
    await tester.pumpAndSettle();
    expect(find.text('Vùng tài liệu'), findsOneWidget);

    await tester.tap(find.byKey(const Key('confirm-crop')));
    await tester.pumpAndSettle();
    await tester.fling(
      find.byType(Scrollable),
      const Offset(0, -800),
      1200,
    );
    await tester.pumpAndSettle();
    expect(find.text('Xoay ảnh'), findsOneWidget);
    await tester.tap(find.text('Xoay phải'));
    await tester.pumpAndSettle();
    final apply = tester.widget<FilledButton>(find.byKey(const Key('apply')));
    expect(apply.onPressed, isNotNull);
    apply.onPressed!();
    await tester.pumpAndSettle();

    expect(find.text('Đã lưu ảnh chuẩn hóa'), findsOneWidget);
    await tester.tap(find.text('Về tài liệu'));
    await tester.pumpAndSettle();
    expect(repository.saved?.rotationDegrees, 90);
    final readyButton = tester.widget<FilledButton>(
      find.byKey(const Key('recognize-text')),
    );
    expect(readyButton.onPressed, isNotNull);
  });

  testWidgets('overview supports narrow screen and 2x text', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final page = _page(status: PageNormalizationStatus.ready);
    await tester.pumpWidget(
      MaterialApp(
        theme: MemoTheme.light,
        darkTheme: MemoTheme.dark,
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(390, 844),
            textScaler: TextScaler.linear(2),
          ),
          child: PendingProcessingScreen(
            document: _document(
              page,
              status: ImportedDocumentStatus.pendingOcr,
            ),
            normalizationRepository: _FakeNormalizationRepository(
              _document(page, status: ImportedDocumentStatus.pendingOcr),
            ),
            engine: _FakeEngine(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Tài liệu đang chờ OCR'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

SourcePage _page({
  PageNormalizationStatus status = PageNormalizationStatus.pending,
}) => SourcePage(
  pageId: 'page',
  documentId: 'document',
  pageNumber: 1,
  originalPageNumber: 1,
  source: DocumentPageSource.gallery,
  dataRelativePath: 'documents/document/pages/page.png',
  absolutePath: 'missing-test-image.png',
  mimeType: 'image/png',
  fileSizeBytes: 100,
  width: 120,
  height: 180,
  sha256: 'source-hash',
  qualityCode: 'ok',
  qualityWarningAccepted: false,
  createdAt: DateTime(2026),
  normalizationStatus: status,
);

ImportedDocument _document(
  SourcePage page, {
  ImportedDocumentStatus status = ImportedDocumentStatus.pendingProcessing,
}) => ImportedDocument(
  documentId: 'document',
  title: 'Tài liệu kiểm thử',
  status: status,
  privacy: DocumentPrivacy.private,
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
  pages: [page],
);

class _FakeEngine implements ImageNormalizationEngine {
  final NormalizedRenderedImage image = _readableImage();

  @override
  Future<CropQuadrilateral?> detectCorners(String sourcePath) async =>
      const CropQuadrilateral.fullImage();

  @override
  Future<NormalizedRenderedImage> renderFullResolution(
    String sourcePath,
    NormalizationParameters parameters,
  ) async => image;

  @override
  Future<NormalizedRenderedImage> renderPreview(
    String sourcePath,
    NormalizationParameters parameters,
  ) async => image;
}

class _FakeInspector extends ImageInspector {
  @override
  Future<ImageInspection> inspect(Uint8List bytes) async =>
      const ImageInspection(
        mimeType: 'image/png',
        extension: 'png',
        width: 64,
        height: 64,
        fileSizeBytes: 100,
        sha256: 'preview',
        meanLuminance: 128,
        laplacianVariance: 500,
      );
}

class _FakeNormalizationRepository implements ImageNormalizationRepository {
  _FakeNormalizationRepository(this.document);

  ImportedDocument document;
  NormalizationParameters? saved;

  @override
  Future<void> ensureCapacityFor(SourcePage page) async {}

  @override
  Future<SourcePage?> getNextPendingPage(String documentId) async => null;

  @override
  Future<ImportedDocument> saveNormalizedPage({
    required SourcePage page,
    required NormalizationParameters parameters,
    required NormalizedRenderedImage image,
  }) async {
    saved = parameters;
    final readyPage = _page(status: PageNormalizationStatus.ready);
    document = _document(readyPage, status: ImportedDocumentStatus.pendingOcr);
    return document;
  }
}

NormalizedRenderedImage _readableImage() {
  final image = img.Image(width: 64, height: 64);
  for (var y = 0; y < image.height; y++) {
    for (var x = 0; x < image.width; x++) {
      final light = ((x ~/ 4) + (y ~/ 4)).isEven;
      image.setPixelRgb(
        x,
        y,
        light ? 240 : 20,
        light ? 240 : 20,
        light ? 240 : 20,
      );
    }
  }
  final bytes = Uint8List.fromList(img.encodePng(image));
  return NormalizedRenderedImage(bytes: bytes, width: 64, height: 64);
}

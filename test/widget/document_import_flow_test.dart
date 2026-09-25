import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:memo_mind/features/document_import/application/image_inspector.dart';
import 'package:memo_mind/features/document_import/data/gallery_image_picker.dart';
import 'package:memo_mind/features/document_import/domain/document_import_models.dart';
import 'package:memo_mind/features/document_import/domain/document_import_repository.dart';
import 'package:memo_mind/features/document_import/presentation/document_import_flow.dart';
import 'package:memo_mind/shared/theme/memo_theme.dart';

class _FakeGalleryPicker extends GalleryImagePicker {
  _FakeGalleryPicker(this.candidate);

  final ImageCandidate candidate;

  @override
  Future<ImageCandidate?> retrieveLostImage() async => null;

  @override
  Future<ImageCandidate?> pickImage() async => candidate;
}

class _FakeRepository implements DocumentImportRepository {
  ImportedDocument? document;

  @override
  Future<ImportedDocument> createWithFirstPage({
    required ImageCandidate candidate,
    required ImageInspection inspection,
    required bool qualityWarningAccepted,
  }) async {
    final now = DateTime(2026, 9, 25, 10, 30);
    document = ImportedDocument(
      documentId: 'document-1',
      title: 'Tài liệu 25-09-2026 10-30',
      status: ImportedDocumentStatus.pendingProcessing,
      privacy: DocumentPrivacy.private,
      createdAt: now,
      updatedAt: now,
      pages: [
        SourcePage(
          pageId: 'page-1',
          documentId: 'document-1',
          pageNumber: 1,
          source: candidate.source,
          originalRelativePath: 'documents/document-1/originals/page-1.jpg',
          absolutePath: 'missing-test-file.jpg',
          mimeType: inspection.mimeType,
          fileSizeBytes: inspection.fileSizeBytes,
          width: inspection.width,
          height: inspection.height,
          sha256: inspection.sha256,
          qualityCode: inspection.qualityCode,
          qualityWarningAccepted: qualityWarningAccepted,
          createdAt: now,
        ),
      ],
    );
    return document!;
  }

  @override
  Future<ImportedDocument> appendPage({
    required String documentId,
    required ImageCandidate candidate,
    required ImageInspection inspection,
    required bool qualityWarningAccepted,
  }) => throw UnimplementedError();

  @override
  Future<void> discardCandidate(ImageCandidate candidate) async {}

  @override
  Future<ImportedDocument> getDocument(String documentId) async => document!;

  @override
  Future<void> recoverInterruptedImports() async {}
}

class _FakeInspector extends ImageInspector {
  const _FakeInspector();

  @override
  Future<ImageInspection> inspect(Uint8List bytes) async => ImageInspection(
    mimeType: 'image/jpeg',
    extension: 'jpg',
    width: 64,
    height: 64,
    fileSizeBytes: bytes.length,
    sha256: 'test-hash',
    meanLuminance: 140,
    laplacianVariance: 500,
  );
}

ImageCandidate _candidate() {
  final image = img.Image(width: 64, height: 64);
  for (final pixel in image) {
    final value = ((pixel.x ~/ 4) + (pixel.y ~/ 4)).isEven ? 240 : 40;
    pixel
      ..r = value
      ..g = value
      ..b = value
      ..a = 255;
  }
  return ImageCandidate(
    bytes: Uint8List.fromList(img.encodeJpg(image)),
    source: DocumentImageSource.gallery,
    originalPath: 'selected.jpg',
  );
}

void main() {
  testWidgets('gallery preview saves a page and continues to pending screen', (
    tester,
  ) async {
    final repository = _FakeRepository();
    await tester.pumpWidget(
      MaterialApp(
        theme: MemoTheme.light,
        home: DocumentImportFlow(
          initialSource: DocumentImageSource.gallery,
          repository: repository,
          galleryPicker: _FakeGalleryPicker(_candidate()),
          inspector: const _FakeInspector(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Xem trước ảnh'), findsOneWidget);
    expect(find.text('Sử dụng ảnh'), findsOneWidget);
    await tester.tap(find.text('Sử dụng ảnh'));
    await tester.pumpAndSettle();

    if (find.text('Ảnh có thể khó nhận dạng').evaluate().isNotEmpty) {
      await tester.tap(find.text('Vẫn tiếp tục'));
      await tester.pumpAndSettle();
    }

    expect(find.text('1 trang · Chờ xử lý'), findsOneWidget);
    expect(find.text('Thêm trang'), findsOneWidget);
    await tester.tap(find.text('Tiếp tục'));
    await tester.pumpAndSettle();

    expect(find.text('Tài liệu đang chờ xử lý'), findsOneWidget);
    expect(find.textContaining('document-1'), findsOneWidget);
    expect(repository.document, isNotNull);
  });

  testWidgets(
    'import flow does not overflow on a narrow screen with large text',
    (tester) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          theme: MemoTheme.dark,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: DocumentImportFlow(
            initialSource: DocumentImageSource.gallery,
            repository: _FakeRepository(),
            galleryPicker: _FakeGalleryPicker(_candidate()),
            inspector: const _FakeInspector(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('Sử dụng ảnh'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
}

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:memo_mind/core/database/memo_mind_database.dart';
import 'package:memo_mind/features/document_import/data/local_document_import_repository_io.dart';
import 'package:memo_mind/features/document_import/domain/document_import_models.dart';
import 'package:memo_mind/features/image_normalization/application/image_normalization_engine.dart';
import 'package:memo_mind/features/image_normalization/data/local_image_normalization_repository_io.dart';
import 'package:memo_mind/features/image_normalization/domain/image_normalization_models.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  test('saves normalized copy and keeps source bytes unchanged', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);
    final sourceBefore = await fixture.source.readAsBytes();
    final page = (await fixture.documents.getDocument('document')).pages.single;

    final document = await fixture.normalizations.saveNormalizedPage(
      page: page,
      parameters: const NormalizationParameters(
        corners: CropQuadrilateral.fullImage(),
        rotationDegrees: 90,
        contrast: 0.2,
      ),
      image: _png(12, 18),
    );

    final saved = document.pages.single;
    expect(saved.normalizationStatus, PageNormalizationStatus.ready);
    expect(document.status, ImportedDocumentStatus.pendingOcr);
    expect(saved.normalizedAsset?.revision, 1);
    expect(saved.normalizedAsset?.parameters.rotationDegrees, 90);
    expect(await File(saved.displayPath).exists(), isTrue);
    expect(await fixture.source.readAsBytes(), sourceBefore);
  });

  test('failed replacement preserves the previous normalized asset', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);
    var page = (await fixture.documents.getDocument('document')).pages.single;
    await fixture.normalizations.saveNormalizedPage(
      page: page,
      parameters: const NormalizationParameters(
        corners: CropQuadrilateral.fullImage(),
      ),
      image: _png(10, 10),
    );
    page = (await fixture.documents.getDocument('document')).pages.single;
    final oldPath = page.normalizedAsset!.absolutePath;

    await expectLater(
      fixture.normalizations.saveNormalizedPage(
        page: page,
        parameters: const NormalizationParameters(
          corners: CropQuadrilateral.fullImage(),
        ),
        image: NormalizedRenderedImage(
          bytes: _png(1, 1).bytes,
          width: 0,
          height: 1,
        ),
      ),
      throwsA(isA<NormalizationFailure>()),
    );

    final recovered = (await fixture.documents.getDocument('document'))
        .pages
        .single;
    expect(recovered.normalizedAsset?.revision, 1);
    expect(recovered.normalizedAsset?.absolutePath, oldPath);
    expect(await File(oldPath).exists(), isTrue);
  });

  test('startup recovery removes staging and resets a missing result', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);
    final page = (await fixture.documents.getDocument('document')).pages.single;
    final saved = await fixture.normalizations.saveNormalizedPage(
      page: page,
      parameters: const NormalizationParameters(
        corners: CropQuadrilateral.fullImage(),
      ),
      image: _png(10, 10),
    );
    await File(saved.pages.single.normalizedAsset!.absolutePath).delete();
    final staging = File(
      '${fixture.support.path}/.staging/image_normalization/interrupted.partial',
    );
    final orphan = File(
      '${fixture.support.path}/documents/document/normalized/orphan.png',
    );
    await staging.parent.create(recursive: true);
    await orphan.parent.create(recursive: true);
    await staging.writeAsBytes([1]);
    await orphan.writeAsBytes([2]);

    await fixture.documents.recoverInterruptedImports();

    final recovered =
        (await fixture.documents.getDocument('document')).pages.single;
    expect(recovered.normalizationStatus, PageNormalizationStatus.pending);
    expect(recovered.normalizedAsset, isNull);
    expect(await staging.exists(), isFalse);
    expect(await orphan.exists(), isFalse);
    expect(await fixture.source.exists(), isTrue);
  });
}

NormalizedRenderedImage _png(int width, int height) {
  final image = img.Image(width: width, height: height)
    ..clear(img.ColorRgb8(240, 240, 240));
  final bytes = Uint8List.fromList(img.encodePng(image));
  return NormalizedRenderedImage(bytes: bytes, width: width, height: height);
}

class _Fixture {
  _Fixture({
    required this.db,
    required this.root,
    required this.support,
    required this.source,
    required this.documents,
    required this.normalizations,
  });

  final Database db;
  final Directory root;
  final Directory support;
  final File source;
  final LocalDocumentImportRepository documents;
  final LocalImageNormalizationRepository normalizations;

  static Future<_Fixture> create() async {
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await db.execute('PRAGMA foreign_keys = ON');
    await MemoMindDatabase.createV3(db);
    final root = await Directory.systemTemp.createTemp('memo-normalize-test-');
    final support = Directory('${root.path}/support');
    final cache = Directory('${root.path}/cache');
    final source = File('${support.path}/documents/document/pages/page.png');
    await source.parent.create(recursive: true);
    final sourceBytes = _png(20, 30).bytes;
    await source.writeAsBytes(sourceBytes);
    await db.insert('documents', {
      'document_id': 'document',
      'title': 'Tài liệu',
      'status': 'pending_processing',
      'privacy': 'private',
      'page_count': 1,
      'created_at': 1,
      'updated_at': 1,
    });
    await db.insert('source_pages', {
      'page_id': 'page',
      'document_id': 'document',
      'page_number': 1,
      'original_page_number': 1,
      'source': 'gallery',
      'data_relative_path': 'documents/document/pages/page.png',
      'mime_type': 'image/png',
      'file_size_bytes': sourceBytes.length,
      'width': 20,
      'height': 30,
      'sha256': 'source-hash',
      'quality_code': 'ok',
      'quality_warning_accepted': 0,
      'created_at': 1,
      'normalization_status': 'pending',
    });
    final database = MemoMindDatabase.forTesting(db);
    final documents = LocalDocumentImportRepository(
      database: database,
      supportDirectory: () async => support,
      temporaryDirectory: () async => cache,
      availableBytes: (_) async => 1024 * 1024 * 1024,
    );
    final normalizations = LocalImageNormalizationRepository(
      documentRepository: documents,
      database: database,
      supportDirectory: () async => support,
      availableBytes: (_) async => 1024 * 1024 * 1024,
    );
    return _Fixture(
      db: db,
      root: root,
      support: support,
      source: source,
      documents: documents,
      normalizations: normalizations,
    );
  }

  Future<void> dispose() async {
    await db.close();
    if (await root.exists()) await root.delete(recursive: true);
  }
}

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:memo_mind/core/database/memo_mind_database.dart';
import 'package:memo_mind/features/document_import/data/local_document_import_repository_io.dart';
import 'package:memo_mind/features/document_import/domain/document_import_models.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  test(
    'PDF import stores original and selected pages in source order',
    () async {
      final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
      await db.execute('PRAGMA foreign_keys = ON');
      await MemoMindDatabase.createV2(db);
      final root = await Directory.systemTemp.createTemp('memo-mind-pdf-test-');
      final support = Directory('${root.path}/support');
      final cache = Directory('${root.path}/cache');
      addTearDown(() async {
        await db.close();
        if (await root.exists()) await root.delete(recursive: true);
      });
      final pdf = File('${cache.path}/operation/selected.pdf');
      final pageTwo = File('${cache.path}/operation/rendered/page-2.png');
      final pageSeven = File('${cache.path}/operation/rendered/page-7.png');
      await pdf.parent.create(recursive: true);
      await pageTwo.parent.create(recursive: true);
      await pdf.writeAsBytes([37, 80, 68, 70, 45, 49]);
      await pageTwo.writeAsBytes([1, 2, 3]);
      await pageSeven.writeAsBytes([4, 5, 6]);
      final repository = LocalDocumentImportRepository(
        database: MemoMindDatabase.forTesting(db),
        supportDirectory: () async => support,
        temporaryDirectory: () async => cache,
        availableBytes: (_) async => 1024 * 1024 * 1024,
      );

      final document = await repository.createFromPdf(
        candidate: PdfCandidate(
          temporaryPath: pdf.path,
          originalName: 'Bài giảng.pdf',
          fileSizeBytes: 6,
          sha256: 'pdf-hash',
          ownsTemporaryFile: false,
        ),
        pages: [
          RenderedPdfPage(
            originalPageNumber: 7,
            temporaryPath: pageSeven.path,
            fileSizeBytes: 3,
            width: 20,
            height: 30,
            sha256: 'seven',
          ),
          RenderedPdfPage(
            originalPageNumber: 2,
            temporaryPath: pageTwo.path,
            fileSizeBytes: 3,
            width: 20,
            height: 30,
            sha256: 'two',
          ),
        ],
      );

      expect(document.title, 'Bài giảng');
      expect(document.status, ImportedDocumentStatus.pendingOcr);
      expect(document.pages.map((page) => page.pageNumber), [1, 2]);
      expect(document.pages.map((page) => page.originalPageNumber), [2, 7]);
      expect(await File(document.originalFile!.absolutePath).readAsBytes(), [
        37,
        80,
        68,
        70,
        45,
        49,
      ]);
      expect(
        document.pages.every((page) => File(page.absolutePath).existsSync()),
        isTrue,
      );
    },
  );

  test('database failure removes copied PDF files and document row', () async {
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await db.execute('PRAGMA foreign_keys = ON');
    await MemoMindDatabase.createV2(db);
    final root = await Directory.systemTemp.createTemp(
      'memo-mind-rollback-test-',
    );
    final support = Directory('${root.path}/support');
    final cache = Directory('${root.path}/cache');
    addTearDown(() async {
      await db.close();
      if (await root.exists()) await root.delete(recursive: true);
    });
    final pdf = File('${cache.path}/operation/selected.pdf');
    final page = File('${cache.path}/operation/rendered/page.png');
    await page.parent.create(recursive: true);
    await pdf.writeAsBytes([37, 80, 68, 70, 45]);
    await page.writeAsBytes([1]);
    final repository = LocalDocumentImportRepository(
      database: MemoMindDatabase.forTesting(db),
      supportDirectory: () async => support,
      temporaryDirectory: () async => cache,
      availableBytes: (_) async => 1024 * 1024 * 1024,
    );

    await expectLater(
      repository.createFromPdf(
        candidate: PdfCandidate(
          temporaryPath: pdf.path,
          originalName: 'Lỗi.pdf',
          fileSizeBytes: 5,
          sha256: 'pdf-hash',
          ownsTemporaryFile: false,
        ),
        pages: [
          RenderedPdfPage(
            originalPageNumber: 1,
            temporaryPath: page.path,
            fileSizeBytes: 0,
            width: 10,
            height: 10,
            sha256: 'page-hash',
          ),
        ],
      ),
      throwsA(
        isA<ImportFailure>().having(
          (failure) => failure.code,
          'code',
          ImportFailureCode.saveFailed,
        ),
      ),
    );

    expect(await db.query('documents'), isEmpty);
    final documentsDirectory = Directory('${support.path}/documents');
    final remaining = await documentsDirectory.exists()
        ? await documentsDirectory
              .list(recursive: true)
              .where((item) => item is File)
              .toList()
        : <FileSystemEntity>[];
    expect(remaining, isEmpty);
  });
}

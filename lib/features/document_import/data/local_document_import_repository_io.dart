import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/memo_mind_database.dart';
import '../domain/document_import_models.dart';
import '../domain/document_import_repository.dart';

class LocalDocumentImportRepository implements DocumentImportRepository {
  LocalDocumentImportRepository({
    MemoMindDatabase? database,
    Uuid? uuid,
    DateTime Function()? clock,
  }) : _database = database ?? MemoMindDatabase.instance,
       _uuid = uuid ?? const Uuid(),
       _clock = clock ?? DateTime.now;

  static const _storageChannel = MethodChannel('memo_mind/storage');
  static const _reserveBytes = 10 * 1024 * 1024;

  final MemoMindDatabase _database;
  final Uuid _uuid;
  final DateTime Function() _clock;

  @override
  Future<ImportedDocument> createWithFirstPage({
    required ImageCandidate candidate,
    required ImageInspection inspection,
    required bool qualityWarningAccepted,
  }) async {
    final now = _clock();
    final documentId = _uuid.v4();
    await _persistPage(
      documentId: documentId,
      pageNumber: 1,
      candidate: candidate,
      inspection: inspection,
      qualityWarningAccepted: qualityWarningAccepted,
      createDocument: true,
      now: now,
    );
    return getDocument(documentId);
  }

  @override
  Future<ImportedDocument> appendPage({
    required String documentId,
    required ImageCandidate candidate,
    required ImageInspection inspection,
    required bool qualityWarningAccepted,
  }) async {
    final db = await _database.database;
    final rows = await db.query(
      'documents',
      columns: ['document_id'],
      where: 'document_id = ?',
      whereArgs: [documentId],
      limit: 1,
    );
    if (rows.isEmpty) {
      throw const ImportFailure(
        ImportFailureCode.notFound,
        'Không tìm thấy tài liệu để thêm trang.',
      );
    }
    final value = Sqflite.firstIntValue(
      await db.rawQuery(
        'SELECT MAX(page_number) FROM source_pages WHERE document_id = ?',
        [documentId],
      ),
    );
    await _persistPage(
      documentId: documentId,
      pageNumber: (value ?? 0) + 1,
      candidate: candidate,
      inspection: inspection,
      qualityWarningAccepted: qualityWarningAccepted,
      createDocument: false,
      now: _clock(),
    );
    return getDocument(documentId);
  }

  Future<void> _persistPage({
    required String documentId,
    required int pageNumber,
    required ImageCandidate candidate,
    required ImageInspection inspection,
    required bool qualityWarningAccepted,
    required bool createDocument,
    required DateTime now,
  }) async {
    final support = await getApplicationSupportDirectory();
    await support.create(recursive: true);
    await _ensureCapacity(support.path, inspection.fileSizeBytes);

    final pageId = _uuid.v4();
    final relativePath = p
        .join(
          'documents',
          documentId,
          'originals',
          '$pageId.${inspection.extension}',
        )
        .replaceAll('\\', '/');
    final finalFile = File(
      p.joinAll([support.path, ...relativePath.split('/')]),
    );
    final cache = await getTemporaryDirectory();
    final stagingDirectory = Directory(
      p.join(cache.path, 'document_import', documentId),
    );
    final stagingFile = File(p.join(stagingDirectory.path, '$pageId.partial'));

    try {
      await stagingDirectory.create(recursive: true);
      await stagingFile.writeAsBytes(candidate.bytes, flush: true);
      await finalFile.parent.create(recursive: true);
      await stagingFile.rename(finalFile.path);

      final db = await _database.database;
      await db.transaction((txn) async {
        if (createDocument) {
          await txn.insert('documents', {
            'document_id': documentId,
            'title': _defaultTitle(now),
            'status': 'pending_processing',
            'privacy': 'private',
            'page_count': 0,
            'created_at': now.millisecondsSinceEpoch,
            'updated_at': now.millisecondsSinceEpoch,
          });
        }
        await txn.insert('source_pages', {
          'page_id': pageId,
          'document_id': documentId,
          'page_number': pageNumber,
          'source': candidate.source.name,
          'original_relative_path': relativePath,
          'mime_type': inspection.mimeType,
          'file_size_bytes': inspection.fileSizeBytes,
          'width': inspection.width,
          'height': inspection.height,
          'sha256': inspection.sha256,
          'quality_code': inspection.qualityCode,
          'quality_warning_accepted': qualityWarningAccepted ? 1 : 0,
          'created_at': now.millisecondsSinceEpoch,
        });
        await txn.rawUpdate(
          'UPDATE documents SET page_count = page_count + 1, updated_at = ? '
          'WHERE document_id = ?',
          [now.millisecondsSinceEpoch, documentId],
        );
      });
      await discardCandidate(candidate);
      await _deleteIfEmpty(stagingDirectory);
    } on ImportFailure {
      rethrow;
    } catch (error) {
      await _deleteFile(stagingFile);
      await _deleteFile(finalFile);
      if (createDocument) {
        final db = await _database.database;
        await db.delete(
          'documents',
          where: 'document_id = ?',
          whereArgs: [documentId],
        );
      }
      throw ImportFailure(
        ImportFailureCode.saveFailed,
        'Không thể lưu ảnh. Vui lòng thử lại.',
        error,
      );
    }
  }

  Future<void> _ensureCapacity(String path, int requiredBytes) async {
    try {
      final available = await _storageChannel.invokeMethod<int>(
        'getAvailableBytes',
        {'path': path},
      );
      if (available != null && available < requiredBytes + _reserveBytes) {
        throw const ImportFailure(
          ImportFailureCode.insufficientStorage,
          'Thiết bị không đủ dung lượng. Vui lòng giải phóng bộ nhớ và thử lại.',
        );
      }
    } on MissingPluginException {
      // The actual write remains the final authority in unit-test hosts.
    } on PlatformException catch (error) {
      throw ImportFailure(
        ImportFailureCode.saveFailed,
        'Không thể kiểm tra dung lượng lưu trữ.',
        error,
      );
    }
  }

  @override
  Future<ImportedDocument> getDocument(String documentId) async {
    final db = await _database.database;
    final documents = await db.query(
      'documents',
      where: 'document_id = ?',
      whereArgs: [documentId],
      limit: 1,
    );
    if (documents.isEmpty) {
      throw const ImportFailure(
        ImportFailureCode.notFound,
        'Không tìm thấy tài liệu.',
      );
    }
    final support = await getApplicationSupportDirectory();
    final pages = await db.query(
      'source_pages',
      where: 'document_id = ?',
      whereArgs: [documentId],
      orderBy: 'page_number ASC',
    );
    final row = documents.single;
    return ImportedDocument(
      documentId: row['document_id']! as String,
      title: row['title']! as String,
      status: ImportedDocumentStatus.pendingProcessing,
      privacy: DocumentPrivacy.private,
      createdAt: DateTime.fromMillisecondsSinceEpoch(row['created_at']! as int),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(row['updated_at']! as int),
      pages: pages.map((page) => _mapPage(page, support.path)).toList(),
    );
  }

  SourcePage _mapPage(Map<String, Object?> row, String supportPath) {
    final relativePath = row['original_relative_path']! as String;
    return SourcePage(
      pageId: row['page_id']! as String,
      documentId: row['document_id']! as String,
      pageNumber: row['page_number']! as int,
      source: DocumentImageSource.values.byName(row['source']! as String),
      originalRelativePath: relativePath,
      absolutePath: p.joinAll([supportPath, ...relativePath.split('/')]),
      mimeType: row['mime_type']! as String,
      fileSizeBytes: row['file_size_bytes']! as int,
      width: row['width']! as int,
      height: row['height']! as int,
      sha256: row['sha256']! as String,
      qualityCode: row['quality_code']! as String,
      qualityWarningAccepted: (row['quality_warning_accepted']! as int) == 1,
      createdAt: DateTime.fromMillisecondsSinceEpoch(row['created_at']! as int),
    );
  }

  @override
  Future<void> recoverInterruptedImports() async {
    final cache = await getTemporaryDirectory();
    final staging = Directory(p.join(cache.path, 'document_import'));
    if (await staging.exists()) await staging.delete(recursive: true);

    final support = await getApplicationSupportDirectory();
    final db = await _database.database;
    final pages = await db.query(
      'source_pages',
      columns: ['page_id', 'document_id', 'original_relative_path'],
    );
    final referenced = <String>{};
    await db.transaction((txn) async {
      for (final page in pages) {
        final relative = page['original_relative_path']! as String;
        final file = File(p.joinAll([support.path, ...relative.split('/')]));
        if (await file.exists()) {
          referenced.add(p.normalize(file.path));
        } else {
          await txn.delete(
            'source_pages',
            where: 'page_id = ?',
            whereArgs: [page['page_id']],
          );
        }
      }
      await txn.rawUpdate('''
        UPDATE documents
        SET page_count = (
          SELECT COUNT(*) FROM source_pages
          WHERE source_pages.document_id = documents.document_id
        )
      ''');
      await txn.delete('documents', where: 'page_count = 0');
    });

    final originalsRoot = Directory(p.join(support.path, 'documents'));
    if (await originalsRoot.exists()) {
      await for (final entity in originalsRoot.list(recursive: true)) {
        if (entity is File && !referenced.contains(p.normalize(entity.path))) {
          await _deleteFile(entity);
        }
      }
    }
  }

  @override
  Future<void> discardCandidate(ImageCandidate candidate) async {
    if (!candidate.ownsTemporaryFile || candidate.originalPath.isEmpty) return;
    await _deleteFile(File(candidate.originalPath));
  }

  String _defaultTitle(DateTime time) {
    String two(int value) => value.toString().padLeft(2, '0');
    return 'Tài liệu ${two(time.day)}-${two(time.month)}-${time.year} '
        '${two(time.hour)}-${two(time.minute)}';
  }

  Future<void> _deleteFile(File file) async {
    try {
      if (await file.exists()) await file.delete();
    } on FileSystemException {
      // Recovery will retry on the next application launch.
    }
  }

  Future<void> _deleteIfEmpty(Directory directory) async {
    try {
      if (await directory.exists() && await directory.list().isEmpty) {
        await directory.delete();
      }
    } on FileSystemException {
      // Non-critical cleanup.
    }
  }
}

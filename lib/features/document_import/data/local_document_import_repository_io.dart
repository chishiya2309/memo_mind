import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/memo_mind_database.dart';
import '../domain/document_import_models.dart';
import '../domain/document_import_repository.dart';

typedef DirectoryProvider = Future<Directory> Function();
typedef AvailableBytesProvider = Future<int?> Function(String path);

class LocalDocumentImportRepository
    implements DocumentImportRepository, PdfImportRepository {
  LocalDocumentImportRepository({
    MemoMindDatabase? database,
    Uuid? uuid,
    DateTime Function()? clock,
    DirectoryProvider? supportDirectory,
    DirectoryProvider? temporaryDirectory,
    this.availableBytes,
  }) : _database = database ?? MemoMindDatabase.instance,
       _uuid = uuid ?? const Uuid(),
       _clock = clock ?? DateTime.now,
       _supportDirectory = supportDirectory ?? getApplicationSupportDirectory,
       _temporaryDirectory = temporaryDirectory ?? getTemporaryDirectory;

  static const _storageChannel = MethodChannel('memo_mind/storage');
  static const _reserveBytes = 10 * 1024 * 1024;

  final MemoMindDatabase _database;
  final Uuid _uuid;
  final DateTime Function() _clock;
  final DirectoryProvider _supportDirectory;
  final DirectoryProvider _temporaryDirectory;
  final AvailableBytesProvider? availableBytes;

  @override
  Future<ImportedDocument> createWithFirstPage({
    required ImageCandidate candidate,
    required ImageInspection inspection,
    required bool qualityWarningAccepted,
  }) async {
    final now = _clock();
    final documentId = _uuid.v4();
    await _persistImagePage(
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
    await _persistImagePage(
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

  Future<void> _persistImagePage({
    required String documentId,
    required int pageNumber,
    required ImageCandidate candidate,
    required ImageInspection inspection,
    required bool qualityWarningAccepted,
    required bool createDocument,
    required DateTime now,
  }) async {
    final support = await _supportDirectory();
    await support.create(recursive: true);
    await _ensureCapacity(support.path, inspection.fileSizeBytes);

    final pageId = _uuid.v4();
    final relativePath = p
        .join(
          'documents',
          documentId,
          'pages',
          '$pageId.${inspection.extension}',
        )
        .replaceAll('\\', '/');
    final finalFile = _resolveRelative(support.path, relativePath);
    final cache = await _temporaryDirectory();
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
          'original_page_number': pageNumber,
          'source': _pageSource(candidate.source).name,
          'data_relative_path': relativePath,
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

  @override
  Future<ImportedDocument> createFromPdf({
    required PdfCandidate candidate,
    required List<RenderedPdfPage> pages,
  }) async {
    final ordered = [...pages]
      ..sort(
        (left, right) =>
            left.originalPageNumber.compareTo(right.originalPageNumber),
      );
    final pageNumbers = ordered.map((page) => page.originalPageNumber).toSet();
    if (ordered.isEmpty ||
        ordered.length > 10 ||
        pageNumbers.length != ordered.length) {
      throw const ImportFailure(
        ImportFailureCode.saveFailed,
        'Danh sách trang PDF không hợp lệ.',
      );
    }

    final original = File(candidate.temporaryPath);
    if (!await original.exists()) {
      throw const ImportFailure(
        ImportFailureCode.notFound,
        'Không tìm thấy tệp đã chọn.',
      );
    }
    for (final page in ordered) {
      if (!await File(page.temporaryPath).exists()) {
        throw ImportFailure(
          ImportFailureCode.pageRenderFailed,
          'Không thể tạo dữ liệu cho trang ${page.originalPageNumber}.',
        );
      }
    }

    final support = await _supportDirectory();
    await support.create(recursive: true);
    final requiredBytes =
        candidate.fileSizeBytes +
        ordered.fold<int>(0, (total, page) => total + page.fileSizeBytes);
    await _ensureCapacity(support.path, requiredBytes);

    final documentId = _uuid.v4();
    final now = _clock();
    final documentDirectory = Directory(
      p.join(support.path, 'documents', documentId),
    );
    final originalRelativePath = p
        .join('documents', documentId, 'originals', 'original.pdf')
        .replaceAll('\\', '/');
    final originalFinal = _resolveRelative(support.path, originalRelativePath);
    try {
      await originalFinal.parent.create(recursive: true);
      await original.copy(originalFinal.path);

      final storedPages =
          <({RenderedPdfPage page, String pageId, String path})>[];
      for (final page in ordered) {
        final pageId = _uuid.v4();
        final relativePath = p
            .join('documents', documentId, 'pages', '$pageId.png')
            .replaceAll('\\', '/');
        final destination = _resolveRelative(support.path, relativePath);
        await destination.parent.create(recursive: true);
        await File(page.temporaryPath).copy(destination.path);
        storedPages.add((page: page, pageId: pageId, path: relativePath));
      }

      final db = await _database.database;
      await db.transaction((txn) async {
        await txn.insert('documents', {
          'document_id': documentId,
          'title': _pdfTitle(candidate.originalName),
          'status': 'pending_ocr',
          'privacy': 'private',
          'page_count': storedPages.length,
          'original_file_name': candidate.originalName,
          'original_file_relative_path': originalRelativePath,
          'original_file_mime_type': 'application/pdf',
          'original_file_size_bytes': candidate.fileSizeBytes,
          'original_file_sha256': candidate.sha256,
          'created_at': now.millisecondsSinceEpoch,
          'updated_at': now.millisecondsSinceEpoch,
        });
        for (var index = 0; index < storedPages.length; index++) {
          final stored = storedPages[index];
          await txn.insert('source_pages', {
            'page_id': stored.pageId,
            'document_id': documentId,
            'page_number': index + 1,
            'original_page_number': stored.page.originalPageNumber,
            'source': DocumentPageSource.pdf.name,
            'data_relative_path': stored.path,
            'mime_type': 'image/png',
            'file_size_bytes': stored.page.fileSizeBytes,
            'width': stored.page.width,
            'height': stored.page.height,
            'sha256': stored.page.sha256,
            'quality_code': 'not_inspected',
            'quality_warning_accepted': 0,
            'created_at': now.millisecondsSinceEpoch,
          });
        }
      });

      await discardPdfCandidate(candidate);
      for (final page in ordered) {
        await _deleteFile(File(page.temporaryPath));
      }
      return await getDocument(documentId);
    } on ImportFailure {
      await _deleteDirectory(documentDirectory);
      rethrow;
    } catch (error) {
      final db = await _database.database;
      await db.delete(
        'documents',
        where: 'document_id = ?',
        whereArgs: [documentId],
      );
      await _deleteDirectory(documentDirectory);
      throw ImportFailure(
        ImportFailureCode.saveFailed,
        'Không thể lưu tài liệu. Vui lòng thử lại.',
        error,
      );
    }
  }

  Future<void> _ensureCapacity(String path, int requiredBytes) async {
    try {
      final available = availableBytes != null
          ? await availableBytes!(path)
          : await _storageChannel.invokeMethod<int>('getAvailableBytes', {
              'path': path,
            });
      if (available != null && available < requiredBytes + _reserveBytes) {
        throw const ImportFailure(
          ImportFailureCode.insufficientStorage,
          'Thiết bị không đủ dung lượng. Vui lòng giải phóng bộ nhớ và thử lại.',
        );
      }
    } on MissingPluginException {
      // The actual write remains the final authority in test hosts.
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
    final support = await _supportDirectory();
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
      status: _status(row['status']! as String),
      privacy: DocumentPrivacy.private,
      createdAt: DateTime.fromMillisecondsSinceEpoch(row['created_at']! as int),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(row['updated_at']! as int),
      pages: pages.map((page) => _mapPage(page, support.path)).toList(),
      originalFile: _mapOriginal(row, support.path),
    );
  }

  SourcePage _mapPage(Map<String, Object?> row, String supportPath) {
    final relativePath = row['data_relative_path']! as String;
    return SourcePage(
      pageId: row['page_id']! as String,
      documentId: row['document_id']! as String,
      pageNumber: row['page_number']! as int,
      originalPageNumber: row['original_page_number']! as int,
      source: DocumentPageSource.values.byName(row['source']! as String),
      dataRelativePath: relativePath,
      absolutePath: _resolveRelative(supportPath, relativePath).path,
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

  OriginalDocumentFile? _mapOriginal(
    Map<String, Object?> row,
    String supportPath,
  ) {
    final relativePath = row['original_file_relative_path'] as String?;
    if (relativePath == null) return null;
    return OriginalDocumentFile(
      name: row['original_file_name']! as String,
      relativePath: relativePath,
      absolutePath: _resolveRelative(supportPath, relativePath).path,
      mimeType: row['original_file_mime_type']! as String,
      fileSizeBytes: row['original_file_size_bytes']! as int,
      sha256: row['original_file_sha256']! as String,
    );
  }

  @override
  Future<void> recoverInterruptedImports() async {
    final cache = await _temporaryDirectory();
    await _deleteDirectory(Directory(p.join(cache.path, 'document_import')));

    final support = await _supportDirectory();
    final db = await _database.database;
    final documentRows = await db.query('documents');
    final pageRows = await db.query('source_pages');
    final documents = {
      for (final row in documentRows) row['document_id']! as String: row,
    };
    final invalidPdfDocuments = <String>{};
    final missingImagePages = <String>[];
    for (final entry in documents.entries) {
      final relative = entry.value['original_file_relative_path'] as String?;
      if (relative == null) continue;
      final file = _resolveRelative(support.path, relative);
      if (!await file.exists()) {
        invalidPdfDocuments.add(entry.key);
      }
    }

    for (final page in pageRows) {
      final documentId = page['document_id']! as String;
      final relative = page['data_relative_path']! as String;
      final file = _resolveRelative(support.path, relative);
      if (!await file.exists() &&
          documents[documentId]?['original_file_relative_path'] != null) {
        invalidPdfDocuments.add(documentId);
      } else if (!await file.exists()) {
        missingImagePages.add(page['page_id']! as String);
      }
    }

    await db.transaction((txn) async {
      for (final pageId in missingImagePages) {
        await txn.delete(
          'source_pages',
          where: 'page_id = ?',
          whereArgs: [pageId],
        );
      }
      for (final documentId in invalidPdfDocuments) {
        await txn.delete(
          'documents',
          where: 'document_id = ?',
          whereArgs: [documentId],
        );
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

    final referenced = <String>{};
    final remainingDocuments = await db.query(
      'documents',
      columns: ['original_file_relative_path'],
    );
    final remainingPages = await db.query(
      'source_pages',
      columns: ['data_relative_path'],
    );
    for (final row in remainingDocuments) {
      final relative = row['original_file_relative_path'] as String?;
      if (relative != null) {
        referenced.add(
          p.normalize(_resolveRelative(support.path, relative).path),
        );
      }
    }
    for (final row in remainingPages) {
      final relative = row['data_relative_path']! as String;
      referenced.add(
        p.normalize(_resolveRelative(support.path, relative).path),
      );
    }

    final documentsRoot = Directory(p.join(support.path, 'documents'));
    if (await documentsRoot.exists()) {
      await for (final entity in documentsRoot.list(recursive: true)) {
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

  @override
  Future<void> discardPdfCandidate(PdfCandidate candidate) async {
    if (!candidate.ownsTemporaryFile || candidate.temporaryPath.isEmpty) return;
    await _deleteDirectory(File(candidate.temporaryPath).parent);
  }

  DocumentPageSource _pageSource(DocumentImageSource source) =>
      switch (source) {
        DocumentImageSource.camera => DocumentPageSource.camera,
        DocumentImageSource.gallery => DocumentPageSource.gallery,
      };

  ImportedDocumentStatus _status(String value) => switch (value) {
    'pending_ocr' => ImportedDocumentStatus.pendingOcr,
    _ => ImportedDocumentStatus.pendingProcessing,
  };

  String _pdfTitle(String fileName) {
    final extension = p.extension(fileName);
    final title = extension.toLowerCase() == '.pdf'
        ? fileName.substring(0, fileName.length - extension.length).trim()
        : fileName.trim();
    return title.isEmpty ? _defaultTitle(_clock()) : title;
  }

  String _defaultTitle(DateTime time) {
    String two(int value) => value.toString().padLeft(2, '0');
    return 'Tài liệu ${two(time.day)}-${two(time.month)}-${time.year} '
        '${two(time.hour)}-${two(time.minute)}';
  }

  File _resolveRelative(String root, String relativePath) =>
      File(p.joinAll([root, ...relativePath.split('/')]));

  Future<void> _deleteFile(File file) async {
    try {
      if (await file.exists()) await file.delete();
    } on FileSystemException {
      // Recovery will retry on the next application launch.
    }
  }

  Future<void> _deleteDirectory(Directory directory) async {
    try {
      if (await directory.exists()) await directory.delete(recursive: true);
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

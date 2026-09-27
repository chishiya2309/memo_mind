import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/memo_mind_database.dart';
import '../../document_import/domain/document_import_models.dart';
import '../../document_import/domain/document_import_repository.dart';
import '../application/image_normalization_engine.dart';
import '../domain/image_normalization_models.dart';
import '../domain/image_normalization_repository.dart';

typedef NormalizationDirectoryProvider = Future<Directory> Function();
typedef NormalizationAvailableBytesProvider = Future<int?> Function(
  String path,
);

class LocalImageNormalizationRepository
    implements ImageNormalizationRepository {
  LocalImageNormalizationRepository({
    required this.documentRepository,
    MemoMindDatabase? database,
    Uuid? uuid,
    DateTime Function()? clock,
    NormalizationDirectoryProvider? supportDirectory,
    this.availableBytes,
  }) : _database = database ?? MemoMindDatabase.instance,
       _uuid = uuid ?? const Uuid(),
       _clock = clock ?? DateTime.now,
       _supportDirectory = supportDirectory ?? getApplicationSupportDirectory;

  static const _storageChannel = MethodChannel('memo_mind/storage');
  static const _reserveBytes = 10 * 1024 * 1024;

  final DocumentImportRepository documentRepository;
  final MemoMindDatabase _database;
  final Uuid _uuid;
  final DateTime Function() _clock;
  final NormalizationDirectoryProvider _supportDirectory;
  final NormalizationAvailableBytesProvider? availableBytes;

  @override
  Future<void> ensureCapacityFor(SourcePage page) async {
    final support = await _supportDirectory();
    await support.create(recursive: true);
    final estimated = page.width * page.height * 4;
    try {
      final available = availableBytes != null
          ? await availableBytes!(support.path)
          : await _storageChannel.invokeMethod<int>('getAvailableBytes', {
              'path': support.path,
            });
      if (available != null && available < estimated + _reserveBytes) {
        throw const NormalizationFailure(
          NormalizationFailureCode.insufficientStorage,
          'Thiết bị không đủ dung lượng. Vui lòng giải phóng bộ nhớ và thử lại.',
        );
      }
    } on MissingPluginException {
      // The write is authoritative on hosts without the Android channel.
    } on PlatformException catch (error) {
      throw NormalizationFailure(
        NormalizationFailureCode.saveFailed,
        'Không thể kiểm tra dung lượng lưu trữ.',
        error,
      );
    }
  }

  @override
  Future<ImportedDocument> saveNormalizedPage({
    required SourcePage page,
    required NormalizationParameters parameters,
    required NormalizedRenderedImage image,
  }) async {
    if (!parameters.isValid) {
      throw const NormalizationFailure(
        NormalizationFailureCode.invalidCrop,
        'Vùng cắt không hợp lệ. Vui lòng điều chỉnh lại bốn góc.',
      );
    }
    await ensureCapacityFor(page);
    final decodedSize = await Isolate.run(() {
      final decoded = img.decodePng(image.bytes);
      return decoded == null ? null : (decoded.width, decoded.height);
    });
    if (decodedSize == null ||
        decodedSize.$1 != image.width ||
        decodedSize.$2 != image.height) {
      throw const NormalizationFailure(
        NormalizationFailureCode.processingFailed,
        'Không thể tạo ảnh chuẩn hóa.',
      );
    }
    final support = await _supportDirectory();
    await support.create(recursive: true);
    final db = await _database.database;
    final existing = await db.query(
      'page_normalizations',
      where: 'page_id = ?',
      whereArgs: [page.pageId],
      limit: 1,
    );
    final oldPath = existing.isEmpty
        ? null
        : existing.single['normalized_relative_path']! as String;
    final revision = existing.isEmpty
        ? 1
        : (existing.single['revision']! as int) + 1;
    final token = _uuid.v4();
    final staging = File(
      p.join(support.path, '.staging', 'image_normalization', '$token.partial'),
    );
    final relativePath = p
        .join(
          'documents',
          page.documentId,
          'normalized',
          '${page.pageId}-$revision.png',
        )
        .replaceAll('\\', '/');
    final destination = _resolveRelative(support.path, relativePath);
    final now = _clock();

    try {
      await staging.parent.create(recursive: true);
      await staging.writeAsBytes(image.bytes, flush: true);
      await destination.parent.create(recursive: true);
      await staging.rename(destination.path);
      final hash = sha256.convert(image.bytes).toString();
      final values = <String, Object?>{
        'page_id': page.pageId,
        'revision': revision,
        'normalized_relative_path': relativePath,
        'mime_type': 'image/png',
        'file_size_bytes': image.bytes.length,
        'width': image.width,
        'height': image.height,
        'sha256': hash,
        'top_left_x': parameters.corners.topLeft.x,
        'top_left_y': parameters.corners.topLeft.y,
        'top_right_x': parameters.corners.topRight.x,
        'top_right_y': parameters.corners.topRight.y,
        'bottom_right_x': parameters.corners.bottomRight.x,
        'bottom_right_y': parameters.corners.bottomRight.y,
        'bottom_left_x': parameters.corners.bottomLeft.x,
        'bottom_left_y': parameters.corners.bottomLeft.y,
        'rotation_degrees': parameters.rotationDegrees,
        'contrast': parameters.contrast,
        'updated_at': now.millisecondsSinceEpoch,
      };
      await db.transaction((txn) async {
        await txn.insert(
          'page_normalizations',
          values,
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        await txn.update(
          'source_pages',
          {'normalization_status': 'ready'},
          where: 'page_id = ?',
          whereArgs: [page.pageId],
        );
        final pending = Sqflite.firstIntValue(
          await txn.rawQuery(
            "SELECT COUNT(*) FROM source_pages WHERE document_id = ? AND normalization_status = 'pending'",
            [page.documentId],
          ),
        );
        await txn.update(
          'documents',
          {
            'status': (pending ?? 0) == 0
                ? 'pending_ocr'
                : 'pending_processing',
            'updated_at': now.millisecondsSinceEpoch,
          },
          where: 'document_id = ?',
          whereArgs: [page.documentId],
        );
      });
      if (oldPath != null && oldPath != relativePath) {
        await _deleteFile(_resolveRelative(support.path, oldPath));
      }
      return await documentRepository.getDocument(page.documentId);
    } on NormalizationFailure {
      rethrow;
    } catch (error) {
      await _deleteFile(staging);
      await _deleteFile(destination);
      throw NormalizationFailure(
        NormalizationFailureCode.saveFailed,
        'Không thể lưu ảnh đã chỉnh sửa. Vui lòng thử lại.',
        error,
      );
    }
  }

  @override
  Future<SourcePage?> getNextPendingPage(String documentId) async {
    final document = await documentRepository.getDocument(documentId);
    for (final page in document.pages) {
      if (page.normalizationStatus == PageNormalizationStatus.pending) {
        return page;
      }
    }
    return null;
  }

  File _resolveRelative(String root, String relativePath) =>
      File(p.joinAll([root, ...relativePath.split('/')]));

  Future<void> _deleteFile(File file) async {
    try {
      if (await file.exists()) await file.delete();
    } on FileSystemException {
      // Startup recovery removes unreferenced files.
    }
  }
}

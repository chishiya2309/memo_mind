import '../../../core/workspace/workspace_context.dart';

import 'dart:io';
import 'dart:ui';

import 'package:crypto/crypto.dart';
import 'package:sqflite/sqflite.dart';
import 'package:unorm_dart/unorm_dart.dart' as unicode;

import '../../document_import/domain/document_import_models.dart';
import '../domain/ocr_engine.dart';
import 'mlkit_text_recognition_engine.dart';

import 'package:uuid/uuid.dart';

import '../../../core/database/memo_mind_database.dart';
import '../../document_import/data/local_document_import_repository.dart';
import '../../document_import/domain/document_import_repository.dart';
import '../domain/ocr_models.dart';
import '../domain/ocr_repository.dart';

class LocalOcrRepository implements OcrRepository {
  LocalOcrRepository({
    DocumentImportRepository? documentRepository,
    MemoMindDatabase? database,
    Uuid? uuid,
    DateTime Function()? clock,
    this.geometryEngine,
  }) : _documents = documentRepository ?? LocalDocumentImportRepository(),
       _database = database ?? WorkspaceRuntime.database,
       _uuid = uuid ?? const Uuid(),
       _clock = clock ?? DateTime.now;

  final DocumentImportRepository _documents;
  final MemoMindDatabase _database;
  final Uuid _uuid;
  final DateTime Function() _clock;
  final OcrEngine? geometryEngine;
  final Map<String, Future<void>> _repairs = {};

  @override
  Future<OcrDocumentReview> getOcrReview(String documentId) async {
    final document = await _documents.getDocument(documentId);
    final db = await _database.database;

    final pageReviews = <OcrPageReview>[];

    for (final page in document.pages) {
      await _ensureGeometry(page);
      final pageResultRows = await db.query(
        'ocr_page_results',
        where: 'page_id = ?',
        whereArgs: [page.pageId],
      );

      final blockRows = await db.query(
        'source_blocks',
        where: 'page_id = ?',
        whereArgs: [page.pageId],
        orderBy: 'order_index ASC',
      );

      final blocks = blockRows.map(_mapSourceBlock).toList();

      if (pageResultRows.isEmpty) {
        pageReviews.add(
          OcrPageReview(
            pageId: page.pageId,
            documentId: documentId,
            pageNumber: page.pageNumber,
            status: OcrPageStatus.notStarted,
            blocks: blocks,
            updatedAt: page.createdAt,
          ),
        );
      } else {
        final row = pageResultRows.first;
        pageReviews.add(
          OcrPageReview(
            pageId: page.pageId,
            documentId: documentId,
            pageNumber: page.pageNumber,
            status: _mapPageStatus(row['status'] as String),
            recognizedLanguage: row['recognized_language'] as String?,
            rawFullText: row['raw_full_text'] as String?,
            errorMessage: row['error_message'] as String?,
            blocks: blocks,
            updatedAt: DateTime.fromMillisecondsSinceEpoch(
              row['updated_at'] as int,
            ),
          ),
        );
      }
    }

    return OcrDocumentReview(document: document, pageReviews: pageReviews);
  }

  @override
  Future<List<SourceBlock>> getPageBlocks(String pageId) async {
    final db = await _database.database;
    final pages = await db.query(
      'source_pages',
      where: 'page_id=?',
      whereArgs: [pageId],
    );
    if (pages.isNotEmpty) {
      final doc = await _documents.getDocument(
        pages.single['document_id'] as String,
      );
      for (final page in doc.pages.where((p) => p.pageId == pageId)) {
        await _ensureGeometry(page);
      }
    }
    final rows = await db.query(
      'source_blocks',
      where: 'page_id = ?',
      whereArgs: [pageId],
      orderBy: 'order_index ASC',
    );
    return rows.map(_mapSourceBlock).toList();
  }

  @override
  Future<void> savePageOcrDraft({
    required String documentId,
    required String pageId,
    required int pageNumber,
    required List<SourceBlock> blocks,
    required String rawFullText,
    String? language,
    String? imageSha256,
  }) async {
    final now = _clock().millisecondsSinceEpoch;

    try {
      await _database.studyTransaction((txn) async {
        if (imageSha256 != null) {
          final page = await txn.query(
            'source_pages',
            where: 'page_id=? AND document_id=?',
            whereArgs: [pageId, documentId],
          );
          final normalization = await txn.query(
            'page_normalizations',
            where: 'page_id=?',
            whereArgs: [pageId],
          );
          final currentHash =
              normalization.firstOrNull?['sha256'] ??
              page.firstOrNull?['sha256'];
          if (currentHash != imageSha256) {
            throw const OcrFailure(
              OcrFailureCode.invalidOutput,
              'Ảnh nguồn đã thay đổi. Hãy nhận dạng lại trang hiện tại.',
            );
          }
        }
        // Check existing user-edited or user-added blocks (BR04-07)
        final existingRows = await txn.query(
          'source_blocks',
          where: 'page_id = ?',
          whereArgs: [pageId],
        );

        final existing = existingRows.map(_mapSourceBlock).toList();
        final used = <String>{};
        var order = 0;
        for (final recognized in blocks) {
          final matches = existing
              .where((b) => _text(b.rawText) == _text(recognized.rawText))
              .toList();
          final uniqueNew =
              blocks
                  .where((b) => _text(b.rawText) == _text(recognized.rawText))
                  .length ==
              1;
          final old = matches.length == 1 && uniqueNew ? matches.single : null;
          if (old != null) used.add(old.blockId);
          if (old?.isDeleted == true) continue;
          final block = old == null
              ? recognized
              : old.copyWith(
                  boundingBox: recognized.boundingBox,
                  boxImageSha256: recognized.boxImageSha256,
                  hasValidBox: recognized.hasValidBox,
                  orderIndex: order,
                );
          final values = _blockValues(
            block,
            documentId,
            pageId,
            pageNumber,
            order++,
            now,
          );
          if (old == null) {
            await txn.insert('source_blocks', values);
          } else {
            await txn.update(
              'source_blocks',
              values,
              where: 'block_id=?',
              whereArgs: [old.blockId],
            );
          }
        }
        for (final old in existing.where((b) => !used.contains(b.blockId))) {
          if (old.isVerified ||
              old.isUserAdded ||
              old.isEdited ||
              old.isDeleted) {
            await txn.update(
              'source_blocks',
              {'order_index': order++, 'has_valid_box': 0, 'updated_at': now},
              where: 'block_id=?',
              whereArgs: [old.blockId],
            );
          } else {
            await txn.delete(
              'source_blocks',
              where: 'block_id=?',
              whereArgs: [old.blockId],
            );
          }
        }

        // Upsert ocr_page_results
        await txn.insert('ocr_page_results', {
          'page_id': pageId,
          'document_id': documentId,
          'status': 'completed',
          'recognized_language': language,
          'raw_full_text': rawFullText,
          'error_message': null,
          'updated_at': now,
        }, conflictAlgorithm: ConflictAlgorithm.replace);

        // Advance document status to pending_ocr_review if currently pending_ocr
        await txn.update(
          'documents',
          {'status': 'pending_ocr_review', 'updated_at': now},
          where: "document_id = ? AND status IN ('pending_processing', 'pending_ocr')",
          whereArgs: [documentId],
        );
      });
    } on OcrFailure {
      rethrow;
    } catch (e) {
      throw OcrFailure(
        OcrFailureCode.storageError,
        'Không thể lưu kết quả nhận dạng trang $pageNumber.',
        e,
      );
    }
  }

  @override
  Future<void> recordPageOcrFailure({
    required String documentId,
    required String pageId,
    required String errorMessage,
  }) async {
    final db = await _database.database;
    final now = _clock().millisecondsSinceEpoch;

    await db.insert('ocr_page_results', {
      'page_id': pageId,
      'document_id': documentId,
      'status': 'failed',
      'recognized_language': null,
      'raw_full_text': null,
      'error_message': errorMessage,
      'updated_at': now,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  @override
  Future<void> updateSourceBlock(SourceBlock block) async {
    final db = await _database.database;
    final now = _clock().millisecondsSinceEpoch;

    final count = await db.update(
      'source_blocks',
      {
        'normalized_text': block.normalizedText,
        'status': _blockStatusToDb(block.status),
        'confidence': block.confidence,
        'confidence_source': _confidenceSourceToDb(block.confidenceSource),
        ..._geometryValues(block),
        'updated_at': now,
      },
      where: 'block_id = ?',
      whereArgs: [block.blockId],
    );

    if (count == 0) {
      throw const OcrFailure(
        OcrFailureCode.invalidOutput,
        'Không tìm thấy đoạn văn bản cần cập nhật.',
      );
    }
  }

  @override
  Future<void> addSourceBlock(SourceBlock block) async {
    final db = await _database.database;
    final now = _clock().millisecondsSinceEpoch;

    await db.insert('source_blocks', {
      'block_id': block.blockId.isEmpty ? _uuid.v4() : block.blockId,
      'document_id': block.documentId,
      'page_id': block.pageId,
      'page_number': block.pageNumber,
      'order_index': block.orderIndex,
      'raw_text': block.rawText,
      'normalized_text': block.normalizedText,
      ..._geometryValues(block),
      'confidence': block.confidence,
      'confidence_source': _confidenceSourceToDb(block.confidenceSource),
      'status': _blockStatusToDb(block.status),
      'created_at': now,
      'updated_at': now,
    });
  }

  @override
  Future<void> deleteSourceBlock(String blockId) async {
    final db = await _database.database;
    final now = _clock().millisecondsSinceEpoch;

    await db.update(
      'source_blocks',
      {'status': _blockStatusToDb(BlockStatus.deleted), 'updated_at': now},
      where: 'block_id = ?',
      whereArgs: [blockId],
    );
  }

  @override
  Future<void> restoreSourceBlock(String blockId) async {
    final db = await _database.database;
    final rows = await db.query(
      'source_blocks',
      where: 'block_id = ?',
      whereArgs: [blockId],
    );

    if (rows.isEmpty) return;

    final block = _mapSourceBlock(rows.first);
    final now = _clock().millisecondsSinceEpoch;

    // Reset normalizedText to rawText, and status to draft/needsReview
    final newStatus = (block.confidence == null || (block.confidence! < 0.75))
        ? BlockStatus.needsReview
        : BlockStatus.draft;

    await db.update(
      'source_blocks',
      {
        'normalized_text': block.rawText,
        'status': _blockStatusToDb(newStatus),
        'updated_at': now,
      },
      where: 'block_id = ?',
      whereArgs: [blockId],
    );
  }

  @override
  Future<void> saveDraft(String documentId) async {
    final db = await _database.database;
    final now = _clock().millisecondsSinceEpoch;

    await db.update(
      'documents',
      {'status': 'pending_ocr_review', 'updated_at': now},
      where: 'document_id = ?',
      whereArgs: [documentId],
    );
  }

  @override
  Future<void> confirmOcrReview(String documentId) async {
    final now = _clock().millisecondsSinceEpoch;

    await _database.studyTransaction((txn) async {
      // Mark all non-deleted blocks of this document as verified
      await txn.update(
        'source_blocks',
        {'status': _blockStatusToDb(BlockStatus.verified), 'updated_at': now},
        where: "document_id = ? AND status != 'deleted'",
        whereArgs: [documentId],
      );

      // Advance document status to ready_for_generation
      await txn.update(
        'documents',
        {'status': 'ready_for_generation', 'updated_at': now},
        where: 'document_id = ?',
        whereArgs: [documentId],
      );
    });
  }

  static String _text(String value) =>
      unicode.nfc(value).replaceAll(RegExp(r'\s+', unicode: true), ' ').trim();

  Map<String, Object?> _blockValues(
    SourceBlock b,
    String documentId,
    String pageId,
    int pageNumber,
    int order,
    int now,
  ) => {
    'block_id': b.blockId.isEmpty ? _uuid.v4() : b.blockId,
    'document_id': documentId,
    'page_id': pageId,
    'page_number': pageNumber,
    'order_index': order,
    'raw_text': b.rawText,
    'normalized_text': b.normalizedText,
    ..._geometryValues(b),
    'confidence': b.confidence,
    'confidence_source': _confidenceSourceToDb(b.confidenceSource),
    'status': _blockStatusToDb(b.status),
    'created_at': b.createdAt.millisecondsSinceEpoch,
    'updated_at': now,
  };

  Map<String, Object?> _geometryValues(SourceBlock block) {
    final box = block.hasValidBox && block.boundingBox?.isValid == true
        ? block.boundingBox
        : null;
    return {
      'box_left': box?.left,
      'box_top': box?.top,
      'box_width': box?.width,
      'box_height': box?.height,
      if (block.boxImageSha256 != null)
        'box_image_sha256': block.boxImageSha256,
      'has_valid_box': box == null ? 0 : 1,
    };
  }

  Future<void> _ensureGeometry(SourcePage page) async {
    final key = '${page.pageId}:${page.displayImage.sha256}';
    final existing = _repairs[key];
    if (existing != null) return existing;
    final future = _repairGeometry(page);
    _repairs[key] = future;
    try {
      await future;
    } finally {
      _repairs.remove(key);
    }
  }

  Future<void> _repairGeometry(SourcePage page) async {
    final db = await _database.database;
    final rows = await db.query(
      'source_blocks',
      where: 'page_id=?',
      whereArgs: [page.pageId],
    );
    final blocks = rows
        .map(_mapSourceBlock)
        .where((b) => !b.isDeleted && b.hasValidBox && !b.hasBoxFor(page))
        .toList();
    if (blocks.isEmpty) return;
    final raster = page.displayImage;
    final file = File(raster.path);
    if (!await file.exists()) return;
    if ((await sha256.bind(file.openRead()).first).toString() !=
        raster.sha256) {
      return;
    }
    final engine = geometryEngine ?? MlKitTextRecognitionEngine();
    try {
      final result = await engine.recognizeText(
        imagePath: raster.path,
        imageSize: Size(raster.width.toDouble(), raster.height.toDouble()),
      );
      await _database.studyTransaction((txn) async {
        // The image may have been cropped again while OCR was running.
        final normal = await txn.query(
          'page_normalizations',
          where: 'page_id=?',
          whereArgs: [page.pageId],
        );
        final raw = await txn.query(
          'source_pages',
          where: 'page_id=?',
          whereArgs: [page.pageId],
        );
        if (raw.isEmpty ||
            (normal.firstOrNull?['sha256'] ?? raw.single['sha256']) !=
                raster.sha256) {
          return;
        }
        for (final old in blocks) {
          final matches = result.blocks
              .where((b) => _text(b.text) == _text(old.rawText))
              .toList();
          final oldMatches = rows
              .where(
                (r) =>
                    r['status'] != 'deleted' &&
                    _text(r['raw_text'] as String) == _text(old.rawText),
              )
              .length;
          final box = matches.length == 1 && oldMatches == 1
              ? NormalizedBoundingBox.fromRect(
                  matches.single.boundingBox,
                  Size(raster.width.toDouble(), raster.height.toDouble()),
                )
              : null;
          await txn.update(
            'source_blocks',
            {
              'box_left': box?.left,
              'box_top': box?.top,
              'box_width': box?.width,
              'box_height': box?.height,
              'box_image_sha256': raster.sha256,
              'has_valid_box': box?.isValid == true ? 1 : 0,
              'updated_at': _clock().millisecondsSinceEpoch,
            },
            where: 'block_id=? AND updated_at=? AND raw_text=? AND normalized_text=? AND status=?',
            whereArgs: [
              old.blockId,
              old.updatedAt.millisecondsSinceEpoch,
              old.rawText,
              old.normalizedText,
              _blockStatusToDb(old.status),
            ],
          );
        }
      });
    } catch (_) {
      // Keep text usable offline; unknown geometry is never drawn.
    } finally {
      if (geometryEngine == null) {
        try {
          await engine.dispose();
        } catch (_) {
          // The native recognizer may be unavailable on this platform.
        }
      }
    }
  }

  String _blockStatusToDb(BlockStatus status) => switch (status) {
    BlockStatus.draft => 'draft',
    BlockStatus.needsReview => 'needs_review',
    BlockStatus.verified => 'verified',
    BlockStatus.userAdded => 'user_added',
    BlockStatus.deleted => 'deleted',
  };

  BlockStatus _blockStatusFromDb(String? value) => switch (value) {
    'needs_review' => BlockStatus.needsReview,
    'verified' => BlockStatus.verified,
    'user_added' => BlockStatus.userAdded,
    'deleted' => BlockStatus.deleted,
    _ => BlockStatus.draft,
  };

  String _confidenceSourceToDb(ConfidenceSource source) => switch (source) {
    ConfidenceSource.mlkit => 'mlkit',
    ConfidenceSource.gemini => 'gemini',
    ConfidenceSource.user => 'user',
    ConfidenceSource.unavailable => 'unavailable',
  };

  ConfidenceSource _confidenceSourceFromDb(String? value) => switch (value) {
    'mlkit' => ConfidenceSource.mlkit,
    'gemini' => ConfidenceSource.gemini,
    'user' => ConfidenceSource.user,
    _ => ConfidenceSource.unavailable,
  };

  SourceBlock _mapSourceBlock(Map<String, Object?> row) {
    final left = row['box_left'] as num?;
    final top = row['box_top'] as num?;
    final width = row['box_width'] as num?;
    final height = row['box_height'] as num?;

    NormalizedBoundingBox? box;
    if (left != null && top != null && width != null && height != null) {
      box = NormalizedBoundingBox(
        left: left.toDouble(),
        top: top.toDouble(),
        width: width.toDouble(),
        height: height.toDouble(),
      );
    }

    return SourceBlock(
      blockId: row['block_id'] as String,
      documentId: row['document_id'] as String,
      pageId: row['page_id'] as String,
      pageNumber: row['page_number'] as int,
      orderIndex: row['order_index'] as int,
      rawText: row['raw_text'] as String,
      normalizedText: row['normalized_text'] as String,
      boundingBox: box,
      boxImageSha256: row['box_image_sha256'] as String?,
      hasValidBox: (row['has_valid_box'] as int? ?? 1) == 1,
      confidence: (row['confidence'] as num?)?.toDouble(),
      confidenceSource: _confidenceSourceFromDb(
        row['confidence_source'] as String?,
      ),
      status: _blockStatusFromDb(row['status'] as String?),
      createdAt: DateTime.fromMillisecondsSinceEpoch(row['created_at'] as int),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(row['updated_at'] as int),
    );
  }

  OcrPageStatus _mapPageStatus(String value) => switch (value) {
    'processing' => OcrPageStatus.processing,
    'completed' => OcrPageStatus.completed,
    'failed' => OcrPageStatus.failed,
    _ => OcrPageStatus.notStarted,
  };
}

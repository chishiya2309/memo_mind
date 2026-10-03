import '../../../core/workspace/workspace_context.dart';

import 'package:sqflite/sqflite.dart';
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
  }) : _documents = documentRepository ?? LocalDocumentImportRepository(),
       _database = database ?? WorkspaceRuntime.database,
       _uuid = uuid ?? const Uuid(),
       _clock = clock ?? DateTime.now;

  final DocumentImportRepository _documents;
  final MemoMindDatabase _database;
  final Uuid _uuid;
  final DateTime Function() _clock;

  @override
  Future<OcrDocumentReview> getOcrReview(String documentId) async {
    final document = await _documents.getDocument(documentId);
    final db = await _database.database;

    final pageReviews = <OcrPageReview>[];

    for (final page in document.pages) {
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
  }) async {
    final db = await _database.database;
    final now = _clock().millisecondsSinceEpoch;

    try {
      await db.transaction((txn) async {
        // Check existing user-edited or user-added blocks (BR04-07)
        final existingRows = await txn.query(
          'source_blocks',
          where: 'page_id = ?',
          whereArgs: [pageId],
        );

        final preservedBlocks = existingRows
            .map(_mapSourceBlock)
            .where(
              (b) =>
                  b.status == BlockStatus.verified ||
                  b.status == BlockStatus.userAdded ||
                  b.rawText != b.normalizedText,
            )
            .toList();

        // Delete previous non-preserved blocks for this page
        await txn.delete(
          'source_blocks',
          where: 'page_id = ?',
          whereArgs: [pageId],
        );

        // Insert newly recognized blocks
        var order = 0;
        for (final block in blocks) {
          await txn.insert('source_blocks', {
            'block_id': block.blockId.isEmpty ? _uuid.v4() : block.blockId,
            'document_id': documentId,
            'page_id': pageId,
            'page_number': pageNumber,
            'order_index': order++,
            'raw_text': block.rawText,
            'normalized_text': block.normalizedText,
            'box_left': block.boundingBox?.left,
            'box_top': block.boundingBox?.top,
            'box_width': block.boundingBox?.width,
            'box_height': block.boundingBox?.height,
            'has_valid_box': block.hasValidBox ? 1 : 0,
            'confidence': block.confidence,
            'confidence_source': _confidenceSourceToDb(block.confidenceSource),
            'status': _blockStatusToDb(block.status),
            'created_at': block.createdAt.millisecondsSinceEpoch,
            'updated_at': now,
          });
        }

        // Re-insert preserved user blocks at the end or if they were modified
        for (final preserved in preservedBlocks) {
          await txn.insert('source_blocks', {
            'block_id': preserved.blockId,
            'document_id': documentId,
            'page_id': pageId,
            'page_number': pageNumber,
            'order_index': order++,
            'raw_text': preserved.rawText,
            'normalized_text': preserved.normalizedText,
            'box_left': preserved.boundingBox?.left,
            'box_top': preserved.boundingBox?.top,
            'box_width': preserved.boundingBox?.width,
            'box_height': preserved.boundingBox?.height,
            'has_valid_box': preserved.hasValidBox ? 1 : 0,
            'confidence': preserved.confidence,
            'confidence_source': _confidenceSourceToDb(
              preserved.confidenceSource,
            ),
            'status': _blockStatusToDb(preserved.status),
            'created_at': preserved.createdAt.millisecondsSinceEpoch,
            'updated_at': preserved.updatedAt.millisecondsSinceEpoch,
          });
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
        'has_valid_box': block.hasValidBox ? 1 : 0,
        'box_left': block.boundingBox?.left,
        'box_top': block.boundingBox?.top,
        'box_width': block.boundingBox?.width,
        'box_height': block.boundingBox?.height,
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
      'box_left': block.boundingBox?.left,
      'box_top': block.boundingBox?.top,
      'box_width': block.boundingBox?.width,
      'box_height': block.boundingBox?.height,
      'has_valid_box': block.hasValidBox ? 1 : 0,
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
    final db = await _database.database;
    final now = _clock().millisecondsSinceEpoch;

    await db.transaction((txn) async {
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

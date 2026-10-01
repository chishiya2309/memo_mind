import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/memo_mind_database.dart';
import '../../document_import/domain/document_import_models.dart';
import '../../home/domain/home_dashboard_data.dart';
import '../../image_normalization/domain/image_normalization_models.dart';
import '../../material_generation/domain/material_generation_models.dart';
import '../../material_generation/domain/material_validator.dart';
import '../../ocr_editor/domain/ocr_models.dart';
import '../domain/deck_models.dart';
import '../domain/deck_repository.dart';

typedef DirectoryProvider = Future<Directory> Function();

class LocalDeckRepository implements DeckRepository {
  LocalDeckRepository({
    MemoMindDatabase? database,
    DateTime Function()? clock,
    DirectoryProvider? supportDirectory,
  })  : _database = database ?? MemoMindDatabase.instance,
        _clock = clock ?? DateTime.now,
        _supportDirectory = supportDirectory ?? getApplicationSupportDirectory;

  final MemoMindDatabase _database;
  final DateTime Function() _clock;
  final DirectoryProvider _supportDirectory;
  static const _uuid = Uuid();

  Future<Set<String>> _getDeckColumns(dynamic db) async {
    try {
      final rows = await db.rawQuery('PRAGMA table_info(decks)');
      return rows.map((r) => r['name'] as String).toSet();
    } catch (_) {
      return const {
        'deck_id',
        'title',
        'description',
        'tone',
        'card_count',
        'tags',
        'status',
        'created_at',
        'updated_at',
      };
    }
  }

  @override
  Future<List<Deck>> getDecks() async {
    final db = await _database.database;
    final columns = await _getDeckColumns(db);
    final rows = await db.query(
      'decks',
      where: columns.contains('status') ? "status != 'deleted'" : null,
      orderBy: 'updated_at DESC',
    );
    return rows.map(_mapDeck).toList();
  }

  @override
  Future<Deck?> getDeckById(String deckId) async {
    final db = await _database.database;
    final columns = await _getDeckColumns(db);
    final rows = await db.query(
      'decks',
      where: columns.contains('status')
          ? 'deck_id = ? AND status != ?'
          : 'deck_id = ?',
      whereArgs: columns.contains('status') ? [deckId, 'deleted'] : [deckId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return _mapDeck(rows.first);
  }

  @override
  Future<Deck> createDeck({
    required String title,
    String? description,
    DeckTone tone = DeckTone.indigo,
    List<String> tags = const [],
  }) async {
    final db = await _database.database;
    final now = _clock();
    final deckId = _uuid.v4();

    final values = <String, dynamic>{
      'deck_id': deckId,
      'title': title.trim(),
      'description': description?.trim(),
      'tone': tone.name,
      'card_count': 0,
      'created_at': now.millisecondsSinceEpoch,
      'updated_at': now.millisecondsSinceEpoch,
    };

    final columns = await _getDeckColumns(db);
    if (columns.contains('tags')) {
      values['tags'] = jsonEncode(tags);
    }
    if (columns.contains('status')) {
      values['status'] = 'active';
    }

    await db.insert('decks', values);

    return Deck(
      id: deckId,
      title: title.trim(),
      description: description?.trim(),
      tone: tone,
      cardCount: 0,
      tags: List.unmodifiable(tags),
      status: DeckStatus.active,
      createdAt: now,
      updatedAt: now,
    );
  }

  @override
  Future<Deck> updateDeck(
    String deckId, {
    required String title,
    String? description,
    DeckTone? tone,
    List<String>? tags,
  }) async {
    final db = await _database.database;
    final now = _clock().millisecondsSinceEpoch;
    final columns = await _getDeckColumns(db);

    final existing = await db.query(
      'decks',
      where: columns.contains('status')
          ? 'deck_id = ? AND status != ?'
          : 'deck_id = ?',
      whereArgs: columns.contains('status') ? [deckId, 'deleted'] : [deckId],
      limit: 1,
    );
    if (existing.isEmpty) {
      throw StateError('Deck không tồn tại hoặc đã bị xóa.');
    }

    final existingRow = existing.first;
    final updatedTone = tone ??
        DeckTone.values.firstWhere(
          (t) => t.name == (existingRow['tone'] as String?),
          orElse: () => DeckTone.indigo,
        );

    final values = <String, dynamic>{
      'title': title.trim(),
      'description': description?.trim(),
      'tone': updatedTone.name,
      'updated_at': now,
    };

    if (tags != null && columns.contains('tags')) {
      values['tags'] = jsonEncode(tags);
    }

    await db.update(
      'decks',
      values,
      where: 'deck_id = ?',
      whereArgs: [deckId],
    );

    final updatedRow = await db.query(
      'decks',
      where: 'deck_id = ?',
      whereArgs: [deckId],
      limit: 1,
    );
    return _mapDeck(updatedRow.first);
  }

  @override
  Future<void> deleteDeck(String deckId) async {
    final db = await _database.database;
    final now = _clock().millisecondsSinceEpoch;
    final columns = await _getDeckColumns(db);

    if (columns.contains('status')) {
      await db.update(
        'decks',
        {
          'status': 'deleted',
          'updated_at': now,
        },
        where: 'deck_id = ?',
        whereArgs: [deckId],
      );
    } else {
      await db.delete(
        'decks',
        where: 'deck_id = ?',
        whereArgs: [deckId],
      );
    }
  }

  @override
  Future<void> deleteCard(String cardId) async {
    final db = await _database.database;
    final now = _clock().millisecondsSinceEpoch;

    await db.transaction((txn) async {
      final rows = await txn.query(
        'cards',
        columns: ['deck_id'],
        where: 'card_id = ?',
        whereArgs: [cardId],
        limit: 1,
      );
      if (rows.isEmpty) return;

      final deckId = rows.first['deck_id'] as String;

      await txn.update(
        'cards',
        {
          'status': 'deleted',
          'updated_at': now,
        },
        where: 'card_id = ?',
        whereArgs: [cardId],
      );

      await txn.rawUpdate(
        """
        UPDATE decks SET card_count = (
          SELECT COUNT(*) FROM cards WHERE deck_id = ? AND status != 'deleted'
        ), updated_at = ? WHERE deck_id = ?
        """,
        [deckId, now, deckId],
      );
    });
  }

  @override
  Future<CardSourceTrace> getCardSourceTrace(CardEntity card) async {
    final db = await _database.database;

    String documentTitle = '';
    final docRows = await db.query(
      'documents',
      columns: ['title'],
      where: 'document_id = ?',
      whereArgs: [card.sourceDocumentId],
      limit: 1,
    );
    if (docRows.isNotEmpty) {
      documentTitle = docRows.first['title'] as String? ?? '';
    }

    SourceBlock? sourceBlock;
    final blockRows = await db.query(
      'source_blocks',
      where: 'block_id = ?',
      whereArgs: [card.sourceBlockId],
      limit: 1,
    );
    if (blockRows.isNotEmpty) {
      sourceBlock = _mapSourceBlockRow(blockRows.first);
    }

    SourcePage? sourcePage;
    File? imageFile;

    String supportPath = '';
    try {
      final support = await _supportDirectory();
      supportPath = support.path;
    } catch (_) {
      supportPath = Directory.current.path;
    }

    final pageRows = await db.rawQuery(
      '''
      SELECT source_pages.*,
        page_normalizations.revision AS normalized_revision,
        page_normalizations.normalized_relative_path,
        page_normalizations.mime_type AS normalized_mime_type,
        page_normalizations.file_size_bytes AS normalized_file_size_bytes,
        page_normalizations.width AS normalized_width,
        page_normalizations.height AS normalized_height,
        page_normalizations.sha256 AS normalized_sha256,
        page_normalizations.top_left_x,
        page_normalizations.top_left_y,
        page_normalizations.top_right_x,
        page_normalizations.top_right_y,
        page_normalizations.bottom_right_x,
        page_normalizations.bottom_right_y,
        page_normalizations.bottom_left_x,
        page_normalizations.bottom_left_y,
        page_normalizations.rotation_degrees,
        page_normalizations.contrast,
        page_normalizations.updated_at AS normalization_updated_at
      FROM source_pages
      LEFT JOIN page_normalizations
        ON page_normalizations.page_id = source_pages.page_id
      WHERE source_pages.page_id = ?
      LIMIT 1
      ''',
      [card.sourcePageId],
    );

    if (pageRows.isNotEmpty) {
      sourcePage = _mapSourcePageRow(pageRows.first, supportPath);
      final candidatePath = sourcePage.displayPath;
      final file = File(candidatePath);
      if (await file.exists()) {
        imageFile = file;
      } else {
        final rawFile = File(sourcePage.absolutePath);
        if (await rawFile.exists()) {
          imageFile = rawFile;
        }
      }
    }

    return CardSourceTrace(
      documentTitle: documentTitle,
      sourceQuote: card.sourceQuote,
      sourcePage: sourcePage,
      sourceBlock: sourceBlock,
      imageFile: imageFile,
    );
  }


  @override
  Future<void> saveCardsToDeck({
    required String deckId,
    required List<CardEntity> cards,
  }) async {
    if (cards.isEmpty) return;
    final db = await _database.database;
    final now = _clock().millisecondsSinceEpoch;
    final deckColumns = await _getDeckColumns(db);

    await db.transaction((txn) async {
      final decks = await txn.query(
        'decks',
        columns: ['deck_id'],
        where: deckColumns.contains('status')
            ? 'deck_id = ? AND status != ?'
            : 'deck_id = ?',
        whereArgs: deckColumns.contains('status')
            ? [deckId, 'deleted']
            : [deckId],
      );
      if (decks.isEmpty) {
        throw const MaterialGenerationFailure(
          MaterialGenerationFailureCode.storageError,
          'Deck đích không còn tồn tại. Vui lòng chọn lại deck.',
        );
      }
      for (final card in cards) {
        if (card.deckId != deckId) {
          throw const FormatException('Deck không khớp.');
        }
        final rows = await txn.rawQuery(
          '''
          SELECT b.*, p.document_id AS actual_document_id, p.page_number AS actual_page_number
          FROM source_blocks b JOIN source_pages p ON p.page_id = b.page_id
          WHERE b.block_id = ?
        ''',
          [card.sourceBlockId],
        );
        if (rows.isEmpty) {
          throw const MaterialGenerationFailure(
            MaterialGenerationFailureCode.sourceBlockMismatch,
            'Đoạn nguồn không còn tồn tại.',
          );
        }
        final row = rows.single;
        if (row['page_id'] != card.sourcePageId ||
            row['actual_document_id'] != card.sourceDocumentId ||
            row['actual_page_number'] != card.sourcePageNumber) {
          throw const MaterialGenerationFailure(
            MaterialGenerationFailureCode.sourceBlockMismatch,
            'Trang nguồn đã thay đổi.',
          );
        }
        final block = SourceBlock(
          blockId: row['block_id'] as String,
          documentId: row['document_id'] as String,
          pageId: row['page_id'] as String,
          pageNumber: row['page_number'] as int,
          orderIndex: row['order_index'] as int,
          rawText: row['raw_text'] as String,
          normalizedText: row['normalized_text'] as String,
          status: switch (row['status']) {
            'verified' => BlockStatus.verified,
            'user_added' => BlockStatus.userAdded,
            'deleted' => BlockStatus.deleted,
            _ => BlockStatus.draft,
          },
          createdAt: DateTime.fromMillisecondsSinceEpoch(
            row['created_at'] as int,
          ),
          updatedAt: DateTime.fromMillisecondsSinceEpoch(
            row['updated_at'] as int,
          ),
        );
        MaterialValidator.validate(
          card.toDraft(),
          sourceBlock: block,
          documentId: card.sourceDocumentId,
        );
        await txn.insert('cards', {
          'card_id': card.id,
          'deck_id': deckId,
          'type': card.type.wireName,
          'front': card.front,
          'back': card.back,
          'mcq_payload': card.type == CardType.mcq
              ? jsonEncode({
                  'options': card.options.map((o) => o.toJson()).toList(),
                  'correctOptionId': card.correctOptionId,
                  'explanation': card.explanation,
                })
              : null,
          'source_document_id': card.sourceDocumentId,
          'source_page_id': card.sourcePageId,
          'source_page_number': card.sourcePageNumber,
          'source_block_id': card.sourceBlockId,
          'source_quote': card.sourceQuote,
          'confidence': card.confidence,
          'status': card.status.name,
          'repetitions': card.repetitions,
          'interval_days': card.intervalDays,
          'ease_factor': card.easeFactor,
          'due_date': card.dueDate.millisecondsSinceEpoch,
          'created_at': card.createdAt.millisecondsSinceEpoch,
          'updated_at': now,
        });
      }
      await txn.rawUpdate(
        """
        UPDATE decks SET card_count = (
          SELECT COUNT(*) FROM cards WHERE deck_id = ? AND status != 'deleted'
        ), updated_at = ? WHERE deck_id = ?
      """,
        [deckId, now, deckId],
      );
    });
  }

  @override
  Future<List<CardEntity>> getCardsForDeck(String deckId) async {
    final db = await _database.database;
    final rows = await db.query(
      'cards',
      where: 'deck_id = ? AND status != ?',
      whereArgs: [deckId, 'deleted'],
      orderBy: 'created_at ASC',
    );
    return rows.map(cardFromRow).toList();
  }

  Deck _mapDeck(Map<String, dynamic> row) {
    List<String> tags = const [];
    final tagsRaw = row['tags'];
    if (tagsRaw is String && tagsRaw.isNotEmpty) {
      try {
        final decoded = jsonDecode(tagsRaw);
        if (decoded is List) {
          tags = List<String>.unmodifiable(decoded.map((e) => e.toString()));
        }
      } catch (_) {
        tags = const [];
      }
    }

    final statusRaw = row['status'] as String?;
    final status =
        statusRaw == 'deleted' ? DeckStatus.deleted : DeckStatus.active;

    return Deck(
      id: row['deck_id'] as String,
      title: row['title'] as String,
      description: row['description'] as String?,
      tone: DeckTone.values.firstWhere(
        (t) => t.name == (row['tone'] as String?),
        orElse: () => DeckTone.indigo,
      ),
      cardCount: (row['card_count'] as num?)?.toInt() ?? 0,
      tags: tags,
      status: status,
      createdAt: DateTime.fromMillisecondsSinceEpoch(row['created_at'] as int),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(row['updated_at'] as int),
    );
  }

  static CardEntity cardFromRow(Map<String, dynamic> row) {

  SourceBlock _mapSourceBlockRow(Map<String, dynamic> row) {
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
      confidenceSource: switch (row['confidence_source'] as String?) {
        'mlkit' => ConfidenceSource.mlkit,
        'gemini' => ConfidenceSource.gemini,
        'user' => ConfidenceSource.user,
        _ => ConfidenceSource.unavailable,
      },
      status: switch (row['status'] as String?) {
        'needs_review' => BlockStatus.needsReview,
        'verified' => BlockStatus.verified,
        'user_added' => BlockStatus.userAdded,
        'deleted' => BlockStatus.deleted,
        _ => BlockStatus.draft,
      },
      createdAt: DateTime.fromMillisecondsSinceEpoch(row['created_at'] as int),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(row['updated_at'] as int),
    );
  }

  SourcePage _mapSourcePageRow(Map<String, Object?> row, String supportPath) {
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
      normalizationStatus: switch (row['normalization_status'] as String?) {
        'ready' => PageNormalizationStatus.ready,
        'source_ready' => PageNormalizationStatus.sourceReady,
        _ => PageNormalizationStatus.pending,
      },
      normalizedAsset: _mapNormalizedAsset(row, supportPath),
    );
  }

  NormalizedPageAsset? _mapNormalizedAsset(
    Map<String, Object?> row,
    String supportPath,
  ) {
    final relativePath = row['normalized_relative_path'] as String?;
    if (relativePath == null) return null;
    return NormalizedPageAsset(
      pageId: row['page_id']! as String,
      revision: row['normalized_revision']! as int,
      relativePath: relativePath,
      absolutePath: _resolveRelative(supportPath, relativePath).path,
      mimeType: row['normalized_mime_type']! as String,
      fileSizeBytes: row['normalized_file_size_bytes']! as int,
      width: row['normalized_width']! as int,
      height: row['normalized_height']! as int,
      sha256: row['normalized_sha256']! as String,
      parameters: NormalizationParameters(
        corners: CropQuadrilateral(
          topLeft: NormalizedPoint(
            (row['top_left_x']! as num).toDouble(),
            (row['top_left_y']! as num).toDouble(),
          ),
          topRight: NormalizedPoint(
            (row['top_right_x']! as num).toDouble(),
            (row['top_right_y']! as num).toDouble(),
          ),
          bottomRight: NormalizedPoint(
            (row['bottom_right_x']! as num).toDouble(),
            (row['bottom_right_y']! as num).toDouble(),
          ),
          bottomLeft: NormalizedPoint(
            (row['bottom_left_x']! as num).toDouble(),
            (row['bottom_left_y']! as num).toDouble(),
          ),
        ),
        rotationDegrees: row['rotation_degrees']! as int,
        contrast: (row['contrast']! as num).toDouble(),
      ),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(
        row['normalization_updated_at']! as int,
      ),
    );
  }

  File _resolveRelative(String root, String relativePath) =>
      File(p.joinAll([root, ...relativePath.split('/')]));


  CardEntity _mapCard(Map<String, dynamic> row) {
    final payload = row['mcq_payload'] == null
        ? null
        : jsonDecode(row['mcq_payload'] as String) as Map<String, dynamic>;
    return CardEntity(
      id: row['card_id'] as String,
      deckId: row['deck_id'] as String,
      type: CardType.fromWire(row['type'] as String),
      front: row['front'] as String,
      back: row['back'] as String,
      options: List.unmodifiable(
        (payload?['options'] as List<dynamic>? ?? []).map(
          (o) => McqOption.fromJson(o as Map<String, dynamic>),
        ),
      ),
      correctOptionId: payload?['correctOptionId'] as String?,
      explanation: payload?['explanation'] as String?,
      sourceDocumentId: row['source_document_id'] as String,
      sourcePageId: row['source_page_id'] as String,
      sourcePageNumber: row['source_page_number'] as int,
      sourceBlockId: row['source_block_id'] as String,
      sourceQuote: row['source_quote'] as String,
      confidence: (row['confidence'] as num?)?.toDouble(),
      status: CardStatus.values.byName(row['status'] as String),
      repetitions: (row['repetitions'] as int?) ?? 0,
      intervalDays: (row['interval_days'] as int?) ?? 0,
      easeFactor: (row['ease_factor'] as num?)?.toDouble() ?? 2.5,
      dueDate: DateTime.fromMillisecondsSinceEpoch(row['due_date'] as int),
      createdAt: DateTime.fromMillisecondsSinceEpoch(row['created_at'] as int),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(row['updated_at'] as int),
    );
  }
}

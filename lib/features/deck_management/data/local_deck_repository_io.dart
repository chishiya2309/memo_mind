import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import 'package:sqflite/sqflite.dart';

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
  }) : _database = database ?? MemoMindDatabase.instance,
       _clock = clock ?? DateTime.now,
       _supportDirectory = supportDirectory ?? getApplicationSupportDirectory;

  final MemoMindDatabase _database;
  final DateTime Function() _clock;
  final DirectoryProvider _supportDirectory;
  static const _uuid = Uuid();

  String _title(String title) {
    final value = title.trim();
    if (value.isEmpty) {
      throw const FormatException('Tên deck không được để trống.');
    }
    return value;
  }

  @override
  Future<List<Deck>> getDecks() async {
    final db = await _database.database;
    return (await db.query(
      'decks',
      where: "status='active'",
      orderBy: 'updated_at DESC',
    )).map(_mapDeck).toList();
  }

  @override
  Future<Deck?> getDeckById(String deckId) async {
    final db = await _database.database;
    final rows = await db.query(
      'decks',
      where: "deck_id=? AND status='active'",
      whereArgs: [deckId],
    );
    return rows.isEmpty ? null : _mapDeck(rows.single);
  }

  @override
  Future<Deck> createDeck({
    required String title,
    String? description,
    DeckTone tone = DeckTone.indigo,
    List<String> tags = const [],
  }) async {
    final name = _title(title);
    final labels = CardContent.normalizeTags(tags);
    final db = await _database.database;
    final now = _clock().toUtc();
    final deck = Deck(
      id: _uuid.v4(),
      title: name,
      description: description?.trim(),
      tone: tone,
      tags: labels,
      createdAt: now,
      updatedAt: now,
    );
    await db.insert('decks', {
      'deck_id': deck.id,
      'title': name,
      'description': deck.description,
      'tone': tone.name,
      'tags': jsonEncode(labels),
      'status': 'active',
      'card_count': 0,
      'created_at': now.millisecondsSinceEpoch,
      'updated_at': now.millisecondsSinceEpoch,
    });
    return deck;
  }

  @override
  Future<Deck> updateDeck(
    String deckId, {
    required String title,
    String? description,
    DeckTone? tone,
    List<String>? tags,
  }) async {
    final name = _title(title);
    final db = await _database.database;
    return db.transaction((txn) async {
      final rows = await txn.query(
        'decks',
        where: "deck_id=? AND status='active'",
        whereArgs: [deckId],
      );
      if (rows.isEmpty) throw StateError('Deck không tồn tại hoặc đã bị xóa.');
      await txn.update(
        'decks',
        {
          'title': name,
          if (description != null) 'description': description.trim(),
          if (tone != null) 'tone': tone.name,
          if (tags != null) 'tags': jsonEncode(CardContent.normalizeTags(tags)),
          'updated_at': _clock().toUtc().millisecondsSinceEpoch,
        },
        where: 'deck_id=?',
        whereArgs: [deckId],
      );
      return _mapDeck(
        (await txn.query(
          'decks',
          where: 'deck_id=?',
          whereArgs: [deckId],
        )).single,
      );
    });
  }

  @override
  Future<void> deleteDeck(String deckId) async {
    final db = await _database.database;
    final now = _clock().toUtc().millisecondsSinceEpoch;
    await db.transaction((txn) async {
      await txn.update(
        'decks',
        {'status': 'deleted', 'card_count': 0, 'updated_at': now},
        where: 'deck_id=?',
        whereArgs: [deckId],
      );
      await txn.update(
        'cards',
        {'status': 'deleted', 'updated_at': now},
        where: "deck_id=? AND status!='deleted'",
        whereArgs: [deckId],
      );
    });
  }

  Future<void> _refreshCount(DatabaseExecutor db, String deckId, int now) => db
      .rawUpdate(
        """UPDATE decks SET card_count=(
      SELECT COUNT(*) FROM cards WHERE deck_id=? AND status!='deleted'
    ), updated_at=? WHERE deck_id=?""",
        [deckId, now, deckId],
      )
      .then((_) {});

  @override
  Future<void> deleteCard(String cardId) async {
    final db = await _database.database;
    final now = _clock().toUtc().millisecondsSinceEpoch;
    await db.transaction((txn) async {
      final rows = await txn.query(
        'cards',
        where: 'card_id=?',
        whereArgs: [cardId],
      );
      if (rows.isEmpty) return;
      await txn.update(
        'cards',
        {'status': 'deleted', 'updated_at': now},
        where: 'card_id=?',
        whereArgs: [cardId],
      );
      await _refreshCount(txn, rows.single['deck_id'] as String, now);
    });
  }

  Map<String, Object?> _contentValues(CardContent content) => {
    'front': content.front.trim(),
    'back': content.answer.trim(),
    'tags': jsonEncode(CardContent.normalizeTags(content.tags)),
    'mcq_payload': content.type == CardType.mcq
        ? jsonEncode({
            'options': content.options
                .map(
                  (o) => McqOption(
                    optionId: o.optionId,
                    text: o.text.trim(),
                  ).toJson(),
                )
                .toList(),
            'correctOptionId': content.correctOptionId,
            'explanation': content.explanation?.trim(),
          })
        : null,
  };

  @override
  Future<CardEntity> createManualCard({
    required String deckId,
    required CardContent content,
  }) async {
    content.validate();
    final db = await _database.database;
    final now = _clock().toUtc();
    final id = _uuid.v4();
    return db.transaction((txn) async {
      if ((await txn.query(
        'decks',
        where: "deck_id=? AND status='active'",
        whereArgs: [deckId],
      )).isEmpty) {
        throw StateError('Deck không tồn tại hoặc đã bị xóa.');
      }
      await txn.insert('cards', {
        'card_id': id,
        'deck_id': deckId,
        'type': content.type.wireName,
        ..._contentValues(content),
        'source_quote': '',
        'status': 'active',
        'repetitions': 0,
        'interval_days': 0,
        'ease_factor': 2.5,
        'due_date': now.millisecondsSinceEpoch,
        'created_at': now.millisecondsSinceEpoch,
        'updated_at': now.millisecondsSinceEpoch,
      });
      await _refreshCount(txn, deckId, now.millisecondsSinceEpoch);
      return cardFromRow(
        (await txn.query('cards', where: 'card_id=?', whereArgs: [id])).single,
      );
    });
  }

  @override
  Future<CardEntity> updateCard(
    String cardId, {
    required CardContent content,
  }) async {
    content.validate();
    final db = await _database.database;
    return db.transaction((txn) async {
      final rows = await txn.rawQuery(
        """SELECT c.* FROM cards c JOIN decks d ON d.deck_id=c.deck_id
        WHERE c.card_id=? AND c.status!='deleted' AND d.status='active'""",
        [cardId],
      );
      if (rows.isEmpty) throw StateError('Thẻ không tồn tại hoặc đã bị xóa.');
      if (rows.single['type'] != content.type.wireName) {
        throw const FormatException('Không thể đổi loại thẻ đã lưu.');
      }
      final now = _clock().toUtc().millisecondsSinceEpoch;
      await txn.update(
        'cards',
        {..._contentValues(content), 'updated_at': now},
        where: 'card_id=?',
        whereArgs: [cardId],
      );
      await _refreshCount(txn, rows.single['deck_id'] as String, now);
      return cardFromRow(
        (await txn.query(
          'cards',
          where: 'card_id=?',
          whereArgs: [cardId],
        )).single,
      );
    });
  }

  @override
  Future<CardSourceTrace> getCardSourceTrace(CardEntity card) async {
    if (!card.hasSource) {
      return CardSourceTrace(documentTitle: '', sourceQuote: '');
    }
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
      return CardSourceTrace(
        documentTitle: documentTitle,
        sourceQuote: card.sourceQuote,
        sourcePageNumber: card.sourcePageNumber,
        warning: 'Không thể đọc ảnh nguồn trên thiết bị.',
      );
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
      sourcePageNumber: card.sourcePageNumber,
      imageUsesNormalizedCoordinates:
          imageFile != null &&
          (sourcePage?.normalizedAsset == null ||
              imageFile.path == sourcePage?.normalizedAsset?.absolutePath),
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

    await db.transaction((txn) async {
      final decks = await txn.query(
        'decks',
        columns: ['deck_id'],
        where: "deck_id = ? AND status='active'",
        whereArgs: [deckId],
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
          documentId: card.sourceDocumentId ?? '',
        );
        await txn.insert('cards', {
          'tags': jsonEncode(CardContent.normalizeTags(card.tags)),
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
    final rows = await db.rawQuery(
      "SELECT c.* FROM cards c JOIN decks d ON d.deck_id=c.deck_id WHERE c.deck_id=? AND c.status!='deleted' AND d.status='active' ORDER BY c.created_at",
      [deckId],
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
    final status = statusRaw == 'deleted'
        ? DeckStatus.deleted
        : DeckStatus.active;

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

  static CardEntity cardFromRow(Map<String, dynamic> row) {
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
      sourceDocumentId: row['source_document_id'] as String?,
      sourcePageId: row['source_page_id'] as String?,
      sourcePageNumber: row['source_page_number'] as int?,
      sourceBlockId: row['source_block_id'] as String?,
      sourceQuote: row['source_quote'] as String,
      tags: List<String>.unmodifiable(
        (jsonDecode(row['tags'] as String? ?? '[]') as List).cast<String>(),
      ),
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

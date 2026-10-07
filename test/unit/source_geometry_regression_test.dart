import 'dart:io';
import 'dart:ui';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:memo_mind/core/database/memo_mind_database.dart';
import 'package:memo_mind/features/deck_management/application/get_card_source_trace_use_case.dart';
import 'package:memo_mind/features/deck_management/data/local_deck_repository.dart';
import 'package:memo_mind/features/document_import/data/local_document_import_repository_io.dart';
import 'package:memo_mind/features/document_import/domain/document_import_models.dart';
import 'package:memo_mind/features/document_import/domain/document_import_repository.dart';
import 'package:memo_mind/features/image_normalization/domain/image_normalization_models.dart';
import 'package:memo_mind/features/material_generation/domain/material_generation_models.dart';
import 'package:memo_mind/features/material_generation/domain/source_reference_resolver.dart';
import 'package:memo_mind/features/ocr_editor/application/ocr_orchestrator.dart';
import 'package:memo_mind/features/ocr_editor/data/local_ocr_repository_io.dart';
import 'package:memo_mind/features/ocr_editor/domain/ocr_engine.dart';
import 'package:memo_mind/features/ocr_editor/domain/ocr_models.dart';
import 'package:memo_mind/features/ocr_editor/domain/ocr_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

final _at = DateTime.fromMillisecondsSinceEpoch(1);
const _text = 'Học máy là một tập con của trí tuệ nhân tạo.';

SourcePage _page(
  String path,
  String hash, {
  int cropWidth = 800,
  int cropHeight = 1000,
}) => SourcePage(
  pageId: 'p',
  documentId: 'd',
  pageNumber: 1,
  originalPageNumber: 7,
  source: DocumentPageSource.pdf,
  dataRelativePath: 'documents/d/raw.png',
  absolutePath: '$path.raw.png',
  mimeType: 'image/png',
  fileSizeBytes: 1,
  width: 1000,
  height: 2000,
  sha256: 'a' * 64,
  qualityCode: 'good',
  qualityWarningAccepted: false,
  createdAt: _at,
  normalizedAsset: NormalizedPageAsset(
    pageId: 'p',
    revision: 1,
    relativePath: 'documents/d/crop.png',
    absolutePath: path,
    mimeType: 'image/png',
    fileSizeBytes: 1,
    width: cropWidth,
    height: cropHeight,
    sha256: hash,
    updatedAt: _at,
    parameters: const NormalizationParameters(
      corners: CropQuadrilateral.fullImage(),
    ),
  ),
);

SourceBlock _block({
  String id = 'b',
  String text = _text,
  String? hash,
  int page = 1,
}) => SourceBlock(
  blockId: id,
  documentId: 'd',
  pageId: 'p',
  pageNumber: page,
  orderIndex: 0,
  rawText: text,
  normalizedText: text,
  status: BlockStatus.verified,
  boundingBox: const NormalizedBoundingBox(
    left: .08,
    top: .1,
    width: .4,
    height: .15,
  ),
  boxImageSha256: hash,
  createdAt: _at,
  updatedAt: _at,
);

class _Engine implements OcrEngine {
  int calls = 0;
  Size? size;
  String? path;
  Future<void> Function()? duringRecognition;
  List<ExtractedBlock> blocks = [
    const ExtractedBlock(
      text: _text,
      boundingBox: Rect.fromLTWH(80, 200, 400, 300),
      confidence: .9,
    ),
  ];
  @override
  Future<ExtractedPageOcr> recognizeText({
    required String imagePath,
    required Size imageSize,
  }) async {
    calls++;
    size = imageSize;
    path = imagePath;
    await duringRecognition?.call();
    return ExtractedPageOcr(rawFullText: _text, blocks: blocks);
  }

  @override
  Future<void> dispose() async {}
}

class _Capture implements OcrRepository {
  List<SourceBlock> saved = [];
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
    saved = blocks;
  }

  @override
  Future<void> saveDraft(String documentId) async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Documents implements DocumentImportRepository {
  _Documents(this.page);
  final SourcePage page;
  @override
  Future<ImportedDocument> getDocument(String documentId) async =>
      ImportedDocument(
        documentId: 'd',
        title: 'Machine Learning',
        status: ImportedDocumentStatus.readyForGeneration,
        privacy: DocumentPrivacy.private,
        createdAt: _at,
        updatedAt: _at,
        pages: [page],
      );
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Map<String, Object?> _row(SourceBlock block) => {
  'block_id': block.blockId,
  'document_id': 'd',
  'page_id': 'p',
  'page_number': 1,
  'order_index': 0,
  'raw_text': block.rawText,
  'normalized_text': block.normalizedText,
  'status': 'verified',
  'confidence_source': 'user',
  'has_valid_box': 1,
  'box_left': block.boundingBox!.left,
  'box_top': block.boundingBox!.top,
  'box_width': block.boundingBox!.width,
  'box_height': block.boundingBox!.height,
  'box_image_sha256': block.boxImageSha256,
  'created_at': 1,
  'updated_at': 1,
};

void main() {
  test(
    'cropped and rotated rasters normalize against their own dimensions',
    () async {
      for (final dimensions in [const Size(800, 1000), const Size(1000, 800)]) {
        final page = _page(
          'cropped.png',
          'b' * 64,
          cropWidth: dimensions.width.toInt(),
          cropHeight: dimensions.height.toInt(),
        );
        final capture = _Capture(), engine = _Engine();
        final document = await _Documents(page).getDocument('d');
        await OcrOrchestrator(
          ocrRepository: capture,
          ocrEngine: engine,
        ).processPages(document: document, selectedPages: [page]).drain<void>();
        expect(engine.path, page.normalizedAsset!.absolutePath);
        expect(engine.size, dimensions);
        final block = capture.saved.single;
        expect(
          block.boundingBox!.toRect(dimensions),
          const Rect.fromLTWH(80, 200, 400, 300),
        );
        expect(block.boxImageSha256, page.displayImage.sha256);
        expect(block.hasBoxFor(page), isTrue);
        expect(block.hasBoxFor(_page('new.png', 'c' * 64)), isFalse);
      }
    },
  );

  test('invalid rectangles cannot become plausible source regions', () {
    expect(
      NormalizedBoundingBox.fromRect(
        const Rect.fromLTWH(double.nan, 0, 20, 20),
        const Size(100, 100),
      ),
      isNull,
    );
    expect(
      NormalizedBoundingBox.fromRect(
        const Rect.fromLTWH(120, 0, 20, 20),
        const Size(100, 100),
      ),
      isNull,
    );
    final clipped = NormalizedBoundingBox.fromRect(
      const Rect.fromLTWH(-10, 20, 30, 20),
      const Size(100, 100),
    )!;
    expect(clipped.width, .2);
    expect(clipped.isValid, isTrue);
    expect(
      const NormalizedBoundingBox(
        left: .9,
        top: 0,
        width: .2,
        height: .1,
      ).isValid,
      isFalse,
    );
  });

  test(
    'all card types rebind exact unique evidence without altering content',
    () {
      for (final type in CardType.values) {
        final draft = MaterialDraft(
          id: 'card',
          type: type,
          front: 'Question',
          back: 'Answer',
          sourcePage: 1,
          sourceBlockId: 'wrong',
          sourceQuote: _text,
        );
        final resolved = SourceReferenceResolver.resolveDraft(draft, 'd', [
          _block(id: 'wrong', text: 'Đoạn khác'),
          _block(id: 'right'),
        ]);
        expect(resolved.sourceBlockId, 'right');
        expect(resolved.front, draft.front);
        expect(resolved.back, draft.back);
        expect(resolved.sourceQuote, draft.sourceQuote);
      }
    },
  );

  test('resolver handles NFC/whitespace, ambiguity, deleted sources and wrong pages', () {
    SourceBlock? resolve(
      String quote,
      List<SourceBlock> blocks, {
      int page = 1,
    }) => SourceReferenceResolver.resolve(
      documentId: 'd',
      quote: quote,
      blocks: blocks,
      blockId: 'missing',
      pageNumber: page,
    );
    expect(
      resolve('Học máy là một tập con\n của trí tuệ nhân tạo.', [
        _block(),
      ])?.blockId,
      'b',
    );
    expect(resolve('Máy học thuộc AI', [_block()]), isNull);
    expect(resolve(_text, [_block(id: 'a'), _block(id: 'b')]), isNull);
    expect(
      resolve(_text, [_block().copyWith(status: BlockStatus.deleted)]),
      isNull,
    );
    expect(resolve(_text, [_block(page: 3)])?.pageNumber, 3);
    expect(
      resolve(_text, [
        _block(id: 'a'),
        _block(id: 'b'),
        _block(id: 'c', page: 3),
      ]),
      isNull,
    );
  });

  group('legacy geometry and source links', () {
    late Directory root;
    late Database db;
    late MemoMindDatabase database;
    late SourcePage page;
    late LocalOcrRepository ocr;
    late _Engine engine;
    setUpAll(sqfliteFfiInit);
    setUp(() async {
      root = await Directory.systemTemp.createTemp('source-geometry-');
      final file = File('${root.path}/documents/d/crop.png');
      await file.parent.create(recursive: true);
      final bytes = img.encodePng(img.Image(width: 800, height: 1000));
      await file.writeAsBytes(bytes);
      page = _page(file.path, sha256.convert(bytes).toString());
      db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
      await db.execute('PRAGMA foreign_keys=ON');
      await MemoMindDatabase.createV11(db);
      database = MemoMindDatabase.forTesting(db);
      await db.insert('documents', {
        'document_id': 'd',
        'title': 'Machine Learning',
        'status': 'ready_for_generation',
        'created_at': 1,
        'updated_at': 1,
      });
      await db.insert('source_pages', {
        'page_id': 'p',
        'document_id': 'd',
        'page_number': 1,
        'original_page_number': 7,
        'source': 'pdf',
        'data_relative_path': 'documents/d/raw.png',
        'mime_type': 'image/png',
        'file_size_bytes': 1,
        'width': 1000,
        'height': 2000,
        'sha256': 'a' * 64,
        'quality_code': 'good',
        'quality_warning_accepted': 0,
        'created_at': 1,
        'normalization_status': 'ready',
      });
      await db.insert('page_normalizations', {
        'page_id': 'p',
        'revision': 1,
        'normalized_relative_path': 'documents/d/crop.png',
        'mime_type': 'image/png',
        'file_size_bytes': bytes.length,
        'width': 800,
        'height': 1000,
        'sha256': page.displayImage.sha256,
        'top_left_x': 0,
        'top_left_y': 0,
        'top_right_x': 1,
        'top_right_y': 0,
        'bottom_right_x': 1,
        'bottom_right_y': 1,
        'bottom_left_x': 0,
        'bottom_left_y': 1,
        'rotation_degrees': 0,
        'contrast': 0,
        'updated_at': 1,
      });
      await db.insert(
        'source_blocks',
        _row(_block().copyWith(normalizedText: 'User correction')),
      );
      engine = _Engine();
      ocr = LocalOcrRepository(
        database: database,
        documentRepository: _Documents(page),
        geometryEngine: engine,
      );
    });
    tearDown(() async {
      await database.close();
      await root.delete(recursive: true);
    });

    test(
      'legacy box is recovered once while edits, IDs and approval survive',
      () async {
        final block = (await ocr.getOcrReview('d'))
            .pageReviews
            .single
            .blocks
            .single;
        expect(block.blockId, 'b');
        expect(block.normalizedText, 'User correction');
        expect(block.isVerified, isTrue);
        expect(block.hasBoxFor(page), isTrue);
        expect(block.boundingBox!.top, .2);
        expect(block.boundingBox!.height, .3);
        await ocr.getOcrReview('d');
        expect(engine.calls, 1);
      },
    );

    test(
      'paraphrased or ambiguous raw evidence gets no guessed geometry',
      () async {
        engine.blocks = [
          const ExtractedBlock(
            text: 'Different OCR',
            boundingBox: Rect.fromLTWH(0, 0, 100, 100),
          ),
        ];
        final block = (await ocr.getOcrReview('d'))
            .pageReviews
            .single
            .blocks
            .single;
        expect(block.hasValidBox, isFalse);
        expect(block.normalizedText, 'User correction');
        expect(block.boundingBox, isNull);
      },
    );

    test('OCR repair cannot overwrite a simultaneous text edit', () async {
      engine.duringRecognition = () => db
          .update(
            'source_blocks',
            {'normalized_text': 'Concurrent edit', 'updated_at': 2},
            where: 'block_id=?',
            whereArgs: ['b'],
          )
          .then((_) {});
      final block = (await ocr.getOcrReview('d'))
          .pageReviews
          .single
          .blocks
          .single;
      expect(block.normalizedText, 'Concurrent edit');
      expect(block.boxImageSha256, isNull);
    });

    test(
      'rerunning OCR reuses matched blocks and does not duplicate user edits',
      () async {
        for (var i = 0; i < 2; i++) {
          await ocr.savePageOcrDraft(
            documentId: 'd',
            pageId: 'p',
            pageNumber: 1,
            blocks: [_block(id: 'new-$i', hash: page.displayImage.sha256)],
            rawFullText: _text,
          );
        }
        final rows = await db.query('source_blocks');
        expect(rows.length, 1);
        expect(rows.single['block_id'], 'b');
        expect(rows.single['normalized_text'], 'User correction');
        expect(rows.single['status'], 'verified');
        expect(rows.single['box_image_sha256'], page.displayImage.sha256);
      },
    );

    test(
      'old cards repair their source idempotently without changing scheduling',
      () async {
        await db.insert(
          'source_blocks',
          _row(
            _block(
              id: 'right',
              text: 'Đoạn đúng',
              hash: page.displayImage.sha256,
            ),
          ),
        );
        await db.insert('decks', {
          'deck_id': 'deck',
          'title': 'Deck',
          'created_at': 1,
          'updated_at': 1,
        });
        await db.insert('cards', {
          'card_id': 'card',
          'deck_id': 'deck',
          'type': 'BASIC',
          'status': 'active',
          'front': 'Question',
          'back': 'Answer',
          'source_document_id': 'd',
          'source_page_id': 'p',
          'source_page_number': 1,
          'source_block_id': 'b',
          'source_quote': 'Đoạn đúng',
          'repetitions': 3,
          'interval_days': 6,
          'ease_factor': 2.5,
          'due_date': 9000,
          'created_at': 1,
          'updated_at': 1,
        });
        final decks = LocalDeckRepository(
          database: database,
          supportDirectory: () async => root,
        );
        final card = (await decks.getCardsForDeck('deck')).single;
        final useCase = GetCardSourceTraceUseCase(deckRepository: decks);
        final trace = await useCase.execute(card);
        expect(trace.sourceBlock?.blockId, 'right');
        expect(trace.sourceBlock?.hasValidBox, isTrue);
        expect((await useCase.execute(card)).sourceBlock?.blockId, 'right');
        final row = (await db.query('cards')).single;
        expect(row['source_block_id'], 'right');
        expect(row['front'], 'Question');
        expect(row['repetitions'], 3);
        expect(row['interval_days'], 6);
        expect(row['due_date'], 9000);
        for (final id in ['repeat-1', 'repeat-2']) {
          await db.insert(
            'source_blocks',
            _row(
              _block(id: id, text: 'Repeated', hash: page.displayImage.sha256),
            ),
          );
        }
        await db.update('cards', {
          'source_block_id': 'b',
          'source_quote': 'Repeated',
        });
        final ambiguousCard = (await decks.getCardsForDeck('deck')).single;
        final ambiguous = await useCase.execute(ambiguousCard);
        expect(ambiguous.sourceBlock, isNull);
        expect(ambiguous.warning, isNotNull);
        expect((await db.query('cards')).single['source_block_id'], 'b');
      },
    );

    test(
      'a stale OCR result cannot replace blocks after another crop',
      () async {
        final before = (await db.query('source_blocks')).single;
        await expectLater(
          ocr.savePageOcrDraft(
            documentId: 'd',
            pageId: 'p',
            pageNumber: 1,
            blocks: [_block(id: 'stale', hash: 'c' * 64)],
            rawFullText: _text,
            imageSha256: 'c' * 64,
          ),
          throwsA(isA<OcrFailure>()),
        );
        expect((await db.query('source_blocks')).single, before);
        expect(await db.query('ocr_page_results'), isEmpty);
      },
    );
    test('invalid geometry is rejected before persistence', () async {
      await ocr.addSourceBlock(
        _block(id: 'invalid', hash: page.displayImage.sha256).copyWith(
          boundingBox: const NormalizedBoundingBox(
            left: double.nan,
            top: 0,
            width: .2,
            height: .1,
          ),
        ),
      );
      final row = (await db.query(
        'source_blocks',
        where: "block_id='invalid'",
      )).single;
      expect(row['has_valid_box'], 0);
      expect(row['box_left'], isNull);
    });

    test(
      'startup recovery keeps synchronized metadata whose media is pending',
      () async {
        await db.insert('sync_meta', {
          'table_name': 'documents',
          'entity_id': 'd',
          'version': 1,
          'data': '{}',
          'deleted': 0,
        });
        await db.insert('sync_meta', {
          'table_name': 'source_pages',
          'entity_id': 'p',
          'version': 2,
          'data': '{}',
          'deleted': 0,
        });
        await db.insert('sync_meta', {
          'table_name': 'page_normalizations',
          'entity_id': 'p',
          'version': 3,
          'data': '{}',
          'deleted': 0,
        });
        await File(page.displayPath).delete();
        await LocalDocumentImportRepository(
          database: database,
          supportDirectory: () async => root,
          temporaryDirectory: () async => root,
        ).recoverInterruptedImports();
        expect((await db.query('source_pages')).length, 1);
        expect((await db.query('page_normalizations')).length, 1);
        expect(
          (await db.query('documents')).single['status'],
          'ready_for_generation',
        );
      },
    );
  });

  test('v10 migration preserves frozen payloads and captures the new geometry field', () async {
    sqfliteFfiInit();
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    try {
      await MemoMindDatabase.createV10(db);
      await db.insert('sync_packets', {
        'group_id': 'frozen',
        'payload': '{"unchanged":true}',
        'sequences': '[1]',
      });
      await MemoMindDatabase.migrateV10ToV11(db);
      expect(
        (await db.query('sync_packets')).single['payload'],
        '{"unchanged":true}',
      );
      final triggers = await db.query(
        'sqlite_master',
        where: "type='trigger' AND name='sync_source_blocks_insert'",
      );
      expect(triggers.single['sql'], contains('box_image_sha256'));
      expect(
        (await db.rawQuery('PRAGMA table_info(source_blocks)'))
            .any((r) => r['name'] == 'box_image_sha256'),
        isTrue,
      );
    } finally {
      await db.close();
    }
  });
}

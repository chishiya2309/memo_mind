import 'package:flutter_test/flutter_test.dart';
import 'package:memo_mind/core/database/memo_mind_database.dart';
import 'package:memo_mind/features/deck_management/data/local_deck_repository.dart';
import 'package:memo_mind/features/material_generation/application/generate_flashcards_use_case.dart';
import 'package:memo_mind/features/material_generation/application/save_accepted_cards_use_case.dart';
import 'package:memo_mind/features/material_generation/domain/flashcard_verifier.dart';
import 'package:memo_mind/features/material_generation/domain/material_generation_models.dart';
import 'package:memo_mind/features/material_generation/domain/material_generation_repository.dart';
import 'package:memo_mind/features/ocr_editor/domain/ocr_models.dart';
import 'package:memo_mind/features/ocr_editor/domain/ocr_repository.dart';
import 'package:memo_mind/features/document_import/domain/document_import_models.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _FakeOcrRepository implements OcrRepository {
  _FakeOcrRepository(this.review);
  final OcrDocumentReview review;

  @override
  Future<OcrDocumentReview> getOcrReview(String documentId) async => review;

  @override
  Future<void> addSourceBlock(SourceBlock block) async {}

  @override
  Future<void> confirmOcrReview(String documentId) async {}

  @override
  Future<void> deleteSourceBlock(String blockId) async {}

  @override
  Future<List<SourceBlock>> getPageBlocks(String pageId) async => [];

  @override
  Future<void> recordPageOcrFailure({
    required String documentId,
    required String pageId,
    required String errorMessage,
  }) async {}

  @override
  Future<void> restoreSourceBlock(String blockId) async {}

  @override
  Future<void> saveDraft(String documentId) async {}

  @override
  Future<void> savePageOcrDraft({
    required String documentId,
    required String pageId,
    required int pageNumber,
    required List<SourceBlock> blocks,
    required String rawFullText,
    String? language,
  }) async {}

  @override
  Future<void> updateSourceBlock(SourceBlock block) async {}
}

class _FakeMaterialGenRepository implements MaterialGenerationRepository {
  _FakeMaterialGenRepository({required this.generatedCards});
  final List<MaterialDraft> generatedCards;

  @override
  Future<MaterialGenerationResult> generateMaterials({
    required String documentId,
    required Set<CardType> types,
    QuantityMode quantityMode = QuantityMode.auto,
    int? desiredCount,
    required List<SourceBlock> sourceBlocks,
  }) async {
    return MaterialGenerationResult(
      cards: generatedCards,
      totalGenerated: generatedCards.length,
      validCount: generatedCards.length,
      discardedCount: 0,
    );
  }

  @override
  Future<MaterialDraft> regenerateSingleCard({
    required SourceBlock sourceBlock,
    required CardType type,
  }) async {
    return generatedCards.first;
  }
}

SourcePage _createTestPage({
  required String pageId,
  required String documentId,
  int pageNumber = 1,
}) {
  return SourcePage(
    pageId: pageId,
    documentId: documentId,
    pageNumber: pageNumber,
    originalPageNumber: pageNumber,
    source: DocumentPageSource.camera,
    dataRelativePath: 'pages/$pageId.jpg',
    absolutePath: '/storage/pages/$pageId.jpg',
    mimeType: 'image/jpeg',
    fileSizeBytes: 1000,
    width: 800,
    height: 600,
    sha256: 'dummy',
    qualityCode: 'good',
    qualityWarningAccepted: false,
    createdAt: DateTime.now(),
  );
}

void main() {
  setUpAll(sqfliteFfiInit);

  group('FlashcardVerifier Tests', () {
    test('isQuoteSupported matches exact and normalized substrings', () {
      const source =
          'Trí tuệ nhân tạo (Artificial Intelligence) là một nhánh của khoa học máy tính.';

      expect(
        FlashcardVerifier.isQuoteSupported('Trí tuệ nhân tạo', source),
        isTrue,
      );
      expect(
        FlashcardVerifier.isQuoteSupported('trí tuệ nhân tạo', source),
        isFalse,
      );
      expect(
        FlashcardVerifier.isQuoteSupported(
          'nhánh của khoa học máy tính',
          source,
        ),
        isTrue,
      );
      expect(
        FlashcardVerifier.isQuoteSupported('Lịch sử thế giới', source),
        isFalse,
      );
    });

    test(
      'verifyEditedCard marks card needsSourceCheck if quote is missing',
      () {
        final block = SourceBlock(
          blockId: 'blk-1',
          documentId: 'doc-1',
          pageId: 'page-1',
          pageNumber: 1,
          orderIndex: 0,
          rawText: 'Việt Nam nằm ở Đông Nam Á.',
          normalizedText: 'Việt Nam nằm ở Đông Nam Á.',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );

        final card = MaterialDraft(
          id: 'c-1',
          type: CardType.basic,
          front: 'Việt Nam ở đâu?',
          back: 'Đông Nam Á',
          sourcePage: 1,
          sourceBlockId: 'blk-1',
          sourceQuote: 'Châu Âu xa xôi', // Quote not in block
        );

        final edited = FlashcardVerifier.verifyEditedCard(
          card: card,
          sourceBlock: block,
          newQuestion: 'Việt Nam nằm ở khu vực nào?',
          newAnswer: 'Đông Nam Á',
        );

        expect(edited.status, DraftCardStatus.needsSourceCheck);
        expect(edited.isEdited, isTrue);
      },
    );

    test(
      'verifyEditedCard throws FormatException if cloze question lacks [...]',
      () {
        final card = MaterialDraft(
          id: 'c-1',
          type: CardType.cloze,
          front: 'Thủ đô là [...]',
          back: 'Hà Nội',
          sourcePage: 1,
          sourceBlockId: 'blk-1',
          sourceQuote: 'Hà Nội',
        );

        expect(
          () => FlashcardVerifier.verifyEditedCard(
            card: card,
            sourceBlock: null,
            newQuestion: 'Thủ đô của Việt Nam là Hà Nội', // missing [...]
            newAnswer: 'Hà Nội',
          ),
          throwsFormatException,
        );
      },
    );
  });

  group('GenerateMaterialsUseCase Tests', () {
    test('filters verified blocks and calls generation repository', () async {
      final block1 = SourceBlock(
        blockId: 'b-1',
        documentId: 'doc-1',
        pageId: 'p-1',
        pageNumber: 1,
        orderIndex: 0,
        rawText: 'Khối 1',
        normalizedText: 'Khối 1 đã xác nhận',
        status: BlockStatus.verified,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final block2 = SourceBlock(
        blockId: 'b-2',
        documentId: 'doc-1',
        pageId: 'p-1',
        pageNumber: 1,
        orderIndex: 1,
        rawText: 'Khối 2',
        normalizedText: 'Khối 2 bản nháp',
        status: BlockStatus.draft, // Unverified
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final page = _createTestPage(pageId: 'p-1', documentId: 'doc-1');

      final review = OcrDocumentReview(
        document: ImportedDocument(
          documentId: 'doc-1',
          title: 'Tài liệu test',
          status: ImportedDocumentStatus.readyForGeneration,
          privacy: DocumentPrivacy.private,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          pages: [page],
        ),
        pageReviews: [
          OcrPageReview(
            pageId: 'p-1',
            documentId: 'doc-1',
            pageNumber: 1,
            status: OcrPageStatus.completed,
            blocks: [block1, block2],
            updatedAt: DateTime.now(),
          ),
        ],
      );

      final cardDraft = MaterialDraft(
        id: 'gen-c-1',
        type: CardType.basic,
        front: 'Câu hỏi?',
        back: 'Đáp án',
        sourcePage: 1,
        sourceBlockId: 'b-1',
        sourceQuote: 'Khối 1 đã xác nhận',
      );

      final useCase = GenerateMaterialsUseCase(
        ocrRepository: _FakeOcrRepository(review),
        generationRepository: _FakeMaterialGenRepository(
          generatedCards: [cardDraft],
        ),
      );

      final result = await useCase.execute(
        documentId: 'doc-1',
        types: {CardType.basic},
        desiredCount: 1,
      );

      expect(result.validCount, 1);
      expect(result.cards.first.sourceBlockId, 'b-1');
    });

    test(
      'throws MaterialGenerationFailure if no blocks are verified',
      () async {
        final block = SourceBlock(
          blockId: 'b-draft',
          documentId: 'doc-1',
          pageId: 'p-1',
          pageNumber: 1,
          orderIndex: 0,
          rawText: 'Khối nháp',
          normalizedText: 'Khối nháp',
          status: BlockStatus.draft,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );

        final page = _createTestPage(pageId: 'p-1', documentId: 'doc-1');

        final review = OcrDocumentReview(
          document: ImportedDocument(
            documentId: 'doc-1',
            title: 'Tài liệu test',
            status: ImportedDocumentStatus.pendingOcrReview,
            privacy: DocumentPrivacy.private,
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
            pages: [page],
          ),
          pageReviews: [
            OcrPageReview(
              pageId: 'p-1',
              documentId: 'doc-1',
              pageNumber: 1,
              status: OcrPageStatus.completed,
              blocks: [block],
              updatedAt: DateTime.now(),
            ),
          ],
        );

        final useCase = GenerateMaterialsUseCase(
          ocrRepository: _FakeOcrRepository(review),
          generationRepository: _FakeMaterialGenRepository(generatedCards: []),
        );

        expect(
          () => useCase.execute(
            documentId: 'doc-1',
            types: {CardType.basic},
            desiredCount: 1,
          ),
          throwsA(isA<MaterialGenerationFailure>()),
        );
      },
    );
  });

  group('SaveAcceptedCardsUseCase Tests', () {
    late Database db;
    late LocalDeckRepository deckRepo;

    setUp(() async {
      db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
      await db.execute('PRAGMA foreign_keys = ON');
      await MemoMindDatabase.createV8(db);
      deckRepo = LocalDeckRepository(database: MemoMindDatabase.forTesting(db));
    });

    tearDown(() async {
      await db.close();
    });

    test('saves accepted cards and updates deck card count', () async {
      // 1. Insert document, page, and block into DB
      await db.insert('documents', {
        'document_id': 'doc-save',
        'title': 'Tài liệu lưu',
        'status': 'ready_for_generation',
        'privacy': 'private',
        'page_count': 1,
        'created_at': 1,
        'updated_at': 1,
      });

      await db.insert('source_pages', {
        'page_id': 'p-save',
        'document_id': 'doc-save',
        'page_number': 1,
        'original_page_number': 1,
        'source': 'camera',
        'data_relative_path': 'save.jpg',
        'mime_type': 'image/jpeg',
        'file_size_bytes': 100,
        'width': 800,
        'height': 600,
        'sha256': 'dummy',
        'quality_code': 'good',
        'quality_warning_accepted': 0,
        'created_at': 1,
        'normalization_status': 'source_ready',
      });

      await db.insert('source_blocks', {
        'block_id': 'blk-save',
        'document_id': 'doc-save',
        'page_id': 'p-save',
        'page_number': 1,
        'order_index': 0,
        'raw_text': 'Nội dung',
        'normalized_text': 'Nội dung chuẩn',
        'status': 'verified',
        'confidence_source': 'mlkit',
        'created_at': 1,
        'updated_at': 1,
      });

      // 2. Create Deck
      final deck = await deckRepo.createDeck(title: 'Deck Toán học');

      // 3. Fake OCR review
      final page = _createTestPage(pageId: 'p-save', documentId: 'doc-save');
      final review = OcrDocumentReview(
        document: ImportedDocument(
          documentId: 'doc-save',
          title: 'Tài liệu lưu',
          status: ImportedDocumentStatus.readyForGeneration,
          privacy: DocumentPrivacy.private,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          pages: [page],
        ),
        pageReviews: [
          OcrPageReview(
            pageId: 'p-save',
            documentId: 'doc-save',
            pageNumber: 1,
            status: OcrPageStatus.completed,
            blocks: [
              SourceBlock(
                blockId: 'blk-save',
                documentId: 'doc-save',
                pageId: 'p-save',
                pageNumber: 1,
                orderIndex: 0,
                rawText: 'Nội dung',
                normalizedText: 'Nội dung chuẩn',
                status: BlockStatus.verified,
                createdAt: DateTime.now(),
                updatedAt: DateTime.now(),
              ),
            ],
            updatedAt: DateTime.now(),
          ),
        ],
      );

      final saveUseCase = SaveAcceptedCardsUseCase(
        deckRepository: deckRepo,
        ocrRepository: _FakeOcrRepository(review),
      );

      final acceptedCard = MaterialDraft(
        id: 'card-1',
        type: CardType.basic,
        front: 'Câu hỏi 1?',
        back: 'Đáp án 1',
        sourcePage: 1,
        sourceBlockId: 'blk-save',
        sourceQuote: 'Nội dung chuẩn',
        status: DraftCardStatus.accepted,
      );

      final rejectedCard = MaterialDraft(
        id: 'card-2',
        type: CardType.basic,
        front: 'Câu hỏi 2?',
        back: 'Đáp án 2',
        sourcePage: 1,
        sourceBlockId: 'blk-save',
        sourceQuote: 'Nội dung chuẩn',
        status: DraftCardStatus.rejected, // Should not be saved (BR07-10)
      );

      final count = await saveUseCase.execute(
        deckId: deck.id,
        documentId: 'doc-save',
        drafts: [acceptedCard, rejectedCard],
      );

      expect(count, 1);

      // Verify in DB
      final savedCards = await deckRepo.getCardsForDeck(deck.id);
      expect(savedCards.length, 1);
      expect(savedCards.first.id, 'card-1');
      expect(savedCards.first.front, 'Câu hỏi 1?');

      final updatedDeck = await deckRepo.getDeckById(deck.id);
      expect(updatedDeck?.cardCount, 1);
    });

    test('returns zero without writes when no cards are accepted', () async {
      final saveUseCase = SaveAcceptedCardsUseCase(
        deckRepository: deckRepo,
        ocrRepository: _FakeOcrRepository(
          OcrDocumentReview(
            document: ImportedDocument(
              documentId: 'doc-0',
              title: 'Tài liệu',
              status: ImportedDocumentStatus.readyForGeneration,
              privacy: DocumentPrivacy.private,
              createdAt: DateTime.now(),
              updatedAt: DateTime.now(),
              pages: [],
            ),
            pageReviews: [],
          ),
        ),
      );

      expect(
        await saveUseCase.execute(
          deckId: 'deck-1',
          documentId: 'doc-0',
          drafts: [
            MaterialDraft(
              id: 'c-pending',
              type: CardType.basic,
              front: 'Q',
              back: 'A',
              sourcePage: 1,
              sourceBlockId: 'b-1',
              sourceQuote: 'quote',
              status: DraftCardStatus.pending,
            ),
          ],
        ),
        0,
      );
    });
  });
}

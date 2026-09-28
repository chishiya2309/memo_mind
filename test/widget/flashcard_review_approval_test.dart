import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memo_mind/features/deck_management/domain/deck_models.dart';
import 'package:memo_mind/features/deck_management/domain/deck_repository.dart';
import 'package:memo_mind/features/document_import/domain/document_import_models.dart';
import 'package:memo_mind/features/material_generation/domain/material_generation_models.dart';
import 'package:memo_mind/features/material_generation/domain/material_generation_repository.dart';
import 'package:memo_mind/features/material_generation/presentation/flashcard_review_approval_screen.dart';
import 'package:memo_mind/features/material_generation/presentation/source_inspection_modal.dart';
import 'package:memo_mind/features/ocr_editor/domain/ocr_models.dart';
import 'package:memo_mind/features/ocr_editor/domain/ocr_repository.dart';
import 'package:memo_mind/shared/theme/memo_theme.dart';

class _MockDeckRepository implements DeckRepository {
  final List<Deck> decks = [
    Deck(
      id: 'deck-1',
      title: 'Deck Lịch sử',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    ),
  ];
  final List<CardEntity> savedCards = [];

  @override
  Future<List<Deck>> getDecks() async => decks;

  @override
  Future<Deck?> getDeckById(String deckId) async =>
      decks.firstWhere((d) => d.id == deckId);

  @override
  Future<Deck> createDeck({
    required String title,
    String? description,
    dynamic tone,
  }) async {
    final d = Deck(
      id: 'deck-new',
      title: title,
      description: description,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    decks.add(d);
    return d;
  }

  @override
  Future<List<CardEntity>> getCardsForDeck(String deckId) async => savedCards;

  @override
  Future<void> saveCardsToDeck({
    required String deckId,
    required List<CardEntity> cards,
  }) async {
    savedCards.addAll(cards);
  }
}

class _MockOcrRepository implements OcrRepository {
  @override
  Future<OcrDocumentReview> getOcrReview(String documentId) async {
    return OcrDocumentReview(
      document: ImportedDocument(
        documentId: documentId,
        title: 'Tài liệu Test',
        status: ImportedDocumentStatus.readyForGeneration,
        privacy: DocumentPrivacy.private,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        pages: [],
      ),
      pageReviews: [
        OcrPageReview(
          pageId: 'page-1',
          documentId: documentId,
          pageNumber: 1,
          status: OcrPageStatus.completed,
          blocks: [
            SourceBlock(
              blockId: 'blk-1',
              documentId: documentId,
              pageId: 'page-1',
              pageNumber: 1,
              orderIndex: 0,
              rawText: 'Nguyên văn khối nguồn',
              normalizedText: 'Nguyên văn khối nguồn',
              status: BlockStatus.verified,
              createdAt: DateTime.now(),
              updatedAt: DateTime.now(),
            ),
          ],
          updatedAt: DateTime.now(),
        ),
      ],
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MockMaterialGenRepo implements MaterialGenerationRepository {
  @override
  Future<FlashcardGenerationResult> generateFlashcards({
    required String documentId,
    required FlashcardFormat format,
    required int desiredCount,
    required List<SourceBlock> sourceBlocks,
  }) async {
    return const FlashcardGenerationResult(
      cards: [],
      totalGenerated: 0,
      validCount: 0,
      discardedCount: 0,
    );
  }

  @override
  Future<FlashcardDraft> regenerateSingleCard({
    required SourceBlock sourceBlock,
    required FlashcardFormat format,
  }) async {
    return FlashcardDraft(
      id: 'regen-card',
      format: format,
      question: 'Câu hỏi mới sau khi tạo lại?',
      answer: 'Đáp án mới',
      sourcePage: sourceBlock.pageNumber,
      sourceBlockId: sourceBlock.blockId,
      sourceQuote: sourceBlock.normalizedText,
      status: DraftCardStatus.pending,
    );
  }
}

void main() {
  testWidgets('FlashcardReviewApprovalScreen renders cards and toggles acceptance', (tester) async {
    final mockDeckRepo = _MockDeckRepository();
    final mockOcrRepo = _MockOcrRepository();
    final mockGenRepo = _MockMaterialGenRepo();

    final card1 = const FlashcardDraft(
      id: 'c-1',
      format: FlashcardFormat.qa,
      question: 'Thủ đô của Việt Nam?',
      answer: 'Hà Nội',
      sourcePage: 1,
      sourceBlockId: 'blk-1',
      sourceQuote: 'Hà Nội là thủ đô',
      status: DraftCardStatus.pending,
    );

    final card2 = const FlashcardDraft(
      id: 'c-2',
      format: FlashcardFormat.cloze,
      question: 'Việt Nam có thủ đô là [...]',
      answer: 'Hà Nội',
      sourcePage: 1,
      sourceBlockId: 'blk-1',
      sourceQuote: 'Hà Nội là thủ đô',
      status: DraftCardStatus.pending,
    );

    final block = SourceBlock(
      blockId: 'blk-1',
      documentId: 'doc-1',
      pageId: 'page-1',
      pageNumber: 1,
      orderIndex: 0,
      rawText: 'Nguyên văn khối nguồn',
      normalizedText: 'Hà Nội là thủ đô của Việt Nam',
      status: BlockStatus.verified,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: MemoTheme.light,
        home: FlashcardReviewApprovalScreen(
          documentId: 'doc-1',
          documentTitle: 'Tài liệu Lịch sử',
          initialCards: [card1, card2],
          sourceBlocks: [block],
          sourcePages: const [],
          deckRepository: mockDeckRepo,
          ocrRepository: mockOcrRepo,
          generationRepository: mockGenRepo,
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Verify header and initial status
    expect(find.text('Duyệt Flashcard'), findsOneWidget);
    expect(find.text('Tài liệu Lịch sử'), findsOneWidget);
    expect(find.text('Đã chọn 0 / 2'), findsOneWidget);
    expect(find.text('Lưu các thẻ đã chọn (0)'), findsOneWidget);

    // Verify card contents
    expect(find.text('Thủ đô của Việt Nam?'), findsOneWidget);
    expect(find.text('Hỏi – đáp'), findsOneWidget);
    expect(find.text('Điền khuyết'), findsOneWidget);
    expect(find.text('Chưa duyệt'), findsNWidgets(2));

    // Tap "Chấp nhận" on first card
    final acceptButtons = find.widgetWithText(FilledButton, 'Chấp nhận');
    expect(acceptButtons, findsNWidgets(2));
    await tester.tap(acceptButtons.first);
    await tester.pumpAndSettle();

    // Verify acceptance update
    expect(find.text('Đã chọn 1 / 2'), findsOneWidget);
    expect(find.text('Lưu các thẻ đã chọn (1)'), findsOneWidget);
    expect(find.text('Đã chấp nhận'), findsNWidgets(2));

    // Tap "Xem nguồn"
    final inspectSourceBtn = find.text('Xem nguồn').first;
    await tester.tap(inspectSourceBtn);
    await tester.pumpAndSettle();

    // Modal appears
    expect(find.byType(SourceInspectionModal), findsOneWidget);
    expect(find.text('Đối chiếu nguồn dẫn chứng'), findsOneWidget);
    expect(find.text('"Hà Nội là thủ đô"'), findsOneWidget);

    // Close modal
    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pumpAndSettle();

    // Tap "Chọn hết"
    await tester.tap(find.text('Chọn hết'));
    await tester.pumpAndSettle();
    expect(find.text('Đã chọn 2 / 2'), findsOneWidget);
    expect(find.text('Lưu các thẻ đã chọn (2)'), findsOneWidget);
  });
}

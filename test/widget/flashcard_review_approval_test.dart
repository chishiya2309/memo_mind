import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:memo_mind/features/material_generation/presentation/material_generation_flow.dart';
import 'package:memo_mind/features/deck_management/presentation/deck_detail_screen.dart';
import 'package:memo_mind/features/deck_management/presentation/library_decks_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memo_mind/features/deck_management/domain/deck_models.dart';
import 'package:memo_mind/features/deck_management/domain/deck_repository.dart';
import 'package:memo_mind/features/home/domain/home_dashboard_data.dart';
import 'package:memo_mind/features/document_import/domain/document_import_models.dart';
import 'package:memo_mind/features/material_generation/domain/material_generation_models.dart';
import 'package:memo_mind/features/material_generation/domain/material_generation_repository.dart';
import 'package:memo_mind/features/material_generation/presentation/flashcard_review_approval_screen.dart';
import 'package:memo_mind/features/material_generation/presentation/flashcard_edit_dialog.dart';
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
  bool failSave = false;

  @override
  Future<List<Deck>> getDecks() async => decks;

  @override
  Future<Deck?> getDeckById(String deckId) async =>
      decks.firstWhere((d) => d.id == deckId);

  @override
  Future<Deck> createDeck({
    required String title,
    String? description,
    DeckTone tone = DeckTone.indigo,
    List<String> tags = const [],
  }) async {
    final d = Deck(
      id: 'deck-new',
      title: title,
      description: description,
      tone: tone,
      tags: tags,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    decks.add(d);
    return d;
  }

  @override
  Future<Deck> updateDeck(
    String deckId, {
    required String title,
    String? description,
    DeckTone? tone,
    List<String>? tags,
  }) async {
    final index = decks.indexWhere((d) => d.id == deckId);
    final d = decks[index].copyWith(
      title: title,
      description: description,
      tone: tone,
      tags: tags,
    );
    decks[index] = d;
    return d;
  }

  @override
  Future<void> deleteDeck(String deckId) async =>
      decks.removeWhere((d) => d.id == deckId);
  @override
  Future<void> deleteCard(String cardId) async =>
      savedCards.removeWhere((c) => c.id == cardId);
  @override
  Future<CardSourceTrace> getCardSourceTrace(CardEntity card) async =>
      CardSourceTrace(documentTitle: '', sourceQuote: card.sourceQuote);
  @override
  Future<CardEntity> createManualCard({
    required String deckId,
    required CardContent content,
  }) async => throw UnimplementedError('Not used by approval tests.');
  @override
  Future<CardEntity> updateCard(
    String cardId, {
    required CardContent content,
  }) async => throw UnimplementedError('Not used by approval tests.');

  @override
  Future<List<CardEntity>> getCardsForDeck(String deckId) async => savedCards;

  @override
  Future<void> saveCardsToDeck({
    required String deckId,
    required List<CardEntity> cards,
  }) async {
    if (failSave) {
      throw const MaterialGenerationFailure(
        MaterialGenerationFailureCode.storageError,
        'Deck đích không còn tồn tại. Vui lòng chọn lại deck.',
      );
    }
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
  List<MaterialDraft> generatedCards = [];
  int calls = 0;
  bool failOnce = false;
  final requestedCounts = <int?>[];
  @override
  Future<MaterialGenerationResult> generateMaterials({
    required String documentId,
    required Set<CardType> types,
    QuantityMode quantityMode = QuantityMode.auto,
    int? desiredCount,
    required List<SourceBlock> sourceBlocks,
  }) async {
    calls++;
    requestedCounts.add(desiredCount);
    if (failOnce && calls == 1) {
      throw const MaterialGenerationFailure(
        MaterialGenerationFailureCode.serviceQuotaOrTimeout,
        'AI quá thời gian chờ.',
      );
    }
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
    return MaterialDraft(
      id: 'regen-card',
      type: type,
      front: 'Câu hỏi mới sau khi tạo lại?',
      back: 'Đáp án mới',
      sourcePage: sourceBlock.pageNumber,
      sourceBlockId: sourceBlock.blockId,
      sourceQuote: sourceBlock.normalizedText,
      status: DraftCardStatus.pending,
    );
  }
}

void main() {
  testWidgets(
    'FlashcardReviewApprovalScreen renders cards and toggles acceptance',
    (tester) async {
      tester.view.physicalSize = const Size(900, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final mockDeckRepo = _MockDeckRepository();
      final mockOcrRepo = _MockOcrRepository();
      final mockGenRepo = _MockMaterialGenRepo();

      final card1 = const MaterialDraft(
        id: 'c-1',
        type: CardType.basic,
        front: 'Thủ đô của Việt Nam?',
        back: 'Hà Nội',
        sourcePage: 1,
        sourceBlockId: 'blk-1',
        sourceQuote: 'Hà Nội là thủ đô',
        status: DraftCardStatus.pending,
      );

      final card2 = const MaterialDraft(
        id: 'c-2',
        type: CardType.cloze,
        front: 'Việt Nam có thủ đô là [...]',
        back: 'Hà Nội',
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
            targetDeck: mockDeckRepo.decks.first,
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
      expect(find.text('Duyệt học liệu'), findsOneWidget);
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
    },
  );
  testWidgets(
    'MCQ preview shows all options and editing requires a new approval',
    (tester) async {
      final deckRepo = _MockDeckRepository();
      final ocrRepo = _MockOcrRepository();
      final generationRepo = _MockMaterialGenRepo();
      final now = DateTime.now();
      final block = SourceBlock(
        blockId: 'blk-1',
        documentId: 'doc-1',
        pageId: 'page-1',
        pageNumber: 1,
        orderIndex: 0,
        rawText: 'Nguyên văn khối nguồn',
        normalizedText: 'Hà Nội là thủ đô của Việt Nam',
        status: BlockStatus.verified,
        createdAt: now,
        updatedAt: now,
      );
      final card = MaterialDraft(
        id: 'mcq-1',
        type: CardType.mcq,
        front: 'Chọn thủ đô Việt Nam:',
        back: 'Hà Nội',
        sourcePage: 1,
        sourceBlockId: 'blk-1',
        sourceQuote: 'Hà Nội là thủ đô',
        options: const [
          McqOption(optionId: 'A', text: 'Hà Nội'),
          McqOption(optionId: 'B', text: 'Huế'),
          McqOption(optionId: 'C', text: 'Đà Nẵng'),
          McqOption(optionId: 'D', text: 'Cần Thơ'),
        ],
        correctOptionId: 'A',
        explanation: 'Nguồn ghi Hà Nội là thủ đô.',
        status: DraftCardStatus.accepted,
      );
      tester.view.physicalSize = const Size(900, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: MemoTheme.light,
          home: FlashcardReviewApprovalScreen(
            documentId: 'doc-1',
            documentTitle: 'Tài liệu',
            targetDeck: deckRepo.decks.first,
            initialCards: [card],
            sourceBlocks: [block],
            sourcePages: const [],
            deckRepository: deckRepo,
            ocrRepository: ocrRepo,
            generationRepository: generationRepo,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('A. Hà Nội'), findsOneWidget);
      expect(find.text('B. Huế'), findsOneWidget);
      expect(find.text('C. Đà Nẵng'), findsOneWidget);
      expect(find.text('D. Cần Thơ'), findsOneWidget);
      await tester.tap(find.byTooltip('Chỉnh sửa thẻ'));
      await tester.pumpAndSettle();
      expect(find.byType(FlashcardEditDialog), findsOneWidget);
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('B').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Lưu thay đổi'));
      await tester.pumpAndSettle();
      expect(find.text('Huế'), findsOneWidget);
      expect(find.text('Đã chọn 0 / 1'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Chấp nhận'), findsOneWidget);
      expect(
        find.text('Giải thích: Nguồn ghi Hà Nội là thủ đô.'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'warnings can be saved, structural errors stay visible, retry preserves selection',
    (tester) async {
      tester.view.physicalSize = const Size(900, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final decks = _MockDeckRepository()..failSave = true;
      final cards = [
        for (final id in ['one', 'two'])
          MaterialDraft(
            id: id,
            type: CardType.basic,
            front: 'Câu hỏi trùng?',
            back: 'Đáp án',
            sourcePage: 9,
            sourceBlockId: 'missing',
            sourceQuote: 'Trích dẫn chưa khớp',
          ),
        MaterialDraft.fromReviewJson('broken', {
          'type': 'MCQ',
          'front': 'Câu lỗi',
          'back': '',
          'options': [],
        }),
      ];
      MaterialSaveResult? saved;
      await tester.pumpWidget(
        MaterialApp(
          theme: MemoTheme.light,
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  saved = await Navigator.of(context).push<MaterialSaveResult>(
                    MaterialPageRoute<MaterialSaveResult>(
                      builder: (_) => FlashcardReviewApprovalScreen(
                        documentId: 'doc-1',
                        documentTitle: 'Nguồn',
                        targetDeck: decks.decks.first,
                        initialCards: cards,
                        sourceBlocks: const [],
                        sourcePages: const [],
                        deckRepository: decks,
                        ocrRepository: _MockOcrRepository(),
                        generationRepository: _MockMaterialGenRepo(),
                      ),
                    ),
                  );
                },
                child: const Text('Mở duyệt'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Mở duyệt'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Chọn hết'));
      await tester.pumpAndSettle();
      expect(find.text('Đã chọn 2 / 3'), findsOneWidget);
      await tester.tap(find.text('Cần sửa'));
      await tester.pumpAndSettle();
      expect(find.text('Câu lỗi'), findsOneWidget);
      expect(find.text('Câu hỏi trùng?'), findsNothing);
      await tester.tap(find.text('Tất cả'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Lưu các thẻ đã chọn (2)'));
      await tester.pumpAndSettle();
      expect(saved, isNull);
      expect(decks.savedCards, isEmpty);
      expect(find.text('Đã chọn 2 / 3'), findsOneWidget);
      decks.failSave = false;
      await tester.tap(find.text('Lưu các thẻ đã chọn (2)'));
      await tester.pumpAndSettle();
      expect(saved, (deckId: 'deck-1', savedCount: 2));
      expect(decks.savedCards.length, 2);
      expect(decks.savedCards.every((c) => c.sourceBlockId == null), isTrue);
      expect(find.text('Mở duyệt'), findsOneWidget);
    },
  );

  testWidgets(
    'remove can be undone, back protects review, editing removes duplicate warning',
    (tester) async {
      tester.view.physicalSize = const Size(900, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final decks = _MockDeckRepository();
      final card = MaterialDraft(
        id: 'one',
        type: CardType.basic,
        front: 'Câu hỏi trùng?',
        back: 'Đáp án',
        sourcePage: 1,
        sourceBlockId: 'b',
        sourceQuote: 'Nguồn',
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: MemoTheme.light,
          home: FlashcardReviewApprovalScreen(
            documentId: 'doc-1',
            documentTitle: 'Nguồn',
            targetDeck: decks.decks.first,
            initialCards: [
              card,
              card.copyWith(id: 'two'),
            ],
            sourceBlocks: const [],
            sourcePages: const [],
            deckRepository: decks,
            ocrRepository: _MockOcrRepository(),
            generationRepository: _MockMaterialGenRepo(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Câu hỏi giống thẻ 2.'), findsOneWidget);
      await tester.tap(find.byTooltip('Loại bỏ thẻ').first);
      await tester.pumpAndSettle();
      expect(find.text('Đã chọn 0 / 1'), findsOneWidget);
      await tester.tap(find.text('Hoàn tác'));
      await tester.pumpAndSettle();
      expect(find.text('Đã chọn 0 / 2'), findsOneWidget);
      await tester.tap(find.byTooltip('Chỉnh sửa thẻ').first);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('edit-front')),
        'Câu hỏi khác?',
      );
      await tester.tap(find.text('Lưu thay đổi'));
      await tester.pumpAndSettle();
      expect(find.text('Câu hỏi giống thẻ 2.'), findsNothing);
      expect(find.text('Câu hỏi giống thẻ 1.'), findsNothing);
      final context = tester.element(
        find.byType(FlashcardReviewApprovalScreen),
      );
      Navigator.of(context).maybePop();
      await tester.pumpAndSettle();
      expect(find.text('Rời màn duyệt?'), findsOneWidget);
      await tester.tap(find.text('Tiếp tục duyệt'));
      await tester.pumpAndSettle();
      expect(find.text('Câu hỏi khác?'), findsOneWidget);
    },
  );

  for (final entry in ['ảnh', 'PDF']) {
    testWidgets('saved $entry flow opens deck then library and never OCR', (
      tester,
    ) async {
      final decks = _MockDeckRepository();
      final navigator = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigator,
          theme: MemoTheme.light,
          home: const Scaffold(body: Text('Trang chủ')),
        ),
      );
      navigator.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => Scaffold(body: Text('Nhập $entry')),
        ),
      );
      await tester.pumpAndSettle();
      navigator.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('OCR')),
        ),
      );
      await tester.pumpAndSettle();
      MaterialGenerationFlow.openSavedDeck(
        navigator: navigator.currentState!,
        decks: decks,
        result: (deckId: 'deck-1', savedCount: 2),
      );
      await tester.pumpAndSettle();
      expect(find.byType(DeckDetailScreen), findsOneWidget);
      expect(find.text('Đã thêm 2 thẻ vào deck.'), findsOneWidget);
      navigator.currentState!.pop();
      await tester.pumpAndSettle();
      expect(find.byType(LibraryDecksScreen), findsOneWidget);
      expect(find.text('OCR'), findsNothing);
      expect(find.text('Nhập $entry'), findsNothing);
      navigator.currentState!.pop();
      await tester.pumpAndSettle();
      expect(find.text('Trang chủ'), findsOneWidget);
    });
  }

  testWidgets(
    'generation retry retains config, changed deck is opened after saving',
    (tester) async {
      tester.view.physicalSize = const Size(900, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final decks = _MockDeckRepository();
      final changedDeck = await decks.createDeck(title: 'Deck mới');
      final ocr = _MockOcrRepository();
      final review = await ocr.getOcrReview('doc-1');
      final generation = _MockMaterialGenRepo()
        ..failOnce = true
        ..generatedCards = [
          const MaterialDraft(
            id: 'generated',
            type: CardType.basic,
            front: 'Câu hỏi mới?',
            back: 'Đáp án',
            sourcePage: 1,
            sourceBlockId: 'blk-1',
            sourceQuote: 'Nguyên văn khối nguồn',
          ),
        ];
      await tester.pumpWidget(
        MaterialApp(
          theme: MemoTheme.light,
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => MaterialGenerationFlow.start(
                  context: context,
                  document: review.document,
                  ocrRepository: ocr,
                  deckRepository: decks,
                  generationRepository: generation,
                ),
                child: const Text('Bắt đầu'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Bắt đầu'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Tùy chỉnh'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('material-count')), '12');
      await tester.tap(find.text('Chọn deck đích'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Deck Lịch sử'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Tạo học liệu'));
      await tester.pumpAndSettle();
      expect(find.text('AI quá thời gian chờ.'), findsOneWidget);
      await tester.tap(find.text('Thử lại'));
      await tester.pumpAndSettle();
      expect(generation.requestedCounts, [12, 12]);
      expect(find.byType(FlashcardReviewApprovalScreen), findsOneWidget);
      await tester.tap(find.text('Đổi deck'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Deck mới'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Chọn hết'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Lưu các thẻ đã chọn (1)'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<DeckDetailScreen>(find.byType(DeckDetailScreen)).deckId,
        changedDeck.id,
      );
      expect(decks.savedCards.single.deckId, changedDeck.id);
    },
  );

  testWidgets('regeneration keeps surplus and resets approval', (tester) async {
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final decks = _MockDeckRepository();
    final ocr = _MockOcrRepository();
    final review = await ocr.getOcrReview('doc-1');
    const card = MaterialDraft(
      id: 'original',
      type: CardType.basic,
      front: 'Câu hỏi?',
      back: 'Đáp án',
      sourcePage: 1,
      sourceBlockId: 'blk-1',
      sourceQuote: 'Trích dẫn không khớp',
      status: DraftCardStatus.accepted,
    );
    final generation = _MockMaterialGenRepo()
      ..generatedCards = [
        card.copyWith(id: 'new-1', front: 'Câu mới?'),
        card.copyWith(id: 'new-2', front: 'Câu mới?'),
      ];
    await tester.pumpWidget(
      MaterialApp(
        theme: MemoTheme.light,
        home: FlashcardReviewApprovalScreen(
          documentId: 'doc-1',
          documentTitle: 'Nguồn',
          targetDeck: decks.decks.first,
          initialCards: const [card],
          sourceBlocks: review.pageReviews.first.blocks,
          sourcePages: const [],
          deckRepository: decks,
          ocrRepository: ocr,
          generationRepository: generation,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Tạo lại thẻ này'));
    await tester.pumpAndSettle();
    expect(generation.requestedCounts, [1]);
    expect(find.text('Đã chọn 0 / 2'), findsOneWidget);
    expect(find.text('Câu hỏi giống thẻ 2.'), findsOneWidget);
    await tester.tap(find.text('Chọn hết'));
    await tester.pumpAndSettle();
    expect(find.text('Đã chọn 2 / 2'), findsOneWidget);
  });

  for (final dark in [false, true]) {
    testWidgets('review remains usable at 360px with large text, dark=$dark', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final decks = _MockDeckRepository();
      if (const bool.fromEnvironment('CAPTURE_REVIEW')) {
        final loader = FontLoader('BeVietnamPro')
          ..addFont(rootBundle.load('assets/fonts/BeVietnamPro-Regular.ttf'));
        await loader.load();
      }
      await tester.pumpWidget(
        MaterialApp(
          theme: dark ? MemoTheme.dark : MemoTheme.light,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.5)),
            child: child!,
          ),
          home: FlashcardReviewApprovalScreen(
            documentId: 'doc-1',
            documentTitle: 'Tài liệu dài để kiểm tra hiển thị',
            targetDeck: decks.decks.first,
            initialCards: const [
              MaterialDraft(
                id: 'one',
                type: CardType.basic,
                front: 'Câu hỏi cần đối chiếu',
                back: 'Đáp án',
                sourcePage: 1,
                sourceBlockId: 'missing',
                sourceQuote: 'Trích dẫn',
              ),
            ],
            sourceBlocks: const [],
            sourcePages: const [],
            deckRepository: decks,
            ocrRepository: _MockOcrRepository(),
            generationRepository: _MockMaterialGenRepo(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      if (const bool.fromEnvironment('CAPTURE_REVIEW')) {
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byType(RepaintBoundary).first,
        );
        await tester.runAsync(() async {
          final image = await boundary.toImage();
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          await Directory('build/review-preview').create(recursive: true);
          await File('build/review-preview/${dark ? 'dark' : 'light'}.png')
              .writeAsBytes(data!.buffer.asUint8List());
          image.dispose();
        });
      }
      await tester.drag(find.byType(ListView), const Offset(0, -500));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Chọn hết'));
      await tester.pumpAndSettle();
      expect(find.text('Lưu các thẻ đã chọn (1)'), findsOneWidget);
    });
  }
}

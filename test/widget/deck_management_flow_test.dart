import 'dart:io';

import 'package:image/image.dart' as img;
import 'package:memo_mind/features/document_import/domain/document_import_models.dart';
import 'package:memo_mind/features/ocr_editor/domain/ocr_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memo_mind/features/deck_management/data/local_deck_repository.dart';
import 'package:memo_mind/features/deck_management/domain/deck_models.dart';
import 'package:memo_mind/features/deck_management/presentation/card_editor_dialog.dart';
import 'package:memo_mind/features/deck_management/presentation/deck_detail_screen.dart';
import 'package:memo_mind/features/deck_management/presentation/widgets/deck_form_dialog.dart';
import 'package:memo_mind/features/material_generation/domain/material_generation_models.dart';
import 'package:memo_mind/features/material_generation/presentation/source_inspection_modal.dart';
import 'package:memo_mind/features/material_generation/presentation/select_or_create_deck_sheet.dart';
import 'package:memo_mind/shared/theme/memo_theme.dart';

import '../unit/deck_management_test.dart' as fixture;

class MemoryDeckRepository extends LocalDeckRepository {
  MemoryDeckRepository()
    : deck = Deck(
        id: 'd',
        title: 'Deck',
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
      );
  final Deck deck;
  final List<CardEntity> cards = [];
  bool failWrites = false;
  @override
  Future<List<Deck>> getDecks() async => [deck];
  @override
  Future<Deck?> getDeckById(String id) async =>
      deck.copyWith(cardCount: (await getCardsForDeck(id)).length);
  @override
  Future<List<CardEntity>> getCardsForDeck(String id) async => cards
      .where((c) => c.deckId == id && c.status != CardStatus.deleted)
      .toList();
  @override
  Future<CardEntity> createManualCard({
    required String deckId,
    required CardContent content,
  }) async {
    if (failWrites) throw StateError('Injected write failure');
    content.validate();
    final now = DateTime.utc(2026);
    final c = CardEntity(
      id: 'c${cards.length}',
      deckId: deckId,
      type: content.type,
      front: content.front,
      back: content.answer,
      options: content.options,
      correctOptionId: content.correctOptionId,
      explanation: content.explanation,
      tags: content.tags,
      dueDate: now,
      createdAt: now,
      updatedAt: now,
    );
    cards.add(c);
    return c;
  }

  @override
  Future<void> deleteCard(String cardId) async {
    final index = cards.indexWhere((c) => c.id == cardId);
    cards[index] = cards[index].copyWith(status: CardStatus.deleted);
  }
}

void main() {
  late MemoryDeckRepository repo;
  late Deck deck;
  setUp(() {
    repo = MemoryDeckRepository();
    deck = repo.deck;
  });
  Future<void> openEditor(WidgetTester tester, {CardEntity? card}) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: MemoTheme.light,
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => CardEditorDialog.show(
                context,
                repository: repo,
                deckId: deck.id,
                card: card,
              ),
              child: const Text('Mở'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Mở'));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'invalid content stays open; failed save retains input and retries',
    (tester) async {
      await openEditor(tester);
      await tester.tap(find.byKey(const Key('card-editor-save')));
      await tester.pumpAndSettle();
      expect(find.text('Bắt buộc nhập, tối đa 2000 ký tự.'), findsNWidgets(2));
      await tester.enterText(
        find.byKey(const Key('card-editor-front')),
        'Câu hỏi',
      );
      await tester.enterText(
        find.byKey(const Key('card-editor-back')),
        'Đáp án',
      );
      repo.failWrites = true;
      await tester.tap(find.byKey(const Key('card-editor-save')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Không thể lưu thẻ.'), findsOneWidget);
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('card-editor-front')))
            .controller!
            .text,
        'Câu hỏi',
      );
      expect(repo.cards, isEmpty);
      repo.failWrites = false;
      await tester.tap(find.byKey(const Key('card-editor-save')));
      await tester.pumpAndSettle();
      expect(find.byType(CardEditorDialog), findsNothing);
      expect((await repo.getCardsForDeck(deck.id)).length, 1);
    },
  );

  for (final type in [CardType.cloze, CardType.mcq]) {
    testWidgets('editor creates $type with validated fields', (tester) async {
      await openEditor(tester);
      await tester.tap(find.byKey(const Key('card-editor-type')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(type.wireName).last);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('card-editor-front')),
        type == CardType.cloze ? 'Câu [...]' : 'Question',
      );
      if (type == CardType.cloze) {
        await tester.enterText(
          find.byKey(const Key('card-editor-back')),
          'Answer',
        );
      } else {
        for (final id in ['A', 'B', 'C', 'D']) {
          await tester.ensureVisible(find.byKey(Key('card-editor-$id')));
          await tester.enterText(
            find.byKey(Key('card-editor-$id')),
            'Option $id',
          );
        }
        await tester.ensureVisible(
          find.byKey(const Key('card-editor-explanation')),
        );
        await tester.enterText(
          find.byKey(const Key('card-editor-explanation')),
          'Explanation',
        );
      }
      await tester.tap(find.byKey(const Key('card-editor-save')));
      await tester.pumpAndSettle();
      final c = (await repo.getCardsForDeck(deck.id)).single;
      expect(c.type, type);
      expect(c.hasSource, false);
      if (type == CardType.mcq) expect(c.back, 'Option A');
    });
  }

  testWidgets(
    'deck search uses tags; cancel delete keeps data; confirm removes it',
    (tester) async {
      final c = await repo.createManualCard(
        deckId: deck.id,
        content: fixture.content(CardType.basic, tags: ['Biology']),
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: MemoTheme.light,
          home: DeckDetailScreen(deckId: deck.id, repository: repo),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('search-cards')), 'biology');
      await tester.pump();
      expect(find.text(c.front), findsOneWidget);
      await tester.enterText(find.byKey(const Key('search-cards')), 'missing');
      await tester.pump();
      expect(find.text('Không tìm thấy thẻ'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('search-cards')), '');
      await tester.pump();
      await tester.ensureVisible(find.text('Xóa thẻ'));
      await tester.tap(find.text('Xóa thẻ'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Hủy'));
      await tester.pumpAndSettle();
      expect((await repo.getCardsForDeck(deck.id)).length, 1);
      await tester.tap(find.text('Xóa thẻ'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Xóa thẻ').last);
      await tester.pumpAndSettle();
      expect(await repo.getCardsForDeck(deck.id), isEmpty);
      expect(find.text('Bộ thẻ chưa có thẻ nào'), findsOneWidget);
    },
  );

  testWidgets(
    'missing source keeps long quote and saved page on small screen',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final quote = List.filled(150, 'Nguồn đã lưu.').join(' ');
      await tester.pumpWidget(
        MaterialApp(
          theme: MemoTheme.dark,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(1.5)),
            child: child!,
          ),
          home: Scaffold(
            body: SourceInspectionModal(
              documentTitle: 'Tài liệu',
              sourcePage: null,
              sourceBlock: null,
              sourceQuote: quote,
              sourcePageNumber: 9,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Trang 9 • Tài liệu'), findsOneWidget);
      expect(find.byKey(const Key('source-quote')), findsOneWidget);
      expect(find.byKey(const Key('source-highlight')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('create-deck sheet scrolls with large text and keyboard', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: MemoTheme.light,
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => SelectOrCreateDeckSheet.show(
                context,
                deckRepository: repo,
                cardCountToSave: 3,
              ),
              child: const Text('Mở'),
            ),
          ),
        ),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(1.5),
            viewInsets: const EdgeInsets.only(bottom: 260),
          ),
          child: child!,
        ),
      ),
    );
    await tester.tap(find.text('Mở'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Tạo bộ thẻ mới'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tạo bộ thẻ mới'));
    await tester.pumpAndSettle();
    expect(find.text('Nhãn (ngăn cách bằng dấu phẩy)'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'deck form retains title and tags after write failure and retries',
    (tester) async {
      var attempts = 0;
      DeckFormData? saved;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => DeckFormDialog.show(
                  context,
                  onSave: (data) async {
                    attempts++;
                    if (attempts == 1) throw StateError('Injected failure');
                    saved = data;
                  },
                ),
                child: const Text('Mở'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Mở'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), '  Biology  ');
      await tester.enterText(find.byType(TextField).last, 'Cell, cell, Exam');
      await tester.tap(find.text('Tạo'));
      await tester.pumpAndSettle();
      expect(
        find.text('Không thể lưu thay đổi. Vui lòng thử lại.'),
        findsOneWidget,
      );
      expect(find.text('  Biology  '), findsOneWidget);
      expect(saved, isNull);
      await tester.tap(find.text('Tạo'));
      await tester.pumpAndSettle();
      expect(attempts, 2);
      expect(saved!.title, 'Biology');
      expect(saved!.tags, ['Cell', 'Exam']);
      expect(find.byType(DeckFormDialog), findsNothing);
    },
  );
  testWidgets(
    'decoded page highlights only the matching block; corrupt image keeps quote',
    (tester) async {
      final dir = Directory.systemTemp.createTempSync('memo_source_widget_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final file = File('${dir.path}/page.png')
        ..writeAsBytesSync(img.encodePng(img.Image(width: 32, height: 32)));
      final page = SourcePage(
        pageId: 'p',
        documentId: 'd',
        pageNumber: 7,
        originalPageNumber: 7,
        source: DocumentPageSource.gallery,
        dataRelativePath: 'page.png',
        absolutePath: file.path,
        mimeType: 'image/png',
        fileSizeBytes: file.lengthSync(),
        width: 32,
        height: 32,
        sha256: 'fixture',
        qualityCode: 'ok',
        qualityWarningAccepted: false,
        createdAt: DateTime.utc(2026),
      );
      final block = SourceBlock(
        blockId: 'b',
        documentId: 'd',
        pageId: 'p',
        pageNumber: 7,
        orderIndex: 0,
        rawText: 'Quote',
        normalizedText: 'Quote',
        boundingBox: const NormalizedBoundingBox(
          left: .1,
          top: .1,
          width: .5,
          height: .2,
        ),
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
      );
      Future<void> show(SourceBlock selected, File image) async {
        // Resolve the native FileImage in the real async zone, including its first frame.
        await tester.runAsync(() async {
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: SourceInspectionModal(
                  documentTitle: 'Document',
                  sourcePage: page,
                  sourceBlock: selected,
                  sourceQuote: 'Quote',
                  sourcePageFile: image,
                ),
              ),
            ),
          );
          await precacheImage(
            FileImage(image),
            tester.element(find.byType(SourceInspectionModal)),
            onError: (error, stack) {},
          ).timeout(const Duration(seconds: 10));
        });
        await tester.pumpAndSettle();
      }

      await show(block, file);
      expect(find.text('Trang 7 • Document'), findsOneWidget);
      expect(find.byKey(const Key('source-highlight')), findsOneWidget);
      await show(block.copyWith(pageId: 'another-page'), file);
      expect(find.byKey(const Key('source-highlight')), findsNothing);
      final bad = File('${dir.path}/broken.png')
        ..writeAsStringSync('not an image');
      await show(block, bad);
      expect(
        find.text('Không thể đọc ảnh nguồn. Đoạn trích vẫn được giữ lại.'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('source-quote')), findsOneWidget);
      expect(find.byKey(const Key('source-highlight')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}

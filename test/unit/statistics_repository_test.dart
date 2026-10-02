import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:memo_mind/core/database/memo_mind_database.dart';
import 'package:memo_mind/features/deck_management/data/local_deck_repository.dart';
import 'package:memo_mind/features/deck_management/domain/deck_models.dart';
import 'package:memo_mind/features/material_generation/domain/material_generation_models.dart';
import 'package:memo_mind/features/review/data/local_due_cards_source_io.dart';
import 'package:memo_mind/features/review/data/local_review_repository.dart';
import 'package:memo_mind/features/review/domain/review_models.dart';
import 'package:memo_mind/features/statistics/data/local_statistics_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);
  final now = DateTime.utc(2026, 10, 2, 8);
  late Database db;
  late MemoMindDatabase store;
  late LocalDeckRepository decks;
  late LocalReviewRepository reviews;
  late LocalStatisticsRepository statistics;
  late Deck deck;
  late CardEntity card;
  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(singleInstance: false),
    );
    await db.execute('PRAGMA foreign_keys=ON');
    await MemoMindDatabase.createV8(db);
    store = MemoMindDatabase.forTesting(db);
    decks = LocalDeckRepository(database: store, clock: () => now);
    reviews = LocalReviewRepository(database: store, clock: () => now);
    statistics = LocalStatisticsRepository(
      database: store,
      clock: () => now,
      timeZone: () async => 'Asia/Ho_Chi_Minh',
    );
    deck = await decks.createDeck(title: 'Thống kê');
    card = await decks.createManualCard(
      deckId: deck.id,
      content: const CardContent(type: CardType.basic, front: 'Q', back: 'A'),
    );
  });
  tearDown(() async => db.close());

  test('BR06 concurrent review commit cannot split schedule and event snapshot', () async {
    final session = (await reviews.startSession())!;
    final reading = statistics.loadSnapshot();
    final writing = reviews.rate(
      sessionId: session.session.id,
      cardId: card.id,
      eventId: 'concurrent',
      reviewedAt: now,
      rating: ReviewRating.good,
    );
    final data = await reading;
    await writing;
    // Either complete state is valid; a mix of old schedule/new history is not.
    expect((data.dueCardCount, data.reviewCountToday), anyOf((1, 0), (0, 1)));
    final after = await statistics.loadSnapshot();
    expect((after.dueCardCount, after.reviewCountToday), (0, 1));
  });

  test('AC02 shared eligibility, invalid/missing schedules and removed cards/decks', () async {
    expect((await statistics.loadSnapshot()).dueCardCount, 1);
    expect(
      (await LocalDueCardsSource(database: store).getDueCards(now)).length,
      1,
    );
    for (final change in [
      <String, Object?>{'status': 'suspended'},
      {'status': 'deleted'},
      {
        'status': 'active',
        'due_date': now.add(const Duration(seconds: 1)).millisecondsSinceEpoch,
      },
      {'due_date': 'invalid'},
      {'due_date': now.millisecondsSinceEpoch, 'back': ''},
    ]) {
      await db.update(
        'cards',
        change,
        where: 'card_id=?',
        whereArgs: [card.id],
      );
      expect((await statistics.loadSnapshot()).dueCardCount, 0);
    }
    await db.update(
      'cards',
      {'back': 'A'},
      where: 'card_id=?',
      whereArgs: [card.id],
    );
    await db.update(
      'decks',
      {'status': 'deleted'},
      where: 'deck_id=?',
      whereArgs: [deck.id],
    );
    expect((await statistics.loadSnapshot()).dueCardCount, 0);
  });

  test(
    'AC04/08 committed unfinished reviews, retry ID, reads never mutate tables',
    () async {
      final session = (await reviews.startSession())!;
      await reviews.rate(
        sessionId: session.session.id,
        cardId: card.id,
        eventId: 'event',
        reviewedAt: now,
        rating: ReviewRating.again,
      );
      await reviews.rate(
        sessionId: session.session.id,
        cardId: card.id,
        eventId: 'event',
        reviewedAt: now,
        rating: ReviewRating.again,
      );
      final before = {
        for (final table in [
          'cards',
          'review_events',
          'review_sessions',
          'app_settings',
        ])
          table: await db.query(table),
      };
      final result = await statistics.loadSnapshot();
      expect(result.reviewCountToday, 1);
      expect(result.successRateToday, 0);
      expect(result.dueCardCount, 0);
      expect(result.currentStreakDays, 1);
      for (final entry in before.entries) {
        expect(await db.query(entry.key), entry.value);
      }
    },
  );

  test(
    'AC08 deleting a card or deck retains independent review history',
    () async {
      final session = (await reviews.startSession())!;
      await reviews.rate(
        sessionId: session.session.id,
        cardId: card.id,
        eventId: 'event',
        reviewedAt: now,
        rating: ReviewRating.hard,
      );
      await decks.deleteCard(card.id);
      expect((await statistics.loadSnapshot()).reviewCountToday, 1);
      await decks.deleteDeck(deck.id);
      final result = await statistics.loadSnapshot();
      expect(result.dueCardCount, 0);
      expect(result.reviewCountToday, 1);
      expect(result.successRateToday, 100);
    },
  );

  test('AC09 history and schedules survive close/reopen of SQLite', () async {
    final directory = await Directory.systemTemp.createTemp('statistics_');
    final path = '${directory.path}/stats.db';
    Database? persisted;
    try {
      persisted = await databaseFactoryFfi.openDatabase(path);
      await MemoMindDatabase.createV8(persisted);
      var local = MemoMindDatabase.forTesting(persisted);
      final library = LocalDeckRepository(database: local, clock: () => now);
      final savedDeck = await library.createDeck(title: 'Offline');
      await library.createManualCard(
        deckId: savedDeck.id,
        content: const CardContent(type: CardType.basic, front: 'Q', back: 'A'),
      );
      final review = LocalReviewRepository(database: local, clock: () => now);
      final session = (await review.startSession())!;
      await review.rate(
        sessionId: session.session.id,
        cardId: session.card!.id,
        eventId: 'offline',
        reviewedAt: now,
        rating: ReviewRating.good,
      );
      await persisted.close();
      persisted = await databaseFactoryFfi.openDatabase(path);
      local = MemoMindDatabase.forTesting(persisted);
      final data = await LocalStatisticsRepository(
        database: local,
        clock: () => now,
        timeZone: () async => 'UTC',
      ).loadSnapshot();
      expect(data.reviewCountToday, 1);
      expect(data.successRateToday, 100);
      expect(data.dueCardCount, 0);
    } finally {
      await persisted?.close();
      await directory.delete(recursive: true);
    }
  });

  test(
    'AC10 failed database/timezone reads propagate instead of empty success',
    () async {
      await db.execute('DROP TABLE review_events');
      await expectLater(
        statistics.loadSnapshot(),
        throwsA(isA<DatabaseException>()),
      );
      final broken = LocalStatisticsRepository(
        database: store,
        timeZone: () async => throw StateError('timezone'),
      );
      await expectLater(broken.loadSnapshot(), throwsStateError);
    },
  );
}

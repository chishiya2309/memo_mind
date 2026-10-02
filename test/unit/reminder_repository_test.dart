import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:memo_mind/core/database/memo_mind_database.dart';
import 'package:memo_mind/features/deck_management/data/local_deck_repository_io.dart';
import 'package:memo_mind/features/deck_management/domain/deck_models.dart';
import 'package:memo_mind/features/material_generation/domain/material_generation_models.dart';
import 'package:memo_mind/features/reminders/application/reminder_coordinator.dart';
import 'package:memo_mind/features/reminders/data/local_reminder_settings_repository.dart';
import 'package:memo_mind/features/reminders/domain/reminder_models.dart';
import 'package:memo_mind/features/review/data/local_due_cards_source_io.dart';
import 'package:memo_mind/features/review/data/local_review_repository_io.dart';
import 'package:memo_mind/features/review/domain/review_models.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;

import '../support/reminder_fakes.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    tzdata.initializeTimeZones();
  });
  late Database db;
  late MemoMindDatabase store;
  late LocalDeckRepository decks;
  late LocalReminderSettingsRepository repository;
  late LocalDueCardsSource source;
  late String deckId;
  final now = DateTime.utc(2026, 10, 2, 1);
  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(singleInstance: false),
    );
    await db.execute('PRAGMA foreign_keys=ON');
    await MemoMindDatabase.createV8(db);
    store = MemoMindDatabase.forTesting(db);
    decks = LocalDeckRepository(database: store, clock: () => now);
    repository = LocalReminderSettingsRepository(database: store);
    source = LocalDueCardsSource(database: store);
    deckId = (await decks.createDeck(title: 'Thẻ đến hạn')).id;
  });
  tearDown(() => db.close());
  Future<CardEntity> create(String title) => decks.createManualCard(
    deckId: deckId,
    content: CardContent(type: CardType.basic, front: title, back: 'Đáp án'),
  );

  test(
    'shared due list, dashboard, and session exclude invalid and inactive rows',
    () async {
      final before = await create('Trước');
      final equal = await create('Bằng');
      final future = await create('Sau');
      final deleted = await create('Đã xóa');
      final suspended = await create('Tạm dừng');
      final invalid = await create('Lịch lỗi');
      final badContent = await create('Nội dung lỗi');
      await db.update(
        'cards',
        {'due_date': now.millisecondsSinceEpoch - 1},
        where: 'card_id=?',
        whereArgs: [before.id],
      );
      await db.update(
        'cards',
        {'due_date': now.millisecondsSinceEpoch + 1},
        where: 'card_id=?',
        whereArgs: [future.id],
      );
      await decks.deleteCard(deleted.id);
      await db.update(
        'cards',
        {'status': 'suspended'},
        where: 'card_id=?',
        whereArgs: [suspended.id],
      );
      await db.update(
        'cards',
        {'repetitions': 1, 'interval_days': 0},
        where: 'card_id=?',
        whereArgs: [invalid.id],
      );
      await db.update(
        'cards',
        {'front': ''},
        where: 'card_id=?',
        whereArgs: [badContent.id],
      );
      expect(LocalDueCardsSource.isEligible({}), isFalse);
      final cards = await source.getDueCards(now);
      expect(cards.map((c) => c.card.id), [before.id, equal.id]);
      expect(cards.first.deckTitle, 'Thẻ đến hạn');
      final review = LocalReviewRepository(database: store, clock: () => now);
      expect((await review.getDecks()).single.dueCount, 2);
      expect((await review.startSession())!.session.queue, [
        before.id,
        equal.id,
      ]);
      await decks.deleteDeck(deckId);
      expect(await source.getDueCards(now), isEmpty);
    },
  );
  test('settings default off; save/reload leaves schedules, events and other keys intact', () async {
    await create('Thẻ');
    final cards = await db.query('cards');
    await db.insert('app_settings', {
      'key': 'device_id',
      'value': 'original-device',
    });
    expect((await repository.readSettings()).enabled, isFalse);
    expect((await repository.readSettings()).hour, isNull);
    await repository.saveSettings(
      ReminderSettings(enabled: true, hour: 0, minute: 0, updatedAt: now),
    );
    expect((await repository.readState()).needsReconcile, isTrue);
    final fresh = LocalReminderSettingsRepository(database: store);
    expect((await fresh.readSettings()).hour, 0);
    expect((await fresh.readSettings()).updatedAt, now);
    await expectLater(
      repository.saveSettings(const ReminderSettings(enabled: true)),
      throwsFormatException,
    );
    expect((await fresh.readSettings()).hour, 0);
    expect(await db.query('cards'), cards);
    expect(await db.query('review_events'), isEmpty);
    expect(
      (await db.query(
        'app_settings',
        where: "key='device_id'",
      )).single['value'],
      'original-device',
    );
  });
  test('failed settings transaction rolls back both keys', () async {
    await repository.saveSettings(
      const ReminderSettings(enabled: true, hour: 9, minute: 0),
    );
    final original = await db.query('app_settings', orderBy: 'key');
    await db.execute(
      """CREATE TRIGGER fail_state BEFORE INSERT ON app_settings
      WHEN NEW.key='fr16.reminder_scheduling' BEGIN SELECT RAISE(ABORT,'disk full'); END""",
    );
    await expectLater(
      repository.saveSettings(const ReminderSettings()),
      throwsA(isA<DatabaseException>()),
    );
    expect(await db.query('app_settings', orderBy: 'key'), original);
  });
  test('committed CRUD and ratings emit changes; failures emit nothing; reminders cannot fail reviews', () async {
    final changes = <void>[];
    final subscription = store.studyChanges.listen(changes.add);
    addTearDown(subscription.cancel);
    final card = await create('Thẻ');
    await Future<void>.delayed(Duration.zero);
    expect(changes.length, 1);
    await expectLater(
      decks.createManualCard(
        deckId: deckId,
        content: const CardContent(type: CardType.basic, front: '', back: ''),
      ),
      throwsFormatException,
    );
    await Future<void>.delayed(Duration.zero);
    expect(changes.length, 1);
    final gateway = FakeNotificationGateway()..failSchedule = true;
    final coordinator = ReminderCoordinator(
      repository: repository,
      gateway: gateway,
      dueCards: source,
      timeZone: () async => 'Asia/Ho_Chi_Minh',
      clock: () => now,
    );
    addTearDown(coordinator.dispose);
    final refresh = store.studyChanges.listen((_) => coordinator.reconcile());
    addTearDown(refresh.cancel);
    await coordinator.save(
      const ReminderSettings(enabled: true, hour: 9, minute: 0),
    );
    final review = LocalReviewRepository(database: store, clock: () => now);
    final session = (await review.startSession())!;
    await review.rate(
      sessionId: session.session.id,
      cardId: card.id,
      eventId: 'rating',
      reviewedAt: now,
      rating: ReviewRating.good,
    );
    await Future<void>.delayed(Duration.zero);
    await coordinator.reconcile();
    expect(coordinator.status, ReminderStatus.needsReconcile);
    expect((await db.query('review_events')).single['event_id'], 'rating');
    expect(
      (await db.query('cards')).single['due_date'],
      now.add(const Duration(days: 1)).millisecondsSinceEpoch,
    );
    expect(changes.length, 2);
    await decks.updateCard(
      card.id,
      content: const CardContent(
        type: CardType.basic,
        front: 'Sửa',
        back: 'Đáp án',
      ),
    );
    await decks.deleteCard(card.id);
    await decks.deleteDeck(deckId);
    await Future<void>.delayed(Duration.zero);
    expect(changes.length, 5);
    await coordinator.reconcile();
  });
  test('settings and manifest survive actual database close/reopen', () async {
    final directory = await Directory.systemTemp.createTemp('memo_fr16_');
    final path = '${directory.path}/reminders.db';
    final disk = await databaseFactoryFfi.openDatabase(path);
    await MemoMindDatabase.createV8(disk);
    final first = LocalReminderSettingsRepository(
      database: MemoMindDatabase.forTesting(disk),
    );
    await first.saveSettings(
      ReminderSettings(enabled: true, hour: 23, minute: 59, updatedAt: now),
    );
    await first.complete(
      (await first.readSettings()).inZone('Asia/Ho_Chi_Minh'),
      ReminderSchedulingState(
        timeZone: 'Asia/Ho_Chi_Minh',
        windowEndAt: now,
        occurrences: [
          ReminderOccurrence(
            id: 180261002,
            key: 'review_due:2026-10-02',
            scheduledAt: now,
          ),
        ],
      ),
    );
    await disk.close();
    final reopened = await databaseFactoryFfi.openDatabase(path);
    try {
      final second = LocalReminderSettingsRepository(
        database: MemoMindDatabase.forTesting(reopened),
      );
      expect((await second.readSettings()).minute, 59);
      expect((await second.readState()).occurrences.single.scheduledAt, now);
    } finally {
      await reopened.close();
      await directory.delete(recursive: true);
    }
  });
}

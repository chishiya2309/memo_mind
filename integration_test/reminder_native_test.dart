import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:memo_mind/core/database/memo_mind_database.dart';
import 'package:memo_mind/features/deck_management/data/local_deck_repository_io.dart';
import 'package:memo_mind/features/deck_management/domain/card_content.dart';
import 'package:memo_mind/features/material_generation/domain/material_generation_models.dart';
import 'package:memo_mind/features/reminders/application/reminder_coordinator.dart';
import 'package:memo_mind/features/reminders/data/android_notification_gateway.dart';
import 'package:memo_mind/features/reminders/data/local_reminder_settings_repository.dart';
import 'package:memo_mind/features/reminders/domain/notification_gateway.dart';
import 'package:memo_mind/features/reminders/domain/reminder_models.dart';
import 'package:memo_mind/features/review/data/local_due_cards_source_io.dart';
import 'package:memo_mind/features/review/data/local_review_repository_io.dart';
import 'package:memo_mind/features/review/domain/review_models.dart';
import 'package:sqflite/sqflite.dart';

// Translate to a separate test ID range and hide production alarms from the
// coordinator, so this test never cancels a user's reminders or clears app data.
class IsolatedNativeGateway implements NotificationGateway {
  final delegate = AndroidNotificationGateway();
  static const offset = 60000000;
  Set<int> _testIds(Set<int> ids) => ids
      .where((id) => id >= 240000000 && id < 260000000)
      .map((id) => id - offset)
      .toSet();
  @override
  bool get supported => delegate.supported;
  @override
  Future<bool> initialize(void Function() onReviewDue) =>
      delegate.initialize(onReviewDue);
  @override
  Future<NotificationAccess> access() => delegate.access();
  @override
  Future<void> requestPermission() => delegate.requestPermission();
  @override
  Future<void> openSettings() => delegate.openSettings();
  @override
  Future<Set<int>> pendingIds() async => _testIds(await delegate.pendingIds());
  @override
  Future<Set<int>> activeIds() async => _testIds(await delegate.activeIds());
  @override
  Future<void> cancel(int id) => delegate.cancel(id + offset);
  @override
  Future<void> schedule(ReminderOccurrence occurrence, String timeZone) =>
      delegate.schedule(
        ReminderOccurrence(
          id: occurrence.id + offset,
          key: occurrence.key,
          scheduledAt: occurrence.scheduledAt,
        ),
        timeZone,
      );
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'native offline schedule, idempotence, review refresh and disable',
    (tester) async {
      final directory = await Directory.systemTemp.createTemp(
        'memo_fr16_native_',
      );
      Database? db;
      ReminderCoordinator? coordinator;
      final gateway = IsolatedNativeGateway();
      try {
        await gateway.initialize(() {});
        final access = await gateway.access();
        expect(
          access.allowed,
          isTrue,
          reason: 'Enable app notifications and the Nhắc học channel before running this test.',
        );
        db = await openDatabase(
          '${directory.path}/test.db',
          version: 8,
          onConfigure: (db) => db.execute('PRAGMA foreign_keys=ON'),
          onCreate: (db, _) => MemoMindDatabase.createV8(db),
        );
        final store = MemoMindDatabase.forTesting(db);
        final decks = LocalDeckRepository(database: store);
        final deck = await decks.createDeck(title: 'FR16 test');
        final card = await decks.createManualCard(
          deckId: deck.id,
          content: const CardContent(
            type: CardType.basic,
            front: 'Offline?',
            back: 'Có',
          ),
        );
        final repository = LocalReminderSettingsRepository(database: store);
        coordinator = ReminderCoordinator(
          repository: repository,
          gateway: gateway,
          dueCards: LocalDueCardsSource(database: store),
          timeZone: AndroidNotificationGateway.deviceTimeZone,
        );
        final next = DateTime.now().add(const Duration(minutes: 2));
        await coordinator.save(
          ReminderSettings(
            enabled: true,
            hour: next.hour,
            minute: next.minute,
            updatedAt: DateTime.now().toUtc(),
          ),
        );
        expect(coordinator.status, ReminderStatus.scheduled);
        final registered = await gateway.pendingIds();
        expect(registered.length, inInclusiveRange(6, 7));
        expect(
          (await repository.readState()).occurrences.every(
            (o) => o.scheduledAt.isAfter(DateTime.now()),
          ),
          isTrue,
        );
        await coordinator.reconcile(force: true);
        expect(await gateway.pendingIds(), registered);
        final eventsBefore = await db.query('review_events');
        await LocalDueCardsSource(database: store)
            .getDueCards(DateTime.now().toUtc());
        expect(await db.query('review_events'), eventsBefore);
        final review = LocalReviewRepository(database: store);
        final session = (await review.startSession())!;
        await review.rate(
          sessionId: session.session.id,
          cardId: card.id,
          eventId: 'fr16-test',
          reviewedAt: DateTime.now().toUtc(),
          rating: ReviewRating.good,
        );
        await coordinator.reconcile();
        expect((await db.query('review_events')).length, 1);
        expect(coordinator.status, ReminderStatus.scheduled);
        await coordinator.save(
          ReminderSettings(hour: next.hour, minute: next.minute),
        );
        expect(coordinator.status, ReminderStatus.disabled);
        expect(await gateway.pendingIds(), isEmpty);
        expect(await gateway.activeIds(), isEmpty);
      } finally {
        for (final id in await gateway.pendingIds()) {
          await gateway.cancel(id);
        }
        for (final id in await gateway.activeIds()) {
          await gateway.cancel(id);
        }
        coordinator?.dispose();
        await db?.close();
        await directory.delete(recursive: true);
      }
    },
  );
}

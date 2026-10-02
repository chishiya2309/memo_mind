import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:memo_mind/features/statistics/application/statistics_controller.dart';

import '../support/statistics_fakes.dart';

void main() {
  late FakeStatisticsRepository repository;
  late StreamController<void> changes;
  late StatisticsController controller;
  late DateTime now;
  late String zone;
  setUp(() {
    now = DateTime.utc(2026, 10, 2, 8);
    zone = 'Asia/Ho_Chi_Minh';
    repository = FakeStatisticsRepository();
    changes = StreamController<void>.broadcast();
    controller = StatisticsController(
      repository: repository,
      studyChanges: changes.stream,
      clock: () => now,
      timeZone: () async => zone,
    );
  });
  tearDown(() async {
    controller.dispose();
    await changes.close();
  });

  test('AC10 first failure is error, later failure retains stale data, retry recovers', () async {
    repository.error = StateError('database');
    await controller.refresh();
    expect(controller.state, StatisticsLoadState.error);
    expect(controller.snapshot, isNull);
    repository.error = null;
    await controller.refresh();
    final saved = controller.snapshot;
    repository.error = StateError('database');
    await controller.refresh();
    expect(controller.state, StatisticsLoadState.stale);
    expect(controller.snapshot, same(saved));
    repository.error = null;
    await controller.refresh();
    expect(controller.state, StatisticsLoadState.ready);
  });

  test(
    'AC11 late success and late error cannot overwrite the newest request',
    () async {
      repository.delayed = true;
      final old = controller.refresh();
      final next = controller.refresh();
      final latest = statisticsSnapshot(
        at: now.add(const Duration(minutes: 1)),
      );
      repository.pending[1].complete(latest);
      await next;
      repository.pending[0].complete(statisticsSnapshot(at: now));
      await old;
      expect(controller.snapshot, same(latest));
      final oldError = controller.refresh();
      final success = controller.refresh();
      repository.pending[3].complete(latest);
      await success;
      repository.pending[2].completeError(StateError('old error'));
      await oldError;
      expect(controller.state, StatisticsLoadState.ready);
      expect(controller.snapshot, same(latest));
    },
  );

  testWidgets(
    'AC08 commit, hidden route, resume and reopening refresh independently',
    (tester) async {
      controller.setVisible(true);
      await tester.pump();
      expect(repository.calls, 1);
      changes.add(null);
      await tester.pump();
      expect(repository.calls, 2);
      controller.setVisible(false);
      changes.add(null);
      await tester.pump(const Duration(seconds: 31));
      expect(repository.calls, 2);
      controller.setVisible(true);
      await tester.pump();
      expect(repository.calls, 3);
      controller.setResumed(false);
      changes.add(null);
      await tester.pump(const Duration(seconds: 31));
      expect(repository.calls, 3);
      controller.setResumed(true);
      await tester.pump();
      expect(repository.calls, 4);
      controller.setVisible(false);
    },
  );

  testWidgets('BR06 due instant triggers a complete replacement', (
    tester,
  ) async {
    final due = now.add(const Duration(seconds: 5));
    repository.data = statisticsSnapshot(at: now, cards: {'card': due});
    controller.setVisible(true);
    await tester.pump();
    expect(controller.snapshot!.dueCardCount, 0);
    now = due;
    repository.data = statisticsSnapshot(at: now, cards: {'card': due});
    await tester.pump(const Duration(seconds: 5));
    expect(repository.calls, 2);
    expect(controller.snapshot!.dueCardCount, 1);
    controller.setVisible(false);
  });

  testWidgets('AC07 midnight resets today and preserves yesterday streak', (
    tester,
  ) async {
    now = DateTime.utc(2026, 10, 2, 16, 59, 59);
    final event = statisticsEvent('review', now);
    repository.data = statisticsSnapshot(at: now, events: [event]);
    controller.setVisible(true);
    await tester.pump();
    expect(controller.snapshot!.reviewCountToday, 1);
    now = now.add(const Duration(seconds: 1));
    repository.data = statisticsSnapshot(at: now, events: [event]);
    await tester.pump(const Duration(seconds: 1));
    expect(controller.snapshot!.reviewCountToday, 0);
    expect(controller.snapshot!.currentStreakDays, 1);
    expect(controller.snapshot!.studiedToday, false);
    controller.setVisible(false);
  });

  testWidgets(
    'AC07 timezone and backwards clock jumps refresh on the 30s check',
    (tester) async {
      controller.setVisible(true);
      await tester.pump();
      zone = 'UTC';
      repository.data = statisticsSnapshot(at: now, zone: zone);
      await tester.pump(const Duration(seconds: 30));
      expect(controller.snapshot!.timeZoneId, 'UTC');
      final calls = repository.calls;
      now = now.subtract(const Duration(hours: 1));
      repository.data = statisticsSnapshot(at: now, zone: zone);
      await tester.pump(const Duration(seconds: 30));
      expect(repository.calls, calls + 1);
      expect(controller.snapshot!.asOf, now);
      controller.setVisible(false);
    },
  );

  test(
    'hiding invalidates outstanding work and dispose never notifies',
    () async {
      repository.delayed = true;
      controller.setVisible(true);
      controller.setVisible(false);
      repository.pending.first.complete(repository.data);
      await Future<void>.delayed(Duration.zero);
      expect(controller.snapshot, isNull);
      final pending = controller.refresh();
      var notified = 0;
      controller.addListener(() => notified++);
      controller.dispose();
      repository.pending.last.complete(repository.data);
      await pending;
      expect(notified, 0);
      // Give tearDown a separate controller because ChangeNotifier disposal is single-use.
      controller = StatisticsController(
        repository: repository,
        studyChanges: changes.stream,
      );
    },
  );
}

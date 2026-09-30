import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:memo_mind/core/database/memo_mind_database.dart';
import 'package:memo_mind/features/review/application/review_session_controller.dart';
import 'package:memo_mind/features/review/data/local_review_repository.dart';
import 'package:memo_mind/features/review/domain/review_models.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'review_repository_test.dart' as fixture;

class DelayedReviewRepository extends LocalReviewRepository {
  DelayedReviewRepository(Database db)
    : super(
        database: MemoMindDatabase.forTesting(db),
        clock: () => fixture.reviewNow,
      );
  Completer<void>? gate;
  bool failAfterCommit = false;
  final attemptedIds = <String>[];
  @override
  Future<ReviewSnapshot> rate({
    required String sessionId,
    required String cardId,
    required String eventId,
    required DateTime reviewedAt,
    required ReviewRating rating,
  }) async {
    attemptedIds.add(eventId);
    await gate?.future;
    final result = await super.rate(
      sessionId: sessionId,
      cardId: cardId,
      eventId: eventId,
      reviewedAt: reviewedAt,
      rating: rating,
    );
    if (failAfterCommit) {
      failAfterCommit = false;
      throw StateError('Simulated failure delivering committed result');
    }
    return result;
  }
}

void main() {
  setUpAll(sqfliteFfiInit);
  late Database db;
  late DelayedReviewRepository repository;
  late ReviewSessionController controller;
  setUp(() async {
    db = await fixture.reviewDatabase();
    repository = DelayedReviewRepository(db);
    controller = ReviewSessionController(
      repository,
      clock: () => fixture.reviewNow,
    );
    await controller.initialize();
  });
  tearDown(() async {
    controller.dispose();
    await db.close();
  });
  test('cannot rate before reveal; rapid taps create only one event', () async {
    await controller.rate(ReviewRating.good);
    expect(repository.attemptedIds, isEmpty);
    controller.reveal();
    repository.gate = Completer<void>();
    final first = controller.rate(ReviewRating.good);
    await controller.rate(ReviewRating.easy);
    expect(repository.attemptedIds.length, 1);
    expect(controller.snapshot!.card!.id, 'c0');
    repository.gate!.complete();
    await first;
    expect(controller.snapshot!.card!.id, 'c1');
    expect(controller.revealed, isFalse);
    expect((await db.query('review_events')).length, 1);
  });
  test('retry after committed result is lost uses same event and does not reschedule', () async {
    controller.reveal();
    repository.failAfterCommit = true;
    await controller.rate(ReviewRating.good);
    expect(controller.error, isNotNull);
    expect(controller.snapshot!.card!.id, 'c0');
    expect(controller.hasPendingRating, isTrue);
    await controller.retry();
    expect(repository.attemptedIds.toSet().length, 1);
    expect(controller.snapshot!.card!.id, 'c1');
    expect(controller.hasPendingRating, isFalse);
    expect((await db.query('review_events')).length, 1);
    expect(
      (await db.query('cards', where: "card_id='c0'")).single['repetitions'],
      1,
    );
  });
  test(
    'new controller offers resume and keeps unreviewed current card',
    () async {
      controller.reveal();
      await controller.rate(ReviewRating.again);
      final resumed = ReviewSessionController(repository);
      try {
        await resumed.initialize();
        expect(resumed.awaitingResume, isTrue);
        expect(resumed.snapshot!.card!.id, 'c1');
        expect(resumed.snapshot!.session.learningQueue, ['c0']);
        resumed.resume();
        expect(resumed.revealed, isFalse);
        await resumed.end();
        expect(resumed.snapshot!.reviewedCards, 1);
        expect(resumed.snapshot!.session.status, 'ended');
      } finally {
        resumed.dispose();
      }
    },
  );
}

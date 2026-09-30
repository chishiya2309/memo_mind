import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../domain/review_models.dart';
import '../domain/review_repository.dart';

class ReviewSessionController extends ChangeNotifier {
  ReviewSessionController(this.repository, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;
  final ReviewRepository repository;
  final DateTime Function() _clock;
  ReviewSnapshot? snapshot;
  bool busy = false, revealed = false, awaitingResume = false;
  String? error;
  bool _disposed = false;
  ({String id, String cardId, ReviewRating rating, DateTime at})? _pending;
  bool get hasPendingRating => _pending != null;
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> initialize({
    bool dueOnly = true,
    String? deckId,
    String? cardId,
  }) async {
    if (busy) return;
    busy = true;
    error = null;
    _notify();
    try {
      final active = await repository.getActiveSession();
      awaitingResume = active != null;
      snapshot =
          active ??
          await repository.startSession(
            dueOnly: dueOnly,
            deckId: deckId,
            cardId: cardId,
          );
    } catch (_) {
      error = 'Không thể tải phiên ôn. Vui lòng thử lại.';
    } finally {
      busy = false;
      _notify();
    }
  }

  void resume() {
    awaitingResume = false;
    _notify();
  }

  void reveal() {
    if (busy || snapshot?.card == null || awaitingResume) return;
    revealed = true;
    _notify();
  }

  Future<void> rate(ReviewRating rating) async {
    if (busy || !revealed || snapshot?.card == null || awaitingResume) return;
    _pending ??= (
      id: const Uuid().v4(),
      cardId: snapshot!.card!.id,
      rating: rating,
      at: _clock().toUtc(),
    );
    final pending = _pending!;
    busy = true;
    error = null;
    _notify();
    try {
      snapshot = await repository.rate(
        sessionId: snapshot!.session.id,
        cardId: pending.cardId,
        eventId: pending.id,
        reviewedAt: pending.at,
        rating: pending.rating,
      );
      _pending = null;
      revealed = false;
    } catch (_) {
      error = 'Chưa lưu được đánh giá. Thẻ vẫn được giữ lại để thử lại.';
    } finally {
      busy = false;
      _notify();
    }
  }

  Future<void> retry() async {
    if (_pending != null) await rate(_pending!.rating);
  }

  Future<void> reload() async {
    if (busy || snapshot == null) return;
    busy = true;
    error = null;
    _notify();
    try {
      snapshot = await repository.loadSession(snapshot!.session.id);
      _pending = null;
      revealed = false;
    } catch (_) {
      error = 'Không thể tải lại phiên ôn.';
    } finally {
      busy = false;
      _notify();
    }
  }

  Future<void> end() async {
    if (busy || snapshot == null) return;
    busy = true;
    error = null;
    _notify();
    try {
      snapshot = await repository.endSession(snapshot!.session.id);
      _pending = null;
      awaitingResume = false;
    } catch (_) {
      error = 'Không thể kết thúc phiên. Vui lòng thử lại.';
    } finally {
      busy = false;
      _notify();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

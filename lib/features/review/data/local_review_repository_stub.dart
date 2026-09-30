import '../../../core/database/memo_mind_database.dart';
import '../../home/domain/home_dashboard_data.dart';
import '../domain/review_models.dart';
import '../domain/review_repository.dart';

class LocalReviewRepository implements ReviewRepository {
  LocalReviewRepository({
    MemoMindDatabase? database,
    DateTime Function()? clock,
  });

  Never _unsupported() =>
      throw UnsupportedError('Ôn tập ngoại tuyến hiện hỗ trợ trên Android.');
  @override
  Future<List<ReviewDeck>> getDecks() async => _unsupported();
  @override
  Future<HomeDashboardData> getDashboard() async => _unsupported();
  @override
  Future<ReviewSnapshot?> getActiveSession() async => _unsupported();
  @override
  Future<ReviewSnapshot?> startSession({
    bool dueOnly = true,
    String? deckId,
    String? cardId,
  }) async => _unsupported();
  @override
  Future<ReviewSnapshot> loadSession(String sessionId) async => _unsupported();
  @override
  Future<ReviewSnapshot> rate({
    required String sessionId,
    required String cardId,
    required String eventId,
    required DateTime reviewedAt,
    required ReviewRating rating,
  }) async => _unsupported();
  @override
  Future<ReviewSnapshot> endSession(String sessionId) async => _unsupported();
}

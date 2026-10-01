import '../../home/domain/home_dashboard_data.dart';
import 'review_models.dart';

abstract class ReviewRepository {
  Future<List<ReviewDeck>> getDecks();
  Future<HomeDashboardData> getDashboard();
  Future<ReviewSnapshot?> getActiveSession();
  Future<ReviewSnapshot?> startSession({
    bool dueOnly = true,
    String? deckId,
    String? cardId,
  });
  Future<ReviewSnapshot> loadSession(String sessionId);
  Future<ReviewSnapshot> rate({
    required String sessionId,
    required String cardId,
    required String eventId,
    required DateTime reviewedAt,
    required ReviewRating rating,
  });
  Future<ReviewSnapshot> endSession(String sessionId);
}

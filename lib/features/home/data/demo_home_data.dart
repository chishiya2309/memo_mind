import '../domain/home_dashboard_data.dart';

HomeDashboardData demoHomeDashboard({DateTime? now}) {
  final today = now ?? DateTime.now();
  return HomeDashboardData(
    now: today,
    displayName: 'Hưng',
    review: const ReviewPlan(
      totalToday: 18,
      reviewedToday: 7,
      deckCount: 3,
      estimatedMinutes: 8,
    ),
    totalDeckCount: 4,
    weeklyStats: const WeeklyStats(
      streakDays: 6,
      reviewedCards: 124,
      accuracyPercent: 87,
    ),
    recentDecks: const [
      DeckPreview(
        id: 'data-structures',
        title: 'Cấu trúc dữ liệu',
        dueCount: 12,
        estimatedMinutes: 5,
        learnedPercent: 68,
        tone: DeckTone.indigo,
      ),
      DeckPreview(
        id: 'computer-networks',
        title: 'Mạng máy tính',
        dueCount: 6,
        estimatedMinutes: 3,
        learnedPercent: 82,
        tone: DeckTone.teal,
      ),
    ],
    recentDocuments: [
      HomeDocumentPreview(
        id: 'database-chapter-4',
        title: 'Cơ sở dữ liệu Chương 4',
        pageCount: 6,
        importedAt: today.subtract(const Duration(days: 1)),
        state: HomeDocumentState.hasCards,
        cardCount: 24,
      ),
      HomeDocumentPreview(
        id: 'operating-systems',
        title: 'Bài giảng Hệ điều hành',
        pageCount: 4,
        importedAt: today.subtract(const Duration(days: 3)),
        state: HomeDocumentState.needsReview,
      ),
    ],
  );
}

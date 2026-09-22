enum HomeLoadState { loading, ready, error }

enum HomeSyncState { idle, syncing, failed }

enum DeckTone { indigo, teal, blue, amber, rose, violet }

enum HomeJobKind { ocr, ai }

enum HomeJobState { running, needsReview, failed }

enum HomeDocumentState { ocrDone, needsReview, hasCards, noCards }

enum ImportSource { camera, gallery, pdf, manualDeck }

class ReviewPlan {
  const ReviewPlan({
    required this.totalToday,
    required this.reviewedToday,
    required this.deckCount,
    required this.estimatedMinutes,
  });

  final int totalToday;
  final int reviewedToday;
  final int deckCount;
  final int estimatedMinutes;

  int get remaining =>
      totalToday > reviewedToday ? totalToday - reviewedToday : 0;

  double get progress =>
      totalToday <= 0 ? 0 : (reviewedToday / totalToday).clamp(0.0, 1.0);
}

class WeeklyStats {
  const WeeklyStats({
    required this.streakDays,
    required this.reviewedCards,
    this.accuracyPercent,
  });

  final int streakDays;
  final int reviewedCards;
  final int? accuracyPercent;
}

class DeckPreview {
  const DeckPreview({
    required this.id,
    required this.title,
    required this.dueCount,
    required this.estimatedMinutes,
    required this.learnedPercent,
    required this.tone,
    this.statusLabel,
  });

  final String id;
  final String title;
  final int dueCount;
  final int estimatedMinutes;
  final int learnedPercent;
  final DeckTone tone;
  final String? statusLabel;
}

class HomeJobPreview {
  const HomeJobPreview({
    required this.id,
    required this.title,
    required this.description,
    required this.kind,
    required this.state,
    this.progress,
  });

  final String id;
  final String title;
  final String description;
  final HomeJobKind kind;
  final HomeJobState state;
  final double? progress;
}

class HomeDocumentPreview {
  const HomeDocumentPreview({
    required this.id,
    required this.title,
    required this.pageCount,
    required this.importedAt,
    required this.state,
    this.cardCount = 0,
  });

  final String id;
  final String title;
  final int pageCount;
  final DateTime importedAt;
  final HomeDocumentState state;
  final int cardCount;
}

/// A presentation snapshot. Future SQLite repositories can produce this model.
class HomeDashboardData {
  const HomeDashboardData({
    required this.now,
    required this.review,
    required this.totalDeckCount,
    this.displayName,
    this.weeklyStats,
    this.recentDecks = const [],
    this.jobs = const [],
    this.recentDocuments = const [],
    this.pendingApprovalCount = 0,
    this.pendingApprovalDocument,
    this.isOffline = false,
    this.syncState = HomeSyncState.idle,
    this.pendingSyncChanges = 0,
    this.loadState = HomeLoadState.ready,
    this.loadError,
  });

  final DateTime now;
  final String? displayName;
  final ReviewPlan review;
  final int totalDeckCount;
  final WeeklyStats? weeklyStats;
  final List<DeckPreview> recentDecks;
  final List<HomeJobPreview> jobs;
  final List<HomeDocumentPreview> recentDocuments;
  final int pendingApprovalCount;
  final String? pendingApprovalDocument;
  final bool isOffline;
  final HomeSyncState syncState;
  final int pendingSyncChanges;
  final HomeLoadState loadState;
  final String? loadError;
}

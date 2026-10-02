import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../features/review/data/local_review_repository.dart';
import '../features/review/presentation/review_session_screen.dart';
import '../features/review/presentation/review_deck_selection_screen.dart';
import '../features/home/domain/home_dashboard_data.dart';
import '../features/home/presentation/home_screen.dart';
import '../features/document_import/data/local_document_import_repository.dart';
import '../features/document_import/domain/document_import_models.dart';
import '../features/document_import/presentation/document_import_flow.dart';
import '../features/document_import/presentation/pdf_import_flow.dart';
import '../features/deck_management/data/local_deck_repository.dart';
import '../features/deck_management/domain/deck_repository.dart';
import '../features/deck_management/presentation/deck_detail_screen.dart';
import '../features/deck_management/presentation/library_decks_screen.dart';
import '../features/deck_management/presentation/widgets/deck_form_dialog.dart';
import '../shared/theme/memo_theme.dart';

class MemoMindApp extends StatefulWidget {
  const MemoMindApp({super.key});

  @override
  State<MemoMindApp> createState() => _MemoMindAppState();
}

class _MemoMindAppState extends State<MemoMindApp> {
  late final LocalDocumentImportRepository _importRepository;
  late final DeckRepository _deckRepository;
  late final Future<void> _recovery;
  final _reviewRepository = LocalReviewRepository();
  late Future<HomeDashboardData> _dashboard;

  @override
  void initState() {
    super.initState();
    _importRepository = LocalDocumentImportRepository();
    _deckRepository = LocalDeckRepository();
    _recovery = _importRepository.recoverInterruptedImports();
    _dashboard = _loadDashboard();
  }

  Future<HomeDashboardData> _loadDashboard() async {
    await _recovery;
    if (kIsWeb) {
      return HomeDashboardData(
        now: DateTime.now(),
        review: const ReviewPlan(
          totalToday: 0,
          reviewedToday: 0,
          deckCount: 0,
          estimatedMinutes: 0,
        ),
        totalDeckCount: 0,
      );
    }
    return _reviewRepository.getDashboard();
  }

  void _refreshDashboard() {
    if (!mounted) return;

    final dashboardFuture = _loadDashboard();

    setState(() {
      _dashboard = dashboardFuture;
    });
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'MemoMind',
    debugShowCheckedModeBanner: false,
    locale: const Locale('vi'),
    supportedLocales: const [Locale('vi')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    theme: MemoTheme.light,
    darkTheme: MemoTheme.dark,
    themeMode: ThemeMode.system,
    home: Builder(
      builder: (context) {
        void openPlaceholder(String title) {
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (context) => _FeaturePlaceholder(title: title),
            ),
          );
        }

        void showUnimplemented(String title) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('$title chưa được triển khai.')),
          );
        }

        Future<void> startImageImport(DocumentImageSource source) async {
          await Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => DocumentImportFlow(
                initialSource: source,
                repository: _importRepository,
              ),
            ),
          );
          _refreshDashboard();
        }

        Future<void> startPdfImport() async {
          await Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => PdfImportFlow(repository: _importRepository),
            ),
          );
          _refreshDashboard();
        }

        Future<void> openReview({String? deckId}) async {
          await Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) =>
                  ReviewSessionScreen(deckId: deckId, dueOnly: deckId == null),
            ),
          );
          _refreshDashboard();
        }

        Future<void> selectReviewDeck({bool dueOnly = false}) async {
          await Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => ReviewDeckSelectionScreen(dueOnly: dueOnly),
            ),
          );
          _refreshDashboard();
        }

        Future<void> openDeck(String deckId) async {
          await Navigator.of(context).push<void>(
            MaterialPageRoute<void>(
              builder: (_) =>
                  DeckDetailScreen(deckId: deckId, repository: _deckRepository),
            ),
          );
          _refreshDashboard();
        }

        Future<void> openLibrary() async {
          await Navigator.of(context).push<void>(
            MaterialPageRoute<void>(
              builder: (_) => Scaffold(
                appBar: AppBar(title: const Text('Thư viện')),
                body: LibraryDecksScreen(
                  repository: _deckRepository,
                  onOpenDeck: openDeck,
                  onOpenDeckAsync: openDeck,
                  onChanged: _refreshDashboard,
                ),
              ),
            ),
          );
          _refreshDashboard();
        }

        Future<void> createManualDeck() async {
          String? deckId;
          final form = await DeckFormDialog.show(
            context,
            onSave: (data) async {
              final deck = await _deckRepository.createDeck(
                title: data.title,
                tags: data.tags,
              );
              deckId = deck.id;
            },
          );
          if (form == null || !context.mounted || deckId == null) return;
          await openDeck(deckId!);
        }

        return FutureBuilder<HomeDashboardData>(
          future: _dashboard,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done &&
                !snapshot.hasData) {
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }
            return HomeScreen(
              data:
                  snapshot.data ??
                  HomeDashboardData(
                    now: DateTime.now(),
                    review: const ReviewPlan(
                      totalToday: 0,
                      reviewedToday: 0,
                      deckCount: 0,
                      estimatedMinutes: 0,
                    ),
                    totalDeckCount: 0,
                    loadState: HomeLoadState.error,
                    loadError:
                        'Không thể tải dữ liệu cục bộ. Vui lòng thử lại.',
                  ),
              actions: HomeActions(
                onStartReview: () => openReview(),
                onFreeReview: () => selectReviewDeck(),
                onOpenDueDecks: () => selectReviewDeck(dueOnly: true),
                onOpenDeck: openDeck,
                onStartDeckReview: (id) => openReview(deckId: id),
                onOpenDocument: (_) => openPlaceholder('Chi tiết tài liệu'),
                onOpenStatistics: () => openPlaceholder('Thống kê'),
                onOpenLibrary: openLibrary,
                onOpenProfile: () => openPlaceholder('Cá nhân'),
                onOpenApprovals: () => openPlaceholder('Duyệt thẻ AI'),
                onOpenJob: (_) => openPlaceholder('Tác vụ học liệu'),
                onRetrySync: () => showUnimplemented('Đồng bộ'),
                onRetryLoad: _refreshDashboard,
                onImport: (source) async {
                  switch (source) {
                    case ImportSource.camera:
                      return startImageImport(DocumentImageSource.camera);
                    case ImportSource.gallery:
                      return startImageImport(DocumentImageSource.gallery);
                    case ImportSource.pdf:
                      return startPdfImport();
                    case ImportSource.manualDeck:
                      return createManualDeck();
                  }
                },
              ),
              libraryRepository: _deckRepository,
              onOpenDeckAsync: openDeck,
            );
          },
        );
      },
    ),
  );
}

class _FeaturePlaceholder extends StatelessWidget {
  const _FeaturePlaceholder({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final p = MemoPalette.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.construction_rounded, color: p.primary, size: 44),
              const SizedBox(height: 16),
              Text(
                'Tính năng này chưa được triển khai.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

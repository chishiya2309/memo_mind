import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../features/home/data/demo_home_data.dart';
import '../features/home/domain/home_dashboard_data.dart';
import '../features/home/presentation/home_screen.dart';
import '../features/document_import/data/local_document_import_repository.dart';
import '../features/document_import/domain/document_import_models.dart';
import '../features/document_import/presentation/document_import_flow.dart';
import '../features/document_import/presentation/pdf_import_flow.dart';
import '../shared/theme/memo_theme.dart';

class MemoMindApp extends StatefulWidget {
  const MemoMindApp({super.key});

  @override
  State<MemoMindApp> createState() => _MemoMindAppState();
}

class _MemoMindAppState extends State<MemoMindApp> {
  late final LocalDocumentImportRepository _importRepository;
  late final Future<void> _recovery;

  @override
  void initState() {
    super.initState();
    _importRepository = LocalDocumentImportRepository();
    _recovery = _importRepository.recoverInterruptedImports();
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

        void startImageImport(DocumentImageSource source) {
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => DocumentImportFlow(
                initialSource: source,
                repository: _importRepository,
              ),
            ),
          );
        }

        void startPdfImport() {
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => PdfImportFlow(repository: _importRepository),
            ),
          );
        }

        return FutureBuilder<void>(
          future: _recovery,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }
            return HomeScreen(
              data: demoHomeDashboard(),
              actions: HomeActions(
                onStartReview: () => openPlaceholder('Phiên ôn tập'),
                onFreeReview: () => openPlaceholder('Ôn tự do'),
                onOpenDueDecks: () => openPlaceholder('Bộ thẻ đến hạn'),
                onOpenDeck: (_) => openPlaceholder('Chi tiết bộ thẻ'),
                onStartDeckReview: (_) => openPlaceholder('Phiên ôn bộ thẻ'),
                onOpenDocument: (_) => openPlaceholder('Chi tiết tài liệu'),
                onOpenStatistics: () => openPlaceholder('Thống kê'),
                onOpenLibrary: () => openPlaceholder('Thư viện'),
                onOpenProfile: () => openPlaceholder('Cá nhân'),
                onOpenApprovals: () => openPlaceholder('Duyệt thẻ AI'),
                onOpenJob: (_) => openPlaceholder('Tác vụ học liệu'),
                onRetrySync: () => showUnimplemented('Đồng bộ'),
                onRetryLoad: () => showUnimplemented('Tải dữ liệu'),
                onImport: (source) {
                  switch (source) {
                    case ImportSource.camera:
                      return startImageImport(DocumentImageSource.camera);
                    case ImportSource.gallery:
                      return startImageImport(DocumentImageSource.gallery);
                    case ImportSource.pdf:
                      return startPdfImport();
                    case ImportSource.manualDeck:
                      return showUnimplemented('Tạo deck thủ công');
                  }
                },
              ),
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

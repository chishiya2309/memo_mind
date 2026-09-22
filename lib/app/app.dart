import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../features/home/data/demo_home_data.dart';
import '../features/home/domain/home_dashboard_data.dart';
import '../features/home/presentation/home_screen.dart';
import '../shared/theme/memo_theme.dart';

class MemoMindApp extends StatelessWidget {
  const MemoMindApp({super.key});

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
            onImport: (source) => showUnimplemented(switch (source) {
              ImportSource.camera => 'Chụp bài giảng',
              ImportSource.gallery => 'Chọn ảnh',
              ImportSource.pdf => 'Nhập PDF',
              ImportSource.manualDeck => 'Tạo deck thủ công',
            }),
          ),
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

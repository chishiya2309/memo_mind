import 'dart:async';
import 'package:flutter/material.dart';

import '../../../shared/theme/memo_theme.dart';
import '../../document_import/domain/document_import_models.dart';
import '../application/ocr_orchestrator.dart';
import 'ocr_dual_view_editor_screen.dart';

class OcrProcessingScreen extends StatefulWidget {
  const OcrProcessingScreen({
    super.key,
    required this.document,
    required this.selectedPages,
    this.orchestrator,
  });

  final ImportedDocument document;
  final List<SourcePage> selectedPages;
  final OcrOrchestrator? orchestrator;

  @override
  State<OcrProcessingScreen> createState() => _OcrProcessingScreenState();
}

class _OcrProcessingScreenState extends State<OcrProcessingScreen> {
  late final OcrOrchestrator _orchestrator;
  StreamSubscription<OcrBatchProgress>? _subscription;

  OcrBatchProgress? _progress;
  bool _isProcessing = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _orchestrator = widget.orchestrator ?? OcrOrchestrator();
    _runOcr(widget.selectedPages);
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  void _runOcr(List<SourcePage> pages) {
    setState(() {
      _isProcessing = true;
      _errorMessage = null;
    });

    _subscription?.cancel();
    _subscription = _orchestrator
        .processPages(
          document: widget.document,
          selectedPages: pages,
        )
        .listen(
          (progress) {
            setState(() {
              _progress = progress;
              if (progress.isDone) {
                _isProcessing = false;
              }
            });
          },
          onError: (Object error) {
            setState(() {
              _isProcessing = false;
              _errorMessage = error.toString();
            });
          },
        );
  }

  void _goToEditor() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => OcrDualViewEditorScreen(
          document: widget.document,
        ),
      ),
    );
  }

  void _finishLater() {
    // Luồng 17a: Để sau -> quay về màn hình trước đó hoặc trang chủ
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  void _retryFailed() {
    if (_progress == null || _progress!.failedPages.isEmpty) return;
    _runOcr(_progress!.failedPages);
  }

  @override
  Widget build(BuildContext context) {
    final palette = MemoPalette.of(context);
    final progress = _progress;

    return PopScope(
      canPop: !_isProcessing,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Nhận dạng văn bản'),
          automaticallyImplyLeading: !_isProcessing,
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (_isProcessing) ...[
                    SizedBox(
                      width: 80,
                      height: 80,
                      child: CircularProgressIndicator(
                        value: progress?.ratio,
                        strokeWidth: 6,
                        backgroundColor: palette.hero,
                        color: palette.primary,
                      ),
                    ),
                    const SizedBox(height: 28),
                    Text(
                      progress?.message ?? 'Đang khởi động nhận dạng OCR…',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Quá trình nhận dạng diễn ra trực tiếp trên thiết bị (Offline)',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ] else if (_errorMessage != null) ...[
                    Icon(Icons.error_outline_rounded, size: 64, color: palette.error),
                    const SizedBox(height: 16),
                    Text(
                      'Nhận dạng thất bại',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _errorMessage!,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: () => _runOcr(widget.selectedPages),
                      child: const Text('Thử lại'),
                    ),
                  ] else ...[
                    // Completed status
                    Icon(
                      progress?.failedPages.isEmpty ?? true
                          ? Icons.check_circle_rounded
                          : Icons.warning_amber_rounded,
                      size: 72,
                      color: progress?.failedPages.isEmpty ?? true
                          ? palette.success
                          : palette.warning,
                    ),
                    const SizedBox(height: 20),
                    Text(
                      progress?.failedPages.isEmpty ?? true
                          ? 'Nhận dạng thành công!'
                          : 'Nhận dạng hoàn tất một phần',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      progress?.failedPages.isEmpty ?? true
                          ? 'Đã nhận dạng ${progress?.successfulPages.length ?? 0} trang. Bạn có thể tiến hành hiệu chỉnh nội dung ngay.'
                          : 'Thành công ${progress?.successfulPages.length ?? 0} trang, thất bại ${progress?.failedPages.length ?? 0} trang.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 32),
                    if (progress != null && progress.failedPages.isNotEmpty) ...[
                      OutlinedButton.icon(
                        key: const Key('retry-failed-pages-btn'),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(48),
                        ),
                        onPressed: _retryFailed,
                        icon: const Icon(Icons.refresh_rounded),
                        label: Text('Thử lại ${progress.failedPages.length} trang lỗi'),
                      ),
                      const SizedBox(height: 12),
                    ],
                    FilledButton.icon(
                      key: const Key('go-to-editor-btn'),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(52),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      onPressed: (progress?.successfulPages.isNotEmpty ?? false)
                          ? _goToEditor
                          : null,
                      icon: const Icon(Icons.edit_note_rounded),
                      label: const Text(
                        'Bắt đầu hiệu chỉnh (UC05)',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextButton(
                      key: const Key('ocr-finish-later-btn'),
                      onPressed: _finishLater,
                      child: const Text('Để sau (Lưu bản nháp)'),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

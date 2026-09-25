import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../shared/theme/memo_theme.dart';
import '../application/image_inspector.dart';
import '../data/gallery_image_picker.dart';
import '../domain/document_import_models.dart';
import '../domain/document_import_repository.dart';
import 'document_camera_screen.dart';
import 'stored_image.dart';

class DocumentImportFlow extends StatefulWidget {
  const DocumentImportFlow({
    super.key,
    required this.initialSource,
    required this.repository,
    this.existingDocumentId,
    this.onContinue,
    this.inspector = const ImageInspector(),
    this.galleryPicker,
  });

  final DocumentImageSource initialSource;
  final String? existingDocumentId;
  final DocumentImportRepository repository;
  final ImageInspector inspector;
  final GalleryImagePicker? galleryPicker;
  final ValueChanged<ImportedDocument>? onContinue;

  @override
  State<DocumentImportFlow> createState() => _DocumentImportFlowState();
}

class _DocumentImportFlowState extends State<DocumentImportFlow> {
  late final GalleryImagePicker _gallery;
  ImportedDocument? _document;
  bool _busy = false;
  String _busyLabel = 'Đang chuẩn bị…';

  @override
  void initState() {
    super.initState();
    _gallery = widget.galleryPicker ?? GalleryImagePicker();
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  Future<void> _start() async {
    if (kIsWeb) {
      await _showMessage('Nhập ảnh hiện chỉ được hỗ trợ trên Android.');
      if (mounted) Navigator.of(context).pop();
      return;
    }
    if (widget.existingDocumentId != null) {
      try {
        _document = await widget.repository.getDocument(
          widget.existingDocumentId!,
        );
      } on ImportFailure catch (error) {
        await _showMessage(error.message);
        if (mounted) Navigator.of(context).pop();
        return;
      }
    }
    await _acquire(widget.initialSource);
  }

  Future<void> _acquire(DocumentImageSource source) async {
    if (!mounted) return;
    ImageCandidate? candidate;
    try {
      if (source == DocumentImageSource.camera) {
        final outcome = await Navigator.of(context).push<CameraCaptureOutcome>(
          MaterialPageRoute(builder: (_) => const DocumentCameraScreen()),
        );
        if (!mounted) return;
        if (outcome?.chooseGallery ?? false) {
          await _acquire(DocumentImageSource.gallery);
          return;
        }
        candidate = outcome?.candidate;
      } else {
        candidate = await _gallery.retrieveLostImage();
        candidate ??= await _gallery.pickImage();
      }
    } on ImportFailure catch (error) {
      final alternate = await _showSourceError(error, source);
      if (!mounted) return;
      if (alternate != null) {
        await _acquire(alternate);
      } else if (_document == null) {
        Navigator.of(context).pop();
      }
      return;
    } catch (_) {
      await _showMessage(
        source == DocumentImageSource.camera
            ? 'Không thể chụp ảnh. Vui lòng thử lại hoặc chọn ảnh từ thư viện.'
            : 'Không thể mở ảnh. Vui lòng thử lại.',
      );
      if (_document == null && mounted) Navigator.of(context).pop();
      return;
    }

    if (candidate == null) {
      if (_document == null && mounted) Navigator.of(context).pop();
      return;
    }
    await _previewCandidate(candidate);
  }

  Future<void> _previewCandidate(ImageCandidate candidate) async {
    final decision = await Navigator.of(context).push<_PreviewDecision>(
      MaterialPageRoute(
        builder: (_) => _ImagePreviewScreen(candidate: candidate),
      ),
    );
    if (!mounted) return;
    switch (decision) {
      case _PreviewDecision.use:
        await _inspectAndSave(candidate);
      case _PreviewDecision.retry:
        await widget.repository.discardCandidate(candidate);
        await _acquire(candidate.source);
      case _PreviewDecision.cancel:
      case null:
        await widget.repository.discardCandidate(candidate);
        if (_document == null && mounted) Navigator.of(context).pop();
    }
  }

  Future<void> _inspectAndSave(ImageCandidate candidate) async {
    _setBusy(true, 'Đang kiểm tra ảnh…');
    ImageInspection inspection;
    try {
      inspection = await widget.inspector.inspect(candidate.bytes);
    } on ImportFailure catch (error) {
      _setBusy(false);
      final retry = await _showRetryError(error.message);
      if (!mounted) return;
      if (retry) {
        await widget.repository.discardCandidate(candidate);
        await _acquire(candidate.source);
      } else {
        await widget.repository.discardCandidate(candidate);
        if (!mounted) return;
        if (_document == null) Navigator.of(context).pop();
      }
      return;
    } catch (_) {
      _setBusy(false);
      await _showMessage('Tệp ảnh bị lỗi hoặc không thể đọc.');
      await widget.repository.discardCandidate(candidate);
      if (_document == null && mounted) Navigator.of(context).pop();
      return;
    }
    _setBusy(false);

    var acceptedWarning = false;
    if (inspection.hasQualityWarning) {
      final proceed = await _showQualityWarning();
      if (!mounted) return;
      if (!proceed) {
        await widget.repository.discardCandidate(candidate);
        await _chooseAndAcquire();
        return;
      }
      acceptedWarning = true;
    }

    var retry = true;
    while (retry && mounted) {
      retry = false;
      _setBusy(true, 'Đang lưu ảnh gốc…');
      try {
        final currentId = _document?.documentId ?? widget.existingDocumentId;
        final saved = currentId == null
            ? await widget.repository.createWithFirstPage(
                candidate: candidate,
                inspection: inspection,
                qualityWarningAccepted: acceptedWarning,
              )
            : await widget.repository.appendPage(
                documentId: currentId,
                candidate: candidate,
                inspection: inspection,
                qualityWarningAccepted: acceptedWarning,
              );
        if (!mounted) return;
        setState(() {
          _document = saved;
          _busy = false;
        });
      } on ImportFailure catch (error) {
        _setBusy(false);
        retry = await _showSaveError(error);
        if (!retry) {
          await widget.repository.discardCandidate(candidate);
          if (_document == null && mounted) Navigator.of(context).pop();
        }
      }
    }
  }

  Future<void> _chooseAndAcquire() async {
    final source = await showModalBottomSheet<DocumentImageSource>(
      context: context,
      useSafeArea: true,
      backgroundColor: MemoPalette.of(context).surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (_) => const _ImageSourceSheet(),
    );
    if (source != null && mounted) await _acquire(source);
  }

  Future<bool> _showQualityWarning() async =>
      (await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          icon: Icon(
            Icons.warning_amber_rounded,
            color: MemoPalette.of(context).warning,
          ),
          title: const Text('Ảnh có thể khó nhận dạng'),
          content: const Text(
            'Ảnh có dấu hiệu bị mờ hoặc thiếu sáng. Bạn muốn chọn lại ảnh hay vẫn tiếp tục?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Chụp/chọn lại'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Vẫn tiếp tục'),
            ),
          ],
        ),
      )) ??
      false;

  Future<bool> _showRetryError(String message) async =>
      (await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Không thể sử dụng ảnh'),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Hủy'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Chọn ảnh khác'),
            ),
          ],
        ),
      )) ??
      false;

  Future<bool> _showSaveError(ImportFailure failure) async {
    final canRetry = failure.code != ImportFailureCode.insufficientStorage;
    return (await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(
              failure.code == ImportFailureCode.insufficientStorage
                  ? 'Không đủ dung lượng'
                  : 'Không thể lưu ảnh',
            ),
            content: Text(failure.message),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Hủy'),
              ),
              if (canRetry)
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Thử lại'),
                ),
            ],
          ),
        )) ??
        false;
  }

  Future<DocumentImageSource?> _showSourceError(
    ImportFailure failure,
    DocumentImageSource source,
  ) => showDialog<DocumentImageSource>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Không thể tiếp tục'),
      content: Text(failure.message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Hủy'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, source),
          child: const Text('Thử lại'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(
            context,
            source == DocumentImageSource.camera
                ? DocumentImageSource.gallery
                : DocumentImageSource.camera,
          ),
          child: Text(
            source == DocumentImageSource.camera
                ? 'Chọn từ thư viện'
                : 'Chụp bằng camera',
          ),
        ),
      ],
    ),
  );

  Future<void> _showMessage(String message) => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      content: Text(message),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Đóng'),
        ),
      ],
    ),
  );

  void _setBusy(bool value, [String? label]) {
    if (!mounted) return;
    setState(() {
      _busy = value;
      if (label != null) _busyLabel = label;
    });
  }

  void _continue() {
    final document = _document;
    if (document == null) return;
    widget.onContinue?.call(document);
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PendingProcessingScreen(document: document),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final document = _document;
    return PopScope(
      canPop: !_busy,
      child: Scaffold(
        appBar: AppBar(title: const Text('Nhập tài liệu')),
        bottomNavigationBar: document == null
            ? null
            : SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size(0, 52),
                          ),
                          onPressed: _busy ? null : _chooseAndAcquire,
                          icon: const Icon(Icons.add_photo_alternate_outlined),
                          label: const Text('Thêm trang'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton(
                          onPressed: _busy ? null : _continue,
                          child: const Text('Tiếp tục'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
        body: Stack(
          children: [
            if (document == null)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'Chọn hoặc chụp một ảnh để tạo tài liệu mới.',
                    textAlign: TextAlign.center,
                  ),
                ),
              )
            else
              _ImportSummary(
                document: document,
                onAddPage: _chooseAndAcquire,
                onContinue: _continue,
              ),
            if (_busy)
              Positioned.fill(
                child: ColoredBox(
                  color: Colors.black38,
                  child: Center(
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const CircularProgressIndicator(),
                            const SizedBox(height: 16),
                            Text(_busyLabel),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

enum _PreviewDecision { use, retry, cancel }

class _ImagePreviewScreen extends StatelessWidget {
  const _ImagePreviewScreen({required this.candidate});

  final ImageCandidate candidate;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    appBar: AppBar(
      backgroundColor: Colors.black,
      foregroundColor: Colors.white,
      title: const Text('Xem trước ảnh'),
      leading: IconButton(
        onPressed: () => Navigator.pop(context, _PreviewDecision.cancel),
        icon: const Icon(Icons.close_rounded),
      ),
    ),
    body: SafeArea(
      child: Column(
        children: [
          Expanded(
            child: InteractiveViewer(
              minScale: 0.8,
              maxScale: 4,
              child: Center(
                child: Image.memory(
                  candidate.bytes,
                  fit: BoxFit.contain,
                  errorBuilder: (_, _, _) => const Text(
                    'Không thể hiển thị ảnh.',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      minimumSize: const Size(0, 52),
                    ),
                    onPressed: () =>
                        Navigator.pop(context, _PreviewDecision.retry),
                    child: Text(
                      candidate.source == DocumentImageSource.camera
                          ? 'Chụp lại'
                          : 'Chọn ảnh khác',
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: () =>
                        Navigator.pop(context, _PreviewDecision.use),
                    child: const Text('Sử dụng ảnh'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _ImportSummary extends StatelessWidget {
  const _ImportSummary({
    required this.document,
    required this.onAddPage,
    required this.onContinue,
  });

  final ImportedDocument document;
  final VoidCallback onAddPage;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    final p = MemoPalette.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 120),
              sliver: SliverList.list(
                children: [
                  Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: p.secondaryContainer,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(Icons.check_rounded, color: p.success),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              document.title,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            Text(
                              '${document.pages.length} trang · Chờ xử lý',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          mainAxisSpacing: 12,
                          crossAxisSpacing: 12,
                          childAspectRatio: 0.75,
                        ),
                    itemCount: document.pages.length,
                    itemBuilder: (context, index) {
                      final page = document.pages[index];
                      return Semantics(
                        label: 'Trang ${page.pageNumber}',
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(14),
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              ColoredBox(
                                color: p.surfaceMuted,
                                child: StoredImage(path: page.absolutePath),
                              ),
                              Positioned(
                                left: 8,
                                bottom: 8,
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    color: Colors.black87,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 9,
                                      vertical: 5,
                                    ),
                                    child: Text(
                                      'Trang ${page.pageNumber}',
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelSmall
                                          ?.copyWith(color: Colors.white),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ImageSourceSheet extends StatelessWidget {
  const _ImageSourceSheet();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Center(
          child: Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: MemoPalette.of(context).outline,
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
        const SizedBox(height: 20),
        Text('Thêm trang', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        ListTile(
          minTileHeight: 64,
          leading: const Icon(Icons.camera_alt_outlined),
          title: const Text('Chụp ảnh'),
          subtitle: const Text('Dùng camera để thêm một trang'),
          onTap: () => Navigator.pop(context, DocumentImageSource.camera),
        ),
        ListTile(
          minTileHeight: 64,
          leading: const Icon(Icons.image_outlined),
          title: const Text('Chọn từ thư viện'),
          subtitle: const Text('Nhập một ảnh có sẵn trên thiết bị'),
          onTap: () => Navigator.pop(context, DocumentImageSource.gallery),
        ),
      ],
    ),
  );
}

class PendingProcessingScreen extends StatelessWidget {
  const PendingProcessingScreen({super.key, required this.document});

  final ImportedDocument document;

  @override
  Widget build(BuildContext context) {
    final p = MemoPalette.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Tài liệu đã nhập')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: p.hero,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.schedule_rounded,
                    color: p.primary,
                    size: 36,
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'Tài liệu đang chờ xử lý',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                Text(
                  '${document.pages.length} trang ảnh gốc đã được lưu an toàn trên thiết bị. OCR sẽ được nối vào bước tiếp theo.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 20),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: p.surfaceMuted,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: SelectableText(
                    'documentId: ${document.documentId}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: () =>
                      Navigator.of(context).popUntil((route) => route.isFirst),
                  icon: const Icon(Icons.home_outlined),
                  label: const Text('Về trang chủ'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

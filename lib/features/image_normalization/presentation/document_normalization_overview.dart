import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../shared/theme/memo_theme.dart';
import '../../document_import/application/image_inspector.dart';
import '../../document_import/data/local_document_import_repository.dart';
import '../../document_import/domain/document_import_models.dart';
import '../../document_import/domain/document_import_repository.dart';
import '../../document_import/presentation/stored_image.dart';
import '../application/image_normalization_engine.dart';
import '../data/document_scan_engine.dart';
import '../data/local_image_normalization_repository.dart';
import '../domain/image_normalization_models.dart';
import '../domain/image_normalization_repository.dart';

class PendingProcessingScreen extends StatefulWidget {
  const PendingProcessingScreen({
    super.key,
    required this.document,
    this.documentRepository,
    this.normalizationRepository,
    this.engine,
    this.onRecognizeText,
    this.inspector = const ImageInspector(),
  });

  final ImportedDocument document;
  final DocumentImportRepository? documentRepository;
  final ImageNormalizationRepository? normalizationRepository;
  final ImageNormalizationEngine? engine;
  final ValueChanged<ImportedDocument>? onRecognizeText;
  final ImageInspector inspector;

  @override
  State<PendingProcessingScreen> createState() =>
      _PendingProcessingScreenState();
}

class _PendingProcessingScreenState extends State<PendingProcessingScreen> {
  late ImportedDocument _document;
  late final DocumentImportRepository _documents;
  late final ImageNormalizationRepository _normalizations;
  late final ImageNormalizationEngine _engine;

  @override
  void initState() {
    super.initState();
    _document = widget.document;
    _documents = widget.documentRepository ?? LocalDocumentImportRepository();
    _normalizations =
        widget.normalizationRepository ??
        LocalImageNormalizationRepository(documentRepository: _documents);
    _engine = widget.engine ?? DocumentScanImageNormalizationEngine();
  }

  bool get _isReady => _document.pages.every(
    (page) => page.normalizationStatus != PageNormalizationStatus.pending,
  );

  Future<void> _edit(SourcePage page) async {
    if (kIsWeb) {
      await _message('Chuẩn hóa ảnh hiện chỉ được hỗ trợ trên Android.');
      return;
    }
    final result = await Navigator.of(context).push<NormalizationEditorResult>(
      MaterialPageRoute(
        builder: (_) => ImageNormalizationEditorScreen(
          page: page,
          engine: _engine,
          repository: _normalizations,
          inspector: widget.inspector,
        ),
      ),
    );
    if (!mounted || result == null) return;
    setState(() => _document = result.document);
    if (result.openNext) {
      final next = await _normalizations.getNextPendingPage(
        _document.documentId,
      );
      if (mounted && next != null) await _edit(next);
    }
  }

  void _recognize() {
    widget.onRecognizeText?.call(_document);
    if (widget.onRecognizeText != null) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const _OcrPlaceholderScreen()),
    );
  }

  Future<void> _message(String message) => showDialog<void>(
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

  @override
  Widget build(BuildContext context) {
    final palette = MemoPalette.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Tài liệu đã nhập')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: CustomScrollView(
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 120),
                sliver: SliverList.list(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: _isReady
                            ? palette.secondaryContainer
                            : palette.hero,
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            _isReady
                                ? Icons.document_scanner_outlined
                                : Icons.tune_rounded,
                            color: _isReady ? palette.success : palette.primary,
                            size: 34,
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _isReady || _document.originalFile != null
                                      ? 'Tài liệu đang chờ OCR'
                                      : 'Tài liệu đang chờ xử lý',
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '${_document.pages.length} trang · Dữ liệu được xử lý ngoại tuyến',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 22),
                    Text(
                      _document.title,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 4),
                    SelectableText(
                      'documentId: ${_document.documentId}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 18),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final columns = constraints.maxWidth >= 600 ? 3 : 2;
                        return GridView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: columns,
                                mainAxisSpacing: 12,
                                crossAxisSpacing: 12,
                                childAspectRatio: 0.68,
                              ),
                          itemCount: _document.pages.length,
                          itemBuilder: (context, index) {
                            final page = _document.pages[index];
                            return _PageCard(
                              page: page,
                              onEdit: () => _edit(page),
                            );
                          },
                        );
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
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
                  onPressed: () =>
                      Navigator.of(context).popUntil((route) => route.isFirst),
                  icon: const Icon(Icons.home_outlined),
                  label: const Text('Trang chủ'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  key: const Key('recognize-text'),
                  onPressed: _isReady ? _recognize : null,
                  icon: const Icon(Icons.text_snippet_outlined),
                  label: const Text('Nhận dạng văn bản'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PageCard extends StatelessWidget {
  const _PageCard({required this.page, required this.onEdit});

  final SourcePage page;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final ready = page.normalizationStatus != PageNormalizationStatus.pending;
    final palette = MemoPalette.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      margin: EdgeInsets.zero,
      child: InkWell(
        key: Key('normalize-page-${page.pageId}'),
        onTap: onEdit,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: ColoredBox(
                color: palette.surfaceMuted,
                child: StoredImage(path: page.displayPath),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 9, 10, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Trang ${page.pageNumber}',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(
                        ready ? Icons.check_circle_outline : Icons.schedule,
                        size: 16,
                        color: ready ? palette.success : palette.warning,
                      ),
                      const SizedBox(width: 5),
                      Expanded(
                        child: Text(
                          ready ? 'Sẵn sàng OCR' : 'Chưa chuẩn hóa',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    page.normalizedAsset == null
                        ? 'Chuẩn hóa ảnh'
                        : 'Chỉnh sửa ảnh',
                    style: Theme.of(context).textTheme.labelLarge
                        ?.copyWith(color: palette.primary),
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

class NormalizationEditorResult {
  const NormalizationEditorResult({
    required this.document,
    required this.openNext,
  });

  final ImportedDocument document;
  final bool openNext;
}

enum _EditorStep { crop, adjust }

class ImageNormalizationEditorScreen extends StatefulWidget {
  const ImageNormalizationEditorScreen({
    super.key,
    required this.page,
    required this.engine,
    required this.repository,
    this.inspector = const ImageInspector(),
  });

  final SourcePage page;
  final ImageNormalizationEngine engine;
  final ImageNormalizationRepository repository;
  final ImageInspector inspector;

  @override
  State<ImageNormalizationEditorScreen> createState() =>
      _ImageNormalizationEditorScreenState();
}

class _ImageNormalizationEditorScreenState
    extends State<ImageNormalizationEditorScreen> {
  _EditorStep _step = _EditorStep.crop;
  NormalizationParameters? _parameters;
  NormalizationParameters? _initial;
  Uint8List? _preview;
  bool _loading = true;
  bool _busy = false;
  bool _autoDetectionFailed = false;
  int? _draggingIndex;
  Timer? _previewDebounce;

  bool get _dirty =>
      _parameters != null && _initial != null && _parameters != _initial;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  @override
  void dispose() {
    _previewDebounce?.cancel();
    super.dispose();
  }

  Future<void> _initialize() async {
    final saved = widget.page.normalizedAsset?.parameters;
    CropQuadrilateral corners;
    if (saved != null) {
      _parameters = saved;
      _initial = saved;
    } else if (widget.page.source == DocumentPageSource.pdf) {
      corners = const CropQuadrilateral.fullImage();
      _parameters = NormalizationParameters(corners: corners);
      _initial = _parameters;
    } else {
      final detected = await widget.engine.detectCorners(
        widget.page.absolutePath,
      );
      corners = detected ?? const CropQuadrilateral.fullImage();
      _autoDetectionFailed = detected == null;
      _parameters = NormalizationParameters(corners: corners);
      _initial = _parameters;
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<bool> _confirmDiscard() async {
    if (!_dirty) return true;
    return (await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Bỏ thay đổi?'),
            content: const Text(
              'Các điều chỉnh chưa lưu sẽ bị xóa. Ảnh gốc không bị thay đổi.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Tiếp tục chỉnh sửa'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Bỏ thay đổi'),
              ),
            ],
          ),
        )) ??
        false;
  }

  Future<void> _reset() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Đặt lại chỉnh sửa?'),
        content: const Text(
          'Vùng cắt, góc xoay và độ tương phản sẽ được đặt lại.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Không'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Đặt lại'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      setState(() {
        _parameters = _initial;
        _preview = null;
        _step = _EditorStep.crop;
      });
    }
  }

  Future<void> _continueToAdjust() async {
    final parameters = _parameters;
    if (parameters == null || !parameters.corners.isValid) {
      await _showError(
        'Vùng cắt không hợp lệ. Vui lòng điều chỉnh lại bốn góc.',
      );
      return;
    }
    setState(() {
      _step = _EditorStep.adjust;
      _busy = true;
    });
    await _renderPreview();
  }

  void _schedulePreview() {
    _previewDebounce?.cancel();
    _previewDebounce = Timer(const Duration(milliseconds: 180), _renderPreview);
  }

  Future<void> _renderPreview() async {
    final parameters = _parameters;
    if (parameters == null || !parameters.isValid) return;
    if (mounted) setState(() => _busy = true);
    try {
      final result = await widget.engine.renderPreview(
        widget.page.absolutePath,
        parameters,
      );
      if (mounted) setState(() => _preview = result.bytes);
    } on NormalizationFailure catch (error) {
      if (mounted) await _showError(error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _apply() async {
    final parameters = _parameters;
    if (parameters == null || !parameters.isValid) {
      await _showError(
        'Vùng cắt không hợp lệ. Vui lòng điều chỉnh lại bốn góc.',
      );
      return;
    }
    if (_preview == null) await _renderPreview();
    if (!mounted || _preview == null) return;
    try {
      final inspection = await widget.inspector.inspect(_preview!);
      if (!mounted) return;
      if (inspection.hasQualityWarning) {
        final use = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Ảnh có thể khó nhận dạng'),
            content: const Text(
              'Ảnh có thể khó nhận dạng văn bản. Bạn có muốn tiếp tục?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Chỉnh sửa lại'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Vẫn sử dụng'),
              ),
            ],
          ),
        );
        if (use != true) return;
      }
      setState(() => _busy = true);
      await widget.repository.ensureCapacityFor(widget.page);
      final rendered = await widget.engine.renderFullResolution(
        widget.page.absolutePath,
        parameters,
      );
      final document = await widget.repository.saveNormalizedPage(
        page: widget.page,
        parameters: parameters,
        image: rendered,
      );
      if (!mounted) return;
      final hasNext = await widget.repository.getNextPendingPage(
        document.documentId,
      );
      if (!mounted) return;
      setState(() => _busy = false);
      final openNext = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: const Text('Đã lưu ảnh chuẩn hóa'),
          content: Text(
            hasNext == null
                ? 'Tất cả trang đã sẵn sàng cho bước tiếp theo.'
                : 'Bạn có muốn chỉnh sửa trang chưa xử lý tiếp theo?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Về tài liệu'),
            ),
            if (hasNext != null)
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Chỉnh trang tiếp theo'),
              ),
          ],
        ),
      );
      if (mounted) {
        Navigator.pop(
          context,
          NormalizationEditorResult(
            document: document,
            openNext: openNext == true,
          ),
        );
      }
    } on NormalizationFailure catch (error) {
      if (mounted) await _showError(error.message);
    } catch (_) {
      if (mounted) {
        await _showError('Không thể lưu ảnh đã chỉnh sửa. Vui lòng thử lại.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _showError(String message) => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Không thể chuẩn hóa ảnh'),
      content: Text(message),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Đóng'),
        ),
      ],
    ),
  );

  void _rotate(int delta) {
    final value = _parameters!;
    setState(() {
      _parameters = value.copyWith(
        rotationDegrees: (value.rotationDegrees + delta + 360) % 360,
      );
    });
    _schedulePreview();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_dirty && !_busy,
    onPopInvokedWithResult: (didPop, result) async {
      if (didPop || _busy) return;
      if (await _confirmDiscard() && context.mounted) Navigator.pop(context);
    },
    child: Scaffold(
      appBar: AppBar(
        title: Text('Trang ${widget.page.pageNumber}'),
        actions: [
          TextButton(
            onPressed: _busy ? null : _reset,
            child: const Text('Đặt lại'),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                if (_autoDetectionFailed && _step == _EditorStep.crop)
                  MaterialBanner(
                    content: const Text(
                      'Không thể tự động nhận diện tài liệu. Vui lòng điều chỉnh vùng cắt thủ công.',
                    ),
                    leading: const Icon(Icons.info_outline),
                    actions: [
                      TextButton(
                        onPressed: () =>
                            setState(() => _autoDetectionFailed = false),
                        child: const Text('Đã hiểu'),
                      ),
                    ],
                  ),
                Expanded(
                  child: _step == _EditorStep.crop
                      ? _buildCropEditor()
                      : _buildAdjustmentEditor(),
                ),
                _buildBottomBar(),
              ],
            ),
    ),
  );

  Widget _buildCropEditor() {
    final parameters = _parameters!;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Vùng tài liệu', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            'Kéo bốn điểm đến đúng các góc của tài liệu.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          Expanded(
            child: _CornerEditor(
              imagePath: widget.page.absolutePath,
              imageWidth: widget.page.width,
              imageHeight: widget.page.height,
              corners: parameters.corners,
              draggingIndex: _draggingIndex,
              onDragStart: (index) => setState(() => _draggingIndex = index),
              onDragEnd: () => setState(() => _draggingIndex = null),
              onChanged: (corners) => setState(
                () => _parameters = parameters.copyWith(corners: corners),
              ),
            ),
          ),
          if (!parameters.corners.isValid)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Vùng cắt không hợp lệ. Vui lòng điều chỉnh lại bốn góc.',
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: MemoPalette.of(context).error),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildAdjustmentEditor() {
    final parameters = _parameters!;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        AspectRatio(
          aspectRatio: 0.78,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.black,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (_preview != null)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(18),
                    child: Image.memory(_preview!, fit: BoxFit.contain),
                  ),
                if (_busy) const Center(child: CircularProgressIndicator()),
              ],
            ),
          ),
        ),
        const SizedBox(height: 18),
        Text('Xoay ảnh', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _busy ? null : () => _rotate(-90),
                icon: const Icon(Icons.rotate_left),
                label: const Text('Xoay trái'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _busy ? null : () => _rotate(90),
                icon: const Icon(Icons.rotate_right),
                label: const Text('Xoay phải'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        Row(
          children: [
            Expanded(
              child: Text(
                'Độ tương phản',
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
            Text('${(parameters.contrast * 100).round()}'),
          ],
        ),
        Slider(
          key: const Key('contrast-slider'),
          value: parameters.contrast,
          min: -0.5,
          max: 0.5,
          divisions: 20,
          label: '${(parameters.contrast * 100).round()}',
          onChanged: _busy
              ? null
              : (value) {
                  setState(
                    () => _parameters = parameters.copyWith(contrast: value),
                  );
                  _schedulePreview();
                },
        ),
      ],
    );
  }

  Widget _buildBottomBar() => SafeArea(
    top: false,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
      child: Row(
        children: [
          if (_step == _EditorStep.adjust) ...[
            Expanded(
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(minimumSize: const Size(0, 52)),
                onPressed: _busy
                    ? null
                    : () => setState(() => _step = _EditorStep.crop),
                child: const Text('Chỉnh lại vùng'),
              ),
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: FilledButton(
              key: Key(_step == _EditorStep.crop ? 'confirm-crop' : 'apply'),
              onPressed: _busy
                  ? null
                  : _step == _EditorStep.crop
                  ? _continueToAdjust
                  : _apply,
              child: Text(
                _step == _EditorStep.crop ? 'Xác nhận vùng' : 'Áp dụng',
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _CornerEditor extends StatelessWidget {
  const _CornerEditor({
    required this.imagePath,
    required this.imageWidth,
    required this.imageHeight,
    required this.corners,
    required this.draggingIndex,
    required this.onChanged,
    required this.onDragStart,
    required this.onDragEnd,
  });

  final String imagePath;
  final int imageWidth;
  final int imageHeight;
  final CropQuadrilateral corners;
  final int? draggingIndex;
  final ValueChanged<CropQuadrilateral> onChanged;
  final ValueChanged<int> onDragStart;
  final VoidCallback onDragEnd;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final source = Size(imageWidth.toDouble(), imageHeight.toDouble());
      final fitted = applyBoxFit(BoxFit.contain, source, constraints.biggest);
      final rect = Alignment.center.inscribe(
        fitted.destination,
        Offset.zero & constraints.biggest,
      );
      Offset position(NormalizedPoint point) => Offset(
        rect.left + point.x * rect.width,
        rect.top + point.y * rect.height,
      );
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanStart: (details) {
          var closest = 0;
          var distance = double.infinity;
          for (var index = 0; index < corners.points.length; index++) {
            final value =
                (position(corners.points[index]) - details.localPosition)
                    .distanceSquared;
            if (value < distance) {
              distance = value;
              closest = index;
            }
          }
          onDragStart(closest);
        },
        onPanUpdate: (details) {
          final index = draggingIndex;
          if (index == null) return;
          final point = NormalizedPoint(
            (details.localPosition.dx - rect.left) / rect.width,
            (details.localPosition.dy - rect.top) / rect.height,
          ).clamped();
          onChanged(corners.replacePoint(index, point));
        },
        onPanEnd: (_) => onDragEnd(),
        onPanCancel: onDragEnd,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Positioned.fromRect(
              rect: rect,
              child: StoredImage(path: imagePath),
            ),
            CustomPaint(
              painter: _CropOverlayPainter(
                rect: rect,
                corners: corners,
                valid: corners.isValid,
              ),
            ),
            if (draggingIndex != null)
              Positioned(
                left: (position(corners.points[draggingIndex!]).dx - 42).clamp(
                  0.0,
                  math.max(0.0, constraints.maxWidth - 84),
                ),
                top: (position(corners.points[draggingIndex!]).dy - 104).clamp(
                  0.0,
                  math.max(0.0, constraints.maxHeight - 84),
                ),
                child: IgnorePointer(
                  child: Container(
                    width: 84,
                    height: 84,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.black,
                      border: Border.all(color: Colors.white, width: 3),
                      boxShadow: const [BoxShadow(blurRadius: 8)],
                    ),
                    child: ClipOval(
                      child: Transform.scale(
                        scale: 2.2,
                        alignment: Alignment(
                          corners.points[draggingIndex!].x * 2 - 1,
                          corners.points[draggingIndex!].y * 2 - 1,
                        ),
                        child: StoredImage(path: imagePath),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
    },
  );
}

class _CropOverlayPainter extends CustomPainter {
  const _CropOverlayPainter({
    required this.rect,
    required this.corners,
    required this.valid,
  });

  final Rect rect;
  final CropQuadrilateral corners;
  final bool valid;

  Offset _position(NormalizedPoint point) => Offset(
    rect.left + point.x * rect.width,
    rect.top + point.y * rect.height,
  );

  @override
  void paint(Canvas canvas, Size size) {
    final points = corners.points.map(_position).toList();
    final path = Path()..addPolygon(points, true);
    final outside = Path()..addRect(Offset.zero & size);
    canvas.drawPath(
      Path.combine(PathOperation.difference, outside, path),
      Paint()..color = Colors.black54,
    );
    final color = valid ? const Color(0xFF5EEAD4) : const Color(0xFFFCA5A5);
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
    for (final point in points) {
      canvas.drawCircle(point, 13, Paint()..color = Colors.black54);
      canvas.drawCircle(point, 9, Paint()..color = color);
      canvas.drawCircle(
        point,
        9,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _CropOverlayPainter oldDelegate) =>
      oldDelegate.rect != rect ||
      oldDelegate.corners != corners ||
      oldDelegate.valid != valid;
}

class _OcrPlaceholderScreen extends StatelessWidget {
  const _OcrPlaceholderScreen();

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Nhận dạng văn bản')),
    body: Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.text_snippet_outlined,
              size: 48,
              color: MemoPalette.of(context).primary,
            ),
            const SizedBox(height: 16),
            Text(
              'Tài liệu đã sẵn sàng. FR04 OCR chưa được triển khai.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ],
        ),
      ),
    ),
  );
}

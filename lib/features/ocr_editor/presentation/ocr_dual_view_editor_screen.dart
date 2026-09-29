import 'package:flutter/material.dart';

import '../../../shared/theme/memo_theme.dart';
import '../../document_import/domain/document_import_models.dart';
import '../../document_import/presentation/stored_image.dart';
import '../application/image_region_cropper.dart';
import '../data/gemini_vision_enhancer.dart';
import '../data/local_ocr_repository.dart';
import '../domain/gemini_enhancer.dart';
import '../domain/ocr_models.dart';
import '../domain/ocr_repository.dart';
import 'widgets/bounding_box_painter.dart';
import 'widgets/gemini_assist_dialogs.dart';
import '../../material_generation/presentation/material_generation_flow.dart';

enum _BlockFilter { all, needsReview, edited }

class OcrDualViewEditorScreen extends StatefulWidget {
  const OcrDualViewEditorScreen({
    super.key,
    required this.document,
    this.ocrRepository,
    this.geminiEnhancer,
    this.cropper = const ImageRegionCropper(),
  });

  final ImportedDocument document;
  final OcrRepository? ocrRepository;
  final GeminiEnhancer? geminiEnhancer;
  final ImageRegionCropper cropper;

  @override
  State<OcrDualViewEditorScreen> createState() =>
      _OcrDualViewEditorScreenState();
}

class _OcrDualViewEditorScreenState extends State<OcrDualViewEditorScreen> {
  late final OcrRepository _repository;
  late final GeminiEnhancer _gemini;

  bool _loading = true;
  String? _errorMessage;
  OcrDocumentReview? _review;

  int _currentPageIndex = 0;
  String? _selectedBlockId;
  _BlockFilter _filter = _BlockFilter.all;

  final TransformationController _transformController =
      TransformationController();
  final Map<String, GlobalKey> _blockKeys = {};

  SourcePage get _currentPage => widget.document.pages[_currentPageIndex];

  OcrPageReview? get _currentPageReview {
    if (_review == null) return null;
    final pageId = _currentPage.pageId;
    return _review!.pageReviews.firstWhere(
      (p) => p.pageId == pageId,
      orElse: () => OcrPageReview(
        pageId: pageId,
        documentId: widget.document.documentId,
        pageNumber: _currentPage.pageNumber,
        status: OcrPageStatus.notStarted,
        blocks: const [],
        updatedAt: DateTime.now(),
      ),
    );
  }

  List<SourceBlock> get _filteredBlocks {
    final review = _currentPageReview;
    if (review == null) return const [];
    final active = review.blocks.where((b) => !b.isDeleted).toList();

    return switch (_filter) {
      _BlockFilter.all => active,
      _BlockFilter.needsReview => active.where((b) => b.needsReview).toList(),
      _BlockFilter.edited => active.where((b) => b.isEdited).toList(),
    };
  }

  @override
  void initState() {
    super.initState();
    _repository = widget.ocrRepository ?? LocalOcrRepository();
    _gemini = widget.geminiEnhancer ?? GeminiVisionEnhancer();
    _loadData();
  }

  @override
  void dispose() {
    _transformController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    try {
      final review = await _repository.getOcrReview(widget.document.documentId);
      if (!mounted) return;
      setState(() {
        _review = review;
        _loading = false;
        // Select first block if available
        final blocks = _currentPageReview?.blocks;
        if (blocks != null && blocks.isNotEmpty) {
          _selectedBlockId = blocks.first.blockId;
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.toString();
        _loading = false;
      });
    }
  }

  void _selectBlock(String blockId, {bool focusImage = true}) {
    setState(() => _selectedBlockId = blockId);

    // Scroll block card into view
    final key = _blockKeys[blockId];
    if (key?.currentContext != null) {
      Scrollable.ensureVisible(
        key!.currentContext!,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
        alignment: 0.3,
      );
    }

    if (focusImage) {
      _focusBoundingBox(blockId);
    }
  }

  void _focusBoundingBox(String blockId) {
    final review = _currentPageReview;
    if (review == null) return;
    final block = review.blocks.firstWhere((b) => b.blockId == blockId);
    if (block.boundingBox == null || !block.hasValidBox) return;

    final box = block.boundingBox!;
    final centerX = box.left + box.width / 2;
    final centerY = box.top + box.height / 2;

    // Reset or zoom smoothly towards center of bounding box
    final zoom = 1.8;
    final matrix = Matrix4.diagonal3Values(zoom, zoom, 1.0)
      ..setTranslationRaw(
        -centerX * 300 * (zoom - 1),
        -centerY * 400 * (zoom - 1),
        0.0,
      );

    _transformController.value = matrix;
  }

  void _onImageTap(TapUpDetails details, Size canvasSize) {
    if (canvasSize.width <= 0 || canvasSize.height <= 0) return;

    final normX = details.localPosition.dx / canvasSize.width;
    final normY = details.localPosition.dy / canvasSize.height;

    final review = _currentPageReview;
    if (review == null) return;

    // Find block containing tap point
    for (final block in review.blocks) {
      if (block.isDeleted || block.boundingBox == null || !block.hasValidBox) {
        continue;
      }
      final box = block.boundingBox!;
      if (normX >= box.left &&
          normX <= box.left + box.width &&
          normY >= box.top &&
          normY <= box.top + box.height) {
        _selectBlock(block.blockId, focusImage: false);
        return;
      }
    }
  }

  Future<void> _updateBlockText(SourceBlock block, String newText) async {
    final updated = block.copyWith(
      normalizedText: newText,
      status:
          block.status == BlockStatus.needsReview && newText.trim().isNotEmpty
          ? BlockStatus.draft
          : block.status,
    );
    await _repository.updateSourceBlock(updated);
    _reloadSilently();
  }

  Future<void> _restoreBlock(SourceBlock block) async {
    await _repository.restoreSourceBlock(block.blockId);
    _reloadSilently();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Đã khôi phục văn bản nhận dạng ban đầu.'),
        ),
      );
    }
  }

  Future<void> _markBlockVerified(SourceBlock block) async {
    final updated = block.copyWith(status: BlockStatus.verified);
    await _repository.updateSourceBlock(updated);
    _reloadSilently();
  }

  Future<void> _deleteBlock(SourceBlock block) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Xóa đoạn văn bản?'),
        content: const Text(
          'Đoạn văn bản này sẽ bị loại bỏ và không được gửi sang AI để sinh học liệu.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Xóa'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _repository.deleteSourceBlock(block.blockId);
      _reloadSilently();
    }
  }

  Future<void> _enhanceWithGemini(SourceBlock block) async {
    if (block.boundingBox == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Đoạn này không có tọa độ vùng ảnh để gửi AI.'),
        ),
      );
      return;
    }

    final consent = await showDialog<bool>(
      context: context,
      builder: (_) => const GeminiConsentDialog(),
    );

    if (consent != true) return;

    if (!mounted) return;

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: Card(
          child: Padding(
            padding: EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Gemini đang trích xuất văn bản…'),
              ],
            ),
          ),
        ),
      ),
    );

    try {
      final cropBytes = await widget.cropper.cropRegion(
        imagePath: _currentPage.displayPath,
        box: block.boundingBox!,
      );

      if (cropBytes == null) {
        throw const OcrFailure(
          OcrFailureCode.pageImageNotFound,
          'Không thể cắt vùng ảnh.',
        );
      }

      final suggested = await _gemini.enhanceCropText(
        imageBytes: cropBytes,
        currentText: block.normalizedText,
      );

      if (!mounted) return;
      Navigator.pop(context); // Dismiss loading dialog

      final accept = await showDialog<bool>(
        context: context,
        builder: (_) => GeminiSuggestionDialog(
          currentText: block.normalizedText,
          suggestedText: suggested,
        ),
      );

      if (accept == true) {
        final updated = block.copyWith(
          normalizedText: suggested,
          confidence: null,
          confidenceSource: ConfidenceSource.gemini,
          status: BlockStatus.draft,
        );
        await _repository.updateSourceBlock(updated);
        _reloadSilently();
      }
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context); // Dismiss loading dialog
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  Future<void> _addNewBlock() async {
    final textController = TextEditingController();
    final added = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Thêm đoạn văn bản'),
        content: TextField(
          controller: textController,
          maxLines: 4,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Nhập nội dung văn bản bị bỏ sót…',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Thêm'),
          ),
        ],
      ),
    );

    if (added == true && textController.text.trim().isNotEmpty) {
      final newBlock = SourceBlock(
        blockId: '',
        documentId: widget.document.documentId,
        pageId: _currentPage.pageId,
        pageNumber: _currentPage.pageNumber,
        orderIndex: _currentPageReview?.blocks.length ?? 0,
        rawText: textController.text.trim(),
        normalizedText: textController.text.trim(),
        boundingBox: null, // Toàn trang / không vị trí
        hasValidBox: false,
        confidence: null,
        confidenceSource: ConfidenceSource.user,
        status: BlockStatus.userAdded,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      await _repository.addSourceBlock(newBlock);
      _reloadSilently();
    }
  }

  Future<void> _saveDraftAndExit() async {
    await _repository.saveDraft(widget.document.documentId);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Đã lưu bản nháp hiệu chỉnh.')),
    );
    Navigator.of(context).pop();
  }

  Future<void> _confirmOcr() async {
    final review = _review;
    if (review == null) return;

    // Luồng 12a: Kiểm tra block rỗng
    for (final page in review.pageReviews) {
      for (final block in page.blocks) {
        if (!block.isDeleted && block.normalizedText.trim().isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Trang ${block.pageNumber}: Đoạn #${block.orderIndex + 1} có nội dung rỗng. Vui lòng nhập nội dung hoặc xóa đoạn.',
              ),
            ),
          );
          _selectBlock(block.blockId);
          return;
        }
      }
    }

    // Luồng 14a: Cảnh báo còn block chưa kiểm tra
    if (review.hasUnreviewedBlocks) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Còn đoạn cần kiểm tra'),
          content: Text(
            'Hiện còn ${review.needsReviewCount} đoạn có độ tin cậy thấp hoặc chưa được kiểm tra. Bạn có chắc chắn muốn xác nhận không?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Quay lại kiểm tra'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Vẫn xác nhận'),
            ),
          ],
        ),
      );
      if (proceed != true) return;
    }

    if (!mounted) return;

    // Luồng 15: Xác nhận văn bản đưa vào AI
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Xác nhận hoàn tất OCR?'),
        content: const Text(
          'Văn bản đã hiệu chỉnh sẽ được lưu và sẵn sàng gửi sang AI để sinh flashcard và câu hỏi trắc nghiệm.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            key: const Key('final-ocr-confirm-btn'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Đồng ý xác nhận'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    await _repository.confirmOcrReview(widget.document.documentId);

    if (!mounted) return;

    final shouldStartAi = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('OCR đã được xác nhận!'),
        content: const Text(
          'Tài liệu đã ở trạng thái "Sẵn sàng tạo học liệu". Bạn có muốn tạo flashcard và câu hỏi ngay không?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Để sau'),
          ),
          FilledButton.icon(
            icon: const Icon(Icons.auto_awesome),
            label: const Text('Tạo học liệu AI'),
            onPressed: () => Navigator.pop(dialogContext, true),
          ),
        ],
      ),
    );

    if (shouldStartAi == true && mounted) {
      await MaterialGenerationFlow.start(
        context: context,
        document: widget.document,
        ocrRepository: _repository,
      );
    } else if (mounted) {
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  Future<void> _reloadSilently() async {
    try {
      final review = await _repository.getOcrReview(widget.document.documentId);
      if (mounted) setState(() => _review = review);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final palette = MemoPalette.of(context);

    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Hiệu chỉnh OCR')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_errorMessage != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Hiệu chỉnh OCR')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.error_outline, size: 48, color: palette.error),
                const SizedBox(height: 16),
                Text(_errorMessage!, textAlign: TextAlign.center),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _loadData,
                  child: const Text('Tải lại'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final pages = widget.document.pages;
    final filteredBlocks = _filteredBlocks;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.document.title, style: const TextStyle(fontSize: 15)),
            Text(
              'Trang ${_currentPageIndex + 1}/${pages.length} · ${_review?.totalBlocksCount ?? 0} đoạn',
              style: TextStyle(fontSize: 12, color: palette.outline),
            ),
          ],
        ),
        actions: [
          if (_review?.isReadyForGeneration == true)
            IconButton(
              tooltip: 'Tạo học liệu',
              icon: const Icon(Icons.auto_awesome),
              onPressed: () => MaterialGenerationFlow.start(
                context: context,
                document: widget.document,
                ocrRepository: _repository,
              ),
            ),
          IconButton(
            tooltip: 'Lưu bản nháp',
            icon: const Icon(Icons.save_outlined),
            onPressed: _saveDraftAndExit,
          ),
          IconButton(
            tooltip: 'Thêm đoạn văn bản',
            icon: const Icon(Icons.add_box_outlined),
            onPressed: _addNewBlock,
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth >= 720;

          if (isWide) {
            return Row(
              children: [
                Expanded(flex: 5, child: _buildImageSection(palette)),
                const VerticalDivider(width: 1),
                Expanded(
                  flex: 5,
                  child: _buildEditorSection(palette, filteredBlocks),
                ),
              ],
            );
          } else {
            return Column(
              children: [
                Expanded(flex: 4, child: _buildImageSection(palette)),
                const Divider(height: 1),
                Expanded(
                  flex: 6,
                  child: _buildEditorSection(palette, filteredBlocks),
                ),
              ],
            );
          }
        },
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: palette.surface,
            border: Border(
              top: BorderSide(color: palette.outline.withValues(alpha: 0.2)),
            ),
          ),
          child: Row(
            children: [
              // Page navigation
              if (pages.length > 1) ...[
                IconButton(
                  icon: const Icon(Icons.chevron_left_rounded),
                  onPressed: _currentPageIndex > 0
                      ? () => setState(() => _currentPageIndex--)
                      : null,
                ),
                Text(
                  '${_currentPageIndex + 1}/${pages.length}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right_rounded),
                  onPressed: _currentPageIndex < pages.length - 1
                      ? () => setState(() => _currentPageIndex++)
                      : null,
                ),
                const Spacer(),
              ] else
                const Spacer(),

              OutlinedButton(
                onPressed: _saveDraftAndExit,
                child: const Text('Lưu nháp'),
              ),
              const SizedBox(width: 10),
              FilledButton.icon(
                key: const Key('confirm-ocr-btn'),
                icon: const Icon(Icons.check_circle_outline_rounded),
                label: const Text('Xác nhận OCR'),
                onPressed: _confirmOcr,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildImageSection(MemoPalette palette) {
    final blocks = _currentPageReview?.blocks ?? const [];

    return Container(
      color: Colors.black.withValues(alpha: 0.04),
      child: Stack(
        fit: StackFit.expand,
        children: [
          InteractiveViewer(
            transformationController: _transformController,
            minScale: 0.8,
            maxScale: 4.0,
            child: Center(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return GestureDetector(
                    onTapUp: (details) => _onImageTap(
                      details,
                      Size(constraints.maxWidth, constraints.maxHeight),
                    ),
                    child: CustomPaint(
                      foregroundPainter: BoundingBoxPainter(
                        blocks: blocks,
                        selectedBlockId: _selectedBlockId,
                        primaryColor: palette.primary,
                        warningColor: palette.warning,
                        tealColor: Colors.teal,
                      ),
                      child: StoredImage(
                        path: _currentPage.displayPath,
                        fit: BoxFit.contain,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          Positioned(
            right: 8,
            bottom: 8,
            child: FloatingActionButton.small(
              heroTag: 'reset-zoom-btn',
              tooltip: 'Đặt lại góc nhìn',
              backgroundColor: palette.surface,
              onPressed: () => _transformController.value = Matrix4.identity(),
              child: Icon(
                Icons.center_focus_strong,
                color: palette.primary,
                size: 20,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEditorSection(MemoPalette palette, List<SourceBlock> blocks) {
    return Column(
      children: [
        // Filter tabs
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          color: palette.surface,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildFilterChip('Tất cả', _BlockFilter.all, palette),
                const SizedBox(width: 8),
                _buildFilterChip(
                  'Cần kiểm tra',
                  _BlockFilter.needsReview,
                  palette,
                ),
                const SizedBox(width: 8),
                _buildFilterChip('Đã sửa', _BlockFilter.edited, palette),
              ],
            ),
          ),
        ),
        const Divider(height: 1),

        // Block list
        Expanded(
          child: blocks.isEmpty
              ? Center(
                  child: Text(
                    _filter == _BlockFilter.needsReview
                        ? 'Không còn đoạn nào cần kiểm tra trên trang này! 🎉'
                        : 'Không có đoạn văn bản nào.',
                    style: TextStyle(color: palette.outline),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 80),
                  itemCount: blocks.length,
                  itemBuilder: (context, index) {
                    final block = blocks[index];
                    final isSelected = block.blockId == _selectedBlockId;

                    return _BlockCard(
                      key: _blockKeys.putIfAbsent(
                        block.blockId,
                        () => GlobalKey(),
                      ),
                      block: block,
                      isSelected: isSelected,
                      palette: palette,
                      onTap: () => _selectBlock(block.blockId),
                      onTextChange: (newText) =>
                          _updateBlockText(block, newText),
                      onRestore: () => _restoreBlock(block),
                      onVerify: () => _markBlockVerified(block),
                      onDelete: () => _deleteBlock(block),
                      onGeminiEnhance: () => _enhanceWithGemini(block),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildFilterChip(
    String label,
    _BlockFilter filter,
    MemoPalette palette,
  ) {
    final isSelected = _filter == filter;
    final review = _currentPageReview;
    int count = 0;
    if (review != null) {
      final active = review.blocks.where((b) => !b.isDeleted);
      count = switch (filter) {
        _BlockFilter.all => active.length,
        _BlockFilter.needsReview => active.where((b) => b.needsReview).length,
        _BlockFilter.edited => active.where((b) => b.isEdited).length,
      };
    }

    return FilterChip(
      selected: isSelected,
      label: Text('$label ($count)'),
      onSelected: (_) => setState(() => _filter = filter),
    );
  }
}

class _BlockCard extends StatefulWidget {
  const _BlockCard({
    super.key,
    required this.block,
    required this.isSelected,
    required this.palette,
    required this.onTap,
    required this.onTextChange,
    required this.onRestore,
    required this.onVerify,
    required this.onDelete,
    required this.onGeminiEnhance,
  });

  final SourceBlock block;
  final bool isSelected;
  final MemoPalette palette;
  final VoidCallback onTap;
  final ValueChanged<String> onTextChange;
  final VoidCallback onRestore;
  final VoidCallback onVerify;
  final VoidCallback onDelete;
  final VoidCallback onGeminiEnhance;

  @override
  State<_BlockCard> createState() => _BlockCardState();
}

class _BlockCardState extends State<_BlockCard> {
  late final TextEditingController _controller;
  bool _showRawText = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.block.normalizedText);
  }

  @override
  void didUpdateWidget(covariant _BlockCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.block.normalizedText != widget.block.normalizedText &&
        _controller.text != widget.block.normalizedText) {
      _controller.text = widget.block.normalizedText;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final block = widget.block;
    final palette = widget.palette;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: widget.isSelected ? 3 : 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: widget.isSelected
              ? palette.primary
              : (block.needsReview
                    ? palette.warning
                    : palette.outline.withValues(alpha: 0.2)),
          width: widget.isSelected ? 2 : 1,
        ),
      ),
      child: InkWell(
        onTap: widget.onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header line: Order badge, Confidence, Status chips
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: widget.isSelected ? palette.primary : palette.hero,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '#${block.orderIndex + 1}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: widget.isSelected
                            ? Colors.white
                            : palette.primary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),

                  // Confidence badge (BR04-04, BR05-07)
                  if (block.confidence != null) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: palette.secondaryContainer,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '${(block.confidence! * 100).round()}% ML Kit',
                        style: TextStyle(fontSize: 11, color: palette.primary),
                      ),
                    ),
                  ] else ...[
                    Text(
                      block.isUserAdded
                          ? 'Người dùng nhập'
                          : 'AI / Không có confidence',
                      style: TextStyle(fontSize: 11, color: palette.outline),
                    ),
                  ],

                  const Spacer(),

                  if (block.needsReview)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: palette.warning.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.warning_amber_rounded,
                            size: 14,
                            color: palette.warning,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Cần kiểm tra',
                            style: TextStyle(
                              fontSize: 11,
                              color: palette.warning,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),

                  if (block.isEdited) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: palette.hero,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text(
                        'Đã sửa',
                        style: TextStyle(fontSize: 11),
                      ),
                    ),
                  ],
                ],
              ),

              const SizedBox(height: 10),

              // Editable Text Field
              TextField(
                controller: _controller,
                maxLines: null,
                style: const TextStyle(fontSize: 14, height: 1.4),
                decoration: const InputDecoration(
                  isDense: true,
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.zero,
                  hintText: 'Nhập nội dung văn bản…',
                ),
                onChanged: widget.onTextChange,
              ),

              // Raw text comparison accordion
              if (block.isEdited) ...[
                const SizedBox(height: 8),
                InkWell(
                  onTap: () => setState(() => _showRawText = !_showRawText),
                  child: Row(
                    children: [
                      Icon(
                        _showRawText
                            ? Icons.arrow_drop_down
                            : Icons.arrow_right,
                        size: 18,
                        color: palette.outline,
                      ),
                      Text(
                        'Xem bản gốc OCR',
                        style: TextStyle(fontSize: 12, color: palette.outline),
                      ),
                    ],
                  ),
                ),
                if (_showRawText)
                  Container(
                    margin: const EdgeInsets.only(top: 6),
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: palette.hero,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      block.rawText,
                      style: TextStyle(fontSize: 12, color: palette.outline),
                    ),
                  ),
              ],

              const SizedBox(height: 10),

              // Action buttons toolbar
              SizedBox(
                width: double.infinity,
                child: Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 4,
                  runSpacing: 4,
                  children: [
                    Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (block.isEdited)
                          TextButton.icon(
                            style: TextButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                              ),
                            ),
                            icon: const Icon(Icons.undo_rounded, size: 16),
                            label: const Text(
                              'Khôi phục gốc',
                              style: TextStyle(fontSize: 12),
                            ),
                            onPressed: widget.onRestore,
                          ),
                        if (block.hasValidBox && block.boundingBox != null)
                          TextButton.icon(
                            style: TextButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                              ),
                            ),
                            icon: Icon(
                              Icons.auto_awesome,
                              size: 16,
                              color: palette.primary,
                            ),
                            label: Text(
                              'Cải thiện bằng AI',
                              style: TextStyle(
                                fontSize: 12,
                                color: palette.primary,
                              ),
                            ),
                            onPressed: widget.onGeminiEnhance,
                          ),
                      ],
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: 'Xóa đoạn này',
                          icon: Icon(
                            Icons.delete_outline_rounded,
                            size: 18,
                            color: palette.error,
                          ),
                          onPressed: widget.onDelete,
                        ),
                        IconButton(
                          tooltip: 'Đánh dấu đã kiểm tra',
                          icon: Icon(
                            block.isVerified
                                ? Icons.check_circle
                                : Icons.check_circle_outline,
                            size: 20,
                            color: block.isVerified
                                ? palette.success
                                : palette.outline,
                          ),
                          onPressed: widget.onVerify,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

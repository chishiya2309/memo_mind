import 'package:flutter/material.dart';

import '../../../shared/theme/memo_theme.dart';
import '../../document_import/domain/document_import_models.dart';
import '../../document_import/presentation/stored_image.dart';
import '../../image_normalization/domain/image_normalization_models.dart';
import '../application/ocr_orchestrator.dart';
import 'ocr_processing_screen.dart';

class OcrPageSelectionScreen extends StatefulWidget {
  const OcrPageSelectionScreen({
    super.key,
    required this.document,
    this.orchestrator,
  });

  final ImportedDocument document;
  final OcrOrchestrator? orchestrator;

  @override
  State<OcrPageSelectionScreen> createState() => _OcrPageSelectionScreenState();
}

class _OcrPageSelectionScreenState extends State<OcrPageSelectionScreen> {
  late final Set<String> _selectedPageIds;

  @override
  void initState() {
    super.initState();
    // Default to all pages selected
    _selectedPageIds = widget.document.pages.map((p) => p.pageId).toSet();
  }

  void _toggleAll() {
    setState(() {
      if (_selectedPageIds.length == widget.document.pages.length) {
        _selectedPageIds.clear();
      } else {
        _selectedPageIds
          ..clear()
          ..addAll(widget.document.pages.map((p) => p.pageId));
      }
    });
  }

  void _togglePage(String pageId) {
    setState(() {
      if (_selectedPageIds.contains(pageId)) {
        _selectedPageIds.remove(pageId);
      } else {
        _selectedPageIds.add(pageId);
      }
    });
  }

  void _startOcr() {
    final selectedPages = widget.document.pages
        .where((p) => _selectedPageIds.contains(p.pageId))
        .toList();

    if (selectedPages.isEmpty) return;

    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => OcrProcessingScreen(
          document: widget.document,
          selectedPages: selectedPages,
          orchestrator: widget.orchestrator,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = MemoPalette.of(context);
    final pages = widget.document.pages;
    final allSelected = _selectedPageIds.length == pages.length;
    final hasUnnormalized = pages.any(
      (p) => p.normalizationStatus == PageNormalizationStatus.pending,
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Chọn trang nhận dạng'),
        actions: [
          TextButton(
            key: const Key('toggle-all-pages-btn'),
            onPressed: _toggleAll,
            child: Text(allSelected ? 'Bỏ chọn hết' : 'Chọn tất cả'),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: CustomScrollView(
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
                sliver: SliverList.list(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: palette.hero,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.document_scanner_rounded,
                            color: palette.primary,
                            size: 32,
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  widget.document.title,
                                  style: Theme.of(context).textTheme.titleSmall,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Đã chọn ${_selectedPageIds.length}/${pages.length} trang',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (hasUnnormalized) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: palette.warning.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.info_outline_rounded,
                              size: 20,
                              color: palette.warning,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'Một số ảnh chưa chuẩn hóa góc/tương phản. Hệ thống sẽ nhận dạng trên ảnh gốc.',
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: palette.warning,
                                    ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final columns = constraints.maxWidth > 500 ? 3 : 2;
                        return GridView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: columns,
                            mainAxisSpacing: 12,
                            crossAxisSpacing: 12,
                            childAspectRatio: 0.72,
                          ),
                          itemCount: pages.length,
                          itemBuilder: (context, index) {
                            final page = pages[index];
                            final isSelected =
                                _selectedPageIds.contains(page.pageId);
                            return _PageSelectionCard(
                              page: page,
                              isSelected: isSelected,
                              onToggle: () => _togglePage(page.pageId),
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
          child: FilledButton.icon(
            key: const Key('start-ocr-button'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            onPressed: _selectedPageIds.isEmpty ? null : _startOcr,
            icon: const Icon(Icons.play_arrow_rounded),
            label: Text(
              'Bắt đầu OCR (${_selectedPageIds.length} trang)',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ),
      ),
    );
  }
}

class _PageSelectionCard extends StatelessWidget {
  const _PageSelectionCard({
    required this.page,
    required this.isSelected,
    required this.onToggle,
  });

  final SourcePage page;
  final bool isSelected;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final palette = MemoPalette.of(context);
    final isNormalized =
        page.normalizationStatus != PageNormalizationStatus.pending;

    return Card(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: isSelected ? palette.primary : Colors.transparent,
          width: 2,
        ),
      ),
      elevation: isSelected ? 3 : 1,
      child: InkWell(
        key: Key('toggle-page-${page.pageId}'),
        onTap: onToggle,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Positioned.fill(
              child: StoredImage(path: page.displayPath),
            ),
            // Gradient overlay
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.4),
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.6),
                    ],
                    stops: const [0.0, 0.4, 1.0],
                  ),
                ),
              ),
            ),
            // Top Selection Checkbox
            Positioned(
              top: 8,
              right: 8,
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isSelected ? palette.primary : Colors.black45,
                ),
                padding: const EdgeInsets.all(4),
                child: Icon(
                  isSelected ? Icons.check : Icons.circle_outlined,
                  size: 18,
                  color: Colors.white,
                ),
              ),
            ),
            // Bottom Info Label
            Positioned(
              left: 8,
              bottom: 8,
              right: 8,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Trang ${page.pageNumber}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    isNormalized ? 'Đã chuẩn hóa' : 'Ảnh gốc',
                    style: TextStyle(
                      color: isNormalized
                          ? Colors.lightGreenAccent
                          : Colors.white70,
                      fontSize: 11,
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
}

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../shared/theme/memo_theme.dart';
import '../application/pdf_import_services.dart';
import '../data/pdf_import_tools.dart';
import '../domain/document_import_models.dart';
import '../domain/document_import_repository.dart';
import 'document_import_flow.dart';
import 'stored_image.dart';

class PdfImportFlow extends StatefulWidget {
  const PdfImportFlow({
    super.key,
    required this.repository,
    this.picker,
    this.processor,
    this.onContinue,
  });

  final PdfImportRepository repository;
  final PdfCandidatePicker? picker;
  final PdfDocumentProcessor? processor;
  final ValueChanged<ImportedDocument>? onContinue;

  @override
  State<PdfImportFlow> createState() => _PdfImportFlowState();
}

enum _PdfImportPhase { picking, selecting, preview, saved }

class _PdfImportFlowState extends State<PdfImportFlow> {
  late final PdfCandidatePicker _picker;
  late final PdfDocumentProcessor _processor;
  final Map<int, Future<Uint8List>> _thumbnails = {};

  PdfCandidate? _candidate;
  PdfInspection? _inspection;
  ImportedDocument? _document;
  Set<int> _selectedPages = {};
  _PdfImportPhase _phase = _PdfImportPhase.picking;
  bool _busy = false;
  String _busyLabel = 'Đang chuẩn bị…';
  bool _committed = false;

  @override
  void initState() {
    super.initState();
    _picker = widget.picker ?? DevicePdfCandidatePicker();
    _processor = widget.processor ?? DevicePdfDocumentProcessor();
    WidgetsBinding.instance.addPostFrameCallback((_) => _pickPdf());
  }

  @override
  void dispose() {
    final candidate = _candidate;
    if (!_committed && candidate != null) {
      unawaited(
        _processor.dispose().then(
          (_) => widget.repository.discardPdfCandidate(candidate),
        ),
      );
    } else {
      unawaited(_processor.dispose());
    }
    super.dispose();
  }

  Future<void> _pickPdf() async {
    _setBusy(true, 'Đang mở trình quản lý tệp…');
    PdfCandidate? candidate;
    try {
      candidate = await _picker.pickPdf();
    } on ImportFailure catch (error) {
      _setBusy(false);
      await _handlePickError(error);
      return;
    } catch (_) {
      _setBusy(false);
      await _handlePickError(
        const ImportFailure(
          ImportFailureCode.pickerUnavailable,
          'Không thể mở trình quản lý tệp. Vui lòng thử lại.',
        ),
      );
      return;
    }
    if (!mounted) return;
    if (candidate == null) {
      _setBusy(false);
      Navigator.of(context).pop();
      return;
    }
    _candidate = candidate;
    await _inspect(candidate);
  }

  Future<void> _inspect(PdfCandidate candidate) async {
    _setBusy(true, 'Đang kiểm tra tệp PDF…');
    try {
      final inspection = await _processor.inspect(candidate);
      if (!mounted) return;
      final isShort = inspection.pageCount <= 10;
      setState(() {
        _inspection = inspection;
        _selectedPages = isShort
            ? {for (var page = 1; page <= inspection.pageCount; page++) page}
            : <int>{};
        _phase = isShort ? _PdfImportPhase.preview : _PdfImportPhase.selecting;
        _busy = false;
      });
      if (!isShort) {
        await _showMessage(
          'Tài liệu có ${inspection.pageCount} trang. '
          'Mỗi lượt chỉ có thể xử lý tối đa 10 trang.',
          title: 'Chọn trang cần xử lý',
        );
      }
    } on ImportFailure catch (error) {
      _setBusy(false);
      await widget.repository.discardPdfCandidate(candidate);
      _candidate = null;
      final retry = await _showRetryError(error.message);
      if (!mounted) return;
      if (retry) {
        await _pickPdf();
      } else {
        Navigator.of(context).pop();
      }
    }
  }

  Future<void> _handlePickError(ImportFailure error) async {
    final retry = await _showRetryError(error.message);
    if (!mounted) return;
    if (retry) {
      await _pickPdf();
    } else {
      Navigator.of(context).pop();
    }
  }

  Future<void> _chooseAnotherFile() async {
    final candidate = _candidate;
    _candidate = null;
    _inspection = null;
    _thumbnails.clear();
    await _processor.dispose();
    if (candidate != null) {
      await widget.repository.discardPdfCandidate(candidate);
    }
    if (!mounted) return;
    setState(() {
      _phase = _PdfImportPhase.picking;
      _selectedPages = {};
    });
    await _pickPdf();
  }

  Future<Uint8List> _thumbnail(int pageNumber) {
    final candidate = _candidate!;
    return _thumbnails.putIfAbsent(
      pageNumber,
      () => _processor.renderThumbnail(candidate, pageNumber),
    );
  }

  void _togglePage(int pageNumber) {
    if (_selectedPages.contains(pageNumber)) {
      setState(() => _selectedPages.remove(pageNumber));
      return;
    }
    if (_selectedPages.length >= 10) {
      _showSelectionMessage(
        'Bạn chỉ có thể chọn tối đa 10 trang cho mỗi lượt xử lý.',
      );
      return;
    }
    setState(() => _selectedPages.add(pageNumber));
  }

  Future<void> _selectRange() async {
    final inspection = _inspection!;
    final range = await showDialog<_PageRange>(
      context: context,
      builder: (_) => _PageRangeDialog(pageCount: inspection.pageCount),
    );
    if (!mounted || range == null) return;
    final pages = {
      for (var page = range.start; page <= range.end; page++) page,
    };
    if (pages.length > 10) {
      _showSelectionMessage(
        'Bạn chỉ có thể chọn tối đa 10 trang cho mỗi lượt xử lý.',
      );
      return;
    }
    setState(() => _selectedPages = pages);
  }

  void _confirmSelection() {
    if (_selectedPages.isEmpty) {
      _showSelectionMessage('Vui lòng chọn ít nhất một trang để tiếp tục.');
      return;
    }
    setState(() => _phase = _PdfImportPhase.preview);
  }

  void _showSelectionMessage(String message) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 84),
      ),
    );
  }

  Future<void> _importPdf() async {
    final candidate = _candidate;
    if (candidate == null || _selectedPages.isEmpty) return;
    _setBusy(true, 'Đang tạo dữ liệu các trang…');
    try {
      final selected = _selectedPages.toList()..sort();
      final rendered = await _processor.renderSelectedPages(
        candidate,
        selected,
      );
      if (!mounted) return;
      _setBusy(true, 'Đang lưu PDF gốc và các trang…');
      final document = await widget.repository.createFromPdf(
        candidate: candidate,
        pages: rendered,
      );
      await _processor.dispose();
      if (!mounted) return;
      setState(() {
        _document = document;
        _phase = _PdfImportPhase.saved;
        _busy = false;
        _committed = true;
      });
    } on ImportFailure catch (error) {
      _setBusy(false);
      final retry = await _showRetryError(error.message, retryLabel: 'Thử lại');
      if (!mounted || retry) {
        if (retry) await _importPdf();
        return;
      }
    } catch (_) {
      _setBusy(false);
      await _showMessage('Không thể lưu tài liệu. Vui lòng thử lại.');
    }
  }

  void _continue() {
    final document = _document;
    if (document == null) return;
    widget.onContinue?.call(document);
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => PendingProcessingScreen(document: document),
      ),
    );
  }

  void _later() => Navigator.of(context).pop();

  Future<bool> _showRetryError(
    String message, {
    String retryLabel = 'Chọn tệp khác',
  }) async =>
      (await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Không thể nhập PDF'),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Hủy'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(retryLabel),
            ),
          ],
        ),
      )) ??
      false;

  Future<void> _showMessage(String message, {String? title}) =>
      showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: title == null ? null : Text(title),
          content: Text(message),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Đã hiểu'),
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

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_busy,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Nhập PDF'),
          actions: [
            if (_candidate != null && _phase != _PdfImportPhase.saved)
              TextButton(
                onPressed: _busy ? null : _chooseAnotherFile,
                child: const Text('Chọn tệp khác'),
              ),
          ],
        ),
        body: Stack(
          children: [
            Positioned.fill(child: _buildBody()),
            if (_busy) _BusyOverlay(label: _busyLabel),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() => switch (_phase) {
    _PdfImportPhase.picking => const Center(
      child: Text('Đang chờ chọn một tệp PDF…'),
    ),
    _PdfImportPhase.selecting => _PageSelectionView(
      inspection: _inspection!,
      selectedPages: _selectedPages,
      thumbnail: _thumbnail,
      onToggle: _togglePage,
      onSelectRange: _selectRange,
      onConfirm: _confirmSelection,
    ),
    _PdfImportPhase.preview => _PdfPreviewView(
      candidate: _candidate!,
      inspection: _inspection!,
      selectedPages: _selectedPages.toList()..sort(),
      thumbnail: _thumbnail,
      onReselect: () => setState(() => _phase = _PdfImportPhase.selecting),
      onImport: _importPdf,
    ),
    _PdfImportPhase.saved => _SavedPdfView(
      document: _document!,
      onContinue: _continue,
      onLater: _later,
    ),
  };
}

class _PageSelectionView extends StatelessWidget {
  const _PageSelectionView({
    required this.inspection,
    required this.selectedPages,
    required this.thumbnail,
    required this.onToggle,
    required this.onSelectRange,
    required this.onConfirm,
  });

  final PdfInspection inspection;
  final Set<int> selectedPages;
  final Future<Uint8List> Function(int) thumbnail;
  final ValueChanged<int> onToggle;
  final VoidCallback onSelectRange;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
        child: Row(
          children: [
            Expanded(
              child: Text(
                'Đã chọn ${selectedPages.length}/10 trang',
                key: const Key('pdf-selection-count'),
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            OutlinedButton.icon(
              key: const Key('pdf-select-range'),
              onPressed: onSelectRange,
              icon: const Icon(Icons.linear_scale_rounded),
              label: const Text('Chọn phạm vi'),
            ),
          ],
        ),
      ),
      Expanded(
        child: GridView.builder(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 0.72,
          ),
          itemCount: inspection.pageCount,
          itemBuilder: (context, index) {
            final pageNumber = index + 1;
            return _SelectablePageTile(
              pageNumber: pageNumber,
              selected: selectedPages.contains(pageNumber),
              thumbnail: thumbnail(pageNumber),
              onTap: () => onToggle(pageNumber),
            );
          },
        ),
      ),
      SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
          child: FilledButton(
            key: const Key('pdf-confirm-selection'),
            style: FilledButton.styleFrom(
              minimumSize: const Size(double.infinity, 52),
            ),
            onPressed: onConfirm,
            child: const Text('Xác nhận'),
          ),
        ),
      ),
    ],
  );
}

class _SelectablePageTile extends StatelessWidget {
  const _SelectablePageTile({
    required this.pageNumber,
    required this.selected,
    required this.thumbnail,
    required this.onTap,
  });

  final int pageNumber;
  final bool selected;
  final Future<Uint8List> thumbnail;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      selected: selected,
      label: 'Trang $pageNumber',
      child: InkWell(
        key: Key('pdf-page-$pageNumber'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              width: selected ? 3 : 1,
              color: selected ? colors.primary : colors.outlineVariant,
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(9),
            child: Stack(
              fit: StackFit.expand,
              children: [
                _MemoryThumbnail(future: thumbnail),
                Positioned(
                  left: 6,
                  bottom: 6,
                  child: _PageLabel(pageNumber: pageNumber),
                ),
                Positioned(
                  right: 6,
                  top: 6,
                  child: CircleAvatar(
                    radius: 13,
                    backgroundColor: selected
                        ? colors.primary
                        : colors.surface.withValues(alpha: 0.88),
                    child: Icon(
                      selected ? Icons.check_rounded : Icons.add_rounded,
                      size: 17,
                      color: selected
                          ? colors.onPrimary
                          : colors.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PdfPreviewView extends StatelessWidget {
  const _PdfPreviewView({
    required this.candidate,
    required this.inspection,
    required this.selectedPages,
    required this.thumbnail,
    required this.onReselect,
    required this.onImport,
  });

  final PdfCandidate candidate;
  final PdfInspection inspection;
  final List<int> selectedPages;
  final Future<Uint8List> Function(int) thumbnail;
  final VoidCallback onReselect;
  final VoidCallback onImport;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Expanded(
        child: CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              sliver: SliverToBoxAdapter(
                child: _PdfFileHeader(
                  fileName: candidate.originalName,
                  pageCount: inspection.pageCount,
                  fileSizeBytes: candidate.fileSizeBytes,
                  selectedCount: selectedPages.length,
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
              sliver: SliverGrid.builder(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 0.72,
                ),
                itemCount: selectedPages.length,
                itemBuilder: (context, index) {
                  final page = selectedPages[index];
                  return ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        _MemoryThumbnail(future: thumbnail(page)),
                        Positioned(
                          left: 8,
                          bottom: 8,
                          child: _PageLabel(pageNumber: page),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  key: const Key('pdf-reselect-pages'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 52),
                  ),
                  onPressed: onReselect,
                  child: const Text('Chọn lại trang'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  key: const Key('pdf-import-document'),
                  style: FilledButton.styleFrom(minimumSize: const Size(0, 52)),
                  onPressed: onImport,
                  child: const Text('Nhập tài liệu'),
                ),
              ),
            ],
          ),
        ),
      ),
    ],
  );
}

class _SavedPdfView extends StatelessWidget {
  const _SavedPdfView({
    required this.document,
    required this.onContinue,
    required this.onLater,
  });

  final ImportedDocument document;
  final VoidCallback onContinue;
  final VoidCallback onLater;

  @override
  Widget build(BuildContext context) {
    final palette = MemoPalette.of(context);
    return Column(
      children: [
        Expanded(
          child: CustomScrollView(
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
                sliver: SliverToBoxAdapter(
                  child: Row(
                    children: [
                      CircleAvatar(
                        backgroundColor: palette.secondaryContainer,
                        child: Icon(
                          Icons.check_rounded,
                          color: palette.success,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Nhập PDF thành công',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            Text(
                              '${document.title} · ${document.pages.length} trang · Chờ OCR',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                sliver: SliverGrid.builder(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 0.72,
                  ),
                  itemCount: document.pages.length,
                  itemBuilder: (context, index) {
                    final page = document.pages[index];
                    return ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          ColoredBox(
                            color: palette.surfaceMuted,
                            child: StoredImage(path: page.absolutePath),
                          ),
                          Positioned(
                            left: 8,
                            bottom: 8,
                            child: _PageLabel(
                              pageNumber: page.originalPageNumber,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    key: const Key('pdf-later'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 52),
                    ),
                    onPressed: onLater,
                    child: const Text('Để sau'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    key: const Key('pdf-continue'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 52),
                    ),
                    onPressed: onContinue,
                    child: const Text('Tiếp tục'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _PdfFileHeader extends StatelessWidget {
  const _PdfFileHeader({
    required this.fileName,
    required this.pageCount,
    required this.fileSizeBytes,
    required this.selectedCount,
  });

  final String fileName;
  final int pageCount;
  final int fileSizeBytes;
  final int selectedCount;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Icon(Icons.picture_as_pdf_rounded, size: 42),
      const SizedBox(width: 12),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(fileName, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              '$pageCount trang · ${_formatBytes(fileSizeBytes)} · '
              'Đã chọn $selectedCount trang',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    ],
  );
}

class _MemoryThumbnail extends StatelessWidget {
  const _MemoryThumbnail({required this.future});

  final Future<Uint8List> future;

  @override
  Widget build(BuildContext context) => FutureBuilder<Uint8List>(
    future: future,
    builder: (context, snapshot) {
      if (snapshot.hasData) {
        return Image.memory(
          snapshot.data!,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => const _ThumbnailError(),
        );
      }
      if (snapshot.hasError) return const _ThumbnailError();
      return const ColoredBox(
        color: Color(0xffebeef3),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    },
  );
}

class _ThumbnailError extends StatelessWidget {
  const _ThumbnailError();

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: MemoPalette.of(context).surfaceMuted,
    child: const Center(child: Icon(Icons.broken_image_outlined)),
  );
}

class _PageLabel extends StatelessWidget {
  const _PageLabel({required this.pageNumber});

  final int pageNumber;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: Colors.black87,
      borderRadius: BorderRadius.circular(7),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Text(
        'Trang $pageNumber',
        style: Theme.of(context).textTheme.labelSmall
            ?.copyWith(color: Colors.white),
      ),
    ),
  );
}

class _BusyOverlay extends StatelessWidget {
  const _BusyOverlay({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Positioned.fill(
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
                Text(label),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class _PageRange {
  const _PageRange(this.start, this.end);

  final int start;
  final int end;
}

class _PageRangeDialog extends StatefulWidget {
  const _PageRangeDialog({required this.pageCount});

  final int pageCount;

  @override
  State<_PageRangeDialog> createState() => _PageRangeDialogState();
}

class _PageRangeDialogState extends State<_PageRangeDialog> {
  final _start = TextEditingController();
  final _end = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _start.dispose();
    _end.dispose();
    super.dispose();
  }

  void _apply() {
    final start = int.tryParse(_start.text.trim());
    final end = int.tryParse(_end.text.trim());
    if (start == null ||
        end == null ||
        start < 1 ||
        end > widget.pageCount ||
        start > end) {
      setState(() => _error = 'Phạm vi trang không hợp lệ.');
      return;
    }
    if (end - start + 1 > 10) {
      setState(
        () =>
            _error = 'Bạn chỉ có thể chọn tối đa 10 trang cho mỗi lượt xử lý.',
      );
      return;
    }
    Navigator.pop(context, _PageRange(start, end));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Chọn phạm vi trang'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                key: const Key('pdf-range-start'),
                controller: _start,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Từ trang'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                key: const Key('pdf-range-end'),
                controller: _end,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Đến trang'),
              ),
            ),
          ],
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(
            _error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Hủy'),
      ),
      FilledButton(
        key: const Key('pdf-apply-range'),
        onPressed: _apply,
        child: const Text('Áp dụng'),
      ),
    ],
  );
}

String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  final kilobytes = bytes / 1024;
  if (kilobytes < 1024) return '${kilobytes.toStringAsFixed(1)} KB';
  return '${(kilobytes / 1024).toStringAsFixed(1)} MB';
}

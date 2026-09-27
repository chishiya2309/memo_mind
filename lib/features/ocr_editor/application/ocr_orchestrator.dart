import 'dart:async';
import 'dart:ui';
import 'package:uuid/uuid.dart';

import '../../document_import/domain/document_import_models.dart';
import '../data/local_ocr_repository.dart';
import '../data/mlkit_text_recognition_engine.dart';
import '../domain/ocr_engine.dart';
import '../domain/ocr_models.dart';
import '../domain/ocr_repository.dart';

class OcrBatchProgress {
  const OcrBatchProgress({
    required this.currentPageIndex,
    required this.totalPages,
    required this.pageNumber,
    required this.pageId,
    required this.message,
    this.isDone = false,
    this.failedPages = const [],
    this.successfulPages = const [],
  });

  final int currentPageIndex;
  final int totalPages;
  final int pageNumber;
  final String pageId;
  final String message;
  final bool isDone;
  final List<SourcePage> failedPages;
  final List<SourcePage> successfulPages;

  double get ratio => totalPages == 0 ? 1.0 : currentPageIndex / totalPages;
}

class OcrOrchestrator {
  OcrOrchestrator({
    OcrRepository? ocrRepository,
    OcrEngine? ocrEngine,
    Uuid? uuid,
    DateTime Function()? clock,
  })  : _repository = ocrRepository ?? LocalOcrRepository(),
        _engine = ocrEngine ?? MlKitTextRecognitionEngine(),
        _uuid = uuid ?? const Uuid(),
        _clock = clock ?? DateTime.now;

  final OcrRepository _repository;
  final OcrEngine _engine;
  final Uuid _uuid;
  final DateTime Function() _clock;

  static const double lowConfidenceThreshold = 0.75;

  Stream<OcrBatchProgress> processPages({
    required ImportedDocument document,
    required List<SourcePage> selectedPages,
  }) async* {
    if (selectedPages.isEmpty) {
      yield const OcrBatchProgress(
        currentPageIndex: 0,
        totalPages: 0,
        pageNumber: 0,
        pageId: '',
        message: 'Không có trang nào được chọn.',
        isDone: true,
      );
      return;
    }

    final successfulPages = <SourcePage>[];
    final failedPages = <SourcePage>[];
    final total = selectedPages.length;

    for (var i = 0; i < total; i++) {
      final page = selectedPages[i];
      final currentNumber = i + 1;

      yield OcrBatchProgress(
        currentPageIndex: currentNumber,
        totalPages: total,
        pageNumber: page.pageNumber,
        pageId: page.pageId,
        message: 'Đang xử lý trang $currentNumber/$total (Trang ${page.pageNumber})…',
        failedPages: List.unmodifiable(failedPages),
        successfulPages: List.unmodifiable(successfulPages),
      );

      try {
        final imagePath = page.displayPath;
        final imageSize = Size(page.width.toDouble(), page.height.toDouble());

        final extracted = await _engine.recognizeText(
          imagePath: imagePath,
          imageSize: imageSize,
        );

        // Convert extracted blocks to SourceBlocks with normalized coordinates
        final sourceBlocks = <SourceBlock>[];
        var order = 0;

        for (final ext in extracted.blocks) {
          final trimmedText = ext.text.trim();
          if (trimmedText.isEmpty) continue; // Luồng 12: loại bỏ block rỗng

          final normBox = NormalizedBoundingBox.fromRect(
            ext.boundingBox,
            imageSize,
          );

          final hasValidBox = normBox != null && normBox.isValid;
          final isLowConfidence = ext.confidence == null ||
              ext.confidence! < lowConfidenceThreshold;

          // Luồng 11a / Luồng 9a / Luồng 15: đánh dấu needsReview nếu thiếu box hoặc confidence thấp
          final status = (!hasValidBox || isLowConfidence)
              ? BlockStatus.needsReview
              : BlockStatus.draft;

          final now = _clock();
          sourceBlocks.add(
            SourceBlock(
              blockId: _uuid.v4(),
              documentId: document.documentId,
              pageId: page.pageId,
              pageNumber: page.pageNumber,
              orderIndex: order++,
              rawText: trimmedText,
              normalizedText: trimmedText,
              boundingBox: normBox,
              hasValidBox: hasValidBox,
              confidence: ext.confidence,
              confidenceSource: ext.confidence != null
                  ? ConfidenceSource.mlkit
                  : ConfidenceSource.unavailable,
              status: status,
              createdAt: now,
              updatedAt: now,
            ),
          );
        }

        // Save page OCR result atomically
        await _repository.savePageOcrDraft(
          documentId: document.documentId,
          pageId: page.pageId,
          pageNumber: page.pageNumber,
          blocks: sourceBlocks,
          rawFullText: extracted.rawFullText,
          language: extracted.detectedLanguage,
        );

        successfulPages.add(page);
      } catch (e) {
        // Luồng 13a: ghi nhận trang thất bại, tiếp tục trang tiếp theo
        failedPages.add(page);
        await _repository.recordPageOcrFailure(
          documentId: document.documentId,
          pageId: page.pageId,
          errorMessage: e.toString(),
        );
      }
    }

    // Save document state as pending_ocr_review
    await _repository.saveDraft(document.documentId);

    yield OcrBatchProgress(
      currentPageIndex: total,
      totalPages: total,
      pageNumber: selectedPages.last.pageNumber,
      pageId: selectedPages.last.pageId,
      message: 'Hoàn tất nhận dạng văn bản.',
      isDone: true,
      failedPages: List.unmodifiable(failedPages),
      successfulPages: List.unmodifiable(successfulPages),
    );
  }
}

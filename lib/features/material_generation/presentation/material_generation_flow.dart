import 'dart:io';
import 'package:flutter/material.dart';

import '../../../shared/theme/memo_theme.dart';
import '../../deck_management/data/local_deck_repository.dart';
import '../../deck_management/domain/deck_repository.dart';
import '../../document_import/domain/document_import_models.dart';
import '../../ocr_editor/data/local_ocr_repository.dart';
import '../../ocr_editor/domain/ocr_models.dart';
import '../../ocr_editor/domain/ocr_repository.dart';
import '../application/generate_flashcards_use_case.dart';
import '../data/remote_material_generation_repository.dart';
import '../domain/material_generation_models.dart';
import '../domain/material_generation_repository.dart';
import 'flashcard_review_approval_screen.dart';
import 'material_generation_config_modal.dart';

class MaterialGenerationFlow {
  const MaterialGenerationFlow._();

  static Future<void> start({
    required BuildContext context,
    required ImportedDocument document,
    OcrRepository? ocrRepository,
    DeckRepository? deckRepository,
    MaterialGenerationRepository? generationRepository,
    Directory? storageDirectory,
  }) async {
    final ocrRepo = ocrRepository ?? LocalOcrRepository();
    final deckRepo = deckRepository ?? LocalDeckRepository();
    final genRepo = generationRepository ?? RemoteMaterialGenerationRepository();

    // 1. Fetch document review & verified blocks
    final review = await ocrRepo.getOcrReview(document.documentId);
    final verifiedBlocks = <SourceBlock>[];
    final sourcePages = document.pages;

    for (final pageReview in review.pageReviews) {
      for (final block in pageReview.blocks) {
        if (!block.isDeleted && (block.isVerified || block.isUserAdded)) {
          verifiedBlocks.add(block);
        }
      }
    }

    if (!context.mounted) return;

    if (verifiedBlocks.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Tài liệu chưa có đoạn văn bản nào được xác nhận. Vui lòng xác nhận văn bản trước khi tạo học liệu.',
          ),
        ),
      );
      return;
    }

    // 2. Open config modal
    final config = await MaterialGenerationConfigModal.show(
      context,
      documentTitle: document.title,
      verifiedBlocks: verifiedBlocks,
    );

    if (config == null || !context.mounted) return;

    await _executeGeneration(
      context: context,
      document: document,
      format: config.format,
      count: config.count,
      selectedBlockIds: config.selectedBlockIds,
      verifiedBlocks: verifiedBlocks,
      sourcePages: sourcePages,
      ocrRepo: ocrRepo,
      deckRepo: deckRepo,
      genRepo: genRepo,
      storageDirectory: storageDirectory,
    );
  }

  static Future<void> _executeGeneration({
    required BuildContext context,
    required ImportedDocument document,
    required FlashcardFormat format,
    required int count,
    required Set<String> selectedBlockIds,
    required List<SourceBlock> verifiedBlocks,
    required List<SourcePage> sourcePages,
    required OcrRepository ocrRepo,
    required DeckRepository deckRepo,
    required MaterialGenerationRepository genRepo,
    Directory? storageDirectory,
  }) async {
    final palette = MemoPalette.of(context);

    // Show loading indicator
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          decoration: BoxDecoration(
            color: palette.surface,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.1),
                blurRadius: 16,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: palette.primary),
              const SizedBox(height: 16),
              Text(
                'Đang tạo flashcard bằng AI...',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: palette.text,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Đang kiểm định nguồn và cấu trúc thẻ',
                style: TextStyle(fontSize: 12, color: palette.textMuted),
              ),
            ],
          ),
        ),
      ),
    );

    final useCase = GenerateFlashcardsUseCase(
      ocrRepository: ocrRepo,
      generationRepository: genRepo,
    );

    try {
      final result = await useCase.execute(
        documentId: document.documentId,
        format: format,
        desiredCount: count,
        selectedBlockIds: selectedBlockIds,
      );

      if (!context.mounted) return;
      Navigator.of(context, rootNavigator: true).pop(); // Dismiss loading dialog

      // Navigate to Review Approval Screen
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => FlashcardReviewApprovalScreen(
            documentId: document.documentId,
            documentTitle: document.title,
            initialCards: result.cards,
            sourceBlocks: verifiedBlocks,
            sourcePages: sourcePages,
            deckRepository: deckRepo,
            ocrRepository: ocrRepo,
            generationRepository: genRepo,
            discardedCount: result.discardedCount,
            warnings: result.warnings,
            storageDirectory: storageDirectory,
          ),
        ),
      );
    } on MaterialGenerationFailure catch (e) {
      if (!context.mounted) return;
      Navigator.of(context, rootNavigator: true).pop(); // Dismiss loading dialog
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.message),
          backgroundColor: palette.error,
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      Navigator.of(context, rootNavigator: true).pop(); // Dismiss loading dialog
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Lỗi trong quá trình tạo flashcard: $e'),
          backgroundColor: palette.error,
        ),
      );
    }
  }
}

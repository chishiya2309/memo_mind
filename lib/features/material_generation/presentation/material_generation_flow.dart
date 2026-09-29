import 'dart:io';

import 'package:flutter/material.dart';

import '../../deck_management/data/local_deck_repository.dart';
import '../../deck_management/domain/deck_repository.dart';
import '../../document_import/domain/document_import_models.dart';
import '../../ocr_editor/data/local_ocr_repository.dart';
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
    final ocr = ocrRepository ?? LocalOcrRepository();
    final decks = deckRepository ?? LocalDeckRepository();
    final generation =
        generationRepository ?? RemoteMaterialGenerationRepository();
    try {
      final review = await ocr.getOcrReview(document.documentId);
      final blocks = [
        for (final page in review.pageReviews)
          for (final b in page.blocks)
            if (b.documentId == document.documentId &&
                b.pageId == page.pageId &&
                b.pageNumber == page.pageNumber &&
                !b.isDeleted &&
                (b.isVerified || b.isUserAdded) &&
                b.normalizedText.trim().isNotEmpty)
              b,
      ];
      if (!context.mounted) return;
      if (blocks.isEmpty) {
        throw const MaterialGenerationFailure(
          MaterialGenerationFailureCode.invalidRequest,
          'Hoàn tất OCR và xác nhận văn bản trước khi tạo học liệu.',
        );
      }
      final selection = await MaterialGenerationConfigModal.show(
        context,
        documentId: document.documentId,
        documentTitle: document.title,
        verifiedBlocks: blocks,
        deckRepository: decks,
      );
      if (selection == null || !context.mounted) return;
      final deck = await decks.getDeckById(selection.deck.id);
      if (!context.mounted) return;
      if (deck == null) {
        throw const MaterialGenerationFailure(
          MaterialGenerationFailureCode.invalidRequest,
          'Deck đích không còn tồn tại.',
        );
      }
      final navigator = Navigator.of(context, rootNavigator: true);
      final loading = DialogRoute<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => const PopScope(
          canPop: false,
          child: AlertDialog(
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Đang tạo và kiểm tra học liệu…'),
              ],
            ),
          ),
        ),
      );
      navigator.push(loading);
      late final MaterialGenerationResult result;
      try {
        result =
            await GenerateMaterialsUseCase(
              ocrRepository: ocr,
              generationRepository: generation,
            ).execute(
              documentId: document.documentId,
              types: selection.config.types,
              quantityMode: selection.config.quantityMode,
              desiredCount: selection.config.desiredCount,
              selectedBlockIds: selection.config.selectedBlockIds,
            );
      } finally {
        if (loading.isActive && navigator.mounted) {
          navigator.removeRoute(loading);
        }
      }
      if (!context.mounted) return;
      if (result.cards.isEmpty) {
        throw const MaterialGenerationFailure(
          MaterialGenerationFailureCode.noValidCards,
          'Không có học liệu đạt kiểm tra.',
        );
      }
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => FlashcardReviewApprovalScreen(
            documentId: document.documentId,
            documentTitle: document.title,
            targetDeck: deck,
            initialCards: result.cards,
            sourceBlocks: blocks,
            sourcePages: review.document.pages,
            deckRepository: decks,
            ocrRepository: ocr,
            generationRepository: generation,
            discardedCount: result.discardedCount,
            warnings: result.warnings,
            storageDirectory: storageDirectory,
          ),
        ),
      );
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              error is MaterialGenerationFailure
                  ? error.message
                  : 'Không thể tạo học liệu. Vui lòng thử lại.',
            ),
          ),
        );
      }
    }
  }
}

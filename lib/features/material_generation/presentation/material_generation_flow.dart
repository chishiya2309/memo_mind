import 'dart:io';

import 'package:flutter/material.dart';

import '../../deck_management/data/local_deck_repository.dart';
import '../../deck_management/domain/deck_repository.dart';
import '../../deck_management/presentation/deck_detail_screen.dart';
import '../../deck_management/presentation/library_decks_screen.dart';
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
      late MaterialGenerationResult result;
      while (true) {
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
                  Text('Đang tạo học liệu…'),
                ],
              ),
            ),
          ),
        );
        navigator.push(loading);
        Object? failure;
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
          if (result.cards.isEmpty) {
            throw const MaterialGenerationFailure(
              MaterialGenerationFailureCode.noValidCards,
              'AI chưa tạo được học liệu từ nguồn đã chọn. Bạn có thể chọn thêm nguồn hoặc thử lại.',
            );
          }
        } catch (error) {
          failure = error;
        } finally {
          if (loading.isActive && navigator.mounted) {
            navigator.removeRoute(loading);
          }
        }
        if (!context.mounted) return;
        if (failure == null) break;
        final retry = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Chưa thể tạo học liệu'),
            content: Text(
              failure is MaterialGenerationFailure
                  ? failure.message
                  : 'Không thể tạo học liệu. Vui lòng thử lại.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Đóng'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Thử lại'),
              ),
            ],
          ),
        );
        if (retry != true || !context.mounted) return;
      }
      final saved = await Navigator.of(context).push<MaterialSaveResult>(
        MaterialPageRoute<MaterialSaveResult>(
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
      if (saved != null && navigator.mounted) {
        openSavedDeck(navigator: navigator, decks: decks, result: saved);
      }
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

  static void openSavedDeck({
    required NavigatorState navigator,
    required DeckRepository decks,
    required MaterialSaveResult result,
  }) {
    Future<void> openDeck(String id, {int? savedCount}) => navigator.push<void>(
      MaterialPageRoute<void>(
        settings: RouteSettings(name: 'deck/$id'),
        builder: (_) => DeckDetailScreen(
          deckId: id,
          repository: decks,
          savedCount: savedCount,
        ),
      ),
    );
    navigator.popUntil((route) => route.isFirst);
    navigator.push<void>(
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: 'library'),
        builder: (_) => Scaffold(
          appBar: AppBar(title: const Text('Thư viện')),
          body: LibraryDecksScreen(
            repository: decks,
            onOpenDeck: (id) {
              openDeck(id);
            },
            onOpenDeckAsync: openDeck,
          ),
        ),
      ),
    );
    openDeck(result.deckId, savedCount: result.savedCount);
  }
}

import '../../deck_management/domain/deck_models.dart';
import '../../deck_management/domain/deck_repository.dart';
import '../../ocr_editor/domain/ocr_repository.dart';
import '../domain/material_generation_models.dart';

class SaveAcceptedCardsUseCase {
  const SaveAcceptedCardsUseCase({
    required this.deckRepository,
    required this.ocrRepository,
  });

  final DeckRepository deckRepository;
  final OcrRepository ocrRepository;

  Future<int> execute({
    required String deckId,
    required String documentId,
    required List<FlashcardDraft> drafts,
  }) async {
    final accepted = drafts.where((d) => d.isAccepted).toList();

    // BR07-09, Luồng 30a: Chưa chọn thẻ nào
    if (accepted.isEmpty) {
      throw const MaterialGenerationFailure(
        MaterialGenerationFailureCode.invalidRequest,
        'Vui lòng chọn ít nhất một flashcard để lưu.',
      );
    }

    // Luồng 33a: Kiểm tra lại các SourceBlock nguồn trước khi lưu
    final review = await ocrRepository.getOcrReview(documentId);
    final blockMap = <String, ({String pageId, int pageNumber})>{};

    for (final page in review.pageReviews) {
      for (final block in page.blocks) {
        if (!block.isDeleted) {
          blockMap[block.blockId] = (
            pageId: page.pageId,
            pageNumber: block.pageNumber,
          );
        }
      }
    }

    final cardEntities = <CardEntity>[];
    final now = DateTime.now();

    for (final draft in accepted) {
      final blockMeta = blockMap[draft.sourceBlockId];
      if (blockMeta == null) {
        throw MaterialGenerationFailure(
          MaterialGenerationFailureCode.sourceBlockMismatch,
          'Một số khối nguồn đã bị thay đổi hoặc xóa. Vui lòng kiểm tra lại.',
        );
      }

      cardEntities.add(
        CardEntity(
          id: draft.id,
          deckId: deckId,
          type: 'flashcard',
          format: draft.format.name,
          question: draft.question,
          answer: draft.answer,
          sourceDocumentId: documentId,
          sourcePageId: blockMeta.pageId,
          sourcePageNumber: draft.sourcePage,
          sourceBlockId: draft.sourceBlockId,
          sourceQuote: draft.sourceQuote,
          confidence: draft.confidence,
          status: CardStatus.active,
          dueDate: now,
          createdAt: now,
          updatedAt: now,
        ),
      );
    }

    await deckRepository.saveCardsToDeck(
      deckId: deckId,
      cards: cardEntities,
    );

    return cardEntities.length;
  }
}

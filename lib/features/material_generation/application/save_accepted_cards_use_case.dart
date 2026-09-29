import '../../deck_management/domain/deck_models.dart';
import '../../deck_management/domain/deck_repository.dart';
import '../../ocr_editor/domain/ocr_repository.dart';
import '../domain/material_generation_models.dart';
import '../domain/material_validator.dart';

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
    required List<MaterialDraft> drafts,
  }) async {
    final accepted = drafts.where((d) => d.isAccepted).toList();
    if (accepted.isEmpty) return 0;
    final review = await ocrRepository.getOcrReview(documentId);
    final blocks = {
      for (final page in review.pageReviews)
        for (final block in page.blocks) block.blockId: block,
    };
    final now = DateTime.now();
    final cards = <CardEntity>[];
    for (final draft in accepted) {
      final block = blocks[draft.sourceBlockId];
      MaterialValidator.validate(
        draft,
        sourceBlock: block,
        documentId: documentId,
      );
      cards.add(
        CardEntity(
          id: draft.id,
          deckId: deckId,
          type: draft.type,
          front: draft.front.trim(),
          back: draft.back.trim(),
          options: draft.options,
          correctOptionId: draft.correctOptionId,
          explanation: draft.explanation,
          sourceDocumentId: documentId,
          sourcePageId: block!.pageId,
          sourcePageNumber: draft.sourcePage,
          sourceBlockId: draft.sourceBlockId,
          sourceQuote: draft.sourceQuote,
          confidence: draft.confidence,
          dueDate: now,
          createdAt: now,
          updatedAt: now,
        ),
      );
    }
    await deckRepository.saveCardsToDeck(deckId: deckId, cards: cards);
    return cards.length;
  }
}

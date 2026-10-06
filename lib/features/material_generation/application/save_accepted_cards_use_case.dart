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
      final candidate = blocks[draft.sourceBlockId];
      final block =
          candidate != null &&
              !candidate.isDeleted &&
              candidate.documentId == documentId
          ? candidate
          : null;
      final errors = MaterialValidator.errors(draft, requireSource: false);
      if (errors.isNotEmpty) throw FormatException(errors.values.first);
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
          sourcePageId: block?.pageNumber == draft.sourcePage
              ? block?.pageId
              : null,
          sourcePageNumber: block?.pageNumber == draft.sourcePage
              ? draft.sourcePage
              : null,
          sourceBlockId: block?.blockId,
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

import '../../deck_management/domain/deck_models.dart';
import '../../deck_management/domain/deck_repository.dart';
import '../../ocr_editor/domain/ocr_repository.dart';
import '../domain/material_generation_models.dart';
import '../domain/material_validator.dart';
import '../domain/source_reference_resolver.dart';

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
      final block = SourceReferenceResolver.resolve(
        documentId: documentId,
        quote: draft.sourceQuote,
        blockId: draft.sourceBlockId,
        pageNumber: draft.sourcePage,
        blocks: blocks.values,
      );
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
          sourcePageId: block?.pageId,
          sourcePageNumber: block?.pageNumber,
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

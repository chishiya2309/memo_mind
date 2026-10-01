import '../domain/deck_models.dart';
import '../domain/deck_repository.dart';
import '../../ocr_editor/domain/ocr_models.dart';

class GetCardSourceTraceUseCase {
  const GetCardSourceTraceUseCase({required this.deckRepository});

  final DeckRepository deckRepository;

  Future<CardSourceTrace> execute(CardEntity card) async {
    try {
      final trace = await deckRepository.getCardSourceTrace(card);
      final page = trace.sourcePage;
      final sourcePage =
          page != null &&
              page.pageId == card.sourcePageId &&
              page.documentId == card.sourceDocumentId &&
              page.pageNumber == card.sourcePageNumber
          ? page
          : null;

      final block = trace.sourceBlock;
      SourceBlock? sourceBlock;
      if (block != null &&
          block.blockId == card.sourceBlockId &&
          block.documentId == card.sourceDocumentId &&
          block.pageId == card.sourcePageId &&
          block.pageNumber == card.sourcePageNumber) {
        final box = block.boundingBox;
        final hasValidBox =
            block.hasValidBox &&
            box != null &&
            box.left.isFinite &&
            box.top.isFinite &&
            box.width.isFinite &&
            box.height.isFinite &&
            box.left >= 0 &&
            box.top >= 0 &&
            box.width > 0 &&
            box.height > 0 &&
            box.left + box.width <= 1 &&
            box.top + box.height <= 1;
        sourceBlock = hasValidBox ? block : block.copyWith(hasValidBox: false);
      }

      return CardSourceTrace(
        documentTitle: trace.documentTitle,
        sourceQuote: card.sourceQuote,
        sourcePage: sourcePage,
        sourceBlock: sourceBlock,
        imageFile: sourcePage == null ? null : trace.imageFile,
      );
    } catch (_) {
      return CardSourceTrace(documentTitle: '', sourceQuote: card.sourceQuote);
    }
  }
}

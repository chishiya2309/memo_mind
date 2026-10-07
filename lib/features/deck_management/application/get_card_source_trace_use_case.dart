import '../domain/deck_models.dart';
import '../domain/deck_repository.dart';
import '../../ocr_editor/domain/ocr_models.dart';
import '../../material_generation/domain/material_validator.dart';

class GetCardSourceTraceUseCase {
  const GetCardSourceTraceUseCase({required this.deckRepository});

  final DeckRepository deckRepository;

  Future<CardSourceTrace> execute(CardEntity card) async {
    try {
      final trace = await deckRepository.getCardSourceTrace(card);
      final page = trace.sourcePage;
      final sourcePage =
          page != null &&
              (trace.sourceReferenceRepaired ||
                  page.pageId == card.sourcePageId) &&
              page.documentId == card.sourceDocumentId &&
              page.pageNumber ==
                  (trace.sourceReferenceRepaired
                      ? trace.sourcePageNumber
                      : card.sourcePageNumber)
          ? page
          : null;

      final block = trace.sourceBlock;
      SourceBlock? sourceBlock;
      if (block != null &&
          !block.isDeleted &&
          (trace.sourceReferenceRepaired ||
              block.blockId == card.sourceBlockId) &&
          block.documentId == card.sourceDocumentId &&
          block.pageId == sourcePage?.pageId &&
          block.pageNumber == sourcePage?.pageNumber &&
          MaterialValidator.isQuoteSupported(
            card.sourceQuote,
            block.normalizedText,
          )) {
        final hasValidBox =
            trace.imageUsesNormalizedCoordinates &&
            sourcePage != null &&
            block.hasBoxFor(sourcePage);
        sourceBlock = hasValidBox ? block : block.copyWith(hasValidBox: false);
      }

      return CardSourceTrace(
        documentTitle: trace.documentTitle,
        sourceQuote: card.sourceQuote,
        sourcePage: sourcePage,
        sourceBlock: sourceBlock,
        imageFile: sourcePage == null ? null : trace.imageFile,
        sourcePageNumber: trace.sourcePageNumber ?? card.sourcePageNumber,
        sourceReferenceRepaired: trace.sourceReferenceRepaired,
        imageUsesNormalizedCoordinates: trace.imageUsesNormalizedCoordinates,
        warning:
            trace.warning ??
            (sourcePage == null
                ? 'Trang nguồn không còn khả dụng.'
                : sourceBlock == null
                ? 'Liên kết khối nguồn không còn khả dụng.'
                : trace.imageFile == null
                ? 'Ảnh trang nguồn không còn khả dụng.'
                : !sourceBlock.hasValidBox
                ? 'Vị trí đoạn nguồn không khả dụng.'
                : null),
      );
    } catch (_) {
      return CardSourceTrace(
        documentTitle: '',
        sourceQuote: card.sourceQuote,
        sourcePageNumber: card.sourcePageNumber,
        warning: 'Không thể đọc nguồn đã lưu.',
      );
    }
  }
}

import '../../ocr_editor/domain/ocr_models.dart';
import 'material_generation_models.dart';
import 'material_validator.dart';

/// Exact evidence only. An ambiguous or paraphrased quote never picks a box.
class SourceReferenceResolver {
  const SourceReferenceResolver._();

  static SourceBlock? resolve({
    required String documentId,
    required String quote,
    required Iterable<SourceBlock> blocks,
    String? blockId,
    int? pageNumber,
  }) {
    final matches = blocks
        .where(
          (b) =>
              b.documentId == documentId &&
              !b.isDeleted &&
              MaterialValidator.isQuoteSupported(quote, b.normalizedText),
        )
        .toList();
    final current = matches.where(
      (b) => b.blockId == blockId && b.pageNumber == pageNumber,
    );
    if (current.length == 1) return current.single;
    final onPage = matches.where((b) => b.pageNumber == pageNumber).toList();
    if (onPage.isNotEmpty) return onPage.length == 1 ? onPage.single : null;
    return matches.length == 1 ? matches.single : null;
  }

  static MaterialDraft resolveDraft(
    MaterialDraft card,
    String documentId,
    Iterable<SourceBlock> blocks,
  ) {
    final block = resolve(
      documentId: documentId,
      quote: card.sourceQuote,
      blocks: blocks,
      blockId: card.sourceBlockId,
      pageNumber: card.sourcePage,
    );
    return block == null
        ? card
        : card.copyWith(
            sourceBlockId: block.blockId,
            sourcePage: block.pageNumber,
          );
  }
}

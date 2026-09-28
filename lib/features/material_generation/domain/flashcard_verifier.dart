import '../../ocr_editor/domain/ocr_models.dart';
import 'material_generation_models.dart';

class FlashcardVerifier {
  const FlashcardVerifier();

  static String normalizeForComparison(String? text) {
    if (text == null) return '';
    return text
        .toLowerCase()
        .replaceAll(RegExp(r'''[.,\/#!$%\^&\*;:{}=\-_`~()?"'«»“”]'''), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  /// Verifies if a quote exists in the source block's normalized text (BR07-08)
  static bool isQuoteSupported(String quote, String sourceText) {
    final normQuote = normalizeForComparison(quote);
    final normSource = normalizeForComparison(sourceText);
    if (normQuote.isEmpty || normSource.isEmpty) return false;
    return normSource.contains(normQuote);
  }

  /// Verifies an edited card against its source block (Luồng 28a)
  /// Returns updated FlashcardDraft with appropriate status
  static FlashcardDraft verifyEditedCard({
    required FlashcardDraft card,
    required SourceBlock? sourceBlock,
    required String newQuestion,
    required String newAnswer,
  }) {
    final trimmedQ = newQuestion.trim();
    final trimmedA = newAnswer.trim();

    if (trimmedQ.isEmpty || trimmedA.isEmpty) {
      throw const FormatException('Câu hỏi và đáp án không được để trống.');
    }

    if (card.format == FlashcardFormat.cloze && !trimmedQ.contains('[...]')) {
      throw const FormatException(
        'Thẻ điền khuyết phải chứa ký hiệu vị trí trống "[...]".',
      );
    }

    // Check if source block still exists
    if (sourceBlock == null || sourceBlock.isDeleted) {
      return card.copyWith(
        question: trimmedQ,
        answer: trimmedA,
        status: DraftCardStatus.needsSourceCheck,
        isEdited: true,
      );
    }

    // Check if quote is still supported by source block
    final quoteSupported = isQuoteSupported(card.sourceQuote, sourceBlock.normalizedText);

    return card.copyWith(
      question: trimmedQ,
      answer: trimmedA,
      status: quoteSupported ? DraftCardStatus.accepted : DraftCardStatus.needsSourceCheck,
      isEdited: true,
    );
  }
}

import '../../ocr_editor/domain/ocr_models.dart';
import 'material_generation_models.dart';
import 'material_validator.dart';

class FlashcardVerifier {
  const FlashcardVerifier();
  static String normalizeForComparison(String? text) =>
      MaterialValidator.normalize(text ?? '');
  static bool isQuoteSupported(String quote, String sourceText) =>
      MaterialValidator.isQuoteSupported(quote, sourceText);
  static MaterialDraft verifyEditedCard({
    required MaterialDraft card,
    required SourceBlock? sourceBlock,
    required String newQuestion,
    required String newAnswer,
  }) {
    final edited = card.copyWith(
      front: newQuestion.trim(),
      back: newAnswer.trim(),
      status: DraftCardStatus.pending,
      isEdited: true,
    );
    final errors = MaterialValidator.errors(edited);
    if (errors.isNotEmpty) throw FormatException(errors.values.first);
    try {
      MaterialValidator.validate(
        edited,
        sourceBlock: sourceBlock,
        documentId: sourceBlock?.documentId ?? '',
      );
      return edited;
    } on MaterialGenerationFailure {
      return edited.copyWith(status: DraftCardStatus.needsSourceCheck);
    }
  }
}

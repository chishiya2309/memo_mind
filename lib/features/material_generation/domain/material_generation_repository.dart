import '../../ocr_editor/domain/ocr_models.dart';
import 'material_generation_models.dart';

abstract class MaterialGenerationRepository {
  Future<FlashcardGenerationResult> generateFlashcards({
    required String documentId,
    required FlashcardFormat format,
    required int desiredCount,
    required List<SourceBlock> sourceBlocks,
  });

  Future<FlashcardDraft> regenerateSingleCard({
    required SourceBlock sourceBlock,
    required FlashcardFormat format,
  });
}

import '../../ocr_editor/domain/ocr_models.dart';
import 'material_generation_models.dart';

abstract class MaterialGenerationRepository {
  Future<MaterialGenerationResult> generateMaterials({
    required String documentId,
    required Set<CardType> types,
    QuantityMode quantityMode = QuantityMode.auto,
    int? desiredCount,
    required List<SourceBlock> sourceBlocks,
  });
  Future<MaterialDraft> regenerateSingleCard({
    required SourceBlock sourceBlock,
    required CardType type,
  });
}

import '../../ocr_editor/domain/ocr_models.dart';
import '../domain/material_generation_models.dart';
import '../domain/material_generation_repository.dart';
import 'material_generation_api_client.dart';

class RemoteMaterialGenerationRepository
    implements MaterialGenerationRepository {
  RemoteMaterialGenerationRepository({MaterialGenerationApiClient? apiClient})
    : _apiClient = apiClient ?? MaterialGenerationApiClient();
  final MaterialGenerationApiClient _apiClient;
  @override
  Future<MaterialGenerationResult> generateMaterials({
    required String documentId,
    required Set<CardType> types,
    QuantityMode quantityMode = QuantityMode.auto,
    int? desiredCount,
    required List<SourceBlock> sourceBlocks,
  }) => _apiClient.generateMaterials(
    documentId: documentId,
    types: types,
    quantityMode: quantityMode,
    desiredCount: desiredCount,
    sourceBlocks: sourceBlocks,
  );
  @override
  Future<MaterialDraft> regenerateSingleCard({
    required SourceBlock sourceBlock,
    required CardType type,
  }) async {
    final result = await generateMaterials(
      documentId: sourceBlock.documentId,
      types: {type},
      quantityMode: QuantityMode.manual,
      desiredCount: 1,
      sourceBlocks: [sourceBlock],
    );
    return result.cards.first;
  }
}

import '../../ocr_editor/domain/ocr_models.dart';
import '../domain/material_generation_models.dart';
import '../domain/material_generation_repository.dart';
import 'material_generation_api_client.dart';

class RemoteMaterialGenerationRepository implements MaterialGenerationRepository {
  RemoteMaterialGenerationRepository({
    MaterialGenerationApiClient? apiClient,
  }) : _apiClient = apiClient ?? MaterialGenerationApiClient();

  final MaterialGenerationApiClient _apiClient;

  @override
  Future<FlashcardGenerationResult> generateFlashcards({
    required String documentId,
    required FlashcardFormat format,
    required int desiredCount,
    required List<SourceBlock> sourceBlocks,
  }) {
    return _apiClient.generateFlashcards(
      documentId: documentId,
      format: format,
      desiredCount: desiredCount,
      sourceBlocks: sourceBlocks,
    );
  }

  @override
  Future<FlashcardDraft> regenerateSingleCard({
    required SourceBlock sourceBlock,
    required FlashcardFormat format,
  }) async {
    final result = await _apiClient.generateFlashcards(
      documentId: sourceBlock.documentId,
      format: format,
      desiredCount: 1,
      sourceBlocks: [sourceBlock],
    );

    if (result.cards.isEmpty) {
      throw const MaterialGenerationFailure(
        MaterialGenerationFailureCode.noValidCards,
        'Không thể tạo lại thẻ từ khối nguồn này. Vui lòng thử lại.',
      );
    }

    return result.cards.first;
  }
}

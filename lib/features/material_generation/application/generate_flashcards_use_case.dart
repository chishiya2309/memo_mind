import '../../ocr_editor/domain/ocr_models.dart';
import '../../ocr_editor/domain/ocr_repository.dart';
import '../domain/material_generation_models.dart';
import '../domain/material_generation_repository.dart';

class GenerateFlashcardsUseCase {
  const GenerateFlashcardsUseCase({
    required this.ocrRepository,
    required this.generationRepository,
  });

  final OcrRepository ocrRepository;
  final MaterialGenerationRepository generationRepository;

  Future<FlashcardGenerationResult> execute({
    required String documentId,
    required FlashcardFormat format,
    required int desiredCount,
    Set<String> selectedBlockIds = const {},
  }) async {
    final review = await ocrRepository.getOcrReview(documentId);

    // Filter verified or user-added blocks (BR07-01)
    final eligibleBlocks = <SourceBlock>[];
    for (final page in review.pageReviews) {
      for (final block in page.blocks) {
        if (!block.isDeleted && (block.isVerified || block.isUserAdded)) {
          if (selectedBlockIds.isEmpty || selectedBlockIds.contains(block.blockId)) {
            eligibleBlocks.add(block);
          }
        }
      }
    }

    if (eligibleBlocks.isEmpty) {
      throw const MaterialGenerationFailure(
        MaterialGenerationFailureCode.noValidCards,
        'Cần ít nhất một đoạn văn bản đã được xác nhận để sinh flashcard.',
      );
    }

    return generationRepository.generateFlashcards(
      documentId: documentId,
      format: format,
      desiredCount: desiredCount,
      sourceBlocks: eligibleBlocks,
    );
  }
}

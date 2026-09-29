import '../../ocr_editor/domain/ocr_models.dart';
import '../../ocr_editor/domain/ocr_repository.dart';
import '../domain/material_generation_models.dart';
import '../domain/material_generation_repository.dart';

class GenerateMaterialsUseCase {
  const GenerateMaterialsUseCase({
    required this.ocrRepository,
    required this.generationRepository,
  });
  final OcrRepository ocrRepository;
  final MaterialGenerationRepository generationRepository;
  Future<MaterialGenerationResult> execute({
    required String documentId,
    required Set<CardType> types,
    QuantityMode quantityMode = QuantityMode.auto,
    int? desiredCount,
    Set<String> selectedBlockIds = const {},
  }) async {
    if (types.isEmpty ||
        (quantityMode == QuantityMode.manual &&
            (desiredCount == null ||
                desiredCount < types.length ||
                desiredCount > 30))) {
      throw const MaterialGenerationFailure(
        MaterialGenerationFailureCode.invalidRequest,
        'Chọn loại học liệu và số lượng từ số loại đã chọn đến 30.',
      );
    }
    final review = await ocrRepository.getOcrReview(documentId);
    final eligible = <SourceBlock>[
      for (final page in review.pageReviews)
        for (final block in page.blocks)
          if (block.documentId == documentId &&
              block.pageId == page.pageId &&
              block.pageNumber == page.pageNumber &&
              !block.isDeleted &&
              (block.isVerified || block.isUserAdded) &&
              block.normalizedText.trim().isNotEmpty &&
              (selectedBlockIds.isEmpty ||
                  selectedBlockIds.contains(block.blockId)))
            block,
    ];
    if (eligible.isEmpty) {
      throw const MaterialGenerationFailure(
        MaterialGenerationFailureCode.invalidRequest,
        'Cần hoàn tất OCR và xác nhận đoạn nguồn có nội dung.',
      );
    }
    if (eligible.fold<int>(0, (sum, b) => sum + b.normalizedText.length) >
        100000) {
      throw const MaterialGenerationFailure(
        MaterialGenerationFailureCode.payloadTooLarge,
        'Nguồn vượt 100.000 ký tự. Vui lòng chọn ít đoạn hơn.',
      );
    }
    return generationRepository.generateMaterials(
      documentId: documentId,
      types: types,
      quantityMode: quantityMode,
      desiredCount: desiredCount,
      sourceBlocks: eligible,
    );
  }
}

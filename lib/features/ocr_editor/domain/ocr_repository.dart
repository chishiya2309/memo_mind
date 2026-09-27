import 'ocr_models.dart';

abstract class OcrRepository {
  Future<OcrDocumentReview> getOcrReview(String documentId);

  Future<List<SourceBlock>> getPageBlocks(String pageId);

  Future<void> savePageOcrDraft({
    required String documentId,
    required String pageId,
    required int pageNumber,
    required List<SourceBlock> blocks,
    required String rawFullText,
    String? language,
  });

  Future<void> recordPageOcrFailure({
    required String documentId,
    required String pageId,
    required String errorMessage,
  });

  Future<void> updateSourceBlock(SourceBlock block);

  Future<void> addSourceBlock(SourceBlock block);

  Future<void> deleteSourceBlock(String blockId);

  Future<void> restoreSourceBlock(String blockId);

  Future<void> confirmOcrReview(String documentId);

  Future<void> saveDraft(String documentId);
}

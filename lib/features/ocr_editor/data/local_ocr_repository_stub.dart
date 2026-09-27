import '../../../core/database/memo_mind_database.dart';
import '../../document_import/domain/document_import_repository.dart';
import '../domain/ocr_models.dart';
import '../domain/ocr_repository.dart';
import 'package:uuid/uuid.dart';

class LocalOcrRepository implements OcrRepository {
  const LocalOcrRepository({
    DocumentImportRepository? documentRepository,
    MemoMindDatabase? database,
    Uuid? uuid,
    DateTime Function()? clock,
  });

  OcrFailure get _unsupported => const OcrFailure(
        OcrFailureCode.unknown,
        'OCR hiện chỉ được hỗ trợ trên thiết bị di động.',
      );

  @override
  Future<OcrDocumentReview> getOcrReview(String documentId) =>
      Future.error(_unsupported);

  @override
  Future<List<SourceBlock>> getPageBlocks(String pageId) =>
      Future.error(_unsupported);

  @override
  Future<void> savePageOcrDraft({
    required String documentId,
    required String pageId,
    required int pageNumber,
    required List<SourceBlock> blocks,
    required String rawFullText,
    String? language,
  }) =>
      Future.error(_unsupported);

  @override
  Future<void> recordPageOcrFailure({
    required String documentId,
    required String pageId,
    required String errorMessage,
  }) =>
      Future.error(_unsupported);

  @override
  Future<void> updateSourceBlock(SourceBlock block) =>
      Future.error(_unsupported);

  @override
  Future<void> addSourceBlock(SourceBlock block) =>
      Future.error(_unsupported);

  @override
  Future<void> deleteSourceBlock(String blockId) =>
      Future.error(_unsupported);

  @override
  Future<void> restoreSourceBlock(String blockId) =>
      Future.error(_unsupported);

  @override
  Future<void> confirmOcrReview(String documentId) =>
      Future.error(_unsupported);

  @override
  Future<void> saveDraft(String documentId) =>
      Future.error(_unsupported);
}

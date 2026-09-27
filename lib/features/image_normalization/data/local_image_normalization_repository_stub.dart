import '../../document_import/domain/document_import_models.dart';
import '../../document_import/domain/document_import_repository.dart';
import '../application/image_normalization_engine.dart';
import '../domain/image_normalization_models.dart';
import '../domain/image_normalization_repository.dart';

class LocalImageNormalizationRepository
    implements ImageNormalizationRepository {
  LocalImageNormalizationRepository({
    required DocumentImportRepository documentRepository,
  });

  @override
  Future<void> ensureCapacityFor(SourcePage page) =>
      throw const NormalizationFailure(
        NormalizationFailureCode.unsupportedPlatform,
        'Chuẩn hóa ảnh hiện chỉ được hỗ trợ trên Android.',
      );

  @override
  Future<SourcePage?> getNextPendingPage(String documentId) async => null;

  @override
  Future<ImportedDocument> saveNormalizedPage({
    required SourcePage page,
    required NormalizationParameters parameters,
    required NormalizedRenderedImage image,
  }) => throw const NormalizationFailure(
    NormalizationFailureCode.unsupportedPlatform,
    'Chuẩn hóa ảnh hiện chỉ được hỗ trợ trên Android.',
  );
}

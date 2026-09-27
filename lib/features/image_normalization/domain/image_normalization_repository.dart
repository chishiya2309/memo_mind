import '../../document_import/domain/document_import_models.dart';
import '../application/image_normalization_engine.dart';
import 'image_normalization_models.dart';

abstract interface class ImageNormalizationRepository {
  Future<void> ensureCapacityFor(SourcePage page);

  Future<ImportedDocument> saveNormalizedPage({
    required SourcePage page,
    required NormalizationParameters parameters,
    required NormalizedRenderedImage image,
  });

  Future<SourcePage?> getNextPendingPage(String documentId);
}

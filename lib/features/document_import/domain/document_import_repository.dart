import 'document_import_models.dart';

abstract interface class DocumentImportRepository {
  Future<void> recoverInterruptedImports();

  Future<ImportedDocument> createWithFirstPage({
    required ImageCandidate candidate,
    required ImageInspection inspection,
    required bool qualityWarningAccepted,
  });

  Future<ImportedDocument> appendPage({
    required String documentId,
    required ImageCandidate candidate,
    required ImageInspection inspection,
    required bool qualityWarningAccepted,
  });

  Future<ImportedDocument> getDocument(String documentId);

  Future<void> discardCandidate(ImageCandidate candidate);
}

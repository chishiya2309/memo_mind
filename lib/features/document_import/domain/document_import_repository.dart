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

abstract interface class PdfImportRepository {
  Future<ImportedDocument> createFromPdf({
    required PdfCandidate candidate,
    required List<RenderedPdfPage> pages,
  });

  Future<void> discardPdfCandidate(PdfCandidate candidate);
}

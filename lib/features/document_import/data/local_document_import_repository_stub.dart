import '../domain/document_import_models.dart';
import '../domain/document_import_repository.dart';

class LocalDocumentImportRepository
    implements DocumentImportRepository, PdfImportRepository {
  const LocalDocumentImportRepository();

  ImportFailure get _unsupported => const ImportFailure(
    ImportFailureCode.unsupportedPlatform,
    'Nhập ảnh hiện chỉ được hỗ trợ trên Android.',
  );

  @override
  Future<ImportedDocument> appendPage({
    required String documentId,
    required ImageCandidate candidate,
    required ImageInspection inspection,
    required bool qualityWarningAccepted,
  }) => Future.error(_unsupported);

  @override
  Future<ImportedDocument> createWithFirstPage({
    required ImageCandidate candidate,
    required ImageInspection inspection,
    required bool qualityWarningAccepted,
  }) => Future.error(_unsupported);

  @override
  Future<void> discardCandidate(ImageCandidate candidate) async {}

  @override
  Future<ImportedDocument> createFromPdf({
    required PdfCandidate candidate,
    required List<RenderedPdfPage> pages,
  }) => Future.error(_unsupported);

  @override
  Future<void> discardPdfCandidate(PdfCandidate candidate) async {}

  @override
  Future<ImportedDocument> getDocument(String documentId) =>
      Future.error(_unsupported);

  @override
  Future<void> recoverInterruptedImports() async {}
}

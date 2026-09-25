import 'dart:typed_data';

import '../application/pdf_import_services.dart';
import '../domain/document_import_models.dart';

class DevicePdfCandidatePicker implements PdfCandidatePicker {
  const DevicePdfCandidatePicker();

  ImportFailure get _unsupported => const ImportFailure(
    ImportFailureCode.unsupportedPlatform,
    'Nhập PDF hiện chỉ được hỗ trợ trên Android.',
  );

  @override
  Future<PdfCandidate?> pickPdf() => Future.error(_unsupported);
}

class DevicePdfDocumentProcessor implements PdfDocumentProcessor {
  const DevicePdfDocumentProcessor();

  ImportFailure get _unsupported => const ImportFailure(
    ImportFailureCode.unsupportedPlatform,
    'Nhập PDF hiện chỉ được hỗ trợ trên Android.',
  );

  @override
  Future<void> dispose() async {}

  @override
  Future<PdfInspection> inspect(PdfCandidate candidate) =>
      Future.error(_unsupported);

  @override
  Future<List<RenderedPdfPage>> renderSelectedPages(
    PdfCandidate candidate,
    List<int> pageNumbers,
  ) => Future.error(_unsupported);

  @override
  Future<Uint8List> renderThumbnail(PdfCandidate candidate, int pageNumber) =>
      Future.error(_unsupported);
}

import 'dart:typed_data';

import '../domain/document_import_models.dart';

abstract interface class PdfCandidatePicker {
  Future<PdfCandidate?> pickPdf();
}

abstract interface class PdfDocumentProcessor {
  Future<PdfInspection> inspect(PdfCandidate candidate);

  Future<Uint8List> renderThumbnail(PdfCandidate candidate, int pageNumber);

  Future<List<RenderedPdfPage>> renderSelectedPages(
    PdfCandidate candidate,
    List<int> pageNumbers,
  );

  Future<void> dispose();
}

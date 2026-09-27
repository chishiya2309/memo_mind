import 'dart:ui';

import '../../document_import/domain/document_import_models.dart';

enum BlockStatus {
  draft,
  needsReview,
  verified,
  userAdded,
  deleted,
}

enum ConfidenceSource {
  mlkit,
  gemini,
  user,
  unavailable,
}

class NormalizedBoundingBox {
  const NormalizedBoundingBox({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });

  final double left;
  final double top;
  final double width;
  final double height;

  Rect toRect(Size imageSize) => Rect.fromLTWH(
    left * imageSize.width,
    top * imageSize.height,
    width * imageSize.width,
    height * imageSize.height,
  );

  static NormalizedBoundingBox? fromRect(Rect? rect, Size imageSize) {
    if (rect == null || imageSize.width <= 0 || imageSize.height <= 0) {
      return null;
    }

    final double l = (rect.left / imageSize.width).clamp(0.0, 1.0);
    final double t = (rect.top / imageSize.height).clamp(0.0, 1.0);
    final double w = (rect.width / imageSize.width).clamp(0.0, 1.0 - l);
    final double h = (rect.height / imageSize.height).clamp(0.0, 1.0 - t);

    return NormalizedBoundingBox(
      left: l,
      top: t,
      width: w,
      height: h,
    );
  }

  bool get isValid => width > 0 && height > 0;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NormalizedBoundingBox &&
          runtimeType == other.runtimeType &&
          (left - other.left).abs() < 1e-5 &&
          (top - other.top).abs() < 1e-5 &&
          (width - other.width).abs() < 1e-5 &&
          (height - other.height).abs() < 1e-5;

  @override
  int get hashCode => Object.hash(
        (left * 1000).round(),
        (top * 1000).round(),
        (width * 1000).round(),
        (height * 1000).round(),
      );

  @override
  String toString() =>
      'NormalizedBoundingBox(left: ${left.toStringAsFixed(3)}, top: ${top.toStringAsFixed(3)}, width: ${width.toStringAsFixed(3)}, height: ${height.toStringAsFixed(3)})';
}

class SourceBlock {
  const SourceBlock({
    required this.blockId,
    required this.documentId,
    required this.pageId,
    required this.pageNumber,
    required this.orderIndex,
    required this.rawText,
    required this.normalizedText,
    this.boundingBox,
    this.hasValidBox = true,
    this.confidence,
    this.confidenceSource = ConfidenceSource.mlkit,
    this.status = BlockStatus.draft,
    required this.createdAt,
    required this.updatedAt,
  });

  final String blockId;
  final String documentId;
  final String pageId;
  final int pageNumber;
  final int orderIndex;
  final String rawText;
  final String normalizedText;
  final NormalizedBoundingBox? boundingBox;
  final bool hasValidBox;
  final double? confidence;
  final ConfidenceSource confidenceSource;
  final BlockStatus status;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get isEdited => normalizedText.trim() != rawText.trim();
  bool get needsReview => status == BlockStatus.needsReview;
  bool get isUserAdded => status == BlockStatus.userAdded;
  bool get isDeleted => status == BlockStatus.deleted;
  bool get isVerified => status == BlockStatus.verified;

  SourceBlock copyWith({
    String? blockId,
    String? documentId,
    String? pageId,
    int? pageNumber,
    int? orderIndex,
    String? rawText,
    String? normalizedText,
    NormalizedBoundingBox? boundingBox,
    bool? hasValidBox,
    double? confidence,
    ConfidenceSource? confidenceSource,
    BlockStatus? status,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return SourceBlock(
      blockId: blockId ?? this.blockId,
      documentId: documentId ?? this.documentId,
      pageId: pageId ?? this.pageId,
      pageNumber: pageNumber ?? this.pageNumber,
      orderIndex: orderIndex ?? this.orderIndex,
      rawText: rawText ?? this.rawText,
      normalizedText: normalizedText ?? this.normalizedText,
      boundingBox: boundingBox ?? this.boundingBox,
      hasValidBox: hasValidBox ?? this.hasValidBox,
      confidence: confidence ?? this.confidence,
      confidenceSource: confidenceSource ?? this.confidenceSource,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

enum OcrPageStatus {
  notStarted,
  processing,
  completed,
  failed,
}

class OcrPageReview {
  const OcrPageReview({
    required this.pageId,
    required this.documentId,
    required this.pageNumber,
    required this.status,
    this.recognizedLanguage,
    this.rawFullText,
    this.errorMessage,
    required this.blocks,
    required this.updatedAt,
  });

  final String pageId;
  final String documentId;
  final int pageNumber;
  final OcrPageStatus status;
  final String? recognizedLanguage;
  final String? rawFullText;
  final String? errorMessage;
  final List<SourceBlock> blocks;
  final DateTime updatedAt;

  int get totalBlocks => blocks.where((b) => !b.isDeleted).length;
  int get needsReviewBlocks =>
      blocks.where((b) => !b.isDeleted && b.needsReview).length;
  int get verifiedBlocks =>
      blocks.where((b) => !b.isDeleted && b.isVerified).length;
}

class OcrDocumentReview {
  const OcrDocumentReview({
    required this.document,
    required this.pageReviews,
  });

  final ImportedDocument document;
  final List<OcrPageReview> pageReviews;

  int get totalBlocksCount =>
      pageReviews.fold(0, (sum, page) => sum + page.totalBlocks);
  int get needsReviewCount =>
      pageReviews.fold(0, (sum, page) => sum + page.needsReviewBlocks);
  int get verifiedCount =>
      pageReviews.fold(0, (sum, page) => sum + page.verifiedBlocks);
  bool get hasUnreviewedBlocks => needsReviewCount > 0;
  bool get isReadyForGeneration =>
      document.status == ImportedDocumentStatus.readyForGeneration;
}

enum OcrFailureCode {
  pageImageNotFound,
  modelUnavailable,
  noTextFound,
  invalidOutput,
  storageError,
  networkUnavailable,
  serviceQuotaOrTimeout,
  saveFailed,
  unknown,
}

class OcrFailure implements Exception {
  const OcrFailure(this.code, this.message, [this.cause]);

  final OcrFailureCode code;
  final String message;
  final Object? cause;

  @override
  String toString() => cause != null ? '$message Cause: $cause' : message;
}

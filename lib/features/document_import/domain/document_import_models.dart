import 'dart:typed_data';

enum DocumentImageSource { camera, gallery }

enum ImportedDocumentStatus { pendingProcessing }

enum DocumentPrivacy { private }

class ImageCandidate {
  const ImageCandidate({
    required this.bytes,
    required this.source,
    required this.originalPath,
    this.ownsTemporaryFile = false,
  });

  final Uint8List bytes;
  final DocumentImageSource source;
  final String originalPath;
  final bool ownsTemporaryFile;
}

class ImageInspection {
  const ImageInspection({
    required this.mimeType,
    required this.extension,
    required this.width,
    required this.height,
    required this.fileSizeBytes,
    required this.sha256,
    required this.meanLuminance,
    required this.laplacianVariance,
  });

  final String mimeType;
  final String extension;
  final int width;
  final int height;
  final int fileSizeBytes;
  final String sha256;
  final double meanLuminance;
  final double laplacianVariance;

  bool get isLowLight => meanLuminance < 50;
  bool get isLikelyBlurred => laplacianVariance < 100;
  bool get hasQualityWarning => isLowLight || isLikelyBlurred;

  String get qualityCode {
    if (isLowLight && isLikelyBlurred) return 'low_light_and_blurred';
    if (isLowLight) return 'low_light';
    if (isLikelyBlurred) return 'blurred';
    return 'ok';
  }
}

class SourcePage {
  const SourcePage({
    required this.pageId,
    required this.documentId,
    required this.pageNumber,
    required this.source,
    required this.originalRelativePath,
    required this.absolutePath,
    required this.mimeType,
    required this.fileSizeBytes,
    required this.width,
    required this.height,
    required this.sha256,
    required this.qualityCode,
    required this.qualityWarningAccepted,
    required this.createdAt,
  });

  final String pageId;
  final String documentId;
  final int pageNumber;
  final DocumentImageSource source;
  final String originalRelativePath;
  final String absolutePath;
  final String mimeType;
  final int fileSizeBytes;
  final int width;
  final int height;
  final String sha256;
  final String qualityCode;
  final bool qualityWarningAccepted;
  final DateTime createdAt;
}

class ImportedDocument {
  const ImportedDocument({
    required this.documentId,
    required this.title,
    required this.status,
    required this.privacy,
    required this.createdAt,
    required this.updatedAt,
    required this.pages,
  });

  final String documentId;
  final String title;
  final ImportedDocumentStatus status;
  final DocumentPrivacy privacy;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<SourcePage> pages;
}

enum ImportFailureCode {
  unsupportedFormat,
  unreadableImage,
  insufficientStorage,
  cameraUnavailable,
  permissionDenied,
  saveFailed,
  notFound,
  unsupportedPlatform,
}

class ImportFailure implements Exception {
  const ImportFailure(this.code, this.message, [this.cause]);

  final ImportFailureCode code;
  final String message;
  final Object? cause;

  @override
  String toString() => message;
}

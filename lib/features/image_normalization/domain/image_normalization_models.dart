enum PageNormalizationStatus { pending, ready, sourceReady }

class NormalizedPoint {
  const NormalizedPoint(this.x, this.y);

  final double x;
  final double y;

  NormalizedPoint clamped() => NormalizedPoint(
    x.clamp(0.0, 1.0).toDouble(),
    y.clamp(0.0, 1.0).toDouble(),
  );

  @override
  bool operator ==(Object other) =>
      other is NormalizedPoint && other.x == x && other.y == y;

  @override
  int get hashCode => Object.hash(x, y);
}

class CropQuadrilateral {
  const CropQuadrilateral({
    required this.topLeft,
    required this.topRight,
    required this.bottomRight,
    required this.bottomLeft,
  });

  const CropQuadrilateral.fullImage()
    : topLeft = const NormalizedPoint(0, 0),
      topRight = const NormalizedPoint(1, 0),
      bottomRight = const NormalizedPoint(1, 1),
      bottomLeft = const NormalizedPoint(0, 1);

  final NormalizedPoint topLeft;
  final NormalizedPoint topRight;
  final NormalizedPoint bottomRight;
  final NormalizedPoint bottomLeft;

  List<NormalizedPoint> get points => [
    topLeft,
    topRight,
    bottomRight,
    bottomLeft,
  ];

  CropQuadrilateral replacePoint(int index, NormalizedPoint point) {
    final value = point.clamped();
    return CropQuadrilateral(
      topLeft: index == 0 ? value : topLeft,
      topRight: index == 1 ? value : topRight,
      bottomRight: index == 2 ? value : bottomRight,
      bottomLeft: index == 3 ? value : bottomLeft,
    );
  }

  double get area {
    var sum = 0.0;
    for (var index = 0; index < points.length; index++) {
      final current = points[index];
      final next = points[(index + 1) % points.length];
      sum += current.x * next.y - next.x * current.y;
    }
    return sum.abs() / 2;
  }

  bool get isValid {
    if (points.any(
      (point) => point.x < 0 || point.x > 1 || point.y < 0 || point.y > 1,
    )) {
      return false;
    }
    if (area < 0.02) return false;
    var direction = 0;
    for (var index = 0; index < points.length; index++) {
      final a = points[index];
      final b = points[(index + 1) % points.length];
      final c = points[(index + 2) % points.length];
      final cross = (b.x - a.x) * (c.y - b.y) - (b.y - a.y) * (c.x - b.x);
      if (cross.abs() < 1e-9) return false;
      final currentDirection = cross > 0 ? 1 : -1;
      direction = direction == 0 ? currentDirection : direction;
      if (direction != currentDirection) return false;
    }
    return !_segmentsIntersect(points[0], points[1], points[2], points[3]) &&
        !_segmentsIntersect(points[1], points[2], points[3], points[0]);
  }

  static bool _segmentsIntersect(
    NormalizedPoint a,
    NormalizedPoint b,
    NormalizedPoint c,
    NormalizedPoint d,
  ) {
    double cross(NormalizedPoint p, NormalizedPoint q, NormalizedPoint r) =>
        (q.x - p.x) * (r.y - p.y) - (q.y - p.y) * (r.x - p.x);
    final abC = cross(a, b, c);
    final abD = cross(a, b, d);
    final cdA = cross(c, d, a);
    final cdB = cross(c, d, b);
    return abC.sign != abD.sign && cdA.sign != cdB.sign;
  }

  @override
  bool operator ==(Object other) =>
      other is CropQuadrilateral &&
      other.topLeft == topLeft &&
      other.topRight == topRight &&
      other.bottomRight == bottomRight &&
      other.bottomLeft == bottomLeft;

  @override
  int get hashCode => Object.hash(topLeft, topRight, bottomRight, bottomLeft);
}

class NormalizationParameters {
  const NormalizationParameters({
    required this.corners,
    this.rotationDegrees = 0,
    this.contrast = 0,
  });

  final CropQuadrilateral corners;
  final int rotationDegrees;
  final double contrast;

  bool get isValid =>
      corners.isValid &&
      const {0, 90, 180, 270}.contains(rotationDegrees) &&
      contrast >= -0.5 &&
      contrast <= 0.5;

  NormalizationParameters copyWith({
    CropQuadrilateral? corners,
    int? rotationDegrees,
    double? contrast,
  }) => NormalizationParameters(
    corners: corners ?? this.corners,
    rotationDegrees: rotationDegrees ?? this.rotationDegrees,
    contrast: contrast ?? this.contrast,
  );

  @override
  bool operator ==(Object other) =>
      other is NormalizationParameters &&
      other.corners == corners &&
      other.rotationDegrees == rotationDegrees &&
      other.contrast == contrast;

  @override
  int get hashCode => Object.hash(corners, rotationDegrees, contrast);
}

class NormalizedPageAsset {
  const NormalizedPageAsset({
    required this.pageId,
    required this.revision,
    required this.relativePath,
    required this.absolutePath,
    required this.mimeType,
    required this.fileSizeBytes,
    required this.width,
    required this.height,
    required this.sha256,
    required this.parameters,
    required this.updatedAt,
  });

  final String pageId;
  final int revision;
  final String relativePath;
  final String absolutePath;
  final String mimeType;
  final int fileSizeBytes;
  final int width;
  final int height;
  final String sha256;
  final NormalizationParameters parameters;
  final DateTime updatedAt;
}

enum NormalizationFailureCode {
  sourceMissing,
  invalidCrop,
  processingFailed,
  insufficientMemory,
  insufficientStorage,
  saveFailed,
  unsupportedPlatform,
}

class NormalizationFailure implements Exception {
  const NormalizationFailure(this.code, this.message, [this.cause]);

  final NormalizationFailureCode code;
  final String message;
  final Object? cause;

  @override
  String toString() => message;
}

import 'package:flutter_test/flutter_test.dart';
import 'package:memo_mind/features/image_normalization/domain/image_normalization_models.dart';

void main() {
  test('clamps points to image bounds', () {
    expect(
      const NormalizedPoint(-0.2, 1.4).clamped(),
      const NormalizedPoint(0, 1),
    );
  });

  test('accepts a convex crop covering at least two percent', () {
    const crop = CropQuadrilateral(
      topLeft: NormalizedPoint(0.1, 0.1),
      topRight: NormalizedPoint(0.9, 0.12),
      bottomRight: NormalizedPoint(0.85, 0.9),
      bottomLeft: NormalizedPoint(0.12, 0.85),
    );

    expect(crop.isValid, isTrue);
    expect(crop.area, greaterThan(0.02));
  });

  test('rejects self-intersecting and tiny crops', () {
    const selfIntersecting = CropQuadrilateral(
      topLeft: NormalizedPoint(0.1, 0.1),
      topRight: NormalizedPoint(0.9, 0.9),
      bottomRight: NormalizedPoint(0.9, 0.1),
      bottomLeft: NormalizedPoint(0.1, 0.9),
    );
    const tiny = CropQuadrilateral(
      topLeft: NormalizedPoint(0.1, 0.1),
      topRight: NormalizedPoint(0.2, 0.1),
      bottomRight: NormalizedPoint(0.2, 0.2),
      bottomLeft: NormalizedPoint(0.1, 0.2),
    );

    expect(selfIntersecting.isValid, isFalse);
    expect(tiny.isValid, isFalse);
  });

  test('only allows orthogonal rotation and safe contrast', () {
    const crop = CropQuadrilateral.fullImage();

    expect(
      const NormalizationParameters(
        corners: crop,
        rotationDegrees: 270,
        contrast: 0.5,
      ).isValid,
      isTrue,
    );
    expect(
      const NormalizationParameters(corners: crop, rotationDegrees: 45).isValid,
      isFalse,
    );
    expect(
      const NormalizationParameters(corners: crop, contrast: 0.6).isValid,
      isFalse,
    );
  });
}

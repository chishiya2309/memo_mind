import 'dart:isolate';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:image/image.dart' as img;

import '../domain/document_import_models.dart';

class ImageInspector {
  const ImageInspector();

  Future<ImageInspection> inspect(Uint8List bytes) async {
    if (bytes.isEmpty) {
      throw const ImportFailure(
        ImportFailureCode.unreadableImage,
        'Tệp ảnh bị lỗi hoặc không thể đọc.',
      );
    }

    final format = _detectFormat(bytes);
    if (format == null) {
      throw const ImportFailure(
        ImportFailureCode.unsupportedFormat,
        'Định dạng ảnh không được hỗ trợ. Vui lòng chọn ảnh JPEG hoặc PNG.',
      );
    }

    _ImageMetrics? metrics;
    try {
      metrics = await Isolate.run(() => _decodeAndMeasure(bytes));
    } catch (error) {
      throw ImportFailure(
        ImportFailureCode.unreadableImage,
        'Tệp ảnh bị lỗi hoặc không thể đọc.',
        error,
      );
    }
    if (metrics == null) {
      throw const ImportFailure(
        ImportFailureCode.unreadableImage,
        'Tệp ảnh bị lỗi hoặc không thể đọc.',
      );
    }

    return ImageInspection(
      mimeType: format.mimeType,
      extension: format.extension,
      width: metrics.width,
      height: metrics.height,
      fileSizeBytes: bytes.length,
      sha256: sha256.convert(bytes).toString(),
      meanLuminance: metrics.meanLuminance,
      laplacianVariance: metrics.laplacianVariance,
    );
  }

  _ImageFormat? _detectFormat(Uint8List bytes) {
    if (bytes.length >= 3 &&
        bytes[0] == 0xff &&
        bytes[1] == 0xd8 &&
        bytes[2] == 0xff) {
      return const _ImageFormat('image/jpeg', 'jpg');
    }
    const png = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a];
    if (bytes.length >= png.length) {
      for (var index = 0; index < png.length; index++) {
        if (bytes[index] != png[index]) return null;
      }
      return const _ImageFormat('image/png', 'png');
    }
    return null;
  }
}

class _ImageFormat {
  const _ImageFormat(this.mimeType, this.extension);

  final String mimeType;
  final String extension;
}

class _ImageMetrics {
  const _ImageMetrics({
    required this.width,
    required this.height,
    required this.meanLuminance,
    required this.laplacianVariance,
  });

  final int width;
  final int height;
  final double meanLuminance;
  final double laplacianVariance;
}

_ImageMetrics? _decodeAndMeasure(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null || decoded.width <= 0 || decoded.height <= 0) return null;

  final sample = decoded.width > 512 || decoded.height > 512
      ? img.copyResize(
          decoded,
          width: decoded.width >= decoded.height ? 512 : null,
          height: decoded.height > decoded.width ? 512 : null,
          interpolation: img.Interpolation.average,
        )
      : decoded;
  final width = sample.width;
  final height = sample.height;
  final luminance = List<double>.filled(width * height, 0);
  var sum = 0.0;
  for (final pixel in sample) {
    final value =
        0.2126 * pixel.r.toDouble() +
        0.7152 * pixel.g.toDouble() +
        0.0722 * pixel.b.toDouble();
    luminance[pixel.y * width + pixel.x] = value;
    sum += value;
  }

  var laplacianSum = 0.0;
  var laplacianSquareSum = 0.0;
  var count = 0;
  for (var y = 1; y < height - 1; y++) {
    for (var x = 1; x < width - 1; x++) {
      final center = luminance[y * width + x];
      final laplacian =
          luminance[(y - 1) * width + x] +
          luminance[(y + 1) * width + x] +
          luminance[y * width + x - 1] +
          luminance[y * width + x + 1] -
          4 * center;
      laplacianSum += laplacian;
      laplacianSquareSum += laplacian * laplacian;
      count++;
    }
  }
  final meanLaplacian = count == 0 ? 0 : laplacianSum / count;
  final variance = count == 0
      ? 0.0
      : (laplacianSquareSum / count) - meanLaplacian * meanLaplacian;
  return _ImageMetrics(
    width: decoded.width,
    height: decoded.height,
    meanLuminance: sum / (width * height),
    laplacianVariance: variance,
  );
}

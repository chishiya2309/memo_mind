import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:memo_mind/features/document_import/application/image_inspector.dart';
import 'package:memo_mind/features/document_import/domain/document_import_models.dart';

void main() {
  const inspector = ImageInspector();

  img.Image checkerboard({int size = 64}) {
    final image = img.Image(width: size, height: size);
    for (final pixel in image) {
      final bright = ((pixel.x ~/ 4) + (pixel.y ~/ 4)).isEven;
      final value = bright ? 240 : 40;
      pixel
        ..r = value
        ..g = value
        ..b = value
        ..a = 255;
    }
    return image;
  }

  test('accepts JPEG by signature and reports dimensions and hash', () async {
    final bytes = Uint8List.fromList(img.encodeJpg(checkerboard()));

    final result = await inspector.inspect(bytes);

    expect(result.mimeType, 'image/jpeg');
    expect(result.extension, 'jpg');
    expect(result.width, 64);
    expect(result.height, 64);
    expect(result.fileSizeBytes, bytes.length);
    expect(result.sha256, sha256.convert(bytes).toString());
    expect(result.isLowLight, isFalse);
  });

  test('accepts PNG and does not alter source bytes', () async {
    final bytes = Uint8List.fromList(img.encodePng(checkerboard(size: 32)));
    final before = Uint8List.fromList(bytes);

    final result = await inspector.inspect(bytes);

    expect(result.mimeType, 'image/png');
    expect(result.extension, 'png');
    expect(bytes, orderedEquals(before));
  });

  test('rejects unsupported signatures and corrupt JPEG data', () async {
    await expectLater(
      inspector.inspect(Uint8List.fromList([0x52, 0x49, 0x46, 0x46])),
      throwsA(
        isA<ImportFailure>().having(
          (error) => error.code,
          'code',
          ImportFailureCode.unsupportedFormat,
        ),
      ),
    );
    await expectLater(
      inspector.inspect(Uint8List.fromList([0xff, 0xd8, 0xff, 0x00])),
      throwsA(
        isA<ImportFailure>().having(
          (error) => error.code,
          'code',
          ImportFailureCode.unreadableImage,
        ),
      ),
    );
  });

  test('flags a dark flat image without rejecting it', () async {
    final dark = img.Image(width: 32, height: 32)
      ..clear(img.ColorRgb8(5, 5, 5));
    final result = await inspector.inspect(
      Uint8List.fromList(img.encodePng(dark)),
    );

    expect(result.isLowLight, isTrue);
    expect(result.isLikelyBlurred, isTrue);
    expect(result.qualityCode, 'low_light_and_blurred');
  });
}

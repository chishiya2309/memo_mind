import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../domain/document_import_models.dart';

class GalleryImagePicker {
  GalleryImagePicker({ImagePicker? picker}) : _picker = picker ?? ImagePicker();

  final ImagePicker _picker;

  Future<ImageCandidate?> pickImage() async {
    try {
      final file = await _picker.pickImage(source: ImageSource.gallery);
      return file == null ? null : await _toCandidate(file);
    } on PlatformException catch (error) {
      throw ImportFailure(
        ImportFailureCode.permissionDenied,
        'Không thể truy cập thư viện ảnh. Hãy kiểm tra quyền của ứng dụng.',
        error,
      );
    }
  }

  Future<ImageCandidate?> retrieveLostImage() async {
    final response = await _picker.retrieveLostData();
    if (response.isEmpty) return null;
    final files = response.files;
    if (files != null && files.isNotEmpty) return _toCandidate(files.first);
    if (response.exception != null) {
      throw ImportFailure(
        ImportFailureCode.unreadableImage,
        'Tệp ảnh bị lỗi hoặc không thể đọc.',
        response.exception,
      );
    }
    return null;
  }

  Future<ImageCandidate> _toCandidate(XFile file) async => ImageCandidate(
    bytes: await file.readAsBytes(),
    source: DocumentImageSource.gallery,
    originalPath: file.path,
  );
}

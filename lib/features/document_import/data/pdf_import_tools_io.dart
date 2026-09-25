import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as image;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:uuid/uuid.dart';

import '../application/pdf_import_services.dart';
import '../domain/document_import_models.dart';

class DevicePdfCandidatePicker implements PdfCandidatePicker {
  DevicePdfCandidatePicker({Uuid? uuid}) : _uuid = uuid ?? const Uuid();

  static const _storageChannel = MethodChannel('memo_mind/storage');
  static const _reserveBytes = 10 * 1024 * 1024;

  final Uuid _uuid;

  @override
  Future<PdfCandidate?> pickPdf() async {
    if (!Platform.isAndroid) {
      throw const ImportFailure(
        ImportFailureCode.unsupportedPlatform,
        'Nhập PDF hiện chỉ được hỗ trợ trên Android.',
      );
    }

    PlatformFile? picked;
    try {
      picked = await FilePicker.pickFile(
        dialogTitle: 'Chọn tệp PDF',
        type: FileType.custom,
        allowedExtensions: const ['pdf'],
      );
    } on MissingPluginException catch (error) {
      throw ImportFailure(
        ImportFailureCode.pickerUnavailable,
        'Không thể mở trình quản lý tệp. Vui lòng thử lại.',
        error,
      );
    } on PlatformException catch (error) {
      throw ImportFailure(
        ImportFailureCode.pickerUnavailable,
        'Không thể mở trình quản lý tệp. Vui lòng thử lại.',
        error,
      );
    }
    if (picked == null) return null;
    if (p.extension(picked.name).toLowerCase() != '.pdf') {
      throw const ImportFailure(
        ImportFailureCode.unsupportedFormat,
        'Định dạng tệp không được hỗ trợ. Vui lòng chọn tệp PDF.',
      );
    }

    final operationId = _uuid.v4();
    final cache = await getTemporaryDirectory();
    final reportedLength = picked.lengthSync() ?? await picked.length();
    if (reportedLength != null) {
      try {
        final available = await _storageChannel.invokeMethod<int>(
          'getAvailableBytes',
          {'path': cache.path},
        );
        if (available != null && available < reportedLength + _reserveBytes) {
          throw const ImportFailure(
            ImportFailureCode.insufficientStorage,
            'Thiết bị không đủ dung lượng. Vui lòng giải phóng bộ nhớ và thử lại.',
          );
        }
      } on MissingPluginException {
        // The write below remains authoritative in test hosts.
      }
    }
    final directory = Directory(
      p.join(cache.path, 'document_import', 'pdf-$operationId'),
    );
    final destination = File(p.join(directory.path, 'selected.pdf'));
    IOSink? sink;
    try {
      await directory.create(recursive: true);
      sink = destination.openWrite();
      await sink.addStream(picked.readAsByteStream());
      await sink.flush();
      await sink.close();
      sink = null;
      final length = await destination.length();
      if (length == 0) {
        throw const ImportFailure(
          ImportFailureCode.invalidPdf,
          'Tệp PDF bị lỗi hoặc không thể đọc.',
        );
      }
      return PdfCandidate(
        temporaryPath: destination.path,
        originalName: picked.name,
        fileSizeBytes: length,
        sha256: await _digestFile(destination),
      );
    } on ImportFailure {
      await sink?.close();
      await _deleteDirectory(directory);
      rethrow;
    } on FileSystemException catch (error) {
      await sink?.close();
      await _deleteDirectory(directory);
      if (error.osError?.errorCode == 28) {
        throw ImportFailure(
          ImportFailureCode.insufficientStorage,
          'Thiết bị không đủ dung lượng. Vui lòng giải phóng bộ nhớ và thử lại.',
          error,
        );
      }
      throw ImportFailure(
        ImportFailureCode.permissionDenied,
        'Không thể truy cập tệp đã chọn. Vui lòng cấp quyền hoặc chọn tệp khác.',
        error,
      );
    } on PlatformException catch (error) {
      await sink?.close();
      await _deleteDirectory(directory);
      throw ImportFailure(
        ImportFailureCode.permissionDenied,
        'Không thể truy cập tệp đã chọn. Vui lòng cấp quyền hoặc chọn tệp khác.',
        error,
      );
    } catch (error) {
      await sink?.close();
      await _deleteDirectory(directory);
      throw ImportFailure(
        ImportFailureCode.notFound,
        'Không tìm thấy tệp đã chọn.',
        error,
      );
    }
  }
}

class DevicePdfDocumentProcessor implements PdfDocumentProcessor {
  PdfDocument? _document;
  String? _openPath;
  Future<void> _renderQueue = Future<void>.value();

  @override
  Future<PdfInspection> inspect(PdfCandidate candidate) async {
    await _closeDocument();
    final file = File(candidate.temporaryPath);
    if (!await file.exists()) {
      throw const ImportFailure(
        ImportFailureCode.notFound,
        'Không tìm thấy tệp đã chọn.',
      );
    }
    if (p.extension(candidate.originalName).toLowerCase() != '.pdf' ||
        !await _hasPdfSignature(file)) {
      throw const ImportFailure(
        ImportFailureCode.unsupportedFormat,
        'Định dạng tệp không được hỗ trợ. Vui lòng chọn tệp PDF.',
      );
    }

    try {
      await pdfrxFlutterInitialize();
      final document = await PdfDocument.openFile(
        candidate.temporaryPath,
        passwordProvider: createSimplePasswordProvider(null),
      );
      if (document.isEncrypted) {
        await document.dispose();
        throw const ImportFailure(
          ImportFailureCode.passwordProtected,
          'PDF có mật khẩu chưa được hỗ trợ. Vui lòng mở khóa tệp và thử lại.',
        );
      }
      if (document.pages.isEmpty) {
        await document.dispose();
        throw const ImportFailure(
          ImportFailureCode.noPages,
          'PDF không chứa trang hợp lệ.',
        );
      }
      _document = document;
      _openPath = candidate.temporaryPath;
      return PdfInspection(
        pageCount: document.pages.length,
        pageSizes: document.pages
            .map((page) => PdfPageSize(width: page.width, height: page.height))
            .toList(growable: false),
        isEncrypted: false,
      );
    } on ImportFailure {
      rethrow;
    } on PdfPasswordException catch (error) {
      throw ImportFailure(
        ImportFailureCode.passwordProtected,
        'PDF có mật khẩu chưa được hỗ trợ. Vui lòng mở khóa tệp và thử lại.',
        error,
      );
    } on PdfException catch (error) {
      throw ImportFailure(
        ImportFailureCode.corruptPdf,
        'Tệp PDF bị lỗi hoặc không thể đọc.',
        error,
      );
    } catch (error) {
      throw ImportFailure(
        ImportFailureCode.corruptPdf,
        'Tệp PDF bị lỗi hoặc không thể đọc.',
        error,
      );
    }
  }

  @override
  Future<Uint8List> renderThumbnail(PdfCandidate candidate, int pageNumber) =>
      _serializeRender(() async {
        final document = await _requireDocument(candidate);
        if (pageNumber < 1 || pageNumber > document.pages.length) {
          throw StateError('Invalid PDF page $pageNumber');
        }
        try {
          return await _renderPng(document.pages[pageNumber - 1], 360);
        } catch (error) {
          throw ImportFailure(
            ImportFailureCode.pageRenderFailed,
            'Không thể tạo dữ liệu cho trang $pageNumber.',
            error,
          );
        }
      });

  @override
  Future<List<RenderedPdfPage>> renderSelectedPages(
    PdfCandidate candidate,
    List<int> pageNumbers,
  ) => _serializeRender(() async {
    final ordered = pageNumbers.toSet().toList()..sort();
    if (ordered.isEmpty || ordered.length > 10) {
      throw const ImportFailure(
        ImportFailureCode.pageRenderFailed,
        'Vui lòng chọn từ 1 đến 10 trang để tiếp tục.',
      );
    }
    final document = await _requireDocument(candidate);
    final outputDirectory = Directory(
      p.join(File(candidate.temporaryPath).parent.path, 'rendered'),
    );
    await outputDirectory.create(recursive: true);
    final results = <RenderedPdfPage>[];
    try {
      for (final pageNumber in ordered) {
        if (pageNumber < 1 || pageNumber > document.pages.length) {
          throw ImportFailure(
            ImportFailureCode.pageRenderFailed,
            'Không thể tạo dữ liệu cho trang $pageNumber.',
          );
        }
        final bytes = await _renderPng(
          document.pages[pageNumber - 1],
          2600,
          targetDpi: 200,
        );
        final decoded = image.decodePng(bytes);
        if (decoded == null) {
          throw StateError('Rendered page is not a valid PNG');
        }
        final output = File(
          p.join(outputDirectory.path, 'page-$pageNumber.png'),
        );
        await output.writeAsBytes(bytes, flush: true);
        results.add(
          RenderedPdfPage(
            originalPageNumber: pageNumber,
            temporaryPath: output.path,
            fileSizeBytes: bytes.length,
            width: decoded.width,
            height: decoded.height,
            sha256: sha256.convert(bytes).toString(),
          ),
        );
      }
      return results;
    } on ImportFailure {
      await _deleteDirectory(outputDirectory);
      rethrow;
    } catch (error) {
      await _deleteDirectory(outputDirectory);
      final failedPage = ordered.length > results.length
          ? ordered[results.length]
          : ordered.last;
      throw ImportFailure(
        ImportFailureCode.pageRenderFailed,
        'Không thể tạo dữ liệu cho trang $failedPage.',
        error,
      );
    }
  });

  Future<T> _serializeRender<T>(Future<T> Function() action) {
    final completer = Completer<T>();
    _renderQueue = _renderQueue.then((_) async {
      try {
        completer.complete(await action());
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }

  Future<PdfDocument> _requireDocument(PdfCandidate candidate) async {
    if (_document == null || _openPath != candidate.temporaryPath) {
      await inspect(candidate);
    }
    return _document!;
  }

  Future<Uint8List> _renderPng(
    PdfPage page,
    double maxLongEdge, {
    double? targetDpi,
  }) async {
    final scale = targetDpi == null ? 1.0 : targetDpi / 72.0;
    var width = page.width * scale;
    var height = page.height * scale;
    final longEdge = width > height ? width : height;
    if (longEdge > maxLongEdge) {
      final fit = maxLongEdge / longEdge;
      width *= fit;
      height *= fit;
    } else if (targetDpi == null && longEdge > 0) {
      final fit = maxLongEdge / longEdge;
      width *= fit;
      height *= fit;
    }
    final rendered = await page.render(
      fullWidth: width.clamp(1, maxLongEdge),
      fullHeight: height.clamp(1, maxLongEdge),
      backgroundColor: 0xffffffff,
    );
    if (rendered == null) throw StateError('PDF renderer returned no image');
    try {
      final converted = image.Image.fromBytes(
        width: rendered.width,
        height: rendered.height,
        bytes: rendered.pixels.buffer,
        bytesOffset: rendered.pixels.offsetInBytes,
        numChannels: 4,
        order: image.ChannelOrder.bgra,
      );
      return Uint8List.fromList(image.encodePng(converted, level: 6));
    } finally {
      rendered.dispose();
    }
  }

  @override
  Future<void> dispose() async {
    await _renderQueue;
    await _closeDocument();
  }

  Future<void> _closeDocument() async {
    final document = _document;
    _document = null;
    _openPath = null;
    await document?.dispose();
  }

  Future<bool> _hasPdfSignature(File file) async {
    final length = await file.length();
    final bytesToRead = length < 1024 ? length : 1024;
    final handle = await file.open();
    try {
      final bytes = await handle.read(bytesToRead);
      const signature = [0x25, 0x50, 0x44, 0x46, 0x2d];
      for (var index = 0; index <= bytes.length - signature.length; index++) {
        var matches = true;
        for (var offset = 0; offset < signature.length; offset++) {
          if (bytes[index + offset] != signature[offset]) {
            matches = false;
            break;
          }
        }
        if (matches) return true;
      }
      return false;
    } finally {
      await handle.close();
    }
  }
}

Future<String> _digestFile(File file) async =>
    (await sha256.bind(file.openRead()).first).toString();

Future<void> _deleteDirectory(Directory directory) async {
  try {
    if (await directory.exists()) await directory.delete(recursive: true);
  } on FileSystemException {
    // Startup recovery will retry.
  }
}

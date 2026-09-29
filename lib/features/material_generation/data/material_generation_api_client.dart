import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import '../../ocr_editor/domain/ocr_models.dart';
import '../domain/material_generation_models.dart';

class MaterialGenerationApiClient {
  MaterialGenerationApiClient({
    String? baseUrl,
    http.Client? httpClient,
  })  : _baseUrl = baseUrl ??
            const String.fromEnvironment(
              'BACKEND_BASE_URL',
              defaultValue: 'https://api.leaselinkconnect.me',
            ),
        _client = httpClient ?? http.Client();

  final String _baseUrl;
  final http.Client _client;
  static const _uuid = Uuid();

  Future<FlashcardGenerationResult> generateFlashcards({
    required String documentId,
    required FlashcardFormat format,
    required int desiredCount,
    required List<SourceBlock> sourceBlocks,
  }) async {
    final cleanBase = _baseUrl.trim().endsWith('/')
        ? _baseUrl.trim().substring(0, _baseUrl.trim().length - 1)
        : _baseUrl.trim();

    final candidateBases = <String>[cleanBase];
    if (cleanBase.contains('10.0.2.2')) {
      candidateBases.add(cleanBase.replaceAll('10.0.2.2', '127.0.0.1'));
    }

    final payload = jsonEncode({
      'documentId': documentId,
      'format': format.name,
      'desiredCount': desiredCount,
      'sourceBlocks': sourceBlocks
          .map((b) => {
                'blockId': b.blockId,
                'pageNumber': b.pageNumber,
                'normalizedText': b.normalizedText,
              })
          .toList(),
    });

    dynamic lastNetworkError;

    for (final base in candidateBases) {
      final endpointPath = base.endsWith('/api')
          ? '/v1/materials/flashcards/generate'
          : '/api/v1/materials/flashcards/generate';
      final uri = Uri.parse('$base$endpointPath');

      try {
        final response = await _client
            .post(
              uri,
              headers: {'Content-Type': 'application/json'},
              body: payload,
            )
            .timeout(const Duration(seconds: 90));

        final body = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;

        if (response.statusCode == 200) {
          final rawCards = body['cards'] as List<dynamic>? ?? [];
          final totalGenerated = (body['totalGenerated'] as num?)?.toInt() ?? rawCards.length;
          final validCount = (body['validCount'] as num?)?.toInt() ?? rawCards.length;
          final discardedCount = (body['discardedCount'] as num?)?.toInt() ?? 0;
          final warnings = (body['warnings'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [];

          final cards = rawCards.map((c) {
            final map = c as Map<String, dynamic>;
            final formatStr = map['format'] as String? ?? 'qa';
            return FlashcardDraft(
              id: _uuid.v4(),
              format: formatStr == 'cloze' ? FlashcardFormat.cloze : FlashcardFormat.qa,
              question: map['question'] as String? ?? '',
              answer: map['answer'] as String? ?? '',
              sourcePage: (map['sourcePage'] as num?)?.toInt() ?? 1,
              sourceBlockId: map['sourceBlockId'] as String? ?? '',
              sourceQuote: map['sourceQuote'] as String? ?? '',
              confidence: (map['confidence'] as num?)?.toDouble(),
              status: DraftCardStatus.pending,
            );
          }).toList();

          return FlashcardGenerationResult(
            cards: cards,
            totalGenerated: totalGenerated,
            validCount: validCount,
            discardedCount: discardedCount,
            warnings: warnings,
          );
        } else if (response.statusCode == 413) {
          throw MaterialGenerationFailure(
            MaterialGenerationFailureCode.payloadTooLarge,
            body['message'] as String? ?? 'Nội dung được chọn vượt quá giới hạn xử lý một lượt.',
          );
        } else if (response.statusCode == 429) {
          throw MaterialGenerationFailure(
            MaterialGenerationFailureCode.serviceQuotaOrTimeout,
            body['message'] as String? ?? 'Dịch vụ AI tạm thời đã đạt giới hạn sử dụng hoặc quá tải.',
          );
        } else if (response.statusCode == 503) {
          throw MaterialGenerationFailure(
            MaterialGenerationFailureCode.backendNotConfigured,
            body['message'] as String? ?? 'Tính năng AI chưa được cấu hình API Key trên máy chủ.',
          );
        } else if (response.statusCode == 422) {
          throw MaterialGenerationFailure(
            MaterialGenerationFailureCode.noValidCards,
            body['message'] as String? ?? 'Không có flashcard nào hợp lệ từ nội dung đã chọn.',
          );
        } else {
          throw MaterialGenerationFailure(
            MaterialGenerationFailureCode.unknown,
            body['message'] as String? ?? 'Đã xảy ra lỗi khi tạo flashcard (mã ${response.statusCode}).',
          );
        }
      } on http.ClientException catch (e) {
        lastNetworkError = e;
        continue;
      } on TimeoutException catch (e) {
        lastNetworkError = e;
        continue;
      } catch (e) {
        if (e is MaterialGenerationFailure) rethrow;
        throw MaterialGenerationFailure(
          MaterialGenerationFailureCode.unknown,
          'Lỗi không xác định trong quá trình sinh học liệu.',
          e,
        );
      }
    }

    if (lastNetworkError is TimeoutException) {
      throw MaterialGenerationFailure(
        MaterialGenerationFailureCode.serviceQuotaOrTimeout,
        'Yêu cầu đến dịch vụ AI bị quá thời gian chờ. Vui lòng kiểm tra kết nối mạng và thử lại.',
        lastNetworkError,
      );
    }

    throw MaterialGenerationFailure(
      MaterialGenerationFailureCode.networkUnavailable,
      'Không thể kết nối đến Backend AI MemoMind ($cleanBase).\n'
      '• Nếu deploy AWS EC2: Vui lòng kiểm tra BACKEND_BASE_URL và trạng thái máy chủ.\n'
      '• Nếu chạy cục bộ trên điện thoại thật: Chạy "adb reverse tcp:8080 tcp:8080" và "cd functions; npm start".\n'
      '• Nếu chạy trên máy ảo: Chạy "cd functions; npm start".',
      lastNetworkError,
    );
  }
}

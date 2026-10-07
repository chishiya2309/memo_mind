import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import '../../../core/network/backend_api_client.dart';
import '../../ocr_editor/domain/ocr_models.dart';
import '../domain/material_generation_models.dart';
import '../domain/source_reference_resolver.dart';

class MaterialGenerationApiClient {
  MaterialGenerationApiClient({String? baseUrl, http.Client? httpClient})
    : _backend = BackendApiClient(baseUrl: baseUrl, httpClient: httpClient);
  final BackendApiClient _backend;
  Future<MaterialGenerationResult> generateMaterials({
    required String documentId,
    required Set<CardType> types,
    QuantityMode quantityMode = QuantityMode.auto,
    int? desiredCount,
    required List<SourceBlock> sourceBlocks,
  }) async {
    try {
      final body = await _backend.post('materials/generate', {
        'documentId': documentId,
        'reviewPolicy': 'user_review',
        'types': types.map((t) => t.wireName).toList(),
        'quantityMode': quantityMode.name,
        if (quantityMode == QuantityMode.manual) 'desiredCount': desiredCount,
        'sourceBlocks': sourceBlocks
            .map(
              (b) => {
                'blockId': b.blockId,
                'documentId': b.documentId,
                'pageNumber': b.pageNumber,
                'normalizedText': b.normalizedText,
              },
            )
            .toList(),
      });
      if (body['reviewPolicy'] != 'user_review') {
        throw const MaterialGenerationFailure(
          MaterialGenerationFailureCode.backendNotConfigured,
          'Dịch vụ AI cần được cập nhật để hiển thị toàn bộ kết quả. Vui lòng cập nhật backend.',
        );
      }
      final raw = body['cards'];
      if (raw is! List || body['totalGenerated'] != raw.length) {
        throw const FormatException('Thống kê kết quả không nhất quán.');
      }
      final cards = <MaterialDraft>[
        for (final entry in raw)
          MaterialDraft.fromReviewJson(
            const Uuid().v4(),
            entry is Map<String, dynamic> && entry.containsKey('card')
                ? entry['card']
                : entry,
            requestedTypes: types,
          ),
      ];
      return MaterialGenerationResult(
        cards: List.unmodifiable(
          cards.map(
            (card) => SourceReferenceResolver.resolveDraft(
              card,
              documentId,
              sourceBlocks,
            ),
          ),
        ),
        totalGenerated: cards.length,
        validCount: cards.length,
        discardedCount: 0,
        warnings: [
          for (final w in body['warnings'] as List? ?? [])
            if (w is String) w,
        ],
      );
    } on BackendApiException catch (e) {
      throw MaterialGenerationFailure(switch (e.code) {
        'network_unavailable' =>
          MaterialGenerationFailureCode.networkUnavailable,
        'provider_timeout' || 'provider_quota' || 'rate_limit_exceeded' =>
          MaterialGenerationFailureCode.serviceQuotaOrTimeout,
        'backend_not_configured' =>
          MaterialGenerationFailureCode.backendNotConfigured,
        'invalid_request' => MaterialGenerationFailureCode.invalidRequest,
        'payload_too_large' => MaterialGenerationFailureCode.payloadTooLarge,
        'no_valid_cards' => MaterialGenerationFailureCode.noValidCards,
        'invalid_llm_output' || 'invalid_provider_response' =>
          MaterialGenerationFailureCode.invalidOutput,
        _ => MaterialGenerationFailureCode.unknown,
      }, e.message);
    } on MaterialGenerationFailure {
      rethrow;
    } on Object catch (e) {
      throw MaterialGenerationFailure(
        MaterialGenerationFailureCode.invalidOutput,
        'Dịch vụ AI trả dữ liệu không hợp lệ.',
        e,
      );
    }
  }
}

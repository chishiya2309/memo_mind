import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import '../../../core/network/backend_api_client.dart';
import '../../ocr_editor/domain/ocr_models.dart';
import '../domain/material_generation_models.dart';
import '../domain/material_validator.dart';

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
      final raw = body['cards'] as List<dynamic>;
      final blocks = {for (final b in sourceBlocks) b.blockId: b};
      final cards = <MaterialDraft>[];
      var localDiscarded = 0;
      final seen = <String>{};
      for (final value in raw) {
        try {
          final card = MaterialDraft.fromJson(
            const Uuid().v4(),
            value as Map<String, dynamic>,
          );
          if (!types.contains(card.type)) {
            throw const FormatException('Loại không được yêu cầu.');
          }
          MaterialValidator.validate(
            card,
            sourceBlock: blocks[card.sourceBlockId],
            documentId: documentId,
          );
          if (!seen.add(
                MaterialValidator.normalize(card.front).toLowerCase(),
              ) ||
              cards.length >=
                  (quantityMode == QuantityMode.auto ? 20 : desiredCount!)) {
            throw const FormatException('Thẻ trùng hoặc quá giới hạn.');
          }
          cards.add(card);
        } on Object {
          localDiscarded++;
        }
      }
      if (cards.isEmpty) {
        throw const MaterialGenerationFailure(
          MaterialGenerationFailureCode.noValidCards,
          'Không có học liệu đạt kiểm tra nguồn và cấu trúc.',
        );
      }
      final warnings = <String>[];
      for (final w in body['warnings'] as List<dynamic>? ?? []) {
        if (w is! Map<String, dynamic>) continue;
        final count = w['count'];
        warnings.add(switch (w['code']) {
          'missing_type' =>
            'Chưa có thẻ ${CardType.fromWire(w['type'] as String).displayName} đạt yêu cầu.',
          'fewer_than_requested' =>
            'Kết quả ít hơn số lượng mong muốn $count thẻ.',
          'duplicate' => 'Đã loại $count thẻ trùng nội dung.',
          'count_limit' => 'Đã giữ số thẻ trong giới hạn yêu cầu.',
          _ => 'Đã loại $count thẻ không đạt kiểm tra nguồn hoặc cấu trúc.',
        });
      }
      if (localDiscarded > 0) {
        warnings.add(
          'Ứng dụng loại thêm $localDiscarded thẻ không đạt kiểm tra.',
        );
      }
      final serverDiscarded = body['discardedCount'] as int;
      if (serverDiscarded < 0 ||
          body['validCount'] != raw.length ||
          body['totalGenerated'] != raw.length + serverDiscarded) {
        throw const FormatException('Thống kê kết quả không nhất quán.');
      }
      return MaterialGenerationResult(
        cards: List.unmodifiable(cards),
        totalGenerated: raw.length + serverDiscarded,
        validCount: cards.length,
        discardedCount: serverDiscarded + localDiscarded,
        warnings: warnings,
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

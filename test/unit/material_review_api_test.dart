import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:memo_mind/features/material_generation/data/material_generation_api_client.dart';
import 'package:memo_mind/features/material_generation/domain/material_generation_models.dart';
import 'package:memo_mind/features/material_generation/domain/material_validator.dart';
import 'package:memo_mind/features/ocr_editor/domain/ocr_models.dart';

void main() {
  final block = SourceBlock(
    blockId: 'b',
    documentId: 'doc',
    pageId: 'p',
    pageNumber: 1,
    orderIndex: 0,
    rawText: 'Nguồn gốc',
    normalizedText: 'Nguồn gốc',
    status: BlockStatus.verified,
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
  );
  final basic = <String, Object?>{
    'type': 'BASIC',
    'front': 'Câu hỏi?',
    'back': 'Đáp án',
    'sourceBlockId': 'b',
    'sourcePage': 1,
    'sourceQuote': 'Không khớp',
    'confidence': null,
    'options': null,
    'correctOptionId': null,
    'explanation': null,
  };

  test('API retains every item, including duplicates, surplus and malformed output', () async {
    final raw = [
      basic,
      basic,
      {...basic, 'type': 'MCQ', 'options': []},
      null,
      'broken',
      {...basic, 'type': 'UNKNOWN'},
    ];
    final client = MaterialGenerationApiClient(
      baseUrl: 'https://example.test',
      httpClient: MockClient((request) async {
        expect(jsonDecode(request.body)['reviewPolicy'], 'user_review');
        return http.Response(
          jsonEncode({
            'reviewPolicy': 'user_review',
            'totalGenerated': raw.length,
            'cards': [
              for (var i = 0; i < raw.length; i++)
                {'id': '$i', 'card': raw[i], 'issues': []},
            ],
            'warnings': ['AI trả thêm thẻ.'],
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );
    final result = await client.generateMaterials(
      documentId: 'doc',
      types: {CardType.basic},
      quantityMode: QuantityMode.manual,
      desiredCount: 1,
      sourceBlocks: [block],
    );
    expect(result.cards.length, raw.length);
    expect(result.cards.map((c) => c.id).toSet().length, raw.length);
    expect(result.discardedCount, 0);
    final issues = MaterialValidator.issues(
      result.cards.first,
      sourceBlock: block,
      documentId: 'doc',
      cards: result.cards,
    );
    expect(
      issues.map((i) => i.code),
      containsAll(['duplicate', 'unsupported_quote']),
    );
    expect(issues.any((i) => i.isError), isFalse);
    expect(
      MaterialValidator.errors(result.cards[2], requireSource: false),
      contains('options'),
    );
    expect(result.cards[3].rawResponse, 'null');
    expect(result.cards[4].rawResponse, '"broken"');
    final repaired = result.cards[5].copyWith(
      type: CardType.basic,
      clearRawResponse: true,
    );
    expect(MaterialValidator.errors(repaired, requireSource: false), isEmpty);
    expect(
      MaterialValidator.issues(
        repaired.copyWith(front: 'Câu mới'),
        sourceBlock: block,
        documentId: 'doc',
        cards: result.cards,
      ).any((i) => i.code == 'duplicate'),
      isFalse,
    );
  });

  test('old backend cannot silently claim all results were returned', () async {
    final client = MaterialGenerationApiClient(
      baseUrl: 'https://example.test',
      httpClient: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'cards': [basic],
            'validCount': 1,
            'totalGenerated': 2,
            'discardedCount': 1,
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        ),
      ),
    );
    await expectLater(
      client.generateMaterials(
        documentId: 'doc',
        types: {CardType.basic},
        sourceBlocks: [block],
      ),
      throwsA(
        isA<MaterialGenerationFailure>().having(
          (e) => e.code,
          'code',
          MaterialGenerationFailureCode.backendNotConfigured,
        ),
      ),
    );
  });

  test(
    'source issues never block valid content; malformed MCQ still needs repair',
    () {
      final draft = MaterialDraft.fromReviewJson('id', basic);
      expect(
        MaterialValidator.issues(
          draft,
          sourceBlock: null,
          documentId: 'doc',
        ).single.code,
        'source_block_mismatch',
      );
      expect(MaterialValidator.errors(draft, requireSource: false), isEmpty);
      final mcq = MaterialDraft.fromReviewJson('mcq', {
        ...basic,
        'type': 'MCQ',
        'options': [
          {'optionId': 'A', 'text': 'Một'},
        ],
        'correctOptionId': 'Z',
      });
      expect(
        MaterialValidator.errors(mcq, requireSource: false).keys,
        containsAll(['options', 'correctOptionId', 'explanation']),
      );
    },
  );

  test(
    'network and timeout errors remain actionable without losing input',
    () async {
      for (final code in ['provider_timeout', 'provider_quota']) {
        final client = MaterialGenerationApiClient(
          baseUrl: 'https://example.test',
          httpClient: MockClient(
            (_) async => http.Response(
              jsonEncode({'error': code}),
              code == 'provider_timeout' ? 504 : 429,
            ),
          ),
        );
        await expectLater(
          client.generateMaterials(
            documentId: 'doc',
            types: {CardType.basic},
            sourceBlocks: [block],
          ),
          throwsA(
            isA<MaterialGenerationFailure>().having(
              (e) => e.code,
              'code',
              MaterialGenerationFailureCode.serviceQuotaOrTimeout,
            ),
          ),
        );
      }
      final client = MaterialGenerationApiClient(
        baseUrl: 'https://example.test',
        httpClient: MockClient(
          (_) async => throw http.ClientException('offline'),
        ),
      );
      await expectLater(
        client.generateMaterials(
          documentId: 'doc',
          types: {CardType.basic},
          sourceBlocks: [block],
        ),
        throwsA(
          isA<MaterialGenerationFailure>().having(
            (e) => e.code,
            'code',
            MaterialGenerationFailureCode.networkUnavailable,
          ),
        ),
      );
    },
  );
}

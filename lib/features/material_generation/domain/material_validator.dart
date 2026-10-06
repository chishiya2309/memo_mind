import 'package:unorm_dart/unorm_dart.dart' as unicode;

import '../../ocr_editor/domain/ocr_models.dart';
import 'material_generation_models.dart';

class MaterialValidator {
  const MaterialValidator._();
  static String normalize(String text) =>
      unicode.nfc(text).replaceAll(RegExp(r'\s+', unicode: true), ' ').trim();
  static bool isQuoteSupported(String quote, String source) =>
      normalize(quote).isNotEmpty &&
      normalize(source).contains(normalize(quote));
  static Map<String, String> errors(
    MaterialDraft card, {
    bool requireSource = true,
  }) {
    final errors = <String, String>{};
    if (card.rawResponse != null) {
      errors['format'] = 'Vui lòng kiểm tra loại và nội dung thẻ trong Chỉnh sửa, rồi lưu thay đổi.';
    }
    void check(String key, String value, int max) {
      if (value.trim().isEmpty || value.length > max) {
        errors[key] = 'Bắt buộc nhập, tối đa $max ký tự.';
      }
    }

    check('front', card.front, 2000);
    check('back', card.back, 2000);
    if (requireSource) check('sourceQuote', card.sourceQuote, 2000);
    if (requireSource &&
        (card.sourceBlockId.trim().isEmpty || card.sourcePage < 1)) {
      errors['source'] = 'Thiếu liên kết nguồn hợp lệ.';
    }
    if (card.confidence != null &&
        (!card.confidence!.isFinite ||
            card.confidence! < 0 ||
            card.confidence! > 1)) {
      errors['confidence'] = 'Độ tin cậy phải từ 0 đến 1.';
    }
    if (card.type == CardType.cloze && !card.front.contains('[...]')) {
      errors['front'] = 'Thẻ điền khuyết phải chứa [...].';
    }
    if (card.type == CardType.mcq) {
      final ids = card.options.map((o) => o.optionId).toSet();
      if (card.options.length != 4 ||
          ids.length != 4 ||
          !ids.containsAll(const {'A', 'B', 'C', 'D'})) {
        errors['options'] = 'Cần đúng bốn lựa chọn A, B, C, D.';
      }
      final seen = <String>{};
      for (final option in card.options) {
        check(option.optionId, option.text, 500);
        if (!seen.add(normalize(option.text).toLowerCase())) {
          errors[option.optionId] = 'Các lựa chọn phải khác nhau.';
        }
      }
      if (!ids.contains(card.correctOptionId)) {
        errors['correctOptionId'] = 'Chọn đáp án đúng.';
      }
      check('explanation', card.explanation ?? '', 2000);
    } else if (card.options.isNotEmpty ||
        card.correctOptionId != null ||
        card.explanation != null) {
      errors['options'] = 'Payload không phù hợp loại thẻ.';
    }
    return errors;
  }

  static void validate(
    MaterialDraft card, {
    required SourceBlock? sourceBlock,
    required String documentId,
  }) {
    final fields = errors(card);
    if (fields.isNotEmpty) throw FormatException(fields.values.first);
    if (sourceBlock == null ||
        sourceBlock.isDeleted ||
        !(sourceBlock.isVerified || sourceBlock.isUserAdded) ||
        sourceBlock.documentId != documentId ||
        sourceBlock.blockId != card.sourceBlockId ||
        sourceBlock.pageNumber != card.sourcePage ||
        !isQuoteSupported(card.sourceQuote, sourceBlock.normalizedText)) {
      throw const MaterialGenerationFailure(
        MaterialGenerationFailureCode.sourceBlockMismatch,
        'Nguồn đã thay đổi hoặc không khớp. Vui lòng kiểm tra lại học liệu.',
      );
    }
  }

  static List<MaterialIssue> issues(
    MaterialDraft card, {
    required SourceBlock? sourceBlock,
    required String documentId,
    List<MaterialDraft> cards = const [],
  }) {
    final result = <MaterialIssue>[
      for (final entry in errors(card, requireSource: false).entries)
        MaterialIssue(
          'invalid_${entry.key}',
          entry.value,
          field: entry.key,
          isError: true,
        ),
    ];
    if (card.requestedTypes.isNotEmpty &&
        !card.requestedTypes.contains(card.type)) {
      result.add(
        const MaterialIssue('unrequested_type', 'Loại thẻ khác với yêu cầu.'),
      );
    }
    if (sourceBlock == null ||
        sourceBlock.isDeleted ||
        sourceBlock.documentId != documentId) {
      result.add(
        const MaterialIssue(
          'source_block_mismatch',
          'Không tìm thấy đoạn nguồn.',
          field: 'sourceBlockId',
        ),
      );
    } else {
      if (sourceBlock.pageNumber != card.sourcePage) {
        result.add(
          const MaterialIssue(
            'source_page_mismatch',
            'Trang nguồn không khớp.',
            field: 'sourcePage',
          ),
        );
      }
      if (!isQuoteSupported(card.sourceQuote, sourceBlock.normalizedText)) {
        result.add(
          const MaterialIssue(
            'unsupported_quote',
            'Trích dẫn chưa khớp đoạn nguồn.',
            field: 'sourceQuote',
          ),
        );
      }
      if (!(sourceBlock.isVerified || sourceBlock.isUserAdded)) {
        result.add(
          const MaterialIssue(
            'source_changed',
            'Đoạn nguồn chưa được xác nhận hoặc đã thay đổi.',
          ),
        );
      }
    }
    final key = normalize(card.front).toLowerCase();
    final duplicate = cards
        .where(
          (c) =>
              c.id != card.id &&
              key.isNotEmpty &&
              normalize(c.front).toLowerCase() == key,
        )
        .firstOrNull;
    if (duplicate != null) {
      result.add(
        MaterialIssue(
          'duplicate',
          'Câu hỏi giống thẻ ${cards.indexOf(duplicate) + 1}.',
          field: 'front',
        ),
      );
    }
    return result;
  }
}

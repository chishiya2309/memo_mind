import 'package:flutter/foundation.dart';

enum FlashcardFormat {
  qa,
  cloze,
  mixed;

  String get displayName => switch (this) {
        FlashcardFormat.qa => 'Hỏi – đáp',
        FlashcardFormat.cloze => 'Điền khuyết',
        FlashcardFormat.mixed => 'Kết hợp cả hai',
      };
}

enum DraftCardStatus {
  pending,          // Chưa duyệt
  accepted,         // Đã chấp nhận
  rejected,         // Đã loại bỏ
  needsSourceCheck, // Cần kiểm tra nguồn
}

@immutable
class FlashcardDraft {
  const FlashcardDraft({
    required this.id,
    required this.format,
    required this.question,
    required this.answer,
    required this.sourcePage,
    required this.sourceBlockId,
    required this.sourceQuote,
    this.confidence,
    this.status = DraftCardStatus.pending,
    this.isEdited = false,
  });

  final String id;
  final FlashcardFormat format; // qa or cloze
  final String question;
  final String answer;
  final int sourcePage;
  final String sourceBlockId;
  final String sourceQuote;
  final double? confidence;
  final DraftCardStatus status;
  final bool isEdited;

  bool get isPending => status == DraftCardStatus.pending;
  bool get isAccepted => status == DraftCardStatus.accepted;
  bool get isRejected => status == DraftCardStatus.rejected;
  bool get needsSourceCheck => status == DraftCardStatus.needsSourceCheck;

  FlashcardDraft copyWith({
    String? id,
    FlashcardFormat? format,
    String? question,
    String? answer,
    int? sourcePage,
    String? sourceBlockId,
    String? sourceQuote,
    double? confidence,
    DraftCardStatus? status,
    bool? isEdited,
  }) {
    return FlashcardDraft(
      id: id ?? this.id,
      format: format ?? this.format,
      question: question ?? this.question,
      answer: answer ?? this.answer,
      sourcePage: sourcePage ?? this.sourcePage,
      sourceBlockId: sourceBlockId ?? this.sourceBlockId,
      sourceQuote: sourceQuote ?? this.sourceQuote,
      confidence: confidence ?? this.confidence,
      status: status ?? this.status,
      isEdited: isEdited ?? this.isEdited,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FlashcardDraft &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          format == other.format &&
          question == other.question &&
          answer == other.answer &&
          sourceBlockId == other.sourceBlockId &&
          status == other.status;

  @override
  int get hashCode => Object.hash(id, format, question, answer, sourceBlockId, status);
}

@immutable
class FlashcardGenerationConfig {
  const FlashcardGenerationConfig({
    required this.documentId,
    this.format = FlashcardFormat.mixed,
    this.desiredCount = 5,
    this.selectedBlockIds = const {},
  });

  final String documentId;
  final FlashcardFormat format;
  final int desiredCount;
  final Set<String> selectedBlockIds;
}

@immutable
class FlashcardGenerationResult {
  const FlashcardGenerationResult({
    required this.cards,
    required this.totalGenerated,
    required this.validCount,
    required this.discardedCount,
    this.warnings = const [],
  });

  final List<FlashcardDraft> cards;
  final int totalGenerated;
  final int validCount;
  final int discardedCount;
  final List<String> warnings;
}

enum MaterialGenerationFailureCode {
  networkUnavailable,
  serviceQuotaOrTimeout,
  backendNotConfigured,
  invalidRequest,
  payloadTooLarge,
  noValidCards,
  sourceBlockMismatch,
  unknown,
}

class MaterialGenerationFailure implements Exception {
  const MaterialGenerationFailure(
    this.code,
    this.message, [
    this.cause,
  ]);

  final MaterialGenerationFailureCode code;
  final String message;
  final Object? cause;

  @override
  String toString() => 'MaterialGenerationFailure($code, $message, cause: $cause)';
}

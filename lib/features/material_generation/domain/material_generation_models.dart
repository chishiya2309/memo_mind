import 'package:flutter/foundation.dart';

enum CardType {
  basic,
  cloze,
  mcq;

  String get wireName => name.toUpperCase();
  String get displayName => switch (this) {
    CardType.basic => 'Hỏi – đáp',
    CardType.cloze => 'Điền khuyết',
    CardType.mcq => 'Trắc nghiệm',
  };
  static CardType fromWire(String value) => CardType.values.firstWhere(
    (type) => type.wireName == value,
    orElse: () => throw const FormatException('Loại học liệu không hợp lệ.'),
  );
}

enum QuantityMode { auto, manual }

enum DraftCardStatus { pending, accepted, rejected, needsSourceCheck }

@immutable
class McqOption {
  const McqOption({required this.optionId, required this.text});
  final String optionId;
  final String text;
  Map<String, Object?> toJson() => {'optionId': optionId, 'text': text};
  factory McqOption.fromJson(Map<String, dynamic> json) => McqOption(
    optionId: json['optionId'] as String,
    text: json['text'] as String,
  );
}

@immutable
class MaterialDraft {
  const MaterialDraft({
    required this.id,
    required this.type,
    required this.front,
    required this._back,
    required this.sourcePage,
    required this.sourceBlockId,
    required this.sourceQuote,
    this.options = const [],
    this.correctOptionId,
    this.explanation,
    this.confidence,
    this.status = DraftCardStatus.pending,
    this.isEdited = false,
  });
  final String id;
  final CardType type;
  final String front;
  final String _back;
  String get back => type == CardType.mcq
      ? options.where((o) => o.optionId == correctOptionId).firstOrNull?.text ??
            ''
      : _back;
  final List<McqOption> options;
  final String? correctOptionId;
  final String? explanation;
  final int sourcePage;
  final String sourceBlockId;
  final String sourceQuote;
  final double? confidence;
  final DraftCardStatus status;
  final bool isEdited;
  bool get isAccepted => status == DraftCardStatus.accepted;
  bool get isPending => status == DraftCardStatus.pending;
  bool get isRejected => status == DraftCardStatus.rejected;
  bool get needsSourceCheck => status == DraftCardStatus.needsSourceCheck;

  // Source fields and type deliberately cannot be changed while editing.
  MaterialDraft copyWith({
    String? id,
    String? front,
    String? back,
    List<McqOption>? options,
    String? correctOptionId,
    String? explanation,
    DraftCardStatus? status,
    bool? isEdited,
  }) => MaterialDraft(
    id: id ?? this.id,
    type: type,
    front: front ?? this.front,
    back: back ?? _back,
    sourcePage: sourcePage,
    sourceBlockId: sourceBlockId,
    sourceQuote: sourceQuote,
    options: options == null ? this.options : List.unmodifiable(options),
    correctOptionId: correctOptionId ?? this.correctOptionId,
    explanation: explanation ?? this.explanation,
    confidence: confidence,
    status: status ?? this.status,
    isEdited: isEdited ?? this.isEdited,
  );
  factory MaterialDraft.fromJson(String id, Map<String, dynamic> json) {
    final type = CardType.fromWire(json['type'] as String);
    final options = json['options'];
    if (type != CardType.mcq &&
        (options != null ||
            json['correctOptionId'] != null ||
            json['explanation'] != null)) {
      throw const FormatException('Payload không phù hợp loại thẻ.');
    }
    return MaterialDraft(
      id: id,
      type: type,
      front: json['front'] as String,
      back: json['back'] as String,
      sourcePage: json['sourcePage'] as int,
      sourceBlockId: json['sourceBlockId'] as String,
      sourceQuote: json['sourceQuote'] as String,
      confidence: (json['confidence'] as num?)?.toDouble(),
      options: List.unmodifiable(
        (options as List<dynamic>? ?? []).map(
          (o) => McqOption.fromJson(o as Map<String, dynamic>),
        ),
      ),
      correctOptionId: json['correctOptionId'] as String?,
      explanation: json['explanation'] as String?,
    );
  }
}

@immutable
class MaterialGenerationConfig {
  const MaterialGenerationConfig({
    required this.documentId,
    this.types = const {CardType.basic, CardType.cloze},
    this.quantityMode = QuantityMode.auto,
    this.desiredCount,
    this.selectedBlockIds = const {},
  });
  final String documentId;
  final Set<CardType> types;
  final QuantityMode quantityMode;
  final int? desiredCount;
  final Set<String> selectedBlockIds;
}

@immutable
class MaterialGenerationResult {
  const MaterialGenerationResult({
    required this.cards,
    required this.totalGenerated,
    required this.validCount,
    required this.discardedCount,
    this.warnings = const [],
  });
  final List<MaterialDraft> cards;
  final int totalGenerated;
  final int validCount;
  final int discardedCount;
  final List<String> warnings;
  Map<CardType, int> get countsByType => {
    for (final type in CardType.values)
      type: cards.where((c) => c.type == type).length,
  };
}

enum MaterialGenerationFailureCode {
  networkUnavailable,
  serviceQuotaOrTimeout,
  backendNotConfigured,
  invalidRequest,
  payloadTooLarge,
  noValidCards,
  sourceBlockMismatch,
  invalidOutput,
  storageError,
  unknown,
}

class MaterialGenerationFailure implements Exception {
  const MaterialGenerationFailure(this.code, this.message, [this.cause]);
  final MaterialGenerationFailureCode code;
  final String message;
  final Object? cause;
  @override
  String toString() => message;
}

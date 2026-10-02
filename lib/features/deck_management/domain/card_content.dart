import '../../material_generation/domain/material_generation_models.dart';
import '../../material_generation/domain/material_validator.dart';

/// Content-only input: editors cannot overwrite source references or scheduling.
class CardContent {
  const CardContent({
    required this.type,
    required this.front,
    required this.back,
    this.options = const [],
    this.correctOptionId,
    this.explanation,
    this.tags = const [],
  });
  final CardType type;
  final String front, back;
  final List<McqOption> options;
  final String? correctOptionId, explanation;
  final List<String> tags;

  String get answer => type == CardType.mcq
      ? options.where((o) => o.optionId == correctOptionId).firstOrNull?.text ??
            ''
      : back;

  Map<String, String> get errors => MaterialValidator.errors(
    MaterialDraft(
      id: '',
      type: type,
      front: front,
      back: answer,
      options: options,
      correctOptionId: correctOptionId,
      explanation: explanation,
      sourcePage: 0,
      sourceBlockId: '',
      sourceQuote: '',
    ),
    requireSource: false,
  );

  void validate() {
    if (errors.isNotEmpty) throw FormatException(errors.values.first);
  }

  static List<String> normalizeTags(Iterable<String> tags) {
    final seen = <String>{};
    return List.unmodifiable(
      tags
          .map((t) => t.trim())
          .where((t) => t.isNotEmpty && seen.add(t.toLowerCase())),
    );
  }
}

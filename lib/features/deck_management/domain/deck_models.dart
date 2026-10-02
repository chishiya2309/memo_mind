import 'dart:io';

import 'card_content.dart';
export 'card_content.dart';

import '../../document_import/domain/document_import_models.dart';
import '../../ocr_editor/domain/ocr_models.dart';
import '../../material_generation/domain/material_generation_models.dart';

import 'package:flutter/foundation.dart';

import '../../home/domain/home_dashboard_data.dart';

enum DeckStatus { active, deleted }

@immutable
class Deck {
  const Deck({
    required this.id,
    required this.title,
    this.description,
    this.tone = DeckTone.indigo,
    this.cardCount = 0,
    this.tags = const [],
    this.status = DeckStatus.active,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String title;
  final String? description;
  final DeckTone tone;
  final int cardCount;
  final List<String> tags;
  final DeckStatus status;
  final DateTime createdAt;
  final DateTime updatedAt;

  Deck copyWith({
    String? id,
    String? title,
    String? description,
    DeckTone? tone,
    int? cardCount,
    List<String>? tags,
    DeckStatus? status,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Deck(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      tone: tone ?? this.tone,
      cardCount: cardCount ?? this.cardCount,
      tags: tags ?? this.tags,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Deck &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          title == other.title &&
          description == other.description &&
          tone == other.tone &&
          cardCount == other.cardCount &&
          listEquals(tags, other.tags) &&
          status == other.status;

  @override
  int get hashCode => Object.hash(
    id,
    title,
    description,
    tone,
    cardCount,
    Object.hashAll(tags),
    status,
  );
}

enum CardStatus { active, suspended, deleted }

@immutable
class CardEntity {
  const CardEntity({
    required this.id,
    required this.deckId,
    required this.type,
    required this.front,
    required this._back,
    this.sourceDocumentId,
    this.sourcePageId,
    this.sourcePageNumber,
    this.sourceBlockId,
    this.sourceQuote = '',
    this.tags = const [],
    this.options = const [],
    this.correctOptionId,
    this.explanation,
    this.confidence,
    this.status = CardStatus.active,
    this.repetitions = 0,
    this.intervalDays = 0,
    this.easeFactor = 2.5,
    required this.dueDate,
    required this.createdAt,
    required this.updatedAt,
  });
  final String id, deckId, front, _back;
  final CardType type;
  final List<McqOption> options;
  final String? correctOptionId, explanation;
  String get back => type == CardType.mcq && options.isNotEmpty
      ? options.where((o) => o.optionId == correctOptionId).firstOrNull?.text ??
            ''
      : _back;
  final String? sourceDocumentId, sourcePageId, sourceBlockId;
  final String sourceQuote;
  final int? sourcePageNumber;
  final List<String> tags;
  bool get hasSource =>
      sourceQuote.trim().isNotEmpty ||
      [
        sourceDocumentId,
        sourcePageId,
        sourceBlockId,
      ].any((s) => s != null && s.trim().isNotEmpty);
  CardContent get content => CardContent(
    type: type,
    front: front,
    back: back,
    options: options,
    correctOptionId: correctOptionId,
    explanation: explanation,
    tags: tags,
  );
  final double? confidence;
  final CardStatus status;
  final int repetitions, intervalDays;
  final double easeFactor;
  final DateTime dueDate, createdAt, updatedAt;
  CardEntity copyWith({
    String? id,
    String? deckId,
    CardStatus? status,
    CardContent? content,
    DateTime? updatedAt,
  }) => CardEntity(
    id: id ?? this.id,
    deckId: deckId ?? this.deckId,
    type: type,
    tags: content == null ? tags : CardContent.normalizeTags(content.tags),
    front: content?.front.trim() ?? front,
    back: content?.answer.trim() ?? back,
    options: content?.options ?? options,
    correctOptionId: content?.correctOptionId ?? correctOptionId,
    explanation: content?.explanation?.trim() ?? explanation,
    sourceDocumentId: sourceDocumentId,
    sourcePageId: sourcePageId,
    sourcePageNumber: sourcePageNumber,
    sourceBlockId: sourceBlockId,
    sourceQuote: sourceQuote,
    confidence: confidence,
    status: status ?? this.status,
    repetitions: repetitions,
    intervalDays: intervalDays,
    easeFactor: easeFactor,
    dueDate: dueDate,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  MaterialDraft toDraft() => MaterialDraft(
    id: id,
    type: type,
    front: front,
    back: back,
    sourcePage: sourcePageNumber ?? 0,
    sourceBlockId: sourceBlockId ?? '',
    sourceQuote: sourceQuote,
    options: options,
    correctOptionId: correctOptionId,
    explanation: explanation,
    confidence: confidence,
    status: DraftCardStatus.accepted,
  );
}

@immutable
class CardSourceTrace {
  const CardSourceTrace({
    required this.documentTitle,
    required this.sourceQuote,
    this.sourcePage,
    this.sourceBlock,
    this.imageFile,
    this.sourcePageNumber,
    this.imageUsesNormalizedCoordinates = false,
    this.warning,
  });

  final String documentTitle;
  final String sourceQuote;
  final SourcePage? sourcePage;
  final SourceBlock? sourceBlock;
  final File? imageFile;
  final int? sourcePageNumber;
  final bool imageUsesNormalizedCoordinates;
  final String? warning;

  SourcePage? get page => sourcePage;
  SourceBlock? get block => sourceBlock;
  File? get sourcePageFile => imageFile;
}

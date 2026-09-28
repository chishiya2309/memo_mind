import 'package:flutter/foundation.dart';
import '../../home/domain/home_dashboard_data.dart';

@immutable
class Deck {
  const Deck({
    required this.id,
    required this.title,
    this.description,
    this.tone = DeckTone.indigo,
    this.cardCount = 0,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String title;
  final String? description;
  final DeckTone tone;
  final int cardCount;
  final DateTime createdAt;
  final DateTime updatedAt;

  Deck copyWith({
    String? id,
    String? title,
    String? description,
    DeckTone? tone,
    int? cardCount,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Deck(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      tone: tone ?? this.tone,
      cardCount: cardCount ?? this.cardCount,
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
          cardCount == other.cardCount;

  @override
  int get hashCode => Object.hash(id, title, description, tone, cardCount);
}

enum CardStatus {
  active,
  suspended,
  deleted,
}

@immutable
class CardEntity {
  const CardEntity({
    required this.id,
    required this.deckId,
    this.type = 'flashcard',
    required this.format,
    required this.question,
    required this.answer,
    required this.sourceDocumentId,
    required this.sourcePageId,
    required this.sourcePageNumber,
    required this.sourceBlockId,
    required this.sourceQuote,
    this.confidence,
    this.status = CardStatus.active,
    this.repetitions = 0,
    this.intervalDays = 0,
    this.easeFactor = 2.5,
    required this.dueDate,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String deckId;
  final String type;
  final String format; // 'qa' | 'cloze'
  final String question;
  final String answer;
  final String sourceDocumentId;
  final String sourcePageId;
  final int sourcePageNumber;
  final String sourceBlockId;
  final String sourceQuote;
  final double? confidence;
  final CardStatus status;
  final int repetitions;
  final int intervalDays;
  final double easeFactor;
  final DateTime dueDate;
  final DateTime createdAt;
  final DateTime updatedAt;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CardEntity &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          deckId == other.deckId &&
          question == other.question &&
          answer == other.answer &&
          sourceBlockId == other.sourceBlockId;

  @override
  int get hashCode => Object.hash(id, deckId, question, answer, sourceBlockId);
}

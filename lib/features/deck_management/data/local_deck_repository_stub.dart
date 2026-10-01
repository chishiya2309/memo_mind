import '../../../core/database/memo_mind_database.dart';
import '../../home/domain/home_dashboard_data.dart';
import '../domain/deck_models.dart';
import '../domain/deck_repository.dart';

class LocalDeckRepository implements DeckRepository {
  const LocalDeckRepository({
    MemoMindDatabase? database,
    DateTime Function()? clock,
  });

  @override
  Future<List<Deck>> getDecks() =>
      Future.error(UnsupportedError('Deck storage unsupported on web.'));

  @override
  Future<Deck?> getDeckById(String deckId) =>
      Future.error(UnsupportedError('Deck storage unsupported on web.'));

  @override
  Future<Deck> createDeck({
    required String title,
    String? description,
    DeckTone tone = DeckTone.indigo,
    List<String> tags = const [],
  }) =>
      Future.error(UnsupportedError('Deck storage unsupported on web.'));

  @override
  Future<Deck> updateDeck(
    String deckId, {
    required String title,
    String? description,
    DeckTone? tone,
    List<String>? tags,
  }) =>
      Future.error(UnsupportedError('Deck storage unsupported on web.'));

  @override
  Future<void> deleteDeck(String deckId) =>
      Future.error(UnsupportedError('Deck storage unsupported on web.'));

  @override
  Future<void> deleteCard(String cardId) =>
      Future.error(UnsupportedError('Deck storage unsupported on web.'));

  @override
  Future<CardSourceTrace> getCardSourceTrace(CardEntity card) =>
      Future.error(UnsupportedError('Deck storage unsupported on web.'));

  @override
  Future<void> saveCardsToDeck({
    required String deckId,
    required List<CardEntity> cards,
  }) =>
      Future.error(UnsupportedError('Deck storage unsupported on web.'));

  @override
  Future<List<CardEntity>> getCardsForDeck(String deckId) =>
      Future.error(UnsupportedError('Deck storage unsupported on web.'));
}

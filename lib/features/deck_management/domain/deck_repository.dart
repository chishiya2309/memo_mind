import 'deck_models.dart';
import '../../home/domain/home_dashboard_data.dart';

abstract class DeckRepository {
  Future<List<Deck>> getDecks();
  Future<Deck?> getDeckById(String deckId);
  Future<Deck> createDeck({
    required String title,
    String? description,
    DeckTone tone = DeckTone.indigo,
  });
  Future<void> saveCardsToDeck({
    required String deckId,
    required List<CardEntity> cards,
  });
  Future<List<CardEntity>> getCardsForDeck(String deckId);
}

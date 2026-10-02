import '../../deck_management/domain/deck_models.dart';

class DueCard {
  const DueCard(this.card, this.deckTitle);
  final CardEntity card;
  final String deckTitle;
}

abstract class DueCardsSource {
  Future<List<DueCard>> getDueCards(DateTime at);
  Future<bool> hasActiveSession();
}

import '../domain/due_cards_source.dart';

class LocalDueCardsSource implements DueCardsSource {
  @override
  Future<bool> hasActiveSession() async =>
      throw UnsupportedError('Danh sách thẻ đến hạn hiện hỗ trợ trên Android.');
  @override
  Future<List<DueCard>> getDueCards(DateTime at) async =>
      throw UnsupportedError('Danh sách thẻ đến hạn hiện hỗ trợ trên Android.');
}

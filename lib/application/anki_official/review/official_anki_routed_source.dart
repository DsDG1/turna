/// Data model representing an Official Anki source resolved for review.
class OfficialAnkiRoutedSource {
  const OfficialAnkiRoutedSource({
    required this.importId,
    required this.sourceId,
    required this.deckId,
    required this.cardIds,
  });

  final String importId;
  final String sourceId;
  final int deckId;
  final Set<int> cardIds;
}

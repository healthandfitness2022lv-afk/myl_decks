import '../models/card_myl.dart';
import '../models/deck.dart';
import '../utils/card_utils.dart';

CardMyL? _resolveCard(
  DeckCardEntry entry,
  Map<String, CardMyL> cardsById,
  Map<String, CardMyL> cardsByNameLower,
) {
  final id = entry.cardId?.trim() ?? '';
  return (id.isNotEmpty ? cardsById[id] : null) ??
      cardsByNameLower[entry.name.toLowerCase()];
}

class LegacyDeckStatistics {
  final Map<String, int> featureOccurrences;
  final Map<String, int> groupOccurrences;

  const LegacyDeckStatistics({
    required this.featureOccurrences,
    required this.groupOccurrences,
  });
}

/// Congela el comportamiento Legacy: cada característica suma una vez por
/// copia y varias características del mismo grupo se acumulan entre sí.
class LegacyDeckStatisticsCalculator {
  const LegacyDeckStatisticsCalculator();

  LegacyDeckStatistics calculate(
    Deck deck, {
    required Map<String, CardMyL> cardsById,
    required Map<String, CardMyL> cardsByNameLower,
    required Map<String, String> featureGroupMap,
  }) {
    final features = <String, int>{};
    final groups = <String, int>{};
    for (final entry in deck.cards) {
      final card = _resolveCard(entry, cardsById, cardsByNameLower);
      for (final feature in card?.caracteristicasRaw ?? const <String>[]) {
        if (feature.trim().isEmpty) continue;
        features[feature] = (features[feature] ?? 0) + entry.count;
        final group = _resolveLegacyGroup(feature, featureGroupMap);
        groups[group] = (groups[group] ?? 0) + entry.count;
      }
    }
    return LegacyDeckStatistics(
      featureOccurrences: features,
      groupOccurrences: groups,
    );
  }
}

String _resolveLegacyGroup(
  String feature,
  Map<String, String> featureGroupMap,
) {
  final exact =
      featureGroupMap[feature] ?? featureGroupMap[feature.toLowerCase()];
  if (exact != null && exact.trim().isNotEmpty) return exact;
  final normalized = normalizeFeatureKey(feature);
  final normalizedExact =
      featureGroupMap[normalized] ?? featureGroupMap[normalized.toLowerCase()];
  if (normalizedExact != null && normalizedExact.trim().isNotEmpty) {
    return normalizedExact;
  }
  for (final entry in featureGroupMap.entries) {
    final key = normalizeFeatureKey(entry.key);
    if (key.isNotEmpty &&
        (normalized.contains(key) || key.contains(normalized))) {
      return entry.value;
    }
  }
  return 'Otros';
}

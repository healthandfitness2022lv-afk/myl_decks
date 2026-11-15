import '../models/deck.dart';
import '../utils/text_normalize.dart';
import 'inventory_keys.dart';

/// Identidad opaca del lugar físico donde están asignadas las cartas.
/// Los mazos Racial Edición de igual edición y raza comparten un destino;
/// los demás formatos conservan un destino independiente por mazo.
String deckStockTargetId(Deck deck) {
  if (!deck.isUnified || deck.format != DeckFormat.racial) return deck.id;
  final edition = Uri.encodeComponent(normalizeSearch(deck.edition ?? ''));
  final race = Uri.encodeComponent(normalizeSearch(deck.race ?? ''));
  if (edition.isEmpty || race.isEmpty) return deck.id;
  return 'family:racial:$edition:$race';
}

/// Solo Racial Edición define la completitud física de la colección. Full y
/// Racial Libre son configuraciones opcionales que pueden recibir copias por
/// decisión explícita, pero no generan demanda automática.
bool countsTowardCollectionCompleteness(Deck deck) =>
    deck.format == DeckFormat.racial;

bool isSharedStockTargetId(String id) => id.startsWith('family:racial:');

class DeckStockTarget {
  final String id;
  final List<Deck> members;
  final List<DeckCardEntry> cards;

  const DeckStockTarget({
    required this.id,
    required this.members,
    required this.cards,
  });

  bool get isShared => members.length > 1 && isSharedStockTargetId(id);
  bool get assemblyEnabled => members.any((deck) => deck.assemblyEnabled);
  bool get sellable => members.any((deck) => deck.sellable);

  String get label {
    if (!isSharedStockTargetId(id)) return members.first.name;
    final edition = (members.first.edition ?? '').trim();
    final race = (members.first.race ?? '').trim();
    return [race, edition].where((value) => value.isNotEmpty).join(' · ');
  }

  /// Proyección compatible con las APIs existentes. Su lista de cartas es
  /// la unión de la familia usando el máximo requerido por carta.
  Deck asDeck() {
    final sample = members.first;
    return sample.copyWith(
      id: id,
      name: label,
      cards: cards,
      assemblyEnabled: assemblyEnabled,
      sellable: sellable,
    );
  }
}

/// Construye destinos físicos. Los mazos pausados siguen siendo miembros de
/// su familia, pero no aportan demanda mientras estén pausados.
List<DeckStockTarget> buildDeckStockTargets(Iterable<Deck> decks) {
  final membersByTarget = <String, List<Deck>>{};
  for (final deck in decks) {
    membersByTarget.putIfAbsent(deckStockTargetId(deck), () => []).add(deck);
  }

  return membersByTarget.entries.map((group) {
    final maxByCard = <String, DeckCardEntry>{};
    for (final deck in group.value.where((deck) => deck.assemblyEnabled)) {
      final counts = <String, int>{};
      final samples = <String, DeckCardEntry>{};
      for (final entry in deck.cards.where((entry) => entry.count > 0)) {
        final key = entryInventoryKey(entry);
        counts[key] = (counts[key] ?? 0) + entry.count;
        samples[key] = entry;
      }
      for (final entry in counts.entries) {
        final previous = maxByCard[entry.key];
        if (previous == null || entry.value > previous.count) {
          maxByCard[entry.key] = samples[entry.key]!.copyWith(
            count: entry.value,
          );
        }
      }
    }
    return DeckStockTarget(
      id: group.key,
      members: List.unmodifiable(group.value),
      cards: List.unmodifiable(maxByCard.values),
    );
  }).toList();
}

Map<String, DeckStockTarget> deckStockTargetsById(Iterable<Deck> decks) => {
  for (final target in buildDeckStockTargets(decks)) target.id: target,
};

Map<String, String> deckStockTargetLabels(Iterable<Deck> decks) => {
  for (final target in buildDeckStockTargets(decks)) target.id: target.label,
};

List<Deck> physicalDeckProjections(Iterable<Deck> decks) => [
  for (final target in buildDeckStockTargets(decks)) target.asDeck(),
];

/// Proyecta el pool físico de variantes sobre una configuración concreta.
/// Una configuración que requiere menos copias toma cualquier subconjunto
/// estable del pool; las posiciones no crean propiedad separada por mazo.
List<DeckCardEntry> applySharedVariantPoolToDeckCards({
  required List<DeckCardEntry> cards,
  required String itemKey,
  required List<String?> variants,
}) {
  var cursor = 0;
  return cards.map((entry) {
    if (entryInventoryKey(entry) != itemKey) return entry;
    final selected = <String>[];
    for (var index = 0; index < entry.count; index++) {
      final poolIndex = cursor + index;
      selected.add(
        poolIndex < variants.length ? variants[poolIndex] ?? '' : '',
      );
    }
    cursor += entry.count;
    return entry.copyWith(selectedVariants: selected);
  }).toList();
}

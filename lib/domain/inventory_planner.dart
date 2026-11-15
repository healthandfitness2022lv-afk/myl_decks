import '../models/deck.dart';
import '../models/inventory.dart';
import 'deck_stock_groups.dart';
import 'inventory_keys.dart';

export 'inventory_keys.dart';

class TargetBuildResult {
  final Deck target;
  final String destinationDeckId;
  final int required;
  final int available;
  final bool needsMoves;
  final List<PlanShortage> shortages;
  const TargetBuildResult({
    required this.target,
    required this.destinationDeckId,
    required this.required,
    required this.available,
    required this.needsMoves,
    required this.shortages,
  });
  bool get isBuildable => shortages.isEmpty;
  bool get alreadyBuilt => isBuildable && !needsMoves;
}

class InventoryPlanResult {
  final List<TargetBuildResult> targets;
  final List<TransferMove> moves;
  final List<PlanShortage> shortages;
  const InventoryPlanResult({
    required this.targets,
    required this.moves,
    required this.shortages,
  });
}

InventoryPlanResult buildInventoryPlan({
  required List<InventoryItem> inventory,
  required List<Deck> orderedTargets,
  required Map<String, String> destinationByTarget,
  bool releaseUnselectedDecks = false,
}) {
  final items = {for (final item in inventory) item.key: item};
  final remaining = {
    for (final item in inventory) item.key: item.total - item.reserved,
  };
  final reservedByDestination = <String, Map<String, int>>{};
  final results = <TargetBuildResult>[];
  final shortages = <PlanShortage>[];

  for (final target in orderedTargets) {
    final destination = destinationByTarget[target.id] ?? 'new:${target.id}';
    final needs = <String, int>{};
    final names = <String, String>{};
    for (final entry in target.cards) {
      final key = entryInventoryKey(entry);
      needs[key] = (needs[key] ?? 0) + entry.count;
      names[key] = entry.name;
    }
    var required = 0;
    var available = 0;
    var needsMoves = false;
    final targetShortages = <PlanShortage>[];
    final reservation = reservedByDestination.putIfAbsent(
      destination,
      () => {},
    );
    for (final need in needs.entries) {
      required += need.value;
      final canUse = (remaining[need.key] ?? 0).clamp(0, need.value);
      available += canUse;
      remaining[need.key] = (remaining[need.key] ?? 0) - canUse;
      reservation[need.key] = (reservation[need.key] ?? 0) + canUse;
      final alreadyThere = (items[need.key]?.allocatedTo(destination) ?? 0)
          .clamp(0, canUse);
      if (alreadyThere < canUse) needsMoves = true;
      if (canUse < need.value) {
        final shortage = PlanShortage(
          targetDeckId: target.id,
          cardKey: need.key,
          cardName: names[need.key]!,
          quantity: need.value - canUse,
        );
        shortages.add(shortage);
        targetShortages.add(shortage);
      }
    }
    results.add(
      TargetBuildResult(
        target: target,
        destinationDeckId: destination,
        required: required,
        available: available,
        needsMoves: needsMoves,
        shortages: targetShortages,
      ),
    );
  }

  final moves = <TransferMove>[];
  var moveIndex = 0;
  final freePool = {for (final item in inventory) item.key: item.free};
  final allocationPool = {
    for (final item in inventory)
      item.key: Map<String, int>.from(item.allocations),
  };

  // Todo lo que excede la configuración de un destino seleccionado vuelve primero al
  // stock libre. Así el destino termina exactamente igual al objetivo y esas
  // copias pueden alimentar otro objetivo del mismo plan.
  for (final destinationEntry in reservedByDestination.entries) {
    final destination = destinationEntry.key;
    for (final item in inventory) {
      final wanted = destinationEntry.value[item.key] ?? 0;
      final current = allocationPool[item.key]?[destination] ?? 0;
      final excess = current - wanted;
      if (excess <= 0) continue;
      moves.add(
        TransferMove(
          id: 'move_${moveIndex++}',
          cardKey: item.key,
          cardName: item.name,
          fromDeckId: destination,
          quantity: excess,
        ),
      );
      allocationPool[item.key]![destination] = wanted;
      freePool[item.key] = (freePool[item.key] ?? 0) + excess;
    }
  }

  for (final destinationEntry in reservedByDestination.entries) {
    final destination = destinationEntry.key;
    for (final reservation in destinationEntry.value.entries) {
      final item = items[reservation.key];
      if (item == null) continue;
      var wanted = reservation.value;
      final kept = (allocationPool[item.key]?[destination] ?? 0).clamp(
        0,
        wanted,
      );
      wanted -= kept;
      if (wanted <= 0) continue;
      final sources =
          allocationPool[item.key]!.entries
              .where((e) => e.key != destination && e.value > 0)
              .toList()
            ..sort((a, b) => b.value.compareTo(a.value));
      final freeTake = (freePool[item.key] ?? 0).clamp(0, wanted);
      if (freeTake > 0) {
        moves.add(
          TransferMove(
            id: 'move_${moveIndex++}',
            cardKey: item.key,
            cardName: item.name,
            toDeckId: destination,
            quantity: freeTake,
          ),
        );
        freePool[item.key] = (freePool[item.key] ?? 0) - freeTake;
        allocationPool[item.key]![destination] =
            (allocationPool[item.key]![destination] ?? 0) + freeTake;
        wanted -= freeTake;
      }
      for (final source in sources) {
        if (wanted <= 0) break;
        final take = source.value.clamp(0, wanted);
        moves.add(
          TransferMove(
            id: 'move_${moveIndex++}',
            cardKey: item.key,
            cardName: item.name,
            fromDeckId: source.key,
            toDeckId: destination,
            quantity: take,
          ),
        );
        allocationPool[item.key]![source.key] = source.value - take;
        allocationPool[item.key]![destination] =
            (allocationPool[item.key]![destination] ?? 0) + take;
        wanted -= take;
      }
    }
  }
  if (releaseUnselectedDecks) {
    final selectedDestinations = reservedByDestination.keys.toSet();
    for (final item in inventory) {
      for (final allocation in allocationPool[item.key]!.entries.toList()) {
        if (selectedDestinations.contains(allocation.key) ||
            allocation.value <= 0) {
          continue;
        }
        moves.add(
          TransferMove(
            id: 'move_${moveIndex++}',
            cardKey: item.key,
            cardName: item.name,
            fromDeckId: allocation.key,
            quantity: allocation.value,
          ),
        );
        allocationPool[item.key]![allocation.key] = 0;
        freePool[item.key] = (freePool[item.key] ?? 0) + allocation.value;
      }
    }
  }
  return InventoryPlanResult(
    targets: results,
    moves: moves,
    shortages: shortages,
  );
}

/// Un mazo que tiene copias asignadas de una carta que le falta a otro mazo,
/// candidato a que el usuario elija sacárselas.
class SourceDeckOption {
  final String deckId;
  final String deckName;
  final int available;
  const SourceDeckOption({
    required this.deckId,
    required this.deckName,
    required this.available,
  });
}

/// Lo que le falta a [target] de una carta puntual, y de qué mazos se podría
/// sacar cada copia (para que el usuario elija, sin decidir nada solo).
class MissingCardWithSources {
  final String cardKey;
  final String cardName;
  final int missing;
  final int free;
  final List<SourceDeckOption> sources;
  const MissingCardWithSources({
    required this.cardKey,
    required this.cardName,
    required this.missing,
    required this.free,
    required this.sources,
  });

  /// Cuánto de lo que falta se puede cubrir sin tocar ningún otro mazo.
  int get coveredByFree => free.clamp(0, missing);

  /// Si ni el stock libre ni todos los mazos candidatos combinados alcanzan.
  bool get hasShortage =>
      coveredByFree + sources.fold<int>(0, (s, o) => s + o.available) < missing;
}

/// Para cada carta que le falta a [target], calcula cuánto cubre el stock
/// libre y qué otros mazos tienen copias asignadas de esa carta (candidatos
/// a intervenir). No mueve ni decide nada — es información para que el
/// usuario elija a quién quitarle copias, si hace falta.
List<MissingCardWithSources> findMissingCardsWithSources({
  required List<InventoryItem> inventory,
  required Deck target,
  required Map<String, String> deckNames,
}) {
  final items = {for (final item in inventory) item.key: item};
  final needs = <String, int>{};
  final names = <String, String>{};
  for (final entry in target.cards) {
    final key = entryInventoryKey(entry);
    needs[key] = (needs[key] ?? 0) + entry.count;
    names[key] = entry.name;
  }

  final result = <MissingCardWithSources>[];
  for (final need in needs.entries) {
    final key = need.key;
    final item = items[key];
    final targetId = deckStockTargetId(target);
    final alreadyThere = (item?.allocatedTo(targetId) ?? 0).clamp(
      0,
      need.value,
    );
    final missing = need.value - alreadyThere;
    if (missing <= 0) continue;
    if (item == null) {
      result.add(
        MissingCardWithSources(
          cardKey: key,
          cardName: names[key]!,
          missing: missing,
          free: 0,
          sources: const [],
        ),
      );
      continue;
    }
    final sources =
        item.allocations.entries
            .where((entry) => entry.key != targetId && entry.value > 0)
            .map(
              (entry) => SourceDeckOption(
                deckId: entry.key,
                deckName: deckNames[entry.key] ?? 'Mazo',
                available: entry.value,
              ),
            )
            .toList();
    result.add(
      MissingCardWithSources(
        cardKey: key,
        cardName: item.name,
        missing: missing,
        free: item.free,
        sources: sources,
      ),
    );
  }
  return result;
}

/// Construye los movimientos de un plan a partir de lo que el usuario eligió
/// explícitamente: [freeAmountByCard] es cuánto tomar del stock libre por
/// carta (siempre se puede aplicar sin elegir nada), y [sourcesByCard] es,
/// por carta, la lista de (deckId, cantidad) elegida por el usuario para
/// completar lo que el stock libre no cubrió.
InventoryPlanResult buildSingleDeckPlanFromSelection({
  required Deck target,
  required List<MissingCardWithSources> missing,
  required Map<String, int> freeAmountByCard,
  required Map<String, List<(String deckId, int quantity)>> sourcesByCard,
}) {
  final targetStockId = deckStockTargetId(target);
  final moves = <TransferMove>[];
  var moveIndex = 0;
  var required = 0;
  var available = 0;
  final shortages = <PlanShortage>[];

  for (final entry in missing) {
    required += entry.missing;
    var covered = 0;

    final freeTake = (freeAmountByCard[entry.cardKey] ?? 0).clamp(
      0,
      entry.missing,
    );
    if (freeTake > 0) {
      moves.add(
        TransferMove(
          id: 'move_${moveIndex++}',
          cardKey: entry.cardKey,
          cardName: entry.cardName,
          toDeckId: targetStockId,
          quantity: freeTake,
        ),
      );
      covered += freeTake;
    }

    final chosenSources =
        sourcesByCard[entry.cardKey] ?? const <(String, int)>[];
    for (final (deckId, quantity) in chosenSources) {
      if (quantity <= 0) continue;
      moves.add(
        TransferMove(
          id: 'move_${moveIndex++}',
          cardKey: entry.cardKey,
          cardName: entry.cardName,
          fromDeckId: deckId,
          toDeckId: targetStockId,
          quantity: quantity,
        ),
      );
      covered += quantity;
    }

    available += covered;
    if (covered < entry.missing) {
      shortages.add(
        PlanShortage(
          targetDeckId: target.id,
          cardKey: entry.cardKey,
          cardName: entry.cardName,
          quantity: entry.missing - covered,
        ),
      );
    }
  }

  final result = TargetBuildResult(
    target: target,
    destinationDeckId: targetStockId,
    required: required,
    available: available,
    needsMoves: moves.isNotEmpty,
    shortages: shortages,
  );

  return InventoryPlanResult(
    targets: [result],
    moves: moves,
    shortages: shortages,
  );
}

/// Un mazo candidato a recibir stock libre sobrante de una carta: cuánto le
/// falta y cuánto de eso se le podría cubrir con el stock disponible.
class FreeStockCandidate {
  final String deckId;
  final String deckName;
  final int missing;
  const FreeStockCandidate({
    required this.deckId,
    required this.deckName,
    required this.missing,
  });
}

/// Una carta con stock libre sobrante y los mazos que la necesitan. Si
/// [candidates] tiene un solo elemento, la asignación es inequívoca
/// (preseleccionable); si tiene más de uno, hace falta que el usuario
/// elija a quién va cada copia.
class FreeStockAssignment {
  final String cardKey;
  final String cardName;
  final int free;
  final List<FreeStockCandidate> candidates;
  const FreeStockAssignment({
    required this.cardKey,
    required this.cardName,
    required this.free,
    required this.candidates,
  });

  bool get isUnambiguous => candidates.length == 1;
}

/// Resultado de agregar copias de una carta desde un mazo (ver
/// InventoryService.addCardsHere): [addedHere] es cuánto se asignó al mazo
/// desde el que se tocó la carta gris, [ambiguous] son los casos donde el
/// sobrante le sirve a más de un mazo distinto y hace falta elegir a mano.
class FillFromHereResult {
  final int addedHere;
  final List<FreeStockAssignment> ambiguous;
  const FillFromHereResult({required this.addedHere, required this.ambiguous});
}

/// Lo que ya se tiene registrado de una carta: total, por variante, y en
/// qué mazos está asignada cada copia. Se muestra antes de preguntar
/// "¿cuántas más tienes?" para no declarar copias que el sistema ya sabe
/// que existen.
class ExistingCardHolding {
  final int total;
  final int free;
  final Map<String, int> byVariant; // variantId ('' = sin variante) -> cant.
  final List<({String deckId, String deckName, int quantity})> byDeck;
  const ExistingCardHolding({
    required this.total,
    required this.free,
    required this.byVariant,
    required this.byDeck,
  });

  bool get hasAny => total > 0;
}

/// Recorre todo el inventario y todos los mazos unificados activos
/// ([decks] ya filtrados) para encontrar, carta por carta, stock libre que
/// algún mazo necesita. No decide ni mueve nada — es la base para el botón
/// "Rellenar mazos": el usuario confirma o elige entre candidatos antes de
/// aplicar nada. La variante física de cada copia no importa acá: solo se
/// compara cantidad requerida vs. asignada, igual que el resto del armado
/// automático (ver [InventoryService._chooseVariantsForAllocation]).
List<FreeStockAssignment> findFreeStockAssignments({
  required List<InventoryItem> inventory,
  required List<Deck> decks,
}) {
  final targets =
      buildDeckStockTargets(
        decks,
      ).where((target) => target.assemblyEnabled).toList();
  final result = <FreeStockAssignment>[];
  for (final item in inventory) {
    if (item.free <= 0) continue;
    final candidates = <FreeStockCandidate>[];
    for (final target in targets) {
      final needed = target.cards
          .where((entry) => entryInventoryKey(entry) == item.key)
          .fold<int>(0, (sum, entry) => sum + entry.count);
      if (needed <= 0) continue;
      final missing = needed - item.allocatedTo(target.id);
      if (missing > 0) {
        final representative = target.members.firstWhere(
          (deck) => deck.assemblyEnabled,
          orElse: () => target.members.first,
        );
        candidates.add(
          FreeStockCandidate(
            deckId: representative.id,
            deckName: target.label,
            missing: missing,
          ),
        );
      }
    }
    if (candidates.isEmpty) continue;
    result.add(
      FreeStockAssignment(
        cardKey: item.key,
        cardName: item.name,
        free: item.free,
        candidates: candidates,
      ),
    );
  }
  return result;
}

/// Resume lo que ya se tiene de [item] (o de nada, si no hay item aún) para
/// mostrarlo antes de preguntar "¿cuántas más tienes?".
ExistingCardHolding describeExistingHolding({
  required InventoryItem? item,
  required Map<String, String> deckNames,
}) {
  if (item == null) {
    return const ExistingCardHolding(
      total: 0,
      free: 0,
      byVariant: {},
      byDeck: [],
    );
  }
  final byVariant = <String, int>{
    for (final entry in item.variantTotals.entries)
      if (entry.value > 0) entry.key: entry.value,
  };
  final unidentified = item.unidentified;
  if (unidentified > 0) byVariant[''] = unidentified;
  final byDeck = [
    for (final entry in item.allocations.entries)
      if (entry.value > 0)
        (
          deckId: entry.key,
          deckName: deckNames[entry.key] ?? 'Mazo',
          quantity: entry.value,
        ),
  ];
  return ExistingCardHolding(
    total: item.total,
    free: item.free,
    byVariant: byVariant,
    byDeck: byDeck,
  );
}

// lib/screens/overall_completeness.dart
import 'dart:developer' as developer;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:collection/collection.dart';
import '../../models/deck.dart';
import '../../models/card_myl.dart';
import '../../services/deck_poster_share_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../domain/inventory_planner.dart';
import '../../domain/deck_stock_groups.dart';
import '../../models/inventory.dart';
import '../../services/inventory_service.dart';
import '../../utils/card_utils.dart';
import './deck_diff_dialog.dart' show DeckVariationPair;

/// Tipos públicos usados por esta pantalla (evitan private underscores entre archivos)
class OverallPairCompleteness {
  final Deck tengo;
  final Deck objetivo;
  final int needTotal;
  final int haveNow;
  final int contribible;
  final int restAfterBorrow;

  /// Pares reales del grupo (puede ser 1 o N variaciones de la misma raza)
  final List<_PairTemp> sourcePairs;

  OverallPairCompleteness({
    required this.tengo,
    required this.objetivo,
    required this.needTotal,
    required this.haveNow,
    required this.contribible,
    required this.restAfterBorrow,
    this.sourcePairs = const [],
  });

  double get pctNow => needTotal == 0 ? 100.0 : (haveNow / needTotal) * 100.0;
  double get pctWithBorrow {
    if (needTotal == 0) return 100.0;
    final possible = (haveNow + contribible);
    final capped = possible > needTotal ? needTotal : possible;
    return (capped / needTotal) * 100.0;
  }
}

/// Datos globales de faltantes usados por la pantalla:
class OverallMissingData {
  final Map<String, int> globalMissing; // cardName -> total faltante
  final Map<String, Map<String, int>>
  donorsPerCard; // cardName -> {donorLabel: qty}
  final Map<String, List<String>>
  perCardTargets; // cardName -> ["Objetivo (qty)", ...]
  final Map<String, Map<String, int>>
  perCardByEdition; // cardName -> {edition: qty}
  /// cardName -> {deckId del objetivo -> qty faltante en ese objetivo}
  final Map<String, Map<String, int>> perCardByDeckId;

  OverallMissingData({
    required this.globalMissing,
    required this.donorsPerCard,
    required this.perCardTargets,
    required this.perCardByEdition,
    this.perCardByDeckId = const {},
  });
}

class _OverallMetricPill extends StatelessWidget {
  final String label;
  final String value;

  const _OverallMetricPill({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0x1AF1D48B),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0x33F1D48B)),
      ),
      child: RichText(
        text: TextSpan(
          style: const TextStyle(fontFamily: 'inherit'),
          children: [
            TextSpan(
              text: '$label ',
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            TextSpan(
              text: value,
              style: const TextStyle(
                color: Color(0xFFF1D48B),
                fontSize: 13,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ----------------- Helpers (copiados/adaptados) -----------------

String _extractCardName(dynamic item) {
  if (item == null) return '';
  if (item is Map) return (item['name'] ?? item['nombre'] ?? '').toString();
  try {
    final dyn = item as dynamic;
    final v = dyn.name ?? dyn.nombre;
    return (v ?? '').toString();
  } catch (_) {
    return item.toString();
  }
}

String? _extractCardId(dynamic item) {
  if (item == null) return null;
  if (item is Map) {
    final v = item['cardId'] ?? item['id'] ?? item['card_id'];
    if (v == null) return null;
    return v.toString();
  }
  try {
    final dyn = item as dynamic;
    final v = dyn.cardId ?? dyn.id ?? dyn.card_id;
    if (v == null) return null;
    return v.toString();
  } catch (_) {
    return null;
  }
}

int _extractCardCount(dynamic item) {
  if (item == null) return 0;
  if (item is Map) {
    final v = item['count'] ?? item['cantidad'] ?? item['qty'] ?? 0;
    if (v is int) return v;
    return int.tryParse('$v') ?? 0;
  }
  try {
    final dyn = item as dynamic;
    final v = dyn.count ?? dyn.cantidad ?? dyn.qty ?? 0;
    if (v is int) return v;
    return int.tryParse('$v') ?? 0;
  } catch (_) {
    return 0;
  }
}

Map<String, int> _cardCountMap(List<dynamic> cards) {
  final m = <String, int>{};
  for (final c in cards) {
    final rawName = _extractCardName(c).trim().toLowerCase();
    if (rawName.isEmpty) continue;
    final qty = _extractCardCount(c);
    m[rawName] = (m[rawName] ?? 0) + qty;
  }
  return m;
}

/// Parear por link primero, y si no, por nombre+edición
List<_PairTemp> _pairByLinkOrName(List<Deck> list) {
  final targetById = <String, Deck>{
    for (final d in list.where((e) => e.isTarget)) d.id: d,
  };

  final map = <String, _PairTemp>{};

  for (final d in list) {
    if (d.isUnified) {
      final pair = map.putIfAbsent('unified:${d.id}', () => _PairTemp());
      pair.tengo = d;
      pair.objetivo = d;
      continue;
    }
    if (d.hasEmbeddedObjective) {
      final key = 'embedded:${d.id}';
      final pair = map.putIfAbsent(key, () => _PairTemp());
      pair.tengo = d;
      pair.objetivo = d.copyWith(
        cards: d.objectiveCards,
        status: DeckStatus.published,
      );
      continue;
    }

    if (d.isTarget) {
      final key = 'obj:${d.id}';
      final pair = map.putIfAbsent(key, () => _PairTemp());
      pair.objetivo = d;
      continue;
    }

    final linked = (d.linkedDeckId ?? '').trim();

    if (linked.isNotEmpty) {
      final key = 'obj:$linked';
      final pair = map.putIfAbsent(key, () => _PairTemp());
      pair.tengo = d;
      pair.objetivo ??= targetById[linked];
      continue;
    }

    final key =
        'name:${d.name.toLowerCase()}|ed:${(d.edition ?? '').toLowerCase()}';
    final pair = map.putIfAbsent(key, () => _PairTemp());
    pair.tengo = d;
  }

  return map.values.toList();
}

/// Poster thumb: imagen 120x170 sin nombre, multiplicador arriba-izquierda.
/// Al tocarla abre la imagen en un diálogo a pantalla completa.
class _PosterThumb extends StatelessWidget {
  final String? imageCandidate; // ya transformada a thumb si aplica
  final int qty;

  const _PosterThumb({required this.imageCandidate, required this.qty});

  @override
  Widget build(BuildContext context) {
    const double width = 120.0;
    const double height = 170.0;

    Widget imageWidget;
    if (imageCandidate != null && imageCandidate!.isNotEmpty) {
      final cand = imageCandidate!.trim();
      if (cand.startsWith('http://') || cand.startsWith('https://')) {
        imageWidget = ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: Image.network(
            cand,
            width: width,
            height: height,
            fit: BoxFit.cover,
            errorBuilder:
                (_, __, ___) => Container(
                  width: width,
                  height: height,
                  color: Colors.grey.shade800,
                  child: const Icon(Icons.broken_image, color: Colors.white70),
                ),
            loadingBuilder: (context, child, progress) {
              if (progress == null) return child;
              return Container(
                width: width,
                height: height,
                alignment: Alignment.center,
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    value:
                        progress.expectedTotalBytes != null
                            ? progress.cumulativeBytesLoaded /
                                (progress.expectedTotalBytes ?? 1)
                            : null,
                  ),
                ),
              );
            },
          ),
        );
      } else {
        // candidate no-http (gs:// o path) — solo placeholder visual
        imageWidget = Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            color: Colors.grey.shade700,
            borderRadius: BorderRadius.circular(6),
          ),
          child: const Icon(Icons.image, color: Colors.white70),
        );
      }
    } else {
      imageWidget = Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: Colors.grey.shade700,
          borderRadius: BorderRadius.circular(6),
        ),
        child: const Icon(Icons.image_not_supported, color: Colors.white70),
      );
    }

    // Sin GestureDetector: al tocar la imagen no pasa nada
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Stack(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: imageWidget,
            ),
            Positioned(
              left: 6,
              top: 6,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black87,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  'x$qty',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _PairTemp {
  Deck? tengo;
  Deck? objetivo;
}

// Completitud de un par tengo↔objetivo, cada mazo independiente: se cuenta solo
// lo que el propio "tengo" cubre del objetivo. Sin préstamos entre mazos.
OverallPairCompleteness _computePairCompleteness(
  Deck tengo,
  Deck objetivo,
  List<Deck> allDecks,
) {
  final objetivoMap = _cardCountMap(objetivo.cards);
  final tengoMap = _cardCountMap(tengo.cards);

  int needTotal = 0;
  int haveNow = 0;
  int restAfterBorrow = 0;

  objetivoMap.forEach((name, need) {
    needTotal += need;
    final have = tengoMap[name] ?? 0;
    final covered = (have > need) ? need : have;
    haveNow += covered;
    restAfterBorrow += need - covered;
  });

  return OverallPairCompleteness(
    tengo: tengo,
    objetivo: objetivo,
    needTotal: needTotal,
    haveNow: haveNow,
    contribible: 0,
    restAfterBorrow: restAfterBorrow,
  );
}

List<OverallPairCompleteness> _computeAllPairCompleteness(
  List<Deck> allDecks, {
  List<InventoryItem>? inventory,
}) {
  final pairs = _pairByLinkOrName(allDecks);
  final list = <OverallPairCompleteness>[];
  for (final pair in pairs) {
    final obj = pair.objetivo;
    if (obj == null) continue;
    // Cada par independiente: tengo del propio par (o vacío si no hay).
    final tengo = pair.tengo ?? obj.copyWith(cards: const <DeckCardEntry>[]);
    OverallPairCompleteness comp;
    if (inventory == null) {
      comp = _computePairCompleteness(tengo, obj, allDecks);
    } else {
      final planned =
          buildInventoryPlan(
            inventory: inventory,
            orderedTargets: [obj],
            destinationByTarget: {obj.id: tengo.id},
          ).targets.single;
      final needsByKey = <String, int>{};
      for (final entry in obj.cards) {
        final key = entryInventoryKey(entry);
        needsByKey[key] = (needsByKey[key] ?? 0) + entry.count;
      }
      var alreadyThere = 0;
      for (final need in needsByKey.entries) {
        final item =
            inventory
                .where((candidate) => candidate.key == need.key)
                .firstOrNull;
        alreadyThere += (item?.allocatedTo(deckStockTargetId(tengo)) ?? 0)
            .clamp(0, need.value);
      }
      comp = OverallPairCompleteness(
        tengo: tengo,
        objetivo: obj,
        needTotal: planned.required,
        haveNow: alreadyThere.clamp(0, planned.required),
        contribible: (planned.available - alreadyThere).clamp(
          0,
          planned.required,
        ),
        restAfterBorrow: planned.required - planned.available,
      );
    }
    if (comp.needTotal > 0) list.add(comp);
  }
  return list;
}

/// Reúne faltantes globales, donantes por carta, objetivos por carta, y por-edición.
/// Cada par (tengo↔objetivo) es independiente: el faltante de un mazo se calcula
/// contra su propio tengo, sin pool ni cartas compartidas entre mazos.
OverallMissingData gatherGlobalMissingData(
  List<Deck> allDecks, {
  List<InventoryItem>? inventory,
}) {
  final pairs = _pairByLinkOrName(allDecks);

  final globalMissing = <String, int>{};
  final perCardTargets = <String, List<String>>{};
  final donorsPerCard = <String, Map<String, int>>{};
  final perCardByEdition = <String, Map<String, int>>{};
  final perCardByDeckId = <String, Map<String, int>>{};

  for (final p in pairs) {
    final obj = p.objetivo;
    if (obj == null) continue;

    final needMap = _cardCountMap(obj.cards);
    if (needMap.isEmpty) continue;

    final tengoMap = <String, int>{};
    if (p.tengo != null) {
      if (p.tengo!.isUnified && inventory != null) {
        for (final entry in obj.cards) {
          final item =
              inventory
                  .where(
                    (candidate) => candidate.key == entryInventoryKey(entry),
                  )
                  .firstOrNull;
          tengoMap[entry.name.trim().toLowerCase()] =
              item?.allocatedTo(deckStockTargetId(p.tengo!)) ?? 0;
        }
      } else {
        tengoMap.addAll(_cardCountMap(p.tengo!.cards));
      }
    }
    final edition = (obj.edition ?? 'Sin edición').trim();
    final label =
        obj.name.isNotEmpty ? obj.name : 'Objetivo ${obj.id.substring(0, 6)}';

    // Faltante de este mazo: need[c] - tengo[c] del mismo par.
    needMap.forEach((cardName, need) {
      final have = tengoMap[cardName] ?? 0;
      final falt = need - have;
      if (falt <= 0) return;

      globalMissing[cardName] = (globalMissing[cardName] ?? 0) + falt;
      perCardTargets.putIfAbsent(cardName, () => []).add('$label ($falt)');
      final edMap = perCardByEdition.putIfAbsent(
        cardName,
        () => <String, int>{},
      );
      edMap[edition] = (edMap[edition] ?? 0) + falt;
      perCardByDeckId.putIfAbsent(cardName, () => <String, int>{})[obj.id] =
          falt;
    });
  }

  // donorsPerCard: mazos de otra raza que podrían prestar las cartas faltantes
  // Calculamos el faltante global ya acumulado y buscamos donantes externos
  final nonVariantDecks = allDecks.where((d) => !d.isTarget).toList();
  globalMissing.forEach((cardName, totalFalt) {
    var remaining = totalFalt;
    for (final donor in nonVariantDecks) {
      if (remaining <= 0) break;
      final donorMap =
          donor.isUnified && inventory != null
              ? {
                for (final item in inventory)
                  item.name.trim().toLowerCase(): item.allocatedTo(
                    deckStockTargetId(donor),
                  ),
              }
              : _cardCountMap(donor.cards);
      final available = donorMap[cardName] ?? 0;
      if (available <= 0) continue;
      final take = available < remaining ? available : remaining;
      final donorLabel =
          donor.name.isNotEmpty
              ? donor.name
              : 'Mazo ${donor.id.substring(0, 6)}';
      final map = donorsPerCard.putIfAbsent(cardName, () => <String, int>{});
      map[donorLabel] = (map[donorLabel] ?? 0) + take;
      remaining -= take;
    }
  });

  return OverallMissingData(
    globalMissing: globalMissing,
    donorsPerCard: donorsPerCard,
    perCardTargets: perCardTargets,
    perCardByEdition: perCardByEdition,
    perCardByDeckId: perCardByDeckId,
  );
}

// ----------------- UI: diálogo público -----------------

// ─── Diálogo de completitud (StatefulWidget para el switch) ──────────────────
class _CompletenessDialog extends StatefulWidget {
  final List<OverallPairCompleteness> comps;
  final OverallMissingData globalData;
  final List<Deck> allDecks;
  final int totalNeed;
  final int totalHave;
  final int totalMissing;
  final double globalNowPct;
  final Map<String, String?>? imgByCardId;
  final Map<String, String?>? officialImgByCardId;
  final Map<String, CardMyL>? cardsById;
  final Map<String, CardMyL>? cardsByNameLower;
  final Map<String, dynamic>? cardsByIdDynamic;
  final Map<String, dynamic>? cardsByNameLowerDynamic;

  const _CompletenessDialog({
    required this.comps,
    required this.globalData,
    required this.allDecks,
    required this.totalNeed,
    required this.totalHave,
    required this.totalMissing,
    required this.globalNowPct,
    this.imgByCardId,
    this.officialImgByCardId,
    this.cardsById,
    this.cardsByNameLower,
    this.cardsByIdDynamic,
    this.cardsByNameLowerDynamic,
  });

  @override
  State<_CompletenessDialog> createState() => _CompletenessDialogState();
}

class _CompletenessDialogState extends State<_CompletenessDialog> {
  // false = vista resumen (por raza), true = vista faltantes por mazo
  bool _showMissingByDeck = false;

  // ── Vista faltantes por mazo ───────────────────────────────────────────────
  Widget _buildMissingByDeckView() {
    // Construir: por mazo objetivo → lista de cartas faltantes
    // Usamos perCardByDeckId del globalData
    final perDeckId =
        widget.globalData.perCardByDeckId; // cardName → {deckId → qty}

    // Recolectar todos los objetivos de todos los grupos
    final allObjetivos = <Deck>[];
    for (final c in widget.comps) {
      for (final p in c.sourcePairs) {
        if (p.objetivo != null) allObjetivos.add(p.objetivo!);
      }
    }

    // Invertir: deckId → {cardName → qty}
    final byDeck = <String, Map<String, int>>{};
    perDeckId.forEach((cardName, byDeckId) {
      byDeckId.forEach((deckId, qty) {
        byDeck.putIfAbsent(deckId, () => {})[cardName] = qty;
      });
    });

    if (byDeck.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: Text(
            '¡Sin faltantes!',
            style: TextStyle(
              color: Color(0xFF3FB950),
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      );
    }

    // Ordenar objetivos: primero los que tienen faltantes, por cantidad desc
    final objetivosConFaltantes =
        allObjetivos.where((d) => byDeck.containsKey(d.id)).toList()
          ..sort((a, b) {
            final qa = byDeck[a.id]!.values.fold(0, (s, v) => s + v);
            final qb = byDeck[b.id]!.values.fold(0, (s, v) => s + v);
            return qb.compareTo(qa);
          });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children:
          objetivosConFaltantes.map((obj) {
            final cards = byDeck[obj.id]!;
            final total = cards.values.fold(0, (s, v) => s + v);
            final label = obj.name.isEmpty ? 'Sin nombre' : obj.name;
            final sortedCards =
                cards.entries.toList()
                  ..sort((a, b) => b.value.compareTo(a.value));

            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF10141B),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: const Color(0xFFFF6B6B).withOpacity(.25),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          label,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFF6B6B).withOpacity(.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '$total faltantes',
                          style: const TextStyle(
                            color: Color(0xFFFF6B6B),
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ...sortedCards.map((e) {
                    final cardLabel = prettyCardName(e.key);
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              cardLabel,
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                              ),
                            ),
                          ),
                          Text(
                            'x${e.value}',
                            style: const TextStyle(
                              color: Color(0xFFFF6B6B),
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                ],
              ),
            );
          }).toList(),
    );
  }

  // ── Vista resumen por raza ─────────────────────────────────────────────────
  Widget _buildSummaryView(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ...widget.comps.map((c) {
          final name = c.tengo.name.isEmpty ? '(sin nombre)' : c.tengo.name;
          final isComplete = c.restAfterBorrow == 0;

          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF10141B),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color:
                    isComplete
                        ? const Color(0xFF2EA04B).withOpacity(.5)
                        : Colors.white10,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        name,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Text(
                      '${c.pctNow.toStringAsFixed(1)}%',
                      style: TextStyle(
                        color:
                            isComplete
                                ? const Color(0xFF3FB950)
                                : const Color(0xFFF1D48B),
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: c.pctNow / 100,
                    minHeight: 5,
                    backgroundColor: Colors.white12,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      isComplete
                          ? const Color(0xFF3FB950)
                          : const Color(0xFFF1D48B),
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                if (c.restAfterBorrow > 0)
                  Text(
                    'Faltan ${c.restAfterBorrow} cartas • Tienes ${c.haveNow}/${c.needTotal}',
                    style: const TextStyle(color: Colors.white54, fontSize: 11),
                  )
                else
                  const Text(
                    '¡Armable! Tienes todas las cartas',
                    style: TextStyle(color: Color(0xFF3FB950), fontSize: 11),
                  ),
              ],
            ),
          );
        }),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            icon: const Icon(Icons.format_list_bulleted),
            label: const Text('Ver todas las cartas faltantes'),
            onPressed: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder:
                      (_) => AllMissingCardsScreen(
                        data: widget.globalData,
                        allDecks: widget.allDecks,
                        imgByCardId: widget.imgByCardId,
                        officialImgByCardId: widget.officialImgByCardId,
                        cardsById: widget.cardsById,
                        cardsByNameLower: widget.cardsByNameLower,
                        cardsByIdDynamic: widget.cardsByIdDynamic,
                        cardsByNameLowerDynamic: widget.cardsByNameLowerDynamic,
                        posterMode: true,
                      ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF14181F),
      title: const Text(
        'Estado general de mazos',
        style: TextStyle(color: Colors.white),
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Métricas globales ────────────────────────────────────────
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF1C2330), Color(0xFF2A2018)],
                  ),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white10),
                ),
                child: Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    _OverallMetricPill(
                      label: 'Razas/grupos',
                      value: '${widget.comps.length}',
                    ),
                    _OverallMetricPill(
                      label: 'Completitud',
                      value: '${widget.globalNowPct.toStringAsFixed(1)}%',
                    ),
                    _OverallMetricPill(
                      label: 'Cartas faltantes',
                      value: '${widget.totalMissing}',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              // ── Switch de vista ──────────────────────────────────────────
              Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF0D1016),
                  borderRadius: BorderRadius.circular(20),
                ),
                padding: const EdgeInsets.all(3),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _ViewTab(
                      label: 'Por raza',
                      icon: Icons.layers_outlined,
                      active: !_showMissingByDeck,
                      color: const Color(0xFFF1D48B),
                      onTap: () => setState(() => _showMissingByDeck = false),
                    ),
                    _ViewTab(
                      label: 'Faltantes por mazo',
                      icon: Icons.playlist_remove,
                      active: _showMissingByDeck,
                      color: const Color(0xFFFF6B6B),
                      onTap: () => setState(() => _showMissingByDeck = true),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              // ── Contenido según vista ────────────────────────────────────
              _showMissingByDeck
                  ? _buildMissingByDeckView()
                  : _buildSummaryView(context),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text(
            'Cerrar',
            style: TextStyle(color: Color(0xFFF1D48B)),
          ),
        ),
      ],
    );
  }
}

class _ViewTab extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool active;
  final Color color;
  final VoidCallback onTap;

  const _ViewTab({
    required this.label,
    required this.icon,
    required this.active,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: active ? color.withOpacity(.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(17),
          border: active ? Border.all(color: color.withOpacity(.4)) : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: active ? color : Colors.white38),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                color: active ? color : Colors.white38,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

/// Llamar desde otra pantalla:
/// showOverallCompletenessDialog(context, allDecks, {optional maps...});
Future<void> showOverallCompletenessDialog(
  BuildContext context,
  List<Deck> allDecks, {
  Map<String, String?>? imgByCardId,
  Map<String, String?>? officialImgByCardId,
  Map<String, CardMyL>? cardsById,
  Map<String, CardMyL>? cardsByNameLower,
  Map<String, dynamic>? cardsByIdDynamic,
  Map<String, dynamic>? cardsByNameLowerDynamic,
}) async {
  List<InventoryItem>? inventory;
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid != null) {
    try {
      final service = InventoryService(uid);
      await service.migrateFromDecksIfNeeded(allDecks);
      inventory = await service.listInventory();
    } catch (_) {
      inventory = null;
    }
  }
  final comps = _computeAllPairCompleteness(allDecks, inventory: inventory);
  if (!context.mounted) return;
  if (comps.isEmpty) {
    await showDialog(
      context: context,
      builder:
          (_) => AlertDialog(
            title: const Text('Completitud de mazos'),
            content: const Text(
              'La función de mazos objetivo y comparación avanzada está disponible solo en la versión PRO. '
              'Pásate a PRO para definir objetivos, comparar mazos y ver planes de préstamo con números.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cerrar'),
              ),
            ],
          ),
    );
    return;
  }

  // cálculo ponderado — pool compartido ya integrado en needTotal/haveNow
  int totalNeed = comps.fold<int>(0, (p, e) => p + e.needTotal);
  int totalHave = comps.fold<int>(0, (p, e) => p + e.haveNow);
  int totalMissing = comps.fold<int>(0, (p, e) => p + e.restAfterBorrow);

  final globalNowPct = totalNeed == 0 ? 100.0 : (totalHave / totalNeed) * 100.0;

  comps.sort((a, b) => a.pctNow.compareTo(b.pctNow));

  final globalData = gatherGlobalMissingData(allDecks, inventory: inventory);

  await showDialog(
    context: context,
    builder:
        (ctx) => _CompletenessDialog(
          comps: comps,
          globalData: globalData,
          allDecks: allDecks,
          totalNeed: totalNeed,
          totalHave: totalHave,
          totalMissing: totalMissing,
          globalNowPct: globalNowPct,
          imgByCardId: imgByCardId,
          officialImgByCardId: officialImgByCardId,
          cardsById: cardsById,
          cardsByNameLower: cardsByNameLower,
          cardsByIdDynamic: cardsByIdDynamic,
          cardsByNameLowerDynamic: cardsByNameLowerDynamic,
        ),
  );
}

/// Pantalla que muestra todas las cartas faltantes, ahora agrupadas por edición
/// con un switch y con mini-thumbs (imagen + multiplicador).
// ------------- Reemplazar AllMissingCardsScreen por este bloque -------------
const List<String> _editionOrderPriority = [
  'Espada sagrada',
  'Helenica',
  'Hijos de Daana',
  'Dominios de Ra',
];

String _normEdition(String? raw) {
  if (raw == null) return 'Sin edición';
  final s = raw.trim().toLowerCase();
  if (s.isEmpty) return 'Sin edición';
  if (s.contains('espada') || s.contains('sagrada')) return 'Espada sagrada';
  if (s.contains('helen') || s.contains('helenica') || s.contains('helénica'))
    return 'Helenica';
  if (s.contains('hijos') || s.contains('daana')) return 'Hijos de Daana';
  if (s.contains('domini') || s.contains('ra')) return 'Dominios de Ra';
  final parts = s.split(RegExp(r'\s+'));
  return parts
      .map((p) => p.isEmpty ? p : '${p[0].toUpperCase()}${p.substring(1)}')
      .join(' ');
}

int _editionCompare(String aRaw, String bRaw) {
  final a = _normEdition(aRaw);
  final b = _normEdition(bRaw);
  final ia = _editionOrderPriority.indexOf(a);
  final ib = _editionOrderPriority.indexOf(b);
  if (ia >= 0 || ib >= 0) {
    if (ia >= 0 && ib >= 0) return ia.compareTo(ib);
    if (ia >= 0) return -1;
    return 1;
  }
  return a.toLowerCase().compareTo(b.toLowerCase());
}

class AllMissingCardsScreen extends StatefulWidget {
  final OverallMissingData data;
  final List<Deck> allDecks;
  final Map<String, String?>? imgByCardId;
  final Map<String, String?>? officialImgByCardId;
  final Map<String, CardMyL>? cardsById;
  final Map<String, CardMyL>? cardsByNameLower;
  final Map<String, dynamic>? cardsByIdDynamic;
  final Map<String, dynamic>? cardsByNameLowerDynamic;
  final bool posterMode; // nuevo: si true muestra poster en pantalla completa

  const AllMissingCardsScreen({
    super.key,
    required this.data,
    required this.allDecks,
    this.imgByCardId,
    this.officialImgByCardId,
    this.cardsById,
    this.cardsByNameLower,
    this.cardsByIdDynamic,
    this.cardsByNameLowerDynamic,
    this.posterMode = false,
  });

  @override
  State<AllMissingCardsScreen> createState() => _AllMissingCardsScreenState();
}

class _AllMissingCardsScreenState extends State<AllMissingCardsScreen> {
  bool _showWithLoans = true;
  bool _showByDeck = false; // false = por edición, true = por mazo objetivo
  bool _exportingPoster = false;
  final GlobalKey _posterKey = GlobalKey();
  final Map<String, String?> _resolvedCache = {};

  /// Reusa la lógica de resolución (copia reducida del anterior)
  Future<String?> _resolveImageForCardName(String cardName) async {
    final key = cardName.trim().toLowerCase();
    final normalizedKey = _normalizeCardLookup(cardName);
    String? foundId;

    String? tryFindIdInDecks(String nameKey) {
      for (final d in widget.allDecks) {
        for (final source in [d.cards, d.objectiveCards]) {
          for (final c in source) {
            final nm = _extractCardName(c).trim().toLowerCase();
            final normalizedName = _normalizeCardLookup(nm);
            if (nm == nameKey || normalizedName == normalizedKey) {
              final id = _extractCardId(c);
              if (id != null && id.isNotEmpty) return id;
            }
          }
        }
      }
      return null;
    }

    foundId = tryFindIdInDecks(key);

    if (foundId != null && widget.officialImgByCardId != null) {
      final off = widget.officialImgByCardId![foundId];
      if (off != null && off.isNotEmpty) return thumb120x170(off);
    }

    if (foundId != null && _resolvedCache.containsKey(foundId))
      return thumb120x170(_resolvedCache[foundId]);

    if (foundId != null && widget.imgByCardId != null) {
      final base = widget.imgByCardId![foundId];
      if (base != null && base.isNotEmpty) {
        _resolvedCache[foundId] = base;
        return thumb120x170(base);
      }
    }

    try {
      CardMyL? byLower;
      if (widget.cardsByNameLower != null) {
        byLower = widget.cardsByNameLower![key];
        byLower ??=
            widget.cardsByNameLower!.entries
                .firstWhereOrNull(
                  (entry) => _normalizeCardLookup(entry.key) == normalizedKey,
                )
                ?.value;
      }
      if (byLower != null) {
        final dyn = byLower as dynamic;
        final cand =
            (dyn.officialImageUrl ??
                    dyn.imageUrl ??
                    dyn.image ??
                    dyn.thumbnail ??
                    dyn.url)
                ?.toString();
        if (cand != null && cand.isNotEmpty) return thumb120x170(cand);
        if (dyn.toJson != null) {
          final p = _probeImageFieldsFromDynamic(dyn.toJson());
          if (p != null && p.isNotEmpty) return thumb120x170(p);
        }
      }

      if (foundId != null &&
          widget.cardsById != null &&
          widget.cardsById!.containsKey(foundId)) {
        final dyn = widget.cardsById![foundId] as dynamic;
        final cand =
            (dyn.officialImageUrl ??
                    dyn.imageUrl ??
                    dyn.image ??
                    dyn.thumbnail ??
                    dyn.url)
                ?.toString();
        if (cand != null && cand.isNotEmpty) return thumb120x170(cand);
        if (dyn.toJson != null) {
          final p = _probeImageFieldsFromDynamic(dyn.toJson());
          if (p != null && p.isNotEmpty) return thumb120x170(p);
        }
      }

      if (widget.cardsByIdDynamic != null) {
        for (final v in widget.cardsByIdDynamic!.values) {
          try {
            final nombre =
                ((v is Map) ? (v['nombre'] ?? v['name']) : null)
                    ?.toString()
                    .toLowerCase();
            if (nombre == key ||
                _normalizeCardLookup(nombre ?? '') == normalizedKey) {
              final p = _probeImageFieldsFromDynamic(v);
              if (p != null && p.isNotEmpty) return thumb120x170(p);
            }
          } catch (_) {}
        }
      }

      if (widget.cardsById != null) {
        for (final v in widget.cardsById!.values) {
          try {
            final dyn = v as dynamic;
            final nombre =
                ((dyn.nombre ?? dyn.name) ?? '').toString().toLowerCase();
            if (nombre == key ||
                _normalizeCardLookup(nombre) == normalizedKey) {
              final cand =
                  (dyn.officialImageUrl ??
                          dyn.imageUrl ??
                          dyn.image ??
                          dyn.thumbnail ??
                          dyn.url)
                      ?.toString();
              if (cand != null && cand.isNotEmpty) {
                return thumb120x170(cand);
              }
              if (dyn.toJson != null) {
                final p = _probeImageFieldsFromDynamic(dyn.toJson());
                if (p != null && p.isNotEmpty) return thumb120x170(p);
              }
            }
          } catch (_) {}
        }
      }

      if (foundId != null && widget.cardsByIdDynamic != null) {
        final v = widget.cardsByIdDynamic![foundId];
        final p = _probeImageFieldsFromDynamic(v);
        if (p != null && p.isNotEmpty) return thumb120x170(p);
      }
      dynamic byLowerDynamic;
      if (widget.cardsByNameLowerDynamic != null) {
        byLowerDynamic = widget.cardsByNameLowerDynamic![key];
        byLowerDynamic ??=
            widget.cardsByNameLowerDynamic!.entries
                .firstWhereOrNull(
                  (entry) => _normalizeCardLookup(entry.key) == normalizedKey,
                )
                ?.value;
      }
      if (byLowerDynamic != null) {
        final v = byLowerDynamic;
        final p = _probeImageFieldsFromDynamic(v);
        if (p != null && p.isNotEmpty) return thumb120x170(p);
      }

      if (foundId != null) {
        final ref = FirebaseFirestore.instance.collection('cards').doc(foundId);
        final offSnap =
            await ref
                .collection('variants')
                .where('official', isEqualTo: true)
                .limit(1)
                .get();
        if (offSnap.docs.isNotEmpty) {
          final u =
              (offSnap.docs.first.data()['imageFrontUrl'] as String?)?.trim();
          if (u != null && u.isNotEmpty) {
            _resolvedCache[foundId] = u;
            return thumb120x170(u);
          }
        }
        final anySnap = await ref.collection('variants').limit(1).get();
        if (anySnap.docs.isNotEmpty) {
          final u =
              (anySnap.docs.first.data()['imageFrontUrl'] as String?)?.trim();
          if (u != null && u.isNotEmpty) {
            _resolvedCache[foundId] = u;
            return thumb120x170(u);
          }
        }
      }
    } catch (e, st) {
      developer.log(
        'resolve image error: $e\n$st',
        name: 'overall_completeness',
      );
    }

    return null;
  }

  Future<void> _exportPosterPng() async {
    if (_exportingPoster || !widget.posterMode) return;

    setState(() => _exportingPoster = true);
    try {
      await Future.delayed(const Duration(milliseconds: 120));
      final boundary =
          _posterKey.currentContext?.findRenderObject()
              as RenderRepaintBoundary?;
      if (boundary == null) {
        throw Exception('No se pudo preparar el poster.');
      }

      final image = await boundary.toImage(pixelRatio: 3);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) {
        throw Exception('No se pudo exportar la imagen.');
      }

      final bytes = byteData.buffer.asUint8List();
      await DeckPosterShareService.sharePosterPng(
        posterBytes: bytes,
        deckName:
            _showWithLoans
                ? 'faltantes_con_prestamo'
                : 'faltantes_sin_prestamo',
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('No se pudo exportar el PNG: $e')));
    } finally {
      if (mounted) {
        setState(() => _exportingPoster = false);
      }
    }
  }

  /// Vista faltantes por mazo objetivo — mismo estilo visual que el poster
  /// (imágenes + Wrap de thumbs), pero agrupado por mazo en lugar de por edición.
  Widget _buildByDeckView() {
    final perDeckId = widget.data.perCardByDeckId;

    // Recolectar objetivos (isTarget + embedded)
    final allObjetivos =
        widget.allDecks
            .where((d) => d.isTarget || d.hasEmbeddedObjective)
            .expand<Deck>(
              (d) =>
                  d.hasEmbeddedObjective
                      ? [
                        d.copyWith(
                          cards: d.objectiveCards,
                          status: DeckStatus.published,
                        ),
                      ]
                      : [d],
            )
            .toList();

    // Invertir: deckId → {cardName → qty}
    final byDeck = <String, Map<String, int>>{};
    perDeckId.forEach((cardName, byDeckId) {
      byDeckId.forEach((deckId, qty) {
        byDeck.putIfAbsent(deckId, () => {})[cardName] = qty;
      });
    });

    if (byDeck.isEmpty) {
      return const Center(
        child: Text(
          '¡Sin faltantes!',
          style: TextStyle(
            color: Color(0xFF3FB950),
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
    }

    final objetivos =
        allObjetivos.where((d) => byDeck.containsKey(d.id)).toList()
          ..sort((a, b) {
            final qa = byDeck[a.id]!.values.fold(0, (s, v) => s + v);
            final qb = byDeck[b.id]!.values.fold(0, (s, v) => s + v);
            return qb.compareTo(qa);
          });

    final totalCartas = byDeck.values.fold<int>(
      0,
      (s, m) => s + m.values.fold(0, (a, b) => a + b),
    );

    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header métricas — mismo estilo que el poster
          Container(
            margin: const EdgeInsets.only(bottom: 18),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF1C2330), Color(0xFF2A2018)],
              ),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.white10),
            ),
            child: Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _OverallMetricPill(
                  label: 'Mazos',
                  value: '${objetivos.length}',
                ),
                _OverallMetricPill(
                  label: 'Cartas distintas',
                  value:
                      '${byDeck.values.fold<int>(0, (s, m) => s + m.length)}',
                ),
                _OverallMetricPill(
                  label: 'Total faltantes',
                  value: '$totalCartas',
                ),
              ],
            ),
          ),
          // Una sección por mazo objetivo
          ...objetivos.map((obj) {
            final cards = byDeck[obj.id]!;
            final total = cards.values.fold(0, (s, v) => s + v);
            final label = obj.name.isEmpty ? 'Sin nombre' : obj.name;
            final sorted =
                cards.entries.toList()
                  ..sort((a, b) => b.value.compareTo(a.value));

            final tiles =
                sorted.map((e) {
                  return FutureBuilder<String?>(
                    future: _resolveImageForCardName(e.key),
                    builder: (context, snap) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _PosterThumb(imageCandidate: snap.data, qty: e.value),
                          const SizedBox(height: 6),
                          SizedBox(
                            width: 120,
                            child: Text(
                              prettyCardName(e.key),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      );
                    },
                  );
                }).toList();

            return Padding(
              padding: const EdgeInsets.only(bottom: 18),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF11151C),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: const Color(0xFFFF6B6B).withOpacity(.2),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            label,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                        ),
                        Text(
                          '$total faltantes',
                          style: const TextStyle(
                            color: Color(0xFFFF6B6B),
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Wrap(spacing: 8, runSpacing: 8, children: tiles),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  /// Construye edition -> (cardName -> qty) según modo:
  /// - showWithLoans true: qty = MAX shortage por objetivo dentro de esa edición
  /// - showWithLoans false: qty = SUM shortage por objetivos dentro de esa edición
  Map<String, Map<String, int>> _buildEditionCardMap(bool showWithLoans) {
    // Usa los datos ya calculados en widget.data.perCardByEdition
    // perCardByEdition: cardName -> {edition: qty}
    final editionMap = <String, Map<String, int>>{};

    // prioridad de ediciones (ya la tienes declarada arriba como _editionOrderPriority)
    final preferred = List<String>.from(_editionOrderPriority.map((p) => p));

    // Para procesar todas las ediciones conocidas (por si aparecen otras)
    String _normEd(String raw) => (raw).trim();

    // Recorremos por carta
    widget.data.perCardByEdition.forEach((cardName, byEd) {
      // total aportable para esta carta (sum de donantes)
      final donorsMap = widget.data.donorsPerCard[cardName] ?? {};
      int available = donorsMap.values.fold<int>(0, (p, e) => p + e);

      if (!showWithLoans) {
        // modo SIN PRÉSTAMO: simplemente sumo por edición (mismo comportamiento que antes)
        byEd.forEach((edRaw, qty) {
          final ed = _normEd(edRaw);
          final mapForEd = editionMap.putIfAbsent(ed, () => <String, int>{});
          mapForEd[cardName] = (mapForEd[cardName] ?? 0) + qty;
        });
        return;
      }

      // modo CON PRÉSTAMO: asigno available siguiendo prioridad de ediciones
      // 1) costruyo lista de ediciones a considerar: primero las prioritarias presentes, luego el resto ordenado
      final allEds = byEd.keys.map((e) => _normEd(e)).toSet().toList();

      // edsPrioritarias presentes en esta carta (en el orden _editionOrderPriority)
      final edsPrior = preferred.where((p) => allEds.contains(p)).toList();
      // resto de eds (alfabético) que no están en prioridad
      final edsRest =
          allEds.where((e) => !edsPrior.contains(e)).toList()
            ..sort((a, b) => a.compareTo(b));
      final orderedEds = [...edsPrior, ...edsRest];

      for (final ed in orderedEds) {
        final needInEd =
            byEd[ed] ??
            byEd.entries
                .firstWhereOrNull((en) => _normEd(en.key) == ed)
                ?.value ??
            0;
        if (needInEd <= 0) continue;

        final allocate =
            (available > 0)
                ? (available >= needInEd ? needInEd : available)
                : 0;
        final remaining = needInEd - allocate;
        available -= allocate;

        if (remaining > 0) {
          final mapForEd = editionMap.putIfAbsent(ed, () => <String, int>{});
          mapForEd[cardName] = (mapForEd[cardName] ?? 0) + remaining;
        }
        // si available llega a 0, las siguientes ediciones quedarán con su necesidad completa
      }
    });

    return editionMap;
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.posterMode) {
      // Modo lista existente (no tocamos tu UI original)
      // Build a map edition -> list of (cardName, qty, aportable, donors, targets)
      final Map<String, List<_CardRow>> groupedByEdition = {};
      widget.data.globalMissing.forEach((card, totalQty) {
        final donors = widget.data.donorsPerCard[card] ?? {};
        final aportable = donors.values.fold<int>(0, (p, e) => p + e);
        final targets = widget.data.perCardTargets[card] ?? [];

        final hasLoan = aportable > 0;
        if (_showWithLoans && !hasLoan) return;
        if (!_showWithLoans && hasLoan) return;

        final byEd =
            widget.data.perCardByEdition[card] ?? {'Sin edición': totalQty};

        byEd.forEach((ed, qty) {
          final list = groupedByEdition.putIfAbsent(ed, () => []);
          list.add(
            _CardRow(
              name: card,
              qty: qty,
              aportable: aportable,
              donors: donors,
              targets: targets,
            ),
          );
        });
      });

      final editionEntries = groupedByEdition.entries.toList();
      editionEntries.sort((a, b) {
        final sa = a.value.fold<int>(0, (p, e) => p + e.qty);
        final sb = b.value.fold<int>(0, (p, e) => p + e.qty);
        // prioridad de ediciones por si hay empate en totales -> usar el comparator
        if (sb == sa) return _editionCompare(a.key, b.key);
        return sb.compareTo(sa);
      });

      return Scaffold(
        backgroundColor: const Color(0xFF0D1016),
        appBar: AppBar(
          backgroundColor: const Color(0xFF14181F),
          foregroundColor: Colors.white,
          elevation: 0,
          title: Text(
            _showByDeck
                ? 'Faltantes por mazo'
                : _showWithLoans
                ? 'Faltantes (con préstamo)'
                : 'Faltantes (sin préstamo)',
          ),
          actions: [
            // Switch "Por mazo"
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Por mazo',
                  style: TextStyle(
                    fontSize: 11,
                    color:
                        _showByDeck ? const Color(0xFFFF6B6B) : Colors.white38,
                  ),
                ),
                Switch(
                  value: _showByDeck,
                  activeColor: const Color(0xFFFF6B6B),
                  onChanged: (v) => setState(() => _showByDeck = v),
                ),
              ],
            ),
            // Switch "Con préstamos" (solo relevante en vista por edición)
            if (!_showByDeck)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Préstamos',
                    style: TextStyle(
                      fontSize: 11,
                      color: _showWithLoans ? Colors.white70 : Colors.white38,
                    ),
                  ),
                  Switch(
                    value: _showWithLoans,
                    onChanged: (v) => setState(() => _showWithLoans = v),
                  ),
                ],
              ),
            const SizedBox(width: 4),
          ],
        ),
        body:
            _showByDeck
                ? _buildByDeckView()
                : editionEntries.isEmpty
                ? Center(
                  child: Text(
                    _showWithLoans
                        ? 'No hay cartas faltantes con préstamo.'
                        : 'No hay cartas faltantes sin préstamo.',
                    style: const TextStyle(color: Colors.white),
                  ),
                )
                : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: editionEntries.length,
                  itemBuilder: (context, idx) {
                    final ed = editionEntries[idx].key;
                    final list = editionEntries[idx].value;
                    list.sort((a, b) => b.qty.compareTo(a.qty));
                    final edTotal = list.fold<int>(0, (p, e) => p + e.qty);
                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF14181F),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.white10),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '$ed — Total faltante: $edTotal',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 8),
                            ...list.map((r) {
                              return FutureBuilder<String?>(
                                future: _resolveImageForCardName(r.name),
                                builder: (context, snap) {
                                  final url = snap.data;
                                  final donorsText = r.donors.entries
                                      .map((e) => '${e.key} (${e.value})')
                                      .join(', ');
                                  return ListTile(
                                    contentPadding: EdgeInsets.zero,
                                    leading: _SmallThumb(
                                      imageUrl: url,
                                      qty: r.qty,
                                      name: r.name,
                                    ),
                                    title: Text(
                                      prettyCardName(r.name),
                                      style: const TextStyle(
                                        color: Colors.white,
                                      ),
                                    ),
                                    subtitle: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Faltan: ${r.qty} · Aportable: ${r.aportable}',
                                          style: const TextStyle(
                                            color: Colors.white70,
                                          ),
                                        ),
                                        if (r.targets.isNotEmpty)
                                          Text(
                                            'Objetivos: ${r.targets.join(' — ')}',
                                            style: const TextStyle(
                                              fontSize: 12,
                                              color: Colors.white60,
                                            ),
                                          ),
                                        if (donorsText.isNotEmpty)
                                          Text(
                                            'Donantes: $donorsText',
                                            style: const TextStyle(
                                              fontSize: 12,
                                              color: Colors.white60,
                                            ),
                                          ),
                                      ],
                                    ),
                                  );
                                },
                              );
                            }).toList(),
                          ],
                        ),
                      ),
                    );
                  },
                ),
      );
    }

    // ---------- Poster mode ----------
    final editionCardMap = _buildEditionCardMap(_showWithLoans);
    final editionEntries = editionCardMap.entries.toList();
    editionEntries.sort((a, b) => _editionCompare(a.key, b.key));

    return Scaffold(
      backgroundColor: const Color(0xFF0B0D12),
      appBar: AppBar(
        backgroundColor: const Color(0xFF14181F),
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(
          _showByDeck
              ? 'Faltantes por mazo'
              : _showWithLoans
              ? 'Faltantes (con préstamo)'
              : 'Faltantes (sin préstamo)',
        ),
        actions: [
          // Switch "Por mazo"
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Por mazo',
                style: TextStyle(
                  fontSize: 11,
                  color: _showByDeck ? const Color(0xFFFF6B6B) : Colors.white38,
                ),
              ),
              Switch(
                value: _showByDeck,
                activeColor: const Color(0xFFFF6B6B),
                onChanged: (v) => setState(() => _showByDeck = v),
              ),
            ],
          ),
          // Switch "Con préstamos" + exportar (solo en vista por edición)
          if (!_showByDeck) ...[
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Préstamos',
                  style: TextStyle(
                    fontSize: 11,
                    color: _showWithLoans ? Colors.white70 : Colors.white38,
                  ),
                ),
                Switch(
                  value: _showWithLoans,
                  onChanged: (v) => setState(() => _showWithLoans = v),
                ),
              ],
            ),
            IconButton(
              tooltip: 'Exportar PNG',
              onPressed: _exportingPoster ? null : _exportPosterPng,
              icon:
                  _exportingPoster
                      ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                      : const Icon(Icons.image_outlined),
            ),
          ],
          const SizedBox(width: 4),
        ],
      ),
      body:
          _showByDeck
              ? _buildByDeckView()
              : RepaintBoundary(
                key: _posterKey,
                child:
                    editionEntries.isEmpty
                        ? Center(
                          child: Text(
                            _showWithLoans
                                ? 'No hay cartas faltantes con préstamo.'
                                : 'No hay cartas faltantes sin préstamo.',
                            style: const TextStyle(color: Colors.white),
                          ),
                        )
                        : SingleChildScrollView(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                margin: const EdgeInsets.only(bottom: 18),
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: [
                                      Color(0xFF1C2330),
                                      Color(0xFF2A2018),
                                    ],
                                  ),
                                  borderRadius: BorderRadius.circular(24),
                                  border: Border.all(color: Colors.white10),
                                ),
                                child: Wrap(
                                  spacing: 12,
                                  runSpacing: 12,
                                  children: [
                                    _OverallMetricPill(
                                      label: 'Ediciones',
                                      value: '${editionEntries.length}',
                                    ),
                                    _OverallMetricPill(
                                      label: 'Cartas distintas',
                                      value:
                                          '${editionCardMap.values.fold<int>(0, (p, e) => p + e.length)}',
                                    ),
                                    _OverallMetricPill(
                                      label: _showWithLoans ? 'Modo' : 'Modo',
                                      value:
                                          _showWithLoans
                                              ? 'Con prestamos'
                                              : 'Sin prestamos',
                                    ),
                                  ],
                                ),
                              ),
                              ...editionEntries.map((entry) {
                                final ed = entry.key;
                                final cardsMap = entry.value; // cardName -> qty
                                final totalEd = cardsMap.values.fold<int>(
                                  0,
                                  (p, e) => p + e,
                                );
                                final tiles = <Widget>[];
                                cardsMap.forEach((cardName, qty) {
                                  tiles.add(
                                    FutureBuilder<String?>(
                                      future: _resolveImageForCardName(
                                        cardName,
                                      ),
                                      builder: (context, snap) {
                                        final url = snap.data;
                                        return Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            _PosterThumb(
                                              imageCandidate: url,
                                              qty: qty,
                                            ),
                                            const SizedBox(height: 6),
                                            SizedBox(
                                              width: 120,
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    prettyCardName(cardName),
                                                    style: const TextStyle(
                                                      color: Colors.white,
                                                      fontSize: 12,
                                                    ),
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        );
                                      },
                                    ),
                                  );
                                });

                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 18),
                                  child: Container(
                                    padding: const EdgeInsets.all(16),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF11151C),
                                      borderRadius: BorderRadius.circular(24),
                                      border: Border.all(color: Colors.white10),
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          '$ed — Total faltante: $totalEd',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            color: Colors.white,
                                            fontSize: 16,
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        Wrap(
                                          spacing: 8,
                                          runSpacing: 8,
                                          children: tiles,
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              }).toList(),
                            ],
                          ),
                        ),
              ),
    );
  }
}

String _normalizeCardLookup(String raw) {
  return raw
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[áàä]'), 'a')
      .replaceAll(RegExp(r'[éèë]'), 'e')
      .replaceAll(RegExp(r'[íìï]'), 'i')
      .replaceAll(RegExp(r'[óòö]'), 'o')
      .replaceAll(RegExp(r'[úùü]'), 'u')
      .replaceAll('ñ', 'n')
      .replaceAll(RegExp(r'\s+'), ' ');
}

class _CardRow {
  final String name;
  final int qty;
  final int aportable;
  final Map<String, int> donors;
  final List<String> targets;
  _CardRow({
    required this.name,
    required this.qty,
    required this.aportable,
    required this.donors,
    required this.targets,
  });
}

/// Mini thumb con multiplicador arriba-izquierda
class _SmallThumb extends StatelessWidget {
  final String? imageUrl;
  final int qty;
  final String name;
  const _SmallThumb({this.imageUrl, required this.qty, required this.name});

  @override
  Widget build(BuildContext context) {
    final width = 56.0;
    final height = 80.0;

    Widget imageWidget;
    if (imageUrl != null && imageUrl!.isNotEmpty) {
      imageWidget = ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Image.network(
          imageUrl!,
          width: width,
          height: height,
          fit: BoxFit.cover,
          errorBuilder:
              (_, __, ___) => Container(
                width: width,
                height: height,
                color: Colors.grey.shade800,
                child: const Icon(Icons.broken_image, color: Colors.white70),
              ),
          loadingBuilder: (context, child, progress) {
            if (progress == null) return child;
            return Container(
              width: width,
              height: height,
              alignment: Alignment.center,
              child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  value:
                      progress.expectedTotalBytes != null
                          ? progress.cumulativeBytesLoaded /
                              (progress.expectedTotalBytes ?? 1)
                          : null,
                ),
              ),
            );
          },
        ),
      );
    } else {
      final initial =
          (name.trim().isNotEmpty) ? name.trim()[0].toUpperCase() : '?';
      imageWidget = Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: Colors.grey.shade700,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Center(
          child: Text(
            initial,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 20,
            ),
          ),
        ),
      );
    }

    return Stack(
      children: [
        imageWidget,
        Positioned(
          left: 6,
          top: 6,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.black87,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              'x$qty',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Probing helper (intenta extraer urls desde dinámicos/modelos)
String? _probeImageFieldsFromDynamic(dynamic dyn) {
  if (dyn == null) return null;
  try {
    if (dyn is Map<String, dynamic>) {
      final candidateKeys = [
        'officialImageUrl',
        'official_image_url',
        'imageUrl',
        'image_url',
        'image',
        'thumbnail',
        'thumbnailUrl',
        'thumbnail_url',
        'url',
        'img',
        'photo',
        'cover',
      ];
      for (final k in candidateKeys) {
        if (dyn.containsKey(k) && dyn[k] != null) {
          final v = dyn[k].toString();
          if (v.isNotEmpty) return v;
        }
      }
      for (final k in dyn.keys) {
        final kl = k.toString().toLowerCase();
        if (kl.contains('image') ||
            kl.contains('img') ||
            kl.contains('thumb') ||
            kl.contains('photo') ||
            kl.contains('cover')) {
          final v = dyn[k];
          if (v != null) return v.toString();
        }
      }
    } else {
      final vdyn = dyn as dynamic;
      final possibles = [
        vdyn.officialImageUrl,
        vdyn.imageUrl,
        vdyn.image,
        vdyn.thumbnail,
        vdyn.url,
        vdyn.photo,
        vdyn.cover,
      ];
      for (final p in possibles) {
        if (p != null) return p.toString();
      }
      if (vdyn.toJson != null) {
        final map = vdyn.toJson() as Map<String, dynamic>;
        return _probeImageFieldsFromDynamic(map);
      }
    }
  } catch (_) {}
  return null;
}

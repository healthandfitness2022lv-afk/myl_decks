// lib/screens/overall_completeness.dart
import 'dart:developer' as developer;
import 'package:flutter/material.dart';
import 'package:collection/collection.dart';
import '../../models/deck.dart';
import '../../models/card_myl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// Tipos públicos usados por esta pantalla (evitan private underscores entre archivos)
class OverallPairCompleteness {
  final Deck tengo;
  final Deck objetivo;
  final int needTotal;
  final int haveNow;
  final int contribible;
  final int restAfterBorrow;

  OverallPairCompleteness({
    required this.tengo,
    required this.objetivo,
    required this.needTotal,
    required this.haveNow,
    required this.contribible,
    required this.restAfterBorrow,
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
  final Map<String,int> globalMissing; // cardName -> total faltante
  final Map<String, Map<String,int>> donorsPerCard; // cardName -> {donorLabel: qty}
  final Map<String, List<String>> perCardTargets; // cardName -> ["Objetivo (qty)", ...]
  final Map<String, Map<String,int>> perCardByEdition; // cardName -> {edition: qty}

  OverallMissingData({
    required this.globalMissing,
    required this.donorsPerCard,
    required this.perCardTargets,
    required this.perCardByEdition,
  });
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

Map<String,int> _cardCountMap(List<dynamic> cards) {
  final m = <String,int>{};
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

    final key = 'name:${d.name.toLowerCase()}|ed:${(d.edition ?? '').toLowerCase()}';
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

  const _PosterThumb({
    required this.imageCandidate,
    required this.qty,
  });

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
            errorBuilder: (_, __, ___) => Container(
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
                    value: progress.expectedTotalBytes != null
                        ? progress.cumulativeBytesLoaded / (progress.expectedTotalBytes ?? 1)
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
        ClipRRect(borderRadius: BorderRadius.circular(6), child: imageWidget),
        Positioned(
          left: 6,
          top: 6,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.black87,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text('x$qty', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
          ),
        ),
      ],
    ),
  ],
);

  }
}


class _PairTemp { Deck? tengo; Deck? objetivo; }

/// Calcula plan de préstamos (donorDeckId -> {cardName: qty})
Map<String, Map<String,int>> _computeBorrowPlan(Deck tengo, Deck objetivo, List<Deck> allDecks) {
  final tengoMap = _cardCountMap(tengo.cards);
  final objetivoMap = _cardCountMap(objetivo.cards);

  final faltantes = <String,int>{};
  objetivoMap.forEach((name, need) {
    final have = tengoMap[name] ?? 0;
    final falt = (need > have) ? (need - have) : 0;
    if (falt > 0) faltantes[name] = falt;
  });

  final contribuciones = <String, Map<String,int>>{};
  if (faltantes.isEmpty) return contribuciones;

  final candidateDonors = allDecks.where((d) =>
    d.id != tengo.id && d.id != objetivo.id && (d.isTarget == false)
  ).toList();

  for (final deck in candidateDonors) {
    final deckMap = _cardCountMap(deck.cards);

    for (final entry in List<MapEntry<String,int>>.from(faltantes.entries)) {
      final cardName = entry.key;
      var need = entry.value;
      final available = deckMap[cardName] ?? 0;
      if (available <= 0) continue;

      final take = (available >= need) ? need : available;
      if (take <= 0) continue;

      final byDeck = contribuciones.putIfAbsent(deck.id, () => <String,int>{});
      byDeck[cardName] = (byDeck[cardName] ?? 0) + take;

      need -= take;
      if (need <= 0) {
        faltantes.remove(cardName);
      } else {
        faltantes[cardName] = need;
      }
    }

    if (faltantes.isEmpty) break;
  }

  return contribuciones;
}

OverallPairCompleteness _computePairCompleteness(Deck tengo, Deck objetivo, List<Deck> allDecks) {
  final objetivoMap = _cardCountMap(objetivo.cards);
  final tengoMap = _cardCountMap(tengo.cards);

  int needTotal = 0;
  int haveNow = 0;

  objetivoMap.forEach((name, need) {
    needTotal += need;
    final have = tengoMap[name] ?? 0;
    haveNow += (have > need) ? need : have;
  });

  final plan = _computeBorrowPlan(tengo, objetivo, allDecks);
  int contribible = 0;
  plan.values.forEach((m) {
    contribible += m.values.fold<int>(0, (p,e) => p + e);
  });

  final restAfterBorrow = (() {
    // sumar faltantes del plan
    final falt = <String,int>{};
    objetivoMap.forEach((name, need) {
      final have = tengoMap[name] ?? 0;
      final f = (need > have) ? (need - have) : 0;
      if (f > 0) falt[name] = f;
    });
    plan.forEach((_, contrib) {
      contrib.forEach((card, qty) {
        final prev = falt[card] ?? 0;
        final remain = (prev - qty) > 0 ? (prev - qty) : 0;
        if (remain > 0) falt[card] = remain;
        else falt.remove(card);
      });
    });
    return falt.values.fold<int>(0, (p,e) => p + e);
  })();

  return OverallPairCompleteness(
    tengo: tengo,
    objetivo: objetivo,
    needTotal: needTotal,
    haveNow: haveNow,
    contribible: contribible,
    restAfterBorrow: restAfterBorrow,
  );
}

List<OverallPairCompleteness> _computeAllPairCompleteness(List<Deck> allDecks) {
  final pairs = _pairByLinkOrName(allDecks);
  final list = <OverallPairCompleteness>[];
  for (final p in pairs) {
    if (p.tengo != null && p.objetivo != null) {
      final comp = _computePairCompleteness(p.tengo!, p.objetivo!, allDecks);
      if (comp.needTotal > 0) list.add(comp);
    }
  }
  return list;
}

/// Reúne faltantes globales, donantes por carta, objetivos por carta, y por-edición.
OverallMissingData _gatherGlobalMissingData(List<Deck> allDecks) {
  final pairs = _pairByLinkOrName(allDecks);

  final globalMissing = <String,int>{};
  final perCardTargets = <String, List<String>>{};
  final donorsPerCard = <String, Map<String,int>>{};
  final perCardByEdition = <String, Map<String,int>>{};

  for (final p in pairs) {
    final tengo = p.tengo;
    final objetivo = p.objetivo;
    if (tengo == null || objetivo == null) continue;

    final faltanInicial = <String,int>{};
    for (final obj in objetivo.cards) {
      final name = _extractCardName(obj).trim().toLowerCase();
      final need = _extractCardCount(obj);
      if (name.isEmpty) continue;
      final found = tengo.cards.firstWhereOrNull((c) => _extractCardName(c).trim().toLowerCase() == name);
      final have = found != null ? _extractCardCount(found) : 0;
      if (need > have) {
        final falt = need - have;
        faltanInicial[name] = (faltanInicial[name] ?? 0) + falt;
        // acumular por edición (objetivo.edition)
        final ed = (objetivo.edition ?? 'Sin edición').trim();
        final map = perCardByEdition.putIfAbsent(name, () => <String,int>{});
        map[ed] = (map[ed] ?? 0) + falt;
      }
    }

    if (faltanInicial.isEmpty) continue;

    final objetivoLabel = objetivo.name.isNotEmpty ? objetivo.name : 'Objetivo ${objetivo.id.substring(0,6)}';
    faltanInicial.forEach((cardName, qty) {
      globalMissing[cardName] = (globalMissing[cardName] ?? 0) + qty;
      perCardTargets.putIfAbsent(cardName, () => []).add('$objetivoLabel ($qty)');
    });

    final plan = _computeBorrowPlan(tengo, objetivo, allDecks);
    plan.forEach((deckId, contribMap) {
      final deck = allDecks.firstWhereOrNull((d) => d.id == deckId);
      final deckLabel = (deck != null && deck.name.isNotEmpty) ? deck.name : 'Mazo ${deckId.substring(0,6)}';
      contribMap.forEach((cardName, qty) {
        final map = donorsPerCard.putIfAbsent(cardName, () => <String,int>{});
        map[deckLabel] = (map[deckLabel] ?? 0) + qty;
      });
    });
  }

  return OverallMissingData(
    globalMissing: globalMissing,
    donorsPerCard: donorsPerCard,
    perCardTargets: perCardTargets,
    perCardByEdition: perCardByEdition,
  );
}

// ----------------- UI: diálogo público -----------------

String prettyCardName(String s) {
  final str = s.trim();
  if (str.isEmpty) return str;
  final parts = str.split(RegExp(r'\s+'));
  return parts.map((p) => p.isEmpty ? p : '${p[0].toUpperCase()}${p.substring(1)}').join(' ');
}

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
  final comps = _computeAllPairCompleteness(allDecks);
  if (comps.isEmpty) {
    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
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

  // cálculo ponderado
  int totalNeed = comps.fold<int>(0, (p, e) => p + e.needTotal);
  int weightedNowNumer = comps.fold<int>(0, (p, e) => p + (e.haveNow));
  int weightedWithBorrowNumer = comps.fold<int>(0, (p, e) => p + ((e.haveNow + e.contribible) > e.needTotal ? e.needTotal : (e.haveNow + e.contribible)));

  final globalNowPct = totalNeed == 0 ? 100.0 : (weightedNowNumer / totalNeed) * 100.0;
  final globalWithBorrowPct = totalNeed == 0 ? 100.0 : (weightedWithBorrowNumer / totalNeed) * 100.0;

  // ordenar por peor completitud actual
  comps.sort((a, b) => a.pctNow.compareTo(b.pctNow));

  final globalData = _gatherGlobalMissingData(allDecks);

  await showDialog(
    context: context,
    builder: (_) => AlertDialog(
      title: const Text('Estado general de mazos'),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Mazos evaluados: ${comps.length}'),
            const SizedBox(height: 8),
            Text('• Completitud actual (ponderada): ${globalNowPct.toStringAsFixed(1)}%'),
            Text('• Completitud con préstamos (ponderada): ${globalWithBorrowPct.toStringAsFixed(1)}%'),
            const SizedBox(height: 12),
            const Text('Mazos (actual → con préstamos):', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),

            // 🔁 Mostrar TODOS los mazos (antes .take(8))
            ...comps.map((c) {
              final name = c.tengo.name.isEmpty ? '(sin nombre)' : c.tengo.name;
              return Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text('• $name — ${c.pctNow.toStringAsFixed(1)}% → ${c.pctWithBorrow.toStringAsFixed(1)}%'),
              );
            }).toList(),

            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                icon: const Icon(Icons.format_list_bulleted),
                label: const Text('Ver todas las cartas faltantes'),
                onPressed: () {
                  Navigator.pop(context); // cierra diálogo actual
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => AllMissingCardsScreen(
                        data: globalData,
                        allDecks: allDecks,
                        imgByCardId: imgByCardId,
                        officialImgByCardId: officialImgByCardId,
                        cardsById: cardsById,
                        cardsByNameLower: cardsByNameLower,
                        cardsByIdDynamic: cardsByIdDynamic,
                        cardsByNameLowerDynamic: cardsByNameLowerDynamic,
                        posterMode: true, // <- se mantiene
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cerrar')),
      ],
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
  if (s.contains('helen') || s.contains('helenica') || s.contains('helénica')) return 'Helenica';
  if (s.contains('hijos') || s.contains('daana')) return 'Hijos de Daana';
  if (s.contains('domini') || s.contains('ra')) return 'Dominios de Ra';
  final parts = s.split(RegExp(r'\s+'));
  return parts.map((p) => p.isEmpty ? p : '${p[0].toUpperCase()}${p.substring(1)}').join(' ');
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
  final Map<String, String?> _resolvedCache = {};

  String? _thumb120x170(String? url) {
    if (url == null || url.isEmpty) return null;
    if (!url.contains('/upload/')) return url;
    return url.replaceFirst('/upload/', '/upload/f_auto,q_auto,w_120,h_170,c_fill,g_auto/');
  }

  /// Reusa la lógica de resolución (copia reducida del anterior)
  Future<String?> _resolveImageForCardName(String cardName) async {
    final key = cardName.trim().toLowerCase();
    String? foundId;
    for (final d in widget.allDecks) {
      for (final c in d.cards) {
        final nm = _extractCardName(c).trim().toLowerCase();
        if (nm == key) {
          final id = _extractCardId(c);
          if (id != null && id.isNotEmpty) {
            foundId = id;
            break;
          }
        }
      }
      if (foundId != null) break;
    }

    if (foundId != null && widget.officialImgByCardId != null) {
      final off = widget.officialImgByCardId![foundId];
      if (off != null && off.isNotEmpty) return _thumb120x170(off);
    }

    if (foundId != null && _resolvedCache.containsKey(foundId)) return _thumb120x170(_resolvedCache[foundId]);

    if (foundId != null && widget.imgByCardId != null) {
      final base = widget.imgByCardId![foundId];
      if (base != null && base.isNotEmpty) {
        _resolvedCache[foundId] = base;
        return _thumb120x170(base);
      }
    }

    try {
      if (widget.cardsByNameLower != null && widget.cardsByNameLower!.containsKey(key)) {
        final dyn = widget.cardsByNameLower![key] as dynamic;
        final cand = (dyn.officialImageUrl ?? dyn.imageUrl ?? dyn.image ?? dyn.thumbnail ?? dyn.url)?.toString();
        if (cand != null && cand.isNotEmpty) return _thumb120x170(cand);
        if (dyn.toJson != null) {
          final p = _probeImageFieldsFromDynamic(dyn.toJson());
          if (p != null && p.isNotEmpty) return _thumb120x170(p);
        }
      }

      if (foundId != null && widget.cardsById != null && widget.cardsById!.containsKey(foundId)) {
        final dyn = widget.cardsById![foundId] as dynamic;
        final cand = (dyn.officialImageUrl ?? dyn.imageUrl ?? dyn.image ?? dyn.thumbnail ?? dyn.url)?.toString();
        if (cand != null && cand.isNotEmpty) return _thumb120x170(cand);
        if (dyn.toJson != null) {
          final p = _probeImageFieldsFromDynamic(dyn.toJson());
          if (p != null && p.isNotEmpty) return _thumb120x170(p);
        }
      }

      if (foundId != null && widget.cardsByIdDynamic != null) {
        final v = widget.cardsByIdDynamic![foundId];
        final p = _probeImageFieldsFromDynamic(v);
        if (p != null && p.isNotEmpty) return _thumb120x170(p);
      }
      if (widget.cardsByNameLowerDynamic != null && widget.cardsByNameLowerDynamic!.containsKey(key)) {
        final v = widget.cardsByNameLowerDynamic![key];
        final p = _probeImageFieldsFromDynamic(v);
        if (p != null && p.isNotEmpty) return _thumb120x170(p);
      }

      if (foundId != null) {
        final ref = FirebaseFirestore.instance.collection('cards').doc(foundId);
        final offSnap = await ref.collection('variants').where('official', isEqualTo: true).limit(1).get();
        if (offSnap.docs.isNotEmpty) {
          final u = (offSnap.docs.first.data()['imageFrontUrl'] as String?)?.trim();
          if (u != null && u.isNotEmpty) {
            _resolvedCache[foundId] = u;
            return _thumb120x170(u);
          }
        }
        final anySnap = await ref.collection('variants').limit(1).get();
        if (anySnap.docs.isNotEmpty) {
          final u = (anySnap.docs.first.data()['imageFrontUrl'] as String?)?.trim();
          if (u != null && u.isNotEmpty) {
            _resolvedCache[foundId] = u;
            return _thumb120x170(u);
          }
        }
      }
    } catch (e, st) {
      developer.log('resolve image error: $e\n$st', name: 'overall_completeness');
    }

    return null;
  }

  /// Construye edition -> (cardName -> qty) según modo:
  /// - showWithLoans true: qty = MAX shortage por objetivo dentro de esa edición
  /// - showWithLoans false: qty = SUM shortage por objetivos dentro de esa edición
  Map<String, Map<String,int>> _buildEditionCardMap(bool showWithLoans) {
  // Usa los datos ya calculados en widget.data.perCardByEdition
  // perCardByEdition: cardName -> {edition: qty}
  final editionMap = <String, Map<String,int>>{};

  // prioridad de ediciones (ya la tienes declarada arriba como _editionOrderPriority)
  final preferred = List<String>.from(_editionOrderPriority.map((p) => p));

  // Para procesar todas las ediciones conocidas (por si aparecen otras)
  String _normEd(String raw) => (raw).trim();

  // Recorremos por carta
  widget.data.perCardByEdition.forEach((cardName, byEd) {
    // total aportable para esta carta (sum de donantes)
    final donorsMap = widget.data.donorsPerCard[cardName] ?? {};
    int available = donorsMap.values.fold<int>(0, (p,e) => p + e);

    if (!showWithLoans) {
      // modo SIN PRÉSTAMO: simplemente sumo por edición (mismo comportamiento que antes)
      byEd.forEach((edRaw, qty) {
        final ed = _normEd(edRaw);
        final mapForEd = editionMap.putIfAbsent(ed, () => <String,int>{});
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
    final edsRest = allEds.where((e) => !edsPrior.contains(e)).toList()..sort((a,b) => a.compareTo(b));
    final orderedEds = [...edsPrior, ...edsRest];

    for (final ed in orderedEds) {
      final needInEd = byEd[ed] ?? byEd.entries.firstWhereOrNull((en) => _normEd(en.key) == ed)?.value ?? 0;
      if (needInEd <= 0) continue;

      final allocate = (available > 0) ? (available >= needInEd ? needInEd : available) : 0;
      final remaining = needInEd - allocate;
      available -= allocate;

      if (remaining > 0) {
        final mapForEd = editionMap.putIfAbsent(ed, () => <String,int>{});
        mapForEd[cardName] = (mapForEd[cardName] ?? 0) + remaining;
      }
      // si available llega a 0, las siguientes ediciones quedarán con su necesidad completa
    }
  });

  return editionMap;
}


  String _prettyCardName(String s) {
    final str = s.trim();
    if (str.isEmpty) return str;
    final parts = str.split(RegExp(r'\s+'));
    return parts.map((p) => p.isEmpty ? p : '${p[0].toUpperCase()}${p.substring(1)}').join(' ');
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.posterMode) {
      // Modo lista existente (no tocamos tu UI original)
      // Build a map edition -> list of (cardName, qty, aportable, donors, targets)
      final Map<String, List<_CardRow>> groupedByEdition = {};
      widget.data.globalMissing.forEach((card, totalQty) {
        final donors = widget.data.donorsPerCard[card] ?? {};
        final aportable = donors.values.fold<int>(0, (p,e) => p + e);
        final targets = widget.data.perCardTargets[card] ?? [];

        final hasLoan = aportable > 0;
        if (_showWithLoans && !hasLoan) return;
        if (!_showWithLoans && hasLoan) return;

        final byEd = widget.data.perCardByEdition[card] ?? {'Sin edición': totalQty};

        byEd.forEach((ed, qty) {
          final list = groupedByEdition.putIfAbsent(ed, () => []);
          list.add(_CardRow(
            name: card,
            qty: qty,
            aportable: aportable,
            donors: donors,
            targets: targets,
          ));
        });
      });

      final editionEntries = groupedByEdition.entries.toList();
      editionEntries.sort((a,b) {
        final sa = a.value.fold<int>(0, (p,e) => p + e.qty);
        final sb = b.value.fold<int>(0, (p,e) => p + e.qty);
        // prioridad de ediciones por si hay empate en totales -> usar el comparator
        if (sb == sa) return _editionCompare(a.key, b.key);
        return sb.compareTo(sa);
      });

      return Scaffold(
        appBar: AppBar(
          title: Text(_showWithLoans ? 'Faltantes (con préstamo)' : 'Faltantes (sin préstamo)'),
          actions: [
            Row(children: [
              const Padding(padding: EdgeInsets.only(right:6)),
              const Text('Con préstamos', style: TextStyle(fontSize: 12)),
              Switch(
                value: _showWithLoans,
                onChanged: (v) => setState(() => _showWithLoans = v),
              ),
            ]),
          ],
        ),
        body: editionEntries.isEmpty
            ? Center(child: Text(_showWithLoans ? 'No hay cartas faltantes con préstamo.' : 'No hay cartas faltantes sin préstamo.'))
            : ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: editionEntries.length,
                itemBuilder: (context, idx) {
                  final ed = editionEntries[idx].key;
                  final list = editionEntries[idx].value;
                  list.sort((a,b) => b.qty.compareTo(a.qty));
                  final edTotal = list.fold<int>(0, (p,e) => p + e.qty);
                  return Card(
                    color: Theme.of(context).cardColor,
                    margin: const EdgeInsets.only(bottom: 12),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('$ed — Total faltante: $edTotal', style: const TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        ...list.map((r) {
                          return FutureBuilder<String?>(
                            future: _resolveImageForCardName(r.name),
                            builder: (context, snap) {
                              final url = snap.data;
                              final donorsText = r.donors.entries.map((e) => '${e.key} (${e.value})').join(', ');
                              return ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: _SmallThumb(imageUrl: url, qty: r.qty, name: r.name),
                                title: Text(_prettyCardName(r.name)),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('Faltan: ${r.qty} · Aportable: ${r.aportable}'),
                                    if (r.targets.isNotEmpty) Text('Objetivos: ${r.targets.join(' — ')}', style: const TextStyle(fontSize: 12)),
                                    if (donorsText.isNotEmpty) Text('Donantes: $donorsText', style: const TextStyle(fontSize: 12)),
                                  ],
                                ),
                              );
                            },
                          );
                        }).toList(),
                      ]),
                    ),
                  );
                },
              ),
      );
    }

    // ---------- Poster mode ----------
    final editionCardMap = _buildEditionCardMap(_showWithLoans);
    final editionEntries = editionCardMap.entries.toList();
    editionEntries.sort((a,b) => _editionCompare(a.key, b.key));

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black87,
        title: Text(_showWithLoans ? 'Póster - con préstamos' : 'Póster - sin préstamos'),
        actions: [
          Row(children: [
            const Padding(padding: EdgeInsets.only(right:8)),
            const Text('Con préstamos', style: TextStyle(fontSize: 12)),
            Switch(value: _showWithLoans, onChanged: (v) => setState(() => _showWithLoans = v)),
            const SizedBox(width: 8),
          ]),
        ],
      ),
      body: editionEntries.isEmpty
          ? Center(child: Text(_showWithLoans ? 'No hay cartas faltantes con préstamo.' : 'No hay cartas faltantes sin préstamo.', style: const TextStyle(color: Colors.white)))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: editionEntries.map((entry) {
                  final ed = entry.key;
                  final cardsMap = entry.value; // cardName -> qty
                  final totalEd = cardsMap.values.fold<int>(0, (p,e) => p + e);
                  final tiles = <Widget>[];
                  cardsMap.forEach((cardName, qty) {
                    tiles.add(
                      FutureBuilder<String?>(
                        future: _resolveImageForCardName(cardName),
                        builder: (context, snap) {
                          final url = snap.data;
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _PosterThumb(imageCandidate: url, qty: qty),
                              const SizedBox(height: 6),
                              SizedBox(
                                width: 120,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(_prettyCardName(cardName), style: const TextStyle(color: Colors.white, fontSize: 12), overflow: TextOverflow.ellipsis),
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
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('$ed — Total faltante: $totalEd', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 16)),
                        const SizedBox(height: 8),
                        Wrap(spacing: 8, runSpacing: 8, children: tiles),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
    );
  }
}


class _CardRow {
  final String name;
  final int qty;
  final int aportable;
  final Map<String,int> donors;
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
          errorBuilder: (_, __, ___) => Container(width: width, height: height, color: Colors.grey.shade800, child: const Icon(Icons.broken_image, color: Colors.white70)),
          loadingBuilder: (context, child, progress) {
            if (progress == null) return child;
            return Container(
              width: width,
              height: height,
              alignment: Alignment.center,
              child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, value: progress.expectedTotalBytes != null ? progress.cumulativeBytesLoaded / (progress.expectedTotalBytes ?? 1) : null)),
            );
          },
        ),
      );
    } else {
      final initial = (name.trim().isNotEmpty) ? name.trim()[0].toUpperCase() : '?';
      imageWidget = Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: Colors.grey.shade700,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Center(child: Text(initial, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 20))),
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
            child: Text('x$qty', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
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
        'officialImageUrl', 'official_image_url', 'imageUrl', 'image_url',
        'image', 'thumbnail', 'thumbnailUrl', 'thumbnail_url', 'url', 'img', 'photo', 'cover'
      ];
      for (final k in candidateKeys) {
        if (dyn.containsKey(k) && dyn[k] != null) {
          final v = dyn[k].toString();
          if (v.isNotEmpty) return v;
        }
      }
      for (final k in dyn.keys) {
        final kl = k.toString().toLowerCase();
        if (kl.contains('image') || kl.contains('img') || kl.contains('thumb') || kl.contains('photo') || kl.contains('cover')) {
          final v = dyn[k];
          if (v != null) return v.toString();
        }
      }
    } else {
      final vdyn = dyn as dynamic;
      final possibles = [
        vdyn.officialImageUrl, vdyn.imageUrl, vdyn.image, vdyn.thumbnail, vdyn.url, vdyn.photo, vdyn.cover
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

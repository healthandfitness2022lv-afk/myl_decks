import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/deck.dart';
import '../../models/card_myl.dart';
import './create_deck_screen.dart';
import '../utils/deck_poster.dart';
import '../utils/deck_stats_section.dart'; // 👈 NUEVO IMPORT

class DeckDetailsScreen extends StatefulWidget {
  final Deck deck;
  const DeckDetailsScreen({super.key, required this.deck});

  @override
  State<DeckDetailsScreen> createState() => _DeckDetailsScreenState();
}

class _DeckDetailsScreenState extends State<DeckDetailsScreen> {
  final GlobalKey _posterKey = GlobalKey();
  Map<String, String?> _imgById = {};
  Map<String, CardMyL> _cardsById = {};
  Map<String, CardMyL> _cardsByNameLower = {};
  bool _showPoster = true;

  @override
  void initState() {
    super.initState();
    _loadImgIndex();
  }

  Future<void> _loadImgIndex() async {
    try {
      final snap = await FirebaseFirestore.instance.collection('cards').get();
      final mImg = <String, String?>{};
      final mCards = <String, CardMyL>{};
      final mByName = <String, CardMyL>{};

      for (final d in snap.docs) {
        final data = d.data();
        final card = CardMyL.fromMap(data, d.id);
        mImg[d.id] = data['imageUrl'] as String?;
        mCards[d.id] = card;
        mByName[card.nombre.toLowerCase()] = card;
      }

      if (mounted) {
        setState(() {
          _imgById = mImg;
          _cardsById = mCards;
          _cardsByNameLower = mByName;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _imgById = {};
          _cardsById = {};
          _cardsByNameLower = {};
        });
      }
    }
  }

  String _normTipo(String? t) {
    var s = (t ?? '-').trim().toLowerCase();
    if (s == 'talismán') s = 'talisman';
    if (s == 'tótem') s = 'totem';
    return s;
  }

  String _displayTipo(String t) {
    switch (t) {
      case 'talisman':
        return 'Talismán';
      case 'totem':
        return 'Tótem';
      case 'aliado':
        return 'Aliado';
      case 'arma':
        return 'Arma';
      case 'oro':
        return 'Oro';
      case '-':
        return '-';
      default:
        return t.isEmpty ? '-' : (t[0].toUpperCase() + t.substring(1));
    }
  }

  // 1) Construir breakdown por tipo
Map<String, List<({String name, int count})>> _buildBreakdownByType(Deck d) {
  final map = <String, List<({String name, int count})>>{};
  for (final e in d.cards) {
    final tipo = _normTipo(e.tipo);
    final nombre = _entryName(e) ?? 'Desconocida';
    final list = map.putIfAbsent(tipo, () => <({String name, int count})>[]);
    list.add((name: nombre, count: e.count));
  }
  // Opcional: mergear duplicados por nombre dentro del mismo tipo
  final merged = <String, List<({String name, int count})>>{};
  map.forEach((tipo, list) {
    final acc = <String, int>{};
    for (final it in list) {
      acc[it.name] = (acc[it.name] ?? 0) + it.count;
    }
    final normalized = acc.entries.map((e) => (name: e.key, count: e.value)).toList()
      ..sort((a, b) {
        final c = b.count.compareTo(a.count);
        return c != 0 ? c : a.name.compareTo(b.name);
      });
    merged[tipo] = normalized;
  });
  return merged;
}

Map<String, int> _countByType(Deck d) {
    final agg = <String, int>{};
    for (final e in d.cards) {
      final k = _normTipo(e.tipo);
      agg[k] = (agg[k] ?? 0) + e.count;
    }
    return agg;
  }

  Map<int, int> _goldCurve(Deck d, {int maxCost = 6}) {
    final curve = {for (var i = 0; i <= maxCost; i++) i: 0};
    for (final e in d.cards) {
      final tipo = _normTipo(e.tipo);
      if (tipo == 'oro') continue;
      final c = e.coste ?? 0;
      final bin = c < 0 ? 0 : (c > maxCost ? maxCost : c);
      curve[bin] = (curve[bin] ?? 0) + e.count;
    }
    return curve;
  }

  Map<int, int> _allyCurve(Deck d, {int maxCost = 6}) {
    final curve = {for (var i = 0; i <= maxCost; i++) i: 0};
    for (final e in d.cards) {
      if (_normTipo(e.tipo) != 'aliado') continue;
      final c = e.coste ?? 0;
      final bin = c < 0 ? 0 : (c > maxCost ? maxCost : c);
      curve[bin] = (curve[bin] ?? 0) + e.count;
    }
    return curve;
  }

  int _totalCards(Deck d) => d.cards.fold<int>(0, (s, e) => s + e.count);
  int _uniqueCards(Deck d) => d.cards.where((e) => e.count > 0).length;

  ({double avg, int median, int mode, double pctLow02, int missingCost}) _costStats(Deck d) {
    final expanded = <int>[];
    var missing = 0;
    for (final e in d.cards) {
      if (_normTipo(e.tipo) == 'oro') continue;
      final c = e.coste;
      if (c == null) {
        missing += e.count;
        continue;
      }
      for (int i = 0; i < e.count; i++) expanded.add(c);
    }
    expanded.sort();

    final avg = expanded.isEmpty ? 0.0 : expanded.reduce((a, b) => a + b) / expanded.length;

    int median = 0;
    if (expanded.isNotEmpty) {
      final mid = expanded.length ~/ 2;
      median = expanded.length.isOdd ? expanded[mid] : ((expanded[mid - 1] + expanded[mid]) / 2).round();
    }

    int mode = 0;
    if (expanded.isNotEmpty) {
      final freq = <int, int>{};
      for (final v in expanded) freq[v] = (freq[v] ?? 0) + 1;
      freq.entries.toList().sort((a, b) => b.value.compareTo(a.value));
      mode = freq.entries.first.key;
    }

    final low = expanded.where((v) => v <= 2).length;
    final pctLow = expanded.isEmpty ? 0.0 : (low / expanded.length) * 100.0;

    return (avg: avg, median: median, mode: mode, pctLow02: pctLow, missingCost: missing);
  }

  ({int x1, int x2, int x3, int x4}) _slotCounts(Deck d) {
    int x1 = 0, x2 = 0, x3 = 0, x4 = 0;
    for (final e in d.cards) {
      switch (e.count) {
        case 1:
          x1++;
          break;
        case 2:
          x2++;
          break;
        case 3:
          x3++;
          break;
        default:
          if (e.count >= 4) x4++;
      }
    }
    return (x1: x1, x2: x2, x3: x3, x4: x4);
  }

  String? _entryId(dynamic entry) {
    try { final v = (entry as dynamic).id; if (v != null) return v.toString(); } catch (_) {}
    try { final v = (entry as dynamic).cardId; if (v != null) return v.toString(); } catch (_) {}
    try { final v = (entry as dynamic).cardID; if (v != null) return v.toString(); } catch (_) {}
    try { final v = (entry as dynamic).cid; if (v != null) return v.toString(); } catch (_) {}
    try { final v = (entry as dynamic).card_id; if (v != null) return v.toString(); } catch (_) {}
    return null;
  }

  String? _entryName(dynamic entry) {
    try { final v = (entry as dynamic).nombre; if (v is String && v.isNotEmpty) return v; } catch (_) {}
    try { final v = (entry as dynamic).name; if (v is String && v.isNotEmpty) return v; } catch (_) {}
    try { final v = (entry as dynamic).cardName; if (v is String && v.isNotEmpty) return v; } catch (_) {}
    try { final v = (entry as dynamic).title; if (v is String && v.isNotEmpty) return v; } catch (_) {}
    return null;
  }

  ({double allyCostAvg, double allyStrengthAvg}) _allyAverages(Deck d) {
    int totalCostCopies = 0;
    int totalStrCopies = 0;
    double sumCost = 0;
    double sumStr = 0;

    for (final e in d.cards) {
      CardMyL? card;

      final maybeId = _entryId(e);
      if (maybeId != null) {
        card = _cardsById[maybeId];
      }

      if (card == null) {
        final maybeName = _entryName(e);
        if (maybeName != null) {
          card = _cardsByNameLower[maybeName.toLowerCase()];
        }
      }

      if (card == null) continue;
      if (!card.esAliado) continue;

      if (card.coste != null && card.coste! >= 0) {
  sumCost += card.coste! * e.count;
  totalCostCopies += e.count;
}


      if (card.fuerza != null) {
        sumStr += card.fuerza! * e.count;
        totalStrCopies += e.count;
      }
    }

    final allyCostAvg = totalCostCopies == 0 ? 0.0 : sumCost / totalCostCopies;
    final allyStrengthAvg = totalStrCopies == 0 ? 0.0 : sumStr / totalStrCopies;

    return (allyCostAvg: allyCostAvg, allyStrengthAvg: allyStrengthAvg);
  }

  @override
  Widget build(BuildContext context) {
    final deck = widget.deck;
    final byType = _countByType(deck);
    final curve = _goldCurve(deck, maxCost: 6);
    final allyCurve = _allyCurve(deck, maxCost: 6);
    final total = _totalCards(deck);
    final uniques = _uniqueCards(deck);
    final slots = _slotCounts(deck);

    final nonGoldTotal = total - (byType['oro'] ?? 0);
    final pctOros = total == 0 ? 0.0 : ((byType['oro'] ?? 0) / total) * 100.0;
    final cs = _costStats(deck);
    final al = _allyAverages(deck);
    final breakdown = _buildBreakdownByType(deck);

    return Scaffold(
      backgroundColor: Colors.black87,
      appBar: AppBar(
        title: Text(deck.name.isEmpty ? 'Detalles del mazo' : deck.name),
        actions: [
          IconButton(
            tooltip: _showPoster ? 'Ver estadísticas' : 'Ver póster',
            onPressed: () => setState(() => _showPoster = !_showPoster),
            icon: Icon(_showPoster ? Icons.bar_chart_rounded : Icons.image_outlined),
          ),
          if (_showPoster)
            IconButton(
              tooltip: 'Exportar/Compartir póster',
              onPressed: () => (_posterKey.currentState as dynamic)?.exportPoster(),
              icon: const Icon(Icons.ios_share),
            ),
          IconButton(
            tooltip: 'Editar',
            icon: const Icon(Icons.edit_outlined),
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => CreateDeckScreen(editDeck: deck)),
              );
              if (mounted) setState(() {});
            },
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Container(
        color: const Color.fromARGB(221, 0, 0, 0),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              switchInCurve: Curves.easeOut,
              switchOutCurve: Curves.easeIn,
              child: _showPoster
                  ? DeckPoster(
                      key: _posterKey,
                      deck: deck,
                      imgByCardId: _imgById,
                    )
                  : DeckStatsSection(
  deckName: deck.name,
  totalCards: total,
  nonGoldTotal: nonGoldTotal,
  uniques: uniques,
  pctOros: pctOros,
  allyCostAvg: al.allyCostAvg,
  allyStrengthAvg: al.allyStrengthAvg,
  costAvg: cs.avg,
  costMedian: cs.median,
  costMode: cs.mode,
  pctLow02: cs.pctLow02,
  missingCost: cs.missingCost,
  curve: curve,
  byType: byType,
  allyCurve: allyCurve,
  displayTipo: _displayTipo,
  kMaxCost: 6,
  slots: slots,
  breakdownByType: breakdown,
  catalogByNameLower: _cardsByNameLower, // 👈 IMPORTANTE
),

            ),
          ),
        ),
      ),
    );
  }
}

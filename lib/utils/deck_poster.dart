import 'dart:ui' as ui;
import 'dart:io' show File;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import '../models/deck.dart';

/// DeckPoster mejorado:
/// - Duel view por defecto ocultando el switch
/// - Agrupación por tipos (Aliados, Talismán, Tótem, Armas, Oro, Otros)
/// - Secciones desplegables en vista VS
class DeckPoster extends StatefulWidget {
  final Deck deck;
  final Map<String, String?> imgByCardId;
  final Map<String, String?>? officialImgByCardId;
  final int refreshTick;

  // Duel props
  final Deck? opponentDeck;
  final Map<String, String?>? opponentImgByCardId;
  final Map<String, String?>? opponentOfficialImgByCardId;

  // already removed visual switch; initialDuelMode permite forzar duel mode
  final bool showDuelSwitch; // kept for backwards compatibility but ignored visually
  final bool initialDuelMode;

  const DeckPoster({
    super.key,
    required this.deck,
    required this.imgByCardId,
    this.officialImgByCardId,
    this.refreshTick = 0,
    this.opponentDeck,
    this.opponentImgByCardId,
    this.opponentOfficialImgByCardId,
    this.showDuelSwitch = false,
    this.initialDuelMode = false,
  });

  @override
  State<DeckPoster> createState() => _DeckPosterState();
}

class _DeckPosterState extends State<DeckPoster> {
  final _rbKey = GlobalKey();

  final Map<String, String> _resolvedUrlByCardId = {};
  final Set<String> _officialResolvedIds = {};
  bool _resolving = false;

  bool _duelMode = false;

  // tipo ordering and normalization
  static const _tipoOrder = [
    'aliado',
    'talisman',
    'totem',
    'arma',
    'oro',
  ];

  int _tipoRank(String t) {
    t = _normalizeTipo(t);
    final i = _tipoOrder.indexOf(t);
    return i >= 0 ? i : 999;
  }

  String _normalizeTipo(dynamic raw) {
    if (raw == null) return 'otros';
    var s = raw.toString().trim().toLowerCase();
    if (s.isEmpty) return 'otros';

    // unify accents / synonyms
    s = s.replaceAll('á', 'a').replaceAll('é', 'e').replaceAll('í', 'i').replaceAll('ó', 'o').replaceAll('ú', 'u');
    if (s == 'talismán') s = 'talisman';
    if (s == 'tótem') s = 'totem';
    if (s.contains('aliad')) s = 'aliado';
    if (s.contains('arma')) s = 'arma';
    if (s.contains('oro')) s = 'oro';
    if (s.contains('talis')) s = 'talisman';
    if (s.contains('totem')) s = 'totem';
    // if nothing matched, return as-is (will go to 'otros' bucket if not recognized)
    if (_tipoOrder.contains(s)) return s;
    // map some English variants sometimes present
    if (s == 'ally' || s == 'allied') return 'aliado';
    if (s == 'weapon') return 'arma';
    return s.isNotEmpty ? s : 'otros';
  }

  static const Map<String, String> _tipoLabel = {
    'aliado': 'Aliados',
    'talisman': 'Talismán',
    'totem': 'Tótems',
    'arma': 'Armas',
    'oro': 'Oro',
    'otros': 'Otros',
  };

  String? _thumb120x170(String? url) {
    if (url == null || url.isEmpty) return url;
    if (!url.contains('/upload/')) return url;
    return url.replaceFirst(
      '/upload/',
      '/upload/f_auto,q_auto,w_120,h_170,c_fill,g_auto/',
    );
  }

  Iterable<List<T>> _chunks<T>(List<T> list, int size) sync* {
    for (var i = 0; i < list.length; i += size) {
      yield list.sublist(i, (i + size > list.length) ? list.length : i + size);
    }
  }

  Future<void> _resolveMissingUrls() async {
    if (_resolving) return;
    _resolving = true;
    try {
      final ids = <String>{};
      void collectFromDeck(Deck d) {
        for (final e in d.cards) {
          final id = e.cardId;
          if (id == null || id.isEmpty) continue;
          ids.add(id);
        }
      }

      collectFromDeck(widget.deck);
      if (widget.opponentDeck != null) collectFromDeck(widget.opponentDeck!);
      if (ids.isEmpty) return;

      final db = FirebaseFirestore.instance;

      for (final chunk in _chunks(ids.toList(), 10)) {
        final qs = await db.collection('cards').where(FieldPath.documentId, whereIn: chunk).get();
        for (final doc in qs.docs) {
          final data = doc.data();
          final id = doc.id;
          final officialUrl = (data['officialImageUrl'] as String?)?.trim();
          if (officialUrl != null && officialUrl.isNotEmpty) {
            _resolvedUrlByCardId[id] = officialUrl;
            _officialResolvedIds.add(id);
          } else {
            _officialResolvedIds.remove(id);
          }
        }
      }

      final stillMissing = ids.where((id) => !_resolvedUrlByCardId.containsKey(id));
      for (final id in stillMissing) {
        final cardRef = db.collection('cards').doc(id);
        final offSnap = await cardRef.collection('variants').where('official', isEqualTo: true).limit(1).get();
        if (offSnap.docs.isNotEmpty) {
          final url = (offSnap.docs.first.data()['imageFrontUrl'] as String?)?.trim();
          if (url != null && url.isNotEmpty) {
            _resolvedUrlByCardId[id] = url;
            _officialResolvedIds.add(id);
            continue;
          }
        }
        final anySnap = await cardRef.collection('variants').limit(1).get();
        if (anySnap.docs.isNotEmpty) {
          final url = (anySnap.docs.first.data()['imageFrontUrl'] as String?)?.trim();
          if (url != null && url.isNotEmpty) {
            _resolvedUrlByCardId[id] = url;
          }
        }
      }
    } catch (_) {
      // silent
    } finally {
      if (mounted) setState(() {});
      _resolving = false;
    }
  }

  @override
  void initState() {
    super.initState();
    // duel mode default: initialDuelMode OR if opponent exists
    _duelMode = widget.initialDuelMode || (widget.opponentDeck != null);
    _resolveMissingUrls();
  }

  @override
  void didUpdateWidget(covariant DeckPoster oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.deck != widget.deck ||
        oldWidget.imgByCardId != widget.imgByCardId ||
        oldWidget.officialImgByCardId != widget.officialImgByCardId ||
        oldWidget.refreshTick != widget.refreshTick ||
        oldWidget.opponentDeck != widget.opponentDeck ||
        oldWidget.opponentImgByCardId != widget.opponentImgByCardId ||
        oldWidget.opponentOfficialImgByCardId != widget.opponentOfficialImgByCardId) {
      _resolvedUrlByCardId.clear();
      _officialResolvedIds.clear();
      // preserve duel mode if already set, else fallback
      if (!(_duelMode)) _duelMode = widget.initialDuelMode || (widget.opponentDeck != null);
      _resolveMissingUrls();
    }
  }

  // Construye lista de entries para un mazo -> reutilizable para ambos lados
  List<Map<String, dynamic>> _entriesForDeck(
    Deck deck,
    Map<String, String?> imgMap,
    Map<String, String?>? officialMap,
    Map<String, int>? otherCounts,
  ) {
    final entries = <Map<String, dynamic>>[];
    for (final e in deck.cards) {
      final id = e.cardId;
      final official = (id != null && officialMap != null) ? officialMap[id] : null;
      final base = (id != null) ? imgMap[id] : null;
      final resolved = (id != null) ? _resolvedUrlByCardId[id] : null;
      final chosen = (official != null && official.isNotEmpty)
          ? official
          : ((resolved != null && resolved.isNotEmpty) ? resolved : base);

      final isShared = id != null && otherCounts != null && otherCounts.containsKey(id);
      entries.add({
        'cardId': id,
        'tipo': e.tipo ?? '-',
        'name': e.name,
        'count': e.count,
        'url': _thumb120x170(chosen),
        'isShared': isShared,
        'otherCount': isShared ? otherCounts[id] : 0,
      });
    }

    entries.sort((a, b) {
      final tr = _tipoRank(a['tipo']).compareTo(_tipoRank(b['tipo']));
      if (tr != 0) return tr;
      final cc = (b['count'] as int).compareTo(a['count'] as int);
      if (cc != 0) return cc;
      return (a['name'] as String).toLowerCase().compareTo((b['name'] as String).toLowerCase());
    });

    return entries;
  }

  /// Agrupa por tipo y devuelve pares (tipo -> lista)
  Map<String, List<Map<String, dynamic>>> _groupByTipo(List<Map<String, dynamic>> entries) {
    final Map<String, List<Map<String, dynamic>>> groups = {};
    for (final e in entries) {
      final tipo = _normalizeTipo(e['tipo']);
      final key = (tipo.isEmpty) ? 'otros' : tipo;
      groups.putIfAbsent(key, () => []).add(e);
    }
    return groups;
  }

  Widget _buildTipoSection(String tipoKey, List<Map<String, dynamic>> items, {List<Map<String, dynamic>>? otherItems}) {
  final label = _tipoLabel[tipoKey] ?? (tipoKey.isNotEmpty ? (tipoKey[0].toUpperCase() + tipoKey.substring(1)) : 'Otros');

  // sumar cantidades (counts) en lugar de contar entradas
  final int thisCount = items.fold<int>(0, (s, e) => s + ((e['count'] as int?) ?? 0));
  final int otherCount = (otherItems == null) ? 0 : otherItems.fold<int>(0, (s, e) => s + ((e['count'] as int?) ?? 0));
  final int totalCount = thisCount + otherCount;

  // si otherItems se pasó (duel mode) mostramos el total combinado; si no, mostramos sólo thisCount
  final countLabel = otherItems != null ? '($totalCount)' : '($thisCount)';

  return ExpansionTile(
    initiallyExpanded: true,
    title: Row(
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(width: 8),
        Text(countLabel, style: const TextStyle(color: Colors.grey, fontSize: 12)),
      ],
    ),
    children: [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 6),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: items.map((e) {
            final hasUrl = (e['url'] as String?)?.trim().isNotEmpty ?? false;
            final image = hasUrl
                ? Image.network(e['url'] as String, width: 120, height: 170, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Container(width: 120, height: 170, color: Colors.grey.shade800, child: const Icon(Icons.image_not_supported, color: Colors.white70)))
                : Container(width: 120, height: 170, color: Colors.grey.shade800, child: const Icon(Icons.image_not_supported, color: Colors.white70));

            return Stack(
              children: [
                ClipRRect(borderRadius: BorderRadius.circular(6), child: image),
                Positioned(left: 4, bottom: 4, child: Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(12)), child: Text('x${e['count']}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)))),
                if (e['isShared'] == true)
                  Positioned(right: 4, bottom: 4, child: Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(12)), child: Text('vs x${e['otherCount']}', style: const TextStyle(color: Colors.yellowAccent, fontWeight: FontWeight.bold, fontSize: 11)))),
              ],
            );
          }).toList(),
        ),
      ),
    ],
  );
}


  // Helper para render poster de un lado (agrupado en secciones)
  Widget _buildGroupedPanel(String title, List<Map<String, dynamic>> entries, {List<Map<String, dynamic>>? otherEntries}) {
  final groups = _groupByTipo(entries);
  final otherGroups = (otherEntries != null) ? _groupByTipo(otherEntries) : <String, List<Map<String, dynamic>>>{};

  // union de keys presentes
  final presentKeys = <String>{}..addAll(groups.keys)..addAll(otherGroups.keys);

  // order keys: primero los tipos definidos por _tipoOrder, luego los demás ordenados alfa, por último 'otros'
  final ordered = <String>[];
  for (final t in _tipoOrder) {
    if (presentKeys.contains(t)) ordered.add(t);
  }
  final remaining = presentKeys.difference(ordered.toSet()).where((k) => k != 'otros').toList()..sort();
  ordered.addAll(remaining);
  if (presentKeys.contains('otros')) ordered.add('otros');

  return Flexible(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // header with deck name
        Padding(
          padding: const EdgeInsets.only(bottom: 6.0),
          child: Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
        // sections (pasamos otherItems para que la sección pueda mostrar el total combinado)
        ...ordered.map((k) => _buildTipoSection(k, groups[k] ?? [], otherItems: otherGroups[k] ?? [])).toList(),
      ],
    ),
  );
}


  Future<void> exportPoster() async {
    try {
      final urls = <String>[];

      void collectFromEntries(List<Map<String, dynamic>> ents) {
        for (final e in ents) {
          final u = e['url'] as String?;
          if (u != null && u.isNotEmpty) urls.add(u);
        }
      }

      final mainEntries = _entriesForDeck(widget.deck, widget.imgByCardId, widget.officialImgByCardId, null);
      collectFromEntries(mainEntries);

      if (_duelMode && widget.opponentDeck != null) {
        final oppEntries = _entriesForDeck(widget.opponentDeck!, widget.opponentImgByCardId ?? {}, widget.opponentOfficialImgByCardId, null);
        collectFromEntries(oppEntries);
      }

      for (final u in urls) {
        final ctx = _rbKey.currentContext;
        if (ctx != null) {
          await precacheImage(NetworkImage(u), ctx);
        }
      }
      await Future.delayed(const Duration(milliseconds: 50));

      final boundary = _rbKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final ui.Image image = await boundary.toImage(pixelRatio: 3);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      final bytes = byteData!.buffer.asUint8List();

      if (kIsWeb) {
        final xf = XFile.fromData(bytes, mimeType: 'image/png', name: 'deck_poster.png');
        await Share.shareXFiles([xf], text: 'Mi mazo — Mitos y Leyendas');
      } else {
        final dir = await getTemporaryDirectory();
        final file = File('${dir.path}/deck_poster.png');
        await file.writeAsBytes(bytes);
        await Share.shareXFiles([XFile(file.path)], text: 'Mi mazo — Mitos y Leyendas');
      }
    } catch (e) {
      debugPrint('❌ Error exportando poster: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    // counts for shared detection
    Map<String, int> countsMain = {};
    for (final c in widget.deck.cards) {
      if (c.cardId != null) countsMain[c.cardId!] = (countsMain[c.cardId!] ?? 0) + c.count;
    }
    Map<String, int> countsOpp = {};
    if (widget.opponentDeck != null) {
      for (final c in widget.opponentDeck!.cards) {
        if (c.cardId != null) countsOpp[c.cardId!] = (countsOpp[c.cardId!] ?? 0) + c.count;
      }
    }

    final mainEntries = _entriesForDeck(widget.deck, widget.imgByCardId, widget.officialImgByCardId, widget.opponentDeck != null ? countsOpp : null);
    List<Map<String, dynamic>>? oppEntries;
    if (widget.opponentDeck != null) {
      oppEntries = _entriesForDeck(widget.opponentDeck!, widget.opponentImgByCardId ?? {}, widget.opponentOfficialImgByCardId, countsMain);
    }


    final content = RepaintBoundary(
      key: _rbKey,
      child: Container(
        color: Colors.transparent,
        padding: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // SWITCH intentionally hidden; duel mode controlled by initialDuelMode/opponentDeck
            // Vista normal (no duel) - como antes: listado plano
            if (!_duelMode || widget.opponentDeck == null)
              Wrap(
                alignment: WrapAlignment.start,
                crossAxisAlignment: WrapCrossAlignment.start,
                spacing: 8,
                runSpacing: 8,
                children: mainEntries.map((e) {
                  final hasUrl = (e['url'] as String?)?.trim().isNotEmpty ?? false;
                  final image = hasUrl
                      ? Image.network(e['url'] as String, width: 120, height: 170, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Container(width: 120, height: 170, color: Colors.grey.shade800, child: const Icon(Icons.image_not_supported, color: Colors.white70)))
                      : Container(width: 120, height: 170, color: Colors.grey.shade800, child: const Icon(Icons.image_not_supported, color: Colors.white70));

                  return Stack(
                    children: [
                      ClipRRect(borderRadius: BorderRadius.circular(6), child: image),
                      Positioned(left: 4, bottom: 4, child: Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(12)), child: Text('x${e['count']}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)))),
                      if (e['isShared'] == true) Positioned(right: 4, bottom: 4, child: Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(12)), child: Text('vs x${e['otherCount']}', style: const TextStyle(color: Colors.yellowAccent, fontWeight: FontWeight.bold, fontSize: 11)))),
                    ],
                  );
                }).toList(),
              )
            else
              // Duel view: grouped panels + VS column
              SizedBox(
                width: double.infinity,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildGroupedPanel(widget.deck.name, mainEntries),
                    // VS central
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12.0),
                      child: Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(color: Colors.redAccent, borderRadius: BorderRadius.circular(8)),
                            child: const Text('VS', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                          ),
                          const SizedBox(height: 8),                          
                        ],
                      ),
                    ),
                    _buildGroupedPanel(widget.opponentDeck!.name, oppEntries ?? []),
                  ],
                ),
              ),

            if (_resolving) const Padding(padding: EdgeInsets.only(top: 8.0), child: LinearProgressIndicator(minHeight: 2)),
          ],
        ),
      ),
    );

    return Stack(children: [content, if (_resolving) const Positioned(left: 0, right: 0, top: 0, child: LinearProgressIndicator(minHeight: 2))]);
  }
}
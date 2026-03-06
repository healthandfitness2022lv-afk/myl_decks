// lib/screens/deck_diff_dialog.dart
import 'dart:developer' as developer;
import 'package:flutter/material.dart';
import 'package:collection/collection.dart';
import '../../models/deck.dart';
import '../../models/card_myl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// Versión del diálogo en formato póster: fondo negro, sin nombres, con multiplicador arriba.
/// Además la sección "Aportable" indica de qué mazo(s) proviene cada carta.
Future<void> showDeckDiffDialog(
  BuildContext context,
  Deck tengo,
  Deck objetivo,
  List<Deck> allDecks, {
  Map<String, CardMyL>? cardsById,
  Map<String, CardMyL>? cardsByNameLower,
  Map<String, dynamic>? cardsByIdDynamic,
  Map<String, dynamic>? cardsByNameLowerDynamic,
  Map<String, String?>? imgByCardId,
  Map<String, String?>? officialImgByCardId,
}) async {
  await Navigator.of(context).push(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => _DeckDiffScreen(
        tengo: tengo,
        objetivo: objetivo,
        allDecks: allDecks,
        cardsById: cardsById,
        cardsByNameLower: cardsByNameLower,
        cardsByIdDynamic: cardsByIdDynamic,
        cardsByNameLowerDynamic: cardsByNameLowerDynamic,
        imgByCardId: imgByCardId,
        officialImgByCardId: officialImgByCardId,
      ),
    ),
  );
}

class _DeckDiffScreen extends StatefulWidget {
  final Deck tengo;
  final Deck objetivo;
  final List<Deck> allDecks;
  final Map<String, CardMyL>? cardsById;
  final Map<String, CardMyL>? cardsByNameLower;
  final Map<String, dynamic>? cardsByIdDynamic;
  final Map<String, dynamic>? cardsByNameLowerDynamic;
  final Map<String, String?>? imgByCardId;
  final Map<String, String?>? officialImgByCardId;

  const _DeckDiffScreen({
    required this.tengo,
    required this.objetivo,
    required this.allDecks,
    this.cardsById,
    this.cardsByNameLower,
    this.cardsByIdDynamic,
    this.cardsByNameLowerDynamic,
    this.imgByCardId,
    this.officialImgByCardId,
  });

  @override
  State<_DeckDiffScreen> createState() => _DeckDiffScreenState();
}

class _DeckDiffScreenState extends State<_DeckDiffScreen> {
  final Map<String, String> _resolvedUrlByCardId = {};
  final Set<String> _officialResolvedIds = {};
  bool _resolving = false;

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

  // Reemplaza/pega esto (misma clase)
bool _isSameDeck(Deck a, Deck b) {
  final aId = (a.id).trim();
  final bId = (b.id).trim();

  // Si ambos tienen id y coinciden -> mismo mazo
  if (aId.isNotEmpty && bId.isNotEmpty && aId == bId) return true;

  // Si ambos tienen nombre no vacío y coinciden, y además los conteos de cartas coinciden -> mismo mazo
  final aName = (a.name).trim().toLowerCase();
  final bName = (b.name).trim().toLowerCase();
  if (aName.isNotEmpty && aName == bName) {
    final am = _cardCountMap(a.cards);
    final bm = _cardCountMap(b.cards);
    if (const DeepCollectionEquality().equals(am, bm)) return true;
  }

  return false;
}



// Reemplaza/pega esto (misma clase)
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

  // Preparar lista de donantes: excluir mazos que sean 'tengo' o 'objetivo' por heurística robusta
  final candidateDonors = <Deck>[];
  for (final d in allDecks) {
    if (_isSameDeck(d, tengo)) {
      developer.log('deck_diff_debug: excluyendo ${d.name} (id:${d.id}) por ser igual a tengo', name: 'deck_diff_debug');
      continue;
    }
    if (_isSameDeck(d, objetivo)) {
      developer.log('deck_diff_debug: excluyendo ${d.name} (id:${d.id}) por ser igual a objetivo', name: 'deck_diff_debug');
      continue;
    }

    if (d.isTarget == true) {
      developer.log('deck_diff_debug: excluyendo ${d.name} (id:${d.id}) por isTarget==true', name: 'deck_diff_debug');
      continue;
    }

    final idTrim = (d.id).trim();
    if (idTrim.isEmpty) {
      developer.log('deck_diff_debug: excluyendo ${d.name} por id vacío', name: 'deck_diff_debug');
      continue;
    }

    candidateDonors.add(d);
  }

  developer.log('deck_diff_debug: candidateDonors -> ${candidateDonors.map((d) => {'id': d.id, 'name': d.name}).toList()}', name: 'deck_diff_debug');

  for (final deck in candidateDonors) {
    final deckMap = _cardCountMap(deck.cards);

    for (final entry in List<MapEntry<String,int>>.from(faltantes.entries)) {
      final cardName = entry.key;
      var need = entry.value;
      final available = deckMap[cardName] ?? 0;
      if (available <= 0) continue;

      final take = (available >= need) ? need : available;
      if (take <= 0) continue;

      final key = (deck.id).trim();
      final byDeck = contribuciones.putIfAbsent(key, () => <String,int>{});
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

  developer.log('deck_diff_debug: contribuciones finales -> $contribuciones', name: 'deck_diff_debug');
  return contribuciones;
}


  Iterable<List<T>> _chunks<T>(List<T> list, int size) sync* {
    for (var i = 0; i < list.length; i += size) {
      yield list.sublist(i, (i + size > list.length) ? list.length : i + size);
    }
  }

  Future<void> _resolveMissingUrlsForCardIds(Iterable<String> ids) async {
    if (_resolving) return;
    _resolving = true;
    try {
      final db = FirebaseFirestore.instance;
      final idList = ids.where((i) => i.isNotEmpty).toList();
      if (idList.isEmpty) return;

      for (final chunk in _chunks(idList, 10)) {
        final qs = await db.collection('cards').where(FieldPath.documentId, whereIn: chunk).get();
        for (final doc in qs.docs) {
          final id = doc.id;
          final data = doc.data();
          final officialUrl = (data['officialImageUrl'] as String?)?.trim();
          if (officialUrl != null && officialUrl.isNotEmpty) {
            _resolvedUrlByCardId[id] = officialUrl;
            _officialResolvedIds.add(id);
          } else {
            _officialResolvedIds.remove(id);
          }
        }
      }

      final stillMissing = idList.where((id) => !_resolvedUrlByCardId.containsKey(id)).toList();
      for (final id in stillMissing) {
        final cardRef = FirebaseFirestore.instance.collection('cards').doc(id);
        try {
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
        } catch (_) {}
      }
    } catch (e, st) {
      developer.log('deck_diff resolve error: $e\n$st', name: 'deck_diff');
    } finally {
      if (mounted) setState(() {});
      _resolving = false;
    }
  }

  String? _thumb120x170(String? url) {
    if (url == null || url.isEmpty) return url;
    if (!url.contains('/upload/')) return url;
    return url.replaceFirst('/upload/', '/upload/f_auto,q_auto,w_120,h_170,c_fill,g_auto/');
  }

  @override
  void initState() {
    super.initState();
    _scheduleResolve();
  }

  Future<void> _scheduleResolve() async {
    final ids = <String>{};
    void collectFromDeck(Deck d) {
      for (final c in d.cards) {
        final id = _extractCardId(c);
        if (id != null && id.isNotEmpty) ids.add(id);
      }
    }

    collectFromDeck(widget.tengo);
    collectFromDeck(widget.objetivo);
    for (final d in widget.allDecks) collectFromDeck(d);

    await _resolveMissingUrlsForCardIds(ids);
  }

  String? _findImageCandidateForName(String cardName) {
    final key = cardName.trim().toLowerCase();
    developer.log('deck_diff: probe candidate for "$key"', name: 'deck_diff');

    String? foundFromModel;
    if (widget.cardsByNameLowerDynamic?.containsKey(key) == true) {
      final probe = _probeImageFieldsFromDynamic(widget.cardsByNameLowerDynamic![key]);
      if (probe != null) foundFromModel = probe;
    }
    if (foundFromModel == null && widget.cardsByNameLower?.containsKey(key) == true) {
      try {
        final dyn = widget.cardsByNameLower![key] as dynamic;
        final candidate = (dyn.officialImageUrl ?? dyn.imageUrl ?? dyn.image ?? dyn.thumbnail ?? dyn.url)?.toString();
        if (candidate != null && candidate.isNotEmpty) foundFromModel = candidate;
        else if (dyn.toJson != null) {
          final map = dyn.toJson() as Map<String, dynamic>;
          final probe = _probeImageFieldsFromDynamic(map);
          if (probe != null) foundFromModel = probe;
        }
      } catch (_) {}
    }

    String? tryFindIdInDecks(String nameKey) {
      for (final d in [widget.tengo, widget.objetivo, ...widget.allDecks]) {
        for (final c in d.cards) {
          final nm = _extractCardName(c).trim().toLowerCase();
          if (nm == nameKey) {
            final id = _extractCardId(c);
            if (id != null && id.isNotEmpty) return id;
          }
        }
      }
      return null;
    }
    final foundId = tryFindIdInDecks(key);

    if (foundId != null && widget.officialImgByCardId != null) {
      final official = widget.officialImgByCardId![foundId];
      if (official != null && official.isNotEmpty) {
        developer.log('deck_diff: found official prop for id $foundId', name: 'deck_diff');
        return _thumb120x170(official);
      }
    }

    if (foundId != null && _resolvedUrlByCardId.containsKey(foundId)) {
      final url = _resolvedUrlByCardId[foundId];
      if (url != null && url.isNotEmpty) {
        developer.log('deck_diff: found resolved url for id $foundId -> $url', name: 'deck_diff');
        return _thumb120x170(url);
      }
    }

    if (foundId != null && widget.imgByCardId != null) {
      final base = widget.imgByCardId![foundId];
      if (base != null && base.isNotEmpty) {
        developer.log('deck_diff: found base imgByCardId for id $foundId -> $base', name: 'deck_diff');
        return _thumb120x170(base);
      }
    }

    if (foundFromModel != null && foundFromModel.isNotEmpty) {
      developer.log('deck_diff: found candidate from model/dynamic -> $foundFromModel', name: 'deck_diff');
      return _thumb120x170(foundFromModel);
    }

    if (widget.cardsByIdDynamic != null) {
      for (final v in widget.cardsByIdDynamic!.values) {
        try {
          final nombre = ((v is Map) ? (v['nombre'] ?? v['name']) : null)?.toString().toLowerCase();
          if (nombre == key) {
            final cand = _probeImageFieldsFromDynamic(v);
            if (cand != null && cand.isNotEmpty) {
              developer.log('deck_diff: found candidate in cardsByIdDynamic -> $cand', name: 'deck_diff');
              return _thumb120x170(cand);
            }
          }
        } catch (_) {}
      }
    }

    if (widget.cardsById != null) {
      for (final v in widget.cardsById!.values) {
        try {
          final dyn = v as dynamic;
          final nombre = ((dyn.nombre ?? dyn.name) ?? '').toString().toLowerCase();
          if (nombre == key) {
            final candidate = (dyn.officialImageUrl ?? dyn.imageUrl ?? dyn.image ?? dyn.thumbnail ?? dyn.url)?.toString();
            if (candidate != null && candidate.isNotEmpty) {
              developer.log('deck_diff: found candidate in cardsById model -> $candidate', name: 'deck_diff');
              return _thumb120x170(candidate);
            }
            if (dyn.toJson != null) {
              final probe = _probeImageFieldsFromDynamic(dyn.toJson());
              if (probe != null) return _thumb120x170(probe);
            }
          }
        } catch (_) {}
      }
    }

    developer.log('deck_diff: no image candidate for "$key"', name: 'deck_diff');
    return null;
  }

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

  Widget _buildPosterGridFromMap(Map<String,int> map, { Map<String, Map<String,int>>? donorsByCard }) {
    // map: cardName -> qty
    final tiles = <Widget>[];
    map.forEach((name, qty) {
      final candidate = _findImageCandidateForName(name);
      final donors = donorsByCard == null ? null : (donorsByCard[name] ?? {});
      tiles.add(_PosterThumb(
        imageCandidate: candidate,
        cardName: name,
        qty: qty,
        donors: donors,
        onTapDonors: donors == null || donors.isEmpty ? null : () => _showDonorsDialog(name, donors),
      ));
    });
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: tiles,
    );
  }

  String _prettyCardName(String s) {
  final str = s.trim();
  if (str.isEmpty) return str;
  final parts = str.split(RegExp(r'\s+'));
  return parts.map((p) => p.isEmpty ? p : '${p[0].toUpperCase()}${p.substring(1)}').join(' ');
}

void _showDonorsDialog(String cardName, Map<String,int> donors) {
    showDialog(
      context: context,
      builder: (_) {
        final list = donors.entries.toList();
        return AlertDialog(
          title: Text(_prettyCardName(cardName)),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.separated(
              shrinkWrap: true,
              itemBuilder: (_, i) {
                final e = list[i];
                return ListTile(
                  title: Text(e.key),
                  subtitle: Text('Cantidad disponible: ${e.value}'),
                );
              },
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemCount: list.length,
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cerrar')),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    // calcular faltantes usando mapas agregados (coherente con _computeBorrowPlan)
    final tengoMap = _cardCountMap(widget.tengo.cards);
    final objetivoMap = _cardCountMap(widget.objetivo.cards);

    final faltanInicial = <String,int>{};
    objetivoMap.forEach((name, need) {
      final have = tengoMap[name] ?? 0;
      final falt = (need > have) ? (need - have) : 0;
      if (falt > 0) faltanInicial[name] = falt;
    });

    if (faltanInicial.isEmpty) {
      return Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(title: const Text('Cartas faltantes')),
        body: const Center(child: Text('¡Este mazo ya cumple con el objetivo!')),
      );
    }

    final plan = _computeBorrowPlan(widget.tengo, widget.objetivo, widget.allDecks);

    final aportablePorCarta = <String,int>{};
    plan.forEach((_, contrib) {
      contrib.forEach((cardName, qty) {
        aportablePorCarta[cardName] = (aportablePorCarta[cardName] ?? 0) + qty;
      });
    });

    

    final donorsByCard = <String, Map<String,int>>{};
    // Construir mapa nombre->cantidad de mazos con ese nombre (para detectar colisiones)
final nameCounts = <String,int>{};
for (final d in widget.allDecks) {
  final n = (d.name).trim();
  if (n.isEmpty) continue;
  nameCounts[n] = (nameCounts[n] ?? 0) + 1;
}

plan.forEach((deckId, contrib) {
  final deck = widget.allDecks.firstWhereOrNull((d) => (d.id).trim() == (deckId).trim());
  String deckLabel;
  if (deck == null) {
    final idShort = deckId.length >= 6 ? deckId.substring(0,6) : deckId;
    deckLabel = 'Mazo $idShort';
  } else {
    final name = (deck.name).trim();
    if (name.isEmpty) {
      final idShort = deck.id.length >= 6 ? deck.id.substring(0,6) : deck.id;
      deckLabel = 'Mazo $idShort';
    } else {
      // Solo añadimos id corto si hay más de 1 mazo con el mismo nombre
      if ((nameCounts[name] ?? 0) > 1) {
        final idShort = (deck.id).length >= 6 ? (deck.id).substring(0,6) : (deck.id);
        deckLabel = '$name (id:$idShort)';
      } else {
        deckLabel = name;
      }
    }
  }

  contrib.forEach((cardName, qty) {
    final map = donorsByCard.putIfAbsent(cardName, () => <String,int>{});
    map[deckLabel] = (map[deckLabel] ?? 0) + qty;
  });
});


    final restAfter = <String,int>{};
    faltanInicial.forEach((card, need) {
      final aport = aportablePorCarta[card] ?? 0;
      final r = (need - aport) > 0 ? (need - aport) : 0;
      if (r > 0) restAfter[card] = r;
    });

    final totalFaltanInicial = faltanInicial.values.fold<int>(0, (p,e) => p + e);
    final totalContribuible = aportablePorCarta.values.fold<int>(0, (p,e) => p + e);
    final totalQuedaran = restAfter.values.fold<int>(0, (p,e) => p + e);
    final canBuild = totalQuedaran == 0;
    

    // UI: fondo negro, textos en blanco
    final titleStyle = const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white);
    final infoStyle = TextStyle(color: Colors.white70);

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.grey[900],
        title: Text(canBuild ? 'Se puede armar (con préstamos)' : 'No se puede armar completamente'),
        centerTitle: true,
        actions: [
          if (_resolving) const Padding(padding: EdgeInsets.symmetric(horizontal:12), child: Center(child: SizedBox(width:16,height:16, child:CircularProgressIndicator(strokeWidth:2)))),
          IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.of(context).pop()),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // FALTANTES (mosaico)
            Text('Cartas faltantes ($totalFaltanInicial)', style: titleStyle),
            const SizedBox(height: 8),
            _buildPosterGridFromMap(faltanInicial),

            const SizedBox(height: 18),

            // APORTABLE (mosaico) — PASAMOS donorsByCard para que el thumb sepa de dónde viene
            Text('Total aportable ($totalContribuible)', style: titleStyle),
            const SizedBox(height: 8),
            if (aportablePorCarta.isEmpty)
              Text('No hay cartas disponibles para prestar desde otros mazos.', style: infoStyle)
            else
              _buildPosterGridFromMap(aportablePorCarta, donorsByCard: donorsByCard),

            const SizedBox(height: 18),

            // REST AFTER (mosaico)
            Text('Faltantes tras aportes ($totalQuedaran)', style: titleStyle),
            const SizedBox(height: 8),
            if (restAfter.isEmpty)
              Text('No quedarán cartas faltantes después de los préstamos.', style: infoStyle)
            else
              _buildPosterGridFromMap(restAfter),

            const SizedBox(height: 22),
            Text(
              canBuild ? 'Resumen: con los préstamos propuestos se puede completar el mazo objetivo.' :
              'Resumen: faltan cartas que no pueden ser aportadas por los mazos disponibles.',
              style: const TextStyle(fontStyle: FontStyle.italic, color: Colors.white70),
            ),

            const SizedBox(height: 18),
            if (canBuild)
              FilledButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Plan listo. (No se hicieron cambios en la base de datos)')));
                },
                child: const Text('Aceptar plan'),
              ),
            const SizedBox(height: 14),
          ]),
        ),
      ),
    );
  }

}

/// Poster-style thumb: imagen 120x170 con multiplicador ARRIBA a la izquierda.
/// Si hay donantes, muestra un pequeño badge inferior y al pulsar abre diálogo con detalles.
class _PosterThumb extends StatelessWidget {
  final String? imageCandidate; // ya transformada con thumb120x170 si aplica
  final String cardName;
  final int qty;
  final Map<String,int>? donors; // donorLabel -> qty
  final VoidCallback? onTapDonors;

  const _PosterThumb({
    required this.imageCandidate,
    required this.cardName,
    required this.qty,
    this.donors,
    this.onTapDonors,
  });

  @override
  Widget build(BuildContext context) {
    final cand = imageCandidate;
    final width = 120.0;
    final height = 170.0;

    Widget imageWidget;
    if (cand != null && cand.isNotEmpty) {
      if (cand.startsWith('http://') || cand.startsWith('https://')) {
        imageWidget = Image.network(
          cand,
          width: width,
          height: height,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Container(width: width, height: height, color: Colors.grey.shade800, child: const Icon(Icons.image_not_supported, color: Colors.white70)),
        );
      } else if (cand.startsWith('gs://')) {
        imageWidget = Container(width: width, height: height, color: Colors.grey.shade700, child: const Icon(Icons.cloud, color: Colors.white70));
      } else {
        imageWidget = Container(width: width, height: height, color: Colors.grey.shade700, child: const Icon(Icons.image, color: Colors.white70));
      }
    } else {
      imageWidget = Container(width: width, height: height, color: Colors.grey.shade700, child: const Icon(Icons.image_not_supported, color: Colors.white70));
    }

    // donor badge content
    Widget? donorBadge;
    if (donors != null && donors!.isNotEmpty) {
      if (donors!.length == 1) {
        final key = donors!.keys.first;
        donorBadge = _smallBadge(key);
      } else {
        donorBadge = _smallBadge('+${donors!.length}');
      }
    }

    return GestureDetector(
      onTap: donors != null && donors!.isNotEmpty ? onTapDonors : null,
      child: Stack(
        children: [
          ClipRRect(borderRadius: BorderRadius.circular(6), child: imageWidget),
          // multiplicador arriba-izquierda
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
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
              ),
            ),
          ),
          // donor badge abajo-derecha (si aplica)
          if (donorBadge != null)
            Positioned(
              right: 6,
              bottom: 6,
              child: GestureDetector(
                onTap: () {
                  // también abre el detalle si se pulsa el badge
                  if (onTapDonors != null) onTapDonors!();
                },
                child: donorBadge,
              ),
            ),
        ],
      ),
    );
  }

  Widget _smallBadge(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.black87,
        borderRadius: BorderRadius.circular(10),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.4), blurRadius: 4, offset: const Offset(0,2))],
      ),
      child: Text(text, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
    );
  }
}


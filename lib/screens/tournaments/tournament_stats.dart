// lib/screens/tournaments/tournament_stats.dart
// Utilities para generar y mostrar estadísticas del torneo (con imágenes y porcentajes)

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'models.dart'; // ajusta la ruta si tu archivo models está en otra ubicación
// models.dart debe exportar Player y MatchResult

/// Resultado agregado con los conteos y mapas adicionales necesarios.
class StatsResult {
  final Map<String, int> editionWins;
  final Map<String, int> editionMatches;
  final Map<String, int> cardCounts; // copias totales por cardId (para "más jugadas")
  final Map<String, String> cardNames;
  final Map<String, int> cardCountsInWinningDecks; // copias en mazos ganadores
  final int totalMatches;

  // Nuevos campos:
  final Map<String, int> cardPresenceMatches; // en cuántos MATCHES estuvo presente (1 match contado 1 vez aunque tenga múltiples copias)
  final Map<String, int> cardWinsWhenPresent; // en cuántos MATCHES fue la carta parte del mazo ganador
  final Map<String, Map<String, int>> cardCountsByEdition; // edition -> (cardId -> copies)

  // Por edición detalle (para win-rate por edición)
  final Map<String, Map<String, int>> cardPresenceMatchesByEdition; // edition -> (cardId -> matches)
  final Map<String, Map<String, int>> cardWinsWhenPresentByEdition; // edition -> (cardId -> wins)

  // Desglose por raza dentro de cada edición
  final Map<String, Map<String, int>> editionRaceMatches; // edition -> (race -> matches)
  final Map<String, Map<String, int>> editionRaceWins; // edition -> (race -> wins)

  StatsResult({
    required this.editionWins,
    required this.editionMatches,
    required this.cardCounts,
    required this.cardNames,
    required this.cardCountsInWinningDecks,
    required this.totalMatches,
    required this.cardPresenceMatches,
    required this.cardWinsWhenPresent,
    required this.cardCountsByEdition,
    required this.cardPresenceMatchesByEdition,
    required this.cardWinsWhenPresentByEdition,
    required this.editionRaceMatches,
    required this.editionRaceWins,
  });
}

typedef DeckLoader = Future<Map<String, dynamic>?> Function(Player player);

class TournamentStatsService {
  /// Genera estadísticas del torneo.
  /// - loadDeckDocForPlayer: función que dado un Player devuelve el documento del mazo (Map) o null.
  Future<StatsResult> generateTournamentStats({
    required List<Player> players,
    required List<MatchResult> allMatchResults,
    required DeckLoader loadDeckDocForPlayer,
  }) async {
    // cache por player id
    final Map<String, Map<String, dynamic>?> decksByPlayerId = {};

    // helper safe int
    int safeInt(dynamic v) {
      if (v == null) return 0;
      if (v is int) return v;
      if (v is num) return v.toInt();
      if (v is String) return int.tryParse(v) ?? 0;
      return 0;
    }

    // 1) cargar todos los mazos (paralelo)
    final futures = <Future>[];
    for (final p in players) {
      futures.add(loadDeckDocForPlayer(p).then((doc) {
        decksByPlayerId[p.id] = doc;
      }).catchError((_) {
        decksByPlayerId[p.id] = null;
      }));
    }
    await Future.wait(futures);

    // 2) inicializar contadores
    final Map<String, int> editionWins = {};
    final Map<String, int> editionMatches = {};
    final Map<String, int> cardCounts = {};
    final Map<String, String> cardNames = {};
    final Map<String, int> cardCountsInWinningDecks = {};
    final Map<String, int> cardPresenceMatches = {}; // matches donde estuvo presente (count matches, not copies)
    final Map<String, int> cardWinsWhenPresent = {};
    final Map<String, Map<String, int>> cardCountsByEdition = {}; // edition -> (cardId -> copies)

    // Nuevos mapas por edición / raza
    final Map<String, Map<String, int>> cardPresenceMatchesByEdition = {}; // edition -> (cardId -> matches)
    final Map<String, Map<String, int>> cardWinsWhenPresentByEdition = {}; // edition -> (cardId -> wins)
    final Map<String, Map<String, int>> editionRaceMatches = {}; // edition -> (race -> matches)
    final Map<String, Map<String, int>> editionRaceWins = {}; // edition -> (race -> wins)

    String editionOfPlayer(Player p) {
      final deckDoc = decksByPlayerId[p.id];
      if (deckDoc != null) {
        final ed = (deckDoc['edition'] ?? deckDoc['edicion'] ?? deckDoc['editionKey'])?.toString();
        if (ed != null && ed.isNotEmpty) return ed;
      }
      // fallback: usar race como etiqueta si no hay edición
      return (p.race.isNotEmpty) ? p.race : 'Unknown';
    }

    // 3) contar copias por mazo (cardCounts) y por edición
    for (final p in players) {
      final deckDoc = decksByPlayerId[p.id];
      if (deckDoc == null) continue;
      final cards = (deckDoc['cards'] as List<dynamic>?) ?? [];
      final ed = editionOfPlayer(p);
      cardCountsByEdition.putIfAbsent(ed, () => {});
      for (final c in cards) {
        if (c is Map) {
          final id = (c['cardId'] ?? c['cardID'] ?? c['id'])?.toString();
          if (id == null || id.isEmpty) continue;
          final name = (c['name'] ?? c['nombre'] ?? '')?.toString() ?? id;
          final cnt = safeInt(c['count'] ?? c['cantidad'] ?? c['qty'] ?? c['quantity']);
          cardCounts[id] = (cardCounts[id] ?? 0) + cnt;
          if (name.isNotEmpty) cardNames[id] = name;
          cardCountsByEdition[ed]![id] = (cardCountsByEdition[ed]![id] ?? 0) + cnt;
        }
      }
    }

    // 4) recorrer resultados y calcular presencia/victorias por edición y por carta (por match)
    final totalMatches = allMatchResults.length;

    for (final m in allMatchResults) {
      // edición/participaciones: contamos por jugador dentro del match (player-ocurrences)
      final aEd = editionOfPlayer(m.a);
      editionMatches[aEd] = (editionMatches[aEd] ?? 0) + 1;
      editionRaceMatches.putIfAbsent(aEd, () => {});
      final aRace = (m.a.race.isNotEmpty) ? m.a.race : 'Unknown';
      editionRaceMatches[aEd]![aRace] = (editionRaceMatches[aEd]![aRace] ?? 0) + 1;

      if (m.b != null) {
        final bEd = editionOfPlayer(m.b!);
        editionMatches[bEd] = (editionMatches[bEd] ?? 0) + 1;
        editionRaceMatches.putIfAbsent(bEd, () => {});
        final bRace = (m.b!.race.isNotEmpty) ? m.b!.race : 'Unknown';
        editionRaceMatches[bEd]![bRace] = (editionRaceMatches[bEd]![bRace] ?? 0) + 1;
      }

      // winner
      final winnerId = m.winnerId;
      final winner = players.firstWhere((p) => p.id == winnerId, orElse: () => m.a);
      final wEd = editionOfPlayer(winner);
      editionWins[wEd] = (editionWins[wEd] ?? 0) + 1;
      editionRaceWins.putIfAbsent(wEd, () => {});
      final wRace = (winner.race.isNotEmpty) ? winner.race : 'Unknown';
      editionRaceWins[wEd]![wRace] = (editionRaceWins[wEd]![wRace] ?? 0) + 1;

      // obtener sets de cardIds por edición que aparecen en este match (para contar presencia por edición una vez por match)
      final Map<String, Set<String>> presentByEdition = {}; // edition -> set(cardIds)
      // también un set global para presencia en el match
      final Set<String> presentInMatch = {};
      // helper sync (no await necesario porque decksByPlayerId ya está cargado)
      void collectFromPlayer(Player p) {
        final deckDoc = decksByPlayerId[p.id];
        if (deckDoc == null) return;
        final cards = (deckDoc['cards'] as List<dynamic>?) ?? [];
        final ed = editionOfPlayer(p);
        presentByEdition.putIfAbsent(ed, () => <String>{});
        for (final c in cards) {
          if (c is Map) {
            final id = (c['cardId'] ?? c['cardID'] ?? c['id'])?.toString();
            if (id == null || id.isEmpty) continue;
            final cnt = safeInt(c['count'] ?? c['cantidad'] ?? c['qty'] ?? c['quantity']);
            if (cnt > 0) {
              presentInMatch.add(id);
              presentByEdition[ed]!.add(id);
            }
            // ensure name known
            final name = (c['name'] ?? c['nombre'] ?? '')?.toString() ?? id;
            if (name.isNotEmpty) cardNames[id] = name;
          }
        }
      }

      collectFromPlayer(m.a);
      if (m.b != null) collectFromPlayer(m.b!);

      // actualizar presencia global por carta (conteo de matches)
      for (final id in presentInMatch) {
        cardPresenceMatches[id] = (cardPresenceMatches[id] ?? 0) + 1;
      }

      // actualizar presencia por edición
      for (final ed in presentByEdition.keys) {
        cardPresenceMatchesByEdition.putIfAbsent(ed, () => {});
        for (final id in presentByEdition[ed]!) {
          cardPresenceMatchesByEdition[ed]![id] = (cardPresenceMatchesByEdition[ed]![id] ?? 0) + 1;
        }
      }

      // actualizar winsWhenPresent global y por edición (por la edición del ganador)
      final winnerDeckDoc = decksByPlayerId[winner.id];
      if (winnerDeckDoc != null) {
        final winnerCards = (winnerDeckDoc['cards'] as List<dynamic>?) ?? [];
        final Set<String> winnerIds = {};
        for (final c in winnerCards) {
          if (c is Map) {
            final id = (c['cardId'] ?? c['cardID'] ?? c['id'])?.toString();
            if (id == null || id.isEmpty) continue;
            final cnt = safeInt(c['count'] ?? c['cantidad'] ?? c['qty'] ?? c['quantity']);
            if (cnt > 0) winnerIds.add(id);
            // ensure name known
            final name = (c['name'] ?? c['nombre'] ?? '')?.toString() ?? id;
            if (name.isNotEmpty) cardNames[id] = name;
          }
        }

        for (final id in winnerIds) {
          cardWinsWhenPresent[id] = (cardWinsWhenPresent[id] ?? 0) + 1;
          cardWinsWhenPresentByEdition.putIfAbsent(wEd, () => {});
          cardWinsWhenPresentByEdition[wEd]![id] = (cardWinsWhenPresentByEdition[wEd]![id] ?? 0) + 1;
        }

        // además, acumular copias del mazo ganador (global)
        for (final c in winnerCards) {
          if (c is Map) {
            final id = (c['cardId'] ?? c['cardID'] ?? c['id'])?.toString();
            if (id == null || id.isEmpty) continue;
            final cnt = safeInt(c['count'] ?? c['cantidad'] ?? c['qty'] ?? c['quantity']);
            cardCountsInWinningDecks[id] = (cardCountsInWinningDecks[id] ?? 0) + cnt;
            final name = (c['name'] ?? c['nombre'] ?? '')?.toString() ?? id;
            if (name.isNotEmpty) cardNames[id] = name;
          }
        }
      }
    } // end for matches

    // asegurarse de tener mapas inicializados (evita null later)
    // (ya inicializamos con putIfAbsent en puntos clave)

    return StatsResult(
      editionWins: editionWins,
      editionMatches: editionMatches,
      cardCounts: cardCounts,
      cardNames: cardNames,
      cardCountsInWinningDecks: cardCountsInWinningDecks,
      totalMatches: totalMatches,
      cardPresenceMatches: cardPresenceMatches,
      cardWinsWhenPresent: cardWinsWhenPresent,
      cardCountsByEdition: cardCountsByEdition,
      cardPresenceMatchesByEdition: cardPresenceMatchesByEdition,
      cardWinsWhenPresentByEdition: cardWinsWhenPresentByEdition,
      editionRaceMatches: editionRaceMatches,
      editionRaceWins: editionRaceWins,
    );
  }
}

// -----------------------------------------------------------------------------
// Diálogo que muestra mosaicos con imágenes + porcentajes y subtítulos explicando
// -----------------------------------------------------------------------------

/// Tile que muestra la imagen de la carta y un badge con número + porcentaje
class _CardImageTile extends StatelessWidget {
  final String? imageUrl;
  final String title;
  final String mainLabel;
  final String? subtitlePercent;

  const _CardImageTile({
    required this.imageUrl,
    required this.title,
    required this.mainLabel,
    required this.subtitlePercent,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 110,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (imageUrl != null && imageUrl!.isNotEmpty)
            SizedBox(height: 70, child: Image.network(imageUrl!, fit: BoxFit.contain)),
          const SizedBox(height: 6),
          Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center),
          const SizedBox(height: 4),
          Text(mainLabel, style: const TextStyle(fontWeight: FontWeight.bold)),
          if (subtitlePercent != null && subtitlePercent!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4.0),
              child: Text(subtitlePercent!, style: const TextStyle(fontSize: 12, color: Colors.grey)),
            ),
        ],
      ),
    );
  }
}

/// Carga (desde Firestore) las URLs de imagen para un conjunto de cardIds.
Future<Map<String, String?>> _loadCardImagesFromFirestore(List<String> cardIds) async {
  final db = FirebaseFirestore.instance;
  final Map<String, String?> out = {};
  if (cardIds.isEmpty) return out;

  for (var i = 0; i < cardIds.length; i += 10) {
    final sub = cardIds.sublist(i, (i + 10 > cardIds.length) ? cardIds.length : i + 10);
    final qs = await db.collection('cards').where(FieldPath.documentId, whereIn: sub).get();
    for (final doc in qs.docs) {
      final data = doc.data();
      final id = doc.id;
      String? maybe = (data['officialImageUrl'] as String?)?.trim();
      maybe ??= (data['imageFrontUrl'] as String?)?.trim();
      maybe ??= (data['image'] as String?)?.trim();
      if (maybe != null && maybe.isNotEmpty) {
        out[id] = maybe;
        continue;
      }
      try {
        final variantsQ = await doc.reference.collection('variants').where('official', isEqualTo: true).limit(1).get();
        if (variantsQ.docs.isNotEmpty) {
          final v = variantsQ.docs.first.data();
          final url = (v['imageFrontUrl'] ?? v['image'] ?? v['imageUrl'])?.toString();
          if (url != null && url.isNotEmpty) {
            out[id] = url;
            continue;
          }
        }
        final anyVar = await doc.reference.collection('variants').limit(1).get();
        if (anyVar.docs.isNotEmpty) {
          final v = anyVar.docs.first.data();
          final url = (v['imageFrontUrl'] ?? v['image'] ?? v['imageUrl'])?.toString();
          if (url != null && url.isNotEmpty) {
            out[id] = url;
            continue;
          }
        }
      } catch (_) {
        // ignore
      }
      out[id] = null;
    }
    for (final id in sub) out.putIfAbsent(id, () => null);
  }
  return out;
}

/// Muestra diálogo con mosaicos e información con porcentajes y subtítulos que
/// explican cómo se calculó cada métrica.
Future<void> showTournamentStatsDialog(BuildContext context, StatsResult stats) async {
  // Build lists and derived values
  final totalMatches = stats.totalMatches;
  stats.cardCounts.values.fold<int>(0, (s, v) => s + v);

  // orden globales
  final mostPlayed = stats.cardCounts.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
  final leastPlayed = stats.cardCounts.entries.toList()..sort((a, b) => a.value.compareTo(b.value));
  final mostInWinners = stats.cardCountsInWinningDecks.entries.toList()..sort((a, b) => b.value.compareTo(a.value));

  // card win-rate list (win matches / matches present) GLOBAL
  final List<Map<String, dynamic>> cardWinRateList = [];
  for (final id in stats.cardPresenceMatches.keys) {
    final pres = stats.cardPresenceMatches[id] ?? 0;
    if (pres <= 0) continue;
    final wins = stats.cardWinsWhenPresent[id] ?? 0;
    final wr = pres > 0 ? wins / pres : 0.0;
    cardWinRateList.add({'id': id, 'present': pres, 'wins': wins, 'winRate': wr});
  }
  cardWinRateList.sort((a, b) => (b['winRate'] as double).compareTo(a['winRate'] as double));

  // top lists por edición (por copias) — precompute sorted maps
  final Map<String, List<MapEntry<String,int>>> mostByEdition = {};
  final Map<String, List<MapEntry<String,int>>> leastByEdition = {};
  for (final ed in stats.cardCountsByEdition.keys) {
    final entries = stats.cardCountsByEdition[ed]!.entries.toList()..sort((a,b) => b.value.compareTo(a.value));
    mostByEdition[ed] = entries;
    final bottom = stats.cardCountsByEdition[ed]!.entries.toList()..sort((a,b) => a.value.compareTo(b.value));
    leastByEdition[ed] = bottom;
  }

  // Collect cardIds to prefetch images (union)
  final idsSet = <String>{};
  idsSet.addAll(mostPlayed.take(10).map((e) => e.key));
  idsSet.addAll(leastPlayed.where((e) => e.value > 0).take(10).map((e) => e.key));
  idsSet.addAll(mostInWinners.take(10).map((e) => e.key));
  idsSet.addAll(cardWinRateList.take(10).map((m) => m['id'] as String));
  // add per-edition top8/bottom8 and top5 winrate ids
  for (final ed in stats.cardCountsByEdition.keys) {
    idsSet.addAll(mostByEdition[ed]!.take(8).map((e) => e.key));
    idsSet.addAll(leastByEdition[ed]!.where((e)=>e.value>0).take(8).map((e) => e.key));
    final presMap = stats.cardPresenceMatchesByEdition[ed] ?? {};
    final winsMap = stats.cardWinsWhenPresentByEdition[ed] ?? {};
    final localList = <Map<String,dynamic>>[];
    for (final id in presMap.keys) {
      final p = presMap[id] ?? 0;
      if (p <= 0) continue;
      final w = winsMap[id] ?? 0;
      final wr = p > 0 ? w / p : 0.0;
      localList.add({'id': id, 'present': p, 'wins': w, 'winRate': wr});
    }
    localList.sort((a,b) => (b['winRate'] as double).compareTo(a['winRate'] as double));
    idsSet.addAll(localList.take(5).map((m)=> m['id'] as String));
  }

  final allIds = idsSet.toList();
  final imagesFuture = _loadCardImagesFromFirestore(allIds);

  if (!context.mounted) return;
  await showDialog(
    context: context,
    builder: (ctx) {
      return Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: FutureBuilder<Map<String, String?>>(
            future: imagesFuture,
            builder: (c, snap) {
              final imageMap = snap.data ?? {};
              String nameOf(String id) => stats.cardNames[id] ?? id;

              Widget buildTileGridFromEntries(
                List<MapEntry<String,int>> entries, {
                required int absoluteBaseForPercent,
                bool showPercent = true, // controla si mostramos % o no
              }) {


                // helper local (definido antes de usarlo)
                String _makePercentLabel(double percent) {
                  return '${(percent * 100).toStringAsFixed(1)}%';
                }

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 12,
                      children: entries.map((e) {
                        final id = e.key;
                        final cnt = e.value;
                        final img = imageMap[id];
                        double percent = 0.0;
                        if (absoluteBaseForPercent > 0) percent = cnt / absoluteBaseForPercent;
                        final mainLabel = 'x$cnt';
                        final subtitlePercent = (showPercent && absoluteBaseForPercent > 0)
                            ? _makePercentLabel(percent)
                            : null; // null = no mostrar

                        return _CardImageTile(
                          imageUrl: img,
                          title: nameOf(id),
                          mainLabel: mainLabel,
                          subtitlePercent: subtitlePercent,
                        );
                      }).toList(),
                    ),
                  ],
                );
              }

              final children = <Widget>[];
              children.add(const Text('Estadísticas del torneo', style: TextStyle(fontWeight: FontWeight.bold)));
              children.add(const SizedBox(height: 8));
              children.add(Text('Partidas totales: $totalMatches'));
              children.add(const SizedBox(height: 12));

              // EDICIONES ordenadas por win rate (explicación) + desglose por RAZA
              final editionKeys = {...stats.editionMatches.keys, ...stats.editionWins.keys}.toList();
              final editionList = editionKeys.map((ed) {
                final played = stats.editionMatches[ed] ?? 0;
                final wins = stats.editionWins[ed] ?? 0;
                final wr = (played > 0) ? (wins / played) : 0.0;
                return {'edition': ed, 'played': played, 'wins': wins, 'winRate': wr};
              }).toList();
              editionList.sort((a, b) => (b['winRate'] as double).compareTo(a['winRate'] as double));

              children.add(const Text('Ediciones (ordenadas por Win Rate)', style: TextStyle(fontWeight: FontWeight.bold)));
              children.add(const SizedBox(height: 6));
              children.add(const Text('Win Rate = victorias de la edición / partidas jugadas por la edición. Se muestra además desglose por raza dentro de la edición.'));
              children.add(const SizedBox(height: 6));
              if (editionList.isEmpty) {
                children.add(const Text('- (sin datos)'));
              } else {
                for (final e in editionList) {
                  final ed = e['edition'] as String;
                  final played = e['played'] as int;
                  final wins = e['wins'] as int;
                  final wr = (e['winRate'] as double) * 100;
                  children.add(Text('- $ed: $played jugadas / $wins victorias • Win rate: ${wr.toStringAsFixed(1)}%'));
                  // desglose por raza para esta edición
                  final raceMatches = stats.editionRaceMatches[ed] ?? {};
                  final raceWins = stats.editionRaceWins[ed] ?? {};
                  if (raceMatches.isNotEmpty) {
                    final races = raceMatches.keys.toList()..sort();
                    final raceWidgets = races.map((r) {
                      final rm = raceMatches[r] ?? 0;
                      final rw = raceWins[r] ?? 0;
                      final rwr = rm > 0 ? (rw / rm * 100.0) : 0.0;
                      return Text('    • $r: $rm jugadas / $rw victorias (${rwr.toStringAsFixed(1)}%)', style: const TextStyle(fontSize: 12, color: Colors.black87));
                    }).toList();
                    children.addAll(raceWidgets);
                  } else {
                    children.add(const Text('    • (sin desglose por raza)', style: TextStyle(fontSize: 12, color: Colors.grey)));
                  }
                }
              }

              children.add(const SizedBox(height: 12));
              children.add(const Divider());
              children.add(const SizedBox(height: 8));

              // --- por edicion: Top8 most played & Bottom8 least played ---
              if (mostByEdition.isNotEmpty) {
                children.add(const Text('Top/Bottom por Edición (Top8 / Bottom8 por COPIAS)', style: TextStyle(fontWeight: FontWeight.bold)));
                children.add(const SizedBox(height: 8));
                final sortedEditionKeys = mostByEdition.keys.toList()..sort();
                for (final ed in sortedEditionKeys) {
                  final mostList = mostByEdition[ed] ?? [];
                  final leastList = leastByEdition[ed] ?? [];
                  final totalCopiesEd = stats.cardCountsByEdition[ed]!.values.fold<int>(0, (s, v) => s + v);

                  children.add(Text('- $ed', style: const TextStyle(fontWeight: FontWeight.w600)));
                  children.add(const SizedBox(height: 6));
                  // Top8
                  children.add(Text('Más jugadas'));
                  children.add(const SizedBox(height: 6));
                  children.add(
                    buildTileGridFromEntries(
                      mostList.take(8).toList(),
                      absoluteBaseForPercent: totalCopiesEd > 0 ? totalCopiesEd : 1,
                    ),
                  );
                  children.add(const SizedBox(height: 8));
                  // Bottom8 (>=1)
                  final bottomFiltered = leastList.where((x) => x.value > 0).toList();
                  children.add(Text('Menos jugadas'));
                  children.add(const SizedBox(height: 6));
                  children.add(
                    buildTileGridFromEntries(
                      bottomFiltered.take(8).toList(),
                      absoluteBaseForPercent: totalCopiesEd > 0 ? totalCopiesEd : 1,
                    ),
                  );
                  children.add(const SizedBox(height: 12));
                }
              }


              // CARTAS CON MAYOR WIN RATE POR EDICIÓN (Top5 por edición)
              children.add(const Divider());
              children.add(const SizedBox(height: 8));
              children.add(const Text('Cartas con mayor Win Rate por edición', style: TextStyle(fontWeight: FontWeight.bold)));
              children.add(const SizedBox(height: 6));
              children.add(const SizedBox(height: 6));

              final editionKeysForWinRate = stats.cardCountsByEdition.keys.toList()..sort();
              for (final ed in editionKeysForWinRate) {
                children.add(Text('- $ed', style: const TextStyle(fontWeight: FontWeight.w600)));
                final presMap = stats.cardPresenceMatchesByEdition[ed] ?? {};
                final winsMap = stats.cardWinsWhenPresentByEdition[ed] ?? {};
                final localList = <Map<String, dynamic>>[];
                for (final id in presMap.keys) {
                  final p = presMap[id] ?? 0;
                  if (p <= 0) continue;
                  final w = winsMap[id] ?? 0;
                  final wr = p > 0 ? w / p : 0.0;
                  localList.add({'id': id, 'present': p, 'wins': w, 'winRate': wr});
                }
                localList.sort((a,b) => (b['winRate'] as double).compareTo(a['winRate'] as double));
                final top5 = localList.take(5).toList();
                if (top5.isEmpty) {
                  children.add(const Text('  - (sin datos)'));
                } else {
                  children.add(const SizedBox(height: 6));
                  children.add(Wrap(
                    spacing: 8,
                    runSpacing: 12,
                    children: top5.map((m) {
                      final id = m['id'] as String;
                      final pres = m['present'] as int;
                      final wins = m['wins'] as int;
                      final img = imageMap[id];
                      final pctStr = pres > 0 ? '${(wins / pres * 100).toStringAsFixed(1)}%' : '-';
                      final mainLabel = '$wins / $pres';
                      final subtitle = 'WinRate: $pctStr';
                      return _CardImageTile(imageUrl: img, title: stats.cardNames[id] ?? id, mainLabel: mainLabel, subtitlePercent: subtitle);
                    }).toList(),
                  ));
                  children.add(const SizedBox(height: 8));
                }
              }

              // NOTA: se removió el bloque final antiguo "Top5 Cartas por Edición (Top5 por copias)" según pedido.

              // return scrollable dialog content
              return SizedBox(
                width: MediaQuery.of(ctx).size.width * 0.92,
                height: MediaQuery.of(ctx).size.height * 0.82,
                child: SingleChildScrollView(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
                ),
              );
            },
          ),
        ),
      );
    },
  );
}

// lib/screens/tournaments/widgets.dart
// Widgets y utilidades para torneos: MatchCard, BracketView, Standings sheet, Race stats dialog.

import 'dart:math';
import 'package:flutter/material.dart';
import './models.dart';

///////////////////////////////////////////////////////////////////////////////
/// MatchCard
///////////////////////////////////////////////////////////////////////////////

/// Tarjeta que muestra un duelo (jugador A vs B), con scores opcionales.
class MatchCard extends StatelessWidget {
  final Player a;
  final Player? b;
  final int? scoreA;
  final int? scoreB;

  const MatchCard({
    super.key,
    required this.a,
    this.b,
    this.scoreA,
    this.scoreB,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(10.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Fila principal: A vs B (o bye)
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(a.displayName, style: const TextStyle(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 4),
                      Text(a.race, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                    ],
                  ),
                ),
                if (scoreA != null || scoreB != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Text('${scoreA ?? '-'} · ${scoreB ?? '-'}', style: const TextStyle(fontWeight: FontWeight.w800)),
                  )
                else
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8),
                    child: Text('vs', style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(b?.displayName ?? '—', style: const TextStyle(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 4),
                      Text(b?.race ?? '-', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                    ],
                  ),
                ),
              ],
            ),

            // Nota para bye
            if (b == null)
              Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: Text('Bye — avanza automáticamente', style: TextStyle(fontSize: 12, color: Colors.orange.shade800)),
              ),
          ],
        ),
      ),
    );
  }
}

///////////////////////////////////////////////////////////////////////////////
/// BracketView (+ painter)
///////////////////////////////////////////////////////////////////////////////

/// Vista del bracket/eliminación que dibuja tarjetas y líneas conectores.
/// - rounds: lista de rondas; cada ronda es lista de Pair.
/// - results: mapa 'r{round}_m{index}' -> MatchResult (opcional)
class BracketView extends StatelessWidget {
  final List<List<Pair>> rounds;
  final Map<String, MatchResult> results;

  const BracketView({super.key, required this.rounds, required this.results});

  @override
  Widget build(BuildContext context) {
    if (rounds.isEmpty) return const Center(child: Text('No hay fases de eliminación aún.'));

    // parámetros visuales
    const double cardWidth = 220.0;
    const double cardHeight = 88.0;
    const double columnWidth = 260.0;
    const double columnSpacing = 20.0;
    const double baseVerticalSpacing = 12.0;

    final roundsCount = rounds.length;

    // Espaciado vertical que crece por ronda (forma "llave")
    final spacingByRound = List<double>.generate(
      roundsCount,
      (i) => baseVerticalSpacing * pow(2, i).toDouble(),
    );

    // referencia de altura usando la primera ronda
    final firstRoundMatches = rounds[0].length;
    final totalHeightReference = firstRoundMatches * cardHeight + (firstRoundMatches - 1) * spacingByRound[0];

    final totalWidth = roundsCount * columnWidth + (roundsCount - 1) * columnSpacing;

    // calcula posiciones (offset top-left) por ronda/partido
    final positions = <int, List<Offset>>{};
    for (int roundIdx = 0; roundIdx < roundsCount; roundIdx++) {
      final matches = rounds[roundIdx];
      final m = matches.length;
      final spacing = spacingByRound[roundIdx];
      final columnContentHeight = m * cardHeight + (m - 1) * spacing;
      final topPadding = max(0.0, (totalHeightReference - columnContentHeight) / 2.0);
      final x = roundIdx * (columnWidth + columnSpacing) + 8.0;
      positions[roundIdx] = List.generate(m, (matchIdx) {
        final y = topPadding + matchIdx * (cardHeight + spacing);
        return Offset(x, y);
      });
    }

    // crea conectores (from -> to)
    final connectors = <_Conn>[];
    for (int roundIdx = 0; roundIdx < roundsCount - 1; roundIdx++) {
      final mCount = rounds[roundIdx].length;
      for (int matchIdx = 0; matchIdx < mCount; matchIdx++) {
        final fromPos = positions[roundIdx]![matchIdx];
        final toMatchIdx = (matchIdx / 2).floor();
        final toPos = positions[roundIdx + 1]![toMatchIdx];
        final p1 = Offset(fromPos.dx + cardWidth, fromPos.dy + cardHeight / 2);
        final p2 = Offset(toPos.dx, toPos.dy + cardHeight / 2);
        connectors.add(_Conn(p1, p2));
      }
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        child: SizedBox(
          width: totalWidth + 40,
          height: max(totalHeightReference, 320.0),
          child: Stack(
            children: [
              // líneas (debajo)
              Positioned.fill(child: CustomPaint(painter: _BracketLinesPainter(connectors: connectors))),
              // tarjetas en posiciones exactas
              for (int roundIdx = 0; roundIdx < roundsCount; roundIdx++) ...[
                for (int matchIdx = 0; matchIdx < rounds[roundIdx].length; matchIdx++) ...[
                  Positioned(
                    left: positions[roundIdx]![matchIdx].dx,
                    top: positions[roundIdx]![matchIdx].dy,
                    child: SizedBox(
                      width: cardWidth,
                      height: cardHeight,
                      child: MatchCard(
                        a: rounds[roundIdx][matchIdx].a,
                        b: rounds[roundIdx][matchIdx].b,
                        scoreA: results['r${roundIdx + 1}_m$matchIdx']?.scoreA,
                        scoreB: results['r${roundIdx + 1}_m$matchIdx']?.scoreB,
                      ),
                    ),
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Conn {
  final Offset a;
  final Offset b;
  _Conn(this.a, this.b);
}

class _BracketLinesPainter extends CustomPainter {
  final List<_Conn> connectors;
  _BracketLinesPainter({required this.connectors});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black87
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round;

    final smallPaint = Paint()..color = Colors.black87..style = PaintingStyle.fill;

    for (final c in connectors) {
      final a = c.a;
      final b = c.b;
      final hGap = ((b.dx - a.dx) / 2).clamp(12.0, 60.0);
      final p1 = a;
      final p2 = Offset(a.dx + hGap, a.dy);
      final p3 = Offset(a.dx + hGap, b.dy);
      final p4 = b;

      final path = Path()
        ..moveTo(p1.dx, p1.dy)
        ..lineTo(p2.dx, p2.dy)
        ..lineTo(p3.dx, p3.dy)
        ..lineTo(p4.dx, p4.dy);

      canvas.drawPath(path, paint);
      canvas.drawCircle(p2, 3.0, smallPaint);
      canvas.drawCircle(p3, 3.0, smallPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _BracketLinesPainter oldDelegate) => oldDelegate.connectors != connectors;
}

///////////////////////////////////////////////////////////////////////////////
/// Dialogs: Standings sheet & Race stats dialog
///////////////////////////////////////////////////////////////////////////////

String _displayDeckName(String deckName) {
  final idx = deckName.indexOf('(');
  if (idx >= 0) return deckName.substring(0, idx).trim();
  return deckName;
}

/// Muestra el modal con la tabla de posiciones y desglose por ronda.
///
/// - players: lista de Player actuales
/// - swissResultsByRound: Map<roundIndex, List<MatchResult>>
/// - stats: Map<playerId, PlayerStats>
/// - elimRounds: (opcional) listas de pares para cada ronda de eliminación
/// - elimResults: (opcional) mapa 'r{round}_m{index}' -> MatchResult
Future<void> showStandingsSheet(
  BuildContext context, {
  required List<Player> players,
  required Map<int, List<MatchResult>> swissResultsByRound,
  required Map<String, PlayerStats> stats,
  List<List<Pair>>? elimRounds,
  Map<String, MatchResult>? elimResults,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).scaffoldBackgroundColor,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(12))),
    builder: (ctx) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: FractionallySizedBox(
            heightFactor: 0.85,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Expanded(child: Text('Tabla de posiciones', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
                    IconButton(onPressed: () => Navigator.of(ctx).pop(), icon: const Icon(Icons.close)),
                  ],
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: SingleChildScrollView(
                    child: _StandingsContent(
                      players: players,
                      swissResultsByRound: swissResultsByRound,
                      stats: stats,
                      elimRounds: elimRounds ?? const [],
                      elimResults: elimResults ?? const {},
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

class _StandingsContent extends StatelessWidget {
  final List<Player> players;
  final Map<int, List<MatchResult>> swissResultsByRound;
  final Map<String, PlayerStats> stats;
  final List<List<Pair>> elimRounds;
  final Map<String, MatchResult> elimResults;

  const _StandingsContent({
    required this.players,
    required this.swissResultsByRound,
    required this.stats,
    required this.elimRounds,
    required this.elimResults,
  });

  static const int pointsPerWin = 3; // ← cambia si tu sistema usa otro valor

  int _toIntSafe(dynamic v) {
    if (v == null) return 0;
    if (v is int) return v;
    if (v is double) return v.toInt();
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v) ?? 0;
    return 0;
  }

  // Recolecta solo los matches Swiss (ordenados por ronda). NO incluye eliminaciones.

  /// Calcula mapas: duelsPlayed/duelsWon/gamesWon/gamesLost/points por playerId
  /// Solo considera las rondas Swiss y asegura a lo sumo 1 duelo por ronda por jugador.
  Map<String, Map<String,int>> _computeFromSwissMatches() {
    final duelsPlayed = <String,int>{};
    final duelsWon = <String,int>{};
    final gamesWon = <String,int>{};
    final gamesLost = <String,int>{};
    final points = <String,int>{};

    final swissRounds = swissResultsByRound.keys.toList()..sort();
    final maxRounds = swissRounds.length;

    for (final r in swissRounds) {
      final matches = swissResultsByRound[r] ?? [];
      final seenThisRound = <String>{};

      for (final m in matches) {
        if (m.b == null) continue;

        final aId = m.a.id;
        final bId = m.b!.id;

        if (seenThisRound.add(aId)) {
          duelsPlayed[aId] = (duelsPlayed[aId] ?? 0) + 1;
        }
        if (seenThisRound.add(bId)) {
          duelsPlayed[bId] = (duelsPlayed[bId] ?? 0) + 1;
        }

        // ganador de duelo: preferir winnerId, fallback por scores
        final winnerId = m.winnerId;
        if ((winnerId == aId || winnerId == bId)) {
          duelsWon[winnerId] = (duelsWon[winnerId] ?? 0) + 1;
        } else {
          final sA = _toIntSafe(m.scoreA);
          final sB = _toIntSafe(m.scoreB);
          if (sA != sB) {
            final w = sA > sB ? aId : bId;
            duelsWon[w] = (duelsWon[w] ?? 0) + 1;
          }
        }

        // games: acumulamos scores (solo Swiss)
        final gA = _toIntSafe(m.scoreA);
        final gB = _toIntSafe(m.scoreB);
        if (gA > 0 || gB > 0) {
          gamesWon[aId] = (gamesWon[aId] ?? 0) + gA;
          gamesLost[aId] = (gamesLost[aId] ?? 0) + gB;
          gamesWon[bId] = (gamesWon[bId] ?? 0) + gB;
          gamesLost[bId] = (gamesLost[bId] ?? 0) + gA;
        }
      }
    }

    // garantía: no contar más duelos de los que hubo rondas Swiss
    if (maxRounds > 0) {
      for (final id in duelsPlayed.keys.toList()) {
        if ((duelsPlayed[id] ?? 0) > maxRounds) duelsPlayed[id] = maxRounds;
      }
    }

    // calcular puntos SÓLO en base a duelsWon de Swiss (nada de eliminatoria)
    for (final id in duelsWon.keys) {
      points[id] = (duelsWon[id] ?? 0) * pointsPerWin;
    }
    // asegurar que también existan entradas 0 para jugadores sin wins
    for (final p in players) {
      duelsPlayed.putIfAbsent(p.id, () => 0);
      duelsWon.putIfAbsent(p.id, () => 0);
      gamesWon.putIfAbsent(p.id, () => 0);
      gamesLost.putIfAbsent(p.id, () => 0);
      points.putIfAbsent(p.id, () => 0);
    }

    return {
      'duelsPlayed': duelsPlayed,
      'duelsWon': duelsWon,
      'gamesWon': gamesWon,
      'gamesLost': gamesLost,
      'points': points,
    };
  }

  // Ordenamiento: usa métricas computadas desde Swiss para duelos/porcentajes/puntos.
  List<Player> _sortedStandingsWithComputed(Map<String, Map<String,int>> computed) {
  final compDuelsWon = computed['duelsWon'] ?? {};
  final compDuelsPlayed = computed['duelsPlayed'] ?? {};
  final compGamesWon = computed['gamesWon'] ?? {};
  final compGamesLost = computed['gamesLost'] ?? {};
  final list = List<Player>.from(players);

  double _duelPct(String id) {
    final played = compDuelsPlayed[id] ?? 0;
    final won = compDuelsWon[id] ?? 0;
    return played > 0 ? (won / played) : 0.0;
  }

  double _gameWinPct(String id) {
    final gw = compGamesWon[id] ?? 0;
    final gl = compGamesLost[id] ?? 0;
    final total = gw + gl;
    return total > 0 ? (gw / total) : 0.0;
  }

  list.sort((a, b) {
    // 1) duels won
    final aDuelsWon = compDuelsWon[a.id] ?? 0;
    final bDuelsWon = compDuelsWon[b.id] ?? 0;
    if (aDuelsWon != bDuelsWon) return bDuelsWon.compareTo(aDuelsWon);

    // 2) duel % (wins / played)
    final aDuelPct = _duelPct(a.id);
    final bDuelPct = _duelPct(b.id);
    if (aDuelPct != bDuelPct) return bDuelPct.compareTo(aDuelPct);

    // 3) GAME WIN % (games won / games played) -> this is the key one you requested
    final aGamePct = _gameWinPct(a.id);
    final bGamePct = _gameWinPct(b.id);
    if (aGamePct != bGamePct) return bGamePct.compareTo(aGamePct);

    // 4) fallback deterministic order (displayName)
    return a.displayName.compareTo(b.displayName);
  });

  return list;
}


  @override
  Widget build(BuildContext context) {
    final computed = _computeFromSwissMatches();
    final standings = _sortedStandingsWithComputed(computed);
    final swissRoundsSorted = swissResultsByRound.keys.toList()..sort();

    // Lectura SÓLO desde computed (no usamos stats para duelos/partidas/puntos)
    int readDuelsWon(String playerId) => computed['duelsWon']?[playerId] ?? 0;
    int readDuelsPlayed(String playerId) => computed['duelsPlayed']?[playerId] ?? 0;
    int readGamesWon(String playerId) => computed['gamesWon']?[playerId] ?? 0;
    int readGamesLost(String playerId) => computed['gamesLost']?[playerId] ?? 0;
    int readPoints(String playerId) => computed['points']?[playerId] ?? 0;

    return LayoutBuilder(builder: (context, constraints) {
      // vista móvil
      if (constraints.maxWidth < 700) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ...List.generate(standings.length, (i) {
              final p = standings[i];
              final duelsW = readDuelsWon(p.id);
              final duelsP = readDuelsPlayed(p.id);
              final duelsL = (duelsP - duelsW).clamp(0, duelsP);
              final gamesW = readGamesWon(p.id);
              final gamesL = readGamesLost(p.id);
              final points = readPoints(p.id);
              final duelPct = duelsP > 0 ? (duelsW / duelsP * 100.0) : 0.0;
              final gamePct = (gamesW + gamesL) > 0 ? (gamesW / (gamesW + gamesL) * 100.0) : 0.0;

              return Card(
                margin: const EdgeInsets.symmetric(vertical: 6),
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Row(
                    children: [
                      CircleAvatar(child: Text('${i + 1}'), radius: 18),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(p.displayName, style: const TextStyle(fontWeight: FontWeight.w700)),
                            const SizedBox(height: 4),
                            Text(_displayDeckName(p.deckName), style: const TextStyle(fontSize: 12, color: Colors.grey)),
                            const SizedBox(height: 6),
                            Text('Pts: $points', style: const TextStyle(fontSize: 12, color: Colors.black54)),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text('D: $duelsW / $duelsL', style: const TextStyle(fontWeight: FontWeight.bold)),
                          Text('${duelPct.toStringAsFixed(1)}%', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                        ],
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text('G: $gamesW / $gamesL', style: const TextStyle(fontWeight: FontWeight.bold)),
                          Text('${gamePct.toStringAsFixed(1)}%', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                        ],
                      ),
                      const SizedBox(width: 8),
                      IconButton(icon: const Icon(Icons.info_outline), onPressed: () {}),
                    ],
                  ),
                ),
              );
            }),
            const SizedBox(height: 12),
            const Text('Resultados por ronda (desglose):', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            if (swissResultsByRound.isEmpty)
              const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Text('Aún no hay resultados de rondas.'))
            else
              ...swissRoundsSorted.map((round) {
                final list = swissResultsByRound[round]!;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Ronda $round', style: const TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    ...list.map((m) {
                      final aName = m.a.displayName;
                      final bName = m.b != null ? m.b!.displayName : 'bye';
                      final score = m.b == null ? '(bye)' : '${m.scoreA}-${m.scoreB}';
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Text('• $aName vs $bName → $score'),
                      );
                    }).toList(),
                    const SizedBox(height: 8),
                  ],
                );
              }).toList(),
          ],
        );
      }

      // vista ancha: tabla
      final minTableWidth = max(constraints.maxWidth, 980.0);

      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: ConstrainedBox(
              constraints: BoxConstraints(minWidth: minTableWidth),
              child: DataTable(
                columnSpacing: 18,
                dataRowHeight: 56,
                headingRowHeight: 56,
                columns: const [
                  DataColumn(label: Text('#', style: TextStyle(fontWeight: FontWeight.bold))),
                  DataColumn(label: Text('Jugador', style: TextStyle(fontWeight: FontWeight.bold))),
                  DataColumn(label: Text('Mazo', style: TextStyle(fontWeight: FontWeight.bold))),
                  DataColumn(label: Text('Puntos', style: TextStyle(fontWeight: FontWeight.bold))),
                  DataColumn(label: Text('Duelos W', style: TextStyle(fontWeight: FontWeight.bold))),
                  DataColumn(label: Text('Duelos L', style: TextStyle(fontWeight: FontWeight.bold))),
                  DataColumn(label: Text('Partidas W', style: TextStyle(fontWeight: FontWeight.bold))),
                  DataColumn(label: Text('Partidas L', style: TextStyle(fontWeight: FontWeight.bold))),
                  DataColumn(label: Text('%Duel', style: TextStyle(fontWeight: FontWeight.bold))),
                  DataColumn(label: Text('%Game', style: TextStyle(fontWeight: FontWeight.bold))),
                ],
                rows: List.generate(standings.length, (i) {
                  final p = standings[i];
                  final duelsW = readDuelsWon(p.id);
                  final duelsP = readDuelsPlayed(p.id);
                  final duelsL = (duelsP - duelsW).clamp(0, duelsP);
                  final gamesW = readGamesWon(p.id);
                  final gamesL = readGamesLost(p.id);
                  final points = readPoints(p.id);
                  final duelPct = duelsP > 0 ? (duelsW / duelsP * 100.0) : 0.0;
                  final gamePct = (gamesW + gamesL) > 0 ? (gamesW / (gamesW + gamesL) * 100.0) : 0.0;

                  return DataRow(cells: [
                    DataCell(Text('${i + 1}')),
                    DataCell(Text(p.displayName)),
                    DataCell(Text(_displayDeckName(p.deckName))),
                    DataCell(Text('$points')),
                    DataCell(Text('$duelsW')),
                    DataCell(Text('$duelsL')),
                    DataCell(Text('$gamesW')),
                    DataCell(Text('$gamesL')),
                    DataCell(Text('${duelPct.toStringAsFixed(1)}%')),
                    DataCell(Text('${gamePct.toStringAsFixed(1)}%')),
                  ]);
                }),
              ),
            ),
          ),
          const SizedBox(height: 12),
          const Text('Resultados por ronda (desglose):', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          if (swissResultsByRound.isEmpty)
            const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Text('Aún no hay resultados de rondas.'))
          else
            ...swissRoundsSorted.map((round) {
              final list = swissResultsByRound[round]!;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Ronda $round', style: const TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  ...list.map((m) {
                    final aName = m.a.displayName;
                    final bName = m.b != null ? m.b!.displayName : 'bye';
                    final score = m.b == null ? '(bye)' : '${m.scoreA}-${m.scoreB}';
                    final winner = m.b == null ? m.a.displayName : (m.winnerId == m.a.id ? m.a.displayName : (m.b?.displayName ?? ''));
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Text('• $aName $score $bName → ganador: $winner'),
                    );
                  }).toList(),
                  const SizedBox(height: 8),
                ],
              );
            }).toList(),
        ],
      );
    });
  }

  // Igual que antes: renderiza texto del bracket (solo para mostrar eliminatorias, no influye en la tabla).
}


/// Muestra un diálogo con estadísticas por raza y detalles por ronda.
/// - players: lista de Player
/// - swissResultsByRound: Map<int, List<MatchResult>>
/// - allMatchResults: lista de todos los MatchResult (Swiss + elim)
/// - stats: Map<String, PlayerStats>
Future<void> showRaceStatsDialog(
  BuildContext context, {
  required List<Player> players,
  required Map<int, List<MatchResult>> swissResultsByRound,
  required List<MatchResult> allMatchResults,
  required Map<String, PlayerStats> stats,
}) {
  // calcula agregados / wins matrix antes de abrir el dialog
  final playersByRace = <String, List<Player>>{};
  for (final p in players) {
    playersByRace.putIfAbsent(p.race, () => []).add(p);
  }

  final raceStats = <String, Map<String, dynamic>>{};
  for (final entry in playersByRace.entries) {
    final race = entry.key;
    final playersList = entry.value;
    final summary = {
      'players': playersList.length,
      'matchesPlayed': 0,
      'matchesWon': 0,
      'gamesWon': 0,
      'gamesLost': 0,
    };
    for (final pl in playersList) {
      final s = stats[pl.id];
      summary['matchesPlayed'] = (summary['matchesPlayed'] as int) + (_toIntSafeLocal(s?.matchesPlayed));
      summary['matchesWon'] = (summary['matchesWon'] as int) + (_toIntSafeLocal(s?.matchesWon));
      summary['gamesWon'] = (summary['gamesWon'] as int) + (_toIntSafeLocal(s?.gamesWon));
      summary['gamesLost'] = (summary['gamesLost'] as int) + (_toIntSafeLocal(s?.gamesLost));
    }
    raceStats[race] = summary;
  }

  final winsMatrix = <String, Map<String, int>>{};
  for (final r in playersByRace.keys) winsMatrix[r] = {};

  for (final m in allMatchResults) {
    if (m.b == null) continue;
    final winnerId = m.winnerId;
    final loserId = (winnerId == m.a.id) ? m.b!.id : m.a.id;

    // localizar indices (si no se encuentran, ignoramos ese match para la matriz)
    final winnerIdx = players.indexWhere((p) => p.id == winnerId);
    final loserIdx = players.indexWhere((p) => p.id == loserId);
    if (winnerIdx == -1 || loserIdx == -1) continue;

    final winner = players[winnerIdx];
    final loser = players[loserIdx];
    final wr = winner.race;
    final lr = loser.race;
    winsMatrix.putIfAbsent(wr, () => {});
    winsMatrix[wr]![lr] = (winsMatrix[wr]![lr] ?? 0) + 1;
  }

  return showDialog(
    context: context,
    builder: (ctx) {
      final rows = raceStats.entries.toList();
      final roundsSorted = swissResultsByRound.keys.toList()..sort();

      return AlertDialog(
        title: const Text('Detalles por raza'),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Resumen por raza: jugadores / matches jugados / matches ganados / games W / games L'),
              const SizedBox(height: 8),
              Expanded(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    DataTable(
                      columns: const [
                        DataColumn(label: Text('Raza')),
                        DataColumn(label: Text('#Jugadores')),
                        DataColumn(label: Text('MatchesJug')),
                        DataColumn(label: Text('MatchesWin')),
                        DataColumn(label: Text('GamesW')),
                        DataColumn(label: Text('GamesL')),
                        DataColumn(label: Text('Win%')),
                      ],
                      rows: rows.map((e) {
                        final r = e.key;
                        final map = e.value;
                        final mp = (map['matchesPlayed'] as int);
                        final mw = (map['matchesWon'] as int);
                        final gw = (map['gamesWon'] as int);
                        final gl = (map['gamesLost'] as int);
                        final winPct = mp == 0 ? 0.0 : (mw / mp * 100);
                        return DataRow(cells: [
                          DataCell(Text(r)),
                          DataCell(Text('${map['players']}')),
                          DataCell(Text('$mp')),
                          DataCell(Text('$mw')),
                          DataCell(Text('$gw')),
                          DataCell(Text('$gl')),
                          DataCell(Text('${winPct.toStringAsFixed(1)}%')),
                        ]);
                      }).toList(),
                    ),
                    const SizedBox(height: 12),
                    const Text('¿A quién le ganan? (por enfrentamiento — "victorias / partidas jugadas (win%)")'),
                    const SizedBox(height: 8),
                    Builder(builder: (ctx) {
                      final races = winsMatrix.keys.toList()..sort();
                      if (races.isEmpty) return const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Text('No hay datos de enfrentamientos aún.'));
                      final totalBetween = <String, Map<String, int>>{};
                      for (final a in races) {
                        totalBetween[a] = {};
                        for (final b in races) {
                          final wab = winsMatrix[a]?[b] ?? 0;
                          final wba = winsMatrix[b]?[a] ?? 0;
                          totalBetween[a]![b] = wab + wba;
                        }
                      }
                      final columns = <DataColumn>[
                        const DataColumn(label: Text('Raza \\ vs', style: TextStyle(fontWeight: FontWeight.bold))),
                        ...races.map((r) => DataColumn(label: Text(r, style: const TextStyle(fontWeight: FontWeight.bold)))),
                      ];
                      final rowsWidgets = races.map((att) {
                        final cells = <DataCell>[];
                        cells.add(DataCell(Text(att)));
                        for (final def in races) {
                          final wins = winsMatrix[att]?[def] ?? 0;
                          final played = totalBetween[att]![def] ?? 0;
                          String txt;
                          if (played == 0) txt = '-';
                          else {
                            final pct = (wins / played * 100);
                            txt = '$wins / $played (${pct.toStringAsFixed(0)}%)';
                          }
                          cells.add(DataCell(Text(txt)));
                        }
                        return DataRow(cells: cells);
                      }).toList();

                      return SizedBox(
                        height: 300,
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: SingleChildScrollView(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                DataTable(columns: columns, rows: rowsWidgets, dataRowHeight: 38, headingRowHeight: 44, columnSpacing: 18),
                                const SizedBox(height: 8),
                                const Text(
                                  'Leyenda: "victorias / partidas jugadas (win%)" — las partidas jugadas son el total de enfrentamientos entre las dos razas (A vs B y B vs A).',
                                  style: TextStyle(fontSize: 12),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    }),
                    const SizedBox(height: 12),
                    const Divider(),
                    const SizedBox(height: 8),
                    const Text('Desglose por ronda (Swiss):', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    ...roundsSorted.map((round) {
                      final list = swissResultsByRound[round]!;
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Ronda $round', style: const TextStyle(fontWeight: FontWeight.w600)),
                          const SizedBox(height: 6),
                          ...list.map((m) {
                            final aName = m.a.displayName;
                            final bName = m.b != null ? m.b!.displayName : 'bye';
                            final score = m.b == null ? '(bye)' : '${m.scoreA}-${m.scoreB}';
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 2),
                              child: Text('• $aName vs  $bName → $score'),
                            );
                          }).toList(),
                          const SizedBox(height: 8),
                        ],
                      );
                    }).toList(),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cerrar')),
        ],
      );
    },
  );
}

/// Helper local para el bloque de raceStats (porque estamos fuera de la clase)
int _toIntSafeLocal(dynamic v) {
  if (v == null) return 0;
  if (v is int) return v;
  if (v is double) return v.toInt();
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v) ?? 0;
  return 0;
}



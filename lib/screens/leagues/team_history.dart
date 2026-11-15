// lib/screens/leagues/team_history.dart
//
// Tabla histórica del team: sumatoria EN VIVO de todo duelo con resultado de
// TODAS las ligas del team, agrupada por jugador. No lee ni escribe
// teams/{teamId}/players (esos campos son solo roster/nombre) — se recalcula
// desde cero a partir de leagues/*/rounds/*/matches cada vez que se abre.

import 'package:cloud_firestore/cloud_firestore.dart';

import 'models.dart';

class TeamHistoryRow {
  final String playerId;
  final String name;
  int matchesWon = 0;
  int matchesLost = 0;
  int matchesDraw = 0;
  int gamesFavor = 0;
  int gamesAgainst = 0;

  TeamHistoryRow({required this.playerId, required this.name});

  int get matchesPlayed => matchesWon + matchesLost + matchesDraw;
  int get points => matchesWon * 3 + matchesDraw;
  int get diff => gamesFavor - gamesAgainst;
  double get winPct => matchesPlayed > 0 ? matchesWon / matchesPlayed * 100 : 0;
  double get ptsPct =>
      matchesPlayed > 0 ? points / (matchesPlayed * 3) * 100 : 0;
}

class TeamHistoryResult {
  final List<TeamHistoryRow> rows;
  final int leagueCount;
  TeamHistoryResult({required this.rows, required this.leagueCount});
}

/// Recorre todas las ligas del team y suma los duelos con resultado
/// (`winnerId != null`) de todas sus fechas, por jugador.
Future<TeamHistoryResult> computeTeamHistory(String teamId) async {
  final db = FirebaseFirestore.instance;
  final leaguesSnap =
      await db.collection('leagues').where('teamId', isEqualTo: teamId).get();

  final rows = <String, TeamHistoryRow>{};
  TeamHistoryRow rowFor(String id, String name) =>
      rows.putIfAbsent(id, () => TeamHistoryRow(playerId: id, name: name));

  for (final league in leaguesSnap.docs) {
    final roundsSnap = await league.reference.collection('rounds').get();
    for (final round in roundsSnap.docs) {
      final rawMatches = (round.data()['matches'] as List<dynamic>?) ?? [];
      for (final rm in rawMatches) {
        if (rm is! Map<String, dynamic>) continue;
        final m = RoundMatch.fromMap(rm);
        if (!m.hasResult) continue;

        final a = rowFor(m.playerAId, m.playerAName);
        if (m.isBye) {
          a.matchesWon++;
          a.gamesFavor += 2;
          continue;
        }

        final b = rowFor(m.playerBId!, m.playerBName ?? m.playerBId!);
        final scoreA = m.scoreA ?? 0;
        final scoreB = m.scoreB ?? 0;
        a.gamesFavor += scoreA;
        a.gamesAgainst += scoreB;
        b.gamesFavor += scoreB;
        b.gamesAgainst += scoreA;

        if (m.winnerId == m.playerAId) {
          a.matchesWon++;
          b.matchesLost++;
        } else if (m.winnerId == m.playerBId) {
          b.matchesWon++;
          a.matchesLost++;
        } else {
          a.matchesDraw++;
          b.matchesDraw++;
        }
      }
    }
  }

  final list =
      rows.values.toList()..sort((x, y) {
        final cp = y.points.compareTo(x.points);
        if (cp != 0) return cp;
        final cd = y.diff.compareTo(x.diff);
        if (cd != 0) return cd;
        return y.winPct.compareTo(x.winPct);
      });

  return TeamHistoryResult(rows: list, leagueCount: leaguesSnap.docs.length);
}

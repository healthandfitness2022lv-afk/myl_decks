// lib/screens/leagues/league_widgets.dart
import 'package:flutter/material.dart';
import '../../models/deck.dart';
import 'models.dart';

String _playedDateLabel(RoundMatch match) {
  if (!match.hasResult) return '';
  final milliseconds = match.resultAt;
  if (milliseconds == null) return 'Fecha sin registrar';
  final date = DateTime.fromMillisecondsSinceEpoch(milliseconds);
  final day = date.day.toString().padLeft(2, '0');
  final month = date.month.toString().padLeft(2, '0');
  return '$day/$month/${date.year}';
}

// ── Tarjetita compacta de mesa/duelo ──────────────────────────────────────────
//
// Vista compacta para la grilla de la fecha: se toca para cargar/editar el
// resultado. Un menú ⋮ (solo admin) expone editar mazos y eliminar duelo.

class RoundMatchTile extends StatelessWidget {
  final RoundMatch match;
  final int index;
  final bool isAdmin;
  final int duelsPerMatch;
  final String? raceA;
  final String? raceB;
  final VoidCallback onResult;
  final VoidCallback onEditDecks;
  final VoidCallback onRemove;

  const RoundMatchTile({
    super.key,
    required this.match,
    required this.index,
    required this.isAdmin,
    this.duelsPerMatch = 1,
    this.raceA,
    this.raceB,
    required this.onResult,
    required this.onEditDecks,
    required this.onRemove,
  });

  static const Color _gold = Color(0xFFD8B46A);

  @override
  Widget build(BuildContext context) {
    final m = match;
    final hasResult = m.hasResult;
    final isWinnerA = hasResult && m.winnerId == m.playerAId;
    final isWinnerB = hasResult && m.winnerId == m.playerBId;
    final wonTossA = m.coinTossWinnerId == m.playerAId;
    final wonTossB =
        m.coinTossWinnerId != null && m.coinTossWinnerId == m.playerBId;
    final statusColor = hasResult ? const Color(0xFF6FCF8E) : _gold;
    final playedDate = _playedDateLabel(m);

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF221913), Color(0xFF161009)],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color:
              hasResult
                  ? const Color(0xFF6FCF8E).withValues(alpha: .35)
                  : _gold.withValues(alpha: .28),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .35),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onResult,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 6, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Header: Mesa N + estado + menú
                Row(
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: statusColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Mesa $index',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 11,
                        letterSpacing: .3,
                        color: Colors.white.withValues(alpha: .55),
                      ),
                    ),
                    const Spacer(),
                    if (isAdmin)
                      SizedBox(
                        width: 26,
                        height: 26,
                        child: PopupMenuButton<String>(
                          padding: EdgeInsets.zero,
                          iconSize: 17,
                          icon: Icon(
                            Icons.more_vert_rounded,
                            color: Colors.white.withValues(alpha: .5),
                          ),
                          color: const Color(0xFF21170F),
                          tooltip: 'Acciones',
                          onSelected: (v) {
                            if (v == 'result') onResult();
                            if (v == 'decks') onEditDecks();
                            if (v == 'remove') onRemove();
                          },
                          itemBuilder:
                              (_) => [
                                PopupMenuItem(
                                  value: 'result',
                                  child: Text(
                                    hasResult
                                        ? 'Editar resultado'
                                        : 'Cargar resultado',
                                  ),
                                ),
                                const PopupMenuItem(
                                  value: 'decks',
                                  child: Text('Editar mazos'),
                                ),
                                const PopupMenuItem(
                                  value: 'remove',
                                  child: Text(
                                    'Eliminar duelo',
                                    style: TextStyle(color: Color(0xFFE58A8A)),
                                  ),
                                ),
                              ],
                        ),
                      )
                    else
                      const SizedBox(height: 26),
                  ],
                ),
                // Enfrentamiento en una fila: A · marcador · B
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: _tilePlayer(
                        context,
                        m.playerAName,
                        raceA,
                        isWinnerA,
                        CrossAxisAlignment.start,
                        wonCoinToss: wonTossA,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Text(
                        m.isBye
                            ? 'BYE'
                            : hasResult
                            ? '${m.scoreA ?? 0}–${m.scoreB ?? 0}'
                            : 'vs',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: hasResult ? 16 : 13,
                          color:
                              hasResult
                                  ? Colors.white
                                  : Colors.white.withValues(alpha: .4),
                        ),
                      ),
                    ),
                    Expanded(
                      child:
                          m.isBye
                              ? const SizedBox()
                              : _tilePlayer(
                                context,
                                m.playerBName ?? '',
                                raceB,
                                isWinnerB,
                                CrossAxisAlignment.end,
                                wonCoinToss: wonTossB,
                              ),
                    ),
                  ],
                ),
                if (hasResult)
                  Text(
                    'Jugado: $playedDate',
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: Colors.white.withValues(alpha: .5),
                    ),
                  )
                else if (duelsPerMatch > 1)
                  Text(
                    'Bo$duelsPerMatch',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.white.withValues(alpha: .35),
                    ),
                  )
                else
                  const SizedBox(height: 2),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _tilePlayer(
    BuildContext context,
    String name,
    String? race,
    bool isWinner,
    CrossAxisAlignment align, {
    bool wonCoinToss = false,
  }) {
    final isEnd = align == CrossAxisAlignment.end;
    final nameRow = Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment:
          isEnd ? MainAxisAlignment.end : MainAxisAlignment.start,
      children: [
        if (isWinner && !isEnd) ...[
          const Icon(Icons.emoji_events_rounded, size: 12, color: _gold),
          const SizedBox(width: 3),
        ],
        if (wonCoinToss && !isEnd) ...[
          Icon(
            Icons.casino_rounded,
            size: 12,
            color: Colors.white.withValues(alpha: .55),
          ),
          const SizedBox(width: 3),
        ],
        Flexible(
          child: Text(
            name,
            textAlign: isEnd ? TextAlign.right : TextAlign.left,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 13,
              color: isWinner ? _gold : Colors.white,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (wonCoinToss && isEnd) ...[
          const SizedBox(width: 3),
          Icon(
            Icons.casino_rounded,
            size: 12,
            color: Colors.white.withValues(alpha: .55),
          ),
        ],
        if (isWinner && isEnd) ...[
          const SizedBox(width: 3),
          const Icon(Icons.emoji_events_rounded, size: 12, color: _gold),
        ],
      ],
    );

    return Column(
      crossAxisAlignment: align,
      mainAxisSize: MainAxisSize.min,
      children: [
        nameRow,
        if (race != null && race.isNotEmpty)
          Text(
            race,
            textAlign: isEnd ? TextAlign.right : TextAlign.left,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: _gold.withValues(alpha: .85),
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
      ],
    );
  }
}

// ── Tarjeta de duelo en una fecha ─────────────────────────────────────────────

class RoundMatchCard extends StatelessWidget {
  final RoundMatch match;
  final int index;
  final bool isAdmin;
  final int duelsPerMatch;
  final VoidCallback onResult;
  final VoidCallback onEditDecks;
  final VoidCallback onRemove;
  final String? raceA;
  final String? raceB;

  const RoundMatchCard({
    super.key,
    required this.match,
    required this.index,
    required this.isAdmin,
    this.duelsPerMatch = 1,
    required this.onResult,
    required this.onEditDecks,
    required this.onRemove,
    this.raceA,
    this.raceB,
  });

  @override
  Widget build(BuildContext context) {
    final m = match;
    final hasResult = m.hasResult;
    final isWinnerA = hasResult && m.winnerId == m.playerAId;
    final isWinnerB = hasResult && m.winnerId == m.playerBId;
    final wonTossA = m.coinTossWinnerId == m.playerAId;
    final wonTossB =
        m.coinTossWinnerId != null && m.coinTossWinnerId == m.playerBId;
    final playedDate = _playedDateLabel(m);

    Color statusColor = hasResult ? Colors.green : Colors.orange;

    return Card(
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color:
              hasResult
                  ? Colors.green.withValues(alpha: .4)
                  : Colors.orange.withValues(alpha: .3),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header: Mesa N + estado + acciones
            Row(
              children: [
                Text(
                  'Mesa $index',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: .12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    hasResult ? 'Finalizado' : 'Pendiente',
                    style: TextStyle(
                      fontSize: 11,
                      color: statusColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (playedDate.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      'Jugado $playedDate',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                  ),
                ],
                const Spacer(),
                if (isAdmin) ...[
                  IconButton(
                    icon: const Icon(Icons.edit_note_rounded, size: 18),
                    tooltip: 'Editar mazos',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: onEditDecks,
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: Icon(
                      hasResult
                          ? Icons.edit_rounded
                          : Icons.sports_score_rounded,
                      size: 18,
                    ),
                    tooltip:
                        hasResult ? 'Editar resultado' : 'Cargar resultado',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: onResult,
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(
                      Icons.delete_outline_rounded,
                      size: 18,
                      color: Colors.red,
                    ),
                    tooltip: 'Eliminar duelo',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: onRemove,
                  ),
                ],
              ],
            ),

            const SizedBox(height: 10),

            // Enfrentamiento
            Row(
              children: [
                // Jugador A
                Expanded(
                  child: _PlayerSide(
                    name: m.playerAName,
                    deck: m.deckA,
                    score: m.scoreA,
                    isWinner: isWinnerA,
                    wonCoinToss: wonTossA,
                    align: CrossAxisAlignment.start,
                    race: raceA,
                  ),
                ),

                // Resultado central
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child:
                      m.isBye
                          ? const Text(
                            'BYE',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              color: Colors.grey,
                            ),
                          )
                          : hasResult
                          ? Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '${m.scoreA ?? 0} – ${m.scoreB ?? 0}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 16,
                                ),
                              ),
                              if (duelsPerMatch > 1)
                                Text(
                                  'Bo$duelsPerMatch',
                                  style: const TextStyle(
                                    fontSize: 10,
                                    color: Colors.grey,
                                  ),
                                ),
                            ],
                          )
                          : Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text(
                                'vs',
                                style: TextStyle(fontWeight: FontWeight.w700),
                              ),
                              if (duelsPerMatch > 1)
                                Text(
                                  'Bo$duelsPerMatch',
                                  style: const TextStyle(
                                    fontSize: 10,
                                    color: Colors.grey,
                                  ),
                                ),
                            ],
                          ),
                ),

                // Jugador B
                Expanded(
                  child:
                      m.isBye
                          ? const SizedBox()
                          : _PlayerSide(
                            name: m.playerBName ?? '',
                            deck: m.deckB,
                            score: m.scoreB,
                            isWinner: isWinnerB,
                            wonCoinToss: wonTossB,
                            align: CrossAxisAlignment.end,
                            race: raceB,
                          ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PlayerSide extends StatelessWidget {
  final String name;
  final List<DeckCardEntry> deck;
  final int? score;
  final bool isWinner;
  final bool wonCoinToss;
  final CrossAxisAlignment align;
  final String? race;

  const _PlayerSide({
    required this.name,
    required this.deck,
    required this.score,
    required this.isWinner,
    this.wonCoinToss = false,
    required this.align,
    this.race,
  });

  @override
  Widget build(BuildContext context) {
    final deckCount = deck.fold<int>(0, (s, e) => s + e.count);
    return Column(
      crossAxisAlignment: align,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isWinner && align == CrossAxisAlignment.start) ...[
              const Icon(
                Icons.emoji_events_rounded,
                size: 14,
                color: Colors.amber,
              ),
              const SizedBox(width: 4),
            ],
            if (wonCoinToss && align == CrossAxisAlignment.start) ...[
              Icon(Icons.casino_rounded, size: 13, color: Colors.grey.shade500),
              const SizedBox(width: 4),
            ],
            Flexible(
              child: Text(
                name,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color:
                      isWinner ? Theme.of(context).colorScheme.primary : null,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (wonCoinToss && align == CrossAxisAlignment.end) ...[
              const SizedBox(width: 4),
              Icon(Icons.casino_rounded, size: 13, color: Colors.grey.shade500),
            ],
            if (isWinner && align == CrossAxisAlignment.end) ...[
              const SizedBox(width: 4),
              const Icon(
                Icons.emoji_events_rounded,
                size: 14,
                color: Colors.amber,
              ),
            ],
          ],
        ),
        if (race != null && race!.isNotEmpty)
          Text(
            race!,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.primary,
            ),
            overflow: TextOverflow.ellipsis,
          )
        else
          Text(
            deckCount > 0 ? '$deckCount cartas' : 'Sin mazo',
            style: TextStyle(
              fontSize: 11,
              color: deckCount > 0 ? Colors.grey : Colors.red.shade300,
            ),
          ),
      ],
    );
  }
}

// ── Tabla de posiciones acumulada ─────────────────────────────────────────────

class LeagueStandingsSheet extends StatelessWidget {
  final List<LeagueStanding> standings;

  const LeagueStandingsSheet({super.key, required this.standings});

  @override
  Widget build(BuildContext context) {
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
                  const Expanded(
                    child: Text(
                      'Tabla de posiciones',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (standings.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'No hay resultados de fechas finalizadas todavía.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey),
                  ),
                )
              else
                Expanded(
                  child: SingleChildScrollView(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final isWide = constraints.maxWidth >= 600;
                        if (isWide) {
                          return _WideStandingsTable(standings: standings);
                        }
                        return _NarrowStandingsList(standings: standings);
                      },
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NarrowStandingsList extends StatelessWidget {
  final List<LeagueStanding> standings;
  const _NarrowStandingsList({required this.standings});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: List.generate(standings.length, (i) {
        final s = standings[i];
        final duelPct = (s.duelWinPct * 100).toStringAsFixed(1);
        final gamePct = (s.gameWinPct * 100).toStringAsFixed(1);

        return Card(
          margin: const EdgeInsets.symmetric(vertical: 4),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Row(
              children: [
                CircleAvatar(radius: 18, child: Text('${i + 1}')),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        s.player.name,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      Text(
                        'D: ${s.matchesWon}W / ${s.matchesLost}L  ($duelPct%)',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${s.points} pts',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    Text(
                      'G: $gamePct%',
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      }),
    );
  }
}

class _WideStandingsTable extends StatelessWidget {
  final List<LeagueStanding> standings;
  const _WideStandingsTable({required this.standings});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columnSpacing: 16,
        columns: const [
          DataColumn(label: Text('#')),
          DataColumn(label: Text('Jugador')),
          DataColumn(label: Text('Pts')),
          DataColumn(label: Text('D W')),
          DataColumn(label: Text('D L')),
          DataColumn(label: Text('%Duel')),
          DataColumn(label: Text('G W')),
          DataColumn(label: Text('G L')),
          DataColumn(label: Text('%Game')),
        ],
        rows: List.generate(standings.length, (i) {
          final s = standings[i];
          return DataRow(
            cells: [
              DataCell(Text('${i + 1}')),
              DataCell(Text(s.player.name)),
              DataCell(Text('${s.points}')),
              DataCell(Text('${s.matchesWon}')),
              DataCell(Text('${s.matchesLost}')),
              DataCell(Text('${(s.duelWinPct * 100).toStringAsFixed(1)}%')),
              DataCell(Text('${s.gamesWon}')),
              DataCell(Text('${s.gamesLost}')),
              DataCell(Text('${(s.gameWinPct * 100).toStringAsFixed(1)}%')),
            ],
          );
        }),
      ),
    );
  }
}

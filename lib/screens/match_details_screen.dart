import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '/services/match_service.dart'; // idempotente para cerrar y sumar stats
import '../battlefield/screens/battlefield_screen.dart';

class MatchDetailsScreen extends StatefulWidget {
  final String matchId;

  /// Permite auto-abrir el tablero al entrar (útil cuando vienes desde un listener).
  final bool autoOpenBattlefield;

  const MatchDetailsScreen({
    super.key,
    required this.matchId,
    this.autoOpenBattlefield = false,
  });

  @override
  State<MatchDetailsScreen> createState() => _MatchDetailsScreenState();
}

class _MatchDetailsScreenState extends State<MatchDetailsScreen> {
  bool _autoOpened = false; // evita doble navegación en auto-open

  @override
  void initState() {
    super.initState();
    if (widget.autoOpenBattlefield) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _goToBattlefieldIfReady());
    }
  }

  Future<void> _goToBattlefieldIfReady() async {
    if (_autoOpened) return;
    try {
      final snap = await FirebaseFirestore.instance
          .collection('matches')
          .doc(widget.matchId)
          .get();
      final m = snap.data();
      if (m == null) return;

      final aName = (m['playerAName'] ?? 'Jugador A') as String;
      final bName = (m['playerBName'] ?? 'Jugador B') as String;
      final deckAName = (m['deckAName'] ?? '') as String;
      final deckBName = (m['deckBName'] ?? '') as String;

      final deckAId = (m['deckA'] ?? '') as String;
      final deckBId = (m['deckB'] ?? '') as String;
      final deckAOwnerId = (m['deckAOwnerId'] ?? m['playerA'] ?? '') as String;
      final deckBOwnerId = (m['deckBOwnerId'] ?? m['playerB'] ?? '') as String;

      final playerAUid = (m['playerA'] ?? '') as String;
      final playerBUid = (m['playerB'] ?? '') as String;

      final currentUid = FirebaseAuth.instance.currentUser?.uid ?? '';

      // Detección robusta de lado (B si soy dueño del mazo B; si no, cae a playerB)
      bool iAmB = false;
      if (currentUid == deckBOwnerId || currentUid == playerBUid) {
        iAmB = true;
      } else if (currentUid == deckAOwnerId || currentUid == playerAUid) {
        iAmB = false;
      }

      if (!mounted) return;
      _autoOpened = true;

      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => BattlefieldScreen(
  matchId: widget.matchId, // 👈 requerido
  playerAName: aName,
  playerBName: bName,
  deckAName: deckAName,
  deckBName: deckBName,
  userIdA: deckAOwnerId,
  deckIdA: deckAId,
  userIdB: deckBOwnerId,
  deckIdB: deckBId,
  currentUserIsPlayerB: iAmB,
  deckASize: 50,
  deckBSize: 50,
  currentUserId: FirebaseAuth.instance.currentUser!.uid,
),

        ),
      );
    } catch (_) {
      // Silencioso: si falla, el usuario puede abrir manualmente con el botón.
    }
  }

  @override
  Widget build(BuildContext context) {
    final matchRef = FirebaseFirestore.instance.collection('matches').doc(widget.matchId);

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: matchRef.snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        if (!snap.hasData || !snap.data!.exists) {
          return const Scaffold(body: Center(child: Text('Match no encontrado')));
        }

        final d = snap.data!.data()!;
        final aName = (d['playerAName'] ?? 'Jugador A') as String;
        final bName = (d['playerBName'] ?? 'Jugador B') as String;
        final deckAName = (d['deckAName'] ?? '') as String;
        final deckBName = (d['deckBName'] ?? '') as String;

        final results = List<String>.from((d['results'] ?? ['', '', '']) as List);
        final aWins = (d['aWins'] ?? 0) as int;
        final bWins = (d['bWins'] ?? 0) as int;
        final winner = (d['winner'] ?? '') as String?;
        final status = (d['status'] ?? 'ongoing') as String;

        // IDs de mazos y dueños
        final deckAId = (d['deckA'] ?? '') as String;
        final deckBId = (d['deckB'] ?? '') as String;
        final deckAOwnerId = (d['deckAOwnerId'] ?? '') as String;
        final deckBOwnerId = (d['deckBOwnerId'] ?? '') as String;

        final finished = status == 'finished' || (winner != null && winner.isNotEmpty);

        return Scaffold(
          appBar: AppBar(title: const Text('Match en vivo (Bo3)')),
          body: FutureBuilder<List<String?>>(
            future: _loadDeckThumbs(deckAId, deckBId, deckAOwnerId, deckBOwnerId),
            builder: (context, thumbsSnap) {
              final aThumb = (thumbsSnap.data != null) ? thumbsSnap.data![0] : null;
              final bThumb = (thumbsSnap.data != null) ? thumbsSnap.data![1] : null;

              return SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _VsHeader(
                      aName: aName,
                      bName: bName,
                      deckAName: deckAName,
                      deckBName: deckBName,
                      aThumb: aThumb,
                      bThumb: bThumb,
                      aWins: aWins,
                      bWins: bWins,
                    ),
                    const SizedBox(height: 16),

                    FilledButton.icon(
                      onPressed: finished
                          ? null
                          : () {
                              final currentUid = FirebaseAuth.instance.currentUser?.uid;

                              // Soy B si mi uid coincide con el dueño del mazo B o playerB
                              bool iAmB = false;
                              if (currentUid != null) {
                                if (currentUid == deckBOwnerId) iAmB = true;
                              }

                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => BattlefieldScreen(
  matchId: widget.matchId, // 👈 requerido
  playerAName: aName,
  playerBName: bName,
  deckAName: deckAName,
  deckBName: deckBName,
  userIdA: deckAOwnerId,
  deckIdA: deckAId,
  userIdB: deckBOwnerId,
  deckIdB: deckBId,
  currentUserIsPlayerB: iAmB,
  deckASize: 50,
  deckBSize: 50,
  currentUserId: FirebaseAuth.instance.currentUser!.uid,
),

                                ),
                              );
                            },
                      icon: const Icon(Icons.sports_esports),
                      label: const Text('Abrir campo de batalla'),
                    ),

                    // Juegos 1-3
                    _GameRow(
                      index: 0,
                      value: results[0],
                      disabled: finished,
                      onPick: (side) => _setGameResult(matchRef, results, side, 0),
                    ),
                    _GameRow(
                      index: 1,
                      value: results[1],
                      disabled: finished,
                      onPick: (side) => _setGameResult(matchRef, results, side, 1),
                    ),

                    if (!finished && aWins < 2 && bWins < 2)
                      _GameRow(
                        index: 2,
                        value: results[2],
                        disabled: finished,
                        onPick: (side) => _setGameResult(matchRef, results, side, 2),
                      ),

                    const SizedBox(height: 12),

                    if (winner != null && winner.isNotEmpty)
                      _WinnerBanner(isA: winner == d['playerA']),

                    const SizedBox(height: 8),

                    OutlinedButton.icon(
                      onPressed: finished
                          ? null
                          : () async {
                              // borra el último juego decidido (2 → 1 → 0)
                              for (int i = 2; i >= 0; i--) {
                                if (results[i] == 'A' || results[i] == 'B') {
                                  results[i] = '';
                                  break;
                                }
                              }
                              await _recomputeFrom(matchRef, results);
                            },
                      icon: const Icon(Icons.undo),
                      label: const Text('Revertir último juego'),
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }

  // ---------- Helpers de datos ----------

  // Lee coverUrl/miniatura de cada mazo desde users/{owner}/decks/{id}
  Future<List<String?>> _loadDeckThumbs(
    String deckAId,
    String deckBId,
    String ownerA,
    String ownerB,
  ) async {
    Future<String?> thumbOf(String deckId, String ownerId) async {
      if (deckId.isEmpty || ownerId.isEmpty) return null;
      final d = await FirebaseFirestore.instance
          .collection('users')
          .doc(ownerId)
          .collection('decks')
          .doc(deckId)
          .get();
      final m = d.data();
      return (m?['coverUrl'] ?? m?['thumbUrl'] ?? m?['imageUrl']) as String?;
    }

    final a = await thumbOf(deckAId, ownerA);
    final b = await thumbOf(deckBId, ownerB);
    return [a, b];
  }

  Future<void> _setGameResult(
    DocumentReference<Map<String, dynamic>> matchRef,
    List<String> current,
    String side,
    int index,
  ) async {
    // Evita cambios si ya hay 2 victorias definidas
    final aWins = current.where((r) => r == 'A').length;
    final bWins = current.where((r) => r == 'B').length;
    if (aWins >= 2 || bWins >= 2) return;

    current[index] = side;
    await _recomputeFrom(matchRef, current);
  }

  /// Recalcula `aWins/bWins`. Si hay ganador (2 victorias), cierra el match
  /// con MatchService.finalizeMatch (sumando stats de usuarios y mazos).
  Future<void> _recomputeFrom(
    DocumentReference<Map<String, dynamic>> matchRef,
    List<String> results,
  ) async {
    // Normaliza: siempre 3 elementos
    final normalized = List<String>.from(results);
    while (normalized.length < 3) normalized.add('');
    if (normalized.length > 3) normalized.removeRange(3, normalized.length);

    final aWins = normalized.where((r) => r == 'A').length;
    final bWins = normalized.where((r) => r == 'B').length;

    if (aWins >= 2 || bWins >= 2) {
      await MatchService.finalizeMatch(
        matchId: matchRef.id,
        results: normalized,
      );
    } else {
      await matchRef.update({
        'results': normalized,
        'aWins': aWins,
        'bWins': bWins,
        'winner': '',
        'status': 'ongoing',
      });
    }
  }
}

// ---------- UI widgets ----------

class _VsHeader extends StatelessWidget {
  final String aName, bName, deckAName, deckBName;
  final String? aThumb, bThumb;
  final int aWins, bWins;

  const _VsHeader({
    required this.aName,
    required this.bName,
    required this.deckAName,
    required this.deckBName,
    required this.aThumb,
    required this.bThumb,
    required this.aWins,
    required this.bWins,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 16, 12, 16),
        child: Column(
          children: [
            Row(
              children: [
                _DeckPill(name: aName, deck: deckAName, thumb: aThumb, alignRight: false),
                Expanded(
                  child: Column(
                    children: [
                      Text('VS', style: Theme.of(context).textTheme.headlineMedium),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: cs.surfaceVariant,
                          borderRadius: BorderRadius.circular(99),
                        ),
                        child: Text('A $aWins - $bWins B'),
                      ),
                    ],
                  ),
                ),
                _DeckPill(name: bName, deck: deckBName, thumb: bThumb, alignRight: true),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DeckPill extends StatelessWidget {
  final String name, deck;
  final String? thumb;
  final bool alignRight;

  const _DeckPill({required this.name, required this.deck, required this.thumb, required this.alignRight});

  @override
  Widget build(BuildContext context) {
    final avatar = ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: (thumb != null && thumb!.isNotEmpty)
          ? Image.network(thumb!, width: 64, height: 64, fit: BoxFit.cover)
          : Container(width: 64, height: 64, color: Colors.black12, child: const Icon(Icons.style)),
    );

    final text = Column(
      crossAxisAlignment: alignRight ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        Text(name, style: const TextStyle(fontWeight: FontWeight.w700)),
        Text(deck, maxLines: 1, overflow: TextOverflow.ellipsis),
      ],
    );

    return SizedBox(
      width: 160,
      child: Row(
        mainAxisAlignment: alignRight ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: alignRight ? [text, const SizedBox(width: 8), avatar] : [avatar, const SizedBox(width: 8), text],
      ),
    );
  }
}

class _GameRow extends StatelessWidget {
  final int index;
  final String value; // '', 'A' o 'B'
  final bool disabled;
  final void Function(String side) onPick;

  const _GameRow({required this.index, required this.value, required this.onPick, this.disabled = false});

  @override
  Widget build(BuildContext context) {
    final decidedA = value == 'A';
    final decidedB = value == 'B';
    return Card(
      child: ListTile(
        title: Text('Juego ${index + 1}'),
        trailing: Wrap(
          spacing: 8,
          children: [
            ChoiceChip(
              label: const Text('Gana A'),
              selected: decidedA,
              onSelected: disabled ? null : (_) => onPick('A'),
            ),
            ChoiceChip(
              label: const Text('Gana B'),
              selected: decidedB,
              onSelected: disabled ? null : (_) => onPick('B'),
            ),
          ],
        ),
      ),
    );
  }
}

class _WinnerBanner extends StatelessWidget {
  final bool isA;
  const _WinnerBanner({required this.isA});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isA ? cs.primaryContainer : cs.secondaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.emoji_events),
          const SizedBox(width: 8),
          Text(isA ? '¡Ganó el Jugador A!' : '¡Ganó el Jugador B!', style: const TextStyle(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

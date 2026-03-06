import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:material_symbols_icons/symbols.dart';

import './match_details_screen.dart';

class MatchScreen extends StatefulWidget {
  const MatchScreen({super.key});

  @override
  State<MatchScreen> createState() => _MatchScreenState();
}

class _MatchScreenState extends State<MatchScreen> {
  // Yo
  late final String _myUid;
  String _myName = 'Yo';

  String? _playerA; // por defecto = yo
  String? _playerB; // amigo
  String? _deckA;   // mi mazo
  String? _deckB;   // mazo del rival (si juegan altiro)
  String? _playerAName;
  String? _playerBName;
  String? _deckAName;
  String? _deckBName;

  // Para enviar desafío
  String? _challengeOpponentUid;
  String? _challengeOpponentName;
  String? _myDeckForChallenge;
  String? _myDeckForChallengeName;

  // Listener de matches aceptados (para auto-navegar a MatchDetails)
  StreamSubscription<QuerySnapshot>? _matchSub;
  final Set<String> _openedAuto = <String>{}; // evitar abrir duplicado
  late final DateTime _listenStartedAt;       // ignorar eventos viejos

  // Resultados (para “jugar ahora”)
  final List<String?> _results = [null, null, null];

  // Caches
  List<_FriendLite> _friends = [];
  List<_DeckLite> _myDecks = [];
  List<_DeckLite> _opponentDecks = [];

  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _myUid = FirebaseAuth.instance.currentUser!.uid;
    _loadMe();
    _loadFriends();
    _loadMyDecks();

    _listenStartedAt = DateTime.now();
    _startAcceptedMatchesListener();
  }

  @override
  void dispose() {
    _matchSub?.cancel();
    super.dispose();
  }

  Future<void> _loadMe() async {
    final me = await FirebaseFirestore.instance.collection('users').doc(_myUid).get();
    setState(() {
      _myName = (me.data()?['displayName'] ?? 'Yo').toString();
      _playerA = _myUid;
      _playerAName = _myName;
    });
  }

  void _startAcceptedMatchesListener() {
    _matchSub = FirebaseFirestore.instance
        .collection('matches')
        .where('players', arrayContains: _myUid)
        .where('status', isEqualTo: 'ongoing')
        .snapshots()
        .listen((snap) {
      for (final ch in snap.docChanges) {
        if (ch.type == DocumentChangeType.added ||
            ch.type == DocumentChangeType.modified) {
          final data = ch.doc.data();
          if (data == null) continue;

          final matchId    = ch.doc.id;
          final acceptedBy = (data['acceptedBy'] ?? '').toString();
          final acceptedAt = data['acceptedAt'];

          // Si yo fui quien aceptó, si no tiene acceptedBy, si ya lo abrí, o si es antiguo → ignora
          if (acceptedBy.isEmpty || acceptedBy == _myUid || _openedAuto.contains(matchId)) continue;

          if (acceptedAt is Timestamp) {
            final when = acceptedAt.toDate();
            if (when.isBefore(_listenStartedAt.subtract(const Duration(seconds: 2)))) {
              continue; // era viejo
            }
          }

          _openedAuto.add(matchId);

          if (!mounted) return;
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => MatchDetailsScreen(
                matchId: matchId,
                // Si tu MatchDetails soporta auto-open, puedes activar:
                // autoOpenBattlefield: true,
              ),
            ),
          );
        }
      }
    });
  }

  Future<void> _loadFriends() async {
    final qs = await FirebaseFirestore.instance
        .collection('users')
        .doc(_myUid)
        .collection('friends')
        .get();

    setState(() {
      _friends = qs.docs.map((d) {
        final data = d.data();
        return _FriendLite(
          uid: data['friendUid'] ?? d.id,
          name: (data['friendName'] ?? 'Amigo').toString(),
          username: (data['friendUsername'] ?? '').toString(),
        );
      }).toList();
    });
  }

  Future<void> _loadMyDecks() async {
    try {
      final qs = await FirebaseFirestore.instance
          .collection('users').doc(_myUid)
          .collection('decks')
          .orderBy('name')
          .get();
      setState(() {
        _myDecks = qs.docs
            .map((d) => _DeckLite(id: d.id, name: (d.data()['name'] ?? 'Mazo').toString()))
            .toList();
      });
    } on FirebaseException catch (e) {
      if (e.code == 'failed-precondition') {
        final qs = await FirebaseFirestore.instance
            .collection('users').doc(_myUid)
            .collection('decks')
            .get();
        final decks = qs.docs
            .map((d) => _DeckLite(id: d.id, name: (d.data()['name'] ?? 'Mazo').toString()))
            .toList()
          ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
        setState(() => _myDecks = decks);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No pude cargar tus mazos: ${e.message ?? e.code}')),
        );
      }
    }
  }

  Future<void> _loadOpponentDecks(String opponentUid) async {
    try {
      final qs = await FirebaseFirestore.instance
          .collection('users').doc(opponentUid)
          .collection('decks')
          .orderBy('name')
          .get();
      setState(() {
        _opponentDecks = qs.docs
            .map((d) => _DeckLite(id: d.id, name: (d.data()['name'] ?? 'Mazo').toString()))
            .toList();
      });
    } on FirebaseException catch (e) {
      if (e.code == 'failed-precondition') {
        final qs = await FirebaseFirestore.instance
            .collection('users').doc(opponentUid)
            .collection('decks')
            .get();
        final decks = qs.docs
            .map((d) => _DeckLite(id: d.id, name: (d.data()['name'] ?? 'Mazo').toString()))
            .toList()
          ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
        setState(() => _opponentDecks = decks);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No pude cargar mazos del rival: ${e.message ?? e.code}')),
        );
      }
    }
  }

  // ===== Resultados (para jugar “local” en el momento) =====
  int get _winsA => _results.where((r) => r == 'A').length;
  int get _winsB => _results.where((r) => r == 'B').length;
  String? get _winnerSide {
    if (_winsA >= 2) return 'A';
    if (_winsB >= 2) return 'B';
    return null;
  }

  bool get _canSaveLocal {
    return _playerA != null &&
        _playerB != null &&
        _deckA != null &&
        _deckB != null &&
        _winnerSide != null;
  }

  void _setGameResult(int index, String side) {
    if (_winnerSide != null) return;
    setState(() {
      _results[index] = side; // "A" o "B"
      final w = _winnerSide;
      if (w != null) {
        for (int i = 0; i < 3; i++) {
          if (_results[i] == null) _results[i] = '';
        }
      }
    });
  }

  Future<void> _updateUserStats(String winnerUid, String loserUid) async {
    final db = FirebaseFirestore.instance;
    final batch = db.batch();

    final winnerRef = db.collection('users').doc(winnerUid);
    final loserRef  = db.collection('users').doc(loserUid);

    batch.set(winnerRef, {
      'matchesPlayed': FieldValue.increment(1),
      'wins': FieldValue.increment(1),
    }, SetOptions(merge: true));

    batch.set(loserRef, {
      'matchesPlayed': FieldValue.increment(1),
      'losses': FieldValue.increment(1),
    }, SetOptions(merge: true));

    await batch.commit();
  }

  Future<void> _saveLocalMatch() async {
    if (!_canSaveLocal) return;
    setState(() => _isSaving = true);
    try {
      final now = DateTime.now();
      final winnerUid = _winnerSide == 'A' ? _playerA! : _playerB!;
      final loserUid  = _winnerSide == 'A' ? _playerB! : _playerA!;

      // 1) Guardar match
      await FirebaseFirestore.instance.collection('matches').add({
        'playerA': _playerA,
        'playerB': _playerB,
        'deckA': _deckA,
        'deckB': _deckB,
        'playerAName': _playerAName,
        'playerBName': _playerBName,
        'deckAName': _deckAName,
        'deckBName': _deckBName,
        'results': _results.map((e) => e ?? '').toList(),
        'winner': winnerUid,
        'aWins': _winsA,
        'bWins': _winsB,
        'date': Timestamp.fromDate(now),
        'createdBy': _myUid,
        'mode': 'local',
        'status': 'finished',
        'bestOf': 3,
        'players': [_playerA, _playerB],
      });

      // 2) Stats de mazos
      await applyDeckStatsOnMatch(
        deckAId: _deckA!,
        deckBId: _deckB!,
        aWins: _winsA,
        bWins: _winsB,
        winnerUid: winnerUid, // si no lo usas, puedes quitarlo de la firma
      );

      // 3) Stats de usuarios
      await _updateUserStats(winnerUid, loserUid);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Match guardado')),
        );
        setState(() {
          _results.setAll(0, [null, null, null]);
          _playerB = null;
          _deckA = _deckB = null;
          _playerBName = null;
          _deckAName = _deckBName = null;
          _opponentDecks = [];
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al guardar: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  // ===== Desafíos (match_invites) =====
  Future<void> _sendChallenge() async {
    if (_challengeOpponentUid == null || _myDeckForChallenge == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecciona amigo y tu mazo')),
      );
      return;
    }

    // Evita duplicados pendientes
    final existing = await FirebaseFirestore.instance
        .collection('match_invites')
        .where('fromUid', isEqualTo: _myUid)
        .where('toUid', isEqualTo: _challengeOpponentUid)
        .where('status', isEqualTo: 'pending')
        .limit(1)
        .get();

    if (existing.docs.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ya tienes un desafío pendiente con este amigo')),
      );
      return;
    }

    await FirebaseFirestore.instance.collection('match_invites').add({
      'fromUid': _myUid,
      'fromName': _myName,
      'toUid': _challengeOpponentUid,
      'toName': _challengeOpponentName,
      'fromDeckId': _myDeckForChallenge,
      'fromDeckName': _myDeckForChallengeName,
      'status': 'pending', // pending | accepted | rejected | canceled
      'createdAt': FieldValue.serverTimestamp(),
      'fromDeckOwnerId': _myUid,
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Desafío enviado')),
      );
    }
  }

  Future<void> _acceptChallenge(
    DocumentReference<Map<String, dynamic>> inviteRef,
    String fromUid,
    String fromName,
    String fromDeckId,
    String fromDeckName,
  ) async {
    // 1) Elijo mi mazo
    final picked = await showDialog<_DeckLite>(
      context: context,
      builder: (_) => _PickDeckDialog(myDecks: _myDecks),
    );
    if (picked == null) return;

    // 2) Leer invite para owner de A (si existe)
    String deckAOwnerId = fromUid;
    try {
      final inviteSnap = await inviteRef.get();
      final inv = inviteSnap.data();
      if (inv != null) {
        final maybeOwner = (inv['fromDeckOwnerId'] ?? '') as String;
        if (maybeOwner.isNotEmpty) deckAOwnerId = maybeOwner;
      }
    } catch (_) {}

    // 3) Dueño de mi mazo
    final deckBOwnerId = _myUid;

    // 4) Crear match y borrar invite
    final batch = FirebaseFirestore.instance.batch();
    final matchRef = FirebaseFirestore.instance.collection('matches').doc();

    batch.set(matchRef, {
      'playerA': fromUid,
      'playerB': _myUid,

      // IDs de mazo
      'deckA': fromDeckId,
      'deckB': picked.id,

      // dueños de los mazos
      'deckAOwnerId': deckAOwnerId,
      'deckBOwnerId': deckBOwnerId,

      // denormalizados para UI
      'playerAName': fromName,
      'playerBName': _myName,
      'deckAName': fromDeckName,
      'deckBName': picked.name,

      // serie
      'results': ['', '', ''],
      'winner': null,
      'aWins': 0,
      'bWins': 0,
      'bestOf': 3,

      'mode': 'challenge',
      'status': 'ongoing',
      'createdBy': fromUid,
      'date': FieldValue.serverTimestamp(),

      // 🔔 clave para que el rival (A) detecte y vaya a MatchDetails
      'acceptedBy': _myUid,                   // 👈 quién aceptó (B)
      'acceptedAt': FieldValue.serverTimestamp(),

      // útil para filtros
      'players': [fromUid, _myUid],
    });

    batch.delete(inviteRef);
    await batch.commit();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Desafío aceptado. Match creado')),
    );

    // 5) B va a MatchDetails (A se queda, pero su listener lo llevará)
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => MatchDetailsScreen(matchId: matchRef.id)),
    );
  }

  Future<void> _rejectChallenge(DocumentReference<Map<String, dynamic>> inviteRef) async {
    await inviteRef.update({
      'status': 'rejected',
      'respondedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> applyDeckStatsOnMatch({
    required String deckAId,
    required String deckBId,
    required int aWins,
    required int bWins,
    required String winnerUid,
  }) async {
    final db = FirebaseFirestore.instance;

    final bool aWon = aWins > bWins;

    Map<String, dynamic> incFor({
      required bool isWinner,
      required int myWins,
      required int oppWins,
    }) {
      final map = <String, dynamic>{
        'games': FieldValue.increment(1),
        'lastMatchAt': FieldValue.serverTimestamp(),
      };
      if (isWinner) {
        map['wins'] = FieldValue.increment(1);
        if (myWins == 2 && oppWins == 0) {
          map['winsBy20'] = FieldValue.increment(1);
        } else {
          map['winsBy21'] = FieldValue.increment(1);
        }
      } else {
        map['losses'] = FieldValue.increment(1);
        if (oppWins == 2 && myWins == 0) {
          map['lossesBy02'] = FieldValue.increment(1);
        } else {
          map['lossesBy12'] = FieldValue.increment(1);
        }
      }
      return map;
    }

    final aUpdate = incFor(isWinner: aWon, myWins: aWins, oppWins: bWins);
    final bUpdate = incFor(isWinner: !aWon, myWins: bWins, oppWins: aWins);

    final batch = db.batch();
    batch.set(db.collection('decks').doc(deckAId), aUpdate, SetOptions(merge: true));
    batch.set(db.collection('decks').doc(deckBId), bUpdate, SetOptions(merge: true));
    await batch.commit();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Partidas (Best of 3)')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ===== Sección: Desafiar amigo =====
            Text('Desafiar amigo', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Card(
              elevation: 1,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    // Amigo
                    DropdownButtonFormField<String>(
                      value: _challengeOpponentUid,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Amigo'),
                      items: _friends
                          .map((f) => DropdownMenuItem(
                                value: f.uid,
                                child: Text('${f.name}${f.username.isNotEmpty ? ' (${f.username})' : ''}'),
                              ))
                          .toList(),
                      onChanged: (v) async {
                        final sel = _friends.firstWhere((e) => e.uid == v);
                        setState(() {
                          _challengeOpponentUid = v;
                          _challengeOpponentName = sel.name;
                        });
                        await _loadOpponentDecks(sel.uid);
                      },
                    ),
                    const SizedBox(height: 12),
                    // Mi mazo para el desafío
                    DropdownButtonFormField<String>(
                      value: _myDeckForChallenge,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Mi mazo'),
                      items: _myDecks.map((d) => DropdownMenuItem(value: d.id, child: Text(d.name))).toList(),
                      onChanged: (v) {
                        final d = _myDecks.firstWhere((e) => e.id == v);
                        setState(() {
                          _myDeckForChallenge = v;
                          _myDeckForChallengeName = d.name;
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: _sendChallenge,
                      icon: const Icon(
                        Symbols.swords,
                        fill: 1,
                        weight: 700,
                        grade: 0,
                        opticalSize: 48,
                      ),
                      label: const Text('Enviar desafío'),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),
            // ===== Desafíos entrantes =====
            Text('Desafíos recibidos', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            _IncomingChallengesList(
              myUid: _myUid,
              onAccept: _acceptChallenge,
              onReject: _rejectChallenge,
            ),

            const SizedBox(height: 16),
            // ===== Desafíos enviados =====
            Text('Desafíos enviados', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            _OutgoingChallengesList(myUid: _myUid),

            const SizedBox(height: 24),
            const Divider(),

            // ===== (Opcional) Jugar ahora local (sin desafío) =====
            const SizedBox(height: 8),
            Text('Jugar ahora (local)', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: _playerDeckCard(side: 'A', cs: cs, fixedToMe: true)),
                const SizedBox(width: 12),
                Expanded(child: _playerDeckCard(side: 'B', cs: cs, friendsOnly: true)),
              ],
            ),
            const SizedBox(height: 16),
            _gamesCard(cs),
            const SizedBox(height: 12),

            FilledButton.icon(
              onPressed: _isSaving || !_canSaveLocal ? null : _saveLocalMatch,
              icon: _isSaving
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.save),
              label: const Text('Guardar Match'),
            ),

            const SizedBox(height: 24),
            const Divider(height: 32),
            const Text('Historial reciente', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            _historyList(),
          ],
        ),
      ),
    );
  }

  // ===== UI helpers =====

  Widget _playerDeckCard({
    required String side,
    required ColorScheme cs,
    bool fixedToMe = false,
    bool friendsOnly = false,
  }) {
    final isA = side == 'A';
    final playerId = isA ? _playerA : _playerB;
    final deckId = isA ? _deckA : _deckB;

    final friendItems = _friends
        .map((f) => DropdownMenuItem<String>(
              value: f.uid,
              child: Text('${f.name}${f.username.isNotEmpty ? ' (${f.username})' : ''}'),
            ))
        .toList();

    final myUserItem = DropdownMenuItem<String>(value: _myUid, child: Text(_myName));

    return Card(
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: isA ? cs.primaryContainer : cs.secondaryContainer,
                  child: Text(isA ? 'A' : 'B'),
                ),
                const SizedBox(width: 8),
                Text(isA ? 'Jugador A' : 'Jugador B', style: const TextStyle(fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: 12),

            // Jugador
            DropdownButtonFormField<String>(
              value: playerId ?? (isA ? _myUid : null),
              decoration: const InputDecoration(labelText: 'Jugador'),
              items: [
                if (isA) myUserItem,
                if (!isA || !fixedToMe) ...friendItems,
              ],
              onChanged: (v) async {
                if (isA && fixedToMe) return;
                setState(() {
                  if (isA) {
                    _playerA = v;
                    _playerAName = v == _myUid
                        ? _myName
                        : _friends.firstWhere((e) => e.uid == v).name;
                  } else {
                    _playerB = v;
                    _playerBName = _friends.firstWhere((e) => e.uid == v).name;
                  }
                });
                if (!isA && v != null) {
                  await _loadOpponentDecks(v);
                }
              },
            ),

            const SizedBox(height: 12),
            // Mazo
            DropdownButtonFormField<String>(
              value: deckId,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Mazo'),
              items: (isA ? _myDecks : _opponentDecks)
                  .map((d) => DropdownMenuItem<String>(value: d.id, child: Text(d.name)))
                  .toList(),
              onChanged: (v) {
                setState(() {
                  if (isA) {
                    _deckA = v;
                    _deckAName = _myDecks.firstWhere((e) => e.id == v).name;
                  } else {
                    _deckB = v;
                    _deckBName = _opponentDecks.firstWhere((e) => e.id == v).name;
                  }
                });
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _gamesCard(ColorScheme cs) {
    final winner = _winnerSide;

    Widget gameRow(int i) {
      final decided = winner != null || (_results[i] != null && _results[i]!.isNotEmpty);
      final aSelected = _results[i] == 'A';
      final bSelected = _results[i] == 'B';
      return ListTile(
        title: Text('Juego ${i + 1}'),
        trailing: Wrap(
          spacing: 8,
          children: [
            ChoiceChip(label: const Text('Gana A'), selected: aSelected, onSelected: decided ? null : (_) => _setGameResult(i, 'A')),
            ChoiceChip(label: const Text('Gana B'), selected: bSelected, onSelected: decided ? null : (_) => _setGameResult(i, 'B')),
          ],
        ),
      );
    }

    return Card(
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.sports_esports),
                const SizedBox(width: 8),
                const Text('Resultados', style: TextStyle(fontWeight: FontWeight.w600)),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(color: cs.surfaceVariant, borderRadius: BorderRadius.circular(99)),
                  child: Text('A ${_winsA} - ${_winsB} B'),
                ),
              ],
            ),
            const Divider(),
            gameRow(0),
            gameRow(1),
            if (_winsA < 2 && _winsB < 2) gameRow(2),
            if (winner != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: winner == 'A' ? cs.primaryContainer : cs.secondaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.emoji_events, color: cs.onPrimaryContainer),
                      const SizedBox(width: 8),
                      Text(
                        winner == 'A' ? 'Ganador: Jugador A' : 'Ganador: Jugador B',
                        style: TextStyle(fontWeight: FontWeight.w600, color: cs.onPrimaryContainer),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _historyList() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('matches')
          .orderBy('date', descending: true)
          .limit(25)
          .snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: Padding(padding: EdgeInsets.all(16.0), child: CircularProgressIndicator()));
        }
        final docs = snap.data?.docs ?? [];
        if (docs.isEmpty) {
          return const Padding(padding: EdgeInsets.all(8.0), child: Text('Sin partidas aún'));
        }
        return ListView.separated(
          physics: const NeverScrollableScrollPhysics(),
          shrinkWrap: true,
          itemCount: docs.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (_, i) {
            final d = docs[i].data();
            final aName = (d['playerAName'] ?? 'A') as String;
            final bName = (d['playerBName'] ?? 'B') as String;
            final deckAName = (d['deckAName'] ?? '') as String;
            final deckBName = (d['deckBName'] ?? '') as String;
            final aWins = (d['aWins'] ?? 0) as int;
            final bWins = (d['bWins'] ?? 0) as int;
            final ts = d['date'];
            DateTime? date;
            if (ts is Timestamp) date = ts.toDate();

            return ListTile(
              leading: CircleAvatar(child: Text('$aWins-$bWins')),
              title: Text('$aName ($deckAName) vs $bName ($deckBName)'),
              subtitle: Text(date != null ? _relative(date) : ''),
              trailing: Icon(Icons.emoji_events, color: aWins > bWins ? Colors.orange : Colors.blueGrey),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => MatchDetailsScreen(matchId: docs[i].id),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  String _relative(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);
    if (diff.inMinutes < 1) return 'ahora';
    if (diff.inMinutes < 60) return 'hace ${diff.inMinutes} min';
    if (diff.inHours < 24) return 'hace ${diff.inHours} h';
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  }
}

// ===== Widgets de desafíos =====

class _IncomingChallengesList extends StatelessWidget {
  final String myUid;
  final Future<void> Function(
    DocumentReference<Map<String, dynamic>> inviteRef,
    String fromUid,
    String fromName,
    String fromDeckId,
    String fromDeckName,
  ) onAccept;
  final Future<void> Function(DocumentReference<Map<String, dynamic>> inviteRef) onReject;

  const _IncomingChallengesList({
    required this.myUid,
    required this.onAccept,
    required this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('match_invites')
          .where('toUid', isEqualTo: myUid)
          .where('status', isEqualTo: 'pending')
          .snapshots(),
      builder: (context, snap) {
        if (snap.hasError) return Text('Error: ${snap.error}');
        final docs = snap.data?.docs ?? [];
        if (docs.isEmpty) return const Text('No tienes desafíos pendientes');

        docs.sort((a, b) {
          final ta = a.data()['createdAt'];
          final tb = b.data()['createdAt'];
          final da = (ta is Timestamp) ? ta.toDate() : DateTime.fromMillisecondsSinceEpoch(0);
          final db = (tb is Timestamp) ? tb.toDate() : DateTime.fromMillisecondsSinceEpoch(0);
          return db.compareTo(da);
        });

        return Column(
          children: docs.map((doc) {
            final d = doc.data();
            final fromName = (d['fromName'] ?? 'Jugador').toString();
            final fromUid = (d['fromUid'] ?? '').toString();
            final fromDeckId = (d['fromDeckId'] ?? '').toString();
            final fromDeckName = (d['fromDeckName'] ?? '').toString();

            return Card(
              child: ListTile(
                leading: const CircleAvatar(child: Icon(Icons.notifications_active)),
                title: Text('$fromName te desafía'),
                subtitle: Text('Mazo: $fromDeckName'),
                trailing: Wrap(
                  spacing: 8,
                  children: [
                    OutlinedButton(onPressed: () => onReject(doc.reference), child: const Text('Rechazar')),
                    FilledButton(onPressed: () => onAccept(doc.reference, fromUid, fromName, fromDeckId, fromDeckName), child: const Text('Aceptar')),
                  ],
                ),
              ),
            );
          }).toList(),
        );
      },
    );
  }
}

class _OutgoingChallengesList extends StatelessWidget {
  final String myUid;
  const _OutgoingChallengesList({required this.myUid});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('match_invites')
          .where('fromUid', isEqualTo: myUid)
          .snapshots(),
      builder: (context, snap) {
        if (snap.hasError) return Text('Error: ${snap.error}');
        final docs = snap.data?.docs ?? [];
        if (docs.isEmpty) return const Text('No has enviado desafíos');

        docs.sort((a, b) {
          final ta = a.data()['createdAt'];
          final tb = b.data()['createdAt'];
          final da = (ta is Timestamp) ? ta.toDate() : DateTime.fromMillisecondsSinceEpoch(0);
          final db = (tb is Timestamp) ? tb.toDate() : DateTime.fromMillisecondsSinceEpoch(0);
          return db.compareTo(da);
        });

        return Column(
          children: docs.map((doc) {
            final d = doc.data();
            final toName = (d['toName'] ?? 'Jugador').toString();
            final deckName = (d['fromDeckName'] ?? '').toString();
            final status = (d['status'] ?? 'pending').toString();

            return Card(
              child: ListTile(
                leading: const CircleAvatar(child: Icon(Icons.outbond)),
                title: Text('A: $toName'),
                subtitle: Text('Mazo: $deckName\nEstado: $status'),
                isThreeLine: true,
              ),
            );
          }).toList(),
        );
      },
    );
  }
}

// ===== Diálogo para elegir mazo propio al aceptar =====
class _PickDeckDialog extends StatelessWidget {
  final List<_DeckLite> myDecks;
  const _PickDeckDialog({required this.myDecks});

  @override
  Widget build(BuildContext context) {
    String? deckId;
    return AlertDialog(
      title: const Text('Elige tu mazo'),
      content: StatefulBuilder(
        builder: (context, setSt) => DropdownButtonFormField<String>(
          decoration: const InputDecoration(labelText: 'Mazo'),
          isExpanded: true,
          items: myDecks.map((d) => DropdownMenuItem(value: d.id, child: Text(d.name))).toList(),
          onChanged: (v) => setSt(() => deckId = v),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(
          onPressed: () {
            if (deckId == null) return;
            final picked = myDecks.firstWhere((e) => e.id == deckId);
            Navigator.pop(context, picked);
          },
          child: const Text('Aceptar'),
        ),
      ],
    );
  }
}

// ===== Modelitos simples =====
class _FriendLite {
  final String uid;
  final String name;
  final String username;
  _FriendLite({required this.uid, required this.name, required this.username});
}

class _DeckLite {
  final String id;
  final String name;
  _DeckLite({required this.id, required this.name});
}

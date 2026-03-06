// lib/screens/tournament_detail_screen.dart
import 'dart:math';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import './models.dart';
import './widgets.dart';
import '../../models/deck.dart';
import '../../utils/deck_poster.dart';
import 'tournament_stats.dart';



class TournamentDetailScreen extends StatefulWidget {
  final String tournamentId;
  const TournamentDetailScreen({super.key, required this.tournamentId});

  @override
  State<TournamentDetailScreen> createState() => _TournamentDetailScreenState();
}

class _TournamentDetailScreenState extends State<TournamentDetailScreen>
    with TickerProviderStateMixin {
  bool _loading = true;
  Map<String, dynamic>? _tournament;
  final Random _rnd = Random();
  String? _adminOwnerUid;
  final String _adminEmailForBots = 'hecturnicolas@gmail.com';
  List<Player> players = [];
  final Map<String, PlayerStats> _stats = {};
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _tournamentSub;
    final Map<String, Map<String, dynamic>> _reportedResults = {};
  final Set<String> _appliedReportedResults = {}; // keys ya aplicadas a stats

  // swiss control
  int _swissRounds = 0;
  int _currentSwissRound = 0;
  List<Pair> _pairsThisRound = [];
  // índice de pestaña actualmente seleccionada (para pintar la tab activa)
  int _currentTabIndex = 0;

  // visible swiss rounds in UI (se van habilitando a medida que se definen)
  int _visibleSwissRounds = 1;

  // Guarda resultados suizos por ronda (para mostrar por pestaña)
  final Map<int, List<MatchResult>> _swissResultsByRound = {};

  // elimination control
  List<List<Pair>> _elimRounds = []; // rounds for elimination (pairs)
// starts at 1 when elimination begins
  final Map<String, MatchResult> _elimResults = {}; // key: 'r{round}_m{index}'

  // temporary buffer for winners during elimination
  List<Player> _elimNextRoundWinners = [];

  // log
  final List<String> _log = [];

  // guarda todos los resultados match a match (Swiss + eliminación)
  final List<MatchResult> _allMatchResults = [];

  // phase: 'waiting' | 'swiss' | 'elimination' | 'finished'

  // TabController para mostrar pestañas de rondas (recreado cuando cambian rondas/eliminación)
  TabController? _tabController;

  final svc = TournamentStatsService();


  @override
  void initState() {
    super.initState();
    _loadAndPrepare();
    _startTournamentListener();
  }

    /// Reconstruye _stats a partir de _allMatchResults (evita duplicados y
  /// asegura consistencia después de confirmar reportes o terminar una ronda).
  void _recomputeStatsFromAllResults() {
    // reset stats (mantener jugadores existentes)
    for (final s in _stats.values) s.reset();

    // rebuild from history
    for (final m in _allMatchResults) {
      try {
        final a = m.a;
        final b = m.b;

        // ensure keys exist
        _stats.putIfAbsent(a.id, () => PlayerStats(player: a));
        if (b != null) _stats.putIfAbsent(b.id, () => PlayerStats(player: b));

        // matches played
        _stats[a.id]!.matchesPlayed += 1;
        if (b != null) _stats[b.id]!.matchesPlayed += 1;

        // winner / matchesWon / matchesLost / points
        if (m.winnerId == a.id) {
          _stats[a.id]!.matchesWon += 1;
          if (b != null) _stats[b.id]!.matchesLost += 1;
          _stats[a.id]!.points += 3;
        } else if (b != null && m.winnerId == b.id) {
          _stats[b.id]!.matchesWon += 1;
          _stats[a.id]!.matchesLost += 1;
          _stats[b.id]!.points += 3;
        }

        // games
        _stats[a.id]!.gamesWon += (m.scoreA);
        _stats[a.id]!.gamesLost += (m.scoreB);
        if (b != null) {
          _stats[b.id]!.gamesWon += (m.scoreB);
          _stats[b.id]!.gamesLost += (m.scoreA);
        }
      } catch (e) {
        debugPrint('recomputeStatsFromAllResults: error procesando match: $e');
      }
    }
  }

  /// Calcula agregados por raza (summary y matriz de victorias entre razas)
    /// Calcula agregados por raza (summary y matriz de victorias entre razas)
  void _computeRaceAggregates() {
    final byRace = <String, Map<String, int>>{}; // race -> {players, matchesPlayed, matchesWon, gamesWon, gamesLost}
    final winsMatrix = <String, Map<String, int>>{}; // attRace -> {defRace: wins}

    // init races and base counters
    for (final p in players) {
      byRace.putIfAbsent(p.race, () => {
        'players': 0,
        'matchesPlayed': 0,
        'matchesWon': 0,
        'gamesWon': 0,
        'gamesLost': 0,
      });
      byRace[p.race]!['players'] = (byRace[p.race]!['players'] ?? 0) + 1;
      winsMatrix.putIfAbsent(p.race, () => {});
    }

    // accumulate from _stats (que debería estar ya recomputeado)
    for (final p in players) {
      final s = _stats[p.id];
      if (s == null) continue;
      final race = p.race;
      byRace[race]!['matchesPlayed'] = (byRace[race]!['matchesPlayed'] ?? 0) + s.matchesPlayed;
      byRace[race]!['matchesWon'] = (byRace[race]!['matchesWon'] ?? 0) + s.matchesWon;
      byRace[race]!['gamesWon'] = (byRace[race]!['gamesWon'] ?? 0) + s.gamesWon;
      byRace[race]!['gamesLost'] = (byRace[race]!['gamesLost'] ?? 0) + s.gamesLost;
    }

    // wins matrix: recorrer allMatchResults y contabilizar winner race vs loser race
    for (final m in _allMatchResults) {
      // ignorar byes o matches sin oponente
      if (m.b == null) continue;

      // aquí ya sabemos que m.b != null, por eso podemos usar ! para obtener tipos no-null
      final Player winner = (m.winnerId == m.a.id) ? m.a : m.b!;
      final Player loser = (winner.id == m.a.id) ? m.b! : m.a;

      final wr = winner.race;
      final lr = loser.race;

      winsMatrix.putIfAbsent(wr, () => {});
      winsMatrix[wr]![lr] = (winsMatrix[wr]![lr] ?? 0) + 1;
    }

  }



void _startTournamentListener() {
  final ref = FirebaseFirestore.instance
      .collection('tournaments')
      .doc(widget.tournamentId)
      .withConverter<Map<String, dynamic>>(
        fromFirestore: (snap, _) => snap.data() ?? <String, dynamic>{},
        toFirestore: (m, _) => m,
      );

  // cancelar si ya existía
  _tournamentSub?.cancel();
  _tournamentSub = ref.snapshots().listen((snap) async {
    final data = snap.data();
    if (data == null) return;

    // asignamos el doc localmente (no hacemos setState todavía)
    _tournament = data;

    try {
      // preparar participantes (enriquecimiento puede hacer fetchs)
      var participants = (data['participants'] as List<dynamic>?) ?? <dynamic>[];
      final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
      participants = await _enrichParticipantsWithDecks(participants);

      // esto inicializa players / _stats / control — _preparePlayersFromParticipants puede hacer setState internamente
      _preparePlayersFromParticipants(participants, uid, []);

      // --- sincronizar reportedResults (si existen) ---
      final rr = (data['reportedResults'] as Map<String, dynamic>?) ?? <String, dynamic>{};
      _reportedResults.clear();
      rr.forEach((k, v) {
        try {
          _reportedResults[k] = Map<String, dynamic>.from(v as Map);
        } catch (_) {
          // ignorar entradas mal formadas
        }
      });

      // Aplicar automáticamente reportes confirmados a stats (solo una vez)
      for (final entry in _reportedResults.entries) {
        final key = entry.key;
        final map = entry.value;
        if (map['confirmed'] == true && !_appliedReportedResults.contains(key)) {
          _applyReportedResultToStats(key, map);
          _appliedReportedResults.add(key);
        }
      }

      // finalmente refrescar UI (si _preparePlayers... ya llamó setState, esto no hace daño)
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('Tournament listener error: $e');
      if (mounted) setState(() {});
    }
  }, onError: (err) {
    debugPrint('Tournament listener stream error: $err');
  });
}


  @override
  void dispose() {
    _tournamentSub?.cancel();
    _tabController?.removeListener(_handleTabChange);
    _tabController?.dispose();
    super.dispose();
  }

  Future<void> _persistReportedResultToFirestore(String matchKey, Map<String, dynamic> value) async {
  final docRef = FirebaseFirestore.instance.collection('tournaments').doc(widget.tournamentId);
  try {
    // Intentamos actualizar sólo la clave dentro del mapa reportedResults
    await docRef.update({'reportedResults.$matchKey': value});
  } catch (e) {
    // Si el doc no existe o la update falla, usamos set con merge
    await docRef.set({'reportedResults': {matchKey: value}}, SetOptions(merge: true));
  }
}

Future<void> _showTournamentStats() async {
  // muestra un diálogo de carga mientras se generan las estadísticas
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => const Dialog(
      child: Padding(
        padding: EdgeInsets.all(16.0),
        child: SizedBox(
          height: 72,
          child: Center(child: CircularProgressIndicator()),
        ),
      ),
    ),
  );

  try {
    final svc = TournamentStatsService();
    final stats = await svc.generateTournamentStats(
      players: players,
      allMatchResults: _allMatchResults,
      loadDeckDocForPlayer: _loadDeckDocForPlayer,
    );

    // cerrar diálogo de carga
    if (mounted) Navigator.of(context).pop();

    // mostrar el diálogo con los resultados (usa la función provista en tournament_stats.dart)
    if (mounted) await showTournamentStatsDialog(context, stats);
  } catch (e) {
    // cerrar diálogo de carga si sigue abierto
    if (mounted) Navigator.of(context).pop();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error generando estadísticas: $e')),
      );
    }
  }
}

Future<String?> _resolveAdminOwnerUid() async {
  if (_adminOwnerUid != null) return _adminOwnerUid;
  try {
    final q = await FirebaseFirestore.instance
        .collection('users')
        .where('email', isEqualTo: _adminEmailForBots)
        .limit(1)
        .get();
    if (q.docs.isNotEmpty) {
      _adminOwnerUid = q.docs.first.id;
      return _adminOwnerUid;
    }
  } catch (_) {
    // ignore errors, devolver null si falla
  }
  return null;
}

Future<List<dynamic>> _enrichParticipantsWithDecks(
    List<dynamic> participants,
  ) async {
    final List<dynamic> out = [];
    for (final p in participants) {
      if (p is Map) {
        final Map<String, dynamic> mp = Map<String, dynamic>.from(p);
        if (mp['deckBrief'] == null) {
          // 1) try deckPath
          final dp = mp['deckPath'];
          bool filled = false;
          if (dp is String && dp.isNotEmpty) {
            try {
              final doc = await FirebaseFirestore.instance.doc(dp).get();
              if (doc.exists && doc.data() != null) {
                final d = doc.data() as Map<String, dynamic>;
                mp['deckBrief'] = {
                  'race': d['race'] ?? d['faction'] ?? 'unknown',
                  'edition': d['edition'] ?? d['edicion'],
                  'archetype': d['archetype'] ?? d['type'],
                  'totalCards': _calcTotalCardsFromDocData(d),
                  'deckPath': doc.reference.path,
                  'name': d['name'] ?? mp['deckName'] ?? null,
                };
                filled = true;
              }
            } catch (_) {}
          }

          // 2) try users/{uid}/decks/{deckId}
          if (!filled) {
            final ownerUid = (mp['uid'] ?? mp['user'] ?? '').toString();
            final deckId = (mp['deckId'] ?? '').toString();
            if (ownerUid.isNotEmpty && deckId.isNotEmpty) {
              try {
                final doc = await FirebaseFirestore.instance
                    .collection('users')
                    .doc(ownerUid)
                    .collection('decks')
                    .doc(deckId)
                    .get();
                if (doc.exists && doc.data() != null) {
                  final d = doc.data() as Map<String, dynamic>;
                  mp['deckBrief'] = {
                    'race': d['race'] ?? d['faction'] ?? 'unknown',
                    'edition': d['edition'] ?? d['edicion'],
                    'archetype': d['archetype'] ?? d['type'],
                    'totalCards': _calcTotalCardsFromDocData(d),
                    'deckPath': doc.reference.path,
                    'name': d['name'] ?? mp['deckName'],
                  };
                  filled = true;
                }
              } catch (_) {}
            }
          }

          // 3) fallback: si no pudimos, intentar inferir race/name desde el mapa 'p' original
          if (!filled) {
            mp['deckBrief'] = {
              'race': mp['race'] ?? mp['faction'] ?? 'Unknown',
              'edition': mp['edition'] ?? mp['edicion'],
              'archetype': mp['archetype'] ?? mp['type'],
              'totalCards': mp['totalCards'] ?? null,
              'deckPath': mp['deckPath'],
              'name': mp['deckName'] ?? mp['name'] ?? null,
            };
          }
        }
        out.add(mp);
      } else {
        out.add(p); // no-map entries preserved
      }
    }
    return out;
  }

  /// Calcula total de cartas a partir del doc de mazo (si tiene 'cards' array)
  int _calcTotalCardsFromDocData(Map<String, dynamic> d) {
    final cards = (d['cards'] as List<dynamic>?) ?? [];
    int total = 0;
    for (final c in cards) {
      try {
        if (c is Map) {
          final maybe =
              c['count'] ?? c['cantidad'] ?? c['qty'] ?? c['quantity'] ?? 0;
          final v = (maybe is int) ? maybe : int.tryParse('$maybe') ?? 0;
          total += v;
        }
      } catch (_) {}
    }
    return total;
  }

  Future<void> _loadAndPrepare() async {
    setState(() => _loading = true);
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      setState(() {
        _tournament = null;
        _loading = false;
      });
      return;
    }

    try {
      final doc = await FirebaseFirestore.instance
          .collection('tournaments')
          .doc(widget.tournamentId)
          .get();
      final data = doc.data();
      if (data == null) throw 'Torneo no encontrado';
      setState(() => _tournament = data);

      // load participants and user's decks (to pick random deck for current user when needed)
      var participants =
          (data['participants'] as List<dynamic>?) ?? <dynamic>[];
      final userDecksSnap = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('decks')
          .get();
      final userDecks = <Map<String, dynamic>>[];
      for (final d in userDecksSnap.docs) {
        final m = d.data();
        final cards = (m['cards'] as List<dynamic>?) ?? [];
        int total = 0;
        for (final c in cards) {
          try {
            if (c is Map) {
              final maybe =
                  c['count'] ?? c['cantidad'] ?? c['qty'] ?? c['quantity'] ?? 0;
              final v = (maybe is int) ? maybe : int.tryParse('$maybe') ?? 0;
              total += v;
            }
          } catch (_) {}
        }
        if (total >= 40) {
          final copy = Map<String, dynamic>.from(m);
          copy['__id'] = d.id;
          copy['__total'] = total;
          userDecks.add(copy);
        }
      }
      participants = await _enrichParticipantsWithDecks(participants);
      _preparePlayersFromParticipants(participants, uid, userDecks);
    } catch (e) {
      setState(() {
        _tournament = {'error': e.toString()};
      });
    } finally {
      setState(() => _loading = false);
      _recreateTabController();
    }
  }

  /// Construye players y _stats a partir del array `participants` del documento.
  void _preparePlayersFromParticipants(
    List<dynamic> participants,
    String currentUid,
    List<Map<String, dynamic>> userDecks,
  ) {
    players.clear();
    _stats.clear();
    _log.clear();
    _elimRounds.clear();
    _elimResults.clear();
    _elimNextRoundWinners.clear();
    _allMatchResults.clear();
    _swissResultsByRound.clear();

    int syntheticBotCounter = 1;

    for (final p in participants) {
      try {
        if (p is Map) {
          (p['uid'] ?? p['user'] ?? '').toString();
          final name = (p['name'] ?? p['displayName'] ?? '').toString();
          final mp = Map<String, dynamic>.from(p);

          // participant fields (uid/name)
          final participantUid = (mp['uid'] ?? mp['user'] ?? '').toString();

          // preferimos un 'deckBrief' si está presente
          final Map<String, dynamic>? deckBrief = (mp['deckBrief'] is Map)
              ? Map<String, dynamic>.from(mp['deckBrief'])
              : null;

          // extraemos id/nombre/raza priorizando deckBrief
          final deckId =
              (deckBrief?['deckId'] ??
                      mp['deckId'] ??
                      mp['mazoId'] ??
                      mp['deck'] ??
                      '')
                  .toString();
          final deckName =
              (deckBrief?['name'] ??
                      mp['deckName'] ??
                      mp['mazoNombre'] ??
                      mp['deck_name'] ??
                      '')
                  .toString();
          final raceVal =
              (deckBrief?['race'] ??
                      mp['race'] ??
                      mp['faction'] ??
                      mp['raza'] ??
                      'Unknown')
                  .toString();

          // Si no hay mazo y el participante es el usuario actual, elegimos uno aleatorio del usuario
          String finalDeckId = deckId;
          String finalDeckName = deckName;
          String finalRace = raceVal;
          if ((finalDeckId.isEmpty || finalDeckName.isEmpty) &&
              participantUid == currentUid &&
              userDecks.isNotEmpty) {
            final r = userDecks[_rnd.nextInt(userDecks.length)];
            finalDeckId = r['__id'] ?? finalDeckId;
            finalDeckName = r['name'] ?? finalDeckName ?? 'Mazo';
            finalRace = (r['race'] ?? r['faction'] ?? finalRace).toString();
          }

          // id del player local (mantener sintéticos si falta uid)
          final id = participantUid.isNotEmpty
              ? 'p_${participantUid}_${finalDeckId.isNotEmpty ? finalDeckId : syntheticBotCounter}'
              : 'p_${syntheticBotCounter++}';

          players.add(
            Player(
              id: id,
              displayName: name.isNotEmpty
                  ? name
                  : (participantUid == currentUid ? 'Tú' : 'Jugador'),
              ownerUid: participantUid.isNotEmpty ? participantUid : 'guest',
              deckId: finalDeckId.isNotEmpty
                  ? finalDeckId
                  : 'unknown_${syntheticBotCounter}',
              deckName: finalDeckName.isNotEmpty
                  ? finalDeckName
                  : 'Mazo ${syntheticBotCounter}',
              race: finalRace,
            ),
          );
        } else {
          // elemento no-map: fallback synthetic
          final id = 'p_synthetic_${players.length + 1}';
          players.add(
            Player(
              id: id,
              displayName: 'Jugador ${players.length + 1}',
              ownerUid: 'guest',
              deckId: 'unknown',
              deckName: 'Mazo ${players.length + 1}',
              race: 'Unknown',
            ),
          );
        }
      } catch (_) {
        final id = 'p_err_${players.length + 1}';
        players.add(
          Player(
            id: id,
            displayName: 'Jugador ${players.length + 1}',
            ownerUid: 'guest',
            deckId: 'unknown',
            deckName: 'Mazo ${players.length + 1}',
            race: 'Unknown',
          ),
        );
      }
    }

    // init stats
    for (final p in players) {
      _stats[p.id] = PlayerStats(player: p);
    }

    // swiss rounds config
    final explicitRounds = (_tournament?['swissRounds'] as int?);
    final n = players.length;
    final defaultRounds = n <= 1 ? 1 : (log(max(2, n)) / log(2)).ceil();
    _swissRounds = (explicitRounds != null && explicitRounds > 0)
        ? explicitRounds
        : defaultRounds;

    // reset control
    if (players.length >= 2) {
      _currentSwissRound = 1;
      _pairsThisRound = _computePairsForRound();
      // Start UI showing only round 1 (las demás aparecerán cuando se definan)
      _visibleSwissRounds = 1;
    } else {
      _currentSwissRound = 0;
      _pairsThisRound = [];
      _visibleSwissRounds = 1;
    }

    _elimRounds = [];
    _elimNextRoundWinners = [];
    _elimResults.clear();
    _allMatchResults.clear();

    _log.add(
      'Cargados ${players.length} jugadores. Swiss rounds: $_swissRounds\n',
    );
    setState(() {});
    _recreateTabController();
  }

  void _recreateTabController() {
    final prevIndex = _tabController?.index ?? 0;
    _tabController?.removeListener(_handleTabChange);
    _tabController?.dispose();

    // number of tabs = visible swiss rounds + elimination rounds (if any prepared)
    final elimTabs = _elimRounds.isNotEmpty ? _elimRounds.length : 0;
    final swissCount = max(1, _visibleSwissRounds);
    final total = swissCount + elimTabs;

    final initial = (prevIndex < total)
        ? prevIndex
        : (total - 1 >= 0 ? total - 1 : 0);
    _tabController = TabController(
      length: total == 0 ? 1 : total,
      vsync: this,
      initialIndex: initial,
    );
    _tabController!.addListener(_handleTabChange);

    // sync our tracked current index
    _currentTabIndex = _tabController!.index;

    setState(() {});
  }


  void _handleTabChange() {
    if (!mounted) return;
    if (_tabController == null) return;
    if (_currentTabIndex != _tabController!.index) {
      setState(() {
        _currentTabIndex = _tabController!.index;
      });
    }
  }

  // helper para mostrar nombre limpio del mazo (quita sufijos como " (bot 14)")
  String _displayDeckName(String deckName) {
    final idx = deckName.indexOf('(');
    if (idx >= 0) {
      return deckName.substring(0, idx).trim();
    }
    return deckName;
  }

  // standings sort (simple)
  List<Player> _sortedStandings() {
    final list = List<Player>.from(players);
    list.sort((a, b) {
      final sa = _stats[a.id]!;
      final sb = _stats[b.id]!;
      final cmpPoints = sb.points.compareTo(sa.points);
      if (cmpPoints != 0) return cmpPoints;
      final diffA = sa.gamesWon - sa.gamesLost;
      final diffB = sb.gamesWon - sb.gamesLost;
      final cmpGD = diffB.compareTo(diffA);
      if (cmpGD != 0) return cmpGD;
      final cmpWins = sb.matchesWon.compareTo(sa.matchesWon);
      if (cmpWins != 0) return cmpWins;
      return a.deckName.compareTo(b.deckName);
    });
    return list;
  }



  List<Pair> _computePairsForRound() {
    final sorted = _sortedStandings();
    final pairs = <Pair>[];
    for (int i = 0; i < sorted.length; i += 2) {
      final a = sorted[i];
      final b = (i + 1 < sorted.length) ? sorted[i + 1] : null;
      pairs.add(Pair(a, b));
    }
    return pairs;
  }

  // ---------- HELPERS para abrir DeckPoster desde TournamentDetailScreen ----------

  /// Carga el documento de mazo (users/{owner}/decks/{deckId}) y devuelve el Map
  Future<Map<String, dynamic>?> _loadDeckDocForPlayer(Player p) async {
  try {
    String owner = p.ownerUid;
    String deckId = p.deckId;

    debugPrint('[loadDeck] player=${p.displayName} owner="$owner" deckId="$deckId"');

    Map<String, dynamic>? fromSnap(DocumentSnapshot ds) {
      if (!ds.exists) return null;
      final data = Map<String, dynamic>.from(ds.data() as Map<String, dynamic>);
      data['__path'] = ds.reference.path;
      data['__id'] = ds.id;
      final parent = ds.reference.parent.parent;
      if (parent != null) data['ownerId'] = parent.id;
      return data;
    }

    // Normal: owner real (no bot/guest) -> leer users/{owner}/decks/{deckId}
    final ownerLower = owner.toLowerCase();
    final isBotLike = ownerLower.startsWith('bot'); // cubre 'bot', 'bot_', 'Bot'...
    final isGuest = ownerLower == 'guest';

    if (!isBotLike && !isGuest) {
      if (owner.isEmpty || deckId.isEmpty) {
        debugPrint('[loadDeck] owner present but deckId empty -> null');
        return null;
      }
      try {
        final doc = await FirebaseFirestore.instance
            .collection('users')
            .doc(owner)
            .collection('decks')
            .doc(deckId)
            .get();
        final res = fromSnap(doc);
        debugPrint('[loadDeck] direct read ${res != null ? 'OK: ${res['__path']}' : 'NOT FOUND'}');
        if (res != null) return res;
        // If not found, fall through to admin fallback below (useful if owner is malformed)
      } catch (e) {
        debugPrint('[loadDeck] direct read error: $e');
        // fallthrough to fallback logic
      }
    }

    // Si llegamos acá: owner es bot/guest o la lectura directa falló.
    final adminUid = await _resolveAdminOwnerUid();
    if (adminUid == null) {
      debugPrint('[loadDeck] admin user not found by email ($_adminEmailForBots).');
    } else {
      debugPrint('[loadDeck] adminUid resolved: $adminUid');
    }

    // 1) Si deckId parece una ruta completa (users/.../decks/...), intentar leerla
    if (deckId.contains('/') && deckId.trim().isNotEmpty) {
      try {
        final ds = await FirebaseFirestore.instance.doc(deckId).get();
        if (ds.exists && ds.data() != null) {
          final data = Map<String, dynamic>.from(ds.data() as Map<String, dynamic>);
          data['__path'] = ds.reference.path;
          data['__id'] = ds.id;
          final parent = ds.reference.parent.parent;
          if (parent != null) data['ownerId'] = parent.id;
          debugPrint('[loadDeck] read by full path OK: ${data['__path']}');
          return data;
        } else {
          debugPrint('[loadDeck] full path given but not found: $deckId');
        }
      } catch (e) {
        debugPrint('[loadDeck] full path read error: $e');
      }
    }

    // 2) Try collectionGroup where the deck doc contains field 'id' == deckId
    if (deckId.isNotEmpty) {
      try {
        final q = await FirebaseFirestore.instance
            .collectionGroup('decks')
            .where('id', isEqualTo: deckId)
            .limit(1)
            .get();
        if (q.docs.isNotEmpty) {
          final d = q.docs.first;
          final map = Map<String, dynamic>.from(d.data());
          map['__path'] = d.reference.path;
          map['__id'] = d.id;
          final parent = d.reference.parent.parent;
          if (parent != null) map['ownerId'] = parent.id;
          debugPrint('[loadDeck] collectionGroup by id found: ${map['__path']}');
          return map;
        } else {
          debugPrint('[loadDeck] collectionGroup by id returned empty');
        }
      } catch (e) {
        debugPrint('[loadDeck] collectionGroup by id error: $e (this may happen if docs do not have field "id")');
      }
    }

    // 3) Si tenemos adminUid, intentar leer admin decks por id directo
    if (adminUid != null) {
      if (deckId.isNotEmpty) {
        try {
          final adminDoc = await FirebaseFirestore.instance
              .collection('users')
              .doc(adminUid)
              .collection('decks')
              .doc(deckId)
              .get();
          if (adminDoc.exists && adminDoc.data() != null) {
            final map = Map<String, dynamic>.from(adminDoc.data()!);
            map['ownerId'] = adminUid;
            map['__path'] = adminDoc.reference.path;
            map['__id'] = adminDoc.id;
            debugPrint('[loadDeck] found under admin by doc id: ${map['__path']}');
            return map;
          } else {
            debugPrint('[loadDeck] admin direct read by id NOT FOUND');
          }
        } catch (e) {
          debugPrint('[loadDeck] admin direct read error: $e');
        }
      }

      // 4) Último recurso: escanear los decks del admin y buscar coincidencias por id o por campo 'id' o por name
      try {
        final snaps = await FirebaseFirestore.instance
            .collection('users')
            .doc(adminUid)
            .collection('decks')
            .get();
        for (final d in snaps.docs) {
          final map = Map<String, dynamic>.from(d.data());
          final docId = d.id;
          final fieldId = (map['id']?.toString() ?? '').toString();
          final name = (map['name']?.toString() ?? '').toString();
          if (docId == deckId || fieldId == deckId || name == deckId) {
            map['ownerId'] = adminUid;
            map['__path'] = d.reference.path;
            map['__id'] = d.id;
            debugPrint('[loadDeck] admin scan matched: ${map['__path']} (docId=$docId, fieldId=$fieldId, name=$name)');
            return map;
          }
        }
        debugPrint('[loadDeck] admin scan found nothing for $deckId');
      } catch (e) {
        debugPrint('[loadDeck] admin scan error: $e');
      }
    }

    debugPrint('[loadDeck] returning null (no deck found)');
    return null;
  } catch (err) {
    debugPrint('[loadDeck] EXCEPTION: $err');
    return null;
  }
}


  /// Construye dos mapas requeridos por DeckPoster: imgByCardId y officialImgByCardId
  Map<String, String?> _buildImgMapsFromDeckDoc(
    Map<String, dynamic>? deckDoc, {
    String cardFieldImg = 'imageFrontUrl',
  }) {
    final imgById = <String, String?>{};
    if (deckDoc == null) return imgById;

    final cards = (deckDoc['cards'] as List<dynamic>?) ?? [];
    for (final c in cards) {
      if (c is Map) {
        final id = (c['cardId'] ?? c['cardID'] ?? c['id'])?.toString();
        if (id == null || id.isEmpty) continue;
        final maybeImg =
            (c[cardFieldImg] ?? c['image'] ?? c['imageUrl'] ?? c['url'])
                ?.toString();
        if (maybeImg != null && maybeImg.isNotEmpty) imgById[id] = maybeImg;
      }
    }
    return imgById;
  }

  Map<String, String?> _buildOfficialMapFromDeckDoc(
    Map<String, dynamic>? deckDoc,
  ) {
    final officialById = <String, String?>{};
    if (deckDoc == null) return officialById;
    final cards = (deckDoc['cards'] as List<dynamic>?) ?? [];
    for (final c in cards) {
      if (c is Map) {
        final id = (c['cardId'] ?? c['cardID'] ?? c['id'])?.toString();
        if (id == null || id.isEmpty) continue;
        final official =
            (c['officialImageUrl'] ?? c['officialImage'] ?? c['official'])
                ?.toString();
        if (official != null && official.isNotEmpty)
          officialById[id] = official;
      }
    }
    return officialById;
  }

  /// Abre dialog con DeckPoster en modo duelo (si hay mazos).
Future<void> _openDeckPosterDialog(Player a, Player? b, {int? scoreA, int? scoreB}) async {
  // 1) precargar docs de mazos (pueden ser null para bots/guests)
  final docA = await _loadDeckDocForPlayer(a);
  final docB = b != null ? await _loadDeckDocForPlayer(b) : null;

  // 2) crear objetos Deck usando Deck.fromMap (que ya sabe parsear cards)
  //    Si docA/docB son null usamos un map fallback con lo mínimo necesario.
  late final Deck deckA;
  Deck? deckB;

  try {
    final mapA = <String, dynamic>{
      // si docA ya tiene id/ownerId, Deck.fromMap los usará; si no, damos defaults
      'id': docA?['__id'] ?? docA?['id'] ?? '${a.ownerUid}_${a.deckId}',
      'ownerId': docA?['ownerId'] ?? a.ownerUid,
      'name': docA?['name'] ?? a.deckName ?? 'Mazo',
      'edition': docA?['edition'] ?? '',
      'cards': docA?['cards'] ?? [],
      // copiar otros campos si quieres: createdAt/updatedAt/etc.
      ...?docA, // si docA no es null, mezclarlo para aprovechar campos existentes
    };
    deckA = Deck.fromMap(mapA);
  } catch (e) {
    // Como último recurso (no debería ocurrir si Deck.fromMap existe), construir mínimo
    deckA = Deck.fromMap({
      'id': '${a.ownerUid}_${a.deckId}',
      'ownerId': a.ownerUid,
      'name': a.deckName,
      'edition': '',
      'cards': [],
    });
  }

  if (b != null) {
    try {
      final mapB = <String, dynamic>{
        'id': docB?['__id'] ?? docB?['id'] ?? '${b.ownerUid}_${b.deckId}',
        'ownerId': docB?['ownerId'] ?? b.ownerUid,
        'name': docB?['name'] ?? b.deckName ?? 'Mazo',
        'edition': docB?['edition'] ?? '',
        'cards': docB?['cards'] ?? [],
        ...?docB,
      };
      deckB = Deck.fromMap(mapB);
    } catch (_) {
      deckB = Deck.fromMap({
        'id': '${b.ownerUid}_${b.deckId}',
        'ownerId': b.ownerUid,
        'name': b.deckName,
        'edition': '',
        'cards': [],
      });
    }
  }

  // 3) construir mapas de imágenes
  final imgA = _buildImgMapsFromDeckDoc(docA);
  final officialA = _buildOfficialMapFromDeckDoc(docA);
  final imgB = _buildImgMapsFromDeckDoc(docB);
  final officialB = _buildOfficialMapFromDeckDoc(docB);

  // 4) mostrar dialog con DeckPoster. showDuelSwitch permite alternar mostrar 1 o 2 mazos.
  showDialog(
    context: context,
    builder: (_) => Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 24),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Ponemos un título corto, DeckPoster ya incluye los paneles
              Text('${a.displayName}  vs  ${b?.displayName ?? 'bye'}', style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              DeckPoster(
  deck: deckA,
  imgByCardId: imgA,
  officialImgByCardId: officialA,
  opponentDeck: deckB,
  opponentImgByCardId: imgB,
  opponentOfficialImgByCardId: officialB,
  // ocultamos el switch y forzamos duel mode si hay oponente
  showDuelSwitch: false,
  initialDuelMode: deckB != null,
  refreshTick: DateTime.now().millisecondsSinceEpoch.remainder(100000),
),

              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cerrar')),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}


  // returns a MatchResult and updates stats as requested

  // Advance one step (plays next match in current phase)


  // Build elimination bracket from standings (respect the tournament swissQualifiers if set)





  void _showRaceStatsDialog() {
    showRaceStatsDialog(
      context,
      players: players,
      swissResultsByRound: _swissResultsByRound,
      allMatchResults: _allMatchResults,
      stats: _stats,
    );
  }

  // UI builders

  void _showStandingsSheet() {
  // defensivo: si alguna cosa puede ser null, pasar un valor por defecto
  final playersSafe = players; // asume List<Player> no-nulo; si puede ser nulo, haz players ?? <Player>[]
  final swissSafe = _swissResultsByRound;
  final statsSafe = _stats;
  final elimRoundsSafe = _elimRounds;
  final elimResultsSafe = _elimResults;

  // import: asegúrate de tener importado el archivo que contiene showStandingsSheet
  showStandingsSheet(
    context,
    players: playersSafe,
    swissResultsByRound: swissSafe,
    stats: statsSafe,
    elimRounds: elimRoundsSafe,
    elimResults: elimResultsSafe,
  );
}



  Widget _buildBracketViewForElimRound(int roundIdx) {
    if (_elimRounds.isEmpty || roundIdx < 0 || roundIdx >= _elimRounds.length) {
      return const Center(
        child: Text('No hay datos de eliminación para esta ronda.'),
      );
    }
    final pairs = _elimRounds[roundIdx];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: List.generate(pairs.length, (mIdx) {
          final p = pairs[mIdx];
          final key = 'r${roundIdx + 1}_m$mIdx';
          final res = _elimResults[key];
          return Container(
            width: 260,
            margin: const EdgeInsets.symmetric(horizontal: 8),
            child: Card(
              // el Card ahora contiene todo: header compacto + contenido
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // header compacto dentro del Card: Mesa N + ojo integrado dentro de la línea gris
                    Container(
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surfaceVariant,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 6,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.max,
                        children: [
                          Expanded(
                            child: Text(
                              'Mesa ${mIdx + 1}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          IconButton(
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                              minWidth: 32,
                              minHeight: 32,
                            ),
                            icon: Icon(Icons.visibility_outlined, size: 18),
                            color: (res != null)
                                ? Theme.of(context).colorScheme.primary
                                : Colors.grey,
                            tooltip: 'Ver enfrentamiento',
                            onPressed: () => _openDeckPosterDialog(
                              p.a,
                              p.b,
                              scoreA: res?.scoreA,
                              scoreB: res?.scoreB,
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 8),

                    // contenido de la mesa
                    Column(
                      children: [
                        Text(
                          p.a.displayName,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        Text(
                          p.a.race,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.grey,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'vs',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          p.b?.displayName ?? 'bye',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        Text(
                          p.b?.race ?? '-',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.grey,
                          ),
                        ),
                        const SizedBox(height: 8),
                        if (res != null)
                          Text(
                            'Resultado: ${res.scoreA}-${res.scoreB} • Ganador: ${res.winnerId == p.a.id ? _displayDeckName(p.a.deckName) : _displayDeckName(p.b?.deckName ?? '')}',
                          )
                        else
                          const Text(
                            'Pendiente',
                            style: TextStyle(color: Colors.orange),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  // ---- muestra la vista de una ronda suiza (mesa por duelo) ----
  Widget _buildSwissRoundView(int roundNumber) {
  // obtenemos lista de "pares" para mostrar (preferimos resultados guardados)
  final results = _swissResultsByRound[roundNumber];

  // Lista de pares a mostrar — cada item es Map{'a': Player, 'b': Player? , 'scoreA': int?, 'scoreB': int?}
  final List<Map<String, dynamic>> displayMatches = [];

  if (results != null && results.isNotEmpty) {
    for (final r in results) {
      displayMatches.add({
        'a': r.a,
        'b': r.b,
        'scoreA': r.scoreA,
        'scoreB': r.scoreB,
      });
    }
  } else {
    // fallback: si estamos viendo la ronda actual y existen pares preparados, los usamos tal cual
    if (roundNumber == _currentSwissRound && _pairsThisRound.isNotEmpty) {
      for (final p in _pairsThisRound) {
        displayMatches.add({
          'a': p.a,
          'b': p.b,
          'scoreA': null,
          'scoreB': null,
        });
      }
    } else {
      // si no, calculamos emparejamientos provisionales desde el estado (standings)
      final provisionalPairs = _computePairsForRound();
      for (final p in provisionalPairs) {
        displayMatches.add({
          'a': p.a,
          'b': p.b,
          'scoreA': null,
          'scoreB': null,
        });
      }
    }
  }

  if (displayMatches.isEmpty) {
    return Center(
      child: Text('Aún no hay emparejamientos para Ronda $roundNumber.'),
    );
  }

  // UI: grid flexible de mesas (Wrap) — cada mesa tiene ancho fijo para mantener consistencia
  return SingleChildScrollView(
    padding: const EdgeInsets.all(8.0),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: List.generate(displayMatches.length, (i) {
            final m = displayMatches[i];
            final a = m['a'] as Player;
            final b = m['b'] as Player?;
            final scoreA = m['scoreA'] as int?;
            final scoreB = m['scoreB'] as int?;

            // clave única para este match (se usa para reportes y confirmaciones)
            final String matchKey = 'swiss_r${roundNumber}_m${i}';
            final reported = _reportedResults[matchKey];

           return SizedBox(
  width: 260,
  child: Card(
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    elevation: 1,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Header compacto: Mesa N + estado + ojo
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceVariant,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Mesa ${i + 1}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),

              // status badge: Pendiente / Reportado / Confirmado
              const SizedBox(width: 8),
IconButton(
  padding: EdgeInsets.zero,
  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
  icon: const Icon(Icons.visibility_outlined, size: 18),
  color: (scoreA != null || scoreB != null || (reported != null))
      ? Theme.of(context).colorScheme.primary
      : Colors.grey,
  tooltip: 'Ver enfrentamiento',
  onPressed: () => _openDeckPosterDialog(a, b, scoreA: scoreA, scoreB: scoreB),
),
            ],
          ),
        ),

        // Contenido: DuelPanel
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: DuelPanel(
  a: a,
  b: b,
  scoreA: scoreA,
  scoreB: scoreB,
  matchKey: matchKey,
  reportedResult: reported,
  onReportDialogRequested: () => _showReportDialogAndSave(matchKey, a, b),
  onConfirm: (k) => _confirmReportedResult(k),
  onOpenDeckPoster: () => _openDeckPosterDialog(a, b, scoreA: scoreA, scoreB: scoreB),
  reporterName: _reporterDisplayName, // <-- aquí pasamos la función
),

        ),

        // Footer: info del report (opcional)
        if (reported != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
  'Reportado: ${_reporterDisplayName(reported['reporterUid'] as String?)}',
  style: const TextStyle(fontSize: 11, color: Colors.grey),
  overflow: TextOverflow.ellipsis,
),
                ),
                if (reported['confirmed'] == true)
                  const Icon(Icons.check_circle, size: 16, color: Colors.green),
              ],
            ),
          ),
      ],
    ),
  ),
);

          }),
        ),
      ],
    ),
  );
}


    // Abre diálogo para ingresar score y luego guarda reporte
  Future<void> _showReportDialogAndSave(String matchKey, Player a, Player? b) async {
    final ctx = context;
    final scoreActrl = TextEditingController();
    final scoreBctrl = TextEditingController();

    final res = await showDialog<bool>(
      context: ctx,
      builder: (dctx) => AlertDialog(
        title: const Text('Reportar resultado'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Mesa: $matchKey'),
            const SizedBox(height: 8),
            TextField(
              controller: scoreActrl,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(labelText: '${a.displayName} - puntaje'),
            ),
            TextField(
              controller: scoreBctrl,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(labelText: '${b?.displayName ?? "Oponente"} - puntaje'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(dctx).pop(false), child: const Text('Cancelar')),
          TextButton(onPressed: () => Navigator.of(dctx).pop(true), child: const Text('Enviar')),
        ],
      ),
    );

    if (res != true) return;

    final aScore = int.tryParse(scoreActrl.text.trim()) ?? 0;
    final bScore = int.tryParse(scoreBctrl.text.trim()) ?? 0;
    _reportResult(matchKey, a, b, aScore, bScore);
  }

  String _reporterDisplayName(String? uid) {
  if (uid == null || uid.isEmpty) return '—';
  try {
    final p = players.firstWhere((pl) => pl.ownerUid == uid);
    return p.displayName;
  } catch (_) {}
  try {
    final parts = (_tournament?['participants'] as List<dynamic>?) ?? <dynamic>[];
    for (final item in parts) {
      if (item is Map) {
        final candidate = (item['uid'] ?? item['user'] ?? '').toString();
        if (candidate == uid) {
          return (item['name'] ?? item['displayName'] ?? candidate).toString();
        }
      }
    }
  } catch (_) {}
  // fallback: acortar uid para no mostrar un string crudo enorme
  return uid.length > 10 ? '${uid.substring(0, 6)}...' : uid;
}

  void _reportResult(String matchKey, Player a, Player? b, int scoreA, int scoreB) async {
  final uid = FirebaseAuth.instance.currentUser?.uid ?? 'unknown';
  final payload = {
    'aId': a.id,
    'bId': b?.id,
    'scoreA': scoreA,
    'scoreB': scoreB,
    'reporterUid': uid,
    'confirmed': false,
    'timestamp': DateTime.now().toIso8601String(),
  };

  // Actualizamos localmente primero (optimistic UI)
  _reportedResults[matchKey] = Map<String, dynamic>.from(payload);
  setState(() {});

  // Persistir en Firestore
  try {
    await _persistReportedResultToFirestore(matchKey, payload);
  } catch (e) {
    debugPrint('Error guardando reporte en Firestore: $e');
    // Puedes mostrar Snackbar si quieres
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('No se pudo guardar el reporte en servidor')),
    );
  }
}


  // Invocada por el oponente para confirmar el resultado reportado
  Future<void> _confirmReportedResult(String matchKey) async {
  final rep = _reportedResults[matchKey];
  if (rep == null) return;
  final currentUid = FirebaseAuth.instance.currentUser?.uid ?? 'unknown';
  if (rep['reporterUid'] == currentUid) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('El reportero no puede confirmar su propio reporte')),
    );
    return;
  }

  // Marcamos confirmado localmente
  rep['confirmed'] = true;
  rep['confirmedBy'] = currentUid;
  rep['confirmedAt'] = DateTime.now().toIso8601String();
  _reportedResults[matchKey] = Map<String, dynamic>.from(rep);
  setState(() {});

  // Persistir confirmación en Firestore (actualiza sólo la clave)
  try {
    await _persistReportedResultToFirestore(matchKey, rep);
  } catch (e) {
    debugPrint('Error guardando confirmación en Firestore: $e');
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('No se pudo confirmar en servidor')),
    );
    return;
  }

  // Aplicar el resultado a las stats (solo una vez)
  if (!_appliedReportedResults.contains(matchKey)) {
    _applyReportedResultToStats(matchKey, rep);
    _appliedReportedResults.add(matchKey);
  }
}


  void _applyReportedResultToStats(String matchKey, Map<String, dynamic> rep) {
  try {
    final aId = rep['aId'] as String;
    final bId = rep['bId'] as String?;
    final scoreA = (rep['scoreA'] as int?) ?? 0;
    final scoreB = (rep['scoreB'] as int?) ?? 0;

    // Buscar players de forma segura (no usar orElse que retorne null)
    Player? aPlayer;
    Player? bPlayer;

    try {
      aPlayer = players.firstWhere((p) => p.id == aId);
    } catch (_) {
      // si no lo encontramos, abortamos — sin jugador no hay forma de aplicar
      debugPrint('[applyReported] aPlayer not found for id=$aId');
      return;
    }

    if (bId != null) {
      try {
        bPlayer = players.firstWhere((p) => p.id == bId);
      } catch (_) {
        // no encontrado -> lo dejamos nulo (bye / posible error de datos)
        debugPrint('[applyReported] bPlayer not found for id=$bId');
        bPlayer = null;
      }
    }

    // determinar ganador (en caso de empate winner = null)
    final Player? winner = (scoreA > scoreB) ? aPlayer : (scoreB > scoreA ? bPlayer : null);
    final winnerId = winner?.id ?? aPlayer.id;

    // Actualizar stats similar a _simulateSingleMatch pero con scores reales
    _stats[aPlayer.id]!.matchesPlayed += 1;
    if (bPlayer != null) _stats[bPlayer.id]!.matchesPlayed += 1;

    if (winnerId == aPlayer.id) {
      _stats[aPlayer.id]!.matchesWon += 1;
      if (bPlayer != null) _stats[bPlayer.id]!.matchesLost += 1;
      _stats[aPlayer.id]!.points += 3;
    } else if (bPlayer != null) {
      _stats[bPlayer.id]!.matchesWon += 1;
      _stats[aPlayer.id]!.matchesLost += 1;
      _stats[bPlayer.id]!.points += 3;
    } else {
      // empate: actualmente no otorgamos puntos extra (modifica si quieres otra regla)
    }

    // games
    _stats[aPlayer.id]!.gamesWon += scoreA;
    _stats[aPlayer.id]!.gamesLost += scoreB;
    if (bPlayer != null) {
      _stats[bPlayer.id]!.gamesWon += scoreB;
      _stats[bPlayer.id]!.gamesLost += scoreA;
    }

    // push a _allMatchResults para historial
        // push a _allMatchResults para historial
    final res = MatchResult(aPlayer, bPlayer, scoreA, scoreB, winnerId);
    _allMatchResults.add(res);

    // también lo guardamos en swissResultsByRound o en _elimResults según la key
    final rg = RegExp(r'(?:swiss|elim)_r(\d+)_m(\d+)');
    final m = rg.firstMatch(matchKey);
    if (m != null) {
      final roundNum = int.tryParse(m.group(1) ?? '') ?? 0;
      final isSwiss = matchKey.startsWith('swiss_');
      if (isSwiss) {
        _swissResultsByRound.putIfAbsent(roundNum, () => []);
        _swissResultsByRound[roundNum]!.add(res);
      } else {
        final idx = m.group(2) ?? '0';
        final key = 'r${roundNum}_m$idx';
        _elimResults[key] = res;
      }
    }

    // Recalcular _stats desde el historial (fuente de verdad) y agregados por raza
    _recomputeStatsFromAllResults();
    _computeRaceAggregates();

    if (mounted) setState(() {});

  } catch (e) {
    debugPrint('Error aplicando resultado reportado: $e');
  }
}



  /// También limpia resultados y estados relacionados para empezar "desde cero".
  void _shufflePlayersAndPrepareRound() {
    // reset estadísticos y resultados
    for (final s in _stats.values) s.reset();
    _allMatchResults.clear();
    _log.clear();
    _swissResultsByRound.clear();
    _elimRounds.clear();
    _elimResults.clear();
    _elimNextRoundWinners.clear();

    // barajar jugadores y crear pares aleatorios
    final shuffled = List<Player>.from(players);
    shuffled.shuffle(_rnd);

    final pairs = <Pair>[];
    for (int i = 0; i < shuffled.length; i += 2) {
      final a = shuffled[i];
      final b = (i + 1 < shuffled.length) ? shuffled[i + 1] : null;
      pairs.add(Pair(a, b));
    }

    _pairsThisRound = pairs;
    // reiniciar control suizo
    _swissRounds = (_swissRounds <= 0)
        ? 1
        : _swissRounds; // mantener configuración previa si existe
    _currentSwissRound = players.length >= 2 ? 1 : 0;
    _visibleSwissRounds = 1;

    _recreateTabController();

    // mover la pestaña activa a la ronda actual (si aplica)
    if (_tabController != null && _currentSwissRound > 0) {
      final desiredIndex = (_currentSwissRound - 1).clamp(
        0,
        _tabController!.length - 1,
      );
      // animateTo es más seguro que asignar index directamente
      _tabController!.animateTo(desiredIndex);
    }

    setState(() {});
  }


  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_tournament == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Detalles del torneo')),
        body: const Center(child: Text('No se pudo cargar el torneo')),
      );
    }

    final name = _tournament!['name'] ?? 'Torneo';
    final desc = _tournament!['description'] ?? '';

    // build tab widgets (para poder pintar la active tab con fondo)
    final tabWidgets = <Widget>[];
    final swissCount = max(1, _visibleSwissRounds);

    // swiss tabs
    for (int i = 1; i <= swissCount; i++) {
      final idx = i - 1; // índice en el TabController
      final isActive = _currentTabIndex == idx;
      final isDefined = i <= _visibleSwissRounds;

      tabWidgets.add(
        Tab(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: isActive
                ? BoxDecoration(
                    color: Theme.of(context).colorScheme.primary,
                    borderRadius: BorderRadius.circular(8),
                  )
                : null,
            child: Text(
              'R$i',
              style: TextStyle(
                color: isActive
                    ? Theme.of(context).colorScheme.onPrimary
                    : (isDefined ? null : Colors.grey),
                fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
        ),
      );
    }

    // elimination tabs (TopX / Final)
    if (_elimRounds.isNotEmpty) {
      int qualifiers = _elimRounds.first.length * 2;
      for (int r = 0; r < _elimRounds.length; r++) {
        final idx = swissCount + r;
        final label = qualifiers == 2 ? 'Final' : 'Top$qualifiers';
        final isActive = _currentTabIndex == idx;
        tabWidgets.add(
          Tab(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: isActive
                  ? BoxDecoration(
                      color: Theme.of(context).colorScheme.primary,
                      borderRadius: BorderRadius.circular(8),
                    )
                  : null,
              child: Text(
                label,
                style: TextStyle(
                  color: isActive
                      ? Theme.of(context).colorScheme.onPrimary
                      : null,
                  fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ),
          ),
        );
        qualifiers = (qualifiers / 2).floor();
      }
    }

    // defensivo: al menos una tab
    if (tabWidgets.isEmpty) {
      tabWidgets.add(const Tab(text: 'R1'));
    }

    // Asegurar _tabController y preservar índice (recrearlo si cambia la longitud)
    final targetLength = tabWidgets.length;
    if (_tabController == null) {
      final initIndex = (_currentTabIndex < targetLength)
          ? _currentTabIndex
          : 0;
      _tabController = TabController(
        length: targetLength,
        vsync: this,
        initialIndex: initIndex,
      );
      _tabController!.addListener(_handleTabChange);
    } else if (_tabController!.length != targetLength) {
      // recrear conservando índice previo si es posible
      final prev = _tabController!.index;
      _tabController!.removeListener(_handleTabChange);
      _tabController!.dispose();
      final initIndex = (prev < targetLength)
          ? prev
          : (targetLength - 1 >= 0 ? targetLength - 1 : 0);
      _tabController = TabController(
        length: targetLength,
        vsync: this,
        initialIndex: initIndex,
      );
      _tabController!.addListener(_handleTabChange);
    }

    return Scaffold(
  appBar: AppBar(
    title: Text(name),
    actions: [
      // 1) Descripción en diálogo
      IconButton(
        tooltip: 'Descripción',
        icon: const Icon(Icons.description_outlined),
        onPressed: () {
          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Descripción'),
              content: SingleChildScrollView(child: Text(desc ?? '')),
              actions: [
                TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cerrar')),
              ],
            ),
          );
        },
      ),
      IconButton(
        tooltip: 'Reiniciar',
        icon: const Icon(Icons.restart_alt),
        onPressed: () {
          _shufflePlayersAndPrepareRound();
        },
      ),

      IconButton(
        tooltip: 'Detalles por raza',
        icon: const Icon(Icons.info_outline),
        onPressed: _allMatchResults.isEmpty ? null : () => _showRaceStatsDialog(),
      ),

      IconButton(
        tooltip: 'Estadísticas torneo',
        icon: const Icon(Icons.bar_chart),
        onPressed: (_allMatchResults.isEmpty || players.isEmpty) ? null : () => _showTournamentStats(),
      ),

      IconButton(
        tooltip: 'Tabla posiciones',
        icon: const Icon(Icons.table_rows),
        onPressed: () => _showStandingsSheet(),
      ),

      const SizedBox(width: 6), // pequeño padding derecho
    ],
  ),
  body: Padding( padding: const EdgeInsets.all(12),
        child: Column(
          children: [
              if (tabWidgets.isNotEmpty)
              Column(
                children: [
                  TabBar(
                    controller: _tabController,
                    isScrollable: true,
                    tabs: tabWidgets,
                    indicatorColor: Colors.transparent,
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            const SizedBox(height: 8),
            Expanded(
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: (_tabController == null || _tabController!.length == 0)
                      ? const Center(child: Text('No hay rondas definidas'))
                      : TabBarView(
                          controller: _tabController,
                          children: List.generate(_tabController!.length, (
                            tabIndex,
                          ) {
                            // swiss tabs first
                            if (tabIndex < swissCount) {
                              final rndNum = tabIndex + 1;
                              return _buildSwissRoundView(rndNum);
                            } else {
                              final elimIdx = tabIndex - swissCount;
                              return _buildBracketViewForElimRound(elimIdx);
                            }
                          }),
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class DuelPanel extends StatefulWidget {
  final Player a;
  final Player? b;
  final int? scoreA;
  final int? scoreB;

  // nuevos
  final String? matchKey;
  final Map<String, dynamic>? reportedResult;
  final void Function(String matchKey, int scoreA, int scoreB)? onReport;
  final VoidCallback? onReportDialogRequested;
  final void Function(String matchKey)? onConfirm;
  final VoidCallback? onOpenDeckPoster;

  // <-- NEW: callback para obtener el nombre del reportero desde el padre
  final String? Function(String? uid)? reporterName;

  const DuelPanel({
    super.key,
    required this.a,
    this.b,
    this.scoreA,
    this.scoreB,
    this.matchKey,
    this.reportedResult,
    this.onReport,
    this.onReportDialogRequested,
    this.onConfirm,
    this.onOpenDeckPoster,
    this.reporterName, // <-- añadir al constructor
  });

  @override
  State<DuelPanel> createState() => _DuelPanelState();
}



class _DuelPanelState extends State<DuelPanel> {
  Future<Map<String, dynamic>?>? _deckAFut;
  Future<Map<String, dynamic>?>? _deckBFut;

  @override
  void initState() {
    super.initState();
    _deckAFut = _maybeLoadDeck(widget.a);
    if (widget.b != null) _deckBFut = _maybeLoadDeck(widget.b!);
  }

  Future<Map<String, dynamic>?> _maybeLoadDeck(Player p) async {
  try {
    final owner = p.ownerUid;
    final deckId = p.deckId;
    if ((owner.isEmpty && deckId.isEmpty)) return null;

    // 1) intento por collectionGroup buscando docId igual a deckId
    if (deckId.isNotEmpty) {
      try {
        final q = await FirebaseFirestore.instance
            .collectionGroup('decks')
            .where(FieldPath.documentId, isEqualTo: deckId)
            .limit(1)
            .get();
        if (q.docs.isNotEmpty) {
          final doc = q.docs.first;
          final data = Map<String, dynamic>.from(doc.data());
          final parent = doc.reference.parent.parent;
          if (parent != null) data['ownerId'] = parent.id;
          data['__path'] = doc.reference.path;
          data['__id'] = doc.id;
          return data;
        }
      } catch (_) {
        // seguir a fallback
      }
    }

    // 2) si owner parece bot/guest intentar buscar en admin (fallback)
    if (owner.startsWith('Bot') || owner == 'guest') {
      try {
        final adminQ = await FirebaseFirestore.instance
            .collection('users')
            .where('email', isEqualTo: 'hecturnicolas@gmail.com')
            .limit(1)
            .get();
        if (adminQ.docs.isNotEmpty) {
          final adminUid = adminQ.docs.first.id;
          final decksSnap = await FirebaseFirestore.instance
              .collection('users')
              .doc(adminUid)
              .collection('decks')
              .limit(1)
              .get();
          if (decksSnap.docs.isNotEmpty) {
            final doc = decksSnap.docs.first;
            final data = Map<String, dynamic>.from(doc.data());
            data['ownerId'] = adminUid;
            data['__path'] = doc.reference.path;
            data['__id'] = doc.id;
            return data;
          }
        }
      } catch (_) {}
      return null;
    }

    // 3) fallback: owner normal -> leer users/{owner}/decks/{deckId}
    if (owner.isNotEmpty && deckId.isNotEmpty) {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(owner)
          .collection('decks')
          .doc(deckId)
          .get();
      if (doc.exists && doc.data() != null) {
        final data = Map<String, dynamic>.from(doc.data()!);
        data['__path'] = doc.reference.path;
        data['__id'] = doc.id;
        return data;
      }
    }

    return null;
  } catch (_) {
    return null;
  }
}


  // ... conserva _maybeLoadDeck() igual que antes ...

  @override
  Widget build(BuildContext context) {

    return Card(
  elevation: 1,
  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
  child: Padding(
    padding: const EdgeInsets.all(10.0),
    child: FutureBuilder<List<Map<String, dynamic>?>>(
      future: Future.wait([
        _deckAFut ?? Future.value(null),
        _deckBFut ?? Future.value(null),
      ]),
      builder: (ctx, snap) {
        final deckA = (snap.data != null && snap.data!.isNotEmpty) ? snap.data![0] : null;
        final deckB = (snap.data != null && snap.data!.length > 1) ? snap.data![1] : null;

        String? _extractImg(Map<String, dynamic>? d) {
          if (d == null) return null;
          final maybe = (d['image'] ?? d['imageUrl'] ?? d['cover'] ?? d['thumbnail'])?.toString();
          if (maybe != null && maybe.isNotEmpty) return maybe;
          final cards = (d['cards'] as List<dynamic>?) ?? [];
          if (cards.isNotEmpty && cards.first is Map) {
            final c = cards.first as Map;
            final m = (c['imageFrontUrl'] ?? c['image'] ?? c['imageUrl'])?.toString();
            if (m != null && m.isNotEmpty) return m;
          }
          return null;
        }

        final imgA = _extractImg(deckA);
        final imgB = _extractImg(deckB);

        // Resultado: preferido reportado, sino score fijo
        final reported = widget.reportedResult;
        final resultText = (widget.scoreA == null && widget.scoreB == null)
            ? (reported != null
                ? '${reported['scoreA'] ?? 0} - ${reported['scoreB'] ?? 0}${reported['confirmed'] == true ? ' • confirmado' : ' • pendiente'}'
                : 'Pendiente')
            : '${widget.scoreA ?? 0} - ${widget.scoreB ?? 0}';

        return LayoutBuilder(builder: (context, constraints) {
          final isNarrow = constraints.maxWidth < 420; // threshold; ajusta si quieres

          Widget playerColumn(Player p, String? img, {bool alignRight = false}) {
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
  child: Column(
    crossAxisAlignment: alignRight ? CrossAxisAlignment.end : CrossAxisAlignment.start,
    children: [
      Text(p.displayName, style: const TextStyle(fontWeight: FontWeight.w700)),
      const SizedBox(height: 2),
      Text(
        _displayDeckName(p.deckName),
        style: const TextStyle(fontSize: 12, color: Colors.grey),
        overflow: TextOverflow.ellipsis,
      ),
    ],
  ),
),
              ],
            );
          }

          // badge central del resultado
          final scoreBadge = Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: (reported != null && reported['confirmed'] == true)
                  ? Colors.green.shade50
                  : Colors.grey.shade100,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Column(
              children: [
                Text(resultText, style: const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text(
  reported != null
      ? 'Reportado por ${widget.reporterName?.call(reported['reporterUid'] as String?) ?? (reported['reporterUid'] as String? ?? '—')}'
      : (widget.scoreA == null && widget.scoreB == null ? 'Sin reportar' : 'Informe oficial'),
  style: const TextStyle(fontSize: 10, color: Colors.grey),
),


              ],
            ),
          );

          // botones alineados en wrap para que no corten en celular
          final actionButtons = Wrap(
            spacing: 8,
            runSpacing: 4,
            alignment: WrapAlignment.end,
            children: [
              if (reported == null) ...[
                OutlinedButton.icon(
                  onPressed: widget.onReportDialogRequested,
                  icon: const Icon(Icons.edit_note_outlined, size: 16),
                  label: const Text('Reportar'),
                  style: OutlinedButton.styleFrom(minimumSize: const Size(0, 36)),
                ),
              ] else if (reported['confirmed'] == true) ...[
                Chip(label: const Text('Confirmado'), backgroundColor: Colors.green.shade50),
              ] else ...[
                ElevatedButton.icon(
                  onPressed: widget.matchKey != null ? () => widget.onConfirm?.call(widget.matchKey!) : null,
                  icon: const Icon(Icons.check, size: 16),
                  label: const Text('Confirmar'),
                  style: ElevatedButton.styleFrom(minimumSize: const Size(0, 36)),
                ),
              ],
            ],
          );

          if (isNarrow) {
            // layout vertical para celular
            // Reemplaza el return actual del LayoutBuilder por este
return Column(
  crossAxisAlignment: CrossAxisAlignment.stretch,
  children: [
    // fila con nombres: izquierda - vs - derecha
    Row(
      children: [
        Expanded(
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              widget.a.displayName,
              style: const TextStyle(fontWeight: FontWeight.w700),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8.0),
          child: Text('vs', style: const TextStyle(fontWeight: FontWeight.w700)),
        ),
        Expanded(
          child: Align(
            alignment: Alignment.centerRight,
            child: Text(
              widget.b?.displayName ?? 'bye',
              style: const TextStyle(fontWeight: FontWeight.w700),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ],
    ),

    const SizedBox(height: 4),

    // fila con nombres de mazos (más ligera, gris y con ellipsis)
    Row(
      children: [
        Expanded(
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              _displayDeckName(widget.a.deckName),
              style: const TextStyle(fontSize: 12, color: Colors.grey),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Align(
            alignment: Alignment.centerRight,
            child: Text(
              widget.b != null ? _displayDeckName(widget.b!.deckName) : '',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ],
    ),

    const SizedBox(height: 6),

    // estado muy pequeño centrado (Pendiente / Reportado / Confirmado)
    Center(
      child: Builder(builder: (_) {
        if (widget.scoreA == null && widget.scoreB == null) {
          final rep = widget.reportedResult;
          if (rep == null) {
            return const Text('Pendiente',
                style: TextStyle(fontSize: 11, color: Colors.grey));
          } else if (rep['confirmed'] == true) {
            return Text('Confirmado',
                style: TextStyle(fontSize: 11, color: Colors.green.shade700));
          } else {
            return Text('Reportado • pendiente',
                style: TextStyle(fontSize: 11, color: Colors.orange.shade800));
          }
        } else {
          // si ya hay score oficial no mostrar "Pendiente"
          return const SizedBox.shrink();
        }
      }),
    ),

    const SizedBox(height: 8),

    // Badge/resultado central (si lo querés mantener) y botones a la derecha
    // Aquí reutilizamos scoreBadge y actionButtons que ya definiste arriba.
    Center(child: scoreBadge),
    const SizedBox(height: 8),
    Align(alignment: Alignment.centerRight, child: actionButtons),
  ],
);

          } else {
            // layout horizontal para tablet/desktop
            return Row(
              children: [
                Expanded(child: playerColumn(widget.a, imgA, alignRight: false)),
                const SizedBox(width: 12),
                scoreBadge,
                const SizedBox(width: 12),
                Expanded(child: playerColumn(widget.b ?? Player(id: 'guest', displayName: 'bye', ownerUid: 'guest', deckId: '', deckName: '', race: ''), imgB, alignRight: true)),
                const SizedBox(width: 12),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 180),
                  child: actionButtons,
                ),
              ],
            );
          }
        });
      },
    ),
  ),
);

  }


  String _displayDeckName(String deckName) {
    final idx = deckName.indexOf('(');
    if (idx >= 0) return deckName.substring(0, idx).trim();
    return deckName;
  }
}


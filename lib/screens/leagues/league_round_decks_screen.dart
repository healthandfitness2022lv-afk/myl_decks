// lib/screens/leagues/league_round_decks_screen.dart
//
// Asignación de mazos por jugador para una fecha de liga.
//
// El admin ve la lista de jugadores de la fecha y, para cada uno, arma su mazo
// con la misma vista que create_deck (LeagueDeckBuilderScreen), respetando las
// restricciones del formato de la fecha. Cada jugador tiene UN mazo para toda la
// fecha, guardado en `leagues/{id}/rounds/{id}.decks` como { playerId: [cards] }.

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../models/deck.dart';
import '../../services/deck_service.dart';
import 'models.dart';
import 'league_deck_builder_screen.dart';

class LeagueRoundDecksScreen extends StatefulWidget {
  final String leagueId;
  final String roundId;
  final List<LeaguePlayer> players;
  final RoundFormat roundFormat;
  final List<Map<String, dynamic>>? banListSnapshot;
  final bool isAdmin;

  const LeagueRoundDecksScreen({
    super.key,
    required this.leagueId,
    required this.roundId,
    required this.players,
    required this.roundFormat,
    this.banListSnapshot,
    required this.isAdmin,
  });

  @override
  State<LeagueRoundDecksScreen> createState() => _LeagueRoundDecksScreenState();
}

class _LeagueRoundDecksScreenState extends State<LeagueRoundDecksScreen> {
  // playerId → cartas del mazo asignado para esta fecha.
  Map<String, List<DeckCardEntry>> _decks = {};
  // playerId → raza del mazo (deducida de los aliados).
  Map<String, String> _deckRaces = {};
  bool _loading = true;
  bool _saving = false;

  DocumentReference<Map<String, dynamic>> get _roundRef => FirebaseFirestore
      .instance
      .collection('leagues')
      .doc(widget.leagueId)
      .collection('rounds')
      .doc(widget.roundId);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final snap = await _roundRef.get();
      final data = snap.data() ?? {};
      // Firestore puede devolver los mapas anidados dentro de una List como
      // Map<Object?, Object?> según la plataforma, no Map<String, dynamic>
      // exacto — whereType<Map<String, dynamic>>() los descarta en silencio
      // en ese caso, dejando el mazo "vacío" aunque el dato sí exista.
      final raw = (data['decks'] as Map?) ?? {};
      final parsed = <String, List<DeckCardEntry>>{};
      raw.forEach((playerId, cards) {
        if (cards is List) {
          parsed[playerId.toString()] =
              cards
                  .whereType<Map>()
                  .map(
                    (m) => DeckCardEntry.fromMap(Map<String, dynamic>.from(m)),
                  )
                  .toList();
        }
      });
      final rawRaces = (data['deckRaces'] as Map?) ?? {};
      final races = <String, String>{};
      if (widget.roundFormat != RoundFormat.full) {
        rawRaces.forEach((playerId, race) {
          if (race is String && race.trim().isNotEmpty) {
            races[playerId.toString()] = race.trim();
          }
        });
      }
      if (!mounted) return;
      setState(() {
        _decks = parsed;
        _deckRaces = races;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _persist() async {
    setState(() => _saving = true);
    try {
      final payload = <String, dynamic>{};
      _decks.forEach((playerId, cards) {
        payload[playerId] = cards.map((e) => e.toMap()).toList();
      });
      await _roundRef.update({
        'decks': payload,
        'deckRaces':
            widget.roundFormat == RoundFormat.full
                ? <String, dynamic>{}
                : Map<String, dynamic>.from(_deckRaces),
      });
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  int _deckCount(String playerId) =>
      (_decks[playerId] ?? const []).fold<int>(0, (s, e) => s + e.count);

  Future<void> _editDeck(LeaguePlayer player) async {
    final result = await Navigator.push<LeagueDeckResult>(
      context,
      MaterialPageRoute(
        builder:
            (_) => LeagueDeckBuilderScreen(
              playerName: player.name,
              roundFormat: widget.roundFormat,
              banListSnapshot: widget.banListSnapshot,
              initialCards: List.from(_decks[player.id] ?? const []),
              initialRace: _deckRaces[player.id],
            ),
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      _decks[player.id] = result.cards;
      if (result.race != null) {
        _deckRaces[player.id] = result.race!;
      } else {
        _deckRaces.remove(player.id);
      }
    });
    await _persist();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Mazo de ${player.name} guardado')),
      );
    }
  }

  // ── Herramienta temporal de pruebas ────────────────────────────────────────
  // Asigna a un jugador uno de MIS mazos ya armados. Sirve para poblar rápido
  // una fecha durante el testeo; no se usará con los mazos reales cargados por
  // los jugadores.
  Future<void> _copyFromMyDecks(LeaguePlayer player) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    List<Deck> myDecks = [];
    try {
      myDecks = await DeckService(uid).listMine();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error cargando mazos: $e')));
      }
      return;
    }
    if (!mounted) return;

    // Solo mazos "objetivo" completos (49 cartas). Para un mazo con objetivo
    // embebido usamos objectiveCards; si es objetivo puro (published), sus cards.
    List<DeckCardEntry> objectiveOf(Deck d) =>
        d.isUnified
            ? d.cards
            : (d.hasEmbeddedObjective ? d.objectiveCards : d.cards);
    final candidates =
        myDecks.where((d) {
          if (!(d.isUnified || d.isTarget || d.hasEmbeddedObjective)) {
            return false;
          }
          final count = objectiveOf(d).fold<int>(0, (s, e) => s + e.count);
          return count == 49;
        }).toList();

    if (candidates.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No tienes configuraciones completas (49 cartas).'),
        ),
      );
      return;
    }

    final chosen = await showModalBottomSheet<Deck>(
      context: context,
      showDragHandle: true,
      builder:
          (_) => SafeArea(
            child: ListView(
              shrinkWrap: true,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                  child: Text(
                    'Copiar mazo a ${player.name}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
                ),
                ...candidates.map((d) {
                  final count = objectiveOf(
                    d,
                  ).fold<int>(0, (s, e) => s + e.count);
                  return ListTile(
                    leading: const Icon(Icons.style_rounded),
                    title: Text(d.name.isEmpty ? 'Mazo sin nombre' : d.name),
                    subtitle: Text(
                      [
                        if ((d.race ?? '').isNotEmpty) d.race,
                        '$count cartas',
                      ].join(' · '),
                    ),
                    onTap: () => Navigator.pop(context, d),
                  );
                }),
              ],
            ),
          ),
    );

    if (chosen == null || !mounted) return;

    setState(() {
      _decks[player.id] = List<DeckCardEntry>.from(objectiveOf(chosen));
      final race = leagueDeckRaceForFormat(widget.roundFormat, chosen.race);
      if (race != null) {
        _deckRaces[player.id] = race;
      } else {
        _deckRaces.remove(player.id);
      }
    });
    await _persist();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('"${chosen.name}" asignado a ${player.name}')),
      );
    }
  }

  Future<void> _clearDeck(LeaguePlayer player) async {
    setState(() {
      _decks.remove(player.id);
      _deckRaces.remove(player.id);
    });
    await _persist();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final assigned = widget.players.where((p) => _deckCount(p.id) > 0).length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Asignar mazos'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(28),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              '${widget.roundFormat.label} · $assigned/${widget.players.length} mazos cargados',
              style: const TextStyle(fontSize: 12, color: Colors.white70),
            ),
          ),
        ),
        actions: [
          if (_saving)
            const Padding(
              padding: EdgeInsets.only(right: 16),
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
        ],
      ),
      body:
          widget.players.isEmpty
              ? const Center(
                child: Text(
                  'No hay jugadores en esta fecha.',
                  style: TextStyle(color: Colors.grey),
                ),
              )
              : ListView.separated(
                padding: const EdgeInsets.all(12),
                itemCount: widget.players.length,
                separatorBuilder: (_, __) => const SizedBox(height: 6),
                itemBuilder: (context, i) {
                  final p = widget.players[i];
                  final count = _deckCount(p.id);
                  final hasDeck = count > 0;
                  final race = _deckRaces[p.id];
                  final subtitle =
                      hasDeck
                          ? [
                            if (race != null && race.isNotEmpty) race,
                            '$count/49 cartas',
                          ].join(' · ')
                          : 'Sin mazo asignado';
                  return Card(
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor:
                            hasDeck
                                ? Colors.green.shade100
                                : Colors.orange.shade100,
                        child: Icon(
                          hasDeck ? Icons.check_rounded : Icons.style_outlined,
                          color:
                              hasDeck
                                  ? Colors.green.shade700
                                  : Colors.orange.shade700,
                        ),
                      ),
                      title: Text(
                        p.name,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        subtitle,
                        style: TextStyle(
                          color:
                              hasDeck
                                  ? Colors.green.shade700
                                  : Colors.orange.shade800,
                          fontSize: 12,
                        ),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (widget.isAdmin)
                            IconButton(
                              icon: const Icon(Icons.copy_all_rounded),
                              tooltip: 'Copiar desde mis mazos (pruebas)',
                              onPressed:
                                  _saving ? null : () => _copyFromMyDecks(p),
                            ),
                          if (hasDeck && widget.isAdmin)
                            IconButton(
                              icon: const Icon(Icons.delete_outline_rounded),
                              tooltip: 'Quitar mazo',
                              onPressed: _saving ? null : () => _clearDeck(p),
                            ),
                          Icon(
                            widget.isAdmin
                                ? Icons.chevron_right_rounded
                                : Icons.visibility_outlined,
                            color: Colors.grey,
                          ),
                        ],
                      ),
                      onTap: widget.isAdmin ? () => _editDeck(p) : null,
                    ),
                  );
                },
              ),
    );
  }
}

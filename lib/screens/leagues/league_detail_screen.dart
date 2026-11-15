// lib/screens/leagues/league_detail_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../services/ban_list_service.dart';
import 'models.dart';
import 'league_round_screen.dart';
import 'league_settings_screen.dart';
import 'league_widgets.dart';
import 'round_ban_list_viewer.dart';

class LeagueDetailScreen extends StatefulWidget {
  final String leagueId;
  const LeagueDetailScreen({super.key, required this.leagueId});

  @override
  State<LeagueDetailScreen> createState() => _LeagueDetailScreenState();
}

class _LeagueDetailScreenState extends State<LeagueDetailScreen> {
  Map<String, dynamic>? _league;
  List<LeaguePlayer> _players = [];
  bool _loading = true;
  bool _updatingBanLists = false;
  String? _uid;
  bool _teamCanManage = false;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _memberSub;

  @override
  void initState() {
    super.initState();
    _uid = FirebaseAuth.instance.currentUser?.uid;
    _load();
  }

  @override
  void dispose() {
    _memberSub?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final leagueDoc =
          await FirebaseFirestore.instance
              .collection('leagues')
              .doc(widget.leagueId)
              .get();
      final playersSnap =
          await FirebaseFirestore.instance
              .collection('leagues')
              .doc(widget.leagueId)
              .collection('players')
              .orderBy('name')
              .get();

      if (!mounted) return;
      setState(() {
        _league = leagueDoc.data();
        _players =
            playersSnap.docs
                .map((d) => LeaguePlayer.fromMap(d.id, d.data()))
                .toList();
      });
      _listenTeamRole();
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

  void _listenTeamRole() {
    final uid = _uid;
    final teamId = (_league?['teamId'] as String?) ?? '';
    if (uid == null || teamId.isEmpty) return;
    _memberSub?.cancel();
    _memberSub = FirebaseFirestore.instance
        .collection('teams')
        .doc(teamId)
        .collection('members')
        .doc(uid)
        .snapshots()
        .listen((snapshot) {
          final role = snapshot.data()?['role'] as String?;
          final canManage = role == 'owner' || role == 'admin';
          if (mounted && canManage != _teamCanManage) {
            setState(() => _teamCanManage = canManage);
          }
        });
  }

  bool get _isAdmin => _league?['adminUid'] == _uid || _teamCanManage;

  // ── Jugadores ──────────────────────────────────────────────────────────────

  Future<void> _addPlayer() async {
    // Traer jugadores del team que no están ya en la liga
    final teamId = (_league?['teamId'] as String?) ?? '';
    List<Map<String, dynamic>> teamCandidates = [];

    if (teamId.isNotEmpty) {
      try {
        final teamSnap =
            await FirebaseFirestore.instance
                .collection('teams')
                .doc(teamId)
                .collection('players')
                .get();
        final alreadyIn = _players.map((p) => p.id).toSet();
        // También comparar por nombre por si el ID no coincide
        final alreadyInNames =
            _players.map((p) => p.name.toLowerCase()).toSet();
        teamCandidates =
            teamSnap.docs
                .where(
                  (d) =>
                      !alreadyIn.contains(d.id) &&
                      !alreadyInNames.contains(
                        (d.data()['name'] as String? ?? '').toLowerCase(),
                      ),
                )
                .map((d) => {'id': d.id, ...d.data()})
                .toList();
      } catch (_) {}
    }

    if (!mounted) return;

    // Si hay candidatos del team → mostrar lista para seleccionar
    // Si no → input manual de nombre
    if (teamCandidates.isNotEmpty) {
      final selected = await showDialog<Map<String, dynamic>>(
        context: context,
        builder:
            (ctx) => AlertDialog(
              title: const Text('Agregar jugador del team'),
              content: SizedBox(
                width: double.maxFinite,
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: teamCandidates.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final c = teamCandidates[i];
                    return ListTile(
                      title: Text(c['name'] as String? ?? ''),
                      onTap: () => Navigator.pop(ctx, c),
                    );
                  },
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancelar'),
                ),
              ],
            ),
      );
      if (selected == null || !mounted) return;

      try {
        final db = FirebaseFirestore.instance;
        final leagueRef = db.collection('leagues').doc(widget.leagueId);
        final playerId = selected['id'] as String;
        final playerName = selected['name'] as String? ?? '';

        // Agregar a players de la liga
        await leagueRef.collection('players').doc(playerId).set({
          'name': playerName,
        });

        await _load();
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('$playerName agregado')));
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Error: $e')));
        }
      }
    } else {
      // Sin candidatos del team → input manual
      final ctrl = TextEditingController();
      final name = await showDialog<String>(
        context: context,
        builder:
            (ctx) => AlertDialog(
              title: const Text('Agregar jugador'),
              content: TextField(
                controller: ctrl,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Nombre del jugador',
                ),
                textCapitalization: TextCapitalization.words,
                onSubmitted: (v) {
                  if (v.trim().isNotEmpty) Navigator.pop(ctx, v.trim());
                },
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancelar'),
                ),
                FilledButton(
                  onPressed: () {
                    final v = ctrl.text.trim();
                    if (v.isNotEmpty) Navigator.pop(ctx, v);
                  },
                  child: const Text('Agregar'),
                ),
              ],
            ),
      );
      WidgetsBinding.instance.addPostFrameCallback((_) => ctrl.dispose());
      if (name == null || !mounted) return;

      try {
        await FirebaseFirestore.instance
            .collection('leagues')
            .doc(widget.leagueId)
            .collection('players')
            .add({'name': name});
        await _load();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Error: $e')));
        }
      }
    }
  }

  Future<void> _removePlayer(LeaguePlayer player) async {
    // Primera confirmación.
    final firstOk = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: const Text('Sacar jugador'),
            content: Text(
              '¿Sacar a ${player.name} de la liga? '
              'Sus resultados ya jugados en fechas cerradas se mantienen.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: Colors.red),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Sacar'),
              ),
            ],
          ),
    );
    if (firstOk != true || !mounted) return;

    // Segunda confirmación con tiempo de espera antes de habilitar el botón.
    const waitSeconds = 3;
    final finalOk = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder:
          (ctx) => StatefulBuilder(
            builder: (ctx, setS) {
              int remaining = waitSeconds;
              Timer.periodic(const Duration(seconds: 1), (t) {
                if (remaining <= 0) {
                  t.cancel();
                  return;
                }
                remaining--;
                setS(() {});
                if (remaining <= 0) t.cancel();
              });
              return AlertDialog(
                title: const Text('Confirmar definitivamente'),
                content: Text(
                  'Esta acción no se puede deshacer. '
                  '${player.name} será eliminado de la liga.',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('Cancelar'),
                  ),
                  FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: Colors.red),
                    onPressed:
                        remaining > 0 ? null : () => Navigator.pop(ctx, true),
                    child: Text(
                      remaining > 0 ? 'Esperá ${remaining}s...' : 'Sacar',
                    ),
                  ),
                ],
              );
            },
          ),
    );
    if (finalOk != true || !mounted) return;

    try {
      await FirebaseFirestore.instance
          .collection('leagues')
          .doc(widget.leagueId)
          .collection('players')
          .doc(player.id)
          .delete();
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${player.name} sacado de la liga')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  // ── Fechas ─────────────────────────────────────────────────────────────────

  Future<void> _addRound() async {
    final nameCtrl = TextEditingController();
    RoundFormat selectedFormat = RoundFormat.racialEdicion;
    DateTime? date;

    final ok = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => StatefulBuilder(
            builder:
                (ctx, setS) => AlertDialog(
                  title: const Text('Nueva fecha'),
                  content: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextField(
                          controller: nameCtrl,
                          autofocus: true,
                          decoration: const InputDecoration(
                            hintText: 'Nombre (ej: Fecha 1)',
                          ),
                          textCapitalization: TextCapitalization.words,
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<RoundFormat>(
                          value: selectedFormat,
                          decoration: const InputDecoration(
                            labelText: 'Tipo de fecha',
                            border: OutlineInputBorder(),
                          ),
                          items:
                              RoundFormat.values
                                  .map(
                                    (f) => DropdownMenuItem(
                                      value: f,
                                      child: Text(f.label),
                                    ),
                                  )
                                  .toList(),
                          onChanged: (v) {
                            if (v != null) setS(() => selectedFormat = v);
                          },
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                date == null
                                    ? 'Sin fecha'
                                    : '${date!.day}/${date!.month}/${date!.year}',
                              ),
                            ),
                            TextButton(
                              onPressed: () async {
                                final picked = await showDatePicker(
                                  context: ctx,
                                  initialDate: DateTime.now(),
                                  firstDate: DateTime(2020),
                                  lastDate: DateTime(2030),
                                );
                                if (picked != null) setS(() => date = picked);
                              },
                              child: const Text('Elegir fecha'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('Cancelar'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('Crear'),
                    ),
                  ],
                ),
          ),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) => nameCtrl.dispose());

    if (ok != true || !mounted) return;

    final roundName =
        nameCtrl.text.trim().isEmpty
            ? 'Fecha ${DateTime.now().millisecondsSinceEpoch}'
            : nameCtrl.text.trim();

    // Congelar las restricciones vigentes evita que una modificación futura
    // de la Ban List reescriba retrospectivamente la legalidad de esta fecha.
    List<Map<String, dynamic>>? banListSnapshot;
    try {
      final service = BanListService.forRoundFormatKey(
        selectedFormat.firestoreKey,
      );
      banListSnapshot = await service.fetchSnapshot();
    } catch (_) {
      // La fecha puede crearse sin conexión a la Ban List. El dashboard usará
      // la lista vigente y marcará que no existe una instantánea histórica.
    }

    try {
      await FirebaseFirestore.instance
          .collection('leagues')
          .doc(widget.leagueId)
          .collection('rounds')
          .add({
            'name': roundName,
            'deckType': selectedFormat.label,
            'roundFormat': selectedFormat.firestoreKey,
            'date': date != null ? Timestamp.fromDate(date!) : null,
            'status': 'open',
            'matches': <Map<String, dynamic>>[],
            if (banListSnapshot != null) ...{
              'banListSnapshot': banListSnapshot,
              'banListCapturedAt': FieldValue.serverTimestamp(),
              'banListSource': 'current',
              'banListFormat': selectedFormat.firestoreKey,
              'banListEntryCount': banListSnapshot.length,
            },
            'createdAt': FieldValue.serverTimestamp(),
          });
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$roundName creada')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Future<void> _fillMissingRoundBanLists() async {
    if (_updatingBanLists) return;
    final roundsRef = FirebaseFirestore.instance
        .collection('leagues')
        .doc(widget.leagueId)
        .collection('rounds');

    try {
      final rounds = await roundsRef.get();
      final missing = rounds.docs
          .where((doc) => doc.data()['banListSnapshot'] is! List)
          .toList(growable: false);

      if (!mounted) return;
      if (missing.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Todas las fechas ya tienen una Ban List guardada'),
          ),
        );
        return;
      }

      final names = missing
          .take(8)
          .map((doc) => (doc.data()['name'] ?? 'Fecha').toString())
          .join(', ');
      final extra = missing.length > 8 ? ' y ${missing.length - 8} más' : '';
      final confirmed = await showDialog<bool>(
        context: context,
        builder:
            (ctx) => AlertDialog(
              title: const Text('Regularizar Ban Lists'),
              content: Text(
                'Se guardará una copia de la Ban List vigente en '
                '${missing.length} fecha(s) sin snapshot:\n\n$names$extra\n\n'
                'Úsalo solo si esas fechas se jugaron con la lista actual. '
                'Las fechas que ya tienen snapshot no se modificarán.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancelar'),
                ),
                FilledButton.icon(
                  onPressed: () => Navigator.pop(ctx, true),
                  icon: const Icon(Icons.shield_outlined),
                  label: const Text('Guardar lista actual'),
                ),
              ],
            ),
      );
      if (confirmed != true || !mounted) return;

      setState(() => _updatingBanLists = true);
      final snapshots = <String, List<Map<String, dynamic>>>{};

      for (final doc in missing) {
        final formatKey = roundBanListFormatKey(doc.data());
        snapshots[formatKey] ??=
            await BanListService.forRoundFormatKey(formatKey).fetchSnapshot();
      }

      var batch = FirebaseFirestore.instance.batch();
      var pending = 0;
      for (final doc in missing) {
        final formatKey = roundBanListFormatKey(doc.data());
        final snapshot = snapshots[formatKey]!;
        batch.update(doc.reference, {
          'banListSnapshot': snapshot,
          'banListCapturedAt': FieldValue.serverTimestamp(),
          'banListSource': 'current_backfill',
          'banListFormat': formatKey,
          'banListEntryCount': snapshot.length,
        });
        pending++;
        if (pending >= 400) {
          await batch.commit();
          batch = FirebaseFirestore.instance.batch();
          pending = 0;
        }
      }
      if (pending > 0) await batch.commit();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Ban List actual guardada en ${missing.length} fecha(s)',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudieron actualizar las fechas: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _updatingBanLists = false);
    }
  }

  Future<void> _showLeagueBanLists() async {
    try {
      final rounds =
          await FirebaseFirestore.instance
              .collection('leagues')
              .doc(widget.leagueId)
              .collection('rounds')
              .get();
      final docs = [...rounds.docs]..sort((a, b) {
        final aData = a.data();
        final bData = b.data();
        final aDate =
            (aData['date'] as Timestamp?) ?? (aData['createdAt'] as Timestamp?);
        final bDate =
            (bData['date'] as Timestamp?) ?? (bData['createdAt'] as Timestamp?);
        return (aDate?.millisecondsSinceEpoch ?? 0).compareTo(
          bDate?.millisecondsSinceEpoch ?? 0,
        );
      });

      if (!mounted) return;
      if (docs.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('La liga todavía no tiene fechas')),
        );
        return;
      }

      final selectedId = await showModalBottomSheet<String>(
        context: context,
        showDragHandle: true,
        builder:
            (ctx) => SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ListTile(
                    leading: const Icon(Icons.shield_outlined),
                    title: const Text(
                      'Ban Lists por fecha',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: const Text(
                      'Selecciona una fecha para ver el snapshot asignado',
                    ),
                  ),
                  const Divider(height: 1),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 480),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: docs.length,
                      itemBuilder: (context, index) {
                        final doc = docs[index];
                        final data = doc.data();
                        final format = roundBanListFormatLabel(data);
                        return ListTile(
                          leading: Icon(
                            readRoundBanListSnapshot(data) == null
                                ? Icons.gpp_maybe_outlined
                                : Icons.gpp_good_outlined,
                          ),
                          title: Text((data['name'] ?? 'Fecha').toString()),
                          subtitle: Text(
                            '$format · ${roundBanListStatusLabel(data)}',
                          ),
                          trailing: const Icon(Icons.chevron_right_rounded),
                          onTap: () => Navigator.pop(ctx, doc.id),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
      );
      if (selectedId == null || !mounted) return;
      final selected = docs.firstWhere((doc) => doc.id == selectedId);
      await showRoundBanListViewer(
        context,
        roundName: (selected.data()['name'] ?? 'Fecha').toString(),
        roundData: selected.data(),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudieron cargar las Ban Lists: $e')),
        );
      }
    }
  }

  Future<void> _finishLeague() async {
    final ok = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: const Text('Finalizar liga'),
            content: const Text(
              'Se marcará la liga como finalizada. No podrás agregar más fechas.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: Colors.red),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Finalizar'),
              ),
            ],
          ),
    );
    if (ok != true || !mounted) return;

    try {
      await FirebaseFirestore.instance
          .collection('leagues')
          .doc(widget.leagueId)
          .update({'status': 'finished'});
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  // ── Standings acumulados ───────────────────────────────────────────────────

  Future<List<LeagueStanding>> _computeStandings() async {
    final roundsSnap =
        await FirebaseFirestore.instance
            .collection('leagues')
            .doc(widget.leagueId)
            .collection('rounds')
            .where('status', isEqualTo: 'finished')
            .get();

    final map = <String, LeagueStanding>{};
    for (final p in _players) {
      map[p.id] = LeagueStanding(player: p);
    }

    for (final rdoc in roundsSnap.docs) {
      final rawMatches = (rdoc.data()['matches'] as List<dynamic>?) ?? [];
      for (final rm in rawMatches) {
        if (rm is! Map<String, dynamic>) continue;
        final m = RoundMatch.fromMap(rm);
        if (!m.hasResult) continue;

        final aId = m.playerAId;
        final bId = m.playerBId;

        map.putIfAbsent(
          aId,
          () => LeagueStanding(
            player: LeaguePlayer(id: aId, name: m.playerAName),
          ),
        );
        if (bId != null) {
          map.putIfAbsent(
            bId,
            () => LeagueStanding(
              player: LeaguePlayer(id: bId, name: m.playerBName ?? bId),
            ),
          );
        }

        {
          map[aId]!.matchesPlayed++;
          if (bId != null) map[bId]!.matchesPlayed++;

          if (m.winnerId == aId) {
            map[aId]!.matchesWon++;
            map[aId]!.points += 3;
            if (bId != null) map[bId]!.matchesLost++;
          } else if (bId != null && m.winnerId == bId) {
            map[bId]!.matchesWon++;
            map[bId]!.points += 3;
            map[aId]!.matchesLost++;
          } else if (bId != null && m.winnerId == 'draw') {
            map[aId]!.matchesDraw++;
            map[aId]!.points += 1;
            map[bId]!.matchesDraw++;
            map[bId]!.points += 1;
          }

          if (m.scoreA != null) {
            map[aId]!.gamesWon += m.scoreA!;
            map[aId]!.gamesLost += m.scoreB ?? 0;
            if (bId != null) {
              map[bId]!.gamesWon += m.scoreB ?? 0;
              map[bId]!.gamesLost += m.scoreA!;
            }
          }
        }
      }
    }

    final list =
        map.values.toList()..sort((a, b) {
          final cp = b.points.compareTo(a.points);
          if (cp != 0) return cp;
          final cd = b.duelWinPct.compareTo(a.duelWinPct);
          if (cd != 0) return cd;
          return b.gameWinPct.compareTo(a.gameWinPct);
        });
    return list;
  }

  void _showStandings() async {
    final standings = await _computeStandings();
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => LeagueStandingsSheet(standings: standings),
    );
  }

  Future<void> _openSettings() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder:
            (_) => LeagueSettingsScreen(
              leagueId: widget.leagueId,
              players: _players,
            ),
      ),
    );
    _load();
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final leagueName = (_league?['name'] as String?) ?? 'Liga';
    final isFinished = (_league?['status'] as String?) == 'finished';
    final description = (_league?['description'] as String?) ?? '';
    final duelsPerMatch = (_league?['duelsPerMatch'] as num?)?.toInt() ?? 3;

    return Scaffold(
      appBar: AppBar(
        title: Text(leagueName),
        actions: [
          if (_isAdmin)
            IconButton(
              icon: const Icon(Icons.settings_rounded),
              tooltip: 'Configuración de liga',
              onPressed: _openSettings,
            ),
          if (_updatingBanLists)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
          if (_isAdmin)
            PopupMenuButton<String>(
              onSelected: (v) {
                if (v == 'finish') _finishLeague();
                if (v == 'fill_ban_lists') _fillMissingRoundBanLists();
              },
              itemBuilder:
                  (_) => [
                    const PopupMenuItem(
                      value: 'fill_ban_lists',
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.shield_outlined),
                        title: Text('Completar Ban Lists faltantes'),
                      ),
                    ),
                    if (!isFinished)
                      const PopupMenuItem(
                        value: 'finish',
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(Icons.flag_outlined, color: Colors.red),
                          title: Text(
                            'Finalizar liga',
                            style: TextStyle(color: Colors.red),
                          ),
                        ),
                      ),
                  ],
            ),
        ],
      ),
      body: Column(
        children: [
          _LeagueOverviewCard(
            leagueId: widget.leagueId,
            playerCount: _players.length,
            isFinished: isFinished,
            isAdmin: _isAdmin,
            onStandings: _showStandings,
            onBanLists: _showLeagueBanLists,
            onAddRound: _addRound,
            onAddPlayer: _addPlayer,
          ),
          // Info banner
          if (description.isNotEmpty || isFinished)
            Container(
              width: double.infinity,
              color:
                  isFinished
                      ? Colors.grey.shade100
                      : Theme.of(
                        context,
                      ).colorScheme.primaryContainer.withValues(alpha: .3),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (isFinished)
                    const Text(
                      'Liga finalizada',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: Colors.grey,
                      ),
                    ),
                  if (description.isNotEmpty) Text(description),
                ],
              ),
            ),

          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Panel jugadores (lateral en ancho, o colapsado en móvil)
                if (MediaQuery.of(context).size.width >= 600)
                  _PlayersPanel(
                    players: _players,
                    isAdmin: _isAdmin,
                    onRemove: _removePlayer,
                  ),

                // Panel principal: fechas
                Expanded(
                  child: _RoundsPanel(
                    leagueId: widget.leagueId,
                    players: _players,
                    isAdmin: _isAdmin,
                    isFinished: isFinished,
                    duelsPerMatch: duelsPerMatch,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LeagueOverviewCard extends StatelessWidget {
  final String leagueId;
  final int playerCount;
  final bool isFinished;
  final bool isAdmin;
  final VoidCallback onStandings;
  final VoidCallback onBanLists;
  final VoidCallback onAddRound;
  final VoidCallback onAddPlayer;

  const _LeagueOverviewCard({
    required this.leagueId,
    required this.playerCount,
    required this.isFinished,
    required this.isAdmin,
    required this.onStandings,
    required this.onBanLists,
    required this.onAddRound,
    required this.onAddPlayer,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream:
          FirebaseFirestore.instance
              .collection('leagues')
              .doc(leagueId)
              .collection('rounds')
              .snapshots(),
      builder: (context, snapshot) {
        final rounds = snapshot.data?.docs ?? [];
        final finished =
            rounds.where((doc) => doc.data()['status'] == 'finished').length;
        var completedDuels = 0;
        var totalDuels = 0;
        for (final round in rounds) {
          final matches = (round.data()['matches'] as List<dynamic>?) ?? [];
          final realMatches = matches.where((raw) {
            if (raw is! Map) return false;
            return raw['playerBId'] != null;
          });
          totalDuels += realMatches.length;
          completedDuels +=
              realMatches.where((raw) => raw['winnerId'] != null).length;
        }

        return Card(
          margin: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 20,
                  runSpacing: 10,
                  children: [
                    _LeagueMetric(
                      icon: Icons.group_outlined,
                      value: '$playerCount',
                      label: 'Jugadores',
                    ),
                    _LeagueMetric(
                      icon: Icons.calendar_month_outlined,
                      value: '$finished/${rounds.length}',
                      label: 'Fechas cerradas',
                    ),
                    _LeagueMetric(
                      icon: Icons.sports_mma_outlined,
                      value: '$completedDuels/$totalDuels',
                      label: 'Duelos listos',
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.icon(
                      onPressed: onStandings,
                      icon: const Icon(Icons.leaderboard_outlined),
                      label: const Text('Posiciones'),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: onBanLists,
                      icon: const Icon(Icons.shield_outlined),
                      label: const Text('Ban Lists'),
                    ),
                    if (isAdmin && !isFinished)
                      FilledButton.tonalIcon(
                        onPressed: onAddRound,
                        icon: const Icon(Icons.add_circle_outline),
                        label: const Text('Nueva fecha'),
                      ),
                    if (isAdmin && !isFinished)
                      OutlinedButton.icon(
                        onPressed: onAddPlayer,
                        icon: const Icon(Icons.person_add_outlined),
                        label: const Text('Agregar jugador'),
                      ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _LeagueMetric extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;

  const _LeagueMetric({
    required this.icon,
    required this.value,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value, style: const TextStyle(fontWeight: FontWeight.w800)),
            Text(label, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ],
    );
  }
}

// ── Panel lateral de jugadores ────────────────────────────────────────────────

class _PlayersPanel extends StatelessWidget {
  final List<LeaguePlayer> players;
  final bool isAdmin;
  final ValueChanged<LeaguePlayer>? onRemove;

  const _PlayersPanel({
    required this.players,
    required this.isAdmin,
    this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 200,
      decoration: BoxDecoration(
        border: Border(
          right: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
            child: Text(
              'Jugadores (${players.length})',
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
            ),
          ),
          if (isAdmin && onRemove != null)
            const Padding(
              padding: EdgeInsets.fromLTRB(12, 0, 12, 6),
              child: Text(
                'Mantené presionado un jugador para sacarlo',
                style: TextStyle(fontSize: 11, color: Colors.grey),
              ),
            ),
          Expanded(
            child:
                players.isEmpty
                    ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: Text(
                        'Sin jugadores',
                        style: TextStyle(color: Colors.grey),
                      ),
                    )
                    : ListView.builder(
                      itemCount: players.length,
                      itemBuilder: (_, i) {
                        final p = players[i];
                        return ListTile(
                          dense: true,
                          title: Text(
                            p.name,
                            style: const TextStyle(fontSize: 13),
                          ),
                          onLongPress:
                              isAdmin && onRemove != null
                                  ? () => onRemove!(p)
                                  : null,
                        );
                      },
                    ),
          ),
        ],
      ),
    );
  }
}

// ── Panel de fechas/rondas ────────────────────────────────────────────────────

class _RoundsPanel extends StatelessWidget {
  final String leagueId;
  final List<LeaguePlayer> players;
  final bool isAdmin;
  final bool isFinished;
  final int duelsPerMatch;

  const _RoundsPanel({
    required this.leagueId,
    required this.players,
    required this.isAdmin,
    required this.isFinished,
    this.duelsPerMatch = 1,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream:
          FirebaseFirestore.instance
              .collection('leagues')
              .doc(leagueId)
              .collection('rounds')
              .orderBy('createdAt')
              .snapshots(),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final docs = snap.data!.docs;
        if (docs.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.calendar_today_outlined,
                  size: 48,
                  color: Colors.grey,
                ),
                const SizedBox(height: 12),
                const Text(
                  'No hay fechas todavía.',
                  style: TextStyle(color: Colors.grey),
                ),
                if (isAdmin && !isFinished) ...[const SizedBox(height: 12)],
              ],
            ),
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.all(12),
          itemCount: docs.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, i) {
            final doc = docs[i];
            final d = doc.data();
            final status = (d['status'] as String?) ?? 'open';
            final deckType = (d['deckType'] as String?) ?? '';
            final ts = d['date'] as Timestamp?;
            final date = ts?.toDate();
            final banSnapshot = d['banListSnapshot'];
            final hasBanSnapshot = banSnapshot is List;
            final banEntryCount =
                (d['banListEntryCount'] as num?)?.toInt() ??
                (hasBanSnapshot ? banSnapshot.length : 0);
            final matches = (d['matches'] as List<dynamic>?) ?? [];
            final realMatches = matches.where(
              (raw) => raw is Map && raw['playerBId'] != null,
            );
            final total = realMatches.length;
            final completed =
                realMatches
                    .where((raw) => raw is Map && raw['winnerId'] != null)
                    .length;

            return Card(
              margin: EdgeInsets.zero,
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor:
                      status == 'finished'
                          ? Colors.green.shade100
                          : Colors.orange.shade100,
                  child: Icon(
                    status == 'finished'
                        ? Icons.check_rounded
                        : Icons.schedule_rounded,
                    color: status == 'finished' ? Colors.green : Colors.orange,
                    size: 20,
                  ),
                ),
                title: Text(
                  (d['name'] as String?) ?? 'Fecha',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: Text(
                  [
                    if (deckType.isNotEmpty) deckType,
                    if (date != null) '${date.day}/${date.month}/${date.year}',
                    '$completed/$total duelos',
                    if (hasBanSnapshot) 'Ban List: $banEntryCount reglas',
                    if (!hasBanSnapshot) 'Ban List sin guardar',
                    if (status == 'finished') 'Finalizada',
                  ].join(' · '),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 28,
                      height: 28,
                      child: CircularProgressIndicator(
                        value: total == 0 ? 0 : completed / total,
                        strokeWidth: 4,
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Icon(Icons.chevron_right_rounded),
                  ],
                ),
                onTap:
                    () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder:
                            (_) => LeagueRoundScreen(
                              leagueId: leagueId,
                              roundId: doc.id,
                              players: players,
                              isAdmin: isAdmin,
                              duelsPerMatch: duelsPerMatch,
                            ),
                      ),
                    ),
              ),
            );
          },
        );
      },
    );
  }
}

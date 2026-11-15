// lib/screens/leagues/team_screen.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'team_models.dart';
import 'team_history.dart';
import 'create_league_screen.dart';
import 'league_detail_screen.dart';
import '../../widgets/async_state_view.dart';
import '../../services/team_service.dart';
import '../team_members_screen.dart';

// ── Lista de teams ────────────────────────────────────────────────────────────

class TeamsListScreen extends StatelessWidget {
  const TeamsListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;

    return Scaffold(
      appBar: AppBar(title: const Text('Teams')),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream:
            FirebaseFirestore.instance
                .collection('teams')
                .orderBy('createdAt', descending: true)
                .snapshots(),
        builder: (context, snap) {
          if (snap.hasError) return ErrorStateView(error: snap.error);
          if (!snap.hasData) {
            return const LoadingStateView(message: 'Cargando teams…');
          }

          final docs = snap.data!.docs;
          if (docs.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.groups_rounded,
                    size: 64,
                    color: Colors.grey,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'No hay teams todavía.',
                    style: TextStyle(color: Colors.grey),
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: () => _openCreate(context),
                    icon: const Icon(Icons.add),
                    label: const Text('Crear team'),
                  ),
                ],
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: docs.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) {
              final doc = docs[i];
              final d = doc.data();
              final ownerUid = (d['ownerId'] ?? d['adminUid'] ?? '').toString();
              final isAdmin = ownerUid == uid;
              return ListTile(
                leading: const CircleAvatar(child: Icon(Icons.groups_rounded)),
                title: Text(
                  (d['name'] as String?) ?? doc.id,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: isAdmin ? const Text('Admin') : null,
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap:
                    () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder:
                            (_) => TeamDetailScreen(
                              teamId: doc.id,
                              teamName: (d['name'] as String?) ?? doc.id,
                              adminUid: ownerUid,
                            ),
                      ),
                    ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openCreate(context),
        tooltip: 'Crear team',
        child: const Icon(Icons.add),
      ),
    );
  }

  void _openCreate(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const CreateTeamScreen()),
    );
  }
}

// ── Crear team ────────────────────────────────────────────────────────────────

class CreateTeamScreen extends StatefulWidget {
  const CreateTeamScreen({super.key});

  @override
  State<CreateTeamScreen> createState() => _CreateTeamScreenState();
}

class _CreateTeamScreenState extends State<CreateTeamScreen> {
  final _nameCtrl = TextEditingController();
  bool _loading = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('El nombre es obligatorio')));
      return;
    }
    setState(() => _loading = true);
    try {
      await TeamService().createTeam(name);
      if (!mounted) return;
      Navigator.pop(context);
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Crear team')),
      body:
          _loading
              ? const Center(child: CircularProgressIndicator())
              : Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    TextField(
                      controller: _nameCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Nombre del team',
                        border: OutlineInputBorder(),
                      ),
                      textCapitalization: TextCapitalization.words,
                      autofocus: true,
                    ),
                    const Spacer(),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: _save,
                        child: const Text('Crear team'),
                      ),
                    ),
                  ],
                ),
              ),
    );
  }
}

// ── Detalle del team: tabla histórica + ligas ─────────────────────────────────

class TeamDetailScreen extends StatefulWidget {
  final String teamId;
  final String teamName;
  final String adminUid;

  const TeamDetailScreen({
    super.key,
    required this.teamId,
    required this.teamName,
    required this.adminUid,
  });

  @override
  State<TeamDetailScreen> createState() => _TeamDetailScreenState();
}

class _TeamDetailScreenState extends State<TeamDetailScreen> {
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _memberSub;
  bool _memberCanManage = false;

  // Admin si el doc tiene adminUid igual al usuario, O si adminUid está vacío
  // (teams creados sin ese campo) y hay un usuario logueado.
  bool get _isAdmin {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    return uid != null && widget.adminUid.isNotEmpty && uid == widget.adminUid;
  }

  bool get _canManage => _isAdmin || _memberCanManage;

  @override
  void initState() {
    super.initState();
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    _memberSub = FirebaseFirestore.instance
        .collection('teams')
        .doc(widget.teamId)
        .collection('members')
        .doc(uid)
        .snapshots()
        .listen((snapshot) {
          final role = snapshot.data()?['role'] as String?;
          final canManage = role == 'owner' || role == 'admin';
          if (mounted && canManage != _memberCanManage) {
            setState(() => _memberCanManage = canManage);
          }
        });
  }

  @override
  void dispose() {
    _memberSub?.cancel();
    super.dispose();
  }

  CollectionReference<Map<String, dynamic>> get _playersRef => FirebaseFirestore
      .instance
      .collection('teams')
      .doc(widget.teamId)
      .collection('players');

  Future<void> _addPlayer() async {
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => _AddPlayerDialog(),
    );
    if (name == null || name.isEmpty || !mounted) return;
    await _playersRef.add({'name': name});
  }

  void _openMembers() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder:
            (_) => TeamMembersScreen(
              teamId: widget.teamId,
              teamName: widget.teamName,
              ownerUid: widget.adminUid,
            ),
      ),
    );
  }

  Future<void> _showStandings() async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    TeamHistoryResult result;
    try {
      result = await computeTeamHistory(widget.teamId);
    } catch (e) {
      if (mounted) Navigator.pop(context);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
      return;
    }
    if (!mounted) return;
    Navigator.pop(context); // cierra el loader

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder:
          (_) => DraggableScrollableSheet(
            initialChildSize: 0.6,
            minChildSize: 0.35,
            maxChildSize: 0.92,
            expand: false,
            builder:
                (_, ctrl) => Column(
                  children: [
                    Container(
                      margin: const EdgeInsets.only(top: 10, bottom: 4),
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.fromLTRB(16, 8, 16, 12),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Tabla histórica',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: SingleChildScrollView(
                        controller: ctrl,
                        scrollDirection: Axis.horizontal,
                        child: SingleChildScrollView(
                          child: _StandingsTable(rows: result.rows),
                        ),
                      ),
                    ),
                  ],
                ),
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isAdmin = _canManage;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.teamName),
        actions: [
          StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream:
                FirebaseFirestore.instance
                    .collection('teams')
                    .doc(widget.teamId)
                    .collection('members')
                    .doc(FirebaseAuth.instance.currentUser!.uid)
                    .snapshots(),
            builder: (context, snapshot) {
              final role = snapshot.data?.data()?['role'];
              final canManage = isAdmin || role == 'owner' || role == 'admin';
              if (!canManage) return const SizedBox.shrink();
              return IconButton(
                icon: const Icon(Icons.manage_accounts_outlined),
                tooltip: 'Gestionar integrantes',
                onPressed: _openMembers,
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.table_rows_rounded),
            tooltip: 'Tabla histórica',
            onPressed: _showStandings,
          ),
          if (isAdmin)
            IconButton(
              icon: const Icon(Icons.person_add_rounded),
              tooltip: 'Agregar jugador',
              onPressed: _addPlayer,
            ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _playersRef.orderBy('name').snapshots(),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final players =
              snap.data!.docs
                  .map((d) => TeamPlayer.fromMap(d.id, d.data()))
                  .toList();

          return CustomScrollView(
            slivers: [
              // ── Ligas de este team ──────────────────────────────────────
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 24, 16, 4),
                  child: Row(
                    children: [
                      const Icon(Icons.emoji_events_rounded, size: 16),
                      const SizedBox(width: 6),
                      const Text(
                        'Ligas',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                      const Spacer(),
                      if (isAdmin)
                        FilledButton.icon(
                          onPressed:
                              () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder:
                                      (_) => CreateLeagueScreen(
                                        teamId: widget.teamId,
                                        teamPlayers: players,
                                      ),
                                ),
                              ),
                          icon: const Icon(Icons.add, size: 16),
                          label: const Text('Nueva liga'),
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),

              _LeaguesSliver(teamId: widget.teamId),

              const SliverToBoxAdapter(child: SizedBox(height: 32)),
            ],
          );
        },
      ),
    );
  }
}

// ── Ligas del team (sliver) ───────────────────────────────────────────────────

class _AddPlayerDialog extends StatefulWidget {
  @override
  State<_AddPlayerDialog> createState() => _AddPlayerDialogState();
}

class _AddPlayerDialogState extends State<_AddPlayerDialog> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Agregar jugador'),
      content: TextField(
        controller: _ctrl,
        decoration: const InputDecoration(
          labelText: 'Nombre del jugador',
          border: OutlineInputBorder(),
        ),
        autofocus: true,
        textCapitalization: TextCapitalization.words,
        onSubmitted: (v) => Navigator.pop(context, v.trim()),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _ctrl.text.trim()),
          child: const Text('Agregar'),
        ),
      ],
    );
  }
}

class _LeaguesSliver extends StatelessWidget {
  final String teamId;
  const _LeaguesSliver({required this.teamId});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream:
          FirebaseFirestore.instance
              .collection('leagues')
              .where('teamId', isEqualTo: teamId)
              .snapshots(),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const SliverToBoxAdapter(
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final docs =
            snap.data!.docs.toList()..sort((a, b) {
              final ao = (a.data()['leagueOrder'] as num?)?.toInt();
              final bo = (b.data()['leagueOrder'] as num?)?.toInt();
              if (ao != null || bo != null) {
                // Las ligas actuales que todavía no tienen número quedan
                // primero; luego se ordenan las históricas 5, 4, 3...
                return (bo ?? 1 << 30).compareTo(ao ?? 1 << 30);
              }
              final at = a.data()['createdAt'] as Timestamp?;
              final bt = b.data()['createdAt'] as Timestamp?;
              return (bt?.millisecondsSinceEpoch ?? 0).compareTo(
                at?.millisecondsSinceEpoch ?? 0,
              );
            });
        if (docs.isEmpty) {
          return const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Center(
                child: Text(
                  'No hay ligas para este team todavía.',
                  style: TextStyle(color: Colors.grey),
                ),
              ),
            ),
          );
        }
        return SliverList(
          delegate: SliverChildBuilderDelegate((context, i) {
            final doc = docs[i];
            final d = doc.data();
            final isAdmin = d['adminUid'] == uid;
            final status = (d['status'] as String?) ?? 'active';
            final season = (d['season'] as String?) ?? '';
            return ListTile(
              leading: CircleAvatar(
                backgroundColor:
                    status == 'finished'
                        ? Colors.grey.shade300
                        : Theme.of(context).colorScheme.primaryContainer,
                child: Icon(
                  Icons.emoji_events_rounded,
                  color:
                      status == 'finished'
                          ? Colors.grey
                          : Theme.of(context).colorScheme.primary,
                ),
              ),
              title: Text(
                (d['name'] as String?) ?? 'Liga sin nombre',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: Text(
                [
                  if (d['isHistorical'] == true) 'Histórica',
                  if (d['leagueOrder'] != null) 'Liga ${d['leagueOrder']}',
                  if (season.isNotEmpty) 'Temporada $season',
                  if (isAdmin) 'Admin',
                  if (status == 'finished') 'Finalizada',
                ].join(' · '),
              ),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap:
                  () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => LeagueDetailScreen(leagueId: doc.id),
                    ),
                  ),
            );
          }, childCount: docs.length),
        );
      },
    );
  }
}

// ── Tabla de posiciones ───────────────────────────────────────────────────────

class _StandingsTable extends StatelessWidget {
  final List<TeamHistoryRow> rows;

  const _StandingsTable({required this.rows});

  @override
  Widget build(BuildContext context) {
    return Table(
      defaultColumnWidth: const IntrinsicColumnWidth(),
      border: TableBorder.all(
        color: Theme.of(context).dividerColor,
        borderRadius: BorderRadius.circular(10),
      ),
      children: [
        TableRow(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
          ),
          children: [
            _th('#'),
            _th('Jugador', left: true),
            _th('Pts'),
            _th('J'),
            _th('G'),
            _th('P'),
            _th('E'),
            _th('Dif.F'),
            _th('Dif.C'),
            _th('Dif'),
            _th('%Pts'),
            _th('%Vict'),
          ],
        ),
        ...List.generate(rows.length, (i) {
          final p = rows[i];
          final diff = p.diff;
          final diffStr = diff > 0 ? '+$diff' : '$diff';
          final diffColor =
              diff > 0
                  ? Colors.green
                  : diff < 0
                  ? Colors.red
                  : Colors.grey;
          return TableRow(
            decoration: BoxDecoration(
              color:
                  i.isEven
                      ? Colors.transparent
                      : Theme.of(context).colorScheme.surfaceContainerHighest
                          .withValues(alpha: .3),
            ),
            children: [
              _td(
                '${i + 1}',
                bold: i < 3,
                color:
                    i == 0
                        ? Colors.amber
                        : i == 1
                        ? Colors.grey
                        : i == 2
                        ? const Color(0xFFB87333)
                        : null,
              ),
              _tdLeft(p.name, bold: true),
              _td(
                '${p.points}',
                bold: true,
                color: Theme.of(context).colorScheme.primary,
              ),
              _td('${p.matchesPlayed}'),
              _td('${p.matchesWon}'),
              _td('${p.matchesLost}'),
              _td('${p.matchesDraw}'),
              _td('${p.gamesFavor}'),
              _td('${p.gamesAgainst}'),
              _td(diffStr, color: diffColor, bold: true),
              _td('${p.ptsPct.toStringAsFixed(1)}%', color: Colors.grey),
              _td(
                '${p.winPct.toStringAsFixed(1)}%',
                bold: true,
                color: Theme.of(context).colorScheme.primary,
              ),
            ],
          );
        }),
      ],
    );
  }

  Widget _th(String label, {bool left = false}) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    child: Text(
      label,
      textAlign: left ? TextAlign.left : TextAlign.center,
      style: const TextStyle(
        fontWeight: FontWeight.w700,
        fontSize: 11,
        letterSpacing: .04,
      ),
    ),
  );

  Widget _td(String text, {bool bold = false, Color? color}) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
    child: Text(
      text,
      textAlign: TextAlign.center,
      style: TextStyle(
        fontWeight: bold ? FontWeight.w700 : FontWeight.normal,
        fontSize: 13,
        color: color,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    ),
  );

  Widget _tdLeft(String text, {bool bold = false}) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
    child: Text(
      text,
      style: TextStyle(
        fontWeight: bold ? FontWeight.w700 : FontWeight.normal,
        fontSize: 13,
      ),
    ),
  );
}

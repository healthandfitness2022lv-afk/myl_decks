import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/team_service.dart';
import 'team_detail_screen.dart';

class TeamsScreen extends StatefulWidget {
  const TeamsScreen({super.key});

  @override
  State<TeamsScreen> createState() => _TeamsScreenState();
}

class _TeamsScreenState extends State<TeamsScreen> {
  final _svc = TeamService();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Teams')),
      floatingActionButton: PopupMenuButton<String>(
        icon: const Icon(Icons.add),
        onSelected: (v) => v == 'create' ? _createTeam() : _joinTeam(),
        itemBuilder: (_) => const [
          PopupMenuItem(value: 'create', child: Text('Crear equipo')),
          PopupMenuItem(value: 'join', child: Text('Unirse por código')),
        ],
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _svc.myTeams(),
        builder: (ctx, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final docs = snap.data?.docs ?? [];
          if (docs.isEmpty) {
            return Center(
              child: Text('Aún no perteneces a ningún Team', style: TextStyle(color: cs.onSurfaceVariant)),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: docs.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (_, i) {
              final teamId = docs[i].id;
              final role = docs[i].data()['role'] ?? 'member';
              return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
  stream: _svc.team(teamId),
  builder: (_, tSnap) {
    final map = tSnap.data?.data();          // 👈 obtener el Map
    final name = map?['name'] ?? 'Team';     // 👈 usar el Map
    final code = map?['inviteCode'] ?? '';
                  return ListTile(
                    tileColor: cs.surfaceContainerLowest,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    title: Text(name, style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text('Rol: $role  •  Código: $code'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => TeamDetailScreen(teamId: teamId)),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _createTeam() async {
    final ctrl = TextEditingController();
    final name = await showDialog<String?>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Nuevo equipo'),
        content: TextField(controller: ctrl, decoration: const InputDecoration(hintText: 'Nombre del equipo')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, ctrl.text.trim()), child: const Text('Crear')),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    final id = await _svc.createTeam(name);
    if (!mounted) return;
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => TeamDetailScreen(teamId: id)));
  }

  Future<void> _joinTeam() async {
    final ctrl = TextEditingController();
    final code = await showDialog<String?>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Unirse a un Team'),
        content: TextField(
          controller: ctrl,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(hintText: 'Código de invitación (6)'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, ctrl.text.trim()), child: const Text('Unirse')),
        ],
      ),
    );
    if (code == null || code.isEmpty) return;
    final teamId = await _svc.joinByCode(code);
    if (!mounted) return;
    if (teamId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Código inválido')));
    } else {
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => TeamDetailScreen(teamId: teamId)));
    }
  }
}

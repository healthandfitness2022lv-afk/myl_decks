import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/team_service.dart';

class TeamDetailScreen extends StatelessWidget {
  final String teamId;
  const TeamDetailScreen({super.key, required this.teamId});

  @override
  Widget build(BuildContext context) {
    final svc = TeamService();
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
  stream: svc.team(teamId),
  builder: (_, s) {
    final map = s.data?.data();              // 👈 obtener el Map
    return Text(map?['name'] ?? 'Team');     // 👈 usar el Map
  },
),
        actions: [
          IconButton(
            icon: const Icon(Icons.exit_to_app),
            tooltip: 'Salir del Team',
            onPressed: () async {
              try {
                await svc.leaveTeam(teamId);
                if (context.mounted) Navigator.pop(context);
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(e.toString())),
                  );
                }
              }
            },
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: svc.members(teamId),
        builder: (_, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final members = snap.data?.docs ?? [];
          if (members.isEmpty) {
            return Center(child: Text('Sin miembros', style: TextStyle(color: cs.onSurfaceVariant)));
          }
          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: members.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (_, i) {
              final m = members[i].data();
              return ListTile(
                leading: CircleAvatar(
                  backgroundImage: (m['photoUrl'] ?? '').toString().isNotEmpty
                      ? NetworkImage(m['photoUrl'])
                      : null,
                  child: (m['photoUrl'] ?? '').toString().isEmpty ? const Icon(Icons.person) : null,
                ),
                title: Text(m['displayName']?.toString().isNotEmpty == true ? m['displayName'] : members[i].id),
                subtitle: Text('Rol: ${m['role']}'),
              );
            },
          );
        },
      ),
    );
  }
}

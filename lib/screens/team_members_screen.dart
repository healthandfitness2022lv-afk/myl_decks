import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/team.dart';
import '../services/team_service.dart';
import '../utils/text_normalize.dart';
import '../widgets/async_state_view.dart';

class TeamMembersScreen extends StatefulWidget {
  final String teamId;
  final String teamName;
  final String ownerUid;

  const TeamMembersScreen({
    super.key,
    required this.teamId,
    required this.teamName,
    required this.ownerUid,
  });

  @override
  State<TeamMembersScreen> createState() => _TeamMembersScreenState();
}

class _TeamMembersScreenState extends State<TeamMembersScreen> {
  final _service = TeamService();
  String get _uid => FirebaseAuth.instance.currentUser!.uid;
  bool get _isOwner => _uid == widget.ownerUid;

  @override
  void initState() {
    super.initState();
    _service.ensureOwnerMembership(widget.teamId);
  }

  Future<void> _addMember() async {
    final members =
        await FirebaseFirestore.instance
            .collection('teams')
            .doc(widget.teamId)
            .collection('members')
            .get();
    if (!mounted) return;
    final existingIds = members.docs.map((doc) => doc.id).toSet();
    final userId = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _UserPickerSheet(existingIds: existingIds),
    );
    if (userId == null || !mounted) return;
    await _run(
      () => _service.addMember(widget.teamId, userId),
      success: 'Integrante agregado',
    );
  }

  Future<void> _changeRole(TeamMember member, String role) async {
    await _run(
      () => _service.changeMemberRole(widget.teamId, member.uid, role),
      success: 'Rol actualizado',
    );
  }

  Future<void> _remove(TeamMember member) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Quitar del team'),
            content: Text('¿Quitar a ${member.displayName}?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Quitar'),
              ),
            ],
          ),
    );
    if (confirmed != true || !mounted) return;
    await _run(() => _service.removeMember(widget.teamId, member.uid));
  }

  Future<void> _transfer(TeamMember member) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Transferir propiedad'),
            content: Text(
              '${member.displayName} pasará a ser propietario. Tú quedarás como administrador.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Transferir'),
              ),
            ],
          ),
    );
    if (confirmed != true || !mounted) return;
    await _run(
      () => _service.transferOwnership(widget.teamId, member.uid),
      success: 'Propiedad transferida',
    );
    if (mounted) Navigator.pop(context);
  }

  Future<void> _run(Future<void> Function() action, {String? success}) async {
    try {
      await action();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(success ?? 'Integrantes actualizados')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('No se pudo completar: $error')));
    }
  }

  String _roleLabel(TeamRole role) => switch (role) {
    TeamRole.owner => 'Propietario',
    TeamRole.admin => 'Administrador',
    TeamRole.captain => 'Capitán',
    TeamRole.member => 'Miembro',
  };

  void _handleMemberAction(TeamMember member, String value) {
    if (value == 'remove') {
      _remove(member);
    } else if (value == 'transfer') {
      _transfer(member);
    } else {
      _changeRole(member, value);
    }
  }

  @override
  Widget build(BuildContext context) {
    final members = FirebaseFirestore.instance
        .collection('teams')
        .doc(widget.teamId)
        .collection('members');
    return Scaffold(
      appBar: AppBar(title: const Text('Integrantes')),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: members.snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) return ErrorStateView(error: snapshot.error);
          if (!snapshot.hasData) {
            return const LoadingStateView(message: 'Cargando integrantes…');
          }
          final values =
              snapshot.data!.docs.map(TeamMember.fromSnapshot).toList();
          values.sort((a, b) {
            final roleOrder = {
              TeamRole.owner: 0,
              TeamRole.admin: 1,
              TeamRole.captain: 2,
              TeamRole.member: 3,
            };
            final byRole = roleOrder[a.role]!.compareTo(roleOrder[b.role]!);
            return byRole != 0
                ? byRole
                : a.displayName.compareTo(b.displayName);
          });
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1100),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Wrap(
                          spacing: 16,
                          runSpacing: 16,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            CircleAvatar(
                              radius: 28,
                              child: Text('${values.length}'),
                            ),
                            SizedBox(
                              width: 480,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    widget.teamName,
                                    style: Theme.of(context)
                                        .textTheme
                                        .headlineSmall
                                        ?.copyWith(fontWeight: FontWeight.w800),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${values.length} integrante${values.length == 1 ? '' : 's'} · Administra roles y accesos del team',
                                    style:
                                        Theme.of(context).textTheme.bodyMedium,
                                  ),
                                ],
                              ),
                            ),
                            FilledButton.icon(
                              onPressed: _addMember,
                              icon: const Icon(Icons.person_add_outlined),
                              label: const Text('Agregar integrante'),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Miembros del team',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Expanded(
                      child:
                          values.isEmpty
                              ? EmptyStateView(
                                icon: Icons.group_add_outlined,
                                title: 'Agrega el primer integrante',
                                message:
                                    'Busca usuarios de la app y asígnales un rol dentro del team.',
                                actionLabel: 'Buscar usuarios',
                                onAction: _addMember,
                              )
                              : LayoutBuilder(
                                builder: (context, constraints) {
                                  final columns =
                                      constraints.maxWidth >= 900
                                          ? 3
                                          : constraints.maxWidth >= 580
                                          ? 2
                                          : 1;
                                  return GridView.builder(
                                    gridDelegate:
                                        SliverGridDelegateWithFixedCrossAxisCount(
                                          crossAxisCount: columns,
                                          mainAxisSpacing: 12,
                                          crossAxisSpacing: 12,
                                          mainAxisExtent: 112,
                                        ),
                                    itemCount: values.length,
                                    itemBuilder: (context, index) {
                                      final member = values[index];
                                      return _MemberCard(
                                        member: member,
                                        roleLabel: _roleLabel(member.role),
                                        isOwner: _isOwner,
                                        onAction:
                                            (value) => _handleMemberAction(
                                              member,
                                              value,
                                            ),
                                      );
                                    },
                                  );
                                },
                              ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _MemberCard extends StatelessWidget {
  final TeamMember member;
  final String roleLabel;
  final bool isOwner;
  final ValueChanged<String> onAction;

  const _MemberCard({
    required this.member,
    required this.roleLabel,
    required this.isOwner,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final isTeamOwner = member.role == TeamRole.owner;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            CircleAvatar(
              radius: 25,
              backgroundImage:
                  member.photoUrl.isEmpty
                      ? null
                      : NetworkImage(member.photoUrl),
              child:
                  member.photoUrl.isEmpty
                      ? Text(member.displayName.characters.first.toUpperCase())
                      : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    member.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 6),
                  Chip(
                    avatar: Icon(
                      isTeamOwner
                          ? Icons.workspace_premium_outlined
                          : Icons.shield_outlined,
                      size: 16,
                    ),
                    label: Text(roleLabel),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            ),
            if (!isTeamOwner)
              PopupMenuButton<String>(
                tooltip: 'Administrar integrante',
                onSelected: onAction,
                itemBuilder:
                    (context) => [
                      if (isOwner)
                        const PopupMenuItem(
                          value: 'admin',
                          child: Text('Hacer administrador'),
                        ),
                      const PopupMenuItem(
                        value: 'captain',
                        child: Text('Hacer capitán'),
                      ),
                      const PopupMenuItem(
                        value: 'member',
                        child: Text('Hacer miembro'),
                      ),
                      if (isOwner)
                        const PopupMenuItem(
                          value: 'transfer',
                          child: Text('Transferir propiedad'),
                        ),
                      const PopupMenuDivider(),
                      const PopupMenuItem(
                        value: 'remove',
                        child: Text('Quitar del team'),
                      ),
                    ],
              ),
          ],
        ),
      ),
    );
  }
}

class _UserPickerSheet extends StatefulWidget {
  final Set<String> existingIds;
  const _UserPickerSheet({required this.existingIds});

  @override
  State<_UserPickerSheet> createState() => _UserPickerSheetState();
}

class _UserPickerSheetState extends State<_UserPickerSheet> {
  final _searchController = TextEditingController();
  late final Future<List<_AppUserOption>> _usersFuture = _loadUsers();
  String _query = '';

  Future<List<_AppUserOption>> _loadUsers() async {
    final snapshot =
        await FirebaseFirestore.instance.collection('users').limit(300).get();
    final users =
        snapshot.docs
            .where((doc) => !widget.existingIds.contains(doc.id))
            .map(_AppUserOption.fromSnapshot)
            .toList();
    users.sort(
      (a, b) =>
          a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()),
    );
    return users;
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FractionallySizedBox(
      heightFactor: .88,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Agregar integrante',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: _searchController,
              autofocus: true,
              onChanged:
                  (value) => setState(() => _query = normalizeSearch(value)),
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Buscar por nombre o usuario',
              ),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: FutureBuilder<List<_AppUserOption>>(
              future: _usersFuture,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return ErrorStateView(error: snapshot.error);
                }
                if (!snapshot.hasData) {
                  return const LoadingStateView(message: 'Buscando usuarios…');
                }
                final filtered =
                    snapshot.data!.where((user) {
                      if (_query.isEmpty) return true;
                      return user.searchText.contains(_query);
                    }).toList();
                if (filtered.isEmpty) {
                  return const EmptyStateView(
                    icon: Icons.person_search_outlined,
                    title: 'No encontramos usuarios',
                    message: 'Prueba con otro nombre o usuario.',
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 24),
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final user = filtered[index];
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundImage:
                            user.photoUrl.isEmpty
                                ? null
                                : NetworkImage(user.photoUrl),
                        child:
                            user.photoUrl.isEmpty ? Text(user.initial) : null,
                      ),
                      title: Text(user.displayName),
                      subtitle:
                          user.username.isEmpty
                              ? null
                              : Text('@${user.username}'),
                      trailing: const Icon(Icons.add_circle_outline),
                      onTap: () => Navigator.pop(context, user.uid),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _AppUserOption {
  final String uid;
  final String displayName;
  final String username;
  final String photoUrl;
  final String email;

  const _AppUserOption({
    required this.uid,
    required this.displayName,
    required this.username,
    required this.photoUrl,
    required this.email,
  });

  factory _AppUserOption.fromSnapshot(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    final data = snapshot.data() ?? const <String, dynamic>{};
    return _AppUserOption(
      uid: snapshot.id,
      displayName:
          (data['displayName'] ?? data['username'] ?? 'Usuario').toString(),
      username: (data['username'] ?? '').toString(),
      photoUrl: (data['photoUrl'] ?? '').toString(),
      email: (data['email'] ?? '').toString(),
    );
  }

  String get initial =>
      displayName.isEmpty ? 'U' : displayName[0].toUpperCase();
  String get searchText => normalizeSearch('$displayName $username $email');
}

// lib/screens/admin_users_screen.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

class AdminUsersScreen extends StatefulWidget {
  const AdminUsersScreen({super.key});

  @override
  State<AdminUsersScreen> createState() => _AdminUsersScreenState();
}

class _AdminUsersScreenState extends State<AdminUsersScreen> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  Future<void> _applyChange(
    String targetUid,
    String newRole,
    DateTime? expiresAt,
  ) async {
    try {
      final Map<String, dynamic> payload = {
        'role': newRole,
        'updatedAt': FieldValue.serverTimestamp(),
      };

      if (newRole == 'pro') {
        payload['proSince'] = FieldValue.serverTimestamp();
        if (expiresAt != null) {
          payload['subscriptionExpires'] = Timestamp.fromDate(expiresAt);
        } else {
          payload['subscriptionExpires'] = FieldValue.delete();
        }
      } else {
        payload['subscriptionExpires'] = FieldValue.delete();
        if (newRole != 'pro') payload.remove('proSince');
      }

      await _db.collection('users').doc(targetUid).update(payload);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Rol actualizado a "$newRole" correctamente')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error al actualizar: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Administrar usuarios')),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream:
            _db
                .collection('users')
                .orderBy('createdAt', descending: false)
                .snapshots(),
        builder: (context, snap) {
          if (snap.hasError) return Center(child: Text('Error: ${snap.error}'));
          if (!snap.hasData)
            return const Center(child: CircularProgressIndicator());

          final docs = snap.data!.docs;
          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: docs.length,
            separatorBuilder: (_, __) => const Divider(),
            itemBuilder: (context, index) {
              final doc = docs[index];
              final data = doc.data();
              final username =
                  (data['username'] ?? data['displayName'] ?? '(sin nombre)')
                      as String;
              final email = data['email'] as String?;
              final role = (data['role'] ?? 'basico') as String;
              final expiryRaw = data['subscriptionExpires'];
              DateTime? expiry;
              if (expiryRaw is Timestamp)
                expiry = expiryRaw.toDate();
              else if (expiryRaw is int)
                expiry = DateTime.fromMillisecondsSinceEpoch(expiryRaw);
              else
                expiry = null;

              return _UserRow(
                uid: doc.id,
                username: username,
                email: email,
                currentRole: role,
                currentExpiry: expiry,
                onApply:
                    (newRole, newExpiry) =>
                        _applyChange(doc.id, newRole, newExpiry),
              );
            },
          );
        },
      ),
    );
  }
}

class _UserRow extends StatefulWidget {
  final String uid;
  final String username;
  final String? email;
  final String currentRole;
  final DateTime? currentExpiry;
  final void Function(String newRole, DateTime? newExpiry) onApply;

  const _UserRow({
    required this.uid,
    required this.username,
    this.email,
    required this.currentRole,
    this.currentExpiry,
    required this.onApply,
  });

  @override
  State<_UserRow> createState() => _UserRowState();
}

class _UserRowState extends State<_UserRow> {
  late String _role;
  DateTime? _expiry;

  final DateFormat _fmt = DateFormat('yyyy-MM-dd');

  @override
  void initState() {
    super.initState();
    _role = widget.currentRole;
    _expiry = widget.currentExpiry;
  }

  Future<void> _pickExpiry() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _expiry ?? now.add(const Duration(days: 30)),
      firstDate: now,
      lastDate: DateTime(now.year + 10),
    );
    if (picked != null) setState(() => _expiry = picked);
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: CircleAvatar(
        child: Text(
          widget.username.isNotEmpty ? widget.username[0].toUpperCase() : '?',
        ),
      ),
      title: Text(widget.username),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.email != null) Text(widget.email!),
          const SizedBox(height: 6),
          // Fila 1: rol de app + expiración
          Row(
            children: [
              const Text(
                'Rol: ',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(width: 6),
              DropdownButton<String>(
                value: _role,
                items: const [
                  DropdownMenuItem(value: 'basico', child: Text('Básico')),
                  DropdownMenuItem(value: 'pro', child: Text('Pro')),
                  DropdownMenuItem(
                    value: 'administrador',
                    child: Text('Administrador'),
                  ),
                ],
                onChanged: (v) {
                  if (v == null) return;
                  setState(() => _role = v);
                },
              ),
              const SizedBox(width: 16),
              const Text(
                'Expira: ',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(width: 6),
              GestureDetector(
                onTap: _pickExpiry,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade900,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: Text(
                    _expiry != null ? _fmt.format(_expiry!) : 'Sin expiración',
                    style: const TextStyle(color: Colors.white70),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
      trailing: ElevatedButton(
        onPressed: () => widget.onApply(_role, _expiry),
        child: const Text('Aplicar'),
      ),
    );
  }
}

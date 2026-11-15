// lib/screens/leagues/create_league_screen.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'team_models.dart';

class CreateLeagueScreen extends StatefulWidget {
  final String teamId;
  final List<TeamPlayer> teamPlayers;

  const CreateLeagueScreen({
    super.key,
    required this.teamId,
    required this.teamPlayers,
  });

  @override
  State<CreateLeagueScreen> createState() => _CreateLeagueScreenState();
}

class _CreateLeagueScreenState extends State<CreateLeagueScreen> {
  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _seasonCtrl = TextEditingController();

  late final Set<String> _selectedPlayerIds;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    // Todos seleccionados por defecto
    _selectedPlayerIds = widget.teamPlayers.map((p) => p.id).toSet();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _seasonCtrl.dispose();
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
    if (_selectedPlayerIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Seleccioná al menos un jugador')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final uid = FirebaseAuth.instance.currentUser!.uid;
      final db = FirebaseFirestore.instance;

      final leagueRef = await db.collection('leagues').add({
        'name': name,
        'description': _descCtrl.text.trim(),
        'season': _seasonCtrl.text.trim(),
        'adminUid': uid,
        'teamId': widget.teamId,
        'status': 'active',
        'createdAt': FieldValue.serverTimestamp(),
      });

      final selected =
          widget.teamPlayers
              .where((p) => _selectedPlayerIds.contains(p.id))
              .toList();

      final batch = db.batch();

      for (final p in selected) {
        batch.set(leagueRef.collection('players').doc(p.id), {'name': p.name});
      }

      await batch.commit();

      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Liga creada')));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Nueva liga'),
        actions: [
          if (_saving)
            const Padding(
              padding: EdgeInsets.only(right: 12),
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            TextButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.check_rounded),
              label: const Text('Crear'),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _nameCtrl,
            decoration: const InputDecoration(
              labelText: 'Nombre de la liga',
              border: OutlineInputBorder(),
            ),
            textCapitalization: TextCapitalization.words,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _seasonCtrl,
            decoration: const InputDecoration(
              labelText: 'Temporada (ej: 2025, T1…)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _descCtrl,
            decoration: const InputDecoration(
              labelText: 'Descripción (opcional)',
              border: OutlineInputBorder(),
            ),
            maxLines: 2,
          ),

          const SizedBox(height: 24),

          Row(
            children: [
              const Text(
                'Jugadores que participan',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
              ),
              const Spacer(),
              TextButton(
                onPressed:
                    () => setState(() {
                      if (_selectedPlayerIds.length ==
                          widget.teamPlayers.length) {
                        _selectedPlayerIds.clear();
                      } else {
                        _selectedPlayerIds.addAll(
                          widget.teamPlayers.map((p) => p.id),
                        );
                      }
                    }),
                child: Text(
                  _selectedPlayerIds.length == widget.teamPlayers.length
                      ? 'Deseleccionar todos'
                      : 'Seleccionar todos',
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          if (widget.teamPlayers.isEmpty)
            const Text(
              'Este team no tiene jugadores todavía.',
              style: TextStyle(color: Colors.grey),
            )
          else
            Card(
              child: Column(
                children:
                    widget.teamPlayers.map((p) {
                      final selected = _selectedPlayerIds.contains(p.id);
                      return CheckboxListTile(
                        dense: true,
                        value: selected,
                        title: Text(p.name),
                        onChanged:
                            (v) => setState(() {
                              if (v == true) {
                                _selectedPlayerIds.add(p.id);
                              } else {
                                _selectedPlayerIds.remove(p.id);
                              }
                            }),
                      );
                    }).toList(),
              ),
            ),

          const SizedBox(height: 32),
          FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: const Icon(Icons.add_rounded),
            label: const Text('Crear liga'),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

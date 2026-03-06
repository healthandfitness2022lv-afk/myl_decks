import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../services/deck_service.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late final String _uid;
  late final DeckService _deckService;

  bool _uploading = false;
  int? _deckCount;

  @override
  void initState() {
    super.initState();
    final user = FirebaseAuth.instance.currentUser!;
    _uid = user.uid;
    _deckService = DeckService(_uid);
    _loadDeckCount();
  }

  Future<void> _loadDeckCount() async {
    try {
      final n = await _deckService.countDecks(); // Implementa si no existe
      if (mounted) setState(() => _deckCount = n);
    } catch (_) {
      if (mounted) setState(() => _deckCount = 0);
    }
  }

  /// Sube imagen a Firebase Storage y guarda photoUrl en users/{uid}
  Future<void> _pickAndUploadAvatar() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery, imageQuality: 90);
    if (picked == null) return;

    setState(() => _uploading = true);
    try {
      final file = File(picked.path);
      final ref = FirebaseStorage.instance
          .ref()
          .child('profile_avatars')
          .child('$_uid.jpg');

      await ref.putFile(file, SettableMetadata(contentType: 'image/jpeg'));
      final url = await ref.getDownloadURL();

      await FirebaseFirestore.instance.collection('users').doc(_uid).set(
        {'photoUrl': url},
        SetOptions(merge: true),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Foto actualizada')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al subir foto: $e')),
      );
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  double _computeWinRate(int wins, int losses) {
    final total = wins + losses;
    if (total == 0) return 0.0;
    return wins / total;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection('users').doc(_uid).snapshots(),
      builder: (context, snap) {
        final data = snap.data?.data() ?? {};
        final name = (data['displayName'] as String?) ?? 'Jugador';
        final email = (data['email'] as String?) ?? FirebaseAuth.instance.currentUser?.email ?? '';
        final photoUrl = (data['photoUrl'] as String?);
        final wins = (data['wins'] is int) ? data['wins'] as int : (data['wins'] ?? 0).toInt();
        final losses = (data['losses'] is int) ? data['losses'] as int : (data['losses'] ?? 0).toInt();

        final winRate = _computeWinRate(wins, losses);
        final totalGames = wins + losses;

        return Scaffold(
          appBar: AppBar(
            title: const Text('Perfil'),
            centerTitle: true,
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 24, 16, 24),
            children: [
              // Header con avatar + nombre
              Center(
                child: Column(
                  children: [
                    Stack(
                      children: [
                        CircleAvatar(
                          radius: 56,
                          backgroundColor: cs.surfaceContainerHighest,
                          backgroundImage: (photoUrl != null && photoUrl.isNotEmpty)
                              ? NetworkImage(photoUrl)
                              : null,
                          child: (photoUrl == null || photoUrl.isEmpty)
                              ? Icon(Icons.person, size: 56, color: cs.onSurfaceVariant)
                              : null,
                        ),
                        Positioned(
                          right: 0,
                          bottom: 0,
                          child: Tooltip(
                            message: 'Cambiar foto',
                            child: InkWell(
                              onTap: _uploading ? null : _pickAndUploadAvatar,
                              borderRadius: BorderRadius.circular(24),
                              child: Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: _uploading ? cs.surfaceVariant : cs.primary,
                                  shape: BoxShape.circle,
                                ),
                                child: _uploading
                                    ? const SizedBox(
                                        width: 18, height: 18,
                                        child: CircularProgressIndicator(strokeWidth: 2),
                                      )
                                    : const Icon(Icons.camera_alt, color: Colors.white, size: 20),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(name, style: Theme.of(context).textTheme.titleLarge),
                    if (email.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(email, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
                    ],
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // Tarjetas de estadísticas
              Row(
                children: [
                  Expanded(
                    child: _StatCard(
                      label: 'Win Rate',
                      value: '${(winRate * 100).toStringAsFixed(1)}%',
                      subtitle: '$wins W / $losses L',
                      icon: Icons.emoji_events_outlined,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _StatCard(
                      label: 'Partidas',
                      value: '$totalGames',
                      subtitle: 'Totales',
                      icon: Icons.sports_score_outlined,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _StatCard(
                      label: 'Mazos',
                      value: _deckCount == null ? '—' : '$_deckCount',
                      subtitle: 'Creados',
                      icon: Icons.style_outlined,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _StatCard(
                      label: 'Racha',
                      value: (data['streak'] ?? 0).toString(),
                      subtitle: 'Ganadas seguidas',
                      icon: Icons.local_fire_department_outlined,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 24),

              Card(
                elevation: 0,
                color: cs.surfaceContainerLowest,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Acciones', style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          OutlinedButton.icon(
                            icon: const Icon(Icons.edit),
                            label: const Text('Editar nombre'),
                            onPressed: () async {
                              await _promptEditName(context);
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _promptEditName(BuildContext context) async {
    final ctrl = TextEditingController();
    final newName = await showDialog<String?>(
      context: context,
      builder: (_) {
        return AlertDialog(
          title: const Text('Editar nombre'),
          content: TextField(
            controller: ctrl,
            decoration: const InputDecoration(hintText: 'Tu nombre'),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, null), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(context, ctrl.text.trim()), child: const Text('Guardar')),
          ],
        );
      },
    );
    if (newName == null || newName.isEmpty) return;
    await FirebaseFirestore.instance.collection('users').doc(_uid).set(
      {'displayName': newName},
      SetOptions(merge: true),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final String? subtitle;
  final IconData icon;

  const _StatCard({
    required this.label,
    required this.value,
    this.subtitle,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      color: cs.surfaceContainerLowest,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: cs.primary.withOpacity(0.12),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: cs.primary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: Theme.of(context).textTheme.labelMedium?.copyWith(color: cs.onSurfaceVariant)),
                  const SizedBox(height: 4),
                  Text(value, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(subtitle!, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// lib/screens/leagues/league_settings_screen.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'models.dart';

class LeagueSettingsScreen extends StatefulWidget {
  final String leagueId;
  final List<LeaguePlayer> players;

  const LeagueSettingsScreen({
    super.key,
    required this.leagueId,
    required this.players,
  });

  @override
  State<LeagueSettingsScreen> createState() => _LeagueSettingsScreenState();
}

class _LeagueSettingsScreenState extends State<LeagueSettingsScreen> {
  bool _loading = true;
  bool _saving = false;

  int _duelsPerMatch = 3;

  DocumentReference<Map<String, dynamic>> get _leagueRef =>
      FirebaseFirestore.instance.collection('leagues').doc(widget.leagueId);

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    setState(() => _loading = true);
    try {
      final doc = await _leagueRef.get();
      final data = doc.data() ?? {};
      final duels = (data['duelsPerMatch'] as num?)?.toInt() ?? 3;

      if (!mounted) return;
      setState(() => _duelsPerMatch = duels);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error al cargar: $e')));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await _leagueRef.update({'duelsPerMatch': _duelsPerMatch});
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Configuración guardada')));
        Navigator.pop(context);
      }
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
        title: const Text('Configuración de liga'),
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
              icon: const Icon(Icons.save_rounded),
              label: const Text('Guardar'),
            ),
        ],
      ),
      body:
          _loading
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // ── Duelos por enfrentamiento ─────────────────────────────
                  Row(
                    children: [
                      Icon(
                        Icons.sports_score_rounded,
                        size: 18,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Duelos por enfrentamiento',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Cantidad de juegos por mesa en cada fecha.',
                            style: TextStyle(color: Colors.grey, fontSize: 13),
                          ),
                          const SizedBox(height: 14),
                          Row(
                            children: [
                              for (final n in [1, 3, 5]) ...[
                                ChoiceChip(
                                  label: Text(n == 1 ? '1 juego' : 'Bo$n'),
                                  selected: _duelsPerMatch == n,
                                  onSelected:
                                      (_) => setState(() => _duelsPerMatch = n),
                                  selectedColor:
                                      Theme.of(context).colorScheme.primary,
                                  labelStyle: TextStyle(
                                    color:
                                        _duelsPerMatch == n
                                            ? Colors.white
                                            : null,
                                    fontWeight:
                                        _duelsPerMatch == n
                                            ? FontWeight.w700
                                            : null,
                                  ),
                                ),
                                const SizedBox(width: 8),
                              ],
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _duelsPerMatch == 1
                                ? 'Un único juego decide el enfrentamiento.'
                                : 'Mejor de $_duelsPerMatch — gana quien llegue primero a ${(_duelsPerMatch ~/ 2) + 1} victorias.',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.grey,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),
                  FilledButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: const Icon(Icons.save_rounded),
                    label: const Text('Guardar configuración'),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
    );
  }
}

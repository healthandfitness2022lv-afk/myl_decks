// lib/screens/meta_stats_screen.dart
// Estadísticas del meta: agrega todos los mazos de la comunidad y muestra
// razas dominantes, ediciones y las cartas más jugadas.
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../theme/app_theme.dart';
import '../utils/card_utils.dart';
import '../widgets/skeletons.dart';

class MetaStatsScreen extends StatefulWidget {
  const MetaStatsScreen({super.key});

  @override
  State<MetaStatsScreen> createState() => _MetaStatsScreenState();
}

class _MetaSnapshot {
  final int totalDecks;
  final Map<String, int> byRace; // raza -> mazos
  final Map<String, int> byEdition; // edición -> mazos
  final List<MapEntry<String, int>> topCards; // nombre -> copias totales
  final List<MapEntry<String, int>> topCardsByDecks; // nombre -> nº de mazos

  const _MetaSnapshot({
    required this.totalDecks,
    required this.byRace,
    required this.byEdition,
    required this.topCards,
    required this.topCardsByDecks,
  });
}

class _MetaStatsScreenState extends State<MetaStatsScreen> {
  Future<_MetaSnapshot>? _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_MetaSnapshot> _load() async {
    final snap =
        await FirebaseFirestore.instance.collectionGroup('decks').get();

    final byRace = <String, int>{};
    final byEdition = <String, int>{};
    final copiesByCard = <String, int>{};
    final decksByCard = <String, int>{};
    var total = 0;

    for (final doc in snap.docs) {
      final data = doc.data();
      final cards = (data['cards'] as List<dynamic>? ?? const []);
      if (cards.isEmpty) continue; // ignorar mazos vacíos
      total++;

      final race = (data['race'] as String?)?.trim();
      if (race != null && race.isNotEmpty) {
        byRace[race] = (byRace[race] ?? 0) + 1;
      }
      final edition = (data['edition'] as String?)?.trim();
      if (edition != null && edition.isNotEmpty) {
        byEdition[edition] = (byEdition[edition] ?? 0) + 1;
      }

      final seenInDeck = <String>{};
      for (final raw in cards) {
        if (raw is! Map) continue;
        final name = prettyCardName((raw['name'] ?? '').toString());
        if (name.isEmpty) continue;
        final count =
            (raw['count'] is num)
                ? (raw['count'] as num).toInt()
                : int.tryParse('${raw['count']}') ?? 0;
        // Excluir oros básicos del ranking (están en todos los mazos).
        if (normalizeTipoLoose((raw['tipo'] ?? '').toString()) == 'oro') {
          continue;
        }
        copiesByCard[name] = (copiesByCard[name] ?? 0) + count;
        if (seenInDeck.add(name)) {
          decksByCard[name] = (decksByCard[name] ?? 0) + 1;
        }
      }
    }

    List<MapEntry<String, int>> topOf(Map<String, int> m, int n) {
      final list =
          m.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
      return list.take(n).toList();
    }

    return _MetaSnapshot(
      totalDecks: total,
      byRace: byRace,
      byEdition: byEdition,
      topCards: topOf(copiesByCard, 20),
      topCardsByDecks: topOf(decksByCard, 20),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Meta de la comunidad')),
      body: FutureBuilder<_MetaSnapshot>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return ListView(
              children: const [
                SizedBox(height: 8),
                SkeletonListTile(),
                SkeletonListTile(),
                SkeletonListTile(),
                SkeletonListTile(),
              ],
            );
          }
          if (snap.hasError) {
            return Center(
              child: Text(
                'No se pudieron cargar las estadísticas.\n${snap.error}',
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.textSecondary),
              ),
            );
          }
          final meta = snap.data!;
          if (meta.totalDecks == 0) {
            return const Center(
              child: Text(
                'Aún no hay mazos para analizar.',
                style: TextStyle(color: AppColors.textSecondary),
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: () async => setState(() => _future = _load()),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _headline(meta),
                const SizedBox(height: 16),
                _rankSection(
                  title: 'Razas dominantes',
                  icon: Icons.groups_2_rounded,
                  entries:
                      meta.byRace.entries.toList()
                        ..sort((a, b) => b.value.compareTo(a.value)),
                  unit: 'mazos',
                ),
                const SizedBox(height: 16),
                _rankSection(
                  title: 'Ediciones más jugadas',
                  icon: Icons.layers_rounded,
                  entries:
                      meta.byEdition.entries.toList()
                        ..sort((a, b) => b.value.compareTo(a.value)),
                  unit: 'mazos',
                ),
                const SizedBox(height: 16),
                _rankSection(
                  title: 'Cartas más incluidas (por nº de mazos)',
                  icon: Icons.style_rounded,
                  entries: meta.topCardsByDecks,
                  unit: 'mazos',
                ),
                const SizedBox(height: 16),
                _rankSection(
                  title: 'Cartas con más copias en total',
                  icon: Icons.copy_all_rounded,
                  entries: meta.topCards,
                  unit: 'copias',
                ),
                const SizedBox(height: 24),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _headline(_MetaSnapshot meta) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          const Icon(Icons.insights_rounded, color: AppColors.gold, size: 32),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${meta.totalDecks} mazos analizados',
                  style: const TextStyle(
                    color: AppColors.text,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const Text(
                  'Datos de todos los mazos construidos en la app',
                  style: TextStyle(color: AppColors.textFaint, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _rankSection({
    required String title,
    required IconData icon,
    required List<MapEntry<String, int>> entries,
    required String unit,
  }) {
    if (entries.isEmpty) return const SizedBox.shrink();
    final max = entries.first.value.toDouble();
    final top = entries.take(12).toList();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: AppColors.gold, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: AppColors.text,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          for (var i = 0; i < top.length; i++) ...[
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  SizedBox(
                    width: 22,
                    child: Text(
                      '${i + 1}',
                      style: TextStyle(
                        color: i < 3 ? AppColors.gold : AppColors.textFaint,
                        fontWeight: FontWeight.w900,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          top[i].key,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.text,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 3),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: max > 0 ? top[i].value / max : 0,
                            minHeight: 5,
                            backgroundColor: AppColors.surfaceDeep,
                            valueColor: AlwaysStoppedAnimation(
                              i < 3
                                  ? AppColors.gold
                                  : AppColors.gold.withOpacity(.45),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    '${top[i].value} $unit',
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

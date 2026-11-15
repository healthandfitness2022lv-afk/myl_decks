// lib/screens/all_missing_cards_screen.dart
import 'package:flutter/material.dart';
import '../utils/card_utils.dart';

/// Contenedor de datos globales de faltantes
class GlobalMissingData {
  final Map<String, int> globalMissing; // cardName -> total faltante
  final Map<String, Map<String, int>>
  donorsPerCard; // cardName -> {donorLabel: qty}
  final Map<String, List<String>>
  perCardTargets; // cardName -> ["ObjetivoName (qty)", ...]

  GlobalMissingData({
    required this.globalMissing,
    required this.donorsPerCard,
    required this.perCardTargets,
  });
}

class AllMissingCardsScreen extends StatelessWidget {
  final GlobalMissingData data;
  const AllMissingCardsScreen({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    final entries =
        data.globalMissing.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value));

    return Scaffold(
      appBar: AppBar(title: const Text('Todas las cartas faltantes')),
      body:
          entries.isEmpty
              ? const Center(child: Text('No hay cartas faltantes.'))
              : ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: entries.length,
                itemBuilder: (context, idx) {
                  final e = entries[idx];
                  final card = e.key;
                  final totalQty = e.value;
                  final donorsMap = data.donorsPerCard[card] ?? {};
                  final totalAportable = donorsMap.values.fold<int>(
                    0,
                    (p, n) => p + n,
                  );
                  final donorsList = donorsMap.entries
                      .map((d) => '${d.key} (${d.value})')
                      .join(', ');
                  final targets = (data.perCardTargets[card] ?? []).join(' — ');

                  return Card(
                    margin: const EdgeInsets.symmetric(vertical: 6),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${prettyCardName(card)} — Faltan: $totalQty',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 6),
                          Text('Aportable: $totalAportable'),
                          if (donorsList.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Text(
                                'Donantes: $donorsList',
                                style: const TextStyle(fontSize: 13),
                              ),
                            ),
                          if (targets.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Text(
                                'Objetivos: $targets',
                                style: const TextStyle(fontSize: 13),
                              ),
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
    );
  }
}

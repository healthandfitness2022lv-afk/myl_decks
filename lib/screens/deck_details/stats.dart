part of '../deck_details_screen.dart';

class _DeckStatsSnapshot {
  final String deckName;
  final int total;
  final int uniques;
  final int oros;
  final double pctOros;
  final double avgCost;
  final double avgStrength;
  final Map<String, int> byTypeNice;
  final Map<int, int> curve;
  final Map<String, int> featureTotals;
  final Map<String, int> featureGroupTotals;
  final Map<String, List<String>> featureToCards;
  final Map<String, List<_FeatureCardPreview>> featureCardPreviews;

  /// Qué hace el mazo según sus habilidades programadas.
  final PerfilHabilidades perfil;

  const _DeckStatsSnapshot({
    required this.deckName,
    required this.total,
    required this.uniques,
    required this.oros,
    required this.pctOros,
    required this.avgCost,
    required this.avgStrength,
    required this.byTypeNice,
    required this.curve,
    required this.featureTotals,
    required this.featureGroupTotals,
    required this.featureToCards,
    required this.featureCardPreviews,
    required this.perfil,
  });

  factory _DeckStatsSnapshot.fromDeck(
    Deck deck, {
    required Map<String, CardMyL> cardsById,
    required Map<String, CardMyL> cardsByNameLower,
    required Map<String, String> featureGroupMap,
    required Map<String, String?> imgById,
  }) {
    final total = deck.cards.fold<int>(0, (sum, entry) => sum + entry.count);
    final uniques = deck.cards.where((entry) => entry.count > 0).length;

    final byType = <String, int>{};
    for (final entry in deck.cards) {
      final type = normalizeDeckType(entry.tipo);
      byType[type] = (byType[type] ?? 0) + entry.count;
    }

    final oros = byType['oro'] ?? 0;
    final pctOros = total == 0 ? 0.0 : (oros / total) * 100;

    final nonGoldCosts = <int>[];
    for (final entry in deck.cards) {
      if (normalizeDeckType(entry.tipo) == 'oro') continue;
      final cost = entry.coste;
      if (cost == null) continue;
      for (int i = 0; i < entry.count; i++) {
        nonGoldCosts.add(cost);
      }
    }
    final avgCost =
        nonGoldCosts.isEmpty
            ? double.nan
            : nonGoldCosts.reduce((a, b) => a + b) / nonGoldCosts.length;

    double totalStrength = 0;
    int allyCopies = 0;
    final featureTotals = <String, int>{};
    final featureToCards = <String, List<String>>{};
    final featureCardPreviews = <String, List<_FeatureCardPreview>>{};

    for (final entry in deck.cards) {
      CardMyL? card;
      if ((entry.cardId ?? '').trim().isNotEmpty) {
        card = cardsById[entry.cardId!.trim()];
      }
      card ??= cardsByNameLower[entry.name.toLowerCase()];

      if (normalizeDeckType(entry.tipo ?? card?.tipo) == 'aliado' &&
          card?.fuerza != null) {
        totalStrength += card!.fuerza! * entry.count;
        allyCopies += entry.count;
      }

      // Las características antiguas solo cuentan para cartas que aún no
      // tienen habilidades programadas (las demás van en el perfil nuevo).
      final caracteristicas =
          (card?.habilidades.isNotEmpty ?? false)
              ? const <String>[]
              : card?.caracteristicasRaw ?? const <String>[];
      for (final feature in caracteristicas) {
        if (feature.trim().isEmpty) continue;
        featureTotals[feature] = (featureTotals[feature] ?? 0) + entry.count;
        featureToCards.putIfAbsent(feature, () => []);
        featureToCards[feature]!.add('${entry.name} (x${entry.count})');
        featureCardPreviews.putIfAbsent(feature, () => []);
      }
    }

    final avgStrength =
        allyCopies == 0 ? double.nan : totalStrength / allyCopies;

    final maxCost = deck.cards
        .where(
          (entry) =>
              normalizeDeckType(entry.tipo) != 'oro' && entry.coste != null,
        )
        .map((entry) => entry.coste!)
        .fold<int>(0, (prev, cost) => cost > prev ? cost : prev);

    final curve = {for (var i = 0; i <= maxCost; i++) i: 0};
    for (final entry in deck.cards) {
      if (normalizeDeckType(entry.tipo) == 'oro') continue;
      final cost = entry.coste ?? 0;
      final bin = cost < 0 ? 0 : (cost > maxCost ? maxCost : cost);
      curve[bin] = (curve[bin] ?? 0) + entry.count;
    }

    final byTypeNice = <String, int>{
      'Aliado': byType['aliado'] ?? 0,
      'Talismán': byType['talisman'] ?? 0,
      'Arma': byType['arma'] ?? 0,
      'Tótem': byType['totem'] ?? 0,
      'Oro': byType['oro'] ?? 0,
    };

    final featureGroupTotals = <String, int>{};
    for (final entry in featureTotals.entries) {
      final group = _resolveFeatureGroup(entry.key, featureGroupMap);
      featureGroupTotals[group] =
          (featureGroupTotals[group] ?? 0) + entry.value;
    }

    return _DeckStatsSnapshot(
      deckName: deck.name.isEmpty ? 'Mazo' : deck.name,
      total: total,
      uniques: uniques,
      oros: oros,
      pctOros: pctOros,
      avgCost: avgCost,
      avgStrength: avgStrength,
      byTypeNice: byTypeNice,
      curve: curve,
      featureTotals: featureTotals,
      featureGroupTotals: featureGroupTotals,
      featureToCards: featureToCards,
      featureCardPreviews: _hydrateFeatureCardPreviews(
        featureCardPreviews,
        deck.cards,
        imgById,
        cardsById,
        cardsByNameLower,
      ),
      perfil: calcularPerfilHabilidades(
        deck,
        resolver: (entry) {
          final id = (entry.cardId ?? '').trim();
          return (id.isNotEmpty ? cardsById[id] : null) ??
              cardsByNameLower[entry.name.toLowerCase()];
        },
      ),
    );
  }
}

Map<String, List<_FeatureCardPreview>> _hydrateFeatureCardPreviews(
  Map<String, List<_FeatureCardPreview>> raw,
  List<DeckCardEntry> deckCards,
  Map<String, String?> imgById,
  Map<String, CardMyL> cardsById,
  Map<String, CardMyL> cardsByNameLower,
) {
  final hydrated = <String, List<_FeatureCardPreview>>{};

  for (final featureEntry in raw.entries) {
    hydrated[featureEntry.key] = [];
  }

  for (final entry in deckCards) {
    CardMyL? card;
    if ((entry.cardId ?? '').trim().isNotEmpty) {
      card = cardsById[entry.cardId!.trim()];
    }
    card ??= cardsByNameLower[entry.name.toLowerCase()];

    final imageUrl =
        ((entry.cardId ?? '').trim().isNotEmpty
            ? imgById[entry.cardId!.trim()]
            : null) ??
        _readCardImageUrl(card) ??
        '';

    for (final feature in card?.caracteristicasRaw ?? const <String>[]) {
      if (!hydrated.containsKey(feature)) continue;
      hydrated[feature]!.add(
        _FeatureCardPreview(
          name: entry.name,
          quantityLabel: 'x${entry.count}',
          imageUrl: imageUrl,
        ),
      );
    }
  }

  return hydrated;
}

String? _readCardImageUrl(CardMyL? card) {
  if (card == null) return null;
  try {
    final dyn = card as dynamic;
    final candidates = [
      dyn.officialImageUrl,
      dyn.OfficialImageUrl,
      dyn.imageFrontUrl,
      dyn.imageUrl,
    ];
    for (final candidate in candidates) {
      final value = candidate?.toString().trim() ?? '';
      if (value.isNotEmpty) return DriveService.webSafeUrl(value);
    }
  } catch (_) {}
  return null;
}

// _normalizeDeckType → normalizeDeckType (card_utils.dart)
// _normalizeFeatureKey → normalizeFeatureKey (card_utils.dart)

String _resolveFeatureGroup(
  String feature,
  Map<String, String> featureGroupMap,
) {
  final exact =
      featureGroupMap[feature] ?? featureGroupMap[feature.toLowerCase()];
  if (exact != null && exact.trim().isNotEmpty) return exact;

  final normalized = normalizeFeatureKey(feature);
  final normalizedExact =
      featureGroupMap[normalized] ?? featureGroupMap[normalized.toLowerCase()];
  if (normalizedExact != null && normalizedExact.trim().isNotEmpty) {
    return normalizedExact;
  }

  for (final entry in featureGroupMap.entries) {
    final key = normalizeFeatureKey(entry.key);
    if (key.isEmpty) continue;
    if (normalized.contains(key) || key.contains(normalized)) {
      return entry.value;
    }
  }

  return 'Otros';
}

/// Cartas de una categoría del perfil por habilidades (con su imagen).
List<_FeatureCardPreview> _previewsHabilidad(_DeckStatsSnapshot stats, String cat) {
  final imagenes = <String, String>{
    for (final lista in stats.featureCardPreviews.values)
      for (final x in lista) x.name: x.imageUrl,
  };
  return [
    for (final e in stats.perfil.cartasPorCategoria[cat] ?? const <DeckCardEntry>[])
      _FeatureCardPreview(
        name: e.name,
        quantityLabel: 'x${e.count}',
        imageUrl: imagenes[e.name] ?? '',
      ),
  ];
}

class _DeckStatsDialog extends StatelessWidget {
  final _DeckStatsSnapshot stats;

  const _DeckStatsDialog({required this.stats});

  @override
  Widget build(BuildContext context) {
    final featureEntries =
        stats.featureTotals.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value));
    final groupEntries =
        stats.featureGroupTotals.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value));

    return Dialog(
      backgroundColor: const Color(0xFF110E0B),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760, maxHeight: 840),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Estadísticas del mazo',
                          style: Theme.of(
                            context,
                          ).textTheme.titleLarge?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          stats.deckName,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close, color: Colors.white70),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          _StatPill(label: 'Cartas', value: '${stats.total}'),
                          _StatPill(label: 'Oros', value: '${stats.oros}'),
                          _StatPill(
                            label: 'Coste prom.',
                            value:
                                stats.avgCost.isNaN
                                    ? '-'
                                    : stats.avgCost.toStringAsFixed(2),
                          ),
                          _StatPill(
                            label: 'Fuerza prom.',
                            value:
                                stats.avgStrength.isNaN
                                    ? '-'
                                    : stats.avgStrength.toStringAsFixed(2),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      _StatsSection(
                        title: 'Distribución por tipo',
                        child: Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: [
                            for (final entry in stats.byTypeNice.entries)
                              _TypeChip(label: entry.key, value: entry.value),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      _StatsSection(
                        title: 'Curva de coste',
                        child: _DeckStatsCurveChart(curve: stats.curve),
                      ),
                      const SizedBox(height: 16),
                      if (!stats.perfil.vacio) ...[
                        _StatsSection(
                          title: 'Perfil del mazo: ${stats.perfil.perfil}',
                          child: Text(
                            stats.perfil.motivoPerfil,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 13,
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        _StatsSection(
                          title: 'Qué hace el mazo (según sus habilidades)',
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (final cat in categoriasHabilidad)
                                if ((stats.perfil.porCategoria[cat] ?? 0) > 0)
                                  _FeatureChip(
                                    label: cat,
                                    value: stats.perfil.porCategoria[cat]!,
                                    onTap:
                                        () => _showFeatureCards(
                                          context,
                                          cat,
                                          _previewsHabilidad(stats, cat),
                                        ),
                                  ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        _StatsSection(
                          title: 'Cuándo actúan sus habilidades',
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (final e in (stats.perfil.porMomento.entries
                                  .toList()
                                ..sort((a, b) => b.value.compareTo(a.value))))
                                _TypeChip(label: e.key, value: e.value),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                      if (groupEntries.isNotEmpty || stats.perfil.vacio) ...[
                      _StatsSection(
                        title:
                            stats.perfil.vacio
                                ? 'Características por grupo'
                                : 'Características antiguas (${stats.perfil.sinProgramar} cartas sin programar)',
                        child:
                            groupEntries.isEmpty
                                ? const _EmptyStats(
                                  message:
                                      'No hay características disponibles.',
                                )
                                : _FeatureGroupChart(entries: groupEntries),
                      ),
                      const SizedBox(height: 16),
                      _StatsSection(
                        title: 'Características destacadas',
                        child:
                            featureEntries.isEmpty
                                ? const _EmptyStats(
                                  message:
                                      'No hay características registradas.',
                                )
                                : Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    for (final entry in featureEntries.take(18))
                                      _FeatureChip(
                                        label: entry.key,
                                        value: entry.value,
                                        onTap:
                                            () => _showFeatureCards(
                                              context,
                                              entry.key,
                                              stats.featureCardPreviews[entry
                                                      .key] ??
                                                  const <_FeatureCardPreview>[],
                                            ),
                                      ),
                                  ],
                                ),
                      ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showFeatureCards(
    BuildContext context,
    String feature,
    List<_FeatureCardPreview> cards,
  ) {
    final sortedCards = [...cards]
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    showDialog<void>(
      context: context,
      builder:
          (_) => AlertDialog(
            backgroundColor: const Color(0xFF141922),
            title: Text(
              'Cartas con "$feature"',
              style: const TextStyle(color: Colors.white),
            ),
            content: SizedBox(
              width: 320,
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F131B),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: const Color(0xFF4DA6FF).withOpacity(.6),
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 10,
                          height: 10,
                          decoration: const BoxDecoration(
                            color: Color(0xFF4DA6FF),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            stats.deckName,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${sortedCards.length} cartas relacionadas',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 10),
                    if (sortedCards.isEmpty)
                      const Text(
                        'No tiene cartas para esta característica.',
                        style: TextStyle(color: Colors.white38),
                      )
                    else
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 420),
                        child: GridView.builder(
                          shrinkWrap: true,
                          itemCount: sortedCards.length,
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 3,
                                mainAxisSpacing: 10,
                                crossAxisSpacing: 10,
                                childAspectRatio: 0.62,
                              ),
                          itemBuilder: (context, index) {
                            final card = sortedCards[index];
                            return _FeaturePreviewTile(card: card);
                          },
                        ),
                      ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text(
                  'Cerrar',
                  style: TextStyle(color: Color(0xFFF4D88A)),
                ),
              ),
            ],
          ),
    );
  }
}

class _FeaturePreviewTile extends StatelessWidget {
  final _FeatureCardPreview card;

  const _FeaturePreviewTile({required this.card});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Expanded(
          child: Container(
            width: double.infinity,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white10),
              color: const Color(0xFF0D1118),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child:
                  card.imageUrl.isNotEmpty
                      ? Image.network(
                        DriveService.webSafeUrl(card.imageUrl),
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => _featurePreviewFallback(),
                      )
                      : _featurePreviewFallback(),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          card.name,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          card.quantityLabel,
          style: const TextStyle(
            color: Colors.white60,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }

  Widget _featurePreviewFallback() {
    return Container(
      color: const Color(0xFF1A202A),
      alignment: Alignment.center,
      child: const Icon(
        Icons.image_not_supported_outlined,
        color: Colors.white38,
      ),
    );
  }
}

class _CompactDistribution extends StatelessWidget {
  final Map<String, int> values;
  final String label;

  const _CompactDistribution({required this.values, required this.label});

  @override
  Widget build(BuildContext context) {
    final entries =
        values.entries.where((entry) => entry.value > 0).toList()
          ..sort((a, b) => b.value.compareTo(a.value));
    if (entries.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Colors.white54,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 7),
        Wrap(
          spacing: 7,
          runSpacing: 7,
          children: [
            for (final entry in entries)
              _FeatureChip(label: _v2Label(entry.key), value: entry.value),
          ],
        ),
      ],
    );
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;

  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 9,
        height: 9,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
      const SizedBox(width: 5),
      Text(label, style: const TextStyle(color: Colors.white60, fontSize: 11)),
    ],
  );
}

class _ComparisonInsight extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;
  final String description;

  const _ComparisonInsight({
    required this.icon,
    required this.title,
    required this.value,
    required this.description,
  });

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 7),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: const Color(0xFFF1D48B), size: 20),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$title · $value',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                description,
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

String _v2Label(String value) => value
    .split('_')
    .map(
      (part) =>
          part.isEmpty ? part : '${part[0].toUpperCase()}${part.substring(1)}',
    )
    .join(' ');

class _StatsSection extends StatelessWidget {
  final String title;
  final Widget child;

  const _StatsSection({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(.04),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _StatPill extends StatelessWidget {
  final String label;
  final String value;

  const _StatPill({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF20160D),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFF1D184).withOpacity(.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Colors.white60,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _TypeChip extends StatelessWidget {
  final String label;
  final int value;

  const _TypeChip({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(.24),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white12),
      ),
      child: Text(
        '$label: $value',
        style: const TextStyle(
          color: Colors.white70,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _FeatureChip extends StatelessWidget {
  final String label;
  final int value;
  final VoidCallback? onTap;

  const _FeatureChip({required this.label, required this.value, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFF161A22),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white10),
          ),
          child: Text(
            '$label ($value)',
            style: const TextStyle(
              color: Colors.white70,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

class _FeatureCardPreview {
  final String name;
  final String quantityLabel;
  final String imageUrl;

  const _FeatureCardPreview({
    required this.name,
    required this.quantityLabel,
    required this.imageUrl,
  });
}

class _EmptyStats extends StatelessWidget {
  final String message;

  const _EmptyStats({required this.message});

  @override
  Widget build(BuildContext context) {
    return Text(
      message,
      style: const TextStyle(
        color: Colors.white60,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

class _DeckStatsCurveChart extends StatelessWidget {
  final Map<int, int> curve;

  const _DeckStatsCurveChart({required this.curve});

  @override
  Widget build(BuildContext context) {
    final entries =
        curve.entries.toList()..sort((a, b) => a.key.compareTo(b.key));
    if (entries.isEmpty) {
      return const _EmptyStats(message: 'No hay datos de curva.');
    }

    return SizedBox(
      height: 220,
      child: BarChart(
        BarChartData(
          borderData: FlBorderData(show: false),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: _curveInterval(entries),
            getDrawingHorizontalLine:
                (_) => const FlLine(color: Colors.white12, strokeWidth: 1),
          ),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            rightTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget:
                    (value, meta) => Text(
                      '${value.toInt()}',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 11,
                      ),
                    ),
              ),
            ),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 28,
                interval: _curveInterval(entries),
                getTitlesWidget:
                    (value, meta) => Text(
                      '${value.toInt()}',
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 10,
                      ),
                    ),
              ),
            ),
          ),
          barGroups: [
            for (final entry in entries)
              BarChartGroupData(
                x: entry.key,
                barRods: [
                  BarChartRodData(
                    toY: entry.value.toDouble(),
                    width: 18,
                    color: const Color(0xFFD8A12A),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

double _curveInterval(List<MapEntry<int, int>> entries) {
  final maxValue = entries.fold<int>(
    0,
    (max, entry) => math.max(max, entry.value),
  );
  if (maxValue <= 5) return 1;
  return (maxValue / 5).ceil().toDouble();
}

class _FeatureGroupChart extends StatelessWidget {
  final List<MapEntry<String, int>> entries;

  const _FeatureGroupChart({required this.entries});

  @override
  Widget build(BuildContext context) {
    final total = entries.fold<int>(0, (sum, entry) => sum + entry.value);
    return LayoutBuilder(
      builder: (context, constraints) {
        final chart = SizedBox(
          width: 180,
          height: 180,
          child: PieChart(
            PieChartData(
              centerSpaceRadius: 34,
              sectionsSpace: 2,
              pieTouchData: PieTouchData(enabled: false),
              sections: [
                for (int i = 0; i < entries.length; i++)
                  PieChartSectionData(
                    color: _featureGroupColor(i),
                    value: entries[i].value.toDouble(),
                    title:
                        ((entries[i].value / total) * 100) >= 8
                            ? '${((entries[i].value / total) * 100).toStringAsFixed(0)}%'
                            : '',
                    radius: 54,
                    titleStyle: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
              ],
            ),
          ),
        );

        final legend = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (int i = 0; i < entries.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: _featureGroupColor(i),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${entries[i].key}: ${entries[i].value}',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        );

        if (constraints.maxWidth >= 500) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              chart,
              const SizedBox(width: 18),
              Expanded(child: legend),
            ],
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [chart, const SizedBox(height: 14), legend],
        );
      },
    );
  }
}

Color _featureGroupColor(int index) {
  const palette = [
    Color(0xFFe41a1c),
    Color(0xFF377eb8),
    Color(0xFF4daf4a),
    Color(0xFF984ea3),
    Color(0xFFff7f00),
    Color(0xFF17bebb),
    Color(0xFFa65628),
    Color(0xFFf781bf),
    Color(0xFF999999),
  ];
  return palette[index % palette.length];
}

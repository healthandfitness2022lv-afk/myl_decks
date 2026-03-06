// lib/screens/compare_decks_screen.dart
// ignore_for_file: cast_from_null_always_fails

import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../models/deck.dart';
import '../../models/card_myl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:math' as math;


final Map<String, String?> _firestoreUrlCache = {};


/// CompareDecksScreen ahora recibe featureGroupMap: feature -> groupName
class CompareDecksScreen extends StatelessWidget {
  final List<Deck> decks;
  final Map<String, CardMyL> cardsById;
  final Map<String, CardMyL> cardsByNameLower;
  final Map<String, String> featureGroupMap; // <-- nuevo
  

  const CompareDecksScreen({
    super.key,
    required this.decks,
    required this.cardsById,
    required this.cardsByNameLower,
    this.featureGroupMap = const {},
  });

  

  @override
  Widget build(BuildContext context) {
    final models = decks
        .map((d) => _DeckCompareModel.fromDeck(d, cardsById, cardsByNameLower))
        .toList();

    // recolectamos todas las características
    final allFeatures = <String>{};
    for (final m in models) {
      allFeatures.addAll(m.byFeatures.keys);
    }
    final featureList = allFeatures.toList()..sort();

    // ---- agrupamos por group usando featureGroupMap; features sin grupo -> 'Otros' (robusto) ----
    String _normalizeKey(String s) {
      var t = s.trim().toLowerCase();
      t = t
          .replaceAll(RegExp(r'[áàä]'), 'a')
          .replaceAll(RegExp(r'[éèë]'), 'e')
          .replaceAll(RegExp(r'[íìï]'), 'i')
          .replaceAll(RegExp(r'[óòö]'), 'o')
          .replaceAll(RegExp(r'[úùü]'), 'u')
          .replaceAll('ñ', 'n')
          .replaceAll('_', ' ')
          .replaceAll('-', ' ')
          .replaceAll(RegExp(r'[^a-z0-9\s]'), '')
          .replaceAll(RegExp(r'\s+'), ' ');
      return t;
    }

    // Preparo un índice normalizado desde featureGroupMap para búsquedas rápidas
    final Map<String, String> normIndex = {};
    featureGroupMap.forEach((k, v) {
      if (k.trim().isEmpty) return;
      normIndex[k.toLowerCase()] = v;
      normIndex[_normalizeKey(k)] = v;
    });

    // Ahora mapeo cada feature intentando varias estrategias
    final Map<String, List<String>> grouped = {};
    int mapped = 0;
    int unmapped = 0;

    for (final f in featureList) {
      String? foundGroup;

      // 1) lookup exacto
      if (featureGroupMap.containsKey(f)) foundGroup = featureGroupMap[f];

      // 2) lowercase exact
      if (foundGroup == null) foundGroup = featureGroupMap[f.toLowerCase()];

      // 3) normalized exact via índice
      if (foundGroup == null) foundGroup = normIndex[_normalizeKey(f)];

      // 4) partial / contains match (normalized) - útil si caller puso variantes
      if (foundGroup == null) {
        final fn = _normalizeKey(f);
        try {
          final matchKey = normIndex.keys.firstWhere(
            (k) => k.isNotEmpty && (fn.contains(k) || k.contains(fn)),
          );
          foundGroup = normIndex[matchKey];
        } catch (_) {
          // no match parcial
        }
      }

      final groupName = (foundGroup ?? '').trim();
      final finalGroup = groupName.isEmpty ? 'Otros' : groupName;

      (grouped[finalGroup] ??= []).add(f);

      if (finalGroup == 'Otros') {
        unmapped++;
      } else {
        mapped++;
      }
    }

    // Ordenar características dentro de cada grupo (por defecto por total desc)
    final Map<String, int> featureTotals = {};
    for (final m in models) {
      m.byFeatures.forEach((k, v) {
        featureTotals[k] = (featureTotals[k] ?? 0) + v;
      });
    }
    for (final k in grouped.keys) {
      grouped[k]!.sort((a, b) {
        final ta = featureTotals[a] ?? 0;
        final tb = featureTotals[b] ?? 0;
        if (ta != tb) return tb.compareTo(ta); // mayor primero
        return a.compareTo(b);
      });
    }

    // Ordenar grupos: alfabético, poniendo "Otros" al final
    final groupNames = grouped.keys.toList()
      ..sort((a, b) {
        if (a == 'Otros') return 1;
        if (b == 'Otros') return -1;
        return a.toLowerCase().compareTo(b.toLowerCase());
      });

    // DEBUG: imprime en consola para que veas el resultado (mira logcat)
    debugPrint('[CompareDecks] features totales: ${featureList.length}');
    debugPrint('[CompareDecks] mapped: $mapped, unmapped -> Otros: $unmapped');
    debugPrint(
      '[CompareDecks] grupos detectados: ${groupNames.length} -> $groupNames',
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Comparar mazos')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ======================= RESUMEN =======================
          Text("Resumen", style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final m in models)
                Card(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: SizedBox(
                      width: 340,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            m.name,
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              _chip(
                                context,
                                'Coste prom.',
                                m.avgCost.isNaN
                                    ? '-'
                                    : m.avgCost.toStringAsFixed(2),
                              ),
                              _chip(
                                context,
                                'Fuerza prom.',
                                m.avgStrength.isNaN
                                    ? '-'
                                    : m.avgStrength.toStringAsFixed(2),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          const SizedBox(height: 8),

// PIE CHART del mazo (usa funciones que pegamos antes)
Builder(
  builder: (ctx) => _buildGroupPieChartForModel(
    ctx,
    m,
    grouped,    // variable calculada más arriba en build()
    groupNames, // también calculada más arriba
    size: 100,  // ajusta el tamaño del gráfico si hace falta
  ),
),

                        ],
                        
                      ),
                    ),
                  ),
                ),
            ],
          ),

          const SizedBox(height: 24),

          // ======================= TIPOS =======================
          Text(
            "Distribución por tipo",
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          ...models.map((m) => _StackedTypeBar(model: m)),

          const SizedBox(height: 24),

// --- REEMPLAZA el bloque "CURVAS" por esto ---
Text(
  "Curva de coste (sin oros)",
  style: Theme.of(context).textTheme.titleLarge,
),
const SizedBox(height: 8),

// Si hay 0 o 1 mazo, mostramos solo el chart sin tabs
if (models.isEmpty)
  const Text('No hay mazos'),
if (models.length == 1) ...[
  Card(
    margin: const EdgeInsets.only(bottom: 12),
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 200,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                // ancho dinámico según cantidad de buckets (evita overcrowding)
                width: (models.first.curva.length * 26).clamp(240, 900).toDouble(),
                height: 200,
                child: BarChart(
                  BarChartData(
                    borderData: FlBorderData(show: false),
                    gridData: const FlGridData(show: false),
                    titlesData: FlTitlesData(
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          getTitlesWidget: (value, meta) => Text('${value.toInt()}'),
                        ),
                      ),
                      leftTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 28,
                          interval: _calcInterval([models.first]),
                          getTitlesWidget: (value, meta) {
                            if (value % meta.appliedInterval == 0) {
                              return Text('${value.toInt()}', style: const TextStyle(fontSize: 10));
                            }
                            return const SizedBox.shrink();
                          },
                        ),
                      ),
                      rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    ),
                    barGroups: _buildGroupsForModel(models.first, _deckColor(0), barWidth: 14),
                    groupsSpace: 6,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  ),
],

if (models.length > 1)
  DefaultTabController(
    length: models.length,
    child: Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // fila con título + tabs (scrollable si hay muchos mazos)
            Row(
              children: [
                Expanded(
                  child: Text("Curva por mazo", style: Theme.of(context).textTheme.titleLarge),
                ),
                SizedBox(
                  height: 36,
                  child: TabBar(
                    isScrollable: true,
                    indicatorSize: TabBarIndicatorSize.label,
                    tabs: [for (final m in models) Tab(text: m.name,)],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // contenido: un TabBarView con 1 chart por mazo
            SizedBox(
              height: 220,
              child: TabBarView(
                children: [
                  for (int i = 0; i < models.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: SizedBox(
                          width: (models[i].curva.length * 26).clamp(260, 1200).toDouble(),
                          height: 200,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: BarChart(
                                  BarChartData(
                                    borderData: FlBorderData(show: false),
                                    gridData: const FlGridData(show: false),
                                    titlesData: FlTitlesData(
                                      bottomTitles: AxisTitles(
                                        sideTitles: SideTitles(
                                          showTitles: true,
                                          getTitlesWidget: (value, meta) => Text('${value.toInt()}'),
                                        ),
                                      ),
                                      leftTitles: AxisTitles(
                                        sideTitles: SideTitles(
                                          showTitles: true,
                                          reservedSize: 28,
                                          interval: _calcInterval([models[i]]),
                                          getTitlesWidget: (value, meta) {
                                            if (value % meta.appliedInterval == 0) {
                                              return Text('${value.toInt()}', style: const TextStyle(fontSize: 10));
                                            }
                                            return const SizedBox.shrink();
                                          },
                                        ),
                                      ),
                                      rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                                      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                                    ),
                                    barGroups: _buildGroupsForModel(models[i], _deckColor(i), barWidth: 14),
                                    groupsSpace: 6,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 6),
                              // pequeña leyenda compacta
                              Text(models[i].name, style: Theme.of(context).textTheme.bodySmall),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  ),

const SizedBox(height: 24),
// --- FIN DEL BLOQUE REEMPLAZADO ---


          // ======================= CARACTERISTICAS AGRUPADAS (TABS) =======================
          if (groupNames.isNotEmpty)
            DefaultTabController(
              length: groupNames.length,
              child: Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Cabecera con título y TabBar
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8.0,
                          vertical: 4,
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                "Distribución de características por grupo",
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 6),

                      // TabBar (scrollable para muchos grupos)
                      TabBar(
                        isScrollable: true,
                        labelPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        indicatorSize: TabBarIndicatorSize.label,
                        // estilo opcional para que el texto no sea demasiado grande
                        labelStyle: const TextStyle(fontSize: 13),
                        unselectedLabelStyle: const TextStyle(fontSize: 13),
                        tabs: [
                          for (final g in groupNames)
                            Tab(
                              // limitamos ancho máximo para evitar que un tab gigante rompa la fila
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxWidth: 160,
                                ),
                                child: Tooltip(
                                  message: g,
                                  waitDuration: Duration(milliseconds: 300),
                                  child: Text(
                                    g,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    softWrap:
                                        false, // <-- evita que el texto se parta en varias líneas
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),

                      // Vista de pestañas: altura adaptativa para evitar overflows
                      Builder(
                        builder: (ctx) {
                          final mq = MediaQuery.of(ctx);
                          final totalH = mq.size.height;
                          final topPadding = mq.padding.top;
                          // Reservamos sitio para AppBar + contenido superior: ajusta 220 si necesitas más/menos
                          final reservedForOtherContent =
                              kToolbarHeight + topPadding + 220;
                          final available = totalH - reservedForOtherContent;
                          final double panelHeight =
                              (available.isFinite ? available : 300)
                                  .clamp(220.0, 420.0)
                                  .toDouble();

                          return SizedBox(
                            height: panelHeight,
                            child: TabBarView(
                              children: [
                                for (final g in groupNames)
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 8.0,
                                    ),
                                    child: _FeatureGroupCard(
                                      groupName: g,
                                      features: grouped[g]!,
                                      models: models,
                                      cardsById: cardsById,
                                      cardsByNameLower: cardsByNameLower,
                                    ),
                                  ),
                              ],
                            ),
                          );
                        },
                      ),

                      // ======================= DIFERENCIAS =======================
                      // ======================= DIFERENCIAS / COMUNES =======================
if (decks.length >= 2) ...[
  if (decks.length == 2) ...[
    Text(
      "Diferencias",
      style: Theme.of(context).textTheme.titleLarge,
    ),
    const SizedBox(height: 8),
    Builder(
      builder: (ctx) {
        final diff = compareDecks(
          decks[0],
          decks[1],
          cardsById: cardsById,
          cardsByNameLower: cardsByNameLower,
        );

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Solo en ${decks[0].name} (${diff.totalSoloEnA})",
              style: Theme.of(ctx).textTheme.titleMedium,
            ),
            Wrap(
              spacing: 8,
              children:
                  diff.soloEnA.map((c) => Chip(label: Text(c))).toList(),
            ),
            const SizedBox(height: 20),
            Text(
              "Solo en ${decks[1].name} (${diff.totalSoloEnB})",
              style: Theme.of(ctx).textTheme.titleMedium,
            ),
            Wrap(
              spacing: 8,
              children:
                  diff.soloEnB.map((c) => Chip(label: Text(c))).toList(),
            ),
            const SizedBox(height: 20),
            Text(
              "En ambos (${diff.totalEnAmbos})",
              style: Theme.of(ctx).textTheme.titleMedium,
            ),
            Wrap(
              spacing: 8,
              children:
                  diff.enAmbos.map((c) => Chip(label: Text(c))).toList(),
            ),
          ],
        );
      },
    ),
  ] else ...[
    // Caso: más de 2 mazos -> mostramos cartas comunes a todos
    Text(
      "Cartas comunes (${decks.length} mazos)",
      style: Theme.of(context).textTheme.titleLarge,
    ),
    const SizedBox(height: 8),
    Builder(
      builder: (ctx) {
        // construimos mapas name -> count para cada mazo
        final List<Map<String, int>> maps = decks.map((d) {
          final m = <String, int>{};
          for (final c in d.cards) {
            m[c.name] = (m[c.name] ?? 0) + c.count;
          }
          return m;
        }).toList();

        // intersección: start con el primero y mantener min counts
        final common = Map<String, int>.from(maps.first);
        for (int i = 1; i < maps.length; i++) {
          final other = maps[i];
          // eliminar los que no existen en "other"
          final toRemove = <String>[];
          common.forEach((name, cnt) {
            if (!other.containsKey(name)) {
              toRemove.add(name);
            }
          });
          for (final r in toRemove) common.remove(r);

          // actualizar conteos al mínimo entre common y other
          common.keys.toList().forEach((name) {
            common[name] = math.min(common[name]!, other[name]!);

          });
        }

        if (common.isEmpty) {
          return const Text('No hay cartas comunes entre todos los mazos.');
        }

        final totalCommon =
            common.values.fold<int>(0, (p, n) => p + n);

        // ordenamos alfabéticamente para presentación
        final names = common.keys.toList()..sort();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Total cartas comunes (sumadas): $totalCommon',
              style: Theme.of(ctx).textTheme.bodyMedium,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final n in names)
                  Chip(label: Text('$n (x${common[n]})')),
              ],
            ),
          ],
        );
      },
    ),
  ],
],

                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _chip(BuildContext context, String k, String v) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Chip(
      label: Text(
        '$k: $v',
        style: TextStyle(color: isDark ? Colors.white : Colors.black87),
      ),
      backgroundColor: isDark ? Colors.white10 : Colors.black12,
      side: BorderSide(color: isDark ? Colors.white24 : Colors.black26),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
    );
  }
}

// ======================= FEATURE GROUP CARD (DECKS en filas, FEATURES en columnas) =======================
// ======================= FEATURE GROUP CARD (DECKS en filas, FEATURES en columnas) =======================
class _FeatureGroupCard extends StatelessWidget {
  final String groupName;
  final List<String> features;
  final List<_DeckCompareModel> models;
  final Map<String, CardMyL> cardsById;
  final Map<String, CardMyL> cardsByNameLower;

  const _FeatureGroupCard({
    required this.groupName,
    required this.features,
    required this.models,
    required this.cardsById,
    required this.cardsByNameLower,
  });

  @override
  Widget build(BuildContext context) {
    // Ajustables
    const double perFeatureColW = 120.0;
    const double deckNameColW = 200.0;
    const double headerHeight = 56.0;
    const double rowHeight = 56.0;

    // ancho total de la "tabla"
    final double tableWidth = deckNameColW + (features.length * perFeatureColW);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(groupName, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),

            LayoutBuilder(
              builder: (ctx, constraints) {
                final availableHeight = (constraints.maxHeight.isFinite)
                    ? constraints.maxHeight
                    : (headerHeight + (models.length * rowHeight)).clamp(
                        180.0,
                        420.0,
                      );

                // restamos headerHeight y pequeño margen
                final listHeight = (availableHeight - headerHeight + 3.0).clamp(
                  rowHeight,
                  9999.0,
                );

                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(
                    width: tableWidth,
                    height: headerHeight + listHeight,
                    child: Column(
                      children: [
                        // HEADER
                        SizedBox(
                          height: headerHeight,
                          child: Row(
                            children: [
                              SizedBox(
                                width: deckNameColW,
                                child: Text(
                                  'Mazo',
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(fontWeight: FontWeight.bold),
                                ),
                              ),
                              // columnas de características (header)
                              for (final f in features) ...[
                                const SizedBox(width: 8),
                                SizedBox(
                                  width: perFeatureColW - 8,
                                  child: Tooltip(
                                    message: f,
                                    child: Text(
                                      f,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      textAlign: TextAlign.center,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            fontWeight: FontWeight.bold,
                                          ),
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),

                        const Divider(height: 1),

                        // BODY: filas por mazo
                        Expanded(
                          child: ListView.separated(
                            padding: EdgeInsets.zero,
                            itemCount: models.length,
                            separatorBuilder: (_, __) =>
                                const Divider(height: 1),
                            itemBuilder: (ctx, idx) {
                              final m = models[idx];

                              return SizedBox(
                                height: rowHeight,
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    // Nombre del mazo (columna fija)
                                    SizedBox(
                                      width: deckNameColW,
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 6.0,
                                        ),
                                        child: Text(
                                          m.name,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: Theme.of(
                                            context,
                                          ).textTheme.bodyMedium,
                                        ),
                                      ),
                                    ),

                                    // Celdas por característica (centro + clickable)
                                    // dentro del Row de la fila del mazo
                                    for (final f in features) ...[
                                      const SizedBox(width: 8),
                                      FeatureCountCell(
                                        feature: f,
                                        model: m,
                                        cardsById: cardsById,
                                        cardsByNameLower: cardsByNameLower,
                                        width: perFeatureColW - 8,
                                      ),
                                    ],
                                  ],
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),

            const SizedBox(height: 8),

            // leyenda de colores
            Wrap(
              spacing: 12,
              children: [
                for (int i = 0; i < models.length; i++)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(width: 12, height: 12, color: _deckColor(i)),
                      const SizedBox(width: 6),
                      Text(models[i].name),
                    ],
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Celda que muestra el número y abre diálogo con las cartas (miniaturas).
/// Si no hay URL en memoria, intenta leer `officialImageUrl` desde Firestore.
// Widget que muestra el número y al tocar abre un diálogo con las cartas del feature
class FeatureCountCell extends StatelessWidget {
  final String feature;
  final _DeckCompareModel model;
  final Map<String, CardMyL> cardsById;
  final Map<String, CardMyL> cardsByNameLower;
  final double width; // ancho de la celda que estés usando

  const FeatureCountCell({
    Key? key,
    required this.feature,
    required this.model,
    required this.cardsById,
    required this.cardsByNameLower,
    required this.width,
  }) : super(key: key);

  int get count => model.byFeatures[feature] ?? 0;

  @override
  Widget build(BuildContext context) {
    // FittedBox evita overflow si la celda es pequeña
    return InkWell(
      onTap: count > 0 ? () => _showFeatureCardsDialog(context) : null,
      child: SizedBox(
        width: width,
        child: Center(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              '$count',
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  }

 void _showFeatureCardsDialog(BuildContext context) async {
  final List<String> names = model.featureToCards[feature] ?? [];

  final cards = <_CardPreview>[];

  for (final entry in names) {
    final rawName = entry.split(' (').first.trim();
    CardMyL? c;

    // 1) intenta encontrar por mapa por nombre (más rápido)
    c = cardsByNameLower[rawName.toLowerCase()];

    String? foundId;
    String? url;

    // 2) si no está, intenta buscar por coincidencia en cardsById.values
    if (c == null) {
      try {
        final maybe = cardsById.entries.firstWhere(
          (en) => (en.value.nombre.toLowerCase() == rawName.toLowerCase()),
          orElse: () => null as MapEntry<String, CardMyL>,
        );
        foundId = maybe.key;
        c = maybe.value;
            } catch (_) {
        // ignore
      }
    } else {
      // si vino por cardsByNameLower, intenta también recuperar su id buscando en cardsById.entries
      try {
        final maybe = cardsById.entries.firstWhere(
          (en) => (en.value.nombre.toLowerCase() == rawName.toLowerCase()),
          orElse: () => null as MapEntry<String, CardMyL>,
        );
        foundId = maybe.key;
      } catch (_) {}
    }

    // 3) si encontramos el objeto Card, probar distintos campos (como dynamic)
    if (c != null) {
      try {
        final dyn = c as dynamic;
        url = (dyn.officialImageUrl as String?)?.trim() ??
              (dyn.OfficialImageUrl as String?)?.trim() ??
              (dyn.imageFrontUrl as String?)?.trim() ??
              (dyn.imageUrl as String?)?.trim();
      } catch (_) {
        url = null;
      }
    }

    // 4) Si no encontramos url local, y tenemos id -> buscar en Firestore (con cache)
    if ((url == null || url.isEmpty) && (foundId != null && foundId.isNotEmpty)) {
      // chequeo cache
      if (_firestoreUrlCache.containsKey(foundId)) {
        url = _firestoreUrlCache[foundId];
      } else {
        try {
          final db = FirebaseFirestore.instance;
          final doc = await db.collection('cards').doc(foundId).get();
          if (doc.exists) {
            final data = doc.data();
            final off = (data?['officialImageUrl'] as String?)?.trim();
            if (off != null && off.isNotEmpty) {
              url = off;
            } else {
              // buscar variants official
              final offSnap = await db.collection('cards').doc(foundId).collection('variants')
                  .where('official', isEqualTo: true).limit(1).get();
              if (offSnap.docs.isNotEmpty) {
                final u = (offSnap.docs.first.data()['imageFrontUrl'] as String?)?.trim();
                if (u != null && u.isNotEmpty) url = u;
              } else {
                final anySnap = await db.collection('cards').doc(foundId).collection('variants').limit(1).get();
                if (anySnap.docs.isNotEmpty) {
                  final u = (anySnap.docs.first.data()['imageFrontUrl'] as String?)?.trim();
                  if (u != null && u.isNotEmpty) url = u;
                }
              }
            }
          }
        } catch (_) {
          // swallow errors
        } finally {
          _firestoreUrlCache[foundId] = url;
        }
      }
    }

    cards.add(_CardPreview(name: rawName, imageUrl: url));
  }

  // mostrar diálogo (igual que antes)
  showDialog(
    context: context,
    builder: (_) => AlertDialog(
      title: Text('Cartas con "$feature" (${cards.length})'),
      content: SizedBox(
        width: double.maxFinite,
        child: GridView.count(
          crossAxisCount: 3,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          childAspectRatio: 120 / 170,
          shrinkWrap: true,
          children: cards.map((cp) {
            final hasUrl = cp.imageUrl != null && cp.imageUrl!.isNotEmpty;
            final img = hasUrl
                ? Image.network(
                    cp.imageUrl!,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => _placeholder(),
                  )
                : _placeholder();

            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: AspectRatio(aspectRatio: 120 / 170, child: img),
                  ),
                ),
                const SizedBox(height: 6),
                Text(cp.name, maxLines: 2, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center),
              ],
            );
          }).toList(),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cerrar')),
      ],
    ),
  );
}



  Widget _placeholder() => Container(
    color: Colors.grey.shade800,
    child: const Center(
      child: Icon(Icons.image_not_supported, color: Colors.white70),
    ),
  );
}

class _CardPreview {
  final String name;
  final String? imageUrl;
  _CardPreview({required this.name, this.imageUrl});
}

class DeckDiff {
  final List<String> soloEnA;
  final List<String> soloEnB;
  final List<String> enAmbos;

  final int totalSoloEnA;
  final int totalSoloEnB;
  final int totalEnAmbos;

  DeckDiff({
    required this.soloEnA,
    required this.soloEnB,
    required this.enAmbos,
    required this.totalSoloEnA,
    required this.totalSoloEnB,
    required this.totalEnAmbos,
  });
}

DeckDiff compareDecks(
  Deck a,
  Deck b, {
  required Map<String, CardMyL> cardsById,
  required Map<String, CardMyL> cardsByNameLower,
}) {
  String deckEdition(Deck d) {
    String found = '';
    for (final e in d.cards) {
      CardMyL? card;
      if (e.cardId != null) {
        card = cardsById[e.cardId!];
      }
      card ??= cardsByNameLower[e.name.toLowerCase()];
      if (card != null && card.edicion.isNotEmpty) {
        final ed = card.edicion.trim().toLowerCase();
        if (found.isEmpty) {
          found = ed;
        } else if (found != ed) {
          // mezcla de ediciones → marcamos como inválido
          return '';
        }
      }
    }
    return found;
  }

  final edA = deckEdition(a);
  final edB = deckEdition(b);

  if (edA.isEmpty || edB.isEmpty || edA != edB) {
    // ediciones distintas → nada
    return DeckDiff(
      soloEnA: const [],
      soloEnB: const [],
      enAmbos: const [],
      totalSoloEnA: 0,
      totalSoloEnB: 0,
      totalEnAmbos: 0,
    );
  }

  // ============== lógica de comparación normal ==============
  final mapA = <String, int>{};
  final mapB = <String, int>{};
  final typeA = <String, String>{};
  final typeB = <String, String>{};

  for (final c in a.cards) {
    mapA[c.name] = (mapA[c.name] ?? 0) + c.count;
    typeA[c.name] = (c.tipo ?? '').toLowerCase();
  }
  for (final c in b.cards) {
    mapB[c.name] = (mapB[c.name] ?? 0) + c.count;
    typeB[c.name] = (c.tipo ?? '').toLowerCase();
  }

  final allNames = {...mapA.keys, ...mapB.keys};

  final soloEnA = <String>[];
  final soloEnB = <String>[];
  final enAmbos = <String>[];

  int totalA = 0, totalB = 0, totalCommon = 0;

  for (final name in allNames) {
    final countA = mapA[name] ?? 0;
    final countB = mapB[name] ?? 0;
    final tipo = (typeA[name] ?? typeB[name] ?? '').toLowerCase();

    if (countA > 0 && countB > 0) {
      final comunes = countA < countB ? countA : countB;
      enAmbos.add("$tipo|$name (x$comunes)");
      totalCommon += comunes;

      if (countA > comunes) {
        soloEnA.add("$tipo|$name (x${countA - comunes})");
        totalA += countA - comunes;
      }
      if (countB > comunes) {
        soloEnB.add("$tipo|$name (x${countB - comunes})");
        totalB += countB - comunes;
      }
    } else if (countA > 0) {
      soloEnA.add("$tipo|$name (x$countA)");
      totalA += countA;
    } else if (countB > 0) {
      soloEnB.add("$tipo|$name (x$countB)");
      totalB += countB;
    }
  }

  int typeOrder(String s) {
    final tipo = s.split('|').first;
    switch (tipo) {
      case 'aliado':
        return 0;
      case 'talisman':
      case 'talismán':
        return 1;
      case 'arma':
        return 2;
      case 'totem':
      case 'tótem':
        return 3;
      case 'oro':
        return 4;
      default:
        return 5;
    }
  }

  int compare(String a, String b) {
    final orderA = typeOrder(a);
    final orderB = typeOrder(b);
    if (orderA != orderB) return orderA.compareTo(orderB);
    return a.compareTo(b);
  }

  soloEnA.sort(compare);
  soloEnB.sort(compare);
  enAmbos.sort(compare);

  String _stripType(String s) => s.contains('|') ? s.split('|')[1] : s;

  return DeckDiff(
    soloEnA: soloEnA.map(_stripType).toList(),
    soloEnB: soloEnB.map(_stripType).toList(),
    enAmbos: enAmbos.map(_stripType).toList(),
    totalSoloEnA: totalA,
    totalSoloEnB: totalB,
    totalEnAmbos: totalCommon,
  );
}



class _StackedTypeBar extends StatelessWidget {
  final _DeckCompareModel model;
  const _StackedTypeBar({required this.model});
  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              model.name,
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 18,
              child: Row(
                children: [
                  for (final e in model.byTypeNice.entries.where(
                    (e) => e.value > 0,
                  ))
                    Expanded(
                      flex: e.value,
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 1),
                        decoration: BoxDecoration(
                          color: _typeColor(context, e.key),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 10,
              runSpacing: 6,
              children: [
                for (final e in model.byTypeNice.entries.where(
                  (e) => e.value > 0,
                ))
                  Text(
                    '${e.key}: ${e.value}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ======================= MODEL =======================
class _DeckCompareModel {
  final String id;
  final String name;
  final int total;
  final int uniques;
  final int oros;
  final double pctOros;
  final double avgCost;
  final double avgStrength;
  final Map<String, int> byTypeNice;
  final Map<int, int> curva;
  final Map<String, int> byFeatures;
  final Map<String, List<String>> featureToCards;

  _DeckCompareModel({
    required this.id,
    required this.name,
    required this.total,
    required this.uniques,
    required this.oros,
    required this.pctOros,
    required this.avgCost,
    required this.avgStrength,
    required this.byTypeNice,
    required this.curva,
    required this.byFeatures,
    required this.featureToCards,
  });

  static String _normTipo(String? t) {
    var s = (t ?? '').trim().toLowerCase();
    if (s == 'talismán') s = 'talisman';
    if (s == 'tótem') s = 'totem';
    return s;
  }

  factory _DeckCompareModel.fromDeck(
    Deck d,
    Map<String, CardMyL> cardsById,
    Map<String, CardMyL> cardsByNameLower,
  ) {
    final total = d.cards.fold<int>(0, (s, e) => s + e.count);
    final uniques = d.cards.where((e) => e.count > 0).length;

    final byType = <String, int>{};
    for (final e in d.cards) {
      final k = _normTipo(e.tipo);
      byType[k] = (byType[k] ?? 0) + e.count;
    }
    final oros = byType['oro'] ?? 0;
    final pctOros = total == 0 ? 0.0 : (oros / total) * 100.0;

    // Coste promedio (sin oros)
    final expanded = <int>[];
    for (final e in d.cards) {
      if (_normTipo(e.tipo) == 'oro') continue;
      final c = e.coste;
      if (c == null) continue;
      for (int i = 0; i < e.count; i++) expanded.add(c);
    }
    final avgCost = expanded.isEmpty
        ? double.nan
        : expanded.reduce((a, b) => a + b) / expanded.length;

    // Etiquetas bonitas
    final labels = {
      'aliado': 'Aliado',
      'talisman': 'Talismán',
      'totem': 'Tótem',
      'arma': 'Arma',
      'oro': 'Oro',
    };
    final pretty = <String, int>{for (final v in labels.values) v: 0};
    byType.forEach((k, v) {
      final lab = labels[k];
      if (lab != null) pretty[lab] = v;
    });

    // Calcular máximo coste real (excluyendo oros y nulls)
    final maxCost = d.cards
        .where((e) => _normTipo(e.tipo) != 'oro' && e.coste != null)
        .map((e) => e.coste!)
        .fold<int>(0, (prev, c) => c > prev ? c : prev);

    // Armar curva dinámica
    final curva = {for (var i = 0; i <= maxCost; i++) i: 0};
    for (final e in d.cards) {
      if (_normTipo(e.tipo) == 'oro') continue;
      final c = e.coste ?? 0;
      final bin = c < 0 ? 0 : (c > maxCost ? maxCost : c);
      curva[bin] = (curva[bin] ?? 0) + e.count;
    }

    // Fuerza promedio de aliados
    int totalStrCopies = 0;
    double sumStr = 0;
    for (final e in d.cards) {
      if (_normTipo(e.tipo) != 'aliado') continue;
      CardMyL? card;
      if (e.cardId != null) {
        card = cardsById[e.cardId!];
      }
      card ??= cardsByNameLower[e.name.toLowerCase()];
      if (card?.fuerza == null) continue;
      sumStr += card!.fuerza! * e.count;
      totalStrCopies += e.count;
    }
    final avgStrength = totalStrCopies == 0
        ? double.nan
        : sumStr / totalStrCopies;

    // Características
    final byFeatures = <String, int>{};
    final featureToCards = <String, List<String>>{};
    for (final e in d.cards) {
      CardMyL? card;
      if (e.cardId != null) {
        card = cardsById[e.cardId!];
      }
      card ??= cardsByNameLower[e.name.toLowerCase()];
      final feats = card?.caracteristicasRaw ?? [];
      for (final f in feats) {
        byFeatures[f] = (byFeatures[f] ?? 0) + e.count;
        featureToCards.putIfAbsent(f, () => []);
        featureToCards[f]!.add("${e.name} (x${e.count})");
      }
    }

    return _DeckCompareModel(
      id: d.id,
      name: d.name.isEmpty ? 'Mazo' : d.name,
      total: total,
      uniques: uniques,
      oros: oros,
      pctOros: pctOros,
      avgCost: avgCost,
      avgStrength: avgStrength,
      byTypeNice: pretty,
      curva: curva,
      byFeatures: byFeatures,
      featureToCards: featureToCards,
    );
  }
}

// ======================= COLORS & HELPERS =======================
Color _typeColor(BuildContext context, String label) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  Color hex(String s) =>
      Color(int.parse('FF' + s.replaceAll('#', ''), radix: 16));
  switch (label.toLowerCase()) {
    case 'aliado':
      return hex('#0072B2');
    case 'talismán':
      return hex('#E69F00');
    case 'tótem':
      return hex('#009E73');
    case 'arma':
      return hex('#D55E00');
    case 'oro':
      return hex('#F0E442');
    default:
      return isDark ? Colors.white70 : Colors.black54;
  }
}

Color _deckColor(int index) {
  const palette = [
    Colors.blue,
    Colors.red,
    Colors.green,
    Colors.orange,
    Colors.purple,
  ];
  return palette[index % palette.length];
}

double _calcInterval(List<_DeckCompareModel> models) {
  final maxY = models
      .map((m) => m.curva.values.fold<int>(0, (a, b) => a > b ? a : b))
      .fold<int>(0, (a, b) => a > b ? a : b);
  if (maxY <= 5) return 1;
  return (maxY / 5).ceil().toDouble().clamp(1, double.infinity);
}

// agrega esto dentro de CompareDecksScreen

Widget _buildGroupPieChartForModel(
  BuildContext context,
  _DeckCompareModel m,
  Map<String, List<String>> grouped,
  List<String> groupNames, {
  double size = 120,
}) {
  // calcular totales por grupo para este modelo
  final Map<String, int> totals = {};
  for (final g in groupNames) {
    final feats = grouped[g] ?? [];
    int s = 0;
    for (final f in feats) {
      s += (m.byFeatures[f] ?? 0);
    }
    if (s > 0) totals[g] = s;
  }

  final totalAll = totals.values.fold<int>(0, (p, n) => p + n);
  if (totalAll == 0) {
    // placeholder si no hay características en grupos
    return SizedBox(
      width: size,
      height: size,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.pie_chart_outline, size: size * 0.4, color: Colors.grey),
            const SizedBox(height: 6),
            const Text('Sin datos', style: TextStyle(fontSize: 12)),
          ],
        ),
      ),
    );
  }

  // construir secciones (una sección por grupo con valor > 0)
  final sections = <PieChartSectionData>[];
  int idx = 0;
  totals.forEach((group, val) {
    final percent = (val / totalAll) * 100;
    sections.add(PieChartSectionData(
      value: val.toDouble(),
      title: percent >= 7 ? '${percent.toStringAsFixed(0)}%' : '', // solo label si grande
      radius: size * 0.42,
      titleStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
      color: _groupColor(idx),
    ));
    idx++;
  });

 // reemplaza el bloque RETURN por este (responsive: Row si cabe, Column si no)
return LayoutBuilder(builder: (ctx, constraints) {
  final available = constraints.maxWidth.isFinite ? constraints.maxWidth : (size + 160.0);

  // ancho mínimo que queremos para mantener la torta y la leyenda en fila
  final minRowWidth = size + 160.0;

  // Leyenda como columna scrollable (reutilizable)
  Widget legendColumn() {
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: 160.0, maxHeight: size),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (int i = 0; i < totals.keys.length; i++)
              _smallLegendRow(
                ctx,
                totals.keys.elementAt(i),
                totals.values.elementAt(i),
                _groupColor(i),
              ),
          ],
        ),
      ),
    );
  }

  // Si hay espacio suficiente, usamos fila (Row) — con posibilidad de scroll horizontal si algo extra entra
  if (available >= minRowWidth) {
    final legendWidth = (available - size - 12.0).clamp(80.0, 240.0);
    return SizedBox(
      width: available,
      height: size,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: size, height: size, child: PieChart(PieChartData(
              sections: sections,
              centerSpaceRadius: size * 0.18,
              sectionsSpace: 2,
              pieTouchData: PieTouchData(enabled: false),
            ))),
            const SizedBox(width: 12),
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: legendWidth, maxHeight: size),
              child: legendColumn(),
            ),
          ],
        ),
      ),
    );
  }

  // Si no cabe en fila, apilamos verticalmente (Column): torta arriba y leyenda abajo (evita overflow-right)
  return SizedBox(
    width: available,
    // altura total: torta + una leyenda acotada (legend puede scrollear si hay muchas entradas)
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: available,
          height: size,
          child: PieChart(PieChartData(
            sections: sections,
            centerSpaceRadius: size * 0.18,
            sectionsSpace: 2,
            pieTouchData: PieTouchData(enabled: false),
          )),
        ),
        const SizedBox(height: 8),
        // leyenda ocupa todo el ancho disponible, pero su contenido puede scrollear verticalmente
        ConstrainedBox(
          constraints: BoxConstraints(maxWidth: available, maxHeight: (size * 0.45).clamp(80.0, 240.0)),
          child: SingleChildScrollView(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (int i = 0; i < totals.keys.length; i++)
                _smallLegendRow(
                  ctx,
                  totals.keys.elementAt(i),
                  totals.values.elementAt(i),
                  _groupColor(i),
                ),
            ],
          )),
        ),
      ],
    ),
  );
});

}

List<BarChartGroupData> _buildGroupsForModel(_DeckCompareModel m, Color color, {double barWidth = 12}) {
  // calcula min/max bins
  final keys = m.curva.keys.toList()..sort();
  if (keys.isEmpty) return [];
  final minCost = keys.first;
  final maxCost = keys.last;

  final groups = <BarChartGroupData>[];
  for (int cost = minCost; cost <= maxCost; cost++) {
    final val = m.curva[cost] ?? 0;
    groups.add(BarChartGroupData(
      x: cost,
      barRods: [
        BarChartRodData(toY: val.toDouble(), color: color, width: barWidth),
      ],
    ));
  }
  return groups;
}


Widget _smallLegendRow(BuildContext ctx, String label, int qty, Color color) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 2.0),
    child: Row(
      children: [
        Container(width: 12, height: 12, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            '$label: $qty',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(ctx).textTheme.bodySmall,
          ),
        ),
      ],
    ),
  );
}

// paleta para los grupos (ajustá si querés otros colores)
Color _groupColor(int index) {
  const palette = [
    Color(0xFFe41a1c), // rojo
    Color(0xFF377eb8), // azul
    Color(0xFF4daf4a), // verde
    Color(0xFF984ea3), // morado
    Color(0xFFff7f00), // naranja
    Color(0xFFffff33), // amarillo
    Color(0xFFa65628), // marrón
    Color(0xFFf781bf), // rosa
    Color(0xFF999999), // gris
  ];
  return palette[index % palette.length];
}


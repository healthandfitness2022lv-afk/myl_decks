import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../models/card_myl.dart'; // para leer raza/fuerza/keywords/tags/caracteristicasRaw

class DeckStatsSection extends StatefulWidget {
  final String deckName;
  final int totalCards;
  final int nonGoldTotal;
  final int uniques;
  final double pctOros;
  final double costAvg;
  final int costMedian;
  final int costMode;
  final double pctLow02;
  final int missingCost;
  final Map<int, int> curve; // 0..k con k+
  final Map<String, int> byType; // normalizado -> cantidad
  final Map<int, int> allyCurve; // 0..k con k+
  final String Function(String) displayTipo;
  final int kMaxCost;
  final ({int x1, int x2, int x3, int x4}) slots;
  final double allyCostAvg;
  final double allyStrengthAvg;
  final Map<String, CardMyL>? catalogByNameLower; // opcional

  final Map<String, List<({String name, int count})>> breakdownByType;

  const DeckStatsSection({
    super.key,
    required this.deckName,
    required this.totalCards,
    required this.nonGoldTotal,
    required this.uniques,
    required this.pctOros,
    required this.costAvg,
    required this.costMedian,
    required this.costMode,
    required this.pctLow02,
    required this.missingCost,
    required this.curve,
    required this.byType,
    required this.allyCurve,
    required this.displayTipo,
    required this.kMaxCost,
    required this.slots,
    required this.allyCostAvg,
    required this.allyStrengthAvg,
    required this.breakdownByType,
    this.catalogByNameLower,
  });

  @override
  State<DeckStatsSection> createState() => _DeckStatsSectionState();
}

class _DeckStatsSectionState extends State<DeckStatsSection> {
  bool showOro = true; // toggle entre curva de oro y aliados


  String _norm(String input) {
    return input
        .toLowerCase()
        .replaceAll(RegExp(r'[áàä]'), 'a')
        .replaceAll(RegExp(r'[éèë]'), 'e')
        .replaceAll(RegExp(r'[íìï]'), 'i')
        .replaceAll(RegExp(r'[óòö]'), 'o')
        .replaceAll(RegExp(r'[úùü]'), 'u')
        .replaceAll('ñ', 'n')
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
  }

  String _prettyFromNorm(String k) {
    const pretties = {
      'bonificador': 'Bonificador',
      'imbloqueable': 'Imbloqueable',
      'furia': 'Furia',
      'removal': 'Removal',
      'baraje': 'Baraje',
      'robo': 'Robo',
      'finalizador': 'Finalizador',
      'invocador': 'Invocador',
      'buscador': 'Buscador',
      'anulacion': 'Anulación',
      'destierro': 'Destierro',
      'indestructible': 'Indestructible',
      'indesterrable': 'Indesterrable',
      'dano_directo': 'Daño directo',
      'generador_oros': 'Generador de oros',
      'control_aliados': 'Control de aliados',
      'cancelacion': 'Cancelación',
      'inhabilitar': 'Inhabilitar',
      'reducir_dano': 'Reducir daño',
    };
    if (pretties.containsKey(k)) return pretties[k]!;
    final raw = k.replaceAll('_', ' ');
    return raw.isEmpty ? '-' : raw[0].toUpperCase() + raw.substring(1);
  }

  // ---------- Facetas (incluye Características) ----------
  ({ Map<String, Map<String,int>> counters, Map<String, Map<String, List<({String name,int count})>>> details })
_buildFacetDataHere() {
  final counters = <String, Map<String,int>>{
    'Fuerza (Aliados)': {},
    'Características': {},
  };
  final details = <String, Map<String, List<({String name,int count})>>>{
    'Fuerza (Aliados)': {},
    'Características': {},
  };

  // Acumulador específico para evitar duplicados por nombre en Características:
  final caracteristicasAgg = <String, Map<String,int>>{}; // label -> {name -> count}

  final catalog = widget.catalogByNameLower;
  if (catalog == null || widget.breakdownByType.isEmpty) {
    return (counters: counters, details: details);
  }

  widget.breakdownByType.forEach((_, list) {
    for (final it in list) {
      final key = it.name.toLowerCase().trim();
      final card = catalog[key];
      if (card == null) continue;

      // ---- Fuerza (solo aliados) ----
      if (card.esAliado && card.fuerza != null) {
        final f = card.fuerza!;
        final bin = f >= 6 ? '6+' : '$f';
        counters['Fuerza (Aliados)']![bin] = (counters['Fuerza (Aliados)']![bin] ?? 0) + it.count;
        final lst = (details['Fuerza (Aliados)']![bin] ??= <({String name,int count})>[]);
        lst.add((name: it.name, count: it.count));
      }

final seenLabels = <String>{}; // 👈 deduplicamos por LABEL

// 1) Enum tags
for (final t in card.tags) {
  final norm = _norm(t.key);
  final label = _prettyFromNorm(norm); // "Generador de oros"
  if (seenLabels.add(label)) {         // 👈 evita contar dos veces si el raw trae "generador de oros)"
    counters['Características']![label] =
        (counters['Características']![label] ?? 0) + it.count;
    final byName = (caracteristicasAgg[label] ??= <String,int>{});
    byName[it.name] = (byName[it.name] ?? 0) + it.count; // consolida por carta
  }
}

// 2) Raw strings
for (final raw in card.caracteristicasRaw) {
  final norm = _norm(raw);
  final label = _prettyFromNorm(norm); // también "Generador de oros"
  if (seenLabels.add(label)) {         // 👈 ya no se duplica aunque el norm sea distinto
    counters['Características']![label] =
        (counters['Características']![label] ?? 0) + it.count;
    final byName = (caracteristicasAgg[label] ??= <String,int>{});
    byName[it.name] = (byName[it.name] ?? 0) + it.count;
  }
}
    }
  });

  // Pasa de los acumuladores (label -> {name -> count}) a listas ordenadas
  caracteristicasAgg.forEach((label, byName) {
    final lst = byName.entries
        .map<({String name,int count})>((e) => (name: e.key, count: e.value))
        .toList()
      ..sort((a,b){
        final c = b.count.compareTo(a.count);
        return c != 0 ? c : a.name.compareTo(b.name);
      });
    details['Características']![label] = lst;
  });

  // Si quieres, también puedes ordenar las listas de “Fuerza (Aliados)”
  details['Fuerza (Aliados)']?.forEach((bin, lst) {
    lst.sort((a,b){
      final c = b.count.compareTo(a.count);
      return c != 0 ? c : a.name.compareTo(b.name);
    });
  });

  return (counters: counters, details: details);
}



  // ---------- UI helpers ----------
  List<MapEntry<String, int>> _sortedTypeEntries() {
    final list = <MapEntry<String, int>>[];
    widget.byType.forEach((raw, v) {
      if (v <= 0) return;
      final label = widget.displayTipo(raw.trim().toLowerCase());
      list.add(MapEntry(label, v));
    });
    list.sort((a, b) => b.value.compareTo(a.value));
    return list;
  }

  /// Top 5 tipos (por cantidad total) preservando el label bonito con displayTipo
  List<({String typeKey, String label, int total})> _top5Types() {
    final items = <({String typeKey, String label, int total})>[];
    widget.byType.forEach((rawKey, total) {
      if (total <= 0) return;
      items.add((typeKey: rawKey, label: widget.displayTipo(rawKey), total: total));
    });
    items.sort((a, b) => b.total.compareTo(a.total));
    if (items.length > 5) return items.sublist(0, 5);
    return items;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final titleStyle = theme.textTheme.titleMedium?.copyWith(
      color: Colors.white,
      fontWeight: FontWeight.w800,
    );

    final donutEntries = _sortedTypeEntries();
    final facetData = _buildFacetDataHere();

    

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 720;
        final gap = 12.0;
        final cardWidth = isWide ? (constraints.maxWidth - gap) / 2 : constraints.maxWidth;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.deckName.isEmpty ? 'Estadísticas del mazo' : widget.deckName,
              style: titleStyle,
            ),

            // KPIs
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _KpiCard(icon: Icons.style_rounded, label: 'Únicas', value: '${widget.uniques}'),
                _KpiCard(
                  icon: Icons.toll_rounded,
                  label: 'Coste promedio)',
                  value: widget.costAvg.isNaN ? '-' : widget.costAvg.toStringAsFixed(2),
                ),
                _KpiCard(
                  icon: Icons.groups_2_rounded,
                  label: 'Coste promedio aliados',
                  value: widget.allyCostAvg.isNaN ? '-' : widget.allyCostAvg.toStringAsFixed(2),
                ),
                _KpiCard(
                  icon: Icons.fitness_center_rounded,
                  label: 'Fuerza promedio aliados',
                  value: widget.allyStrengthAvg.isNaN ? '-' : widget.allyStrengthAvg.toStringAsFixed(2),
                ),
                _KpiCard(
                  icon: Icons.troubleshoot_rounded,
                  label: '0–2 coste',
                  value: '${widget.pctLow02.toStringAsFixed(0)}%',
                ),
                if (widget.missingCost > 0)
                  const _KpiCard(
                    icon: Icons.warning_amber_rounded,
                    label: 'Sin coste',
                    value: '',
                    tone: KpiTone.warning,
                  ),
              ].map((w) => w).toList(),
            ),

            const SizedBox(height: 12),

            // Donut + Curva
            isWide
                ? Row(
                    children: [
                      SizedBox(
                        width: cardWidth,
                        child: _DonutByType(
                          entries: donutEntries,
                          onSurface: scheme.onSurface,
                          background: scheme.surfaceVariant.withOpacity(.25),
                        ),
                      ),
                      SizedBox(width: gap),
                      SizedBox(
                        width: cardWidth,
                        child: _CurvesCard(
                          showOro: showOro,
                          onToggle: (v) => setState(() => showOro = v),
                          oroData: widget.curve,
                          allyData: widget.allyCurve,
                          kMax: widget.kMaxCost,
                        ),
                      ),
                    ],
                  )
                : Column(
                    children: [
                      _DonutByType(
                        entries: donutEntries,
                        onSurface: scheme.onSurface,
                        background: scheme.surfaceVariant.withOpacity(.25),
                      ),
                      SizedBox(height: gap),
                      _CurvesCard(
                        showOro: showOro,
                        onToggle: (v) => setState(() => showOro = v),
                        oroData: widget.curve,
                        allyData: widget.allyCurve,
                        kMax: widget.kMaxCost,
                      ),
                    ],
                  ),

            const SizedBox(height: 16),

            // Desglose por tipo (Top 5)
            _TypeBreakdownCard(
              title: 'Desglose por tipo',
              topTypes: _top5Types(),
              breakdownByType: widget.breakdownByType,
              displayTipo: widget.displayTipo,
            ),

            const SizedBox(height: 12),
            _CharacteristicsSection(
            characteristics: facetData.counters['Características'] ?? const {},
            details: facetData.details['Características'] ?? const {},
),
const SizedBox(height: 12),

// (si quieres mantener el resto de facetas, deja _FacetCountersSection debajo)
_FacetCountersSection(
  facetCounters: facetData.counters,
  facetDetails: facetData.details,
),

          ],
        );
      },
    );
  }
}

class _CharacteristicsSection extends StatelessWidget {
  final Map<String, int> characteristics;
  final Map<String, List<({String name,int count})>> details;

  const _CharacteristicsSection({
    required this.characteristics,
    required this.details,
  });

  @override
  Widget build(BuildContext context) {
    if (characteristics.isEmpty) return const SizedBox.shrink();

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scheme = Theme.of(context).colorScheme;

    final entries = characteristics.entries.toList()
      ..sort((a,b){
        final c = b.value.compareTo(a.value);
        return c != 0 ? c : a.key.compareTo(b.key);
      });

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceVariant.withOpacity(.18),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Características',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: entries.map((e) {
              final label = '${e.key} · ${e.value}';
              return InkWell(
                borderRadius: BorderRadius.circular(999),
                onTap: () {
                  final detail = (details[e.key] ?? const <({String name,int count})>[]);
                  showModalBottomSheet(
                    context: context,
                    backgroundColor: Colors.black87,
                    isScrollControlled: true,
                    shape: const RoundedRectangleBorder(
                      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                    ),
                    builder: (_) {
                      return SafeArea(
                        top: false,
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      e.key,
                                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.close, color: Colors.white70),
                                    onPressed: () => Navigator.pop(context),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              if (detail.isEmpty)
                                const Text('Sin cartas', style: TextStyle(color: Colors.white54))
                              else
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: detail.map((it) {
                                    return Chip(
                                      label: Text(
                                        '${it.count}x ${it.name}',
                                        style: TextStyle(color: isDark ? Colors.white : Colors.black87),
                                      ),
                                      backgroundColor: isDark ? Colors.white10 : Colors.black12,
                                      side: BorderSide(color: isDark ? Colors.white24 : Colors.black26),
                                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                      visualDensity: VisualDensity.compact,
                                    );
                                  }).toList(),
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  );
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white10 : Colors.black12,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: isDark ? Colors.white24 : Colors.black26),
                  ),
                  child: Text(label, style: const TextStyle(color: Colors.white)),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}


class _FacetCountersSection extends StatelessWidget {
  final Map<String, Map<String,int>> facetCounters;
  final Map<String, Map<String, List<({String name,int count})>>> facetDetails;

  const _FacetCountersSection({
    required this.facetCounters,
    required this.facetDetails,
  });

  @override
  Widget build(BuildContext context) {
    if (facetCounters.values.every((m) => m.isEmpty)) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;    

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceVariant.withOpacity(.18),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        
      ),
    );
  }
}

class _CurvesCard extends StatelessWidget {
  final bool showOro;
  final void Function(bool) onToggle;
  final Map<int, int> oroData;
  final Map<int, int> allyData;
  final int kMax;

  const _CurvesCard({
    required this.showOro,
    required this.onToggle,
    required this.oroData,
    required this.allyData,
    required this.kMax,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceVariant.withOpacity(.25),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: true, label: Text('Curva de Oro')),
            ButtonSegment(value: false, label: Text('Aliados')),
            ],
            selected: {showOro},
            onSelectionChanged: (s) => onToggle(s.first),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 160,
            child: _BarChartSimple(
              data: showOro ? oroData : allyData,
              kMax: kMax,
              labelStyle: const TextStyle(color: Colors.white70, fontSize: 11),
              color: showOro ? scheme.primary : scheme.secondary,
            ),
          ),
        ],
      ),
    );
  }
}

// ----------------- UI helpers -----------------

class _KpiCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final KpiTone tone;
  const _KpiCard({
    required this.icon,
    required this.label,
    required this.value,
    this.tone = KpiTone.neutral,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final Color bg = switch (tone) {
      KpiTone.warning => Colors.orange.withOpacity(.12),
      KpiTone.neutral => (isDark ? Colors.white10 : Colors.black12),
    };
    final Color border = switch (tone) {
      KpiTone.warning => Colors.orange.withOpacity(.5),
      KpiTone.neutral => (isDark ? Colors.white24 : Colors.black26),
    };
    final Color text = switch (tone) {
      KpiTone.warning => Colors.orangeAccent,
      KpiTone.neutral => Colors.white, // siempre blanco sobre fondo oscuro
    };

    return Container(
      width: 170,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: border),
      ),
      child: Row(
        children: [
          Icon(icon, color: text),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(value, style: TextStyle(color: text, fontWeight: FontWeight.w800, fontSize: 16)),
                const SizedBox(height: 2),
                Text(label, style: TextStyle(color: text.withOpacity(.8), fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

enum KpiTone { neutral, warning }

/// Donut de “Cantidad por tipo”
class _DonutByType extends StatelessWidget {
  final List<MapEntry<String, int>> entries;
  final Color onSurface;
  final Color background;

  const _DonutByType({
    required this.entries,
    required this.onSurface,
    required this.background,
  });

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      return Container(
        height: 160,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Text('Sin datos', style: TextStyle(color: Colors.white70)),
      );
    }

    final colors = _palette(context);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          SizedBox(
            height: 160,
            child: PieChart(
              PieChartData(
                sectionsSpace: 2,
                centerSpaceRadius: 40,
                sections: List.generate(entries.length, (i) {
                  final e = entries[i];
                  final value = e.value.toDouble();
                  return PieChartSectionData(
                    value: value,
                    color: colors[i % colors.length],
                    radius: 54,
                    title: '${e.value}',
                    titleStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12),
                  );
                }),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: List.generate(entries.length, (i) {
              final e = entries[i];
              return _LegendPill(color: colors[i % colors.length], text: e.key);
            }),
          ),
        ],
      ),
    );
  }

  List<Color> _palette(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return [
      scheme.primary,
      scheme.secondary,
      scheme.tertiary,
      Colors.pinkAccent.shade200,
      Colors.tealAccent.shade400,
      Colors.amberAccent.shade200,
      Colors.lightBlueAccent.shade200,
    ].map((c) => c.withOpacity(.9)).toList();
  }
}

class _LegendPill extends StatelessWidget {
  final Color color;
  final String text;
  const _LegendPill({required this.color, required this.text});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(.2),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Text(text, style: const TextStyle(color: Colors.white)),
        ],
      ),
    );
  }
}

/// Barras verticales simples (0..k y k+)
class _BarChartSimple extends StatelessWidget {
  final Map<int, int> data;
  final int kMax;
  final TextStyle labelStyle;
  final Color color;

  const _BarChartSimple({
    required this.data,
    required this.kMax,
    required this.labelStyle,
    required this.color,
  });

  

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bg = isDark ? Colors.white10 : Colors.black12;

    final maxY = (data.values.isEmpty ? 1 : data.values.reduce((a, b) => a > b ? a : b)).toDouble();
    final groups = List.generate(kMax + 1, (i) {
      final v = (data[i] ?? 0).toDouble();
      return BarChartGroupData(
        x: i,
        barsSpace: 0,
        barRods: [
          BarChartRodData(
            toY: v,
            color: color.withOpacity(.9),
            width: 16,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
          ),
        ],
      );
    });

    return Container(
      height: 180,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(16)),
      child: BarChart(
        BarChartData(
          maxY: (maxY == 0 ? 1 : maxY) * 1.15,
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            getDrawingHorizontalLine: (v) => FlLine(color: Colors.white12, strokeWidth: 1),
          ),
          borderData: FlBorderData(show: false),
          barGroups: groups,
          titlesData: FlTitlesData(
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 24,
                getTitlesWidget: (v, meta) {
                  if (v == 0) return const SizedBox.shrink();
                  return Text(v.toInt().toString(), style: const TextStyle(color: Colors.white54, fontSize: 10));
                },
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (v, meta) {
                  final i = v.toInt();
                  final txt = (i == kMax) ? '$kMax+' : '$i';
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(txt, style: const TextStyle(color: Colors.white70, fontSize: 11)),
                  );
                },
              ),
            ),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          barTouchData: BarTouchData(
            enabled: true,
            touchTooltipData: BarTouchTooltipData(
              tooltipPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              tooltipBgColor: Colors.black87,
              getTooltipItem: (group, groupIndex, rod, rodIndex) {
                final label = (group.x == kMax) ? '$kMax+' : '${group.x}';
                return BarTooltipItem(
                  '$label: ${rod.toY.toInt()}',
                  const TextStyle(color: Colors.white),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// Tarjeta de desglose por tipo (Top 5) con chips "Nx Nombre"
class _TypeBreakdownCard extends StatelessWidget {
  final String title;
  final List<({String typeKey, String label, int total})> topTypes;
  final Map<String, List<({String name, int count})>> breakdownByType;
  final String Function(String) displayTipo;

  const _TypeBreakdownCard({
    required this.title,
    required this.topTypes,
    required this.breakdownByType,
    required this.displayTipo,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceVariant.withOpacity(.25),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14),
          ),
          const SizedBox(height: 10),
          if (topTypes.isEmpty)
            const Text('Sin datos', style: TextStyle(color: Colors.white70))
          else
            Column(
              children: topTypes.map((t) {
                final list = (breakdownByType[t.typeKey] ?? const <({String name, int count})>[])
                    .where((e) => e.count > 0)
                    .toList()
                  ..sort((a, b) {
                    final byCount = b.count.compareTo(a.count);
                    return byCount != 0 ? byCount : a.name.compareTo(b.name);
                  });

                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.label_important_outline, size: 18, color: Colors.white70),
                          const SizedBox(width: 6),
                          Text(
                            '${t.label} • ${t.total}',
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      if (list.isEmpty)
                        const Text('—', style: TextStyle(color: Colors.white54))
                      else
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: list.map((e) {
                            return Chip(
                              label: Text('${e.count}x ${e.name}',
                                  style: TextStyle(color: isDark ? Colors.white : Colors.black87)),
                              backgroundColor: isDark ? Colors.white10 : Colors.black12,
                              side: BorderSide(color: isDark ? Colors.white24 : Colors.black26),
                              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              visualDensity: VisualDensity.compact,
                            );
                          }).toList(),
                        ),
                    ],
                  ),
                );
              }).toList(),
            ),
        ],
      ),
    );
  }
}

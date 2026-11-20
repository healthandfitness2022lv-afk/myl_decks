part of '../deck_details_screen.dart';

/// Estadísticas del mazo, calculadas desde las habilidades programadas
/// (ver `domain/analisis_mazo`).
class _DeckStatsSnapshot {
  final String deckName;
  final AnalisisMazo analisis;

  /// Imagen de cada carta del mazo, por nombre.
  final Map<String, String> imagenes;

  const _DeckStatsSnapshot({
    required this.deckName,
    required this.analisis,
    required this.imagenes,
  });

  int get total => analisis.total;
  int get oros => analisis.oros;
  double get avgCost =>
      analisis.curva.isEmpty ? double.nan : analisis.costeMedio;
  double get avgStrength =>
      analisis.fuerzaMedia == 0 ? double.nan : analisis.fuerzaMedia;

  factory _DeckStatsSnapshot.fromDeck(
    Deck deck, {
    required Map<String, CardMyL> cardsById,
    required Map<String, CardMyL> cardsByNameLower,
    required Map<String, String?> imgById,
  }) {
    CardMyL? resolver(DeckCardEntry entry) {
      final id = (entry.cardId ?? '').trim();
      return (id.isNotEmpty ? cardsById[id] : null) ??
          cardsByNameLower[entry.name.toLowerCase()];
    }

    final imagenes = <String, String>{};
    for (final entry in deck.cards) {
      final id = (entry.cardId ?? '').trim();
      final url =
          (id.isNotEmpty ? imgById[id] : null) ??
          _readCardImageUrl(resolver(entry)) ??
          '';
      if (url.isNotEmpty) imagenes[entry.name] = url;
    }
    return _DeckStatsSnapshot(
      deckName: deck.name.isEmpty ? 'Mazo' : deck.name,
      analisis: analizarMazo(deck, resolver: resolver),
      imagenes: imagenes,
    );
  }
}

String? _readCardImageUrl(CardMyL? card) {
  final url = card?.bestVariant?.imageFrontUrl?.trim() ?? '';
  return url.isEmpty ? null : DriveService.webSafeUrl(url);
}

const _nombresTipo = <String, String>{
  'aliado': 'Aliado',
  'talisman': 'Talismán',
  'arma': 'Arma',
  'totem': 'Tótem',
  'oro': 'Oro',
};

Color _colorPerfil(String perfil) {
  switch (perfil) {
    case 'Agro':
      return const Color(0xFFE5734A);
    case 'Control':
      return const Color(0xFF4FA3E0);
    case 'Combo':
      return const Color(0xFFB07CE8);
    default:
      return const Color(0xFFD8A12A);
  }
}

String _pct(double p) => '${(p * 100).round()}%';

class _DeckStatsDialog extends StatelessWidget {
  final _DeckStatsSnapshot stats;

  const _DeckStatsDialog({required this.stats});

  @override
  Widget build(BuildContext context) {
    final a = stats.analisis;
    final rolesConPuntos = a.rolesPrincipales;
    final maxPuntos =
        rolesConPuntos.isEmpty ? 1.0 : a.puntos[rolesConPuntos.first]!;

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
                          _StatPill(label: 'Cartas', value: '${a.total}'),
                          _StatPill(label: 'Oros', value: '${a.oros}'),
                          _StatPill(
                            label: 'Coste medio',
                            value:
                                stats.avgCost.isNaN
                                    ? '-'
                                    : a.costeMedio.toStringAsFixed(2),
                          ),
                          _StatPill(
                            label: 'Fuerza media',
                            value:
                                stats.avgStrength.isNaN
                                    ? '-'
                                    : a.fuerzaMedia.toStringAsFixed(2),
                          ),
                          _StatPill(
                            label: 'Fuerza por Oro',
                            value:
                                a.fuerzaPorOro == 0
                                    ? '-'
                                    : a.fuerzaPorOro.toStringAsFixed(2),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      if (!a.sinRoles) ...[
                        _StatsSection(
                          title: 'Perfil del mazo: ${a.perfil}',
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _VelocidadBar(
                                indice: a.indice,
                                color: _colorPerfil(a.perfil),
                              ),
                              const SizedBox(height: 10),
                              Text(
                                a.motivo,
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        _StatsSection(
                          title: 'Qué hace el mazo',
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Según las habilidades programadas de sus '
                                'cartas. Toca un rol para ver qué cartas lo '
                                'aportan.',
                                style: TextStyle(
                                  color: Colors.white54,
                                  fontSize: 12,
                                ),
                              ),
                              const SizedBox(height: 10),
                              for (final rol in rolesConPuntos)
                                _RolBar(
                                  nombre: nombresRol[rol]!,
                                  copias: a.copiasPorRol[rol] ?? 0,
                                  fraccion: a.puntos[rol]! / maxPuntos,
                                  onTap: () => _showRol(context, rol),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                      _StatsSection(
                        title: 'Consistencia',
                        child: Column(
                          children: [
                            _ProbRow(
                              label: '2 Oros en el turno 2',
                              p: a.consistencia.orosTurno2,
                            ),
                            _ProbRow(
                              label: '3 Oros en el turno 3',
                              p: a.consistencia.orosTurno3,
                            ),
                            _ProbRow(
                              label: '4 Oros en el turno 4',
                              p: a.consistencia.orosTurno4,
                            ),
                            if ((a.copiasPorRol['remocion'] ?? 0) > 0)
                              _ProbRow(
                                label: 'Remoción en la mano inicial',
                                p: a.consistencia.remocionInicial,
                              ),
                            if ((a.copiasPorRol['respuesta'] ?? 0) > 0)
                              _ProbRow(
                                label: 'Respuesta en la mano inicial',
                                p: a.consistencia.respuestaInicial,
                              ),
                            if ((a.copiasPorRol['ventaja'] ?? 0) > 0)
                              _ProbRow(
                                label: 'Robo o búsqueda en la mano inicial',
                                p: a.consistencia.ventajaInicial,
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      _StatsSection(
                        title: 'Distribución por tipo',
                        child: Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: [
                            for (final e in _nombresTipo.entries)
                              _TypeChip(
                                label: e.value,
                                value: a.porTipo[e.key] ?? 0,
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      _StatsSection(
                        title: 'Curva de coste',
                        child: _DeckStatsCurveChart(curve: a.curva),
                      ),
                      if (a.sinProgramar > 0) ...[
                        const SizedBox(height: 16),
                        Text(
                          '${a.sinProgramar} carta${a.sinProgramar == 1 ? '' : 's'} '
                          'de este mazo aún no tiene${a.sinProgramar == 1 ? '' : 'n'} '
                          'sus habilidades programadas y no cuenta${a.sinProgramar == 1 ? '' : 'n'} '
                          'en el perfil.',
                          style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 12,
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

  void _showRol(BuildContext context, String rol) {
    final cartas = stats.analisis.aportes[rol] ?? const <AporteRol>[];
    showDialog<void>(
      context: context,
      builder:
          (_) => AlertDialog(
            backgroundColor: const Color(0xFF141922),
            title: Text(
              nombresRol[rol]!,
              style: const TextStyle(color: Colors.white),
            ),
            content: SizedBox(
              width: 340,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    descripcionRol[rol]!,
                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                  const SizedBox(height: 12),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 420),
                    child: GridView.builder(
                      shrinkWrap: true,
                      itemCount: cartas.length,
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3,
                            mainAxisSpacing: 10,
                            crossAxisSpacing: 10,
                            childAspectRatio: 0.62,
                          ),
                      itemBuilder:
                          (context, i) => _RolCardTile(
                            nombre: cartas[i].nombre,
                            copias: cartas[i].copias,
                            imageUrl: stats.imagenes[cartas[i].nombre] ?? '',
                          ),
                    ),
                  ),
                ],
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

/// Barra Control ↔ Agro con la posición del mazo.
class _VelocidadBar extends StatelessWidget {
  final int indice;
  final Color color;

  const _VelocidadBar({required this.indice, required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        LayoutBuilder(
          builder: (context, c) {
            final x = (c.maxWidth - 14) * indice / 100;
            return SizedBox(
              height: 18,
              child: Stack(
                alignment: Alignment.centerLeft,
                children: [
                  Container(
                    height: 6,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(4),
                      gradient: const LinearGradient(
                        colors: [
                          Color(0xFF4FA3E0),
                          Color(0xFFD8A12A),
                          Color(0xFFE5734A),
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    left: x,
                    child: Container(
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Control',
              style: TextStyle(color: Colors.white54, fontSize: 11),
            ),
            Text(
              'Velocidad $indice de 100',
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
            const Text(
              'Agro',
              style: TextStyle(color: Colors.white54, fontSize: 11),
            ),
          ],
        ),
      ],
    );
  }
}

class _RolBar extends StatelessWidget {
  final String nombre;
  final int copias;
  final double fraccion;
  final VoidCallback onTap;

  const _RolBar({
    required this.nombre,
    required this.copias,
    required this.fraccion,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            SizedBox(
              width: 132,
              child: Text(
                nombre,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: fraccion.clamp(0.0, 1.0),
                  minHeight: 8,
                  backgroundColor: Colors.white10,
                  valueColor: const AlwaysStoppedAnimation(Color(0xFFD8A12A)),
                ),
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              width: 70,
              child: Text(
                '$copias carta${copias == 1 ? '' : 's'}',
                textAlign: TextAlign.right,
                style: const TextStyle(color: Colors.white60, fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProbRow extends StatelessWidget {
  final String label;
  final double p;

  const _ProbRow({required this.label, required this.p});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
          ),
          Text(
            _pct(p),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _RolCardTile extends StatelessWidget {
  final String nombre;
  final int copias;
  final String imageUrl;

  const _RolCardTile({
    required this.nombre,
    required this.copias,
    required this.imageUrl,
  });

  @override
  Widget build(BuildContext context) {
    Widget fallback() => Container(
      color: const Color(0xFF1A202A),
      alignment: Alignment.center,
      child: const Icon(
        Icons.image_not_supported_outlined,
        color: Colors.white38,
      ),
    );
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
                  imageUrl.isNotEmpty
                      ? Image.network(
                        DriveService.webSafeUrl(imageUrl),
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => fallback(),
                      )
                      : fallback(),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          nombre,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        Text(
          'x$copias',
          style: const TextStyle(
            color: Colors.white60,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

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
        color: Colors.white.withValues(alpha: .04),
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
        border: Border.all(
          color: const Color(0xFFF1D184).withValues(alpha: .22),
        ),
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
        color: Colors.black.withValues(alpha: .24),
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
    if (curve.isEmpty) {
      return const _EmptyStats(message: 'No hay datos de curva.');
    }
    // Rellena los costes intermedios sin cartas para que el eje sea continuo.
    final maxCoste = curve.keys.reduce(math.max);
    final entries = [
      for (var i = 0; i <= maxCoste; i++) MapEntry(i, curve[i] ?? 0),
    ];

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

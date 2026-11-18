// lib/screens/meta_stats_screen.dart
//
// Meta y tendencias, en dos miradas:
//   1. Lo que se juega: los mazos construidos en la app (razas, cartas y
//      qué tan agro o control son, según sus habilidades programadas).
//   2. Lo que gana: la matriz del simulador, publicada por el worker en
//      `config/meta_simulador`.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../domain/meta_comunidad.dart';
import '../services/card_service.dart';
import '../theme/app_theme.dart';
import '../widgets/skeletons.dart';
import 'tournaments/tournament_widgets.dart' show colorPerfil;

const _estilos = ['Agro', 'Medio', 'Control', 'Combo'];

class MetaStatsScreen extends StatefulWidget {
  const MetaStatsScreen({super.key});

  @override
  State<MetaStatsScreen> createState() => _MetaStatsScreenState();
}

class _MetaStatsScreenState extends State<MetaStatsScreen> {
  late Future<MetaComunidad> _comunidad = _cargarComunidad();
  late Future<Map<String, dynamic>?> _simulador = _cargarSimulador();

  Future<MetaComunidad> _cargarComunidad() async {
    final db = FirebaseFirestore.instance;
    final mazos = await db.collectionGroup('decks').get();
    final cartas = await CardService.catalogo();
    final porId = {for (final c in cartas) c.id: c};
    final porNombre = {
      for (final c in cartas) c.nombre.trim().toLowerCase(): c,
    };
    return agregarMeta(
      mazos.docs.map((d) => d.data()),
      resolver:
          (e) =>
              porId[(e.cardId ?? '').trim()] ??
              porNombre[e.name.trim().toLowerCase()],
    );
  }

  Future<Map<String, dynamic>?> _cargarSimulador() async {
    final doc =
        await FirebaseFirestore.instance.doc('config/meta_simulador').get();
    return doc.data();
  }

  void _recargar() => setState(() {
    _comunidad = _cargarComunidad();
    _simulador = _cargarSimulador();
  });

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Meta y tendencias'),
          actions: [
            IconButton(
              tooltip: 'Actualizar',
              icon: const Icon(Icons.refresh),
              onPressed: _recargar,
            ),
          ],
          bottom: const TabBar(
            tabs: [Tab(text: 'Lo que se juega'), Tab(text: 'Lo que gana')],
          ),
        ),
        body: TabBarView(children: [_tabComunidad(), _tabSimulador()]),
      ),
    );
  }

  Widget _centrado(List<Widget> hijos) => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 860),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final h in hijos) ...[h, const SizedBox(height: 14)],
            ],
          ),
        ),
      ),
    ],
  );

  // ── Lo que se juega ───────────────────────────────────────────────────────
  Widget _tabComunidad() {
    return FutureBuilder<MetaComunidad>(
      future: _comunidad,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return ListView(
            children: const [
              SizedBox(height: 8),
              SkeletonListTile(),
              SkeletonListTile(),
              SkeletonListTile(),
            ],
          );
        }
        if (snap.hasError) {
          return _Mensaje(
            'No se pudieron cargar los mazos de la comunidad.\n${snap.error}',
          );
        }
        final m = snap.data!;
        if (m.mazos == 0) {
          return const _Mensaje('Aún no hay mazos completos para analizar.');
        }
        List<MapEntry<String, int>> orden(Map<String, int> x) =>
            x.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
        final conEstilo = m.porEstilo.values.fold<int>(0, (s, v) => s + v);
        return _centrado([
          _Tarjeta(
            icono: Icons.insights_rounded,
            titulo: '${m.mazos} mazos completos analizados',
            child: const Text(
              'Todos los mazos de 40 cartas o más construidos en la app. '
              'Muestra qué arma la comunidad, no qué gana.',
              style: TextStyle(color: AppColors.textFaint, fontSize: 12),
            ),
          ),
          if (m.indiceMedio != null)
            _Tarjeta(
              icono: Icons.speed_rounded,
              titulo:
                  'Estilo del meta: ${lecturaIndice(m.indiceMedio!).toLowerCase()}',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _BarraEstilos(
                    reparto: {
                      for (final e in _estilos)
                        e: (m.porEstilo[e] ?? 0) / conEstilo,
                    },
                    detalle: {
                      for (final e in _estilos) e: '${m.porEstilo[e] ?? 0} mazos',
                    },
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Velocidad media ${m.indiceMedio} de 100 (0 = control, '
                    '100 = agro). El estilo de cada mazo sale de las '
                    'habilidades programadas de sus cartas y de su curva de '
                    'coste.',
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                    ),
                  ),
                  if (m.indicePorRaza.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    const _Subtitulo('Velocidad media por raza'),
                    for (final e in orden(m.indicePorRaza))
                      _Fila(
                        etiqueta: e.key,
                        valor: '${e.value} · ${lecturaIndice(e.value)}',
                        fraccion: e.value / 100,
                        color: colorPerfil(
                          e.value >= 62
                              ? 'Agro'
                              : e.value <= 38
                              ? 'Control'
                              : 'Medio',
                        ),
                      ),
                  ],
                ],
              ),
            ),
          _ranking('Razas más jugadas', Icons.groups_2_rounded, orden(m.porRaza), 'mazos'),
          _ranking('Ediciones más jugadas', Icons.layers_rounded, orden(m.porEdicion), 'mazos'),
          _ranking('Cartas en más mazos', Icons.style_rounded, m.cartasPorMazos, 'mazos'),
          _ranking('Cartas con más copias', Icons.copy_all_rounded, m.cartasPorCopias, 'copias'),
        ]);
      },
    );
  }

  Widget _ranking(
    String titulo,
    IconData icono,
    List<MapEntry<String, int>> entradas,
    String unidad,
  ) {
    if (entradas.isEmpty) return const SizedBox.shrink();
    final max = entradas.first.value;
    return _Tarjeta(
      icono: icono,
      titulo: titulo,
      child: Column(
        children: [
          for (final e in entradas.take(12))
            _Fila(
              etiqueta: e.key,
              valor: '${e.value} $unidad',
              fraccion: max == 0 ? 0 : e.value / max,
            ),
        ],
      ),
    );
  }

  // ── Lo que gana ───────────────────────────────────────────────────────────
  Widget _tabSimulador() {
    return FutureBuilder<Map<String, dynamic>?>(
      future: _simulador,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return _Mensaje('No se pudo cargar el meta simulado.\n${snap.error}');
        }
        final r = snap.data;
        final mp = (r?['metaPerfil'] as Map?)?.cast<String, dynamic>();
        if (r == null || mp == null) {
          return const _Mensaje(
            'Aún no se publica una matriz del simulador.\n\nSe genera en el '
            'computador del simulador (todos los mazos contra todos) y '
            'aparece aquí cuando termina.',
          );
        }
        Map<String, double> reparto(String clave) => {
          for (final e in _estilos)
            e: (((mp['reparto'] as Map?)?[clave] as Map?)?[e] as num?)
                    ?.toDouble() ??
                0,
        };
        num indice(String clave) =>
            ((mp['indiceMedio'] as Map?)?[clave] as num?) ?? 50;
        final ranking =
            (r['ranking'] as List? ?? const [])
                .whereType<Map>()
                .map((e) => e.cast<String, dynamic>())
                .toList();
        final porEstilo =
            (mp['scorePorEstilo'] as Map? ?? const {}).cast<String, dynamic>();
        final entre =
            (mp['entreEstilos'] as Map? ?? const {}).cast<String, dynamic>();
        final presentes = [
          for (final e in _estilos)
            if (entre.containsKey(e)) e,
        ];
        final creado = DateTime.tryParse('${r['creado'] ?? ''}')?.toLocal();
        final correlacion = mp['correlacionIndiceTurno'] as num?;

        Widget bloque(String titulo, String clave, String explicacion) =>
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$titulo · velocidad ${indice(clave).round()} '
                    '(${lecturaIndice(indice(clave)).toLowerCase()})',
                    style: const TextStyle(
                      color: AppColors.text,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  _BarraEstilos(reparto: reparto(clave)),
                  const SizedBox(height: 4),
                  Text(
                    explicacion,
                    style: const TextStyle(
                      color: AppColors.textFaint,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            );

        return _centrado([
          _Tarjeta(
            icono: Icons.science_outlined,
            titulo: 'Matriz del simulador',
            child: Text(
              [
                '${r['mazos']} mazos, todos contra todos',
                '${r['partidasPorCruce']} partidas por cruce',
                if (creado != null)
                  '${creado.day.toString().padLeft(2, '0')}/'
                      '${creado.month.toString().padLeft(2, '0')}/${creado.year}',
              ].join(' · '),
              style: const TextStyle(color: AppColors.textSecondary),
            ),
          ),
          _Tarjeta(
            icono: Icons.speed_rounded,
            titulo: '¿Qué tan agro o control está el meta?',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                bloque(
                  'Hoy',
                  'jugado',
                  'Los mazos de la matriz, con el peso que tiene cada uno.',
                ),
                bloque(
                  'Hacia dónde va',
                  'evolutivo',
                  'Si los jugadores se van pasando a lo que gana (10 generaciones).',
                ),
                bloque(
                  'Equilibrio',
                  'equilibrio',
                  'La mezcla a la que ningún mazo de la lista le saca ventaja.',
                ),
                if (correlacion != null)
                  Text(
                    'Verificación: los mazos con índice más agro ganan antes '
                    'en las partidas simuladas (correlación '
                    '${correlacion.toStringAsFixed(2)} con el turno de victoria).',
                    style: const TextStyle(
                      color: AppColors.textFaint,
                      fontSize: 12,
                    ),
                  ),
              ],
            ),
          ),
          if (porEstilo.isNotEmpty)
            _Tarjeta(
              icono: Icons.emoji_events_outlined,
              titulo: 'Qué estilo rinde más',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Porcentaje de victorias esperado contra el meta.',
                    style: TextStyle(color: AppColors.textFaint, fontSize: 12),
                  ),
                  const SizedBox(height: 6),
                  for (final e in _estilos)
                    if (porEstilo[e] != null)
                      _Fila(
                        etiqueta:
                            '$e (${(mp['mazos'] as Map?)?[e] ?? 0} mazos)',
                        valor:
                            '${((porEstilo[e] as num) * 100).toStringAsFixed(1)}%',
                        fraccion: (porEstilo[e] as num).toDouble(),
                        color: colorPerfil(e),
                      ),
                  if (presentes.length > 1) ...[
                    const SizedBox(height: 12),
                    const _Subtitulo('Estilo contra estilo (gana la fila)'),
                    Table(
                      defaultVerticalAlignment:
                          TableCellVerticalAlignment.middle,
                      children: [
                        TableRow(
                          children: [
                            const SizedBox.shrink(),
                            for (final b in presentes)
                              Padding(
                                padding: const EdgeInsets.all(6),
                                child: Text(
                                  b,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: colorPerfil(b),
                                    fontWeight: FontWeight.w800,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        for (final a in presentes)
                          TableRow(
                            children: [
                              Text(
                                a,
                                style: TextStyle(
                                  color: colorPerfil(a),
                                  fontWeight: FontWeight.w800,
                                  fontSize: 12,
                                ),
                              ),
                              for (final b in presentes)
                                _CeldaCruce(
                                  ((entre[a] as Map?)?[b] as Map?)
                                      ?.cast<String, dynamic>(),
                                ),
                            ],
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          _Tarjeta(
            icono: Icons.leaderboard_outlined,
            titulo: 'Mejores mazos contra el meta',
            child: Column(
              children: [
                for (var i = 0; i < ranking.length && i < 15; i++)
                  _FilaRanking(posicion: i + 1, fila: ranking[i]),
              ],
            ),
          ),
        ]);
      },
    );
  }
}

// ── Piezas ───────────────────────────────────────────────────────────────────

class _Mensaje extends StatelessWidget {
  final String texto;
  const _Mensaje(this.texto);

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Text(
        texto,
        textAlign: TextAlign.center,
        style: const TextStyle(color: AppColors.textSecondary),
      ),
    ),
  );
}

class _Tarjeta extends StatelessWidget {
  final IconData icono;
  final String titulo;
  final Widget child;
  const _Tarjeta({
    required this.icono,
    required this.titulo,
    required this.child,
  });

  @override
  Widget build(BuildContext context) => Container(
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
            Icon(icono, color: AppColors.gold, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                titulo,
                style: const TextStyle(
                  color: AppColors.text,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        child,
      ],
    ),
  );
}

class _Subtitulo extends StatelessWidget {
  final String texto;
  const _Subtitulo(this.texto);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(
      texto,
      style: const TextStyle(
        color: AppColors.textFaint,
        fontSize: 12,
        fontWeight: FontWeight.w800,
      ),
    ),
  );
}

/// Barra apilada Agro / Medio / Control / Combo con su leyenda.
class _BarraEstilos extends StatelessWidget {
  /// estilo → fracción (0–1).
  final Map<String, double> reparto;

  /// Texto extra por estilo en la leyenda (opcional).
  final Map<String, String> detalle;
  const _BarraEstilos({required this.reparto, this.detalle = const {}});

  @override
  Widget build(BuildContext context) {
    final presentes = [
      for (final e in _estilos)
        if ((reparto[e] ?? 0) > 0.004) e,
    ];
    if (presentes.isEmpty) {
      return const Text(
        'Sin datos',
        style: TextStyle(color: AppColors.textFaint),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: Row(
            children: [
              for (final e in presentes)
                Expanded(
                  flex: (reparto[e]! * 1000).round().clamp(1, 1000),
                  child: Container(height: 14, color: colorPerfil(e)),
                ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 12,
          runSpacing: 4,
          children: [
            for (final e in presentes)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 9,
                    height: 9,
                    decoration: BoxDecoration(
                      color: colorPerfil(e),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    '$e ${(reparto[e]! * 100).round()}%'
                    '${detalle[e] == null ? '' : ' · ${detalle[e]}'}',
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
          ],
        ),
      ],
    );
  }
}

class _Fila extends StatelessWidget {
  final String etiqueta;
  final String valor;
  final double fraccion;
  final Color color;
  const _Fila({
    required this.etiqueta,
    required this.valor,
    required this.fraccion,
    this.color = AppColors.goldStrong,
  });

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Column(
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                etiqueta,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: AppColors.text, fontSize: 13),
              ),
            ),
            Text(
              valor,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 3),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: fraccion.clamp(0.0, 1.0),
            minHeight: 5,
            backgroundColor: AppColors.surfaceDeep,
            valueColor: AlwaysStoppedAnimation(color),
          ),
        ),
      ],
    ),
  );
}

class _CeldaCruce extends StatelessWidget {
  final Map<String, dynamic>? cruce;
  const _CeldaCruce(this.cruce);

  @override
  Widget build(BuildContext context) {
    final wr = (cruce?['winrate'] as num?)?.toDouble();
    final color =
        wr == null
            ? AppColors.textFaint
            : wr >= 0.55
            ? AppColors.success
            : wr <= 0.45
            ? AppColors.danger
            : AppColors.textSecondary;
    return Padding(
      padding: const EdgeInsets.all(6),
      child: Text(
        wr == null ? '—' : '${(wr * 100).round()}%',
        textAlign: TextAlign.center,
        style: TextStyle(color: color, fontWeight: FontWeight.w800),
      ),
    );
  }
}

class _FilaRanking extends StatelessWidget {
  final int posicion;
  final Map<String, dynamic> fila;
  const _FilaRanking({required this.posicion, required this.fila});

  @override
  Widget build(BuildContext context) {
    final perfil = (fila['perfil'] ?? '').toString();
    final turno = fila['turnoVictoria'] as num?;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          SizedBox(
            width: 28,
            child: Text(
              '$posicion',
              style: TextStyle(
                color: posicion <= 3 ? AppColors.gold : AppColors.textFaint,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  (fila['nombre'] ?? '').toString(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.text,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  [
                    if ((fila['raza'] ?? '').toString().isNotEmpty) fila['raza'],
                    if (perfil.isNotEmpty) '$perfil ${fila['indice'] ?? ''}',
                    if (turno != null) 'gana en el turno ${turno.toStringAsFixed(turno % 1 == 0 ? 0 : 1)}',
                  ].join(' · '),
                  style: TextStyle(
                    color: perfil.isEmpty ? AppColors.textFaint : colorPerfil(perfil),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          Text(
            '${(((fila['score'] as num?) ?? 0) * 100).toStringAsFixed(1)}%',
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

// lib/screens/simulador/simulador_screen.dart
//
// Simulador de partidas (solo el dueño). Crea simulations/{id} con estado
// "pending"; el worker Python en el PC del dueño la procesa y escribe el
// resultado (ver simulator/myl_sim/worker.py).

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../models/deck.dart';
import 'cartas_por_completar.dart';
import 'desafio_ia_screen.dart';
import 'entrenamiento_screen.dart';
import 'estado_mazos.dart';
import 'narracion_texto.dart';
import 'tablero_screen.dart';
import '../../services/deck_service.dart';
import '../../services/notable_deck_service.dart';
import '../notable_decks_screen.dart';

const _bg = Color(0xFF0F181B);
const _surface = Color(0xFF132126);
const _gold = Color(0xFFF2D487);
const _green = Color(0xFF34D399);
const _red = Color(0xFFF87171);
const _orange = Color(0xFFF59E0B);

/// IA de las simulaciones: la rápida es la heurística; la buena decide la
/// Vigilia (incluye "pasar") y los ataques simulando (≈20 veces más lenta).
const _ias = {'heuristico': 'IA rápida', 'busqueda_vigilia': 'IA buena'};
String _nombreIa(Object? j) => _ias['${j ?? 'heuristico'}'] ?? '$j';

final _sims = FirebaseFirestore.instance.collection('simulations');
final _estadoWorker = FirebaseFirestore.instance.doc('simulator_status/worker');

/// El worker avisa cada 30 s; con 2 minutos sin noticias se da por apagado.
bool _workerActivo(DateTime? visto) =>
    visto != null && DateTime.now().difference(visto).inSeconds < 120;

class SimuladorScreen extends StatefulWidget {
  const SimuladorScreen({super.key});

  @override
  State<SimuladorScreen> createState() => _SimuladorScreenState();
}

class _SimuladorScreenState extends State<SimuladorScreen> {
  final _uid = FirebaseAuth.instance.currentUser!.uid;
  late final Stream<List<Deck>> _decks;

  @override
  void initState() {
    super.initState();
    _decks = soloMazosValidos(_watchDecks());
  }

  Stream<List<Deck>> _watchDecks() {
    late final StreamController<List<Deck>> controller;
    StreamSubscription<List<Deck>>? ownSub;
    StreamSubscription<List<Deck>>? notableSub;
    var own = <Deck>[];
    var notable = <Deck>[];
    var ownReady = false;
    var notableReady = false;
    void emit() {
      if (ownReady && notableReady) controller.add([...own, ...notable]);
    }
    controller = StreamController<List<Deck>>(
      onListen: () {
        ownSub = DeckService(_uid).watchMyDecks().listen(
          (value) { own = value; ownReady = true; emit(); },
          onError: controller.addError,
        );
        notableSub = NotableDeckService(_uid).watch().listen(
          (value) { notable = value; notableReady = true; emit(); },
          onError: controller.addError,
        );
      },
      onCancel: () async {
        await ownSub?.cancel();
        await notableSub?.cancel();
      },
    );
    return controller.stream;
  }
  // Solo el dueño puede leer simulations (reglas), así que no hace falta
  // filtrar por ownerUid (y se evita un índice compuesto).
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _historial =
      _sims.orderBy('createdAt', descending: true).limit(20).snapshots();
  String? _a, _b;
  int _n = 1000;
  bool _enviando = false;
  String _jugador = 'heuristico';
  bool _comparar = false;
  final _semilla = TextEditingController();

  @override
  void dispose() {
    _semilla.dispose();
    super.dispose();
  }

  /// Cartas de los mazos elegidos que aún no están completas (null = cargando).
  int? _pendientes;

  Future<void> _lanzar() async {
    if (_a == null || _b == null) return;
    setState(() => _enviando = true);
    try {
      // Misma semilla = mismos barajados y dados: sirve para comparar IAs.
      final seed = int.tryParse(_semilla.text.trim()) ??
          DateTime.now().millisecondsSinceEpoch % 100000;
      for (final jugador in _comparar ? _ias.keys : [_jugador]) {
        await _sims.add({
          'ownerUid': _uid,
          'createdBy': FirebaseAuth.instance.currentUser?.email,
          'deckA': _a,
          'deckB': _b,
          'n': _n,
          'seed': seed,
          'jugador': jugador,
          if (_comparar) 'comparacion': seed,
          'status': 'pending',
          'createdAt': FieldValue.serverTimestamp(),
        });
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('No se pudo crear: $e')));
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A120C),
        title: const Text(
          'Simulador de partidas',
          style: TextStyle(color: _gold, fontWeight: FontWeight.bold),
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: ListView(
            padding: const EdgeInsets.all(12),
            children: [
              Card(
                color: const Color(0xFF1A120C),
                child: ListTile(
                  leading: const Icon(Icons.smart_toy_outlined, color: _gold),
                  title: const Text(
                    'Desafío IA',
                    style: TextStyle(color: _gold, fontWeight: FontWeight.bold),
                  ),
                  subtitle: const Text(
                    'Juega tú contra la IA, sin side deck.',
                    style: TextStyle(color: Colors.white70),
                  ),
                  trailing: const Icon(Icons.chevron_right, color: _gold),
                  onTap:
                      () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const DesafioIaScreen(),
                        ),
                      ),
                ),
              ),
              const SizedBox(height: 12),
              Card(
                color: const Color(0xFF1A120C),
                child: ListTile(
                  leading: const Icon(Icons.fitness_center_rounded, color: _gold),
                  title: const Text(
                    'ELO',
                    style: TextStyle(color: _gold, fontWeight: FontWeight.bold),
                  ),
                  subtitle: const Text(
                    'Escalera de rivales cada vez más difíciles, con rating.',
                    style: TextStyle(color: Colors.white70),
                  ),
                  trailing: const Icon(Icons.chevron_right, color: _gold),
                  onTap:
                      () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const EntrenamientoScreen(),
                        ),
                      ),
                ),
              ),
              const SizedBox(height: 12),
              Card(
                color: const Color(0xFF1A120C),
                child: ListTile(
                  leading: const Icon(Icons.workspace_premium_outlined, color: _gold),
                  title: const Text('Barajas notables', style: TextStyle(color: _gold, fontWeight: FontWeight.bold)),
                  subtitle: const Text('Listas de torneos para probar y entrenar contra ellas.', style: TextStyle(color: Colors.white70)),
                  trailing: const Icon(Icons.chevron_right, color: _gold),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const NotableDecksScreen())),
                ),
              ),
              const SizedBox(height: 12),
              _nuevaSimulacion(),
              const SizedBox(height: 16),
              const Text(
                'SIMULACIONES',
                style: TextStyle(
                  color: _gold,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(height: 8),
              const _EstadoWorker(),
              const SizedBox(height: 10),
              StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: _historial,
                builder: (context, snap) {
                  if (snap.hasError) {
                    return Text(
                      'No se pudo cargar: ${snap.error}',
                      style: const TextStyle(color: _red),
                    );
                  }
                  final docs = snap.data?.docs ?? const [];
                  if (docs.isEmpty) {
                    return const Text(
                      'Aún no hay simulaciones.',
                      style: TextStyle(color: Colors.white54),
                    );
                  }
                  return Column(
                    children: [for (final d in docs) _SimulacionCard(doc: d)],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _nuevaSimulacion() => Card(
    color: _surface,
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: StreamBuilder<List<Deck>>(
        stream: _decks,
        builder: (context, snap) {
          final decks = [...snap.data ?? const <Deck>[]]..sort(
            (x, y) => x.name.toLowerCase().compareTo(y.name.toLowerCase()),
          );
          return EstadosMazos(
            mazos: decks,
            builder: (context, estados) {
              DropdownButtonFormField<String> selector(
                String label,
                String? value,
                ValueChanged<String?> onChanged,
              ) => DropdownButtonFormField<String>(
                initialValue: decks.any((d) => d.id == value) ? value : null,
                isExpanded: true,
                dropdownColor: _surface,
                decoration: InputDecoration(labelText: label),
                items: [
                  for (final d in decks)
                    DropdownMenuItem(
                      value: d.id,
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${d.name} · ${_formato(d.format)} · ${d.cards.fold<int>(0, (s, c) => s + c.count)} cartas',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          IconoEstadoMazo(estados[d.id]),
                        ],
                      ),
                    ),
                ],
                onChanged: onChanged,
              );
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Enfrenta dos mazos N veces. Las cartas que no marcaste como '
                    'programadas se juegan sin habilidad. El cálculo lo hace el '
                    'worker en tu PC: debe estar corriendo '
                    '(simulator/  →  .venv/Scripts/python -m myl_sim.worker).',
                    style: TextStyle(color: Colors.white60, fontSize: 12),
                  ),
                  const SizedBox(height: 12),
                  selector(
                    'Mazo A',
                    _a,
                    (v) => setState(() {
                      _a = v;
                      _pendientes = null;
                    }),
                  ),
                  const SizedBox(height: 6),
                  const Wrap(
                    spacing: 12,
                    runSpacing: 4,
                    children: [
                      _LeyendaEstadoMazo(EstadoMazo.programado, 'Programado'),
                      _LeyendaEstadoMazo(
                        EstadoMazo.textoCompleto,
                        'Textos escritos',
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  selector(
                    'Mazo B',
                    _b,
                    (v) => setState(() {
                      _b = v;
                      _pendientes = null;
                    }),
                  ),
                  if (_a != null && _b != null) ...[
                    const SizedBox(height: 12),
                    CartasPorCompletar(
                      key: ValueKey('$_a|$_b'),
                      mazos: [
                        for (final id in {_a!, _b!})
                          ...decks.where((d) => d.id == id),
                      ],
                      onPendientes: (n) {
                        if (n != _pendientes) {
                          WidgetsBinding.instance.addPostFrameCallback(
                            (_) =>
                                mounted
                                    ? setState(() => _pendientes = n)
                                    : null,
                          );
                        }
                      },
                    ),
                  ],
                  const SizedBox(height: 12),
                  SegmentedButton<String>(
                    segments: [
                      for (final e in _ias.entries)
                        ButtonSegment(value: e.key, label: Text(e.value)),
                    ],
                    selected: {_jugador},
                    onSelectionChanged:
                        _comparar ? null : (s) => setState(() => _jugador = s.first),
                  ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    value: _comparar,
                    onChanged: (v) => setState(() => _comparar = v ?? false),
                    title: const Text(
                      'Comparar IA rápida vs IA buena (misma semilla)',
                      style: TextStyle(color: Colors.white),
                    ),
                    subtitle: const Text(
                      'Crea dos simulaciones iguales, una con cada IA. La IA buena '
                      'tarda ~6 s por partida: usa 1 narrada o 100.',
                      style: TextStyle(color: Colors.white54, fontSize: 11),
                    ),
                  ),
                  TextField(
                    controller: _semilla,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Semilla (opcional, vacío = al azar)',
                    ),
                  ),
                  const SizedBox(height: 12),
                  SegmentedButton<int>(
                    segments: const [
                      ButtonSegment(value: 1, label: Text('1 narrada')),
                      ButtonSegment(value: 100, label: Text('100')),
                      ButtonSegment(value: 1000, label: Text('1.000')),
                      ButtonSegment(value: 10000, label: Text('10.000')),
                    ],
                    selected: {_n},
                    onSelectionChanged: (s) => setState(() => _n = s.first),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: _gold,
                      foregroundColor: Colors.black,
                    ),
                    onPressed:
                        _a == null ||
                                _b == null ||
                                _enviando ||
                                _pendientes != 0
                            ? null
                            : _lanzar,
                    icon: const Icon(Icons.play_arrow_rounded),
                    label: Text(
                      (_pendientes ?? 0) > 0
                          ? 'Completa las cartas para simular'
                          : 'Simular',
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    ),
  );
}

class _LeyendaEstadoMazo extends StatelessWidget {
  final EstadoMazo estado;
  final String texto;
  const _LeyendaEstadoMazo(this.estado, this.texto);

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      IconoEstadoMazo(estado),
      const SizedBox(width: 4),
      Text(texto, style: const TextStyle(color: Colors.white60, fontSize: 11)),
    ],
  );
}

String _formato(DeckFormat f) => switch (f) {
  DeckFormat.racial => 'Racial Edición',
  DeckFormat.racialLibre => 'Racial Libre',
  DeckFormat.full => 'Libre',
};

String _pct(num? x) => x == null ? '–' : '${(x * 100).toStringAsFixed(1)}%';

/// "Worker activo" o "apagado hace X": sin él, las simulaciones esperan.
class _EstadoWorker extends StatefulWidget {
  const _EstadoWorker();

  @override
  State<_EstadoWorker> createState() => _EstadoWorkerState();
}

class _EstadoWorkerState extends State<_EstadoWorker> {
  late final Timer _reloj;

  @override
  void initState() {
    super.initState();
    // Refresca el "hace X" aunque no lleguen datos nuevos.
    _reloj = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _reloj.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: _estadoWorker.snapshots(),
        builder: (context, snap) {
          final visto =
              (snap.data?.data()?['lastSeen'] as Timestamp?)?.toDate();
          final activo = _workerActivo(visto);
          final hace =
              visto == null
                  ? 'nunca se ha conectado'
                  : 'última señal hace ${_haceCuanto(visto)}';
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: (activo ? _green : _red).withValues(alpha: .12),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: (activo ? _green : _red).withValues(alpha: .5),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  activo ? Icons.memory : Icons.power_off,
                  color: activo ? _green : _red,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    activo
                        ? 'Worker activo en el PC · $hace'
                        : 'Worker apagado · $hace. Las simulaciones esperarán '
                            'en cola hasta que lo enciendas.',
                    style: TextStyle(
                      color: activo ? _green : _red,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      );
}

String _haceCuanto(DateTime t) {
  final d = DateTime.now().difference(t);
  if (d.inSeconds < 60) return '${d.inSeconds} s';
  if (d.inMinutes < 60) return '${d.inMinutes} min';
  if (d.inHours < 48) return '${d.inHours} h';
  return '${d.inDays} días';
}

class _SimulacionCard extends StatelessWidget {
  final QueryDocumentSnapshot<Map<String, dynamic>> doc;
  const _SimulacionCard({required this.doc});

  @override
  Widget build(BuildContext context) {
    final d = doc.data();
    final status = (d['status'] ?? '').toString();
    final r = (d['resultado'] as Map?)?.cast<String, dynamic>();
    final a = (r?['mazoA'] as Map?)?['nombre'] ?? d['deckA'];
    final b = (r?['mazoB'] as Map?)?['nombre'] ?? d['deckB'];
    return Card(
      color: _surface,
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '$a  vs  $b',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Text(
                  '${d['n']} partidas · ${_nombreIa(d['jugador'])} · semilla ${d['seed']}',
                  style: const TextStyle(color: Colors.white54),
                ),
                IconButton(
                  tooltip: 'Eliminar',
                  icon: const Icon(Icons.delete_outline, color: Colors.white38),
                  onPressed: () => doc.reference.delete(),
                ),
              ],
            ),
            if (status == 'pending')
              StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                stream: _estadoWorker.snapshots(),
                builder: (context, snap) {
                  final visto =
                      (snap.data?.data()?['lastSeen'] as Timestamp?)?.toDate();
                  final activo = _workerActivo(visto);
                  return Text(
                    activo
                        ? 'En cola: el worker la tomará en segundos…'
                        : 'En cola, pero el worker está apagado: enciéndelo en '
                            'el PC (python -m myl_sim.worker) y partirá sola.',
                    style: TextStyle(color: activo ? _orange : _red),
                  );
                },
              ),
            if (status == 'running') ...[
              LinearProgressIndicator(
                value: (d['progreso'] as num?)?.toDouble(),
                color: _gold,
              ),
              if (d['parcial'] is Map)
                _Metricas(
                  m: (d['parcial'] as Map).cast<String, dynamic>(),
                  a: '$a',
                  b: '$b',
                  total: (d['n'] as num?)?.toInt() ?? 0,
                  enVivo: true,
                ),
            ],
            if (status == 'error')
              Text('Error: ${d['error']}', style: const TextStyle(color: _red)),
            if (status == 'done' && r != null)
              r['narracion'] is List
                  ? _PartidaNarrada(r: r, doc: doc)
                  : _Informe(r: r),
          ],
        ),
      ),
    );
  }
}

/// Métricas de una simulación de N partidas: en vivo (parcial que escribe el
/// worker cada 1,5 s) o finales. Turno = ronda en que ambos jugaron.
class _Metricas extends StatelessWidget {
  final Map<String, dynamic> m;
  final String a;
  final String b;
  final int total;
  final bool enVivo;

  const _Metricas({
    required this.m,
    required this.a,
    required this.b,
    required this.total,
    this.enVivo = false,
  });

  @override
  Widget build(BuildContext context) {
    final jugadas = (m['jugadas'] as num?)?.toInt() ?? 0;
    final va = (m['victoriasA'] as num?)?.toInt() ?? 0;
    final vb = (m['victoriasB'] as num?)?.toInt() ?? 0;
    final emp = (m['empates'] as num?)?.toInt() ?? 0;
    final validas = va + vb + emp;
    final la = (m['ladoA'] as Map?)?.cast<String, dynamic>() ?? const {};
    final lb = (m['ladoB'] as Map?)?.cast<String, dynamic>() ?? const {};

    String curva(Map<String, dynamic> l) {
      final ev = (l['evaluadasCurva'] as num?)?.toInt() ?? 0;
      final f = (l['fallaCurva'] as num?)?.toInt() ?? 0;
      return ev == 0 ? '–' : '$f (${_pct(f / ev)})';
    }

    String mull(Map<String, dynamic> l) {
      final c = (l['conMulligan'] as num?)?.toInt() ?? 0;
      return validas == 0 ? '–' : '$c (${_pct(c / validas)})';
    }

    Widget celda(String titulo, String valor, {Color color = Colors.white}) =>
        Container(
          width: 150,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: .05),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                titulo,
                style: const TextStyle(color: Colors.white54, fontSize: 11),
              ),
              const SizedBox(height: 2),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: Text(
                  valor,
                  key: ValueKey(valor),
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
              ),
            ],
          ),
        );

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (enVivo)
            Text(
              'Partida $jugadas de $total',
              style: const TextStyle(color: _gold, fontWeight: FontWeight.w700),
            ),
          const SizedBox(height: 6),
          _FranjaResultados(
            resultados: '${m['resultados'] ?? ''}',
            total: total,
          ),
          const SizedBox(height: 4),
          Text(
            'Cada cuadro es una partida · verde: $a · rojo: $b',
            style: const TextStyle(color: Colors.white38, fontSize: 11),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              celda('Victorias $a', '$va', color: _green),
              celda('Victorias $b', '$vb', color: _red),
              celda(
                'Winrate $a',
                validas == 0 ? '–' : _pct((va + emp / 2) / validas),
              ),
              celda(
                'Gana quien gana el dado',
                validas == 0 ? '–' : _pct(m['winrateGanaDado'] as num?),
              ),
              celda(
                'Dados ganados $a / $b',
                '${la['ganaDado'] ?? 0} / ${lb['ganaDado'] ?? 0}',
              ),
              celda(
                'Turnos promedio',
                ((m['rondasPromedio'] as num?) ?? 0).toStringAsFixed(1),
              ),
              celda('Sin 5 Oros en turno 4 · $a', curva(la), color: _orange),
              celda('Sin 5 Oros en turno 4 · $b', curva(lb), color: _orange),
              celda('Con mulligan · $a', mull(la)),
              celda('Con mulligan · $b', mull(lb)),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Ojo: ambos mazos los juega la máquina con reglas simples. Mide el '
            'mazo en manos de la máquina, no el de un jugador real.',
            style: TextStyle(color: Colors.white38, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

/// Una celda por partida, coloreada según quién ganó; las que faltan, oscuras.
class _FranjaResultados extends StatelessWidget {
  final String resultados;
  final int total;
  const _FranjaResultados({required this.resultados, required this.total});

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(4),
    child: SizedBox(
      height: 18,
      width: double.infinity,
      child: CustomPaint(painter: _PintorResultados(resultados, total)),
    ),
  );
}

class _PintorResultados extends CustomPainter {
  final String resultados;
  final int total;
  _PintorResultados(this.resultados, this.total);

  @override
  void paint(Canvas canvas, Size size) {
    final n = total > 0 ? total : resultados.length;
    if (n == 0) return;
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = Colors.white.withValues(alpha: .06),
    );
    final w = size.width / n;
    final hueco = w > 4 ? 1.0 : 0.0;
    for (var k = 0; k < resultados.length && k < n; k++) {
      final color = switch (resultados[k]) {
        'A' => _green,
        'B' => _red,
        'E' => Colors.white54,
        _ => _orange,
      };
      canvas.drawRect(
        Rect.fromLTWH(k * w, 0, w - hueco, size.height),
        Paint()..color = color,
      );
    }
  }

  @override
  bool shouldRepaint(_PintorResultados old) =>
      old.resultados != resultados || old.total != total;
}

class _Informe extends StatelessWidget {
  final Map<String, dynamic> r;
  const _Informe({required this.r});

  @override
  Widget build(BuildContext context) {
    final a = (r['mazoA'] as Map)['nombre'];
    final b = (r['mazoB'] as Map)['nombre'];
    final wr = (r['winrateA'] as num).toDouble();
    final ic = (r['ic95A'] as List).cast<num>();
    final v = (r['ventajaInicial'] as Map).cast<String, dynamic>();
    final t = (r['turnos'] as Map).cast<String, dynamic>();
    final causas = (r['causas'] as List).cast<Map>();
    final pendA = (r['sinProgramarA'] as List? ?? const []).cast<Map>();
    final pendB = (r['sinProgramarB'] as List? ?? const []).cast<Map>();

    Widget fila(String k, String v) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: Text(k, style: const TextStyle(color: Colors.white60)),
          ),
          Text(
            v,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: SizedBox(
            height: 22,
            child: Row(
              children: [
                Expanded(
                  flex: (wr * 1000).round().clamp(1, 999),
                  child: Container(
                    color: _green,
                    alignment: Alignment.center,
                    child: Text(
                      _pct(wr),
                      style: const TextStyle(
                        color: Colors.black,
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
                Expanded(
                  flex: ((1 - wr) * 1000).round().clamp(1, 999),
                  child: Container(
                    color: _red,
                    alignment: Alignment.center,
                    child: Text(
                      _pct(1 - wr),
                      style: const TextStyle(
                        color: Colors.black,
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Verde: $a · Rojo: $b',
          style: const TextStyle(color: Colors.white38, fontSize: 11),
        ),
        if (r['resultados'] is String)
          _Metricas(
            m: r,
            a: '$a',
            b: '$b',
            total: (r['partidas'] as num).toInt(),
          ),
        const SizedBox(height: 8),
        fila(
          'Winrate de $a (IC 95 %)',
          '${_pct(wr)}  (${_pct(ic[0])} – ${_pct(ic[1])})',
        ),
        fila(
          'Victorias A / B / empates',
          '${r['victoriasA']} / ${r['victoriasB']} / ${r['empates']}',
        ),
        if (v['dadosA'] != null)
          fila('Dados ganados $a / $b', '${v['dadosA']} / ${v['dadosB']}'),
        fila(
          'Gana el que ganó el dado (empieza)',
          _pct(v['winrateDelQueEmpieza'] as num?),
        ),
        fila(
          '$a cuando el dado lo gana A / B',
          '${_pct((v['aEmpieza'] as Map)['winrateA'] as num?)} / ${_pct((v['bEmpieza'] as Map)['winrateA'] as num?)}',
        ),
        fila(
          'Turnos completos (promedio · rango)',
          '${(t['promedio'] as num).toStringAsFixed(1)} · ${t['min']}–${t['max']}',
        ),
        for (final c in causas)
          fila(
            'Gana ${c['ganador'] == 'A' ? a : b} por ${_causa('${c['causa']}')}',
            '${c['partidas']}',
          ),
        if ((r['anomalas'] as num? ?? 0) > 0)
          fila('⚠ Partidas anómalas (no cuentan)', '${r['anomalas']}'),
        if (pendA.isNotEmpty || pendB.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(top: 10),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: _orange.withValues(alpha: .1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: _orange.withValues(alpha: .4)),
            ),
            child: Text(
              '⚠ Resultado provisorio: $a tiene ${pendA.length} y $b '
              'tiene ${pendB.length} cartas sin programar (se jugaron sin '
              'habilidad).',
              style: const TextStyle(color: _orange, fontSize: 12),
            ),
          ),
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          title: const Text(
            'Impacto por carta',
            style: TextStyle(color: _gold),
          ),
          subtitle: const Text(
            'Winrate cuando la carta se jugó, menos cuando no. Es correlación: '
            'las cartas caras aparecen más en partidas largas.',
            style: TextStyle(color: Colors.white38, fontSize: 11),
          ),
          children: [
            _TablaImpacto(titulo: '$a', filas: r['impactoA'] as List),
            const SizedBox(height: 10),
            _TablaImpacto(titulo: '$b', filas: r['impactoB'] as List),
          ],
        ),
        if (pendA.isNotEmpty || pendB.isNotEmpty)
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: const Text(
              'Cartas sin programar',
              style: TextStyle(color: _orange),
            ),
            children: [
              for (final (nombre, lista) in [('$a', pendA), ('$b', pendB)])
                if (lista.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      '$nombre: ${lista.map((x) => '${x['carta']} ×${x['copias']}').join(', ')}',
                      style: const TextStyle(color: Colors.white70),
                    ),
                  ),
            ],
          ),
      ],
    );
  }
}

/// Una sola partida: quién ganó y la narración turno a turno.
class _PartidaNarrada extends StatelessWidget {
  final Map<String, dynamic> r;
  final QueryDocumentSnapshot<Map<String, dynamic>> doc;
  const _PartidaNarrada({required this.r, required this.doc});

  /// Vuelve a jugar la misma partida (mismos mazos y semilla): sirve para
  /// comprobar un arreglo del motor sobre la jugada reportada.
  Future<void> _repetir(BuildContext context, {String? jugador}) async {
    final d = doc.data();
    // Con cartas sin marcar como programadas no se repite: el motor las
    // jugaría sin habilidades. Antes se muestran para ir a marcarlas.
    final svc = DeckService('${d['ownerUid']}');
    final mazos = <Deck>[
      for (final id in {'${d['deckA']}', '${d['deckB']}'})
        if (await svc.getById(id) case final Deck m) m,
    ];
    if (!context.mounted) return;
    final listas = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: _surface,
      builder: (_) => _AntesDeRepetir(mazos: mazos),
    );
    if (listas != true || !context.mounted) return;
    try {
      await _sims.add({
        'ownerUid': d['ownerUid'],
        'createdBy': FirebaseAuth.instance.currentUser?.email,
        'deckA': d['deckA'],
        'deckB': d['deckB'],
        'n': 1,
        'seed': d['seed'],
        // Partidas anteriores al dado: se repite con el mismo jugador inicial
        // para que el barajado salga igual.
        if (r['dado'] == null)
          'inicial': r['empieza'] == (r['mazoA'] as Map)['nombre'] ? 0 : 1
        else
          'inicial': d['inicial'],
        'jugador': jugador ?? d['jugador'] ?? 'heuristico',
        'status': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('No se pudo crear: $e')));
    }
  }

  Widget _reportes() {
    final reportes = ((doc.data()['reportes'] as List?) ?? []).cast<Map>();
    if (reportes.isEmpty) return const SizedBox.shrink();
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      initiallyExpanded: true,
      title: Text(
        'Reportes (${reportes.length})',
        style: const TextStyle(color: _orange, fontWeight: FontWeight.w700),
      ),
      subtitle: const Text(
        'Pídele a Claude que revise los reportes del simulador. Bórralos '
        'cuando estén resueltos.',
        style: TextStyle(color: Colors.white38, fontSize: 11),
      ),
      children: [
        for (final x in reportes)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: Text(
              'Paso ${(x['paso'] as num) + 1} · ${x['tipo']}'
              '${x['carta'] == null ? '' : ' · ${x['carta']}'}',
              style: const TextStyle(color: Colors.white, fontSize: 13),
            ),
            subtitle: Text(
              '${x['comentario']}',
              style: const TextStyle(color: Colors.white60, fontSize: 12),
            ),
            trailing: IconButton(
              tooltip: 'Resuelto (borrar)',
              icon: const Icon(Icons.check_circle_outline, color: _green),
              onPressed:
                  () => doc.reference.update({
                    'reportes': FieldValue.arrayRemove([x]),
                  }),
            ),
          ),
      ],
    );
  }

  /// Agrupa las líneas "T3 [fase] texto" por turno.
  List<(String, List<(String, String)>)> _turnos() {
    final out = <(String, List<(String, String)>)>[];
    final patron = RegExp(r'^T(\d+) \[([^\]]+)\] (.*)$');
    for (final linea in (r['narracion'] as List).cast<String>()) {
      final m = patron.firstMatch(linea);
      if (m == null) continue;
      final texto = m.group(3)!;
      if (texto.startsWith('── Turno de')) {
        out.add((
          'Turno ${m.group(1)}: ${texto.replaceAll('─', '').trim()}',
          [],
        ));
        continue;
      }
      if (out.isEmpty) out.add(('Preparación', []));
      out.last.$2.add((m.group(2)!.replaceAll('_', ' '), texto));
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final turnos = _turnos();
    final cartas =
        r['cartas'] is Map
            ? (r['cartas'] as Map).values.map((v) => '$v')
            : const <String>[];
    final causa = (r['causas'] as List).cast<Map>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 8),
        Text(
          'Ganó ${r['ganador']}'
          '${causa.isEmpty ? '' : ' por ${_causa('${causa.first['causa']}')}'}'
          ' · ${r['dado'] is Map ? '${r['empieza']} ganó el dado (${(r['dado'] as Map)['A']} vs ${(r['dado'] as Map)['B']}) y empezó' : 'empezó ${r['empieza']}'}'
          ' · ${(r['turnos'] as Map)['max']} turnos',
          style: const TextStyle(color: _gold, fontWeight: FontWeight.w800),
        ),
        if (r['pasos'] is List)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: _gold,
                foregroundColor: Colors.black,
              ),
              onPressed:
                  () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder:
                          (_) => TableroScreen(
                            resultado: r,
                            simulacion: doc.reference,
                          ),
                    ),
                  ),
              icon: const Icon(Icons.table_restaurant_rounded),
              label: const Text('Ver en el tablero, jugada por jugada'),
            ),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => _repetir(context),
            icon: const Icon(Icons.replay, color: _gold),
            label: const Text(
              'Repetir esta partida (misma semilla)',
              style: TextStyle(color: _gold),
            ),
          ),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => _repetir(
              context,
              jugador: doc.data()['jugador'] == 'busqueda_vigilia'
                  ? 'heuristico'
                  : 'busqueda_vigilia',
            ),
            icon: const Icon(Icons.compare_arrows, color: _gold),
            label: Text(
              'Misma semilla con la '
              '${doc.data()['jugador'] == 'busqueda_vigilia' ? 'IA rápida' : 'IA buena'}',
              style: const TextStyle(color: _gold),
            ),
          ),
        ),
        _reportes(),
        const SizedBox(height: 8),
        for (final (titulo, lineas) in turnos)
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            dense: true,
            initiallyExpanded: turnos.length <= 6,
            title: Text(
              titulo,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
            children: [
              for (final (fase, texto) in lineas)
                Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 120,
                        child: Text(
                          fase,
                          style: const TextStyle(
                            color: Colors.white38,
                            fontSize: 11,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Text.rich(
                          TextSpan(children: tramosConCartas(texto, cartas)),
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
      ],
    );
  }
}

String _causa(String c) => switch (c) {
  'combate' => 'daño de combate',
  'botar' => 'daño directo',
  'robo' => 'quedar sin mazo al robar',
  'autodano' => 'autodaño del rival',
  _ => c,
};

class _TablaImpacto extends StatelessWidget {
  final String titulo;
  final List filas;
  const _TablaImpacto({required this.titulo, required this.filas});

  @override
  Widget build(BuildContext context) {
    final list = filas.cast<Map>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          titulo,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
          ),
        ),
        if (list.isEmpty)
          const Text(
            'Pocas partidas para medir.',
            style: TextStyle(color: Colors.white38),
          ),
        for (final f in list)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '${f['carta']}',
                    style: const TextStyle(color: Colors.white70),
                  ),
                ),
                Text(
                  '${((f['diferencia'] as num) * 100).toStringAsFixed(1)} pts',
                  style: TextStyle(
                    color: (f['diferencia'] as num) >= 0 ? _green : _red,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                SizedBox(
                  width: 70,
                  child: Text(
                    '${f['jugadaEn']}',
                    textAlign: TextAlign.right,
                    style: const TextStyle(color: Colors.white38, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Revisa las cartas de los mazos antes de repetir una partida. Si están
/// todas marcadas como programadas se cierra sola y la partida se repite; si
/// no, las lista: tocar una abre su detalle para marcarla y, al quedar todas
/// listas, sigue sola.
class _AntesDeRepetir extends StatefulWidget {
  final List<Deck> mazos;
  const _AntesDeRepetir({required this.mazos});

  @override
  State<_AntesDeRepetir> createState() => _AntesDeRepetirState();
}

class _AntesDeRepetirState extends State<_AntesDeRepetir> {
  bool _cerrado = false;

  void _pendientes(int n) {
    if (n > 0 || _cerrado) return;
    _cerrado = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).pop(true);
    });
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Repetir esta partida',
              style: TextStyle(
                color: _gold,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Solo se repite con todas las cartas marcadas como programadas.',
              style: TextStyle(color: Colors.white54, fontSize: 12),
            ),
            const SizedBox(height: 12),
            CartasPorCompletar(mazos: widget.mazos, onPendientes: _pendientes),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text(
                'Cancelar',
                style: TextStyle(color: Colors.white54),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

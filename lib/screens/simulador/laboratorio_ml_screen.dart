// Cola local para análisis pesados: la app pide y myl_sim.worker los calcula
// en el PC del dueño. Los episodios y archivos grandes nunca salen del equipo.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../models/deck.dart';
import '../../services/deck_service.dart';
import 'estado_mazos.dart';

const _bg = Color(0xFF0F181B);
const _surface = Color(0xFF132126);
const _gold = Color(0xFFF2D487);
const _green = Color(0xFF34D399);
const _red = Color(0xFFF87171);

final _mlJobs = FirebaseFirestore.instance.collection('ml_jobs');
final _estadoWorker = FirebaseFirestore.instance.doc('simulator_status/worker');

bool _activo(DateTime? visto) =>
    visto != null && DateTime.now().difference(visto).inSeconds < 120;

class LaboratorioMlScreen extends StatefulWidget {
  const LaboratorioMlScreen({super.key});

  @override
  State<LaboratorioMlScreen> createState() => _LaboratorioMlScreenState();
}

class _LaboratorioMlScreenState extends State<LaboratorioMlScreen> {
  final _uid = FirebaseAuth.instance.currentUser!.uid;
  late final Stream<List<Deck>> _decks = soloMazosValidos(
    DeckService(_uid).watchMyDecks(),
  );
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _jobs =
      _mlJobs.orderBy('createdAt', descending: true).limit(20).snapshots();
  String? _base;
  int _n = 1000;
  bool _enviando = false;

  Future<void> _crearMatriz() async {
    if (_base == null) return;
    setState(() => _enviando = true);
    try {
      await _mlJobs.add({
        'ownerUid': _uid,
        'createdBy': FirebaseAuth.instance.currentUser?.email,
        'tipo': 'matriz',
        'deckBase': _base,
        'formato': 'racial',
        'n': _n,
        'seed': DateTime.now().millisecondsSinceEpoch % 1000000,
        'status': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('No se pudo crear la matriz: $e')));
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: _bg,
    appBar: AppBar(
      backgroundColor: const Color(0xFF1A120C),
      title: const Text(
        'Laboratorio ML',
        style: TextStyle(color: _gold, fontWeight: FontWeight.bold),
      ),
    ),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 900),
        child: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            const _AvisoLocal(),
            const SizedBox(height: 12),
            _crear(),
            const SizedBox(height: 18),
            const Text(
              'TRABAJOS Y REPORTES',
              style: TextStyle(
                color: _gold,
                fontSize: 12,
                fontWeight: FontWeight.w800,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 8),
            const _EstadoWorkerMl(),
            const SizedBox(height: 8),
            StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _jobs,
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
                    'Aún no hay trabajos ML.',
                    style: TextStyle(color: Colors.white54),
                  );
                }
                return Column(
                  children: [for (final d in docs) _TrabajoMlCard(doc: d)],
                );
              },
            ),
          ],
        ),
      ),
    ),
  );

  Widget _crear() => Card(
    color: _surface,
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: StreamBuilder<List<Deck>>(
        stream: _decks,
        builder: (context, snap) {
          final racial =
              [...(snap.data ?? const <Deck>[])]
                ..removeWhere((d) => d.format != DeckFormat.racial)
                ..sort(
                  (a, b) =>
                      a.name.toLowerCase().compareTo(b.name.toLowerCase()),
                );
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Matriz competitiva',
                style: TextStyle(
                  color: _gold,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Mide un mazo contra todas tus barajas Racial Edición. Se ejecuta '
                'localmente con el worker; el reporte completo queda guardado en tu PC.',
                style: TextStyle(color: Colors.white60, fontSize: 12),
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<String>(
                initialValue: racial.any((d) => d.id == _base) ? _base : null,
                isExpanded: true,
                dropdownColor: _surface,
                decoration: const InputDecoration(labelText: 'Mazo base'),
                items: [
                  for (final d in racial)
                    DropdownMenuItem(
                      value: d.id,
                      child: Text(d.name, overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: (v) => setState(() => _base = v),
              ),
              const SizedBox(height: 12),
              SegmentedButton<int>(
                segments: const [
                  ButtonSegment(value: 200, label: Text('200')),
                  ButtonSegment(value: 1000, label: Text('1.000')),
                  ButtonSegment(value: 5000, label: Text('5.000')),
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
                onPressed: _base == null || _enviando ? null : _crearMatriz,
                icon: const Icon(Icons.grid_view_rounded),
                label: Text(_enviando ? 'Creando…' : 'Ejecutar matriz racial'),
              ),
            ],
          );
        },
      ),
    ),
  );
}

class _AvisoLocal extends StatelessWidget {
  const _AvisoLocal();

  @override
  Widget build(BuildContext context) => const Card(
    color: Color(0xFF1A120C),
    child: ListTile(
      leading: Icon(Icons.computer_outlined, color: _gold),
      title: Text(
        'Cómputo local',
        style: TextStyle(color: _gold, fontWeight: FontWeight.bold),
      ),
      subtitle: Text(
        'Abre el worker en este PC para ejecutar la cola. Firebase solo sincroniza pedidos, progreso y resúmenes.',
        style: TextStyle(color: Colors.white70),
      ),
    ),
  );
}

class _EstadoWorkerMl extends StatelessWidget {
  const _EstadoWorkerMl();

  @override
  Widget build(BuildContext context) =>
      StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: _estadoWorker.snapshots(),
        builder: (context, snap) {
          final v = snap.data?.data()?['lastSeen'];
          final visto = v is Timestamp ? v.toDate() : null;
          final activo = _activo(visto);
          return Card(
            color: _surface,
            child: ListTile(
              leading: Icon(
                activo ? Icons.check_circle_outline : Icons.error_outline,
                color: activo ? _green : _red,
              ),
              title: Text(
                activo ? 'Worker local activo' : 'Worker local apagado',
                style: TextStyle(
                  color: activo ? _green : _red,
                  fontWeight: FontWeight.bold,
                ),
              ),
              subtitle: const Text(
                'En simulator/: .venv/Scripts/python -m myl_sim.worker',
                style: TextStyle(color: Colors.white60, fontSize: 12),
              ),
            ),
          );
        },
      );
}

class _TrabajoMlCard extends StatelessWidget {
  final QueryDocumentSnapshot<Map<String, dynamic>> doc;
  const _TrabajoMlCard({required this.doc});

  @override
  Widget build(BuildContext context) {
    final d = doc.data();
    final estado = (d['status'] ?? 'pending').toString();
    final parcial = Map<String, dynamic>.from(d['parcial'] ?? const {});
    final resultado = Map<String, dynamic>.from(d['resultado'] ?? const {});
    final cruces = (resultado['cruces'] as List?)?.cast<dynamic>() ?? const [];
    final color =
        estado == 'done'
            ? _green
            : estado == 'error'
            ? _red
            : _gold;
    return Card(
      color: _surface,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  estado == 'done'
                      ? Icons.check_circle_outline
                      : Icons.analytics_outlined,
                  color: color,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Matriz racial · ${_estado(estado)}',
                    style: TextStyle(color: color, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            if (estado == 'running' || estado == 'pending') ...[
              const SizedBox(height: 10),
              LinearProgressIndicator(
                value: (d['progreso'] as num?)?.toDouble(),
                color: _gold,
              ),
              const SizedBox(height: 5),
              Text(
                '${parcial['completados'] ?? 0}/${parcial['total'] ?? '…'} cruces · ${parcial['ultimoRival'] ?? 'esperando worker'}',
                style: const TextStyle(color: Colors.white60, fontSize: 12),
              ),
            ],
            if (estado == 'error') ...[
              const SizedBox(height: 8),
              Text(
                (d['error'] ?? 'Error desconocido').toString(),
                style: const TextStyle(color: _red),
              ),
            ],
            if (estado == 'done') ...[
              const SizedBox(height: 8),
              Text(
                '${resultado['base']?['nombre'] ?? 'Mazo'} · ${cruces.length} rivales · ${resultado['partidasPorCruce'] ?? '?'} partidas/cruce',
                style: const TextStyle(color: Colors.white70),
              ),
              if (cruces.isNotEmpty) ...[
                const SizedBox(height: 8),
                const Text(
                  'Mejores enfrentamientos',
                  style: TextStyle(color: Colors.white60, fontSize: 12),
                ),
                for (final r in cruces.take(3))
                  Text(
                    '${r['rival']?['nombre'] ?? '?'}  ${(100 * ((r['winrate'] as num?)?.toDouble() ?? 0)).toStringAsFixed(1)}%',
                    style: const TextStyle(color: Colors.white70),
                  ),
              ],
              if (d['localPath'] != null) ...[
                const SizedBox(height: 6),
                Text(
                  'Reporte local: ${d['localPath']}',
                  style: const TextStyle(color: Colors.white54, fontSize: 11),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  String _estado(String e) => switch (e) {
    'pending' => 'En cola',
    'running' => 'Calculando',
    'done' => 'Completada',
    'error' => 'Error',
    _ => e,
  };
}

// lib/screens/simulador/entrenamiento_screen.dart
//
// Modo Entrenamiento: una escalera de rivales (mazos del meta jugados por la
// IA) cada vez más difíciles. El rating del jugador sube o baja con cada
// partida, tipo Elo (ver domain/entrenamiento.dart).
//
// La partida es un Desafío IA normal (`ai_challenges`, la juega el worker)
// marcado con `modo: 'entrenamiento'`. Al volver a esta pantalla se cuentan
// en el rating las partidas terminadas que aún no estaban contadas.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../domain/entrenamiento.dart';
import '../../models/deck.dart';
import '../../services/deck_service.dart';
import '../../theme/app_theme.dart';
import '../tournaments/tournament_widgets.dart' show colorPerfil;
import 'desafio_ia_screen.dart';
import 'estado_mazos.dart';

const _nombresNivel = {
  1: 'Principiante',
  2: 'Fácil',
  3: 'Normal',
  4: 'Difícil',
  5: 'Experto',
};

const _enCurso = {'pending', 'preparando', 'jugando', 'esperando'};

class EntrenamientoScreen extends StatefulWidget {
  const EntrenamientoScreen({super.key});

  @override
  State<EntrenamientoScreen> createState() => _EntrenamientoScreenState();
}

class _EntrenamientoScreenState extends State<EntrenamientoScreen> {
  final _uid = FirebaseAuth.instance.currentUser!.uid;
  final _db = FirebaseFirestore.instance;
  late final Stream<List<Deck>> _decks = soloMazosValidos(
    DeckService(_uid).watchMyDecks(),
  );
  late final Future<Escalera> _escalera = _db
      .doc('config/escalera_entrenamiento')
      .get()
      .then((d) => Escalera.fromMap(d.data() ?? const {}));

  String? _mazo;

  /// Rival elegido a mano (más fácil / más difícil); null = el propuesto.
  RivalEscalera? _elegido;
  bool _creando = false;

  /// Partida de entrenamiento sin terminar, si la hay.
  DocumentReference<Map<String, dynamic>>? _pendiente;
  String _pendienteRival = '';

  DocumentReference<Map<String, dynamic>> get _usuario =>
      _db.collection('users').doc(_uid);

  @override
  void initState() {
    super.initState();
    _ponerAlDia();
  }

  void _aviso(String texto) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(texto)));
  }

  /// Cuenta en el rating las partidas terminadas que faltan y detecta si
  /// quedó una partida a medias.
  Future<void> _ponerAlDia() async {
    try {
      final escalera = await _escalera;
      final desafios =
          await _db
              .collection('ai_challenges')
              .where('ownerUid', isEqualTo: _uid)
              .get();
      final mios =
          desafios.docs
              .where((d) => d.data()['modo'] == 'entrenamiento')
              .toList()
            ..sort((a, b) {
              int t(QueryDocumentSnapshot<Map<String, dynamic>> x) =>
                  (x.data()['createdAt'] as Timestamp?)
                      ?.millisecondsSinceEpoch ??
                  0;
              return t(a).compareTo(t(b));
            });
      final abierta =
          mios.where((d) => _enCurso.contains(d.data()['status'])).lastOrNull;
      final cerradas =
          mios
              .where(
                (d) => const {
                  'terminado',
                  'abandonado',
                }.contains(d.data()['status']),
              )
              .toList();
      var sumadas = 0, cambio = 0;
      if (cerradas.isNotEmpty) {
        await _db.runTransaction((tx) async {
          final snap = await tx.get(_usuario);
          var progreso = ProgresoEntrenamiento.fromMap(
            snap.data()?['entrenamiento'],
            inicial: escalera.ratingInicial,
          );
          final antes = progreso;
          for (final d in cerradas) {
            final data = d.data();
            final rival = data['rival'];
            if (rival is! Map || progreso.yaContada(d.id)) continue;
            final resultado = data['resultado'];
            progreso = progreso.conPartida(
              desafio: d.id,
              rival: RivalEscalera.fromMap(rival.cast<String, dynamic>()),
              // Abandonar cuenta como derrota.
              gano:
                  data['status'] == 'terminado' &&
                  resultado is Map &&
                  resultado['ganadorLado'] == 0,
              fecha:
                  (data['finishedAt'] as Timestamp?)?.toDate() ??
                  (data['createdAt'] as Timestamp?)?.toDate() ??
                  DateTime.now(),
            );
          }
          sumadas = progreso.partidas - antes.partidas;
          cambio = progreso.rating - antes.rating;
          if (sumadas > 0) {
            tx.update(_usuario, {'entrenamiento': progreso.toMap()});
          }
        });
      }
      if (!mounted) return;
      setState(() {
        _pendiente = abierta?.reference;
        _pendienteRival =
            ((abierta?.data()['rival'] as Map?)?['nombre'] ?? '').toString();
      });
      if (sumadas > 0) {
        _aviso(
          sumadas == 1
              ? 'Partida contada: ${cambio >= 0 ? '+' : ''}$cambio de rating'
              : '$sumadas partidas contadas: ${cambio >= 0 ? '+' : ''}$cambio de rating',
        );
      }
    } catch (e) {
      _aviso('No se pudo actualizar tu rating: $e');
    }
  }

  Future<void> _abrir(
    DocumentReference<Map<String, dynamic>> ref,
    String rival,
  ) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder:
            (_) => DesafioIaScreen(
              desafio: ref,
              titulo: rival.isEmpty ? 'Entrenamiento' : 'Entrenamiento · $rival',
            ),
      ),
    );
    if (!mounted) return;
    setState(() => _elegido = null);
    await _ponerAlDia();
  }

  Future<void> _jugar(RivalEscalera rival, int rating) async {
    final mazo = _mazo;
    if (mazo == null || _creando) return;
    setState(() => _creando = true);
    try {
      final ref = await _db.collection('ai_challenges').add({
        'ownerUid': _uid,
        'modo': 'entrenamiento',
        'deckHumano': mazo,
        'deckIa': 'escalera:${rival.deck}',
        'nivel': rival.nivel,
        'buscarBloqueos': rival.nivel == 5,
        'rival': rival.toMap(),
        'ratingAntes': rating,
        'seed': DateTime.now().millisecondsSinceEpoch % 1000000,
        'status': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
      });
      if (mounted) await _abrir(ref, rival.nombre);
    } catch (e) {
      _aviso('No se pudo crear la partida: $e');
    } finally {
      if (mounted) setState(() => _creando = false);
    }
  }

  Future<void> _abandonarPendiente() async {
    final ref = _pendiente;
    if (ref == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: const Text('Abandonar la partida'),
            content: const Text(
              'Cuenta como derrota en tu rating. Hazlo solo si no puedes '
              'seguirla.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Abandonar'),
              ),
            ],
          ),
    );
    if (ok != true) return;
    try {
      await ref.update({'status': 'abandonado'});
      await _ponerAlDia();
    } catch (e) {
      _aviso('No se pudo abandonar: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Entrenamiento')),
      body: FutureBuilder<Escalera>(
        future: _escalera,
        builder: (context, se) {
          if (se.hasError) {
            return _Centro('No se pudo cargar la escalera.\n${se.error}');
          }
          if (!se.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final escalera = se.data!;
          if (escalera.vacia) {
            return const _Centro(
              'La escalera de rivales aún no está publicada.\n\nSe genera en '
              'el computador del simulador a partir de la matriz del meta y '
              'aparece aquí cuando esté lista.',
            );
          }
          return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream: _usuario.snapshots(),
            builder: (context, su) {
              final progreso = ProgresoEntrenamiento.fromMap(
                su.data?.data()?['entrenamiento'],
                inicial: escalera.ratingInicial,
              );
              return StreamBuilder<List<Deck>>(
                stream: _decks,
                builder:
                    (context, sd) =>
                        _contenido(escalera, progreso, sd.data, sd.hasData),
              );
            },
          );
        },
      ),
    );
  }

  Widget _contenido(
    Escalera escalera,
    ProgresoEntrenamiento progreso,
    List<Deck>? decks,
    bool decksListos,
  ) {
    final mazos = [...?decks]..sort((a, b) => a.name.compareTo(b.name));
    if (_mazo == null || !mazos.any((d) => d.id == _mazo)) {
      _mazo = mazos.firstOrNull?.id;
    }
    final propuesto = elegirRival(escalera, progreso);
    final rival = _elegido ?? propuesto;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _resumen(escalera, progreso),
                const SizedBox(height: 14),
                if (_pendiente != null) ...[
                  _Caja(
                    destacada: true,
                    child: Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 10,
                      runSpacing: 8,
                      children: [
                        Text(
                          'Tienes una partida sin terminar'
                          '${_pendienteRival.isEmpty ? '' : ' contra $_pendienteRival'}.',
                          style: const TextStyle(color: AppColors.text),
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            TextButton(
                              onPressed: _abandonarPendiente,
                              child: const Text('Abandonar'),
                            ),
                            FilledButton(
                              onPressed:
                                  () => _abrir(_pendiente!, _pendienteRival),
                              child: const Text('Continuar'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                ] else if (rival != null) ...[
                  _proximoRival(
                    escalera,
                    progreso,
                    rival,
                    propuesto!,
                    mazos,
                    decksListos,
                  ),
                  const SizedBox(height: 14),
                ],
                if (progreso.historial.length >= 2) ...[
                  _grafico(progreso),
                  const SizedBox(height: 14),
                ],
                if (progreso.historial.isNotEmpty) _historial(progreso),
                const SizedBox(height: 10),
                const Text(
                  'Cada rival es un mazo del meta jugado por la IA en uno de '
                  'sus cinco niveles. Su rating sale de la fuerza del mazo y '
                  'del nivel de la IA, medidos en el simulador. Las partidas '
                  'las juega el simulador: si está apagado, la partida queda '
                  'esperando.',
                  style: TextStyle(color: AppColors.textFaint, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _resumen(Escalera escalera, ProgresoEntrenamiento p) {
    final avance = avanceEnEscalera(escalera, p.rating);
    final rango = rangoDe(escalera, p.rating);
    final siguiente = rangos.where((r) => r.desde > rango.desde).firstOrNull;
    final faltan =
        siguiente == null
            ? null
            : (escalera.piso + siguiente.desde * (escalera.techo - escalera.piso))
                    .ceil() -
                p.rating;
    return _Caja(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${p.rating}',
                style: const TextStyle(
                  color: AppColors.gold,
                  fontSize: 44,
                  height: 1,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      rango.nombre,
                      style: const TextStyle(
                        color: AppColors.text,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      p.partidas == 0
                          ? 'Rating inicial. Juega tu primera partida.'
                          : p.enColocacion
                          ? 'Colocación: ${p.partidas} de $partidasDeColocacion partidas. El rating se mueve el doble.'
                          : siguiente == null
                          ? 'Estás en lo más alto de la escalera.'
                          : '${faltan! > 0 ? faltan : 1} puntos para ${siguiente.nombre}.',
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: avance,
              minHeight: 10,
              backgroundColor: AppColors.surfaceDeep,
              valueColor: const AlwaysStoppedAnimation(AppColors.goldStrong),
            ),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Rival más fácil ${escalera.piso}',
                style: const TextStyle(color: AppColors.textFaint, fontSize: 11),
              ),
              Text(
                'Más difícil ${escalera.techo}',
                style: const TextStyle(color: AppColors.textFaint, fontSize: 11),
              ),
            ],
          ),
          if (p.partidas > 0) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 18,
              runSpacing: 6,
              children: [
                _Dato('Partidas', '${p.partidas}'),
                _Dato(
                  'Ganadas',
                  '${p.ganadas} (${(p.ganadas / p.partidas * 100).round()}%)',
                ),
                _Dato('Racha', '${p.racha}'),
                _Dato('Mejor rating', '${p.mejorRating}'),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _proximoRival(
    Escalera escalera,
    ProgresoEntrenamiento progreso,
    RivalEscalera rival,
    RivalEscalera propuesto,
    List<Deck> mazos,
    bool decksListos,
  ) {
    final (gana, pierde) = puntosEnJuego(
      progreso.rating,
      rival.rating,
      progreso.partidas,
    );
    final prob = (esperado(progreso.rating, rival.rating) * 100).round();
    final otros = alternativas(escalera, progreso, propuesto);
    return _Caja(
      destacada: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            rival.id == propuesto.id ? 'Tu próximo rival' : 'Rival elegido',
            style: const TextStyle(
              color: AppColors.textFaint,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: Text(
                  rival.nombre,
                  style: const TextStyle(
                    color: AppColors.text,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Text(
                '${rival.rating}',
                style: const TextStyle(
                  color: AppColors.gold,
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              if (rival.perfil.isNotEmpty)
                _Etiqueta(rival.perfil, color: colorPerfil(rival.perfil)),
              _Etiqueta(
                'IA nivel ${rival.nivel} · ${_nombresNivel[rival.nivel]}',
              ),
              _Etiqueta('Ganas $prob de cada 100'),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Si ganas: +$gana · si pierdes: $pierde',
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          if (!decksListos)
            const LinearProgressIndicator()
          else if (mazos.isEmpty)
            const Text(
              'No tienes mazos válidos para jugar: debe tener 49 cartas, '
              'cumplir la Ban List y que todas sus cartas estén programadas.',
              style: TextStyle(color: AppColors.warning),
            )
          else
            DropdownButtonFormField<String>(
              initialValue: _mazo,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Tu mazo'),
              items: [
                for (final d in mazos)
                  DropdownMenuItem(
                    value: d.id,
                    child: Text(d.name, overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: (v) => setState(() => _mazo = v),
            ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              FilledButton.icon(
                onPressed:
                    _creando || _mazo == null
                        ? null
                        : () => _jugar(rival, progreso.rating),
                icon:
                    _creando
                        ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                        : const Icon(Icons.play_arrow_rounded),
                label: const Text('Jugar'),
              ),
              if (rival.id != propuesto.id)
                TextButton(
                  onPressed: () => setState(() => _elegido = null),
                  child: const Text('Volver al propuesto'),
                ),
              for (final o in otros)
                if (o.id != rival.id)
                  OutlinedButton(
                    onPressed: () => setState(() => _elegido = o),
                    child: Text(
                      o.rating < propuesto.rating
                          ? 'Uno más fácil (${o.rating})'
                          : 'Uno más difícil (${o.rating})',
                    ),
                  ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _grafico(ProgresoEntrenamiento p) {
    // Del más antiguo al más reciente, partiendo del rating previo.
    final orden = p.historial.reversed.toList();
    final puntos = [
      FlSpot(0, orden.first.ratingAntes.toDouble()),
      for (var i = 0; i < orden.length; i++)
        FlSpot(i + 1.0, orden[i].ratingDespues.toDouble()),
    ];
    final ys = puntos.map((s) => s.y);
    final minY = ys.reduce((a, b) => a < b ? a : b) - 20;
    final maxY = ys.reduce((a, b) => a > b ? a : b) + 20;
    return _Caja(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Tu rating en las últimas ${orden.length} partidas',
            style: const TextStyle(
              color: AppColors.text,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 160,
            child: LineChart(
              LineChartData(
                minY: minY,
                maxY: maxY,
                gridData: FlGridData(
                  drawVerticalLine: false,
                  getDrawingHorizontalLine:
                      (_) => const FlLine(color: Colors.white10, strokeWidth: 1),
                ),
                borderData: FlBorderData(show: false),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(),
                  rightTitles: const AxisTitles(),
                  bottomTitles: const AxisTitles(),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 40,
                      getTitlesWidget:
                          (v, meta) =>
                              v == meta.min || v == meta.max
                                  ? const SizedBox.shrink()
                                  : Text(
                                    '${v.round()}',
                                    style: const TextStyle(
                                      color: AppColors.textFaint,
                                      fontSize: 10,
                                    ),
                                  ),
                    ),
                  ),
                ),
                lineTouchData: const LineTouchData(enabled: false),
                lineBarsData: [
                  LineChartBarData(
                    spots: puntos,
                    color: AppColors.goldStrong,
                    barWidth: 2.5,
                    dotData: FlDotData(show: puntos.length <= 16),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _historial(ProgresoEntrenamiento p) {
    return _Caja(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Últimas partidas',
            style: TextStyle(color: AppColors.text, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          for (final x in p.historial.take(12))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                children: [
                  Icon(
                    x.gano ? Icons.check_circle : Icons.cancel,
                    size: 18,
                    color: x.gano ? AppColors.success : AppColors.danger,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '${x.rivalNombre} · nivel ${x.nivel} · ${x.rivalRating}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: AppColors.text),
                    ),
                  ),
                  Text(
                    '${x.cambio >= 0 ? '+' : ''}${x.cambio}',
                    style: TextStyle(
                      color: x.cambio >= 0 ? AppColors.success : AppColors.danger,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  SizedBox(
                    width: 52,
                    child: Text(
                      '${x.ratingDespues}',
                      textAlign: TextAlign.right,
                      style: const TextStyle(color: AppColors.textSecondary),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _Centro extends StatelessWidget {
  final String texto;
  const _Centro(this.texto);

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

class _Caja extends StatelessWidget {
  final Widget child;
  final bool destacada;
  const _Caja({required this.child, this.destacada = false});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(
        color:
            destacada ? AppColors.gold.withValues(alpha: .5) : AppColors.border,
      ),
    ),
    child: child,
  );
}

class _Dato extends StatelessWidget {
  final String etiqueta;
  final String valor;
  const _Dato(this.etiqueta, this.valor);

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        etiqueta,
        style: const TextStyle(color: AppColors.textFaint, fontSize: 11),
      ),
      Text(
        valor,
        style: const TextStyle(
          color: AppColors.text,
          fontSize: 16,
          fontWeight: FontWeight.w800,
        ),
      ),
    ],
  );
}

class _Etiqueta extends StatelessWidget {
  final String texto;
  final Color? color;
  const _Etiqueta(this.texto, {this.color});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: (color ?? Colors.white).withValues(alpha: .10),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(
        color: (color ?? Colors.white).withValues(alpha: .35),
      ),
    ),
    child: Text(
      texto,
      style: TextStyle(
        color: color ?? AppColors.textSecondary,
        fontSize: 12,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}

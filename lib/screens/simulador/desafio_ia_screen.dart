import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../models/deck.dart';
import '../../services/deck_service.dart';
import 'estado_mazos.dart';
import 'tablero_desafio.dart';
import 'jugadas_ia.dart';
import 'tablero_screen.dart';

const _bg = Color(0xFF0F181B);
const _surface = Color(0xFF132126);
const _gold = Color(0xFFF2D487);

class DesafioIaScreen extends StatefulWidget {
  /// Con [desafio] abre directo esa partida (modo Entrenamiento): no ofrece
  /// crear otra ni ver el historial de desafíos.
  const DesafioIaScreen({super.key, this.desafio, this.titulo});

  final DocumentReference<Map<String, dynamic>>? desafio;
  final String? titulo;

  @override
  State<DesafioIaScreen> createState() => _DesafioIaScreenState();
}

class _DesafioIaScreenState extends State<DesafioIaScreen> {
  final _uid = FirebaseAuth.instance.currentUser!.uid;
  late final Stream<List<Deck>> _decks = soloMazosValidos(
    DeckService(_uid).watchMyDecks(),
  );
  late DocumentReference<Map<String, dynamic>>? _desafio = widget.desafio;
  bool get _fijo => widget.desafio != null;
  String? _humano;
  String? _ia;
  bool _creando = false;
  bool _buscarBloqueos = false;
  int _nivel = 5;
  // Imágenes de los dos mazos descargadas antes de mostrar la mesa.
  String? _precargaDe;
  bool _precargando = false;
  int _hechas = 0;
  int _total = 0;

  void _precargar(String id, Map<String, String> urls) {
    _precargaDe = id;
    _precargando = true;
    _total = urls.length;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final fin = precargarImagenesDesafio(context, urls, (h, t) {
        if (mounted) {
          setState(() {
            _hechas = h;
            _total = t;
          });
        }
      });
      // Si la red está muy lenta, a los 25 s se muestra la mesa igual (las
      // cartas que falten siguen cargando y reintentando solas).
      await Future.any([
        fin,
        Future<void>.delayed(const Duration(seconds: 25)),
      ]);
      if (mounted) setState(() => _precargando = false);
    });
  }

  static const _niveles = {
    1: (
      'Principiante',
      'Se equivoca seguido: 6 de cada 10 decisiones al azar.',
    ),
    2: ('Fácil', 'Comete errores frecuentes (35% de decisiones al azar).'),
    3: ('Normal', 'Juega bien pero a veces se equivoca (15%).'),
    4: ('Difícil', 'Siempre su mejor jugada según la heurística.'),
    5: (
      'Experto',
      'Simula sus jugadas, ataques y habilidades antes de decidir. Puede pensar un par de segundos.',
    ),
  };

  Future<void> _crear() async {
    if (_humano == null || _ia == null || _humano == _ia) return;
    setState(() => _creando = true);
    try {
      final ref = await FirebaseFirestore.instance
          .collection('ai_challenges')
          .add({
            'ownerUid': _uid,
            'deckHumano': _humano,
            'deckIa': _ia,
            'buscarBloqueos': _buscarBloqueos || _nivel == 5,
            'nivel': _nivel,
            'seed': DateTime.now().millisecondsSinceEpoch % 1000000,
            'status': 'pending',
            'createdAt': FieldValue.serverTimestamp(),
          });
      if (mounted) setState(() => _desafio = ref);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo crear el desafío: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _creando = false);
    }
  }

  /// Pide la siguiente duda de la IA: el worker reproduce una partida suya
  /// hasta la decisión donde no supo qué jugar y la muestra en la mesa.
  Future<void> _resolverDuda() async {
    setState(() => _creando = true);
    try {
      final ref = await FirebaseFirestore.instance
          .collection('ai_challenges')
          .add({
            'ownerUid': _uid,
            'modo': 'duda',
            'status': 'pending',
            'createdAt': FieldValue.serverTimestamp(),
          });
      if (mounted) setState(() => _desafio = ref);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('No se pudo pedir la duda: $e')));
      }
    } finally {
      if (mounted) setState(() => _creando = false);
    }
  }

  Future<void> _reintentar(Map<String, dynamic> anterior) async {
    if (anterior['modo'] == 'duda') return _resolverDuda();
    setState(() {
      _humano = anterior['deckHumano'] as String?;
      _ia = anterior['deckIa'] as String?;
      _buscarBloqueos = anterior['buscarBloqueos'] == true;
      _nivel = (anterior['nivel'] as num?)?.toInt() ?? 5;
      _desafio = null;
    });
    await _crear();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: _bg,
    appBar: AppBar(
      backgroundColor: const Color(0xFF1A120C),
      toolbarHeight:
          _desafio != null &&
                  MediaQuery.sizeOf(context).width >
                      MediaQuery.sizeOf(context).height
              ? 36
              : null,
      title: Text(
        widget.titulo ?? 'Desafío IA',
        style: const TextStyle(color: _gold, fontWeight: FontWeight.bold),
      ),
      actions: [
        if (_desafio == null)
          TextButton.icon(
            onPressed: _creando ? null : _resolverDuda,
            icon: const Icon(Icons.psychology_alt_outlined, color: _gold),
            label: const Text('Dudas de la IA', style: TextStyle(color: _gold)),
          ),
        if (_desafio != null && !_fijo)
          IconButton(
            tooltip: 'Ver mis desafíos',
            onPressed: () => setState(() => _desafio = null),
            icon: const Icon(Icons.history),
          ),
      ],
    ),
    body: _desafio == null ? _configurar() : _partida(_desafio!),
  );

  Widget _configurar() => StreamBuilder<List<Deck>>(
    stream: _decks,
    builder: (context, snap) {
      final decks = [...?snap.data]..sort((a, b) => a.name.compareTo(b.name));
      return EstadosMazos(
        mazos: decks,
        builder: (context, estados) {
          DropdownButtonFormField<String> selector(
            String texto,
            String? value,
            ValueChanged<String?> changed,
          ) => DropdownButtonFormField(
            initialValue: decks.any((d) => d.id == value) ? value : null,
            isExpanded: true,
            dropdownColor: _surface,
            decoration: InputDecoration(labelText: texto),
            items: [
              for (final d in decks)
                DropdownMenuItem(
                  value: d.id,
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${d.name} · ${d.cards.fold<int>(0, (n, c) => n + c.count)} cartas',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      IconoEstadoMazo(estados[d.id]),
                    ],
                  ),
                ),
            ],
            onChanged: changed,
          );
          return ListView(
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 700),
                  child: Card(
                    color: _surface,
                    margin: const EdgeInsets.all(16),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Text(
                            'Juega una partida real contra la IA heurística. Tú eliges mano, cartas, ataques, bloqueos y objetivos; no hay side deck.',
                            style: TextStyle(color: Colors.white70),
                          ),
                          const SizedBox(height: 16),
                          selector(
                            'Tu mazo',
                            _humano,
                            (v) => setState(() => _humano = v),
                          ),
                          const SizedBox(height: 6),
                          const Wrap(
                            spacing: 12,
                            children: [
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconoEstadoMazo(EstadoMazo.programado),
                                  SizedBox(width: 4),
                                  Text(
                                    'Programado',
                                    style: TextStyle(
                                      color: Colors.white60,
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconoEstadoMazo(EstadoMazo.textoCompleto),
                                  SizedBox(width: 4),
                                  Text(
                                    'Textos escritos',
                                    style: TextStyle(
                                      color: Colors.white60,
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          selector(
                            'Mazo de la IA',
                            _ia,
                            (v) => setState(() => _ia = v),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Dificultad de la IA',
                            style: TextStyle(color: Colors.white70),
                          ),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              for (final n in _niveles.keys)
                                ChoiceChip(
                                  label: Text('$n · ${_niveles[n]!.$1}'),
                                  selected: _nivel == n,
                                  selectedColor: _gold,
                                  labelStyle: TextStyle(
                                    color:
                                        _nivel == n
                                            ? Colors.black
                                            : Colors.white,
                                  ),
                                  onSelected:
                                      _creando
                                          ? null
                                          : (_) => setState(() => _nivel = n),
                                ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            _niveles[_nivel]!.$2,
                            style: const TextStyle(
                              color: Colors.white60,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 16),
                          FilledButton.icon(
                            onPressed:
                                _creando ||
                                        _humano == null ||
                                        _ia == null ||
                                        _humano == _ia
                                    ? null
                                    : _crear,
                            style: FilledButton.styleFrom(
                              backgroundColor: _gold,
                              foregroundColor: Colors.black,
                            ),
                            icon: const Icon(Icons.smart_toy_outlined),
                            label: Text(
                              _creando ? 'Creando...' : 'Comenzar desafío',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 700),
                  child: _recientes(decks),
                ),
              ),
            ],
          );
        },
      );
    },
  );

  Widget _recientes(
    List<Deck> decks,
  ) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
    stream:
        FirebaseFirestore.instance
            .collection('ai_challenges')
            .where('ownerUid', isEqualTo: _uid)
            .limit(20)
            .snapshots(),
    builder: (context, snap) {
      if (!snap.hasData) return const SizedBox.shrink();
      final docs = [...snap.data!.docs]..sort((a, b) {
        final at =
            (a.data()['createdAt'] as Timestamp?)?.millisecondsSinceEpoch ?? 0;
        final bt =
            (b.data()['createdAt'] as Timestamp?)?.millisecondsSinceEpoch ?? 0;
        return bt.compareTo(at);
      });
      if (docs.isEmpty) return const SizedBox.shrink();
      String nombre(dynamic id) {
        for (final deck in decks) {
          if (deck.id == id) return deck.name;
        }
        return 'Mazo';
      }

      return Card(
        color: _surface,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          children: [
            const ListTile(
              title: Text(
                'Mis desafíos recientes',
                style: TextStyle(color: _gold, fontWeight: FontWeight.bold),
              ),
            ),
            for (final doc in docs.take(10))
              ListTile(
                title: Text(
                  doc.data()['modo'] == 'duda'
                      ? 'Duda de la IA · ${doc.data()['mazoDuda'] ?? '…'} vs ${doc.data()['rivalDuda'] ?? '…'}'
                      : '${nombre(doc.data()['deckHumano'])} vs ${nombre(doc.data()['deckIa'])}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white),
                ),
                subtitle: Text(
                  '${doc.data()['status']}',
                  style: const TextStyle(color: Colors.white60),
                ),
                trailing: const Icon(Icons.chevron_right, color: _gold),
                onTap: () => setState(() => _desafio = doc.reference),
              ),
          ],
        ),
      );
    },
  );

  Widget _partida(
    DocumentReference<Map<String, dynamic>> ref,
  ) => StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
    stream: ref.snapshots(),
    builder: (context, snap) {
      final d = snap.data?.data();
      if (d == null) {
        return const Center(child: CircularProgressIndicator());
      }
      final status = d['status'] as String? ?? 'pending';
      final estado = (d['estado'] as Map?)?.cast<String, dynamic>();
      final decision =
          status == 'esperando'
              ? (d['decision'] as Map?)?.cast<String, dynamic>()
              : null;
      final enJuego = status == 'esperando' || status == 'jugando';
      final imagenes = (d['imagenes'] as Map?)?.map(
        (k, v) => MapEntry('$k', '$v'),
      );
      if (imagenes != null &&
          imagenes.isNotEmpty &&
          _precargaDe != snap.data!.id) {
        _precargar(snap.data!.id, imagenes);
      }
      if (enJuego && _precargando) {
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 14),
              Text(
                'Cargando cartas $_hechas/$_total',
                style: const TextStyle(color: Colors.white70, fontSize: 16),
              ),
            ],
          ),
        );
      }
      if (enJuego && estado != null) {
        final tipo = decision?['tipo'] as String? ?? '';
        final accionIaMap = (d['accionIa'] as Map?)?.cast<String, dynamic>();
        final accionIa = accionIaMap?['texto'] as String?;
        final hayJugadasIa = accionesIa(d).isNotEmpty;
        final tableroBase = TableroDesafio(
          estado: estado,
          decision: decision,
          enviar:
              (valor) => ref.update({
                'respuesta': {'decisionId': decision?['id'], 'valor': valor},
              }),
        );
        // Mientras la IA juega, su última acción se muestra sobre la mesa.
        // Siempre se puede abrir la lista de jugadas de la IA para marcarlas ✓/✗.
        final tablero = Stack(
          children: [
            Positioned.fill(child: tableroBase),
            // Duda de la IA: una sola decisión, desde el asiento del que dudaba.
            if (d['modo'] == 'duda')
              Positioned(
                top: 8,
                left: 0,
                right: 0,
                child: IgnorePointer(
                  child: Center(
                    child: Container(
                      constraints: const BoxConstraints(maxWidth: 620),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xEE1F2A3A),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: _gold),
                      ),
                      child: Text(
                        status == 'esperando'
                            ? 'La IA dudó en esta posición (${d['mazoDuda']} contra ${d['rivalDuda']}). Juega tu turno completo como lo harías tú.'
                            : '${d['avisoDuda'] ?? 'Comparando tu turno con el de la IA…'}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            if (status == 'jugando' && accionIa != null)
              Positioned(
                key: ValueKey('ia-jugando-${accionIaMap?['id']}'),
                top: 8,
                left: 0,
                right: 0,
                child: Center(
                  child: _AvisoTemporal(
                    segundos: 3,
                    child: _AvisoIa(
                      texto: accionIa,
                      voto: VotoJugadaIa(
                        ref: ref,
                        accionId: '${accionIaMap?['id']}',
                        voto: votosIa(d)['${accionIaMap?['id']}'],
                      ),
                    ),
                  ),
                ),
              ),
            // Reporte qx6H: si la IA anula o responde en tu turno, la
            // decisión llega al instante y el aviso se perdía. Queda
            // unos segundos aunque ya te toque elegir.
            if (status == 'esperando' && accionIa != null)
              Positioned(
                key: ValueKey('ia-${accionIaMap?['id']}'),
                top: 8,
                left: 0,
                right: 0,
                child: Center(
                  // Héctor: 6 s tapaba la mesa rival y entorpecía; ahora
                  // 3 s y se cierra al tocarlo (la jugada sigue al medio).
                  child: _AvisoTemporal(
                    segundos: 3,
                    child: _AvisoIa(
                      texto: accionIa,
                      voto: VotoJugadaIa(
                        ref: ref,
                        accionId: '${accionIaMap?['id']}',
                        voto: votosIa(d)['${accionIaMap?['id']}'],
                      ),
                    ),
                  ),
                ),
              ),
            // Reporte qx6H: el turno de la IA pasó rápido y se saltó una
            // fase sin notar que ya era su turno.
            // Desafío g9FE: que se note cuando una habilidad falla (Idmon,
            // Afrodita): el último «✗» del registro queda unos segundos.
            if (_ultimoFallo(estado) case final fallo?)
              Positioned(
                key: ValueKey('fallo-$fallo'),
                top: 112,
                left: 0,
                right: 0,
                child: IgnorePointer(
                  child: Center(
                    child: _AvisoTemporal(
                      segundos: 3,
                      child: Container(
                        constraints: const BoxConstraints(maxWidth: 620),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xEE3A1414),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.redAccent),
                        ),
                        child: Text(
                          fallo.replaceFirst(RegExp(r'^T\d+ \[[^\]]*\] '), ''),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            if (status == 'esperando' && estado['activo'] == 0)
              Positioned(
                key: ValueKey('turno-${estado['turno']}'),
                top: 64,
                left: 0,
                right: 0,
                child: IgnorePointer(
                  child: Center(
                    child: _AvisoTemporal(
                      segundos: 3,
                      child: _AvisoTurno(turno: estado['turno']),
                    ),
                  ),
                ),
              ),
            // Reportar algo irregular en el momento exacto en que se ve.
            Positioned(
              right: 8,
              bottom: hayJugadasIa ? 56 : 8,
              child: FloatingActionButton.small(
                heroTag: 'reportarVivo',
                tooltip: 'Reportar este momento',
                backgroundColor: const Color(0xFF3A1F1F),
                foregroundColor: Colors.orangeAccent,
                onPressed: () => reportarEnVivo(context, ref, d),
                child: const Icon(Icons.bug_report_outlined),
              ),
            ),
            if (hayJugadasIa)
              Positioned(
                right: 8,
                bottom: 8,
                child: FloatingActionButton.small(
                  heroTag: 'jugadasIa',
                  tooltip: 'Jugadas de la IA (marcar ✓/✗)',
                  backgroundColor: _gold,
                  foregroundColor: Colors.black,
                  onPressed: () => mostrarJugadasIa(context, ref),
                  child: const Icon(Icons.fact_check_outlined),
                ),
              ),
          ],
        );
        // Todo se decide en la mesa (la barra de fase dice qué hacer y se
        // confirma ahí); el selector de abajo queda solo para un tipo de
        // decisión que la mesa todavía no sepa mostrar.
        if (status == 'esperando' &&
            decision != null &&
            !tiposEnMesa.contains(tipo)) {
          return LayoutBuilder(
            builder:
                (context, box) => Column(
                  children: [
                    Expanded(child: tablero),
                    SizedBox(
                      height: (box.maxHeight * .34).clamp(150.0, 290.0),
                      child: _Decision(ref: ref, decision: decision),
                    ),
                  ],
                ),
          );
        }
        return tablero;
      }
      return ListView(
        padding: const EdgeInsets.all(12),
        children: [
          _estado(status, estado, d),
          if (status == 'terminado' && d['modo'] == 'duda')
            _ResultadoDuda(
              resultado:
                  (d['resultadoDuda'] as Map?)?.cast<String, dynamic>() ?? {},
              siguiente: _creando ? null : _resolverDuda,
            ),
          if (status == 'terminado' && d['modo'] != 'duda') ...[
            const SizedBox(height: 10),
            AutopsiaIa(ref: ref, desafio: d),
            const SizedBox(height: 10),
            AprendizajeHumano(ref: ref, desafio: d),
            const SizedBox(height: 10),
            _RevisionDesafio(
              ref: ref,
              resultado:
                  (d['resultado'] as Map?)?.cast<String, dynamic>() ?? {},
              reportes: d['reportes'],
            ),
          ],
          if (status == 'esperando' && decision != null) ...[
            const SizedBox(height: 12),
            _Decision(ref: ref, decision: decision),
          ],
          if ((status == 'error' || status == 'abandonado') && !_fijo)
            FilledButton.icon(
              onPressed: _creando ? null : () => _reintentar(d),
              icon: const Icon(Icons.replay),
              label: Text(
                d['modo'] == 'duda'
                    ? 'Pedir otra duda'
                    : 'Iniciar otra partida con estos mazos',
              ),
            ),
          if (status == 'esperando' ||
              status == 'jugando' ||
              status == 'preparando')
            TextButton.icon(
              onPressed: () => ref.update({'status': 'abandonado'}),
              icon: const Icon(Icons.flag_outlined),
              label: const Text('Abandonar desafío'),
            ),
        ],
      );
    },
  );

  Widget _estado(
    String status,
    Map<String, dynamic>? e,
    Map<String, dynamic> d,
  ) {
    if (status == 'pending' || status == 'preparando') {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(30),
          child: Text(
            d['modo'] == 'duda'
                ? '${d['avisoDuda'] ?? 'El worker está buscando una duda de la IA...'}'
                : 'El worker está preparando la partida...',
            style: const TextStyle(color: Colors.white70),
          ),
        ),
      );
    }
    if (status == 'error') {
      return Text(
        'Error: ${d['error']}',
        style: const TextStyle(color: Colors.redAccent),
      );
    }
    if (status == 'abandonado') {
      return const Text(
        'Desafío abandonado.',
        style: TextStyle(color: Colors.white70),
      );
    }
    if (status == 'terminado' && d['modo'] == 'duda') {
      return const SizedBox.shrink(); // el resultado va en su propia tarjeta
    }
    if (status == 'terminado') {
      final r = (d['resultado'] as Map?)?.cast<String, dynamic>() ?? {};
      return Card(
        color: _surface,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            'Terminó: ganó ${r['ganador']} · ${r['turnos']} turnos · ${r['causa']}',
            style: const TextStyle(color: _gold, fontWeight: FontWeight.bold),
          ),
        ),
      );
    }
    if (e == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final lados = (e['lados'] as List? ?? const []).cast<Map>();
    return Card(
      color: _surface,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Turno ${e['turno']} · ${e['fase']}',
              style: const TextStyle(color: _gold, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            for (final l in lados) _lado(l.cast<String, dynamic>()),
          ],
        ),
      ),
    );
  }

  Widget _lado(Map<String, dynamic> l) {
    String nombres(String key) => ((l[key] as List? ?? const []).cast<Map>())
        .map((x) => x['nombre'])
        .join(', ');
    final mano = nombres('mano');
    final oros = nombres('oros');
    final defensa = nombres('defensa');
    final ataque = nombres('ataque');
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        '${l['nombre']} · castillo ${l['castillo']} · mano ${l['manoCantidad']}\n${mano.isEmpty ? '' : 'Tu mano: $mano\n'}Oros: ${oros.isEmpty ? '—' : oros}\nDefensa: ${defensa.isEmpty ? '—' : defensa}\nAtaque: ${ataque.isEmpty ? '—' : ataque}',
        style: const TextStyle(color: Colors.white70),
      ),
    );
  }
}

/// Cierre de una duda de la IA: tu jugada, la suya y lo que dice la simulación.
class _ResultadoDuda extends StatelessWidget {
  const _ResultadoDuda({required this.resultado, required this.siguiente});

  final Map<String, dynamic> resultado;
  final VoidCallback? siguiente;

  @override
  Widget build(BuildContext context) {
    final coincide = resultado['coincide'] == true;
    String pct(dynamic v) => v is num ? '${(v * 100).round()}%' : '—';
    // El turno completo, paso a paso; si es una sola jugada, tal cual.
    String pasos(dynamic turno, dynamic jugada) =>
        turno is List && turno.length > 1
            ? [
              for (var i = 0; i < turno.length; i++) '${i + 1}. ${turno[i]}',
            ].join('\n')
            : '${turno is List && turno.isNotEmpty ? turno.first : jugada}';
    Widget fila(String quien, String jugada, dynamic estima) => Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 64,
            child: Text(quien, style: const TextStyle(color: Colors.white60)),
          ),
          Expanded(
            child: Text(
              jugada,
              style: const TextStyle(color: Colors.white, fontSize: 15),
            ),
          ),
          if (!coincide)
            Text(
              pct(estima),
              style: const TextStyle(color: _gold, fontWeight: FontWeight.bold),
            ),
        ],
      ),
    );
    final quedan = resultado['quedan'];
    return Card(
      color: _surface,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Duda resuelta · ${resultado['mazo']} contra ${resultado['rival']} · turno ${resultado['turno']}',
              style: const TextStyle(color: _gold, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            fila(
              'Tú',
              pasos(resultado['tuTurno'], resultado['tuJugada']),
              resultado['estimaTuya'],
            ),
            fila(
              'La IA',
              pasos(resultado['turnoIa'], resultado['jugadaIa']),
              resultado['estimaIa'],
            ),
            const SizedBox(height: 4),
            Text(
              '${resultado['veredicto'] ?? ''}',
              style: const TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 6),
            const Text(
              'Tu turno quedó guardado como el correcto para esta posición.',
              style: TextStyle(color: Colors.white38, fontSize: 12),
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: siguiente,
              icon: const Icon(Icons.psychology_alt_outlined),
              label: Text(
                quedan is num && quedan > 0
                    ? 'Siguiente duda ($quedan en cola)'
                    : 'Buscar más dudas',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Decision extends StatefulWidget {
  const _Decision({required this.ref, required this.decision});
  final DocumentReference<Map<String, dynamic>> ref;
  final Map<String, dynamic> decision;
  @override
  State<_Decision> createState() => _DecisionState();
}

class _DecisionState extends State<_Decision> {
  final Set<String> _seleccion = {};
  final Map<String, String?> _bloqueos = {};
  String? _ultimoId;
  bool _enviando = false;

  Future<void> _enviar(dynamic valor) async {
    if (_enviando) return;
    setState(() => _enviando = true);
    try {
      await widget.ref.update({
        'respuesta': {'decisionId': widget.decision['id'], 'valor': valor},
      });
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.decision;
    if (_ultimoId != d['id']) {
      _ultimoId = d['id'] as String?;
      _seleccion.clear();
      _bloqueos.clear();
      _enviando = false;
    }
    final tipo = d['tipo'] as String? ?? '';
    final opciones = (d['opciones'] as List? ?? const []).cast<Map>();
    final cantidad = d['cantidad'] as int?;
    if (tipo == 'avance_fase') {
      return _card(
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '${d['titulo']}',
              style: const TextStyle(color: _gold, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: () => _enviar('continuar'),
              icon: const Icon(Icons.arrow_forward),
              label: const Text('Continuar'),
            ),
          ],
        ),
      );
    }
    if (tipo == 'mano_inicial' || tipo == 'confirmar') {
      return _card(
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('${d['titulo']}', style: const TextStyle(color: _gold)),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed:
                        () =>
                            _enviar(tipo == 'mano_inicial' ? 'mulligan' : 'no'),
                    child: Text(tipo == 'mano_inicial' ? 'Mulligan' : 'No'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton(
                    onPressed:
                        () =>
                            _enviar(tipo == 'mano_inicial' ? 'quedarse' : 'si'),
                    child: Text(tipo == 'mano_inicial' ? 'Quedarse' : 'Sí'),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    }
    if (tipo == 'atacantes' ||
        tipo == 'objetivos' ||
        tipo == 'descartes' ||
        tipo == 'mirar' ||
        tipo == 'pago_oro') {
      return _multiple(opciones, d, cantidad);
    }
    if (tipo == 'bloqueos') return _bloquear(opciones, d);
    return _simple(
      opciones,
      d,
      tipo == 'anular' || tipo == 'responder' || tipo == 'redirigir',
    );
  }

  Widget _card(Widget child) => Card(
    color: _surface,
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(14),
      child: child,
    ),
  );
  Widget _simple(List<Map> opciones, Map<String, dynamic> d, bool puedePasar) =>
      _card(
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '${d['titulo']}',
              style: const TextStyle(color: _gold, fontWeight: FontWeight.bold),
            ),
            if (puedePasar)
              TextButton(
                onPressed: () => _enviar('pasar'),
                child: const Text('No usar'),
              ),
            for (final o in opciones)
              ListTile(
                title: Text(
                  '${o['titulo'] ?? o['nombre'] ?? o['id']}',
                  style: const TextStyle(color: Colors.white),
                ),
                onTap: () async {
                  final valor = await elegirAccionConOros(context, o, d);
                  if (valor != null) await _enviar(valor);
                },
              ),
          ],
        ),
      );
  Widget _multiple(
    List<Map> opciones,
    Map<String, dynamic> d,
    int? cantidad,
  ) => _card(
    Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '${d['titulo']}${cantidad == null ? '' : ' ($cantidad)'}',
          style: const TextStyle(color: _gold, fontWeight: FontWeight.bold),
        ),
        for (final o in opciones)
          CheckboxListTile(
            value: _seleccion.contains('${o['id']}'),
            title: Text(
              '${o['nombre']}',
              style: const TextStyle(color: Colors.white),
            ),
            subtitle: Text(
              '${o['tipo'] ?? ''} ${o['fuerza'] == null ? '' : '· ${o['fuerza']}'}',
              style: const TextStyle(color: Colors.white54),
            ),
            onChanged:
                (v) => setState(() {
                  if (v == true) {
                    _seleccion.add('${o['id']}');
                  } else {
                    _seleccion.remove('${o['id']}');
                  }
                }),
          ),
        FilledButton(
          onPressed:
              cantidad != null && _seleccion.length != cantidad
                  ? null
                  : () => _enviar(_seleccion.toList()),
          child: const Text('Confirmar'),
        ),
      ],
    ),
  );
  Widget _bloquear(List<Map> opciones, Map<String, dynamic> d) => _card(
    Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '${d['titulo']}',
          style: const TextStyle(color: _gold, fontWeight: FontWeight.bold),
        ),
        for (final o in opciones)
          DropdownButtonFormField<String>(
            initialValue: _bloqueos['${(o['atacante'] as Map)['id']}'],
            dropdownColor: _surface,
            decoration: InputDecoration(
              labelText: '${(o['atacante'] as Map)['nombre']}',
            ),
            items: [
              const DropdownMenuItem(value: null, child: Text('Sin bloqueo')),
              ...((o['bloqueadores'] as List).cast<Map>()).map(
                (b) => DropdownMenuItem(
                  value: '${b['id']}',
                  child: Text('${b['nombre']}'),
                ),
              ),
            ],
            onChanged:
                (v) => setState(
                  () => _bloqueos['${(o['atacante'] as Map)['id']}'] = v,
                ),
          ),
        FilledButton(
          onPressed: () => _enviar(_bloqueos),
          child: const Text('Confirmar bloqueos'),
        ),
      ],
    ),
  );
}

class _RevisionDesafio extends StatelessWidget {
  const _RevisionDesafio({
    required this.ref,
    required this.resultado,
    required this.reportes,
  });

  final DocumentReference<Map<String, dynamic>> ref;
  final Map<String, dynamic> resultado;
  final dynamic reportes;

  Future<void> _abrirRepeticion(BuildContext context) async {
    try {
      final meta = (resultado['repeticion'] as Map).cast<String, dynamic>();
      final chunks = await ref.collection('repeticion').orderBy('indice').get();
      final pasos = <dynamic>[
        for (final chunk in chunks.docs)
          ...(chunk.data()['pasos'] as List? ?? const []),
      ];
      if (!context.mounted) return;
      if (pasos.isEmpty) throw StateError('La repetición está vacía');
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder:
              (_) => TableroScreen(
                resultado: {...meta, 'pasos': pasos},
                simulacion: ref,
              ),
        ),
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo abrir la repetición: $e')),
        );
      }
    }
  }

  String _elegida(Map<String, dynamic> evento) {
    final elegida = evento['elegida'];
    if (elegida is String) {
      for (final o in (evento['opciones'] as List? ?? const [])) {
        if (o is Map && '${o['id']}' == elegida) {
          return '${o['titulo'] ?? o['nombre'] ?? elegida}';
        }
      }
    }
    if (elegida is List) {
      return elegida.isEmpty ? 'ninguna' : elegida.join(', ');
    }
    if (elegida is Map) {
      return elegida.isEmpty
          ? 'ninguno'
          : elegida.entries.map((x) => '${x.key} → ${x.value}').join(', ');
    }
    return '$elegida';
  }

  Widget _analisisBloqueos(Map analisis) {
    final opciones =
        (analisis['opciones'] as List? ?? const []).whereType<Map>();
    final obligatorios =
        (analisis['bloqueosObligatorios'] as List? ?? const [])
            .whereType<Map>();
    String carta(Map b, String clave) =>
        b['${clave}Uid'] == null
            ? '${b[clave]}'
            : '${b[clave]} (#${b['${clave}Uid']})';
    String bloqueo(Map b) =>
        '${carta(b, 'bloqueador')} bloquea a ${carta(b, 'atacante')}';
    return Padding(
      padding: const EdgeInsets.only(top: 5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Opciones simuladas · ${analisis['muestrasPorOpcion']} muestras por opción'
            '${analisis['opcionesLimitadas'] == true ? ' · se comparó una selección' : ''}',
            style: const TextStyle(color: _gold, fontSize: 11),
          ),
          if (obligatorios.isNotEmpty)
            Text(
              'Obligatorios: ${obligatorios.map(bloqueo).join(' · ')}',
              style: const TextStyle(color: Colors.white60, fontSize: 11),
            ),
          for (final opcion in opciones)
            Builder(
              builder: (context) {
                final bloqueos =
                    (opcion['bloqueos'] as List? ?? const []).whereType<Map>();
                final nombre =
                    bloqueos.isEmpty
                        ? (obligatorios.isEmpty
                            ? 'Sin bloquear'
                            : 'Sin bloqueos adicionales')
                        : bloqueos.map(bloqueo).join(' · ');
                final tasa = opcion['estimacionVictoria'] as num?;
                final diferencia = opcion['diferenciaConReferencia'] as num?;
                final referencia = opcion['referenciaHeuristica'] == true;
                final detalle =
                    referencia
                        ? ' · referencia heurística'
                        : diferencia == null
                        ? ''
                        : ' · ${diferencia >= 0 ? '+' : ''}${(diferencia * 100).toStringAsFixed(0)} puntos vs. referencia'
                            ' (${opcion['muestrasComparables']} comparaciones)';
                return Text(
                  '${opcion['elegida'] == true ? '✓ ' : ''}$nombre: '
                  '${tasa == null ? 'sin resultado válido' : '${(tasa * 100).toStringAsFixed(0)}% en ${opcion['validas']} simulaciones'}$detalle',
                  style: const TextStyle(color: Colors.white60, fontSize: 11),
                );
              },
            ),
        ],
      ),
    );
  }

  Future<void> _reportar(
    BuildContext context,
    Map<String, dynamic> evento,
  ) async {
    final campo = TextEditingController();
    final texto = await showDialog<String>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Reportar decisión'),
            content: TextField(
              controller: campo,
              autofocus: true,
              maxLines: 4,
              decoration: const InputDecoration(
                hintText: 'Qué fue incorrecto y cuál debió ser la jugada.',
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, campo.text.trim()),
                child: const Text('Guardar reporte'),
              ),
            ],
          ),
    );
    if (texto == null || texto.isEmpty) return;
    await ref.update({
      'reportes': FieldValue.arrayUnion([
        {'fecha': Timestamp.now(), 'comentario': texto, 'decision': evento},
      ]),
    });
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Reporte guardado para revisar la heurística.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final decisiones =
        (resultado['decisiones'] as List? ?? const [])
            .whereType<Map>()
            .map((x) => x.cast<String, dynamic>())
            .toList();
    final cantidadReportes = (reportes as List? ?? const []).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (resultado['politicaIa'] != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(switch (resultado['politicaIa']) {
              'alternativas_djoser' =>
                'IA: política aprendida para este enfrentamiento',
              'busqueda_bloqueos' =>
                resultado['politicaBaseIa'] == 'alternativas_djoser'
                    ? 'IA: política aprendida y búsqueda experimental de bloqueos'
                    : 'IA: heurística y búsqueda experimental de bloqueos',
              _ => 'IA: heurística',
            }, style: const TextStyle(color: _gold, fontWeight: FontWeight.bold)),
          ),
        if (resultado['repeticion'] is Map)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: _gold,
                foregroundColor: Colors.black,
              ),
              onPressed: () => _abrirRepeticion(context),
              icon: const Icon(Icons.table_restaurant_rounded),
              label: const Text('Ver en el tablero, jugada por jugada'),
            ),
          )
        else
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Text(
              'Esta partida anterior no guardó la mesa por pasos. Puedes revisar sus decisiones abajo.',
              style: TextStyle(color: Colors.white60),
            ),
          ),
        Card(
          color: _surface,
          child: ExpansionTile(
            iconColor: _gold,
            collapsedIconColor: _gold,
            title: Text(
              'Revisar decisiones (${decisiones.length})',
              style: const TextStyle(color: _gold, fontWeight: FontWeight.bold),
            ),
            subtitle: Text(
              '$cantidadReportes reportes guardados · revisa tus jugadas y las de la IA.',
              style: const TextStyle(color: Colors.white60, fontSize: 12),
            ),
            children: [
              for (final evento in decisiones)
                ListTile(
                  dense: true,
                  title: Text(
                    '${evento['paso']}. ${evento['quien']} · T${evento['turno']} ${evento['fase']}',
                    style: const TextStyle(color: Colors.white),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${evento['tipo']}: ${_elegida(evento)}',
                        style: const TextStyle(color: Colors.white60),
                      ),
                      if (evento['analisisBloqueos'] is Map)
                        _analisisBloqueos(evento['analisisBloqueos'] as Map),
                    ],
                  ),
                  trailing: IconButton(
                    tooltip: 'Reportar error',
                    icon: const Icon(Icons.bug_report_outlined, color: _gold),
                    onPressed: () => _reportar(context, evento),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Aviso con la jugada que la IA acaba de hacer (se ve mientras juega).
/// Muestra su hijo unos segundos y luego lo desvanece (una vez por key).
/// La última línea «✗» de los últimos movimientos (una habilidad que falló).
String? _ultimoFallo(Map<String, dynamic> estado) {
  final log = (estado['log'] as List? ?? const []).map((x) => '$x').toList();
  for (final linea in log.reversed.take(6)) {
    if (linea.contains('✗')) return linea;
  }
  return null;
}

class _AvisoTemporal extends StatefulWidget {
  const _AvisoTemporal({required this.segundos, required this.child});

  final int segundos;
  final Widget child;

  @override
  State<_AvisoTemporal> createState() => _AvisoTemporalState();
}

class _AvisoTemporalState extends State<_AvisoTemporal> {
  bool _visible = true;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(Duration(seconds: widget.segundos), () {
      if (mounted) setState(() => _visible = false);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
    ignoring: !_visible,
    child: GestureDetector(
      // Tocarlo lo cierra al tiro, sin esperar.
      onTap: () => setState(() => _visible = false),
      child: AnimatedOpacity(
        opacity: _visible ? 1 : 0,
        duration: const Duration(milliseconds: 250),
        child: widget.child,
      ),
    ),
  );
}

class _AvisoTurno extends StatelessWidget {
  const _AvisoTurno({required this.turno});

  final Object? turno;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
    decoration: BoxDecoration(
      color: const Color(0xEE2A1C08),
      borderRadius: BorderRadius.circular(24),
      border: Border.all(color: _gold, width: 2),
    ),
    child: Text(
      'Tu turno · T$turno',
      style: const TextStyle(
        color: _gold,
        fontSize: 20,
        fontWeight: FontWeight.w900,
      ),
    ),
  );
}

class _AvisoIa extends StatelessWidget {
  const _AvisoIa({required this.texto, required this.voto});

  final String texto;
  final Widget voto;

  @override
  Widget build(BuildContext context) => AnimatedSwitcher(
    duration: const Duration(milliseconds: 250),
    child: Container(
      key: ValueKey(texto),
      constraints: const BoxConstraints(maxWidth: 620),
      margin: const EdgeInsets.symmetric(horizontal: 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xEE1A120C),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _gold),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.smart_toy_outlined, color: _gold, size: 20),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              texto,
              style: const TextStyle(color: Colors.white, fontSize: 14),
            ),
          ),
          const SizedBox(width: 4),
          voto,
        ],
      ),
    ),
  );
}

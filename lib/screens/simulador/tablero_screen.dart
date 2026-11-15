// lib/screens/simulador/tablero_screen.dart
//
// Repetición de una partida narrada sobre un campo de juego de Mitos y
// Leyendas: cada paso es una foto de la mesa guardada por el simulador
// (simulator/myl_sim/motor.py → Partida.foto). Se avanza con flechas, con
// reproducción automática o con la barra de tiempo.
//
// La mesa se dibuja en un lienzo de tamaño fijo (uno horizontal y otro
// vertical) que se escala entero a la pantalla, como en los juegos: se ve
// igual en PC y tablet, en cualquier orientación, y nunca se desborda.

import 'dart:async';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/card_myl.dart';
import '../../services/drive_service.dart';
import '../../widgets/card_image.dart';
import 'narracion_texto.dart';

const _gold = Color(0xFFF2D487);
const _oroInicial = 'oro_inicial';
const _fondo = 'assets/wallpaper/2.jpg';

// Lienzos de la mesa.
const _horizontal = Size(1600, 920);
const _vertical = Size(900, 1440);

class TableroScreen extends StatefulWidget {
  final Map<String, dynamic> resultado;

  /// Documento de la simulación, donde se guardan los reportes.
  final DocumentReference<Map<String, dynamic>>? simulacion;
  const TableroScreen({super.key, required this.resultado, this.simulacion});

  @override
  State<TableroScreen> createState() => _TableroScreenState();
}

class _TableroScreenState extends State<TableroScreen> {
  late final List<Map> _pasos = (widget.resultado['pasos'] as List).cast<Map>();
  late final Map<String, String> _nombres = (widget.resultado['cartas'] as Map)
      .map((k, v) => MapEntry('$k', '$v'));
  final Map<String, String?> _imagenes = {};

  /// Contenido de Cementerio y Destierro en cada paso, por jugador. El
  /// simulador solo lo guarda donde cambia ("cl", "dl"); acá se arrastra.
  /// null = partida anterior a este dato.
  late final _cementerios = _arrastrar('cl');
  late final _destierros = _arrastrar('dl');
  int _i = 0;
  Timer? _timer;
  int _velocidad = 900; // ms por paso

  String get _mazoA => '${(widget.resultado['mazoA'] as Map)['nombre']}';
  String get _mazoB => '${(widget.resultado['mazoB'] as Map)['nombre']}';

  @override
  void initState() {
    super.initState();
    _cargarImagenes();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  // Misma resolución que Mazos: imagen oficial del documento y, si no hay,
  // la variante oficial (o la primera) de la subcolección.
  Future<void> _cargarImagenes() async {
    final ids = _nombres.keys.where((id) => id != _oroInicial).toList();
    final col = FirebaseFirestore.instance.collection('cards');
    final sinImagen = <String>[];
    for (var k = 0; k < ids.length; k += 30) {
      final chunk = ids.sublist(k, math.min(k + 30, ids.length));
      try {
        final snap =
            await col.where(FieldPath.documentId, whereIn: chunk).get();
        for (final d in snap.docs) {
          final data = d.data();
          final raw =
              (data['officialImageUrl'] as String?) ??
              (data['imageUrl'] as String?) ??
              CardMyL.fromMap(data, d.id).bestVariant?.imageFrontUrl;
          if (raw != null && raw.trim().isNotEmpty) {
            _imagenes[d.id] = DriveService.webSafeUrl(raw.trim());
          } else {
            sinImagen.add(d.id);
          }
        }
        if (mounted) setState(() {});
      } catch (_) {}
    }
    for (final id in sinImagen) {
      try {
        final variantes = col.doc(id).collection('variants');
        var snap =
            await variantes.where('official', isEqualTo: true).limit(1).get();
        if (snap.docs.isEmpty) snap = await variantes.limit(1).get();
        final raw =
            snap.docs.isEmpty
                ? null
                : (snap.docs.first.data()['imageFrontUrl'] as String?)?.trim();
        if (raw != null && raw.isNotEmpty) {
          _imagenes[id] = DriveService.webSafeUrl(raw);
          if (mounted) setState(() {});
        }
      } catch (_) {}
    }
  }

  List<List<List<String>?>> _arrastrar(String clave) {
    final actual = <List<String>?>[null, null];
    return [
      for (final paso in _pasos)
        [
          for (final (k, j) in (paso['j'] as List).cast<Map>().indexed)
            actual[k] =
                j[clave] is List
                    ? (j[clave] as List).map((x) => '$x').toList()
                    : actual[k],
        ],
    ];
  }

  void _verPila(String titulo, List<String>? ids) {
    showDialog<void>(
      context: context,
      builder:
          (_) => _VerPila(
            titulo: titulo,
            ids: ids,
            nombres: _nombres,
            imagenes: _imagenes,
          ),
    );
  }

  int _previo = -1;

  void _ir(int i) => setState(() {
    _previo = _i;
    _i = i.clamp(0, _pasos.length - 1);
  });

  /// Cartas que llegaron a la mano de cada jugador en este paso (robo).
  List<List<String>> _robadas(Map? antes, Map ahora) {
    if (antes == null || !'${ahora['x']}'.contains('roba')) return [[], []];
    final a = (antes['j'] as List).cast<Map>();
    final b = (ahora['j'] as List).cast<Map>();
    return [
      for (var k = 0; k < 2; k++)
        _nuevasEn(
          (a[k]['h'] as List).map((x) => '$x').toList(),
          (b[k]['h'] as List).map((x) => '$x').toList(),
        ),
    ];
  }

  void _alternarReproduccion() {
    if (_timer != null) {
      _timer!.cancel();
      setState(() => _timer = null);
      return;
    }
    if (_i >= _pasos.length - 1) _i = 0;
    _timer = Timer.periodic(Duration(milliseconds: _velocidad), (_) {
      if (_i >= _pasos.length - 1) {
        _timer?.cancel();
        setState(() => _timer = null);
      } else {
        _ir(_i + 1);
      }
    });
    setState(() {});
  }

  void _cambiarVelocidad(int ms) {
    final reproduciendo = _timer != null;
    _timer?.cancel();
    _timer = null;
    setState(() => _velocidad = ms);
    if (reproduciendo) _alternarReproduccion();
  }

  /// Cartas que se ven en la mesa en este paso (para elegir cuál falló).
  List<String> _cartasDelPaso(Map paso) {
    final ids = <String>{};
    for (final j in (paso['j'] as List).cast<Map>()) {
      for (final k in ['h', 'r', 'p', 'ap']) {
        ids.addAll((j[k] as List).map((x) => '$x'));
      }
      for (final k in ['def', 'atk']) {
        for (final a in (j[k] as List).cast<List>()) {
          ids.add('${a[0]}');
          ids.addAll((a[2] as List).map((x) => '$x'));
        }
      }
      if (j['ct'] != null) ids.add('${j['ct']}');
      if (j['dt'] != null) ids.add('${j['dt']}');
    }
    ids.remove(_oroInicial);
    return ids.map((id) => _nombres[id] ?? id).toSet().toList()..sort();
  }

  Future<void> _reportar() async {
    final ref = widget.simulacion;
    if (ref == null) return;
    _timer?.cancel();
    setState(() => _timer = null);
    final paso = _pasos[_i];
    final reporte = await showDialog<Map<String, dynamic>>(
      context: context,
      builder:
          (_) => _DialogoReporte(
            paso: _i,
            texto: '${paso['x']}'.replaceAll('─', '').trim(),
            cartas: _cartasDelPaso(paso),
          ),
    );
    if (reporte == null) return;
    try {
      await ref.update({
        'reportes': FieldValue.arrayUnion([
          {
            ...reporte,
            'paso': _i,
            'turno': paso['t'],
            'fase': paso['f'],
            'texto': '${paso['x']}',
            'creado': Timestamp.now(),
          },
        ]),
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Reporte guardado en la simulación')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('No se pudo guardar: $e')));
    }
  }

  KeyEventResult _teclas(FocusNode _, KeyEvent e) {
    if (e is! KeyDownEvent) return KeyEventResult.ignored;
    if (e.logicalKey == LogicalKeyboardKey.arrowRight) {
      _ir(_i + 1);
    } else if (e.logicalKey == LogicalKeyboardKey.arrowLeft) {
      _ir(_i - 1);
    } else if (e.logicalKey == LogicalKeyboardKey.space) {
      _alternarReproduccion();
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    if (_pasos.isEmpty) {
      return const Scaffold(body: Center(child: Text('Sin jugadas')));
    }
    final paso = _pasos[_i];
    final jugadores = (paso['j'] as List).cast<Map>();
    final avanzo = _i > 0 && _previo == _i - 1;
    final antes = avanzo ? _pasos[_i - 1] : null;
    final robadas = _robadas(antes, paso);
    final dano = RegExp(
      r'(.+) recibe (\d+) de daño',
    ).firstMatch('${paso['x']}');
    final mesa = _Mesa(
      previo: antes,
      indice: _i,
      paso: paso,
      rival: jugadores[1],
      tuyo: jugadores[0],
      nombreRival: _mazoB,
      nombreTuyo: _mazoA,
      nombres: _nombres,
      imagenes: _imagenes,
      cementerios: _cementerios[_i],
      destierros: _destierros[_i],
      verPila: _verPila,
    );
    return Focus(
      autofocus: true,
      onKeyEvent: _teclas,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          fit: StackFit.expand,
          children: [
            Image.asset(_fondo, fit: BoxFit.cover),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  radius: 1.1,
                  colors: [Color(0x99000000), Color(0xE6000000)],
                ),
              ),
            ),
            SafeArea(
              child: Column(
                children: [
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, box) {
                        final horizontal = box.maxWidth > box.maxHeight;
                        final lienzo = horizontal ? _horizontal : _vertical;
                        return Center(
                          child: FittedBox(
                            fit: BoxFit.contain,
                            child: SizedBox(
                              width: lienzo.width,
                              height: lienzo.height,
                              child: Stack(
                                children: [
                                  Positioned.fill(
                                    child:
                                        horizontal
                                            ? mesa.horizontal()
                                            : mesa.vertical(),
                                  ),
                                  // Robo: la carta se muestra en grande, se da
                                  // vuelta y baja a la mano de quien roba.
                                  for (var k = 0; k < 2; k++)
                                    if (robadas[k].isNotEmpty)
                                      Positioned.fill(
                                        child: Align(
                                          alignment: Alignment(
                                            0,
                                            k == 0 ? .45 : -.45,
                                          ),
                                          child: _RevelarRobo(
                                            key: ValueKey('robo$_i-$k'),
                                            ids: robadas[k],
                                            nombres: _nombres,
                                            imagenes: _imagenes,
                                            haciaAbajo: k == 0,
                                          ),
                                        ),
                                      ),
                                  if (avanzo && dano != null)
                                    Positioned.fill(
                                      child: Align(
                                        alignment: Alignment(
                                          0,
                                          dano.group(1)!.trim() == _mazoA
                                              ? .55
                                              : -.55,
                                        ),
                                        child: _DanoFlotante(
                                          key: ValueKey('dano$_i'),
                                          dano: dano.group(2)!,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  _controles(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ◀ Ant | ▶ Play | Sig ▶ | Paso: N / total | velocidad | Salir
  Widget _controles() => Container(
    decoration: BoxDecoration(
      color: const Color(0xE61A120C),
      border: Border(top: BorderSide(color: _gold.withValues(alpha: .4))),
    ),
    padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 26,
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 3,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
              overlayShape: SliderComponentShape.noOverlay,
            ),
            child: Slider(
              value: _i.toDouble(),
              max: (_pasos.length - 1).toDouble(),
              divisions: _pasos.length > 1 ? _pasos.length - 1 : null,
              activeColor: _gold,
              inactiveColor: Colors.white24,
              onChanged: (v) => _ir(v.round()),
            ),
          ),
        ),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _boton(
                Icons.first_page,
                'Inicio',
                () => _ir(0),
                tooltip: 'Inicio',
              ),
              _boton(
                Icons.chevron_left,
                'Ant',
                () => _ir(_i - 1),
                tooltip: 'Anterior (←)',
              ),
              const SizedBox(width: 6),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: _gold,
                  foregroundColor: Colors.black,
                  visualDensity: VisualDensity.compact,
                ),
                onPressed: _alternarReproduccion,
                icon: Icon(_timer != null ? Icons.pause : Icons.play_arrow),
                label: Text(_timer != null ? 'Pausa' : 'Play'),
              ),
              const SizedBox(width: 6),
              _boton(
                Icons.chevron_right,
                'Sig',
                () => _ir(_i + 1),
                tooltip: 'Siguiente (→)',
                iconoDespues: true,
              ),
              _boton(
                Icons.last_page,
                'Final',
                () => _ir(_pasos.length - 1),
                tooltip: 'Final',
                iconoDespues: true,
              ),
              _separador(),
              Text(
                'Paso: ${_i + 1} / ${_pasos.length}',
                style: const TextStyle(
                  color: Colors.white70,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
              _separador(),
              DropdownButton<int>(
                value: _velocidad,
                isDense: true,
                dropdownColor: const Color(0xFF1A120C),
                underline: const SizedBox.shrink(),
                iconEnabledColor: _gold,
                style: const TextStyle(color: Colors.white70, fontSize: 13),
                items: const [
                  DropdownMenuItem(value: 1800, child: Text('Lento')),
                  DropdownMenuItem(value: 900, child: Text('Normal')),
                  DropdownMenuItem(value: 400, child: Text('Rápido')),
                ],
                onChanged: (v) => v == null ? null : _cambiarVelocidad(v),
              ),
              if (widget.simulacion != null) ...[
                _separador(),
                _boton(
                  Icons.flag_outlined,
                  'Reportar',
                  _reportar,
                  tooltip: 'Reportar un error en esta jugada',
                ),
              ],
              _separador(),
              _boton(
                Icons.logout,
                'Salir',
                () => Navigator.pop(context),
                tooltip: 'Salir',
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _separador() => Container(
    width: 1,
    height: 22,
    margin: const EdgeInsets.symmetric(horizontal: 10),
    color: Colors.white24,
  );

  Widget _boton(
    IconData icono,
    String texto,
    VoidCallback onTap, {
    required String tooltip,
    bool iconoDespues = false,
  }) {
    final icon = Icon(icono, color: _gold, size: 20);
    final label = Text(
      texto,
      style: const TextStyle(color: _gold, fontWeight: FontWeight.w700),
    );
    return Tooltip(
      message: tooltip,
      child: TextButton(
        style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
        onPressed: onTap,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: iconoDespues ? [label, icon] : [icon, label],
        ),
      ),
    );
  }
}

/// Qué salió mal en la jugada actual. Devuelve {tipo, carta?, comentario}.
class _DialogoReporte extends StatefulWidget {
  final int paso;
  final String texto;
  final List<String> cartas;

  const _DialogoReporte({
    required this.paso,
    required this.texto,
    required this.cartas,
  });

  @override
  State<_DialogoReporte> createState() => _DialogoReporteState();
}

class _DialogoReporteState extends State<_DialogoReporte> {
  static const _tipos = [
    'Habilidad mal ejecutada',
    'Jugada mejorable',
    'Regla mal aplicada',
  ];
  String _tipo = _tipos.first;
  String? _carta;
  final _comentario = TextEditingController();

  @override
  void dispose() {
    _comentario.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('Reportar paso ${widget.paso + 1}'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.texto,
            style: const TextStyle(fontStyle: FontStyle.italic),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _tipo,
            decoration: const InputDecoration(labelText: '¿Qué pasó?'),
            items: [
              for (final t in _tipos)
                DropdownMenuItem(value: t, child: Text(t)),
            ],
            onChanged: (v) => setState(() => _tipo = v ?? _tipo),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String?>(
            initialValue: _carta,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Carta (opcional)'),
            items: [
              const DropdownMenuItem(value: null, child: Text('—')),
              for (final c in widget.cartas)
                DropdownMenuItem(
                  value: c,
                  child: Text(c, overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: (v) => setState(() => _carta = v),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _comentario,
            autofocus: true,
            minLines: 3,
            maxLines: 6,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: 'Qué debió pasar',
              hintText:
                  'Ej.: Kawit no debía robar porque yo tenía más Oros; '
                  'o: era mejor bloquear con el Muro que con el Héroe.',
            ),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancelar'),
      ),
      FilledButton(
        onPressed:
            _comentario.text.trim().isEmpty
                ? null
                : () => Navigator.pop(context, {
                  'tipo': _tipo,
                  'carta': _carta,
                  'comentario': _comentario.text.trim(),
                }),
        child: const Text('Guardar'),
      ),
    ],
  );
}

/// Arma la mesa para un paso. Todas las medidas son del lienzo fijo; el
/// lienzo completo se escala a la pantalla.
class _Mesa {
  final Map paso;
  final Map? previo; // paso anterior si se avanzó de a uno (para animar)
  final int indice;
  final Map rival;
  final Map tuyo;
  final String nombreRival;
  final String nombreTuyo;
  final Map<String, String> nombres;
  final Map<String, String?> imagenes;
  final List<List<String>?> cementerios; // por jugador (0 = tuyo, 1 = rival)
  final List<List<String>?> destierros;
  final void Function(String titulo, List<String>? ids) verPila;

  _Mesa({
    required this.previo,
    required this.indice,
    required this.paso,
    required this.rival,
    required this.tuyo,
    required this.nombreRival,
    required this.nombreTuyo,
    required this.nombres,
    required this.imagenes,
    required this.cementerios,
    required this.destierros,
    required this.verPila,
  });

  bool get _rivalActivo => paso['a'] == 1;

  Widget carta(
    String id,
    double ancho, {
    int? fuerza,
    List armas = const [],
    bool pagado = false,
    bool nueva = false,
    String clave = '',
  }) {
    final c = _Carta(
      id: id,
      nombre: nombres[id] ?? id,
      url: imagenes[id],
      ancho: ancho,
      fuerza: fuerza,
      armas: armas.map((a) => nombres['$a'] ?? '$a').toList(),
      pagado: pagado,
    );
    // La clave cambia en cada paso para que la entrada se vuelva a animar.
    return nueva ? _Entrada(key: ValueKey('$indice-$clave-$id'), child: c) : c;
  }

  /// ¿Qué cartas de esta zona no estaban en el paso anterior?
  List<bool> _marcas(Map j, String zona, List<String> ahora) {
    final antes =
        previo == null
            ? null
            : ((previo!['j'] as List).cast<Map>())[identical(j, tuyo) ? 0 : 1];
    if (antes == null) return List.filled(ahora.length, false);
    final previas = _ids(antes, zona);
    final nuevas = _nuevasEn(previas, ahora).toList();
    return [for (final id in ahora) nuevas.remove(id)];
  }

  List<String> _ids(Map j, String zona) => switch (zona) {
    'def' ||
    'atk' => [for (final a in (j[zona] as List).cast<List>()) '${a[0]}'],
    _ => (j[zona] as List).map((x) => '$x').toList(),
  };

  List<Widget> _aliados(Map j, String clave, double ancho) {
    final ids = _ids(j, clave);
    final marcas = _marcas(j, clave, ids);
    final lista = (j[clave] as List).cast<List>();
    return [
      for (var k = 0; k < lista.length; k++)
        carta(
          ids[k],
          ancho,
          fuerza: (lista[k][1] as num).toInt(),
          armas: lista[k][2] as List,
          nueva: marcas[k],
          clave: '$clave$k',
        ),
    ];
  }

  List<Widget> _simples(
    Map j,
    String zona,
    double ancho, {
    bool pagado = false,
  }) {
    final ids = _ids(j, zona);
    final marcas = _marcas(j, zona, ids);
    return [
      for (var k = 0; k < ids.length; k++)
        carta(
          ids[k],
          ancho,
          pagado: pagado,
          nueva: marcas[k],
          clave: '$zona$k',
        ),
    ];
  }

  /// Dos filas por jugador: Defensa con el Apoyo (Tótems) a la derecha, y
  /// Ataque, siempre hacia el centro. Sin recuadros: quien juega MyL ya
  /// reconoce la distribución.
  List<Widget> _lineas(Map j, bool arriba, double ancho, double alto) {
    final cartaAncho = (alto - 6) / 1.4;
    final filas = [
      _Zona(
        ancho: ancho,
        alto: alto,
        cartas: _aliados(j, 'def', cartaAncho),
        derecha: _simples(j, 'ap', cartaAncho),
      ),
      _Zona(ancho: ancho, alto: alto, cartas: _aliados(j, 'atk', cartaAncho)),
    ];
    return arriba ? filas : filas.reversed.toList();
  }

  Widget _mano(Map j, bool arriba, double ancho, double alto) => _Abanico(
    ancho: ancho,
    alto: alto,
    arriba: arriba,
    cartas: _simples(j, 'h', (alto - 14) / 1.4),
  );

  Widget _panel(Map j, String nombre, bool activo, double ancho) =>
      _PanelJugador(nombre: nombre, j: j, activo: activo, ancho: ancho);

  Widget _pilas(Map j, double cartaAncho) {
    final k = identical(j, tuyo) ? 0 : 1;
    final duenio = k == 0 ? nombreTuyo : nombreRival;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _Pila(
          titulo: 'Destierro',
          n: (j['d'] as num).toInt(),
          ancho: cartaAncho,
          tope: j['dt'] == null ? null : carta('${j['dt']}', cartaAncho),
          onTap: () => verPila('Destierro · $duenio', destierros[k]),
        ),
        _Pila(
          titulo: 'Cementerio',
          n: (j['c'] as num).toInt(),
          ancho: cartaAncho,
          tope: j['ct'] == null ? null : carta('${j['ct']}', cartaAncho),
          onTap: () => verPila('Cementerio · $duenio', cementerios[k]),
        ),
        _Pila(
          titulo: 'Castillo',
          n: (j['m'] as num).toInt(),
          ancho: cartaAncho,
          reves: true,
        ),
      ],
    );
  }

  Widget _oros(
    String titulo,
    List ids,
    double ancho,
    double alto, {
    bool pagado = false,
  }) => _Recursos(
    titulo: '$titulo: ${ids.length}',
    ancho: ancho,
    alto: alto,
    cartas: [for (final id in ids) carta('$id', 44, pagado: pagado)],
  );

  Widget _fase(double ancho) => _BannerFase(
    turno: '${paso['t']}',
    fase: '${paso['f']}'.replaceAll('_', ' '),
    juega: paso['a'] == 0 ? nombreTuyo : nombreRival,
    texto: '${paso['x']}'.replaceAll('─', '').trim(),
    cartas: nombres.values,
    ancho: ancho,
  );

  // ── Lienzo horizontal: fichas y pilas a la izquierda, mesa al centro,
  //    Reserva/Pagado, fase y jugada a la derecha.
  Widget horizontal() {
    const izq = 250.0, der = 300.0, gap = 12.0;
    final centro = _horizontal.width - izq - der - 4 * gap;
    const altoMano = 160.0, altoLinea = 135.0;
    return Padding(
      padding: const EdgeInsets.all(gap),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: izq,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _panel(rival, nombreRival, _rivalActivo, izq),
                const SizedBox(height: 10),
                _pilas(rival, 66),
                const Spacer(),
                _pilas(tuyo, 66),
                const SizedBox(height: 10),
                _panel(tuyo, nombreTuyo, !_rivalActivo, izq),
              ],
            ),
          ),
          const SizedBox(width: gap),
          SizedBox(
            width: centro,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _mano(rival, true, centro, altoMano),
                ..._lineas(rival, true, centro, altoLinea),
                const _Divisor(),
                ..._lineas(tuyo, false, centro, altoLinea),
                _mano(tuyo, false, centro, altoMano),
              ],
            ),
          ),
          const SizedBox(width: gap),
          SizedBox(
            width: der,
            child: Column(
              children: [
                _oros('RESERVA (rival)${(rival['v'] as num? ?? 0) > 0 ? '  +${rival['v']} temporal' : ''}', rival['r'] as List, der, 150),
                const SizedBox(height: 8),
                _oros(
                  'PAGADO (rival)',
                  rival['p'] as List,
                  der,
                  110,
                  pagado: true,
                ),
                const Spacer(),
                _fase(der),
                const Spacer(),
                _oros('PAGADO', tuyo['p'] as List, der, 110, pagado: true),
                const SizedBox(height: 8),
                _oros('RESERVA${(tuyo['v'] as num? ?? 0) > 0 ? '  +${tuyo['v']} temporal' : ''}', tuyo['r'] as List, der, 150),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Lienzo vertical: cada lado con su ficha, pilas y Oros en una franja;
  //    la fase y la jugada en el centro, entre los dos.
  Widget vertical() {
    const gap = 10.0;
    final ancho = _vertical.width - 2 * gap;
    const altoMano = 160.0, altoLinea = 140.0, altoFranja = 150.0;
    const panel = 230.0, pilas = 3 * 66.0 + 3 * 8;
    final anchoOros = ancho - panel - pilas - 2 * gap;

    Widget franja(Map j, String nombre, bool activo, bool arriba) => SizedBox(
      height: altoFranja,
      child: Row(
        crossAxisAlignment:
            arriba ? CrossAxisAlignment.start : CrossAxisAlignment.end,
        children: [
          _panel(j, nombre, activo, panel),
          const SizedBox(width: gap),
          SizedBox(width: pilas, child: _pilas(j, 66)),
          const SizedBox(width: gap),
          SizedBox(
            width: anchoOros,
            child: Column(
              children: [
                _oros(
                  '${arriba ? 'RESERVA (rival)' : 'RESERVA'}${(j['v'] as num? ?? 0) > 0 ? '  +${j['v']} temporal' : ''}',
                  j['r'] as List,
                  anchoOros,
                  71,
                ),
                const SizedBox(height: 8),
                _oros(
                  arriba ? 'PAGADO (rival)' : 'PAGADO',
                  j['p'] as List,
                  anchoOros,
                  71,
                  pagado: true,
                ),
              ],
            ),
          ),
        ],
      ),
    );

    return Padding(
      padding: const EdgeInsets.all(gap),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          franja(rival, nombreRival, _rivalActivo, true),
          _mano(rival, true, ancho, altoMano),
          ..._lineas(rival, true, ancho, altoLinea),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const _Divisor(),
              const SizedBox(height: 6),
              _fase(ancho * .8),
              const SizedBox(height: 6),
              const _Divisor(),
            ],
          ),
          ..._lineas(tuyo, false, ancho, altoLinea),
          _mano(tuyo, false, ancho, altoMano),
          franja(tuyo, nombreTuyo, !_rivalActivo, false),
        ],
      ),
    );
  }
}

/// Una fila de cartas de la mesa. `derecha`: el Apoyo (Tótems), separado de
/// los Aliados de la Defensa. Si no caben, la fila se achica.
class _Zona extends StatelessWidget {
  final double ancho;
  final double alto;
  final List<Widget> cartas;
  final List<Widget> derecha;

  const _Zona({
    required this.ancho,
    required this.alto,
    required this.cartas,
    this.derecha = const [],
  });

  Widget _grupo(List<Widget> cs, Alignment alineacion) => Align(
    alignment: alineacion,
    child: FittedBox(
      fit: BoxFit.scaleDown,
      alignment: alineacion,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final c in cs)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: c,
            ),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => SizedBox(
    width: ancho,
    height: alto,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child:
          derecha.isEmpty
              ? _grupo(cartas, Alignment.center)
              : Row(
                children: [
                  Expanded(flex: 3, child: _grupo(cartas, Alignment.center)),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: _grupo(derecha, Alignment.centerRight),
                  ),
                ],
              ),
    ),
  );
}

/// Mano en abanico; la del rival se abre hacia arriba.
class _Abanico extends StatelessWidget {
  final double ancho;
  final double alto;
  final bool arriba;
  final List<Widget> cartas;

  const _Abanico({
    required this.ancho,
    required this.alto,
    required this.arriba,
    required this.cartas,
  });

  @override
  Widget build(BuildContext context) {
    final n = cartas.length;
    final w = (alto - 14) / 1.4;
    final paso = n <= 1 ? 0.0 : math.min(w * .78, (ancho - w) / (n - 1));
    final total = w + paso * (n - 1);
    final inicio = (ancho - total) / 2;
    return SizedBox(
      width: ancho,
      height: alto,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          for (var i = 0; i < n; i++)
            () {
              final d = i - (n - 1) / 2;
              final giro = (d * .05).clamp(-.35, .35);
              final caida = math.min(12.0, d * d * 1.2);
              // Las cartas del centro quedan más adentro de la mesa y las de
              // los extremos caen hacia el borde, formando el arco.
              return Positioned(
                left: inicio + paso * i,
                top: arriba ? 12 - caida : null,
                bottom: arriba ? null : 12 - caida,
                child: Transform.rotate(
                  angle: arriba ? -giro : giro,
                  alignment:
                      arriba ? Alignment.topCenter : Alignment.bottomCenter,
                  child: cartas[i],
                ),
              );
            }(),
        ],
      ),
    );
  }
}

/// Ficha del jugador: nombre y contadores.
class _PanelJugador extends StatelessWidget {
  final String nombre;
  final Map j;
  final bool activo;
  final double ancho;

  const _PanelJugador({
    required this.nombre,
    required this.j,
    required this.activo,
    required this.ancho,
  });

  @override
  Widget build(BuildContext context) {
    Widget contador(IconData icono, String tip, int n) => Tooltip(
      message: tip,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icono, size: 16, color: _gold.withValues(alpha: .8)),
          const SizedBox(width: 3),
          Text(
            '$n',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
    return Container(
      width: ancho,
      height: 130,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xE62A1F14), Color(0xE6120D08)],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: activo ? _gold : _gold.withValues(alpha: .3),
          width: activo ? 2 : 1,
        ),
        boxShadow: [
          if (activo)
            BoxShadow(color: _gold.withValues(alpha: .35), blurRadius: 14),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: const Color(0xFF6B5320),
                child: Text(
                  nombre.isEmpty ? '?' : nombre.characters.first.toUpperCase(),
                  style: const TextStyle(
                    color: _gold,
                    fontWeight: FontWeight.w900,
                    fontSize: 20,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      nombre,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                        height: 1.1,
                      ),
                    ),
                    if (activo)
                      const Text(
                        'EN TURNO',
                        style: TextStyle(
                          color: _gold,
                          fontWeight: FontWeight.w900,
                          fontSize: 10,
                          letterSpacing: 1.5,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const Spacer(),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              contador(Icons.style, 'Mano', (j['h'] as List).length),
              contador(Icons.castle, 'Castillo', (j['m'] as num).toInt()),
              contador(
                Icons.dangerous_outlined,
                'Cementerio',
                (j['c'] as num).toInt(),
              ),
              contador(Icons.block, 'Destierro', (j['d'] as num).toInt()),
            ],
          ),
        ],
      ),
    );
  }
}

/// Mazo Castillo, Cementerio o Destierro con su cantidad.
class _Pila extends StatelessWidget {
  final String titulo;
  final int n;
  final double ancho;
  final Widget? tope;
  final bool reves;
  final VoidCallback? onTap;

  const _Pila({
    required this.titulo,
    required this.n,
    required this.ancho,
    this.tope,
    this.reves = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final alto = ancho * 1.4;
    final Widget base;
    if (reves && n > 0) {
      base = ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: Image.asset(
          'assets/reves.jpg',
          width: ancho,
          height: alto,
          fit: BoxFit.cover,
        ),
      );
    } else if (tope != null) {
      base = tope!;
    } else {
      base = Container(
        width: ancho,
        height: alto,
        decoration: BoxDecoration(
          color: Colors.black38,
          border: Border.all(color: _gold.withValues(alpha: .25)),
          borderRadius: BorderRadius.circular(4),
        ),
      );
    }
    final pila = Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            alignment: Alignment.center,
            children: [
              base,
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: Colors.black87,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: _gold.withValues(alpha: .5)),
                ),
                child: Text(
                  '$n',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            titulo,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
    if (onTap == null) return pila;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(onTap: onTap, child: pila),
    );
  }
}

/// Cartas de un Cementerio o Destierro en una ventana flotante (la de arriba
/// primero).
class _VerPila extends StatelessWidget {
  final String titulo;
  final List<String>? ids;
  final Map<String, String> nombres;
  final Map<String, String?> imagenes;

  const _VerPila({
    required this.titulo,
    required this.ids,
    required this.nombres,
    required this.imagenes,
  });

  @override
  Widget build(BuildContext context) {
    final lista = ids?.reversed.toList();
    return AlertDialog(
      backgroundColor: const Color(0xF21A120C),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: _gold.withValues(alpha: .5)),
      ),
      title: Text(
        '$titulo${lista == null ? '' : ' (${lista.length})'}',
        style: const TextStyle(color: _gold, fontWeight: FontWeight.w800),
      ),
      content: SizedBox(
        width: 640,
        child:
            lista == null
                ? const Text(
                  'Esta partida se simuló antes de guardar el contenido de '
                  'las pilas. Usa "Repetir esta partida" para verlo.',
                  style: TextStyle(color: Colors.white70),
                )
                : lista.isEmpty
                ? const Text('Vacío', style: TextStyle(color: Colors.white54))
                : SingleChildScrollView(
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final id in lista)
                        SizedBox(
                          width: 110,
                          child: Column(
                            children: [
                              _Carta(
                                id: id,
                                nombre: nombres[id] ?? id,
                                url: imagenes[id],
                                ancho: 110,
                              ),
                              const SizedBox(height: 3),
                              Text(
                                nombres[id] ?? id,
                                maxLines: 2,
                                textAlign: TextAlign.center,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cerrar', style: TextStyle(color: _gold)),
        ),
      ],
    );
  }
}

/// Reserva de Oro o Oros pagados: título con la cantidad y miniaturas.
class _Recursos extends StatelessWidget {
  final String titulo;
  final double ancho;
  final double alto;
  final List<Widget> cartas;

  const _Recursos({
    required this.titulo,
    required this.ancho,
    required this.alto,
    required this.cartas,
  });

  @override
  Widget build(BuildContext context) => Container(
    width: ancho,
    height: alto,
    padding: const EdgeInsets.fromLTRB(8, 4, 8, 6),
    decoration: BoxDecoration(
      color: Colors.black.withValues(alpha: .5),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: _gold.withValues(alpha: .3)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          titulo,
          style: const TextStyle(
            color: _gold,
            fontWeight: FontWeight.w800,
            fontSize: 12,
            letterSpacing: .8,
          ),
        ),
        const SizedBox(height: 4),
        Expanded(
          child: Align(
            alignment: Alignment.topLeft,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: ancho - 16,
                child: Wrap(spacing: 4, runSpacing: 4, children: cartas),
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

/// Turno, fase y la jugada que se está resolviendo.
class _BannerFase extends StatelessWidget {
  final String turno;
  final String fase;
  final String juega;
  final String texto;
  final Iterable<String> cartas;
  final double ancho;

  const _BannerFase({
    required this.turno,
    required this.fase,
    required this.juega,
    required this.texto,
    required this.cartas,
    required this.ancho,
  });

  @override
  Widget build(BuildContext context) => SizedBox(
    width: ancho,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0xE6120D08),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: _gold),
          ),
          child: Text(
            'TURNO $turno · FASE: ${fase.toUpperCase()}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: _gold,
              fontWeight: FontWeight.w900,
              fontSize: 13,
              letterSpacing: 1,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Juega $juega',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Colors.white60, fontSize: 12),
        ),
        const SizedBox(height: 6),
        Container(
          width: ancho,
          constraints: BoxConstraints(
            minHeight: 92,
            maxHeight: MediaQuery.sizeOf(context).height * .3,
          ),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xE65A1A10), Color(0xE62A0D08)],
            ),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _gold.withValues(alpha: .7)),
            boxShadow: [
              BoxShadow(color: _gold.withValues(alpha: .25), blurRadius: 12),
            ],
          ),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 350),
            transitionBuilder:
                (child, anim) => FadeTransition(
                  opacity: anim,
                  child: SlideTransition(
                    position: Tween(
                      begin: const Offset(0, .25),
                      end: Offset.zero,
                    ).animate(anim),
                    child: child,
                  ),
                ),
            child: SingleChildScrollView(
              key: ValueKey(texto),
              child: Text.rich(
                TextSpan(children: tramosConCartas(texto, cartas)),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  height: 1.25,
                ),
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

/// Línea brillante que separa los dos lados de la mesa.
class _Divisor extends StatelessWidget {
  const _Divisor();

  @override
  Widget build(BuildContext context) => Container(
    height: 3,
    margin: const EdgeInsets.symmetric(vertical: 2),
    decoration: BoxDecoration(
      gradient: LinearGradient(
        colors: [_gold.withValues(alpha: 0), _gold, _gold.withValues(alpha: 0)],
      ),
      boxShadow: [
        BoxShadow(color: _gold.withValues(alpha: .6), blurRadius: 10),
      ],
    ),
  );
}

/// Las que están en `ahora` y no en `antes` (multiconjunto: copias cuentan).
List<String> _nuevasEn(List<String> antes, List<String> ahora) {
  final quedan = [...antes];
  return [
    for (final id in ahora)
      if (!quedan.remove(id)) id,
  ];
}

/// Una carta que acaba de llegar: entra con rebote y un brillo que se apaga.
class _Entrada extends StatelessWidget {
  final Widget child;
  const _Entrada({super.key, required this.child});

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(begin: 0, end: 1),
    duration: const Duration(milliseconds: 650),
    curve: Curves.easeOutBack,
    child: child,
    builder:
        (context, t, child) => Opacity(
          opacity: t.clamp(0.0, 1.0),
          child: Transform.scale(
            scale: .55 + .45 * t,
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(5),
                boxShadow: [
                  BoxShadow(
                    color: _gold.withValues(
                      alpha: (1 - t).clamp(0.0, 1.0) * .9,
                    ),
                    blurRadius: 18,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: child,
            ),
          ),
        ),
  );
}

/// Robo: la carta aparece boca abajo, se da vuelta, se luce y baja a la mano.
class _RevelarRobo extends StatelessWidget {
  final List<String> ids;
  final Map<String, String> nombres;
  final Map<String, String?> imagenes;
  final bool haciaAbajo;

  const _RevelarRobo({
    super.key,
    required this.ids,
    required this.nombres,
    required this.imagenes,
    required this.haciaAbajo,
  });

  @override
  Widget build(BuildContext context) {
    const ancho = 190.0;
    return IgnorePointer(
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 1400),
        builder: (context, t, _) {
          // 0–.35 da vuelta · .35–.75 se luce · .75–1 baja a la mano.
          final giro = (1 - (t / .35).clamp(0.0, 1.0)) * math.pi;
          final salida = ((t - .75) / .25).clamp(0.0, 1.0);
          final boca = giro > math.pi / 2;
          return Opacity(
            opacity: 1 - salida,
            child: Transform.translate(
              offset: Offset(0, (haciaAbajo ? 1 : -1) * 160 * salida),
              child: Transform.scale(
                scale: 1 - .5 * salida,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final id in ids)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Transform(
                          alignment: Alignment.center,
                          transform:
                              Matrix4.identity()
                                ..setEntry(3, 2, .0015)
                                ..rotateY(giro),
                          child: Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(8),
                              boxShadow: [
                                BoxShadow(
                                  color: _gold.withValues(alpha: .7),
                                  blurRadius: 30,
                                  spreadRadius: 4,
                                ),
                              ],
                            ),
                            child:
                                boca
                                    ? ClipRRect(
                                      borderRadius: BorderRadius.circular(8),
                                      child: Image.asset(
                                        'assets/reves.jpg',
                                        width: ancho,
                                        height: ancho * 1.4,
                                        fit: BoxFit.cover,
                                      ),
                                    )
                                    : _Carta(
                                      id: id,
                                      nombre: nombres[id] ?? id,
                                      url: imagenes[id],
                                      ancho: ancho,
                                    ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Daño al Mazo Castillo: "−N" rojo que sube y se desvanece.
class _DanoFlotante extends StatelessWidget {
  final String dano;
  const _DanoFlotante({super.key, required this.dano});

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 1300),
      curve: Curves.easeOut,
      builder:
          (context, t, _) => Opacity(
            opacity: t < .7 ? 1 : (1 - (t - .7) / .3).clamp(0.0, 1.0),
            child: Transform.translate(
              offset: Offset(0, -90 * t),
              child: Transform.scale(
                scale:
                    .6 +
                    .8 * Curves.elasticOut.transform(t.clamp(0.0, .6) / .6),
                child: Text(
                  '−$dano',
                  style: const TextStyle(
                    color: Color(0xFFFF4D4D),
                    fontSize: 84,
                    fontWeight: FontWeight.w900,
                    shadows: [
                      Shadow(color: Colors.black, blurRadius: 12),
                      Shadow(color: Color(0xFFFF0000), blurRadius: 28),
                    ],
                  ),
                ),
              ),
            ),
          ),
    ),
  );
}

class _Carta extends StatelessWidget {
  final String id;
  final String nombre;
  final String? url;
  final double ancho;
  final int? fuerza;
  final List<String> armas;
  final bool pagado;

  const _Carta({
    required this.id,
    required this.nombre,
    required this.url,
    required this.ancho,
    this.fuerza,
    this.armas = const [],
    this.pagado = false,
  });

  @override
  Widget build(BuildContext context) {
    final alto = ancho * 1.4;
    final respaldo = Container(
      width: ancho,
      height: alto,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color:
            id == _oroInicial
                ? const Color(0xFF6B5320)
                : const Color(0xFF2B2B2B),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.white24),
      ),
      alignment: Alignment.center,
      child: Text(
        nombre,
        textAlign: TextAlign.center,
        maxLines: 4,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: Colors.white70,
          fontSize: (ancho / 7).clamp(6, 11),
        ),
      ),
    );
    final badge = (ancho / 6).clamp(7.0, 13.0);
    return Tooltip(
      message: [
        nombre,
        if (armas.isNotEmpty) 'Armas: ${armas.join(', ')}',
      ].join('\n'),
      child: Opacity(
        opacity: pagado ? .5 : 1,
        child: Container(
          width: ancho,
          height: alto,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(4),
            boxShadow: const [
              BoxShadow(
                color: Colors.black54,
                blurRadius: 4,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: Stack(
            children: [
              (url == null || url!.isEmpty)
                  ? respaldo
                  : MylCardImage(
                    url: url,
                    width: ancho,
                    height: alto,
                    fit: BoxFit.cover,
                    borderRadius: BorderRadius.circular(4),
                    fallback: respaldo,
                  ),
              if (fuerza != null)
                Positioned(
                  left: 1,
                  bottom: 1,
                  child: Container(
                    width: badge * 2,
                    height: badge * 2,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const RadialGradient(
                        colors: [Color(0xFF8E1B12), Color(0xFF3A0905)],
                      ),
                      border: Border.all(color: _gold, width: 1.2),
                    ),
                    child: Text(
                      '$fuerza',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: badge,
                      ),
                    ),
                  ),
                ),
              if (armas.isNotEmpty)
                Positioned(
                  right: 1,
                  top: 1,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    decoration: BoxDecoration(
                      color: Colors.black87,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '⚔${armas.length}',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: badge * .9,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

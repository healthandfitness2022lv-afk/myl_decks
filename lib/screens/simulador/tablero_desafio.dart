import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../models/card_myl.dart';
import '../../services/drive_service.dart';
import '../../widgets/card_image.dart';

const _boardGold = Color(0xFFF2D487);
const _boardSurface = Color(0xFF132126);
const _boardBackground = 'assets/wallpaper/2.jpg';

/// Confirma el pago antes de enviar la jugada. Cancelar deja el motor en la
/// misma decisión, sin mover la carta ni gastar Oros.
Future<dynamic> elegirAccionConOros(
  BuildContext context,
  Map opcion,
  Map<String, dynamic> decision,
) async {
  final cantidad = (opcion['cantidadPago'] as num?)?.toInt() ?? 0;
  final confirmarJugada = opcion['tipoJugada'] == 'jugar';
  if (cantidad == 0 && !confirmarJugada) return opcion['id'];
  final oros = (decision['oros'] as List? ?? const []).whereType<Map>().toList();
  final seleccion = <String>{};
  return showDialog<dynamic>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, actualizar) => Dialog(
        backgroundColor: _boardSurface,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 520,
            maxHeight: MediaQuery.sizeOf(context).height * .8,
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text('${opcion['titulo']}', maxLines: 2, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: _boardGold, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text(cantidad == 0
                  ? 'Esta jugada no requiere Oro.'
                  : 'Elige $cantidad Oro${cantidad == 1 ? '' : 's'} de tu reserva (${seleccion.length}/$cantidad).',
                  style: const TextStyle(color: Colors.white70)),
              if (cantidad > 0) Expanded(child: ListView.builder(
                itemCount: oros.length,
                itemBuilder: (_, i) {
                  final oro = oros[i];
                  final uid = '${oro['id']}';
                  return CheckboxListTile(
                    value: seleccion.contains(uid),
                    title: Text('${oro['nombre']}', style: const TextStyle(color: Colors.white)),
                    secondary: SizedBox(
                      width: 48, height: 66,
                      child: FittedBox(fit: BoxFit.contain, child: SizedBox(
                        width: 92, height: 128,
                        child: _CaraCarta(cartaId: '${oro['cartaId']}', nombre: '${oro['nombre']}'),
                      )),
                    ),
                    onChanged: (marcado) => actualizar(() {
                      if (marcado == true && seleccion.length < cantidad) {
                        seleccion.add(uid);
                      } else if (marcado != true) {
                        seleccion.remove(uid);
                      }
                    }),
                  );
                },
              )),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(child: OutlinedButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Cancelar'),
                )),
                const SizedBox(width: 8),
                Expanded(child: FilledButton(
                  onPressed: seleccion.length == cantidad
                      ? () => Navigator.pop(dialogContext, cantidad == 0
                          ? opcion['id']
                          : {'id': opcion['id'], 'oros': seleccion.toList()})
                      : null,
                  child: const Text('Confirmar jugada'),
                )),
              ]),
            ]),
          ),
        ),
      ),
    ),
  );
}

/// Mesa interactiva del desafío. Los gestos solo proponen una acción: el
/// worker sigue siendo quien valida su legalidad y aplica las reglas.
class TableroDesafio extends StatefulWidget {
  const TableroDesafio({
    super.key,
    required this.estado,
    required this.decision,
    required this.enviar,
  });
  final Map<String, dynamic> estado;
  final Map<String, dynamic>? decision;
  final Future<void> Function(dynamic valor) enviar;

  @override
  State<TableroDesafio> createState() => _TableroDesafioState();
}

/// Decisiones que se resuelven en la mesa (sin paneles): la barra de fase
/// dice qué hacer, se tocan las cartas resaltadas y se confirma en la barra.
const tiposEnMesa = {
  'jugada', 'atacantes', 'pago_oro', 'objetivos', 'descartes', 'portador',
  'mirar', 'bloqueos', 'confirmar', 'mano_inicial', 'avance_fase', 'anular',
  'responder', 'redirigir', 'raza', 'carta', 'opcion',
};

/// Se eligen tocando cartas (en la mesa o en la franja central).
const _tiposDeCartas = {
  'atacantes', 'pago_oro', 'objetivos', 'descartes', 'portador', 'mirar',
};

class _TableroDesafioState extends State<TableroDesafio> {
  String? _decisionId;
  String? _ataquePendiente;
  final Set<String> _seleccion = {};
  // Pago en la mesa: la jugada elegida y los Oros que se tocan para pagarla.
  Map? _pagoOpcion;
  final Set<String> _orosSel = {};
  // Bloqueos: atacante → bloqueador, y el bloqueador tocado esperando atacante.
  final Map<String, String> _bloqueos = {};
  String? _bloqueadorSel;
  bool _enviando = false;
  final ScrollController _franjaScroll = ScrollController();
  String _filtroNombre = '';

  static String _sinTildes(String s) => s.toLowerCase()
      .replaceAll(RegExp('[áà]'), 'a').replaceAll(RegExp('[éè]'), 'e')
      .replaceAll(RegExp('[íì]'), 'i').replaceAll(RegExp('[óò]'), 'o')
      .replaceAll(RegExp('[úùü]'), 'u');

  bool _coincideFiltro(String titulo) =>
      _d['escribir'] != true || _sinTildes(titulo).contains(_sinTildes(_filtroNombre.trim()));

  @override
  void dispose() {
    _franjaScroll.dispose();
    super.dispose();
  }

  Map<String, dynamic> get _d => widget.decision ?? const {};
  String get _tipo => _d['tipo'] as String? ?? '';
  List<Map> get _opciones =>
      (_d['opciones'] as List? ?? const []).whereType<Map>().toList();
  Set<String> get _idsOpciones => {for (final o in _opciones) '${o['id']}'};
  int? get _cantidad => (_d['cantidad'] as num?)?.toInt();
  List<Map> get _modos =>
      (_d['modos'] as List? ?? const []).whereType<Map>().toList();
  List<Map> get _orosPago =>
      (_d['oros'] as List? ?? const []).whereType<Map>().toList();
  int get _cantidadPago => (_pagoOpcion?['cantidadPago'] as num?)?.toInt() ?? 0;

  Future<void> _mandar(dynamic valor) async {
    if (_enviando) return;
    setState(() => _enviando = true);
    try {
      await widget.enviar(valor);
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  /// Ids de cartas que se ven en la mesa (lo demás va a la franja central).
  Set<String> _visibles() {
    final out = <String>{};
    for (final lado in (widget.estado['lados'] as List? ?? const []).whereType<Map>()) {
      for (final z in ['mano', 'reserva', 'pagado', 'defensa', 'ataque', 'apoyo']) {
        for (final c in (lado[z] as List? ?? const []).whereType<Map>()) {
          out.add('${c['id']}');
        }
      }
    }
    return out;
  }

  int? _modoDe(Iterable<String> ids) {
    for (var k = 0; k < _modos.length; k++) {
      final m = _modos[k];
      final validos = {for (final x in (m['ids'] as List? ?? const [])) '$x'};
      if (validos.containsAll(ids) && ids.length <= ((m['maximo'] as num?)?.toInt() ?? 0)) {
        return k;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    if (_decisionId != _d['id']) {
      _decisionId = _d['id'] as String?;
      _seleccion.clear();
      _filtroNombre = '';
      _pagoOpcion = null;
      _orosSel.clear();
      _bloqueos.clear();
      _bloqueadorSel = null;
      if (_tipo == 'atacantes' && _ataquePendiente != null) {
        if (_opciones.any((o) => '${o['id']}' == _ataquePendiente)) {
          _seleccion.add(_ataquePendiente!);
        }
        _ataquePendiente = null;
      }
    }
    final lados =
        (widget.estado['lados'] as List? ?? const []).whereType<Map>().toList();
    if (lados.length != 2) {
      return const Center(child: CircularProgressIndicator());
    }
    var yo = lados[0].cast<String, dynamic>();
    final rival = lados[1].cast<String, dynamic>();
    if (_tipo == 'atacantes' && _seleccion.isNotEmpty) {
      // Los que vas tocando pasan a tu Línea de Ataque (vista previa).
      final defensa = _cartas(yo, 'defensa');
      yo = {
        ...yo,
        'defensa': [for (final c in defensa) if (!_seleccion.contains('${c['id']}')) c],
        'ataque': [
          ..._cartas(yo, 'ataque'),
          for (final c in defensa) if (_seleccion.contains('${c['id']}')) c,
        ],
      };
    }
    return Stack(fit: StackFit.expand, children: [
      Image.asset(_boardBackground, fit: BoxFit.cover),
      const DecoratedBox(decoration: BoxDecoration(
        gradient: RadialGradient(radius: 1.2,
          colors: [Color(0xAA000000), Color(0xE6000000)]),
      )),
      LayoutBuilder(builder: (context, box) => _campo(rival, yo,
          horizontal: box.maxWidth > box.maxHeight)),
    ]);
  }

  Widget _resumen(Map<String, dynamic> lado, {required bool activo}) =>
    Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Color(0xE62A1F14), Color(0xE6120D08)]),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: activo ? _boardGold : _boardGold.withValues(alpha: .3),
          width: activo ? 2 : 1),
        boxShadow: activo ? [BoxShadow(color: _boardGold.withValues(alpha: .25), blurRadius: 14)] : null,
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('${lado['nombre']}', maxLines: 1, overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: _boardGold, fontSize: 17, fontWeight: FontWeight.w900)),
        const SizedBox(height: 5),
        Text('Castillo ${lado['castillo']}  ·  Mano ${lado['manoCantidad']}',
          maxLines: 1, overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
        Text('Cementerio ${lado['cementerio']}  ·  Destierro ${lado['destierro']}',
          maxLines: 1, overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Colors.white70, fontSize: 11)),
      ]),
    );

  Widget _campo(
    Map<String, dynamic> rival,
    Map<String, dynamic> yo, {
    required bool horizontal,
  }) {
    final ancho = horizontal ? 1600.0 : 900.0;
    final alto = horizontal ? 920.0 : 1440.0;
    Positioned poner(double x, double y, double w, double h, Widget child) =>
        Positioned(left: x, top: y, width: w, height: h, child: child);
    Widget zona(String titulo, Map<String, dynamic> lado, String clave,
            String destino, {int ocultas = 0}) =>
        _zona(titulo, _cartas(lado, clave), destino,
            horizontal: horizontal, ocultas: ocultas);
    return LayoutBuilder(builder: (context, limits) => Center(
      child: FittedBox(
        fit: BoxFit.contain,
        child: SizedBox(
          width: ancho,
          height: alto,
          child: Stack(children: horizontal ? [
            poner(12, 12, 250, 125, _resumen(rival, activo: widget.estado['activo'] == 1)),
            poner(12, 148, 250, 125, _pilas(rival)),
            poner(12, 647, 250, 125, _pilas(yo)),
            poner(12, 783, 250, 125, _resumen(yo, activo: widget.estado['activo'] == 0)),
            poner(274, 12, 1002, 124, zona('Mano rival · ${rival['manoCantidad']}', rival, 'mano', 'mano_rival',
                ocultas: (rival['manoCantidad'] as num?)?.toInt() ?? 0)),
            poner(274, 145, 750, 135, zona('Línea de Defensa rival', rival, 'defensa', 'defensa_rival')),
            poner(1034, 145, 242, 135, zona('Tótems', rival, 'apoyo', 'apoyo_rival')),
            poner(274, 290, 1002, 135, zona('Línea de Ataque rival', rival, 'ataque', 'ataque_rival')),
            poner(274, 432, 1002, 48, _divisor()),
            poner(274, 487, 1002, 135, zona('Tu Línea de Ataque', yo, 'ataque', 'ataque')),
            poner(274, 632, 750, 135, zona('Tu Defensa', yo, 'defensa', 'defensa')),
            poner(1034, 632, 242, 135, zona('Tótems', yo, 'apoyo', 'apoyo')),
            poner(274, 777, 1002, 132, zona('Tu mano', yo, 'mano', 'mano')),
            poner(1288, 12, 300, 155, zona('RESERVA RIVAL · ${_cartas(rival, 'reserva').length}${_virtuales(rival)}', rival, 'reserva', 'reserva_rival')),
            poner(1288, 177, 300, 115, zona('PAGADO RIVAL · ${_cartas(rival, 'pagado').length}', rival, 'pagado', 'pagado_rival')),
            poner(1288, 297, 300, 140, _fase()),
            poner(1288, 442, 300, 178, _registro()),
            poner(1288, 627, 300, 115, zona('PAGADO · ${_cartas(yo, 'pagado').length}', yo, 'pagado', 'pagado')),
            poner(1288, 752, 300, 155, zona('RESERVA · ${_cartas(yo, 'reserva').length}${_virtuales(yo)}', yo, 'reserva', 'reserva')),
            if (_franjaCartas().isNotEmpty || _franjaTextos().isNotEmpty)
              poner(274, 12, 1002, 412, _franja()),
          ] : [
            poner(10, 10, 230, 145, _resumen(rival, activo: widget.estado['activo'] == 1)),
            poner(250, 10, 230, 145, _pilas(rival)),
            poner(490, 10, 400, 70, zona('RESERVA RIVAL · ${_cartas(rival, 'reserva').length}${_virtuales(rival)}', rival, 'reserva', 'reserva_rival')),
            poner(490, 85, 400, 70, zona('PAGADO RIVAL · ${_cartas(rival, 'pagado').length}', rival, 'pagado', 'pagado_rival')),
            poner(10, 165, 880, 145, zona('Mano rival · ${rival['manoCantidad']}', rival, 'mano', 'mano_rival',
                ocultas: (rival['manoCantidad'] as num?)?.toInt() ?? 0)),
            poner(10, 320, 675, 140, zona('Línea de Defensa rival', rival, 'defensa', 'defensa_rival')),
            poner(695, 320, 195, 140, zona('Tótems', rival, 'apoyo', 'apoyo_rival')),
            poner(10, 470, 880, 160, zona('Línea de Ataque rival', rival, 'ataque', 'ataque_rival')),
            poner(10, 640, 880, 60, _divisor()),
            poner(10, 710, 880, 180, zona('Tu Línea de Ataque', yo, 'ataque', 'ataque')),
            poner(10, 900, 675, 140, zona('Tu Defensa', yo, 'defensa', 'defensa')),
            poner(695, 900, 195, 140, zona('Tótems', yo, 'apoyo', 'apoyo')),
            poner(10, 1050, 880, 145, zona('Tu mano', yo, 'mano', 'mano')),
            poner(10, 1205, 230, 225, _resumen(yo, activo: widget.estado['activo'] == 0)),
            poner(250, 1205, 230, 225, _pilas(yo)),
            poner(490, 1205, 400, 105, zona('PAGADO · ${_cartas(yo, 'pagado').length}', yo, 'pagado', 'pagado')),
            poner(490, 1320, 400, 110, zona('RESERVA · ${_cartas(yo, 'reserva').length}${_virtuales(yo)}', yo, 'reserva', 'reserva')),
            if (_franjaCartas().isNotEmpty || _franjaTextos().isNotEmpty)
              poner(10, 165, 880, 465, _franja()),
          ]),
        ),
      ),
    ));
  }

  Widget _fase() => Center(child: FittedBox(fit: BoxFit.scaleDown, child: AnimatedSwitcher(
    duration: const Duration(milliseconds: 350),
    transitionBuilder: (child, anim) => FadeTransition(opacity: anim,
      child: ScaleTransition(scale: anim, child: child)),
    child: Container(
      key: ValueKey('${widget.estado['turno']}-${widget.estado['fase']}'),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(color: const Color(0xE6120D08),
        borderRadius: BorderRadius.circular(18), border: Border.all(color: _boardGold)),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text('TURNO ${widget.estado['turno']} · FASE ${'${widget.estado['fase']}'.replaceAll('_', ' ').toUpperCase()}',
          textAlign: TextAlign.center, style: const TextStyle(color: _boardGold,
            fontWeight: FontWeight.w900, fontSize: 20)),
        Text(widget.estado['activo'] == 0 ? 'TU TURNO' : 'TURNO DEL RIVAL',
          textAlign: TextAlign.center, style: const TextStyle(color: Colors.white,
            fontWeight: FontWeight.bold, fontSize: 16)),
      ]),
    ),
  )));

  /// Las últimas jugadas (para leer lo que hizo la IA aunque encadene varias).
  Widget _registro() {
    final lineas = [
      for (final l in (widget.estado['log'] as List? ?? const []))
        if (!'$l'.contains('[agrupacion]'))
          '$l'.replaceFirst(RegExp(r'^T\d+ \[[^\]]*\] '), ''),
    ];
    final ultimas = lineas.length > 7 ? lineas.sublist(lineas.length - 7) : lineas;
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(color: const Color(0xCC0D0906),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _boardGold.withValues(alpha: .35))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('ÚLTIMAS JUGADAS', style: TextStyle(color: _boardGold,
          fontSize: 12, fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        Expanded(child: ClipRect(child: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final l in ultimas)
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Text(l, maxLines: 2, overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12,
                    color: l.startsWith('IA') ? const Color(0xFFFFB4A2) : Colors.white70)),
              ),
          ],
        ))),
      ]),
    );
  }

  Widget _divisor() => Stack(alignment: Alignment.center, children: [
    Container(height: 3, decoration: BoxDecoration(
      gradient: LinearGradient(colors: [
        _boardGold.withValues(alpha: 0), _boardGold,
        _boardGold.withValues(alpha: 0),
      ]),
      boxShadow: [BoxShadow(color: _boardGold.withValues(alpha: .6), blurRadius: 10)],
    )),
    if (widget.decision != null || _pagoOpcion != null) _controlFase(),
  ]);

  Widget _controlFase() {
    final fase = '${widget.estado['fase']}';
    final pasar = _opciones.where((o) => o['tipoJugada'] == 'pasar');
    Widget instruccion(String texto) => Flexible(
      child: Text(texto, maxLines: 1, overflow: TextOverflow.ellipsis,
        style: const TextStyle(color: Colors.white, fontSize: 14,
          fontWeight: FontWeight.w600)),
    );
    Widget boton(String texto, VoidCallback? accion, {bool principal = true}) =>
        Padding(
          padding: const EdgeInsets.only(left: 6),
          child: principal
              ? FilledButton(onPressed: _enviando ? null : accion, child: Text(texto))
              : OutlinedButton(onPressed: _enviando ? null : accion, child: Text(texto)),
        );
    final cantidad = _cantidad;
    final hijos = <Widget>[];
    if (_pagoOpcion != null) {
      final n = _cantidadPago;
      hijos.addAll([
        instruccion('${_pagoOpcion!['titulo']}: toca $n Oro${n == 1 ? '' : 's'} '
            'de tu reserva (${_orosSel.length}/$n)'),
        boton('Cancelar', () => setState(() {
          _pagoOpcion = null;
          _orosSel.clear();
        }), principal: false),
        boton('Confirmar', _orosSel.length == n
            ? () => _mandar({'id': _pagoOpcion!['id'], 'oros': _orosSel.toList()})
            : null),
      ]);
    } else {
      switch (_tipo) {
        case 'jugada':
          hijos.addAll([
            instruccion(fase == 'vigilia'
                ? 'Arrastra cartas para jugarlas · un Aliado a la Línea de Ataque para atacar'
                : 'Puedes usar cartas ahora o seguir'),
            if (_opciones.length > pasar.length)
              boton('Acciones ${_opciones.length - pasar.length}', _mostrarAcciones,
                  principal: false),
            boton(switch (fase) {
              'vigilia' => 'Batalla',
              'final' => 'Terminar turno',
              _ => 'Seguir',
            }, pasar.isEmpty ? null : () => _mandar('${pasar.first['id']}')),
          ]);
        case 'atacantes':
          hijos.addAll([
            instruccion('Toca o arrastra los Aliados que atacan'),
            boton(_seleccion.isEmpty ? 'Sin ataque' : 'Atacar con ${_seleccion.length}',
                () => _mandar(_seleccion.toList())),
          ]);
        case 'bloqueos':
          hijos.addAll([
            instruccion(_bloqueadorSel == null
                ? 'Toca tu Aliado y luego al atacante que bloquea'
                : 'Ahora toca al atacante que bloquea'),
            boton(_bloqueos.isEmpty ? 'Sin bloqueos' : 'Bloquear (${_bloqueos.length})',
                () => _mandar(Map<String, String>.from(_bloqueos))),
          ]);
        case 'mirar':
          final k = _modoDe(_seleccion);
          hijos.addAll([
            instruccion('${_d['titulo']}'
                '${k == null || _seleccion.isEmpty ? '' : ' · ${_modos[k]['titulo']}'}'),
            boton(_seleccion.isEmpty ? 'No tomar' : 'Tomar ${_seleccion.length}',
                k == null ? null : () => _mandar(_seleccion.toList())),
          ]);
        case 'objetivos' || 'descartes' || 'pago_oro' || 'portador':
          final n = _tipo == 'portador' ? 1 : cantidad;
          hijos.addAll([
            instruccion('${_d['titulo'] ?? 'Elige'}'
                '${n == null ? '' : ' (${_seleccion.length}/$n)'}'),
            boton('Confirmar', n != null && _seleccion.length != n
                ? null
                : () => _mandar(_tipo == 'portador'
                    ? _seleccion.first
                    : _seleccion.toList())),
          ]);
        case 'confirmar':
          hijos.addAll([
            instruccion('${_d['titulo']}'),
            boton('No', () => _mandar('no'), principal: false),
            boton('Sí', () => _mandar('si')),
          ]);
        case 'mano_inicial':
          hijos.addAll([
            instruccion('${_d['titulo']}'),
            boton('Mulligan', () => _mandar('mulligan'), principal: false),
            boton('Quedarme', () => _mandar('quedarse')),
          ]);
        case 'avance_fase':
          hijos.addAll([
            instruccion('${_d['titulo']}'),
            boton('Seguir', () => _mandar('continuar')),
          ]);
        case 'anular' || 'responder' || 'redirigir':
          hijos.addAll([
            instruccion('${_d['titulo']} · toca una opción'),
            boton('No usar', () => _mandar('pasar'), principal: false),
          ]);
        default:
          hijos.add(instruccion('${_d['titulo'] ?? 'Elige una opción'}'));
      }
    }
    return DecoratedBox(
      decoration: BoxDecoration(color: const Color(0xF21A120C),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _boardGold.withValues(alpha: .7))),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text('T${widget.estado['turno']} · ${fase.replaceAll('_', ' ').toUpperCase()}',
            style: const TextStyle(color: _boardGold, fontSize: 14,
              fontWeight: FontWeight.w800)),
          const SizedBox(width: 12),
          ...hijos,
        ]),
      ),
    );
  }

  /// Opciones de cartas que no están en la mesa (miradas del mazo, del
  /// Cementerio…): se muestran en la franja central para tocarlas.
  List<Map> _franjaCartas() {
    // Desafío AkOg: con muchos Oros no se veían en la Reserva. Al pagar, la
    // franja muestra todos los que se pueden usar para elegirlos.
    if (_pagoOpcion != null) return _orosPago;
    if (!_tiposDeCartas.contains(_tipo)) return const [];
    if (_tipo == 'pago_oro') return _opciones; // "Paga N Oros": todos a la vista
    if (_tipo == 'mirar') return _opciones; // se ven todas las miradas
    final visibles = _visibles();
    // Reportes kZYc/pyCo: la franja tapa la mesa rival. Si hace falta
    // (opciones fuera de la mesa), muestra todas: el Aliado y su Arma, el
    // Cementerio y la mesa, todo junto para elegir sin que nada quede oculto.
    if (_opciones.every((o) => visibles.contains('${o['id']}'))) return const [];
    return _opciones;
  }

  /// Opciones de texto (nombrar una carta o raza, responder con…).
  List<Map> _franjaTextos() {
    if (_pagoOpcion != null) return const [];
    if (!{'anular', 'responder', 'redirigir', 'raza', 'carta', 'opcion'}.contains(_tipo)) {
      return const [];
    }
    return _opciones;
  }

  Widget _franja() {
    final cartas = _franjaCartas();
    final textos = _franjaTextos();
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: const Color(0xEE0D0906),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _boardGold.withValues(alpha: .6))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(_pagoOpcion != null
            ? 'Paga $_cantidadPago Oro${_cantidadPago == 1 ? '' : 's'}: toca los que quieras usar (${_orosSel.length}/$_cantidadPago)'
            : '${_d['titulo'] ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: _boardGold, fontSize: 17,
            fontWeight: FontWeight.w800)),
        if (_tipo == 'mirar')
          Text(_modos.map((m) => m['titulo']).join('   ·   o   ·   '),
            maxLines: 1, overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white70, fontSize: 13)),
        const SizedBox(height: 8),
        // Reporte HIM0 (Sir Bedivere): nombrar escribiendo; la lista se filtra.
        if (textos.isNotEmpty && _d['escribir'] == true)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: TextField(
              autofocus: true,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                isDense: true,
                prefixIcon: Icon(Icons.search, color: Colors.white54),
                hintText: 'Escribe para filtrar…',
                hintStyle: TextStyle(color: Colors.white38),
              ),
              onChanged: (v) => setState(() => _filtroNombre = v),
            ),
          ),
        Expanded(child: textos.isNotEmpty
            ? SingleChildScrollView(child: Wrap(spacing: 8, runSpacing: 8, children: [
                for (final o in textos)
                  if (_coincideFiltro('${o['titulo'] ?? o['id']}'))
                    ActionChip(
                      label: Text('${o['titulo'] ?? o['id']}'),
                      onPressed: _enviando ? null : () => _elegirOpcionTexto(o),
                    ),
              ]))
            : LayoutBuilder(builder: (context, box) {
                // Reporte 4n5oe: con muchas (Aliados del mazo rival, el
                // Cementerio) no se veían todas y en la web no se podía
                // desplazar. Se busca el tamaño que las muestra todas.
                // Reporte qx6H (mazo rival entero): si no caben a un tamaño
                // legible, quedan de ese tamaño y la franja se desplaza en
                // vertical (la rueda del mouse sí la mueve en la web).
                const gap = 6.0;
                const altoMinimo = 120.0;
                var alto = box.maxHeight;
                for (var filas = 1; filas <= 8; filas++) {
                  final h = (box.maxHeight - gap * (filas - 1)) / filas;
                  final porFila = ((box.maxWidth + gap) / (h * 92 / 128 + gap)).floor();
                  alto = h;
                  if (porFila * filas >= cartas.length || h < altoMinimo) break;
                }
                if (alto < altoMinimo) alto = altoMinimo;
                final ancho = alto * 92 / 128;
                return Scrollbar(
                  controller: _franjaScroll,
                  thumbVisibility: true,
                  child: SingleChildScrollView(
                    controller: _franjaScroll,
                    child: Wrap(spacing: gap, runSpacing: gap, children: [
                      for (final c in cartas)
                        _carta(c, zona: 'franja', draggable: false, width: ancho, height: alto),
                    ]),
                  ),
                );
              })),
      ]),
    );
  }

  Future<void> _elegirOpcionTexto(Map o) async {
    final pago = (o['cantidadPago'] as num?)?.toInt() ?? 0;
    if (pago > 0) {
      _iniciarPago(o);
      return;
    }
    await _mandar('${o['id']}');
  }

  /// Jugar una carta: sin costo se manda de inmediato; con costo, los Oros
  /// de la reserva se resaltan (ya marcados los primeros) y se confirma en
  /// la barra.
  Future<void> _iniciarJugada(Map opcion) async {
    final n = (opcion['cantidadPago'] as num?)?.toInt() ?? 0;
    if (n == 0) {
      await _mandar('${opcion['id']}');
      return;
    }
    _iniciarPago(opcion);
  }

  void _iniciarPago(Map opcion) {
    final n = (opcion['cantidadPago'] as num?)?.toInt() ?? 0;
    setState(() {
      _pagoOpcion = opcion;
      _orosSel
        ..clear()
        ..addAll(_orosPago.take(n).map((o) => '${o['id']}'));
    });
  }

  /// Oros virtuales (Dragones): « + 2 virtuales» junto a la Reserva.
  String _virtuales(Map<String, dynamic> lado) {
    final v = (lado['orosVirtuales'] as num?)?.toInt() ?? 0;
    if (v <= 0) return '';
    final detalle = (lado['orosVirtualesDetalle'] as List? ?? const []).join(', ');
    return ' + $v virtual${v == 1 ? '' : 'es'}${detalle.isEmpty ? '' : ' ($detalle)'}';
  }

  List<Map> _cartas(Map<String, dynamic> lado, String zona) =>
      (lado[zona] as List? ?? const []).whereType<Map>().toList();

  bool _puedeSoltar(String uid, String destino) {
    if (_pagoOpcion != null) return false;
    if (_tipo == 'pago_oro') {
      return destino == 'pagado' && _opciones.any((x) => '${x['id']}' == uid);
    }
    if (_tipo == 'atacantes') {
      return destino == 'ataque' && _opciones.any((x) => '${x['id']}' == uid);
    }
    if (_tipo == 'jugada' && destino != 'mano' && _talismanDe(uid) != null) {
      return true; // Bola de Energía: se juega soltándola en la mesa
    }
    if (_tipo == 'jugada' && destino == 'ataque' &&
        widget.estado['fase'] == 'vigilia') {
      final lados = (widget.estado['lados'] as List? ?? const []);
      final yo = lados.isEmpty ? null : lados.first;
      final defensa = yo is Map ? (yo['defensa'] as List? ?? const []) : const [];
      return defensa.whereType<Map>().any((c) =>
          '${c['id']}' == uid && c['puedeAtacar'] == true) &&
          _opciones.any((o) => o['tipoJugada'] == 'pasar');
    }
    if (_tipo != 'jugada') return false;
    for (final o in _opciones) {
      if ('${o['cartaUid']}' != uid) continue;
      if (destino == 'reserva' && o['tipoJugada'] == 'oro') return true;
      if (destino == 'defensa' &&
          (o['cartaTipo'] == 'Aliado' || o['cartaTipo'] == 'Arma')) {
        return true;
      }
      if (destino == 'apoyo' && o['cartaTipo'] == 'Tótem') return true;
    }
    return false;
  }

  Map? _talismanDe(String uid) => _opciones.cast<Map?>().firstWhere(
    (o) => '${o?['cartaUid']}' == uid && o?['cartaTipo'] == 'Talismán' &&
        o?['tipoJugada'] != 'activar',
    orElse: () => null);

  Future<void> _soltar(String uid, String destino) async {
    if (_tipo == 'pago_oro') {
      setState(() => _seleccion.add(uid));
      return;
    }
    if (_tipo == 'atacantes') {
      setState(() => _seleccion.add(uid));
      return;
    }
    final talisman = _tipo == 'jugada' ? _talismanDe(uid) : null;
    if (talisman != null) {
      await _elegirAccion(talisman);
      return;
    }
    if (destino == 'ataque' && _puedeSoltar(uid, destino)) {
      final pasar = _opciones.firstWhere((o) => o['tipoJugada'] == 'pasar');
      _ataquePendiente = uid;
      await _elegirAccion(pasar);
      return;
    }
    final opcion = _opciones.cast<Map?>().firstWhere(
      (o) =>
          o?['cartaUid'] == uid &&
          ((destino == 'reserva' && o?['tipoJugada'] == 'oro') ||
              (destino == 'defensa' && o?['cartaTipo'] == 'Aliado') ||
              (destino == 'apoyo' && o?['cartaTipo'] == 'Tótem')),
      orElse: () => null,
    );
    if (opcion != null) {
      await _elegirAccion(opcion);
      return;
    }
    if (destino == 'defensa') {
      final armas =
          _opciones
              .where(
                (o) => '${o['cartaUid']}' == uid && o['cartaTipo'] == 'Arma',
              )
              .toList();
      if (armas.isNotEmpty && mounted) {
        final elegido = await showDialog<Map>(
          context: context,
          builder:
              (context) => SimpleDialog(
                title: const Text('¿A qué Aliado equipar el Arma?'),
                children: [
                  for (final arma in armas)
                    SimpleDialogOption(
                      onPressed: () => Navigator.pop(context, arma),
                      child: Text('${arma['titulo']}'),
                    ),
                ],
              ),
        );
        if (elegido != null) await _elegirAccion(elegido);
      }
    }
  }

  Widget _pilas(Map<String, dynamic> lado) => Container(
    padding: const EdgeInsets.all(5),
    decoration: BoxDecoration(color: const Color(0x99120D08),
      borderRadius: BorderRadius.circular(10)),
    child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
      Expanded(child: _pila('Destierro', _cartas(lado, 'destierroCartas'),
          (lado['destierro'] as num?)?.toInt() ?? 0)),
      Expanded(child: _pila('Cementerio', _cartas(lado, 'cementerioCartas'),
          (lado['cementerio'] as num?)?.toInt() ?? 0)),
      Expanded(child: _pila('Castillo',
          lado['topeCastillo'] is Map ? [lado['topeCastillo'] as Map] : const [],
          (lado['castillo'] as num?)?.toInt() ?? 0,
          castillo: lado['topeCastillo'] is! Map)),
    ]),
  );

  Widget _pila(String titulo, List<Map> cartas, int cantidad,
      {bool castillo = false}) {
    final tope = cartas.isEmpty ? null : cartas.last;
    return InkWell(
      onTap: castillo ? null : () => _verPila(titulo, cartas),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Stack(alignment: Alignment.center, children: [
          SizedBox(width: 64, height: 88, child: ClipRRect(
            borderRadius: BorderRadius.circular(5),
            child: castillo
                ? Image.asset('assets/reves.jpg', fit: BoxFit.cover)
                : tope == null
                    ? Container(color: Colors.black45,
                        child: const Icon(Icons.layers_outlined, color: Colors.white38))
                    : _CaraCarta(cartaId: '${tope['cartaId']}',
                        nombre: '${tope['nombre']}', width: 64, height: 88),
          )),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(color: Colors.black87,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _boardGold)),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 260),
              child: Text('$cantidad', key: ValueKey('$titulo-$cantidad'),
                style: const TextStyle(color: Colors.white,
                  fontSize: 16, fontWeight: FontWeight.w900)),
            ),
          ),
        ]),
        const SizedBox(height: 3),
        Text(titulo, maxLines: 1, overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Colors.white,
            fontSize: 10, fontWeight: FontWeight.bold)),
      ]),
    );
  }

  Future<void> _verPila(String titulo, List<Map> cartas) => showDialog<void>(
    context: context,
    builder: (dialogContext) => Dialog(
      backgroundColor: _boardSurface,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 650,
          maxHeight: MediaQuery.sizeOf(dialogContext).height * .8),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(children: [
            Row(children: [
              Expanded(child: Text('$titulo · ${cartas.length} cartas',
                style: const TextStyle(color: _boardGold,
                  fontSize: 18, fontWeight: FontWeight.bold))),
              IconButton(onPressed: () => Navigator.pop(dialogContext),
                icon: const Icon(Icons.close, color: Colors.white)),
            ]),
            Expanded(child: cartas.isEmpty
                ? const Center(child: Text('Pila vacía',
                    style: TextStyle(color: Colors.white70)))
                : GridView.builder(
                    itemCount: cartas.length,
                    gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 120, childAspectRatio: .7,
                      mainAxisSpacing: 8, crossAxisSpacing: 8),
                    itemBuilder: (context, i) {
                      final carta = cartas[cartas.length - 1 - i];
                      return GestureDetector(
                        onTap: () => _ampliar(carta),
                        child: _CaraCarta(cartaId: '${carta['cartaId']}',
                          nombre: '${carta['nombre']}', width: 100, height: 140),
                      );
                    },
                  )),
          ]),
        ),
      ),
    ),
  );

  Widget _zona(String titulo, List<Map> cartas, String destino,
      {required bool horizontal, int ocultas = 0}) =>
      DragTarget<String>(
        onWillAcceptWithDetails: (d) => _puedeSoltar(d.data, destino),
        onAcceptWithDetails: (d) => _soltar(d.data, destino),
        builder:
            (context, candidatos, __) => Container(
              width: double.infinity,
              height: double.infinity,
              padding: const EdgeInsets.fromLTRB(5, 2, 5, 3),
              decoration: BoxDecoration(
                color: candidatos.isNotEmpty
                    ? const Color(0x6655D6FF)
                    : (destino.contains('reserva') || destino.contains('pagado'))
                        ? Colors.black.withValues(alpha: .45)
                        : Colors.transparent,
                border: (destino.contains('reserva') || destino.contains('pagado') || candidatos.isNotEmpty)
                    ? Border.all(color: candidatos.isNotEmpty
                        ? const Color(0xFF55D6FF) : _boardGold.withValues(alpha: .3))
                    : null,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    titulo,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: destino.contains('reserva') || destino.contains('pagado')
                          ? _boardGold : Colors.white70,
                      fontSize: 13, fontWeight: FontWeight.w700, height: 1.1,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Expanded(child: LayoutBuilder(builder: (context, box) {
                    final total = destino == 'mano_rival' ? ocultas : cartas.length;
                    if (total == 0) {
                      return const Center(child: Text('—',
                          style: TextStyle(color: Colors.white30, fontSize: 20)));
                    }
                    final alto = box.maxHeight;
                    // Héctor: cartas más grandes (títulos más chicos, sin tope bajo).
                    final cartaAlto = alto.clamp(40.0, horizontal ? 150.0 : 180.0);
                    final cartaAncho = cartaAlto * 92 / 128;
                    final paso = total <= 1 ? 0.0 :
                        ((box.maxWidth - cartaAncho) / (total - 1)).clamp(1.0, cartaAncho + 5);
                    return Stack(clipBehavior: Clip.none, children: [
                      for (var i = 0; i < total; i++)
                        Positioned(
                          left: i * paso,
                          top: 0,
                          width: cartaAncho,
                          height: cartaAlto,
                          child: Transform.rotate(
                            angle: destino.contains('mano') && total > 1
                                ? (i - (total - 1) / 2) * .035 : 0,
                            alignment: Alignment.bottomCenter,
                            child: destino == 'mano_rival'
                              ? _dorso()
                              : _carta(cartas[i],
                                  zona: destino,
                                  width: cartaAncho, height: cartaAlto,
                                  draggable: destino == 'mano' || destino == 'defensa' || destino == 'reserva'),
                          ),
                        ),
                    ]);
                  })),
                ],
              ),
            ),
      );

  Widget _dorso() => ClipRRect(
    borderRadius: BorderRadius.circular(6),
    child: Image.asset('assets/reves.jpg', fit: BoxFit.cover),
  );

  /// Qué se puede hacer con esta carta ahora (para resaltarla y rotularla).
  String? _rotulo(Map c, String zona) {
    final uid = '${c['id']}';
    if (_pagoOpcion != null) {
      return _orosPago.any((o) => '${o['id']}' == uid) ? 'PAGAR' : null;
    }
    if (_tiposDeCartas.contains(_tipo)) {
      if (!_idsOpciones.contains(uid)) return null;
      return switch (_tipo) {
        'atacantes' => 'ATACA',
        'descartes' => 'DESCARTAR',
        'pago_oro' => 'PAGAR',
        'portador' => 'PORTADOR',
        'mirar' => 'TOMAR',
        _ => 'ELEGIR',
      };
    }
    if (_tipo == 'bloqueos') {
      final asignado = _bloqueos[uid];
      if (asignado != null) return 'BLOQUEADO';
      if (_opciones.any((o) => '${(o['atacante'] as Map?)?['id']}' == uid)) return 'ATACANTE';
      if (_bloqueadores().contains(uid)) return 'BLOQUEAR';
      return null;
    }
    if ({'anular', 'responder'}.contains(_tipo)) {
      return _opciones.any((o) => '${o['cartaUid']}' == uid) ? 'USAR' : null;
    }
    if (_tipo == 'jugada') {
      final acciones = _opciones.where((o) => '${o['cartaUid']}' == uid).toList();
      if (acciones.isNotEmpty) {
        return switch ('${acciones.first['tipoJugada']}') {
          'activar' => 'ACTIVAR',
          'oro' => 'BAJAR ORO',
          _ => 'JUGAR',
        };
      }
      if (zona == 'defensa' && widget.estado['fase'] == 'vigilia' &&
          c['puedeAtacar'] == true) {
        return 'ATACAR';
      }
    }
    return null;
  }

  bool _marcada(String uid) =>
      _seleccion.contains(uid) || _orosSel.contains(uid) ||
      _bloqueadorSel == uid || _bloqueos.containsKey(uid) ||
      _bloqueos.containsValue(uid);

  Set<String> _bloqueadores() => {
    for (final o in _opciones)
      for (final b in (o['bloqueadores'] as List? ?? const []).whereType<Map>())
        '${b['id']}',
  };

  Widget _carta(Map c, {required String zona, required bool draggable,
      required double width, required double height}) {
    final uid = '${c['id']}';
    final rotulo = _rotulo(c, zona);
    final marcada = _marcada(uid);
    // En bloqueos, el atacante muestra quién lo bloquea.
    final bloqueador = _bloqueos[uid];
    final nombreBloqueador = bloqueador == null ? null : _nombreCarta(bloqueador);
    final armas = (c['armas'] as List? ?? const []).whereType<Map>().toList();
    final base = AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      width: width,
      height: height,
      transform: marcada
          ? Matrix4.translationValues(0, zona.contains('mano') ? -14 : -6, 0)
          : Matrix4.identity(),
      decoration: BoxDecoration(
        color: marcada ? const Color(0xFF66531F) : const Color(0xFF263238),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: marcada
              ? const Color(0xFF55D6FF)
              : rotulo != null ? _boardGold : Colors.white24,
          width: marcada || rotulo != null ? 3 : 1,
        ),
        boxShadow: marcada
            ? [const BoxShadow(color: Color(0x9955D6FF), blurRadius: 12)]
            : null,
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: _CaraCarta(
              cartaId: '${c['cartaId']}',
              nombre: '${c['nombre']}',
              width: width,
              height: height,
            ),
          ),
          if (rotulo != null)
            Positioned(
              top: 2, right: 2,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 2),
                color: const Color(0xDD1A120C),
                child: Text(marcada && rotulo != 'BLOQUEADO' ? '✓ $rotulo' : rotulo,
                  style: const TextStyle(color: _boardGold, fontSize: 10,
                    fontWeight: FontWeight.bold)),
              ),
            ),
          if (armas.isNotEmpty)
            Positioned(
              right: 2, bottom: 2,
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                for (final a in armas.take(2))
                  GestureDetector(
                    // Si el Arma es una opción (destruirla, desterrarla), se elige.
                    onTap: () => _idsOpciones.contains('${a['id']}') &&
                            _tiposDeCartas.contains(_tipo)
                        ? _tocarCarta(a, zona)
                        : _ampliar(a),
                    onLongPress: () => _ampliar(a),
                    child: Container(
                      margin: const EdgeInsets.only(left: 2),
                      width: width * .36,
                      height: width * .36 * 128 / 92,
                      decoration: BoxDecoration(
                        border: Border.all(
                            color: _seleccion.contains('${a['id']}')
                                ? const Color(0xFF55D6FF)
                                : _boardGold,
                            width: _seleccion.contains('${a['id']}') ? 3 : 1.5),
                        borderRadius: BorderRadius.circular(3),
                        boxShadow: const [BoxShadow(color: Colors.black, blurRadius: 4)],
                      ),
                      child: _CaraCarta(cartaId: '${a['cartaId']}', nombre: '${a['nombre']}',
                          width: width * .36, height: width * .36 * 128 / 92),
                    ),
                  ),
              ]),
            ),
          if (nombreBloqueador != null)
            Positioned(
              left: 2, right: 2, bottom: 26,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 2),
                color: const Color(0xDD0D3B4A),
                child: Text('⛨ $nombreBloqueador', maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 10,
                    fontWeight: FontWeight.bold)),
              ),
            ),
          if (c['fuerza'] != null)
            Positioned(
              left: 3,
              bottom: 3,
              child: CircleAvatar(
                radius: 12,
                backgroundColor: const Color(0xFF7F1D1D),
                child: Text(
                  '${c['fuerza']}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
    final carta = GestureDetector(
      onTap: () => _tocarCarta(c, zona),
      onDoubleTap: kIsWeb ? () => _ampliar(c) : null,
      onSecondaryTap: () => _ampliar(c),
      onLongPress: draggable ? null : () => _ampliar(c),
      child: _Realce(child: base), // reporte JD4r: la carta se destaca bajo el cursor
    );
    // En la web se arrastra con el mouse al instante; en el teléfono,
    // manteniendo apretado (si se suelta sin moverla, se amplía).
    var movido = 0.0;
    final feedback = Material(
      color: Colors.transparent,
      child: SizedBox(width: width, height: height, child: carta),
    );
    final interactiva = !draggable
        ? carta
        : kIsWeb
            ? Draggable<String>(
                data: uid,
                feedback: feedback,
                childWhenDragging: Opacity(opacity: .35, child: carta),
                child: carta,
              )
            : LongPressDraggable<String>(
                data: uid,
                delay: const Duration(milliseconds: 350),
                feedback: feedback,
                onDragStarted: () => movido = 0,
                onDragUpdate: (d) => movido += d.delta.distance,
                onDraggableCanceled: (_, __) {
                  if (movido < 12) _ampliar(c);
                },
                childWhenDragging: Opacity(opacity: .35, child: carta),
                child: carta,
              );
    return TweenAnimationBuilder<double>(
      key: ValueKey('$zona-$uid'),
      tween: Tween(begin: .82, end: 1),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
      builder: (context, scale, child) => Opacity(
        opacity: scale,
        child: Transform.translate(
          offset: Offset(0, (1 - scale) * (zona.contains('rival') ? -45 : 45)),
          child: Transform.scale(scale: scale, child: child),
        ),
      ),
      child: interactiva,
    );
  }

  String? _nombreCarta(String uid) {
    for (final lado in (widget.estado['lados'] as List? ?? const []).whereType<Map>()) {
      for (final z in ['defensa', 'ataque', 'apoyo']) {
        for (final c in (lado[z] as List? ?? const []).whereType<Map>()) {
          if ('${c['id']}' == uid) return '${c['nombre']}';
        }
      }
    }
    return null;
  }

  Future<void> _tocarCarta(Map carta, String zona) async {
    final uid = '${carta['id']}';
    if (_enviando) return;
    // 1. Pagando: se tocan los Oros de la reserva.
    if (_pagoOpcion != null) {
      if (!_orosPago.any((o) => '${o['id']}' == uid)) return;
      setState(() {
        if (_orosSel.contains(uid)) {
          _orosSel.remove(uid);
        } else if (_orosSel.length < _cantidadPago) {
          _orosSel.add(uid);
        }
      });
      return;
    }
    // 2. Elegir cartas (objetivos, descartes, atacantes, mirar…).
    if (_tiposDeCartas.contains(_tipo)) {
      if (!_idsOpciones.contains(uid)) return;
      setState(() {
        if (_seleccion.contains(uid)) {
          _seleccion.remove(uid);
          return;
        }
        final n = _tipo == 'portador' ? 1 : _cantidad;
        if (_tipo == 'mirar') {
          // Solo cartas de un mismo modo: si no calza, se empieza de nuevo.
          if (_modoDe({..._seleccion, uid}) == null) _seleccion.clear();
        } else if (n == 1) {
          _seleccion.clear();
        } else if (n != null && _seleccion.length >= n) {
          return;
        }
        _seleccion.add(uid);
      });
      return;
    }
    // 3. Bloqueos: tu Aliado y luego el atacante (tocar de nuevo deshace).
    if (_tipo == 'bloqueos') {
      final atacante = _opciones.cast<Map?>().firstWhere(
        (o) => '${(o?['atacante'] as Map?)?['id']}' == uid, orElse: () => null);
      setState(() {
        if (atacante != null) {
          final permitidos = {
            for (final b in (atacante['bloqueadores'] as List? ?? const []).whereType<Map>())
              '${b['id']}',
          };
          if (_bloqueadorSel != null && permitidos.contains(_bloqueadorSel)) {
            _bloqueos.removeWhere((_, b) => b == _bloqueadorSel);
            _bloqueos[uid] = _bloqueadorSel!;
            _bloqueadorSel = null;
          } else {
            _bloqueos.remove(uid);
          }
        } else if (_bloqueadores().contains(uid)) {
          if (_bloqueos.containsValue(uid)) {
            _bloqueos.removeWhere((_, b) => b == uid);
          } else {
            _bloqueadorSel = _bloqueadorSel == uid ? null : uid;
          }
        }
      });
      return;
    }
    // 4. Anular / responder con una carta de la mesa.
    if ({'anular', 'responder'}.contains(_tipo)) {
      final o = _opciones.cast<Map?>().firstWhere(
        (o) => '${o?['cartaUid']}' == uid, orElse: () => null);
      if (o != null) await _elegirOpcionTexto(o);
      return;
    }
    if (_tipo != 'jugada') return;
    final acciones = _opciones.where((o) => '${o['cartaUid']}' == uid).toList();
    if (acciones.isEmpty) {
      // Reporte FeCs: tocar un Aliado no lo manda al ataque; se arrastra a la
      // Línea de Ataque (tocarlo solo lo amplía).
      final motivos = (_d['motivos'] as Map?) ?? const {};
      await _ampliar(carta, motivo: motivos[uid] as String?);
      return;
    }
    if (acciones.length == 1) {
      await _iniciarJugada(acciones.first);
      return;
    }
    final elegida = await showModalBottomSheet<Map>(
      context: context,
      backgroundColor: _boardSurface,
      builder: (context) => SafeArea(child: ListView(
        shrinkWrap: true,
        children: [
          const ListTile(title: Text('Elige una acción', style: TextStyle(color: _boardGold))),
          for (final a in acciones) ListTile(
            title: Text('${a['titulo']}', style: const TextStyle(color: Colors.white)),
            onTap: () => Navigator.pop(context, a),
          ),
        ],
      )),
    );
    if (elegida != null) await _iniciarJugada(elegida);
  }

  /// Carta ampliada (con su habilidad legible en la imagen), su fuerza
  /// actual, las Armas que porta y, si no se puede usar ahora, por qué.
  Future<void> _ampliar(Map c, {String? motivo}) => showDialog<void>(
    context: context,
    builder: (dialogContext) {
      final armas = (c['armas'] as List? ?? const []).whereType<Map>().toList();
      final alto = (MediaQuery.sizeOf(dialogContext).height * .72).clamp(240.0, 640.0);
      return GestureDetector(
        onTap: () => Navigator.pop(dialogContext),
        child: Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(12),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Row(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.end, children: [
              _CaraCarta(cartaId: '${c['cartaId']}', nombre: '${c['nombre']}',
                  width: alto * 92 / 128, height: alto, ancho: 800),
              for (final a in armas)
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: _CaraCarta(cartaId: '${a['cartaId']}', nombre: '${a['nombre']}',
                      width: alto * .55 * 92 / 128, height: alto * .55, ancho: 800),
                ),
            ]),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(color: const Color(0xEE0D0906),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _boardGold.withValues(alpha: .6))),
              child: Text(
                [
                  '${c['nombre']}',
                  if (c['fuerza'] != null) 'fuerza ${c['fuerza']}',
                  if (armas.isNotEmpty) 'porta ${armas.map((a) => a['nombre']).join(', ')}',
                ].join(' · ') + (motivo == null ? '' : '\n$motivo'),
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 14),
              ),
            ),
          ]),
        ),
      );
    },
  );

  Future<void> _elegirAccion(Map opcion) => _iniciarJugada(opcion);

  Future<void> _mostrarAcciones() async {
    final acciones = _opciones.where((o) => o['tipoJugada'] != 'pasar').toList();
    if (acciones.isEmpty) return;
    final elegida = await showModalBottomSheet<Map>(
      context: context,
      backgroundColor: _boardSurface,
      builder: (context) => SafeArea(child: ListView(
        shrinkWrap: true,
        children: [
          const ListTile(title: Text('Acciones disponibles', style: TextStyle(color: _boardGold))),
          for (final a in acciones) ListTile(
            title: Text('${a['titulo']}', style: const TextStyle(color: Colors.white)),
            onTap: () => Navigator.pop(context, a),
          ),
        ],
      )),
    );
    if (elegida != null) await _elegirAccion(elegida);
  }

}

/// Con el mouse encima, la carta crece un poco y se eleva (web y escritorio).
class _Realce extends StatefulWidget {
  const _Realce({required this.child});

  final Widget child;

  @override
  State<_Realce> createState() => _RealceState();
}

class _RealceState extends State<_Realce> {
  bool _encima = false;

  @override
  Widget build(BuildContext context) => MouseRegion(
    onEnter: (_) => setState(() => _encima = true),
    onExit: (_) => setState(() => _encima = false),
    child: AnimatedScale(
      scale: _encima ? 1.12 : 1,
      duration: const Duration(milliseconds: 140),
      curve: Curves.easeOut,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          boxShadow: _encima
              ? const [BoxShadow(color: Color(0xAA000000), blurRadius: 14, offset: Offset(0, 6))]
              : const [],
        ),
        child: widget.child,
      ),
    ),
  );
}

class _CaraCarta extends StatelessWidget {
  const _CaraCarta({required this.cartaId, required this.nombre,
    this.width = 92, this.height = 128, this.ancho = 320});
  final int ancho;
  final String cartaId;
  final String nombre;
  final double width;
  final double height;

  static final Map<String, Future<String?>> _cache = {};

  /// URLs que manda el servidor al empezar el desafío: ninguna carta tiene
  /// que consultarse a Firestore durante la partida.
  static void sembrar(Map<String, String> urls) {
    urls.forEach((id, url) {
      if (url.trim().isNotEmpty) _cache[id] = Future.value(url.trim());
    });
  }

  /// Las direcciones a probar, en orden (web: CDN de Google, proxy, original).
  static List<String> direcciones(String raw, int ancho) => [
    DriveService.webSafeUrl(raw, ancho: ancho),
    DriveService.proxyWeserv(raw, ancho: ancho),
    if (!kIsWeb) raw,
  ];

  Future<String?> _imagen() => _cache.putIfAbsent(cartaId, () async {
    if (cartaId.isEmpty || cartaId.startsWith('__')) return null;
    try {
      final ref = FirebaseFirestore.instance.collection('cards').doc(cartaId);
      final doc = await ref.get();
      if (!doc.exists) return null;
      final d = doc.data() ?? {};
      var raw =
          (d['officialImageUrl'] as String?) ??
          (d['imageUrl'] as String?) ??
          CardMyL.fromMap(d, doc.id).bestVariant?.imageFrontUrl;
      if (raw == null || raw.trim().isEmpty) {
        var variantes = await ref.collection('variants')
            .where('official', isEqualTo: true).limit(1).get();
        if (variantes.docs.isEmpty) {
          variantes = await ref.collection('variants').limit(1).get();
        }
        raw = variantes.docs.isEmpty
            ? null
            : variantes.docs.first.data()['imageFrontUrl'] as String?;
      }
      return raw == null || raw.trim().isEmpty
          ? null
          : raw.trim();
    } catch (_) {
      // Un corte de red no deja la carta sin imagen para siempre.
      _cache.remove(cartaId);
      return null;
    }
  });

  Widget _nombre() => Container(
    color: const Color(0xFF263238),
    padding: const EdgeInsets.all(5),
    alignment: Alignment.center,
    child: Text(
      nombre,
      textAlign: TextAlign.center,
      maxLines: 5,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(color: Colors.white, fontSize: 11),
    ),
  );

  @override
  Widget build(BuildContext context) => FutureBuilder<String?>(
    future: _imagen(),
    builder: (context, snap) {
      final raw = snap.data;
      if (raw == null) return _nombre();
      return _ImagenRobusta(
        key: ValueKey('$cartaId-$ancho'),
        urls: direcciones(raw, ancho),
        width: width,
        height: height,
        mientras: _nombre(),
      );
    },
  );
}

/// Antes de mostrar la mesa: deja las URLs listas y descarga todas las
/// imágenes de los dos mazos (con la dirección de respaldo si la primera
/// falla). `progreso(hechas, total)` para la barra de carga.
Future<void> precargarImagenesDesafio(BuildContext context, Map<String, String> urls,
    void Function(int hechas, int total) progreso) async {
  _CaraCarta.sembrar(urls);
  final lista = urls.values.where((u) => u.trim().isNotEmpty).toSet().toList();
  var hechas = 0;
  Future<void> una(String raw) async {
    for (final url in _CaraCarta.direcciones(raw, 320)) {
      var ok = true;
      // NetworkImage (otro proveedor que el de la carta): calienta la caché
      // del navegador sin compartir la imagen decodificada con el tablero
      // (compartirla en la web dejaba las cartas en negro).
      await precacheImage(NetworkImage(url), context, onError: (_, __) => ok = false);
      if (ok) break;
    }
    hechas++;
    progreso(hechas, lista.length);
  }
  // De a 6 a la vez: rápido sin saturar la red.
  for (var i = 0; i < lista.length; i += 6) {
    if (!context.mounted) return;
    await Future.wait(lista.skip(i).take(6).map(una));
  }
}

/// Reporte del 14-11: a veces la carta quedaba solo con el nombre. Prueba
/// cada dirección; si fallan todas, espera y vuelve a intentar (sin caché de
/// error), hasta 6 rondas. Mientras tanto muestra el nombre.
class _ImagenRobusta extends StatefulWidget {
  const _ImagenRobusta({super.key, required this.urls, required this.width,
    required this.height, required this.mientras});

  final List<String> urls;
  final double width;
  final double height;
  final Widget mientras;

  @override
  State<_ImagenRobusta> createState() => _ImagenRobustaState();
}

class _ImagenRobustaState extends State<_ImagenRobusta> {
  int _intento = 0; // ronda * direcciones + dirección
  bool _cargada = false;
  Timer? _timer;
  Timer? _plazo;

  int get _maximo => widget.urls.length * 5;
  String get _url => widget.urls[_intento % widget.urls.length];

  @override
  void dispose() {
    _timer?.cancel();
    _plazo?.cancel();
    super.dispose();
  }

  /// Falló (o no llegó a tiempo): la siguiente dirección; al terminar una
  /// ronda, espera 1 s, 2 s, 4 s… antes de volver a empezar.
  void _siguiente() {
    _plazo?.cancel();
    if (!mounted || _cargada || _timer != null || _intento + 1 >= _maximo) return;
    final siguiente = _intento + 1;
    final ronda = siguiente ~/ widget.urls.length;
    final espera = siguiente % widget.urls.length == 0
        ? Duration(seconds: 1 << ronda.clamp(0, 4))
        : Duration.zero;
    _timer = Timer(espera, () {
      _timer = null;
      if (mounted) setState(() => _intento = siguiente);
    });
  }

  void _vigilar() {
    // Una descarga colgada (cartas en negro): a los 6 s se vuelve a pedir.
    _plazo?.cancel();
    _plazo = Timer(const Duration(seconds: 6), () {
      if (mounted && !_cargada) _siguiente();
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!kIsWeb) {
      // Teléfono: el componente de siempre, con caché en disco.
      return MylCardImage(
        url: _url, width: widget.width, height: widget.height,
        borderRadius: BorderRadius.circular(5),
        fallback: Builder(builder: (_) {
          WidgetsBinding.instance.addPostFrameCallback((_) => _siguiente());
          return widget.mientras;
        }),
      );
    }
    // Web: el cargador estándar (caché del navegador, el mismo de la precarga).
    if (!_cargada) _vigilar();
    return ClipRRect(
      borderRadius: BorderRadius.circular(5),
      child: Image.network(
        _url,
        key: ValueKey('$_url#$_intento'),
        width: widget.width,
        height: widget.height,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        frameBuilder: (_, child, frame, __) {
          if (frame == null) return widget.mientras; // cargando: el nombre, nunca negro
          if (!_cargada) {
            _cargada = true;
            _plazo?.cancel();
          }
          return child;
        },
        errorBuilder: (_, __, ___) {
          WidgetsBinding.instance.addPostFrameCallback((_) => _siguiente());
          return widget.mientras;
        },
      ),
    );
  }
}

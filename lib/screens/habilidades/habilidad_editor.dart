// lib/screens/habilidades/habilidad_editor.dart
//
// Editor de una habilidad parametrizada. Los campos visibles dependen de la
// acción elegida (ver Accion en card_habilidad.dart).

import 'package:flutter/material.dart';

import '../../models/card_habilidad.dart';
import '../../domain/catalogo_acciones.dart';
import 'luego_editor.dart';

const _bg = Color(0xFF132126);
const _field = Color(0xFF1B3036);
const _gold = Color(0xFFF2D487);

Future<CardHabilidad?> showHabilidadEditor(
  BuildContext context, {
  required List<AccionDef> features,
  CardHabilidad? inicial,
  String textoCarta = '',
  String tipoCarta = '',
}) {
  return showModalBottomSheet<CardHabilidad>(
    context: context,
    isScrollControlled: true,
    backgroundColor: _bg,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
    ),
    builder:
        (_) => _HabilidadEditor(
          features: features,
          inicial: inicial,
          textoCarta: textoCarta,
          tipoCarta: tipoCarta,
        ),
  );
}

class _HabilidadEditor extends StatefulWidget {
  final List<AccionDef> features;
  final CardHabilidad? inicial;
  final String textoCarta;
  final String tipoCarta;

  const _HabilidadEditor({
    required this.features,
    required this.inicial,
    required this.textoCarta,
    required this.tipoCarta,
  });

  @override
  State<_HabilidadEditor> createState() => _HabilidadEditorState();
}

class _HabilidadEditorState extends State<_HabilidadEditor> {
  late CardHabilidad? _h = _sanear(widget.inicial);

  bool get _esTalisman => widget.tipoCarta.toLowerCase().startsWith('talism');

  /// Quita de una habilidad ya guardada lo que no corresponde a su tipo de
  /// carta (p. ej. un Talismán con costo "destruir esta carta").
  CardHabilidad? _sanear(CardHabilidad? h) {
    if (h == null || !_esTalisman) return h;
    return h.copyWith(
      costo: h.costo.copyWith(
        destruirEstaCarta: false,
        desterrarEstaCarta: false,
        pagarEstaCarta: false,
      ),
    );
  }

  /// Casilla "Solo bajo ciertas condiciones": despliega condición y turno.
  late bool _conCondicion =
      widget.inicial != null &&
      (!widget.inicial!.condicion.esNinguna ||
          widget.inicial!.turno != 'cualquiera');

  void _cambiarConCondicion(bool v) => setState(() {
    _conCondicion = v;
    if (!v && _h != null) {
      _h = _h!.copyWith(
        condicion: const CondicionHabilidad(),
        turno: _h!.accion.esPropiedad ? 'cualquiera' : null,
      );
    }
  });

  /// Turno + condición, detrás de la casilla.
  List<Widget> _bloqueCondicion(CardHabilidad h, {required bool conTurno}) => [
    _check(
      'Solo bajo ciertas condiciones',
      _conCondicion,
      _cambiarConCondicion,
    ),
    if (_conCondicion) ...[
      if (conTurno) ...[
        _drop(
          kTurno,
          h.turno,
          (v) => _set((h) => h.copyWith(turno: v)),
          label: '¿En qué turno?',
        ),
        const SizedBox(height: 8),
      ],
      _drop(
        kCondiciones,
        h.condicion.tipo,
        (v) => _set(
          (h) => h.copyWith(
            condicion: _cond(
              h.condicion,
              tipo: v,
              valor: v == 'oros_vs_oponente' ? 0 : null,
            ),
          ),
        ),
        label: 'Condición',
      ),
      if (h.condicion.tipo == 'oros_vs_oponente') ...[
        const SizedBox(height: 8),
        _drop(
          kOrosVsOponente,
          h.condicion.op,
          (v) => _set(
            (h) => h.copyWith(condicion: _cond(h.condicion, op: v, valor: 0)),
          ),
          label: '¿Cuándo?',
        ),
      ] else if (!h.condicion.esNinguna) ...[
        const SizedBox(height: 8),
        Row(
          children: [
            SizedBox(
              width: 90,
              child: _drop(
                kOperadores,
                h.condicion.op,
                (v) => _set(
                  (h) => h.copyWith(condicion: _cond(h.condicion, op: v)),
                ),
              ),
            ),
            const SizedBox(width: 8),
            _num(
              h.condicion.valor,
              (v) => _set(
                (h) => h.copyWith(condicion: _cond(h.condicion, valor: v)),
              ),
            ),
            if (const {
              'aliados_raza',
              'aliados_no_raza',
              'mano_raza',
            }.contains(h.condicion.tipo)) ...[
              const SizedBox(width: 8),
              Expanded(
                child: _text(
                  h.condicion.raza,
                  'Raza',
                  (v) => _set(
                    (h) => h.copyWith(condicion: _cond(h.condicion, raza: v)),
                  ),
                ),
              ),
            ],
            if (const {
              'aliados_arquetipo',
              'mano_arquetipo',
              'atacantes_arquetipo',
            }.contains(h.condicion.tipo)) ...[
              const SizedBox(width: 8),
              Expanded(
                child: _text(
                  h.condicion.arquetipo,
                  'Arquetipo (Druida, Goblin…)',
                  (v) => _set(
                    (h) =>
                        h.copyWith(condicion: _cond(h.condicion, arquetipo: v)),
                  ),
                ),
              ),
            ],
          ],
        ),
      ],
    ],
  ];

  void _elegirFeature(AccionDef f) {
    setState(() {
      final base =
          _h ??
          CardHabilidad(featureId: f.id, featureName: f.name, accion: f.accion);
      final cambiaAccion = base.accion != f.accion || _h == null;
      _h = base.copyWith(
        // Si la acción no cambia se conserva el nombre que ya tenía.
        featureId: cambiaAccion ? f.id : base.featureId,
        featureName: cambiaAccion ? f.name : base.featureName,
        accion: f.accion,
        modo: cambiaAccion ? (kModos[f.accion]?.first.id ?? '') : base.modo,
        cuando: _preguntasDe(f.accion).pasiva ? 'continua' : null,
        duracion:
            cambiaAccion && f.accion == Accion.ganarControl
                ? 'hasta_fase_final'
                : null,
        objetivo: _objetivoInicial(f.accion, base.objetivo, cambiaAccion),
      );
    });
  }

  /// Objetivo por defecto según la acción y el tipo de carta.
  ObjetivoHabilidad _objetivoInicial(
    Accion accion,
    ObjetivoHabilidad actual,
    bool cambiaAccion,
  ) {
    final tipo = widget.tipoCarta.toLowerCase();
    if (accion.esPropiedad) {
      return tipo == 'arma'
          ? ObjetivoHabilidad(quien: aplicaPorDefecto(accion))
          : const ObjetivoHabilidad();
    }
    if (!accion.usaObjetivoCartas) {
      return ObjetivoHabilidad(
        quien:
            const {Accion.botar, Accion.descartar}.contains(accion)
                ? 'oponente'
                : 'propio',
      );
    }
    if (accion == Accion.requisitoPortador && cambiaAccion) {
      return const ObjetivoHabilidad(quien: 'propio');
    }
    final validos = quienPara(
      widget.tipoCarta,
      accion,
      cuando: _h?.cuando ?? '',
    ).map((o) => o.id);
    final conQuien =
        validos.contains(actual.quien)
            ? actual
            : actual.copyWith(quien: 'oponente');
    final zonas = _zonasEfectivas(accion, conQuien);
    return conQuien.copyWith(
      zona: zonas.first,
      zonas: zonas.length > 1 ? zonas : const [],
      tipos: conQuien.tipos.where(tiposPara(accion, zonas).contains).toList(),
    );
  }

  /// Zonas guardadas que son válidas para la acción; si ninguna lo es (p. ej.
  /// "en juego" al pasar a Buscar), la primera válida.
  List<String> _zonasEfectivas(Accion accion, ObjetivoHabilidad o) {
    final validas = _preguntasDe(accion).zonas?.map((z) => z.id).toList();
    if (validas == null) return o.todasLasZonas;
    final efectivas = o.todasLasZonas.where(validas.contains).toList();
    return efectivas.isEmpty ? [validas.first] : efectivas;
  }

  void _set(CardHabilidad Function(CardHabilidad h) f) =>
      setState(() => _h = f(_h!));

  @override
  Widget build(BuildContext context) {
    final h = _h;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: .9,
        maxChildSize: .95,
        builder:
            (context, scroll) => ListView(
              controller: scroll,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.inicial == null
                            ? 'Nueva habilidad'
                            : 'Editar habilidad',
                        style: const TextStyle(
                          color: _gold,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close, color: Colors.white70),
                    ),
                  ],
                ),
                if (widget.textoCarta.isNotEmpty)
                  Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.black26,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      widget.textoCarta,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontStyle: FontStyle.italic,
                        fontSize: 13,
                      ),
                    ),
                  ),
                _label('Acción'),
                // Solo las que tienen sentido para este tipo de carta.
                _FeaturePicker(
                  features:
                      widget.features
                          .where(
                            (f) => accionPermitida(f.accion, widget.tipoCarta),
                          )
                          .toList(),
                  selectedId: h == null ? null : idDeAccion(h.accion),
                  onPick: _elegirFeature,
                ),
                if (h != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Acción del simulador: ${h.accion.label}. ${h.accion.descripcion}',
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                  if (h.accion.esPropiedad) ...[
                    const Padding(
                      padding: EdgeInsets.only(top: 12, bottom: 4),
                      child: Text(
                        'Es una propiedad de la carta: siempre activa, salvo que '
                        'la limites a ciertas condiciones.',
                        style: TextStyle(color: Colors.white70),
                      ),
                    ),
                    if (widget.tipoCarta.toLowerCase() == 'arma') ...[
                      _drop(
                        kAplicaArma,
                        const {
                              'esta_carta',
                              'el_arma',
                            }.contains(h.objetivo.quien)
                            ? h.objetivo.quien
                            : aplicaPorDefecto(h.accion),
                        (v) => _set(
                          (h) => h.copyWith(
                            objetivo: h.objetivo.copyWith(quien: v),
                          ),
                        ),
                        label: '¿A quién aplica?',
                      ),
                      const SizedBox(height: 8),
                    ],
                    ..._bloqueCondicion(h, conTurno: true),
                    if (_conCondicion)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          h.resumen,
                          style: const TextStyle(color: _gold, fontSize: 13),
                        ),
                      ),
                  ] else ...[
                    ..._parametros(h),
                    LuegoSection(
                      tipoCarta: widget.tipoCarta,
                      efectos: h.luego,
                      onChanged: (v) => _set((h) => h.copyWith(luego: v)),
                    ),
                  ],
                  const SizedBox(height: 8),
                  const Text(
                    'Si algo de la carta no se puede expresar aquí, déjalo en '
                    '"Notas para el simulador" de la carta.',
                    style: TextStyle(color: Colors.white38, fontSize: 12),
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: _gold,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    onPressed: () => Navigator.pop(context, h),
                    icon: const Icon(Icons.check),
                    label: const Text('Guardar habilidad'),
                  ),
                ],
              ],
            ),
      ),
    );
  }

  List<Widget> _parametros(CardHabilidad h) {
    final q = _preguntasDe(h.accion);
    final o = h.objetivo;
    final modos = kModos[h.accion];
    // Pasiva: siempre activa mientras la carta esté donde corresponde; no
    // tiene fase, costo, ni es opcional.
    final pasiva = q.pasiva || h.cuando == 'continua';
    final zonasActivacion = _zonasActivacionPara(widget.tipoCarta);
    final usaZonaActivacion =
        zonasActivacion.length > 1 &&
        const {'activada', 'continua', 'al_inicio_fase'}.contains(h.cuando);
    return [
      _section('Cuándo'),
      if (q.pasiva)
        const Text(
          'Siempre activa mientras la carta esté en juego.',
          style: TextStyle(color: Colors.white70),
        )
      else
        _drop(
          cuandoPara(widget.tipoCarta),
          h.cuando,
          (v) => _set((h) => h.copyWith(cuando: v)),
        ),
      const SizedBox(height: 8),
      Row(
        children: [
          if (!pasiva) ...[
            Expanded(
              child: _drop(
                kFases,
                h.fase,
                (v) => _set((h) => h.copyWith(fase: v)),
                label: 'Fase',
              ),
            ),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: _drop(
              kTurno,
              h.turno,
              (v) => _set((h) => h.copyWith(turno: v)),
              label: 'Turno',
            ),
          ),
        ],
      ),
      if (h.cuando == 'oponente_juega') ...[
        const SizedBox(height: 8),
        const Text(
          '¿Qué tipo de carta juega el oponente? (vacío = cualquiera)',
          style: TextStyle(color: Colors.white54, fontSize: 12),
        ),
        _tipos(
          h.disparoTipos,
          (t) => _set((h) => h.copyWith(disparoTipos: t)),
          permitidos: const ['Aliado', 'Arma', 'Talismán', 'Tótem', 'Oro'],
        ),
      ],
      if (h.cuando == 'propia_entra' || h.cuando == 'propia_sale') ...[
        const SizedBox(height: 8),
        const Text(
          '¿Qué tipo de carta tuya? (vacío = cualquiera; no cuenta esta misma)',
          style: TextStyle(color: Colors.white54, fontSize: 12),
        ),
        _tipos(
          h.disparoTipos,
          (t) => _set(
            (h) => h.copyWith(
              disparoTipos: t,
              disparoRaza: t.isEmpty || _esSoloAliado(t) ? null : '',
            ),
          ),
          permitidos: const ['Aliado', 'Arma', 'Tótem', 'Oro'],
        ),
        if (h.disparoTipos.isEmpty || _esSoloAliado(h.disparoTipos))
          _text(
            h.disparoRaza,
            'Raza de ese Aliado (opcional)',
            (v) => _set((h) => h.copyWith(disparoRaza: v)),
          ),
        _numLabeled(
          'Coste mínimo de esa carta (0 = cualquiera)',
          h.disparoCosteMin,
          (v) => _set((h) => h.copyWith(disparoCosteMin: v)),
        ),
      ],
      if (h.cuando == 'activada') ...[
        const SizedBox(height: 8),
        _drop(
          kUsaQuien,
          h.usaQuien,
          (v) => _set((h) => h.copyWith(usaQuien: v)),
          label: '¿Quién puede usarla?',
        ),
      ],
      if (usaZonaActivacion) ...[
        const SizedBox(height: 8),
        _drop(
          zonasActivacion,
          h.zonaActivacion,
          (v) => _set((h) => h.copyWith(zonaActivacion: v)),
          label:
              h.accion == Accion.restriccion
                  ? 'Funciona mientras esta carta está'
                  : 'Se usa con esta carta',
        ),
      ],
      _section('Condición'),
      ..._bloqueCondicion(h, conTurno: false),
      if (!pasiva) ...[
        _section('Costo'),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          children: [
            _numLabeled(
              'Oros',
              h.costo.oros,
              (v) => _set((h) => h.copyWith(costo: h.costo.copyWith(oros: v))),
            ),
            _numLabeled(
              'Descartar',
              h.costo.descartar,
              (v) => _set(
                (h) => h.copyWith(costo: h.costo.copyWith(descartar: v)),
              ),
            ),
            _numLabeled(
              'Botar',
              h.costo.botar,
              (v) => _set((h) => h.copyWith(costo: h.costo.copyWith(botar: v))),
            ),
          ],
        ),
        // Un Talismán no está en juego: no se destruye ni se destierra
        // como costo.
        if (costoPermitido('destruirEstaCarta', widget.tipoCarta))
          _check(
            'Destruir esta carta como costo',
            h.costo.destruirEstaCarta,
            (v) => _set(
              (h) => h.copyWith(costo: h.costo.copyWith(destruirEstaCarta: v)),
            ),
          ),
        if (costoPermitido('pagarEstaCarta', widget.tipoCarta))
          _check(
            'Pagar este Oro (pasa de la Reserva a Oro Pagado)',
            h.costo.pagarEstaCarta,
            (v) => _set(
              (h) => h.copyWith(
                costo: h.costo.copyWith(pagarEstaCarta: v),
                // Pagar el Oro es una acción del jugador desde la Reserva.
                cuando: v ? 'activada' : null,
                zonaActivacion: v ? 'reserva_oro' : null,
              ),
            ),
          ),
        if (costoPermitido('fondoMazoEstaCarta', widget.tipoCarta))
          _check(
            'Poner esta carta al fondo de tu Mazo como costo',
            h.costo.fondoMazoEstaCarta,
            (v) => _set(
              (h) => h.copyWith(costo: h.costo.copyWith(fondoMazoEstaCarta: v)),
            ),
          ),
        if (costoPermitido('desterrarEstaCarta', widget.tipoCarta))
          _check(
            'Desterrar esta carta como costo',
            h.costo.desterrarEstaCarta,
            (v) => _set(
              (h) => h.copyWith(costo: h.costo.copyWith(desterrarEstaCarta: v)),
            ),
          ),
        if (costoPermitido('barajarEstaCarta', widget.tipoCarta))
          _check(
            'Barajar esta carta en tu Mazo como costo',
            h.costo.barajarEstaCarta,
            (v) => _set(
              (h) => h.copyWith(costo: h.costo.copyWith(barajarEstaCarta: v)),
            ),
          ),
        if (costoPermitido('moverEstaCartaAtaque', widget.tipoCarta))
          _check(
            'Mover este Aliado de Defensa a Ataque como costo',
            h.costo.moverEstaCartaAtaque,
            (v) => _set(
              (h) =>
                  h.copyWith(costo: h.costo.copyWith(moverEstaCartaAtaque: v)),
            ),
          ),
        _check(
          'Pagar tantos Oros como el coste del objetivo',
          h.costo.orosSegun == 'coste_objetivo',
          (v) => _set(
            (h) => h.copyWith(
              costo: h.costo.copyWith(orosSegun: v ? 'coste_objetivo' : 'fijo'),
            ),
          ),
        ),
        _check(
          'Desterrar de tu Cementerio tantas como el coste del objetivo',
          h.costo.desterrarCementerioSegun == 'coste_objetivo',
          (v) => _set(
            (h) => h.copyWith(
              costo: h.costo.copyWith(
                desterrarCementerioSegun: v ? 'coste_objetivo' : 'fijo',
              ),
            ),
          ),
        ),
        if (h.costo.desterrarCementerioSegun != 'coste_objetivo')
          _numLabeled(
            'Desterrar N de tu Cementerio',
            h.costo.desterrarCementerio,
            (v) => _set(
              (h) =>
                  h.copyWith(costo: h.costo.copyWith(desterrarCementerio: v)),
            ),
          ),
        Wrap(
          spacing: 12,
          children: [
            _numLabeled(
              'Desterrar N de tus otros Aliados',
              h.costo.desterrarAliados,
              (v) => _set(
                (h) => h.copyWith(costo: h.costo.copyWith(desterrarAliados: v)),
              ),
            ),
            _numLabeled(
              'Destruir N de tus otros Aliados',
              h.costo.destruirAliados,
              (v) => _set(
                (h) => h.copyWith(costo: h.costo.copyWith(destruirAliados: v)),
              ),
            ),
            _numLabeled(
              'Barajar N de tu mano',
              h.costo.barajarMano,
              (v) => _set(
                (h) => h.copyWith(costo: h.costo.copyWith(barajarMano: v)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        const Text(
          'O en su lugar (costo alternativo, opcional):',
          style: TextStyle(color: Colors.white54, fontSize: 12),
        ),
        Wrap(
          spacing: 12,
          children: [
            _numLabeled(
              'Oros',
              h.costoAlternativo.oros,
              (v) => _set(
                (h) => h.copyWith(
                  costoAlternativo: h.costoAlternativo.copyWith(oros: v),
                ),
              ),
            ),
            _numLabeled(
              'Botar',
              h.costoAlternativo.botar,
              (v) => _set(
                (h) => h.copyWith(
                  costoAlternativo: h.costoAlternativo.copyWith(botar: v),
                ),
              ),
            ),
            _numLabeled(
              'Descartar',
              h.costoAlternativo.descartar,
              (v) => _set(
                (h) => h.copyWith(
                  costoAlternativo: h.costoAlternativo.copyWith(descartar: v),
                ),
              ),
            ),
          ],
        ),
      ],

      if (_esTalisman) ...[
        const SizedBox(height: 8),
        _drop(
          _zonas(['cementerio', 'destierro']),
          h.talismanVaA,
          (v) => _set((h) => h.copyWith(talismanVaA: v)),
          label: 'Después de resolverse, este Talismán va a',
        ),
      ],

      // ── Preguntas propias de la acción ──────────────────────────────────
      _section(q.titulo),
      if (modos != null) ...[
        _drop(
          modos,
          h.modo.isEmpty ? modos.first.id : h.modo,
          (v) => _set((h) => h.copyWith(modo: v)),
          label: q.modoLabel,
        ),
        const SizedBox(height: 8),
      ],
      if (h.accion.usaModoFuerza) ...[
        _drop(
          kModoFuerza,
          h.modoFuerza,
          (v) => _set((h) => h.copyWith(modoFuerza: v)),
          label: '¿Cómo cambia la fuerza?',
        ),
        const SizedBox(height: 8),
      ],
      if (q.jugador)
        _drop(
          h.accion == Accion.agrupar
              ? const [
                Opcion('esta_carta', 'Solo esta carta (este Oro)'),
                ...kJugadorObjetivo,
              ]
              : kJugadorObjetivo,
          o.quien,
          (v) => _set((h) => h.copyWith(objetivo: o.copyWith(quien: v))),
          label: q.quienLabel,
        ),
      if (_usaCartas(h, q)) ..._preguntasCartas(h, q),
      if (q.valorLabel != null && _usaValor(h)) ...[
        const SizedBox(height: 8),
        _numLabeled(
          q.valorLabel!,
          h.valor,
          (v) => _set((h) => h.copyWith(valor: v)),
          min: -20,
        ),
        if (h.accion == Accion.modificarFuerza || h.accion == Accion.generarOro)
          _drop(
            kPorCada,
            h.valorPorCada,
            (v) => _set((h) => h.copyWith(valorPorCada: v)),
            label: '¿Por cada…?',
          ),
        if (h.valorPorCada == 'aliado_arquetipo')
          _text(
            h.porCadaArquetipo,
            'Arquetipo que se cuenta (Druida, Goblin…)',
            (v) => _set((h) => h.copyWith(porCadaArquetipo: v)),
          ),
      ],
      if (q.cantidadLabel != null && o.seleccion != 'todos') ...[
        const SizedBox(height: 8),
        _drop(
          kCantidadSegun,
          h.cantidadSegun,
          (v) => _set((h) => h.copyWith(cantidadSegun: v)),
          label: q.cantidadLabel,
        ),
        if (h.cantidadSegun == 'fijo')
          _numLabeled(
            'Cantidad',
            h.cantidad,
            (v) => _set((h) => h.copyWith(cantidad: v)),
          ),
      ],
      if (q.destino) ...[
        const SizedBox(height: 8),
        _drop(
          q.destinos ?? kDestinos,
          h.zonaDestino,
          (v) => _set((h) => h.copyWith(zonaDestino: v)),
          label: q.destinoLabel,
        ),
      ],
      if (h.accion == Accion.mirarTope) ...[
        const SizedBox(height: 8),
        _drop(
          kRestoA,
          h.restoA,
          (v) => _set((h) => h.copyWith(restoA: v)),
          label: '¿Y las que no toma?',
        ),
        const SizedBox(height: 8),
        const Text(
          'O repartir una a cada zona, en este orden (La Odisea):',
          style: TextStyle(color: Colors.white54, fontSize: 12),
        ),
        Wrap(
          spacing: 6,
          children: [
            for (final z in kRepartir)
              FilterChip(
                label: Text(
                  h.repartir.contains(z.id)
                      ? '${h.repartir.indexOf(z.id) + 1}. ${z.label}'
                      : z.label,
                ),
                selected: h.repartir.contains(z.id),
                onSelected:
                    (v) => _set(
                      (h) => h.copyWith(
                        repartir:
                            v
                                ? [...h.repartir, z.id]
                                : h.repartir.where((x) => x != z.id).toList(),
                      ),
                    ),
              ),
          ],
        ),
      ],
      if (h.accion == Accion.cambiarRaza)
        _text(
          h.razaNueva,
          'Raza que pasan a tener',
          (v) => _set((h) => h.copyWith(razaNueva: v)),
        ),
      if (q.soloPara) ...[
        const SizedBox(height: 10),
        const Text(
          'Solo para pagar (vacío = cualquier carta):',
          style: TextStyle(color: Colors.white54, fontSize: 12),
        ),
        _tipos(
          h.soloParaTipos,
          (t) => _set(
            (h) => h.copyWith(
              soloParaTipos: t,
              soloParaRaza: t.isEmpty || _esSoloAliado(t) ? null : '',
            ),
          ),
        ),
        if (h.soloParaTipos.isEmpty || _esSoloAliado(h.soloParaTipos))
          _text(
            h.soloParaRaza,
            'Raza de los Aliados (opcional)',
            (v) => _set((h) => h.copyWith(soloParaRaza: v)),
          ),
        _numLabeled(
          'Coste mínimo de lo que pagan (0 = cualquiera)',
          h.soloParaCosteMin,
          (v) => _set((h) => h.copyWith(soloParaCosteMin: v)),
        ),
      ],
      // Una habilidad continua dura mientras la carta esté en juego.
      if (q.duraciones != null && h.cuando != 'continua') ...[
        const SizedBox(height: 8),
        _drop(
          q.duraciones!,
          h.duracion,
          (v) => _set((h) => h.copyWith(duracion: v)),
          label: '¿Hasta cuándo?',
        ),
      ],
      if (!pasiva)
        Row(
          children: [
            Expanded(
              child: _check(
                'Opcional ("puedes")',
                h.opcional,
                (v) => _set((h) => h.copyWith(opcional: v)),
              ),
            ),
            _numLabeled(
              'Límite/turno (0 = sin)',
              h.limitePorTurno,
              (v) => _set((h) => h.copyWith(limitePorTurno: v)),
            ),
          ],
        ),
      if (!pasiva)
        _text(
          h.grupoElegir,
          'Elige una sola de las opciones con este mismo grupo (opcional)',
          (v) => _set((h) => h.copyWith(grupoElegir: v)),
        ),
      if (h.accion == Accion.barajar)
        _check(
          'Mientras esté en juego, el oponente no puede jugar la carta '
          'barajada',
          h.vetaCarta,
          (v) => _set((h) => h.copyWith(vetaCarta: v)),
        ),
      if (!pasiva && h.limitePorTurno > 0)
        _text(
          h.grupoLimite,
          'Comparte el límite con (mismo nombre de grupo en otra habilidad)',
          (v) => _set((h) => h.copyWith(grupoLimite: v)),
        ),
      if (!pasiva && h.limitePorTurno > 0)
        _check(
          'El límite cuenta para todas sus copias',
          h.limitePorNombre,
          (v) => _set((h) => h.copyWith(limitePorNombre: v)),
        ),
      const SizedBox(height: 10),
      Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: _gold.withValues(alpha: .08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: _gold.withValues(alpha: .3)),
        ),
        child: Text(
          h.resumen,
          style: const TextStyle(color: _gold, fontSize: 13),
        ),
      ),
    ];
  }

  bool _usaCartas(CardHabilidad h, _Preguntas q) {
    if (!q.cartas) return false;
    if (h.accion == Accion.reducirDano) return h.modo == 'aliado_sin_dano';
    if (h.accion == Accion.restriccion) return h.modo == 'jugar_tipo';
    return true;
  }

  bool _usaValor(CardHabilidad h) => switch (h.accion) {
    Accion.modificarFuerza => const {'sumar', 'fijar'}.contains(h.modoFuerza),
    Accion.reducirDano => h.modo == 'reducir_en_n',
    _ => true,
  };

  /// ¿Qué cartas? ¿De quién? ¿Dónde? ¿Con qué limitaciones? ¿Cuántas?
  List<Widget> _preguntasCartas(CardHabilidad h, _Preguntas q) {
    final o = h.objetivo;
    final base = quienPara(widget.tipoCarta, h.accion, cuando: h.cuando);
    final quienes =
        q.permiteEstaCarta
            ? base
            : base.where((x) => x.id != 'esta_carta').toList();
    return [
      if (!q.jugador)
        _drop(
          quienes,
          o.quien,
          (v) => _set((h) => h.copyWith(objetivo: o.copyWith(quien: v))),
          label: q.quienLabel,
        ),
      // Jinetes de Fuego / Qer-Her: "esta carta" se juega desde otra zona; hay
      // que decir desde cuál (antes la pregunta quedaba escondida).
      if (h.accion == Accion.jugarDesde && o.quien == 'esta_carta') ...[
        const SizedBox(height: 8),
        const Text(
          '¿Desde qué zona se puede jugar? (puedes marcar varias)',
          style: TextStyle(color: Colors.white54, fontSize: 12),
        ),
        Wrap(
          spacing: 6,
          children: [
            for (final (id, label) in const [
              ('cementerio', 'Cementerio'),
              ('mazo', 'Mazo Castillo'),
              ('destierro', 'Destierro'),
            ])
              FilterChip(
                label: Text(label),
                selected: _zonasEfectivas(h.accion, o).contains(id),
                onSelected: (sel) {
                  final actuales = [
                    for (final z in _zonasEfectivas(h.accion, o))
                      if (z != 'mano' && z != 'en_juego') z,
                  ];
                  if (sel) {
                    actuales.add(id);
                  } else if (actuales.length > 1) {
                    actuales.remove(id);
                  }
                  if (actuales.isEmpty) return;
                  _set(
                    (h) => h.copyWith(
                      objetivo: o.copyWith(
                        zona: actuales.first,
                        zonas: actuales.length > 1 ? actuales : const [],
                      ),
                    ),
                  );
                },
              ),
          ],
        ),
      ],
      if (q.jugador || o.quien != 'esta_carta') ...[
        const SizedBox(height: 8),
        if (q.tipos) ...[
          _tipos(
            permitidos: tiposPara(h.accion, _zonasEfectivas(h.accion, o)),
            o.tipos,
            (t) => _set(
              (h) => h.copyWith(
                // Al cambiar los tipos se borran los filtros que dejan de
                // corresponder (raza/fuerza solo Aliados; coste no en Oros).
                objetivo: _limpiarFiltros(o.copyWith(tipos: t), q),
              ),
            ),
          ),
          const Text(
            'Sin tipos marcados = cualquier tipo de carta.',
            style: TextStyle(color: Colors.white38, fontSize: 11),
          ),
          const SizedBox(height: 8),
        ],
        if (q.zonas != null) ...[
          Text(
            '${q.zonaLabel} (puedes marcar varias)',
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
          Wrap(
            spacing: 6,
            children: [
              for (final z in q.zonas!)
                FilterChip(
                  label: Text(z.label),
                  selected: _zonasEfectivas(h.accion, o).contains(z.id),
                  onSelected: (sel) {
                    final actuales = [..._zonasEfectivas(h.accion, o)];
                    if (sel) {
                      actuales.add(z.id);
                    } else if (actuales.length > 1) {
                      actuales.remove(z.id);
                    }
                    final permitidos = tiposPara(h.accion, actuales);
                    _set(
                      (h) => h.copyWith(
                        objetivo: _limpiarFiltros(
                          o.copyWith(
                            zona: actuales.first,
                            zonas: actuales.length > 1 ? actuales : const [],
                            tipos: o.tipos.where(permitidos.contains).toList(),
                          ),
                          q,
                        ),
                      ),
                    );
                  },
                ),
            ],
          ),
        ],
        if (q.seleccion) ...[
          const SizedBox(height: 8),
          _drop(
            kSeleccion,
            o.seleccion,
            (v) => _set((h) => h.copyWith(objetivo: o.copyWith(seleccion: v))),
            label: '¿Cuáles?',
          ),
        ],
        if (q.filtros) ...[
          const SizedBox(height: 8),
          const Text(
            '¿Con qué limitaciones?',
            style: TextStyle(color: Colors.white54, fontSize: 12),
          ),
          _check(
            'La carta la nombra el jugador al entrar en juego (afecta a '
            'todas sus copias)',
            o.nombrarCarta,
            (v) =>
                _set((h) => h.copyWith(objetivo: o.copyWith(nombrarCarta: v))),
          ),
          if (_usaCoste(o, q))
            _comparacion(
              'Coste',
              o.coste,
              (c) =>
                  _set((h) => h.copyWith(objetivo: o.copyWith(coste: () => c))),
            ),
          if (_soloAliados(o, q)) ...[
            _comparacion(
              'Fuerza',
              o.fuerza,
              (c) => _set(
                (h) => h.copyWith(objetivo: o.copyWith(fuerza: () => c)),
              ),
            ),
            _check(
              'La raza la nombra el jugador al entrar en juego',
              o.nombrarRaza,
              (v) => _set(
                (h) => h.copyWith(
                  objetivo: o.copyWith(nombrarRaza: v, raza: v ? '' : null),
                ),
              ),
            ),
            if (o.nombrarRaza)
              _text(
                o.excluirRazas.join(', '),
                'No se pueden nombrar (separadas por coma)',
                (v) => _set(
                  (h) => h.copyWith(
                    objetivo: o.copyWith(
                      excluirRazas:
                          v
                              .split(',')
                              .map((r) => r.trim())
                              .where((r) => r.isNotEmpty)
                              .toList(),
                    ),
                  ),
                ),
              )
            else
              _text(
                o.raza,
                'Raza (opcional)',
                (v) => _set((h) => h.copyWith(objetivo: o.copyWith(raza: v))),
              ),
          ] else
            const Text(
              'Raza y Fuerza solo aplican a Aliados: marca solo "Aliado" '
              'para filtrar por ellas.',
              style: TextStyle(color: Colors.white38, fontSize: 11),
            ),
          _text(
            o.arquetipo,
            'Arquetipo en el nombre (Druida, Goblin…; opcional)',
            (v) => _set((h) => h.copyWith(objetivo: o.copyWith(arquetipo: v))),
          ),
          _check(
            'Raza y arquetipo se exigen solo a los Aliados ("un Oro o un '
            'Aliado Druida")',
            o.filtroSoloAliados,
            (v) => _set(
              (h) => h.copyWith(objetivo: o.copyWith(filtroSoloAliados: v)),
            ),
          ),
          _check(
            'Excepto esta carta y sus copias ("tus demás…", "que no sea…")',
            o.excluirEstaCarta,
            (v) => _set(
              (h) => h.copyWith(objetivo: o.copyWith(excluirEstaCarta: v)),
            ),
          ),
          _check(
            'Solo Aliados declarados atacantes o bloqueadores este turno',
            o.combate,
            (v) => _set((h) => h.copyWith(objetivo: o.copyWith(combate: v))),
          ),
        ],
      ],
    ];
  }

  static bool _esSoloAliado(List<String> tipos) =>
      tipos.length == 1 && tipos.first == 'Aliado';

  /// Raza y Fuerza solo existen en Aliados. Si la pregunta no muestra tipos,
  /// la acción ya es sobre Aliados (fuerza, combate, portador…).
  bool _soloAliados(ObjetivoHabilidad o, _Preguntas q) =>
      !q.tipos ||
      _esSoloAliado(o.tipos) ||
      (_h != null &&
          _esSoloAliado(tiposPara(_h!.accion, _zonasEfectivas(_h!.accion, o))));

  /// Los Oros no tienen coste (D.A.R. 4.2.5).
  bool _usaCoste(ObjetivoHabilidad o, _Preguntas q) =>
      !(o.tipos.length == 1 && o.tipos.first == 'Oro');

  ObjetivoHabilidad _limpiarFiltros(ObjetivoHabilidad o, _Preguntas q) =>
      o.copyWith(
        raza: _soloAliados(o, q) ? null : '',
        fuerza: _soloAliados(o, q) ? null : () => null,
        coste: _usaCoste(o, q) ? null : () => null,
      );

  CondicionHabilidad _cond(
    CondicionHabilidad c, {
    String? tipo,
    String? op,
    int? valor,
    String? raza,
    String? arquetipo,
  }) => CondicionHabilidad(
    tipo: tipo ?? c.tipo,
    op: op ?? c.op,
    valor: valor ?? c.valor,
    raza: raza ?? c.raza,
    arquetipo: arquetipo ?? c.arquetipo,
  );

  Widget _check(String label, bool value, ValueChanged<bool> onChanged) =>
      CheckboxListTile(
        contentPadding: EdgeInsets.zero,
        dense: true,
        value: value,
        onChanged: (v) => onChanged(v ?? false),
        title: Text(label, style: const TextStyle(color: Colors.white70)),
      );

  Widget _tipos(
    List<String> actuales,
    ValueChanged<List<String>> onChanged, {
    List<String> permitidos = kTiposCarta,
  }) => Wrap(
    spacing: 6,
    children: [
      for (final t in permitidos)
        FilterChip(
          label: Text(t),
          selected: actuales.contains(t),
          onSelected:
              (sel) => onChanged(
                sel ? [...actuales, t] : actuales.where((x) => x != t).toList(),
              ),
        ),
    ],
  );

  // ── Helpers de UI ──────────────────────────────────────────────────────────
  InputDecoration _deco([String? label]) => InputDecoration(
    labelText: label,
    labelStyle: const TextStyle(color: Colors.white54),
    isDense: true,
    filled: true,
    fillColor: _field,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide.none,
    ),
  );

  Widget _label(String t) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(t, style: const TextStyle(color: Colors.white70)),
  );

  Widget _section(String t) => Padding(
    padding: const EdgeInsets.only(top: 18, bottom: 8),
    child: Text(
      t.toUpperCase(),
      style: const TextStyle(
        color: _gold,
        fontSize: 12,
        fontWeight: FontWeight.w800,
        letterSpacing: 1,
      ),
    ),
  );

  Widget _drop(
    List<Opcion> opciones,
    String value,
    ValueChanged<String> onChanged, {
    String? label,
  }) => DropdownButtonFormField<String>(
    initialValue:
        opciones.any((o) => o.id == value) ? value : opciones.first.id,
    isExpanded: true,
    dropdownColor: _field,
    style: const TextStyle(color: Colors.white, fontSize: 14),
    decoration: _deco(label),
    items: [
      for (final o in opciones)
        DropdownMenuItem(
          value: o.id,
          child: Text(o.label, overflow: TextOverflow.ellipsis),
        ),
    ],
    onChanged: (v) => v == null ? null : onChanged(v),
  );

  Widget _text(String value, String label, ValueChanged<String> onChanged) =>
      TextFormField(
        initialValue: value,
        style: const TextStyle(color: Colors.white),
        decoration: _deco(label),
        onChanged: onChanged,
      );

  Widget _num(int value, ValueChanged<int> onChanged, {int min = 0}) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      IconButton(
        visualDensity: VisualDensity.compact,
        onPressed: value > min ? () => onChanged(value - 1) : null,
        icon: const Icon(Icons.remove, color: Colors.white70, size: 18),
      ),
      SizedBox(
        width: 28,
        child: Text(
          '$value',
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      IconButton(
        visualDensity: VisualDensity.compact,
        onPressed: () => onChanged(value + 1),
        icon: const Icon(Icons.add, color: Colors.white70, size: 18),
      ),
    ],
  );

  Widget _numLabeled(
    String label,
    int value,
    ValueChanged<int> onChanged, {
    int min = 0,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(label, style: const TextStyle(color: Colors.white54, fontSize: 11)),
      _num(value, onChanged, min: min),
    ],
  );

  Widget _comparacion(
    String label,
    Comparacion? c,
    ValueChanged<Comparacion?> onChanged,
  ) => Wrap(
    crossAxisAlignment: WrapCrossAlignment.center,
    spacing: 8,
    children: [
      SizedBox(
        width: 150,
        child: CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          value: c != null,
          onChanged:
              (v) => onChanged(v == true ? const Comparacion('<=', 2) : null),
          title: Text(
            'Filtrar $label',
            style: const TextStyle(color: Colors.white70),
          ),
        ),
      ),
      if (c != null) ...[
        SizedBox(
          width: 80,
          child: _drop(
            kOperadores,
            c.op,
            (v) => onChanged(
              Comparacion(
                v,
                c.valor,
                segun: c.segun,
                raza: c.raza,
                arquetipo: c.arquetipo,
              ),
            ),
          ),
        ),
        SizedBox(
          width: 190,
          child: _drop(
            const [
              Opcion('', 'Un número'),
              Opcion('aliados_raza', 'Tus Aliados de una raza'),
              Opcion('aliados_arquetipo', 'Tus Aliados de un arquetipo'),
            ],
            c.segun,
            (v) => onChanged(
              Comparacion(
                c.op,
                c.valor,
                segun: v,
                raza: c.raza,
                arquetipo: c.arquetipo,
              ),
            ),
          ),
        ),
        if (c.segun == 'aliados_raza')
          SizedBox(
            width: 160,
            child: _text(
              c.raza,
              'Raza',
              (v) => onChanged(
                Comparacion(
                  c.op,
                  c.valor,
                  segun: c.segun,
                  raza: v,
                  arquetipo: c.arquetipo,
                ),
              ),
            ),
          )
        else if (c.segun == 'aliados_arquetipo')
          SizedBox(
            width: 160,
            child: _text(
              c.arquetipo,
              'Arquetipo (Minotauro…)',
              (v) => onChanged(
                Comparacion(
                  c.op,
                  c.valor,
                  segun: c.segun,
                  raza: c.raza,
                  arquetipo: v,
                ),
              ),
            ),
          )
        else
          _num(
            c.valor,
            (v) => onChanged(
              Comparacion(
                c.op,
                v,
                segun: c.segun,
                raza: c.raza,
                arquetipo: c.arquetipo,
              ),
            ),
          ),
      ],
    ],
  );
}

class _FeaturePicker extends StatelessWidget {
  final List<AccionDef> features;
  final String? selectedId;
  final ValueChanged<AccionDef> onPick;

  const _FeaturePicker({
    required this.features,
    required this.selectedId,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    return Autocomplete<AccionDef>(
      initialValue: TextEditingValue(
        text: features.where((f) => f.id == selectedId).firstOrNull?.name ?? '',
      ),
      displayStringForOption: (f) => f.name,
      optionsBuilder: (v) {
        final q = v.text.toLowerCase().trim();
        return q.isEmpty
            ? features
            : features.where((f) => f.name.toLowerCase().contains(q));
      },
      onSelected: onPick,
      fieldViewBuilder:
          (context, ctrl, focus, onSubmit) => TextField(
            controller: ctrl,
            focusNode: focus,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: 'Busca una acción…',
              hintStyle: const TextStyle(color: Colors.white38),
              prefixIcon: const Icon(Icons.search, color: Colors.white54),
              filled: true,
              fillColor: _field,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none,
              ),
            ),
          ),
      optionsViewBuilder:
          (context, onSelected, options) => Align(
            alignment: Alignment.topLeft,
            child: Material(
              color: _field,
              elevation: 6,
              borderRadius: BorderRadius.circular(10),
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxHeight: 280,
                  maxWidth: 520,
                ),
                child: ListView(
                  padding: EdgeInsets.zero,
                  shrinkWrap: true,
                  children: [
                    for (final f in options)
                      ListTile(
                        dense: true,
                        title: Text(
                          f.name,
                          style: const TextStyle(color: Colors.white),
                        ),
                        subtitle: Text(
                          f.descripcion,
                          style: const TextStyle(color: Colors.white54),
                        ),
                        onTap: () => onSelected(f),
                      ),
                  ],
                ),
              ),
            ),
          ),
    );
  }
}

// ── Preguntas según la acción ────────────────────────────────────────────────
// Cada acción muestra solo lo que tiene sentido preguntar para ella.

/// Zonas en el orden dado (la primera es la opción por defecto).
List<Opcion> _zonas(List<String> ids) => [
  for (final id in ids) ...kZonas.where((z) => z.id == id),
];

final _zonasEnJuego = _zonas([
  'en_juego',
  'linea_defensa',
  'linea_ataque',
  'linea_apoyo',
  'reserva_oro',
]);
final _zonasFuera = _zonas(['mazo', 'cementerio', 'destierro', 'mano']);

const _duracionesEfecto = [
  Opcion('hasta_fase_final', 'Hasta la Fase Final'),
  Opcion('hasta_vigilia', 'Hasta tu próxima Vigilia'),
  Opcion('mientras_en_juego', 'Mientras esta carta esté en juego'),
  Opcion('permanente', 'Por el resto del juego'),
];

class _Preguntas {
  final String titulo;
  final bool cartas; // objetivo de cartas
  final bool jugador; // objetivo de jugador (robar, botar…)
  final String quienLabel;
  final bool permiteEstaCarta;
  final bool tipos;
  final List<Opcion>? zonas;
  final String zonaLabel;
  final bool seleccion;
  final bool filtros;
  final String? cantidadLabel;
  final String? valorLabel;
  final bool destino;
  final String destinoLabel;
  final List<Opcion>? duraciones;
  final String modoLabel;
  final bool soloPara;

  /// Siempre activa (continua): sin fase, costo ni "opcional".
  final bool pasiva;

  /// Opciones de destino propias de la acción (null = todas).
  final List<Opcion>? destinos;

  const _Preguntas({
    required this.titulo,
    this.cartas = false,
    this.jugador = false,
    this.quienLabel = '¿De quién?',
    this.permiteEstaCarta = true,
    this.tipos = true,
    this.zonas,
    this.zonaLabel = '¿Dónde?',
    this.seleccion = true,
    this.filtros = true,
    this.cantidadLabel,
    this.valorLabel,
    this.destino = false,
    this.destinoLabel = '¿A dónde va?',
    this.duraciones,
    this.modoLabel = '¿Qué hace?',
    this.soloPara = false,
    this.pasiva = false,
    this.destinos,
  });
}

_Preguntas _preguntasDe(Accion a) => switch (a) {
  Accion.destruir => _Preguntas(
    titulo: '¿Qué destruye?',
    cartas: true,
    zonas: _zonasEnJuego,
    cantidadLabel: '¿Cuántas?',
  ),
  Accion.desterrar => const _Preguntas(
    titulo: '¿Qué destierra?',
    cartas: true,
    zonas: kZonas,
    zonaLabel: '¿Desde dónde?',
    cantidadLabel: '¿Cuántas?',
  ),
  Accion.subirMano => _Preguntas(
    titulo: '¿Qué sube a la mano?',
    cartas: true,
    zonas: [
      ..._zonasEnJuego,
      ..._zonas(['cementerio']),
    ],
    zonaLabel: '¿Desde dónde? (en juego → mano de su dueño)',
    cantidadLabel: '¿Cuántas?',
  ),
  Accion.barajar => _Preguntas(
    titulo: '¿Qué baraja en el Mazo Castillo?',
    cartas: true,
    zonas: [
      ..._zonasEnJuego,
      ..._zonas(['cementerio', 'mano']),
    ],
    zonaLabel: '¿Desde dónde?',
    cantidadLabel: '¿Cuántas?',
  ),
  Accion.mover => const _Preguntas(
    titulo: '¿Qué mueve?',
    cartas: true,
    zonas: kZonas,
    zonaLabel: '¿Desde dónde?',
    cantidadLabel: '¿Cuántas?',
    destino: true,
    destinoLabel: '¿Hacia dónde?',
  ),
  Accion.buscar => _Preguntas(
    titulo: '¿Qué busca?',
    cartas: true,
    permiteEstaCarta: false,
    zonas: _zonasFuera,
    zonaLabel: '¿Dónde busca?',
    cantidadLabel: '¿Cuántas?',
    destino: true,
  ),
  Accion.ponerEnJuego => _Preguntas(
    titulo: '¿Qué pone en juego?',
    cartas: true,
    zonas: _zonasFuera,
    zonaLabel: '¿Desde dónde?',
    cantidadLabel: '¿Cuántas?',
    destino: true,
  ),
  Accion.jugarDesde => _Preguntas(
    titulo: '¿Qué carta se puede jugar?',
    cartas: true,
    zonas: _zonasFuera,
    zonaLabel: '¿Desde dónde?',
    cantidadLabel: '¿Cuántas?',
    modoLabel: '¿Paga su coste?',
    destino: true,
    destinoLabel: 'Si es un Talismán, después de resolverse va a',
    destinos: _zonas(['cementerio', 'destierro']),
  ),
  Accion.ganarControl => _Preguntas(
    titulo: '¿De qué carta toma el control?',
    cartas: true,
    permiteEstaCarta: false,
    zonas: _zonasEnJuego,
    cantidadLabel: '¿Cuántas?',
    duraciones: kDuracionControl,
  ),
  Accion.modificarFuerza => const _Preguntas(
    titulo: '¿A qué Aliados?',
    cartas: true,
    tipos: false,
    zonas: null,
    cantidadLabel: '¿Cuántos?',
    valorLabel: 'Valor (±N o N)',
    duraciones: kDuracion,
  ),
  Accion.modificarCoste => const _Preguntas(
    titulo: '¿Qué cartas cambian de coste?',
    cartas: true,
    zonas: null,
    seleccion: false,
    valorLabel: 'Cambio de coste (negativo = más barato)',
  ),
  Accion.perderHabilidad => _Preguntas(
    titulo: '¿Qué cartas pierden la habilidad?',
    cartas: true,
    zonas: _zonasEnJuego,
    cantidadLabel: '¿Cuántas?',
    duraciones: _duracionesEfecto,
  ),
  Accion.prevenir => const _Preguntas(
    titulo: '¿Qué protege?',
    cartas: true,
    zonas: null,
    seleccion: false,
    destino: true,
    destinoLabel: 'Además, la carta protegida va a (opcional)',
  ),
  Accion.anular => const _Preguntas(
    titulo: '¿Qué puede anular?',
    cartas: true,
    quienLabel: '¿De quién? (normalmente del oponente)',
    permiteEstaCarta: false,
    zonas: null,
    seleccion: false,
  ),
  Accion.restringirCombate => const _Preguntas(
    titulo: 'Restricción de combate',
    cartas: true,
    tipos: false,
    zonas: null,
    cantidadLabel: '¿Cuántos Aliados?',
    duraciones: kDuracion,
  ),
  Accion.inmunidad => const _Preguntas(
    pasiva: true,
    titulo: '¿Inmune a las habilidades de qué cartas?',
    cartas: true,
    quienLabel: '¿Cartas de quién?',
    permiteEstaCarta: false,
    zonas: null,
    seleccion: false,
    filtros: false,
  ),
  Accion.robar => const _Preguntas(
    titulo: '¿Quién roba?',
    jugador: true,
    quienLabel: 'Jugador',
    cantidadLabel: '¿Cuántas cartas?',
    modoLabel: '¿De dónde roba?',
  ),
  Accion.botar => const _Preguntas(
    titulo: '¿Quién bota?',
    jugador: true,
    quienLabel: 'Jugador',
    cantidadLabel: '¿Cuántas cartas?',
  ),
  Accion.descartar => const _Preguntas(
    titulo: '¿Quién descarta?',
    jugador: true,
    quienLabel: 'Jugador',
    cantidadLabel: '¿Cuántas cartas?',
  ),
  Accion.generarOro => const _Preguntas(
    titulo: 'Oros generados',
    valorLabel: '¿Cuántos oros?',
    soloPara: true,
  ),
  Accion.mirar => const _Preguntas(
    titulo: '¿Qué mira?',
    cantidadLabel: '¿Cuántas cartas?',
  ),
  Accion.mirarTope => const _Preguntas(
    titulo: '¿Qué Mazo mira y cuáles puede tomar?',
    cartas: true,
    permiteEstaCarta: false,
    zonas: null,
    seleccion: false,
    quienLabel: '¿De qué Mazo?',
    cantidadLabel: '¿Cuántas mira?',
    valorLabel: '¿Cuántas toma? (0 = ninguna)',
    destino: true,
    destinoLabel: '¿A dónde van las que toma?',
    destinos: [
      Opcion('mano', 'A la mano'),
      Opcion('en_juego', 'Se juegan sin pagar su coste'),
    ],
  ),
  Accion.elegir => _Preguntas(
    titulo: '¿Qué carta elige (sin afectarla)?',
    cartas: true,
    zonas: _zonasEnJuego,
  ),
  Accion.cambiarRaza => _Preguntas(
    titulo: '¿Qué cartas cambian de raza?',
    cartas: true,
    zonas: _zonasEnJuego,
    cantidadLabel: '¿Cuántas?',
  ),
  Accion.convertirEnAliado => const _Preguntas(
    titulo: 'Esta carta se convierte en Aliado',
    valorLabel: 'Coste y fuerza del Aliado',
    duraciones: [Opcion('hasta_fase_final', 'Hasta la Fase Final')],
  ),
  Accion.cancelarAtaque => const _Preguntas(titulo: '¿Qué cancela?'),
  Accion.reducirDano => const _Preguntas(
    titulo: 'Reducir daño',
    cartas: true,
    tipos: false,
    zonas: null,
    seleccion: false,
    filtros: false,
    quienLabel: '¿De quién es el Aliado?',
    valorLabel: '¿En cuánto se reduce?',
  ),
  Accion.agrupar => const _Preguntas(
    titulo: '¿Qué agrupa?',
    jugador: true,
    quienLabel: 'Jugador',
  ),
  Accion.noAgrupar => const _Preguntas(
    titulo: '¿Qué no agrupa?',
    jugador: true,
    quienLabel: 'Jugador',
  ),
  Accion.restriccion => const _Preguntas(
    pasiva: true,
    titulo: '¿Qué prohíbe?',
    jugador: true,
    quienLabel: '¿A quién afecta?',
    cartas: true,
    zonas: null,
    seleccion: false,
    filtros: false,
    modoLabel: 'Prohibición',
  ),
  Accion.otorgarPropiedad => _Preguntas(
    titulo: '¿Qué propiedad y a qué cartas?',
    modoLabel: 'Propiedad',
    cartas: true,
    zonas: _zonasEnJuego,
    cantidadLabel: '¿Cuántas?',
    duraciones: _duracionesEfecto,
  ),
  Accion.protegerHabilidad => const _Preguntas(
    pasiva: true,
    titulo: '¿Qué cartas no pueden perder su habilidad?',
    cartas: true,
    zonas: null,
    seleccion: false,
  ),
  Accion.encarecer => const _Preguntas(
    pasiva: true,
    titulo: '¿Qué cartas del oponente deben pagar más para afectarla?',
    cartas: true,
    quienLabel: '¿Cartas de quién?',
    permiteEstaCarta: false,
    zonas: null,
    seleccion: false,
    filtros: false,
    valorLabel: 'Oros adicionales',
  ),
  Accion.obligarBloqueo => const _Preguntas(
    titulo: '¿Qué Aliado oponente debe bloquearlo?',
    cartas: true,
    quienLabel: '¿De quién? (normalmente del oponente)',
    permiteEstaCarta: false,
    tipos: false,
    zonas: null,
    seleccion: false,
  ),
  Accion.requisitoPortador => const _Preguntas(
    pasiva: true,
    titulo: '¿Qué Aliados pueden portarla?',
    cartas: true,
    quienLabel: '¿De quién? (Tuyos, del oponente o de cualquiera)',
    permiteEstaCarta: false,
    tipos: false,
    zonas: null,
    seleccion: false,
  ),
  Accion.redirigir => const _Preguntas(
    titulo:
        'Redirige un efecto oponente que afecte una de tus cartas a '
        'otra carta válida para ese mismo efecto',
  ),
  _ => const _Preguntas(titulo: 'Efecto'),
};

/// Dónde puede estar la carta para usar su habilidad, según su tipo.
List<Opcion> _zonasActivacionPara(String tipoCarta) {
  final t = tipoCarta.toLowerCase();
  final ids =
      t == 'oro'
          ? ['reserva_oro', 'reserva_o_pagado', 'cementerio', 'mano']
          : t.startsWith('talism')
          ? <String>[]
          : ['en_juego', 'cementerio', 'mano'];
  return kZonaActivacion.where((z) => ids.contains(z.id)).toList();
}

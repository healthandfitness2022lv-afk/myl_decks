// lib/screens/habilidades/luego_editor.dart
//
// Efectos "Luego…" de una habilidad: se resuelven en orden después del
// efecto principal. Pueden actuar sobre las mismas cartas afectadas o sobre
// sus copias (p. ej. Abhartach: destierra un Aliado y luego todas sus copias
// del Mazo Castillo oponente).

import 'package:flutter/material.dart';

import '../../models/card_habilidad.dart';

const _field = Color(0xFF1B3036);
const _gold = Color(0xFFF2D487);
const _bg = Color(0xFF132126);

class LuegoSection extends StatelessWidget {
  final List<EfectoLuego> efectos;

  /// Tipo de la carta (para ofrecer "Pagar este Oro" solo en Oros).
  final String tipoCarta;
  final ValueChanged<List<EfectoLuego>> onChanged;

  const LuegoSection({
    super.key,
    required this.efectos,
    required this.onChanged,
    this.tipoCarta = '',
  });

  Future<void> _editar(BuildContext context, [int? i]) async {
    final r = await showDialog<EfectoLuego>(
      context: context,
      builder:
          (_) => _LuegoDialog(
            inicial: i == null ? null : efectos[i],
            esOro: tipoCarta.toLowerCase() == 'oro',
          ),
    );
    if (r == null) return;
    final list = [...efectos];
    if (i == null) {
      list.add(r);
    } else {
      list[i] = r;
    }
    onChanged(list);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 18, bottom: 4),
          child: Text(
            'LUEGO…',
            style: TextStyle(
              color: _gold,
              fontSize: 12,
              fontWeight: FontWeight.w800,
              letterSpacing: 1,
            ),
          ),
        ),
        const Text(
          'Efectos que ocurren después del principal, en orden.',
          style: TextStyle(color: Colors.white38, fontSize: 12),
        ),
        for (var i = 0; i < efectos.length; i++)
          Container(
            margin: const EdgeInsets.only(top: 6),
            decoration: BoxDecoration(
              color: Colors.black26,
              borderRadius: BorderRadius.circular(10),
            ),
            child: ListTile(
              dense: true,
              title: Text(
                efectos[i].resumen,
                style: const TextStyle(color: Colors.white70),
              ),
              onTap: () => _editar(context, i),
              trailing: IconButton(
                icon: const Icon(Icons.close, color: Colors.white38),
                onPressed: () => onChanged([...efectos]..removeAt(i)),
              ),
            ),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => _editar(context),
            icon: const Icon(Icons.subdirectory_arrow_right_rounded),
            label: const Text('Agregar "luego…"'),
          ),
        ),
      ],
    );
  }
}

class _LuegoDialog extends StatefulWidget {
  final EfectoLuego? inicial;
  final bool esOro;
  const _LuegoDialog({this.inicial, this.esOro = false});

  @override
  State<_LuegoDialog> createState() => _LuegoDialogState();
}

class _LuegoDialogState extends State<_LuegoDialog> {
  late EfectoLuego _e =
      widget.inicial ??
      const EfectoLuego(
        accion: Accion.desterrar,
        objetivo: ObjetivoHabilidad(
          quien: 'oponente',
          zona: 'mazo',
          seleccion: 'todos',
          referencia: 'copias',
        ),
      );

  static final _acciones =
      Accion.values.where((a) => !a.esPropiedad && a != Accion.anular).toList();

  void _obj(ObjetivoHabilidad o) =>
      setState(() => _e = _e.copyWith(objetivo: o));

  @override
  Widget build(BuildContext context) {
    final e = _e;
    final o = e.objetivo;
    final sobreCartas = e.accion.usaObjetivoCartas;
    return AlertDialog(
      backgroundColor: _bg,
      title: const Text('Luego…', style: TextStyle(color: _gold)),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _drop<String>(
                'Cuándo ocurre',
                [for (final r in kRelacion) (r.id, r.label)],
                e.relacion,
                (v) => setState(() => _e = e.copyWith(relacion: v)),
              ),
              if (e.accion == Accion.cambiarRaza)
                _texto(
                  'Raza que pasan a tener',
                  e.razaNueva,
                  (v) => setState(() => _e = e.copyWith(razaNueva: v)),
                ),
              if (e.relacion == 'si_afectada_cumple') ...[
                _texto(
                  'La afectada es de la raza (opcional)',
                  e.filtroRaza,
                  (v) => setState(() => _e = e.copyWith(filtroRaza: v)),
                ),
                _texto(
                  'La afectada es del arquetipo (Druida, Goblin…; opcional)',
                  e.filtroArquetipo,
                  (v) => setState(() => _e = e.copyWith(filtroArquetipo: v)),
                ),
                _texto(
                  'La afectada es de alguno de estos tipos (separados por '
                  'coma, ej. Oro, Aliado; opcional)',
                  e.filtroTipos.join(', '),
                  (v) => setState(
                    () =>
                        _e = e.copyWith(
                          filtroTipos:
                              v
                                  .split(',')
                                  .map((x) => x.trim())
                                  .where((x) => x.isNotEmpty)
                                  .toList(),
                        ),
                  ),
                ),
              ],
              _texto(
                'Elige una sola de las opciones con este mismo grupo '
                '(opcional)',
                e.grupoElegir,
                (v) => setState(() => _e = e.copyWith(grupoElegir: v)),
              ),
              _drop<String>(
                '¿Cuándo se resuelve?',
                [for (final m in kMomento) (m.id, m.label)],
                e.momento,
                (v) => setState(() => _e = e.copyWith(momento: v)),
              ),
              _drop<Accion>(
                'Acción',
                [for (final a in _acciones) (a, a.label)],
                e.accion,
                (v) => setState(
                  () =>
                      _e = e.copyWith(
                        accion: v,
                        modo: kModos[v]?.first.id ?? '',
                        // Al pasar a una acción sobre jugadores (robar, botar…)
                        // no deben quedar filtros de cartas guardados.
                        objetivo:
                            v.usaObjetivoCartas
                                ? e.objetivo
                                : ObjetivoHabilidad(
                                  quien:
                                      v == Accion.botar || v == Accion.descartar
                                          ? 'oponente'
                                          : 'propio',
                                ),
                      ),
                ),
              ),
              if (kModos[e.accion] != null)
                _drop<String>(
                  'Modo',
                  [for (final m in kModos[e.accion]!) (m.id, m.label)],
                  e.modo.isEmpty ? kModos[e.accion]!.first.id : e.modo,
                  (v) => setState(() => _e = e.copyWith(modo: v)),
                ),
              if (sobreCartas) ...[
                _drop<String>(
                  'Sobre qué cartas',
                  [for (final r in kReferencia) (r.id, r.label)],
                  o.referencia,
                  (v) => _obj(o.copyWith(referencia: v)),
                ),
                if (o.referencia != 'afectadas') ...[
                  _drop<String>(
                    'De quién',
                    [
                      for (final q in kQuien)
                        if (q.id != 'esta_carta') (q.id, q.label),
                    ],
                    o.quien == 'esta_carta' ? 'oponente' : o.quien,
                    (v) => _obj(o.copyWith(quien: v)),
                  ),
                  _drop<String>(
                    'Dónde',
                    [for (final z in kZonas) (z.id, z.label)],
                    o.zona,
                    (v) => _obj(
                      o.copyWith(
                        zona: v,
                        tipos:
                            o.tipos
                                .where(tiposPara(e.accion, [v]).contains)
                                .toList(),
                      ),
                    ),
                  ),
                  _drop<String>(
                    'Selección',
                    [for (final x in kSeleccion) (x.id, x.label)],
                    o.seleccion,
                    (v) => _obj(o.copyWith(seleccion: v)),
                  ),
                  if (o.referencia == 'ninguna')
                    Wrap(
                      spacing: 6,
                      children: [
                        for (final t in tiposPara(e.accion, o.todasLasZonas))
                          FilterChip(
                            label: Text(t),
                            selected: o.tipos.contains(t),
                            onSelected:
                                (sel) => _obj(
                                  o.copyWith(
                                    tipos:
                                        sel
                                            ? [...o.tipos, t]
                                            : o.tipos
                                                .where((x) => x != t)
                                                .toList(),
                                  ),
                                ),
                          ),
                      ],
                    ),
                ],
              ] else
                _drop<String>(
                  'A qué jugador',
                  [for (final q in kJugadorObjetivo) (q.id, q.label)],
                  o.quien,
                  (v) => _obj(o.copyWith(quien: v)),
                ),
              if ((o.seleccion != 'todos' || !sobreCartas) &&
                  e.accion != Accion.generarOro)
                _drop<String>(
                  '¿Cuántas?',
                  [for (final c in kCantidadSegun) (c.id, c.label)],
                  e.cantidadSegun,
                  (v) => setState(() => _e = e.copyWith(cantidadSegun: v)),
                ),
              if (e.accion == Accion.generarOro ||
                  ((o.seleccion != 'todos' || !sobreCartas) &&
                      e.cantidadSegun == 'fijo'))
                _num(
                  e.accion == Accion.generarOro ? 'Oros' : 'Cantidad',
                  e.accion == Accion.generarOro ? e.valor : e.cantidad,
                  (v) => setState(
                    () =>
                        _e =
                            e.accion == Accion.generarOro
                                ? e.copyWith(valor: v)
                                : e.copyWith(cantidad: v),
                  ),
                ),
              if (e.accion.usaModoFuerza) ...[
                _drop<String>(
                  'Modo',
                  [for (final m in kModoFuerza) (m.id, m.label)],
                  e.modoFuerza,
                  (v) => setState(() => _e = e.copyWith(modoFuerza: v)),
                ),
                if (e.modoFuerza != 'duplicar')
                  _num(
                    'Valor (±)',
                    e.valor,
                    (v) => setState(() => _e = e.copyWith(valor: v)),
                    min: -20,
                  ),
              ],
              if (e.accion.usaZonaDestino)
                _drop<String>(
                  'Va a',
                  [for (final z in kZonas) (z.id, z.label)],
                  e.zonaDestino,
                  (v) => setState(() => _e = e.copyWith(zonaDestino: v)),
                ),
              _drop<String>(
                'Duración',
                [for (final d in kDuracion) (d.id, d.label)],
                e.duracion,
                (v) => setState(() => _e = e.copyWith(duracion: v)),
              ),
              // Condición, opcional y costo propios de este paso
              // (p. ej. Kawit: "si tienes igual o menos Oros, puedes robar").
              _drop<String>(
                'Condición de este paso',
                [for (final c in kCondiciones) (c.id, c.label)],
                e.condicion.tipo,
                (v) => setState(
                  () =>
                      _e = e.copyWith(
                        condicion: CondicionHabilidad(
                          tipo: v,
                          op: e.condicion.op,
                          valor:
                              v == 'oros_vs_oponente' ? 0 : e.condicion.valor,
                          raza: e.condicion.raza,
                          arquetipo: e.condicion.arquetipo,
                        ),
                      ),
                ),
              ),
              if (e.condicion.tipo == 'oros_vs_oponente')
                _drop<String>(
                  '¿Cuándo?',
                  [for (final x in kOrosVsOponente) (x.id, x.label)],
                  e.condicion.op,
                  (v) => setState(
                    () =>
                        _e = e.copyWith(
                          condicion: CondicionHabilidad(
                            tipo: e.condicion.tipo,
                            op: v,
                            valor: 0,
                            raza: e.condicion.raza,
                            arquetipo: e.condicion.arquetipo,
                          ),
                        ),
                  ),
                )
              else if (!e.condicion.esNinguna)
                Row(
                  children: [
                    SizedBox(
                      width: 90,
                      child: _drop<String>(
                        '',
                        [for (final x in kOperadores) (x.id, x.label)],
                        e.condicion.op,
                        (v) => setState(
                          () =>
                              _e = e.copyWith(
                                condicion: CondicionHabilidad(
                                  tipo: e.condicion.tipo,
                                  op: v,
                                  valor: e.condicion.valor,
                                  raza: e.condicion.raza,
                                  arquetipo: e.condicion.arquetipo,
                                ),
                              ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: _num(
                        'Valor',
                        e.condicion.valor,
                        (v) => setState(
                          () =>
                              _e = e.copyWith(
                                condicion: CondicionHabilidad(
                                  tipo: e.condicion.tipo,
                                  op: e.condicion.op,
                                  valor: v,
                                  raza: e.condicion.raza,
                                  arquetipo: e.condicion.arquetipo,
                                ),
                              ),
                        ),
                        min: -20,
                      ),
                    ),
                  ],
                ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                value: e.opcional,
                onChanged:
                    (v) =>
                        setState(() => _e = e.copyWith(opcional: v ?? false)),
                title: const Text(
                  'Opcional ("puedes")',
                  style: TextStyle(color: Colors.white70),
                ),
              ),
              _num(
                'Costo: oros',
                e.costo.oros,
                (v) => setState(
                  () => _e = e.copyWith(costo: e.costo.copyWith(oros: v)),
                ),
              ),
              if (widget.esOro)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  value: e.costo.pagarEstaCarta,
                  onChanged:
                      (v) => setState(
                        () =>
                            _e = e.copyWith(
                              costo: e.costo.copyWith(
                                pagarEstaCarta: v ?? false,
                              ),
                            ),
                      ),
                  title: const Text(
                    'Costo: pagar este Oro',
                    style: TextStyle(color: Colors.white70),
                  ),
                ),
              const SizedBox(height: 8),
              Text(e.resumen, style: const TextStyle(color: _gold)),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed:
              () => Navigator.pop(
                context,
                // Sin tocar el selector, el modo es la primera opción.
                _e.modo.isEmpty && kModos[_e.accion] != null
                    ? _e.copyWith(modo: kModos[_e.accion]!.first.id)
                    : _e,
              ),
          child: const Text('Listo'),
        ),
      ],
    );
  }

  Widget _drop<T>(
    String label,
    List<(T, String)> items,
    T value,
    ValueChanged<T> onChanged,
  ) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: DropdownButtonFormField<T>(
      initialValue: items.any((i) => i.$1 == value) ? value : items.first.$1,
      isExpanded: true,
      dropdownColor: _field,
      style: const TextStyle(color: Colors.white, fontSize: 14),
      decoration: InputDecoration(
        labelText: label,
        isDense: true,
        filled: true,
        fillColor: _field,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
      ),
      items: [
        for (final (v, l) in items)
          DropdownMenuItem(
            value: v,
            child: Text(l, overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: (v) => v == null ? null : onChanged(v),
    ),
  );

  Widget _texto(String label, String value, ValueChanged<String> onChanged) =>
      Padding(
        padding: const EdgeInsets.only(top: 6),
        child: TextFormField(
          key: ValueKey(label),
          initialValue: value,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            labelText: label,
            labelStyle: const TextStyle(color: Colors.white54),
          ),
          onChanged: onChanged,
        ),
      );

  Widget _num(
    String label,
    int value,
    ValueChanged<int> onChanged, {
    int min = 0,
  }) => Row(
    children: [
      Expanded(
        child: Text(label, style: const TextStyle(color: Colors.white54)),
      ),
      IconButton(
        onPressed: value > min ? () => onChanged(value - 1) : null,
        icon: const Icon(Icons.remove, color: Colors.white70, size: 18),
      ),
      Text(
        '$value',
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
        ),
      ),
      IconButton(
        onPressed: () => onChanged(value + 1),
        icon: const Icon(Icons.add, color: Colors.white70, size: 18),
      ),
    ],
  );
}

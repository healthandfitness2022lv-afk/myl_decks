import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

const _gold = Color(0xFFF2D487);
const _surface = Color(0xFF132126);

/// Jugadas de la IA en un desafío, marcables como buenas (✓) o malas (✗).
/// Las marcas van a `votosIa` del desafío; al terminar, la autopsia revisa
/// esas jugadas simulando alternativas y deja las lecciones para mejorar la IA.
List<Map<String, dynamic>> accionesIa(Map<String, dynamic> desafio) => [
  for (final a in (desafio['accionesIa'] as List? ?? const []))
    if (a is Map) a.cast<String, dynamic>(),
];

Map<String, String> votosIa(Map<String, dynamic> desafio) => {
  for (final e in ((desafio['votosIa'] as Map?) ?? const {}).entries)
    '${e.key}': '${e.value}',
};

Future<void> votarJugadaIa(
  DocumentReference<Map<String, dynamic>> ref,
  String accionId,
  String? voto,
) => ref.update({
  'votosIa.$accionId': voto ?? FieldValue.delete(),
});

/// Botones ✓ / ✗ de una jugada (tocar de nuevo la marca la quita).
class VotoJugadaIa extends StatelessWidget {
  const VotoJugadaIa({
    super.key,
    required this.ref,
    required this.accionId,
    required this.voto,
  });

  final DocumentReference<Map<String, dynamic>> ref;
  final String accionId;
  final String? voto;

  @override
  Widget build(BuildContext context) {
    Widget boton(String valor, IconData icono, Color color, String ayuda) {
      final activo = voto == valor;
      return IconButton(
        tooltip: ayuda,
        visualDensity: VisualDensity.compact,
        onPressed: () => votarJugadaIa(ref, accionId, activo ? null : valor),
        icon: Icon(icono, color: activo ? color : Colors.white38, size: 22),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        boton('buena', Icons.check_circle, Colors.greenAccent, 'Buena jugada'),
        boton('mala', Icons.cancel, Colors.redAccent, 'Mala jugada'),
      ],
    );
  }
}

/// Lista de jugadas de la IA (la más reciente arriba) con sus marcas.
class ListaJugadasIa extends StatelessWidget {
  const ListaJugadasIa({super.key, required this.ref, required this.desafio});

  final DocumentReference<Map<String, dynamic>> ref;
  final Map<String, dynamic> desafio;

  @override
  Widget build(BuildContext context) {
    final acciones = accionesIa(desafio).reversed.toList();
    final votos = votosIa(desafio);
    if (acciones.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Text(
          'La IA todavía no ha hecho jugadas.',
          style: TextStyle(color: Colors.white60),
        ),
      );
    }
    return ListView.separated(
      shrinkWrap: true,
      itemCount: acciones.length,
      separatorBuilder: (_, __) => const Divider(height: 1, color: Colors.white12),
      itemBuilder: (context, k) {
        final a = acciones[k];
        final id = '${a['id']}';
        return ListTile(
          dense: true,
          title: Text('${a['texto']}', style: const TextStyle(color: Colors.white)),
          subtitle: Text(
            'T${a['turno']} · ${'${a['fase']}'.replaceAll('_', ' ')}',
            style: const TextStyle(color: Colors.white54),
          ),
          trailing: VotoJugadaIa(ref: ref, accionId: id, voto: votos[id]),
        );
      },
    );
  }
}

/// Abre la lista de jugadas de la IA en una hoja inferior (durante la partida).
Future<void> mostrarJugadasIa(
  BuildContext context,
  DocumentReference<Map<String, dynamic>> ref,
) => showModalBottomSheet<void>(
  context: context,
  backgroundColor: _surface,
  isScrollControlled: true,
  builder:
      (context) => SizedBox(
        height: MediaQuery.sizeOf(context).height * .6,
        child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: ref.snapshots(),
          builder: (context, snap) {
            final d = snap.data?.data() ?? const <String, dynamic>{};
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
                  child: Text(
                    'Jugadas de la IA',
                    style: TextStyle(color: _gold, fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    'Marca ✓ las buenas y ✗ las malas. Al terminar se simulan alternativas y quedan '
                    'como lecciones; la IA cambia cuando se aplican.',
                    style: TextStyle(color: Colors.white60, fontSize: 12),
                  ),
                ),
                Expanded(child: ListaJugadasIa(ref: ref, desafio: d)),
              ],
            );
          },
        ),
      ),
);

/// Resultado de la autopsia: por qué perdió la IA y qué dicen las simulaciones
/// de las jugadas marcadas.
class AutopsiaIa extends StatelessWidget {
  const AutopsiaIa({super.key, required this.ref, required this.desafio});

  final DocumentReference<Map<String, dynamic>> ref;
  final Map<String, dynamic> desafio;

  @override
  Widget build(BuildContext context) {
    final estado = desafio['autopsiaEstado'] as String?;
    final autopsia = (desafio['autopsia'] as Map?)?.cast<String, dynamic>();
    final revisiones = [
      for (final r in (autopsia?['revisiones'] as List? ?? const []))
        if (r is Map) r.cast<String, dynamic>(),
    ];
    final ocupado = estado == 'analizando' || estado == 'pedida';
    return Card(
      color: _surface,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Revisión de la IA · lecciones pendientes de aplicar',
              style: TextStyle(color: _gold, fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 6),
            if (ocupado)
              const Row(
                children: [
                  SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Analizando la partida: simula alternativas a las jugadas clave de la IA…',
                      style: TextStyle(color: Colors.white70),
                    ),
                  ),
                ],
              )
            else if (estado == 'error')
              Text(
                'No se pudo analizar: ${desafio['autopsiaError'] ?? ''}',
                style: const TextStyle(color: Colors.redAccent),
              )
            else if (autopsia != null) ...[
              Text('${autopsia['resumen']}', style: const TextStyle(color: Colors.white)),
              for (final r in revisiones) ...[
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      // Indiferente: todas las opciones daban el mismo final
                      // (0% o 100%): no es acierto ni error.
                      r['error'] == true
                          ? Icons.error_outline
                          : r['indiferente'] == true
                          ? Icons.remove_circle_outline
                          : Icons.check_circle_outline,
                      color: r['error'] == true
                          ? Colors.orangeAccent
                          : r['indiferente'] == true
                          ? Colors.white38
                          : Colors.greenAccent,
                      size: 18,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '${r['explicacion']}'
                        '${r['voto'] == null ? '' : r['voto'] == 'mala' ? '  (la marcaste ✗)' : '  (la marcaste ✓)'}',
                        style: const TextStyle(color: Colors.white70),
                      ),
                    ),
                  ],
                ),
              ],
            ] else
              const Text(
                'Sin análisis todavía.',
                style: TextStyle(color: Colors.white60),
              ),
            const SizedBox(height: 10),
            const Text(
              'Jugadas de la IA',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 320),
              child: ListaJugadasIa(ref: ref, desafio: desafio),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed:
                  ocupado ? null : () => ref.update({'autopsiaEstado': 'pedida'}),
              icon: const Icon(Icons.psychology_outlined),
              label: const Text('Analizar con mis marcas'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Reporte en el momento exacto (durante la partida): guarda el punto de la
/// grabación, la mesa que estabas viendo y lo último que pasó, para reproducir
/// la partida justo ahí y revisar si el motor o la IA se equivocaron.
Future<void> reportarEnVivo(
  BuildContext context,
  DocumentReference<Map<String, dynamic>> ref,
  Map<String, dynamic> desafio,
) async {
  // Se congela lo que se ve al tocar el botón (la partida sigue avanzando).
  final estado = (desafio['estado'] as Map?)?.cast<String, dynamic>() ?? {};
  final paso = desafio['pasoGrabacion'];
  final accionIa = (desafio['accionIa'] as Map?)?['texto'];
  final decision = (desafio['decision'] as Map?)?.cast<String, dynamic>();
  final campo = TextEditingController();
  var tipo = 'regla';
  final enviar = await showDialog<bool>(
    context: context,
    builder:
        (context) => StatefulBuilder(
          builder:
              (context, setState) => AlertDialog(
                title: const Text('Reportar este momento'),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'T${estado['turno']} · ${'${estado['fase']}'.replaceAll('_', ' ')}'
                      '${accionIa == null ? '' : '\nÚltima de la IA: $accionIa'}',
                      style: const TextStyle(fontSize: 12, color: Colors.white60),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      children: [
                        for (final (valor, texto) in const [
                          ('regla', 'Regla mal aplicada'),
                          ('ia', 'Mala jugada de la IA'),
                          ('otro', 'Otro'),
                        ])
                          ChoiceChip(
                            label: Text(texto),
                            selected: tipo == valor,
                            onSelected: (_) => setState(() => tipo = valor),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: campo,
                      autofocus: true,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        hintText: 'Qué viste de irregular y qué debió pasar.',
                      ),
                    ),
                  ],
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Cancelar'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Guardar reporte'),
                  ),
                ],
              ),
        ),
  );
  final texto = campo.text.trim();
  if (enviar != true || texto.isEmpty) return;
  await ref.update({
    'reportes': FieldValue.arrayUnion([
      {
        'fecha': Timestamp.now(),
        'enVivo': true,
        'tipo': tipo,
        'comentario': texto,
        'turno': estado['turno'],
        'fase': estado['fase'],
        'pasoGrabacion': paso,
        'accionIa': accionIa,
        if (decision != null)
          'decision': {'tipo': decision['tipo'], 'titulo': decision['titulo']},
        'estado': estado,
      },
    ]),
  });
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Reporte guardado en este punto exacto de la partida.'),
      ),
    );
  }
}

/// Tus jugadas contra lo que habría hecho la IA en la misma posición
/// (simulado). Las que rinden más quedan como lecciones; confírmalas ✓ si
/// reflejan tu idea de juego o ✗ si fue casualidad.
class AprendizajeHumano extends StatelessWidget {
  const AprendizajeHumano({super.key, required this.ref, required this.desafio});

  final DocumentReference<Map<String, dynamic>> ref;
  final Map<String, dynamic> desafio;

  @override
  Widget build(BuildContext context) {
    final estado = desafio['aprendizajeEstado'] as String?;
    final inf = (desafio['aprendizajeHumano'] as Map?)?.cast<String, dynamic>();
    final confirmadas = {
      for (final e in ((desafio['confirmacionesHumano'] as Map?) ?? const {}).entries)
        '${e.key}': '${e.value}',
    };
    final diferencias = [
      for (final x in (inf?['diferencias'] as List? ?? const []))
        if (x is Map) x.cast<String, dynamic>(),
    ];
    final ocupado =
        estado == 'analizando' || desafio['autopsiaEstado'] == 'pedida';
    Widget confirmar(String paso) {
      final actual = confirmadas[paso];
      Widget boton(String valor, IconData icono, Color color, String ayuda) =>
          IconButton(
            tooltip: ayuda,
            visualDensity: VisualDensity.compact,
            onPressed:
                () => ref.update({
                  'confirmacionesHumano.$paso':
                      actual == valor ? FieldValue.delete() : valor,
                }),
            icon: Icon(icono, color: actual == valor ? color : Colors.white38, size: 22),
          );
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          boton('si', Icons.check_circle, Colors.greenAccent, 'Sí, es mi idea de juego'),
          boton('no', Icons.cancel, Colors.redAccent, 'No, fue casualidad'),
        ],
      );
    }

    return Card(
      color: _surface,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Tus jugadas vs. la IA · lecciones pendientes de aplicar',
              style: TextStyle(color: _gold, fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 6),
            if (ocupado)
              const Row(
                children: [
                  SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Comparando tus jugadas con lo que haría la IA en cada posición…',
                      style: TextStyle(color: Colors.white70),
                    ),
                  ),
                ],
              )
            else if (estado == 'error')
              Text(
                'No se pudo analizar: ${desafio['aprendizajeError'] ?? ''}',
                style: const TextStyle(color: Colors.redAccent),
              )
            else if (inf != null) ...[
              Text('${inf['resumen']}', style: const TextStyle(color: Colors.white)),
              if (inf['reproduccionOk'] == true)
                Text(
                  '${inf['decisiones']} decisiones tuyas · en ${inf['distintas']} la IA habría jugado distinto'
                  ' · se simularon ${inf['comparadas']}.',
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
              for (final x in diferencias) ...[
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      x['mejor'] == 'humano'
                          ? Icons.star_outline
                          : x['mejor'] == 'ia'
                          ? Icons.smart_toy_outlined
                          : Icons.drag_handle,
                      color:
                          x['mejor'] == 'humano'
                              ? _gold
                              : x['mejor'] == 'ia'
                              ? Colors.lightBlueAccent
                              : Colors.white38,
                      size: 18,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '${x['explicacion']}',
                        style: const TextStyle(color: Colors.white70),
                      ),
                    ),
                    confirmar('${x['paso']}'),
                  ],
                ),
              ],
              if (diferencias.isNotEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text(
                    '✓ = es mi idea de juego (se vuelve lección aunque la simulación salga pareja) · '
                    '✗ = fue casualidad. Luego toca "Analizar con mis marcas".',
                    style: TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                ),
            ] else
              const Text(
                'Sin análisis todavía: toca "Analizar con mis marcas".',
                style: TextStyle(color: Colors.white60),
              ),
          ],
        ),
      ),
    );
  }
}

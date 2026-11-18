// Reportes ANtc / HjND (18-11): en el celular había desbordes en vertical.
// Un teléfono real suele tener la letra del sistema agrandada: la mesa debe
// caber igual, sin franjas de desborde, en varios tamaños y decisiones.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myl_decks/screens/simulador/tablero_desafio.dart';

List<Map<String, Object>> _varias(int n, String prefijo, {String tipo = 'Aliado'}) => [
  for (var i = 0; i < n; i++)
    {
      'id': '$prefijo-$i',
      'cartaId': '__test__',
      'nombre': 'Carta con nombre largo $i',
      'tipo': tipo,
      'fuerza': 2,
    },
];

Map<String, dynamic> _lado(String nombre, {required bool humano, bool llena = true}) => {
  'nombre': nombre,
  'castillo': 40,
  'manoCantidad': humano ? 8 : 7,
  'mano': humano ? _varias(8, 'm') : <Map>[],
  'reserva': llena ? _varias(7, '${nombre}r', tipo: 'Oro') : <Map>[],
  'pagado': llena ? _varias(3, '${nombre}p', tipo: 'Oro') : <Map>[],
  'defensa': llena ? _varias(5, '${nombre}d') : <Map>[],
  'ataque': llena ? _varias(3, '${nombre}t') : <Map>[],
  'apoyo': llena ? _varias(2, '${nombre}a', tipo: 'Tótem') : <Map>[],
  'cementerio': 21,
  'destierro': 3,
  'cementerioCartas': _varias(4, '${nombre}c'),
  'destierroCartas': _varias(2, '${nombre}x'),
};

Map<String, dynamic> _estado({bool llena = true}) => {
  'turno': 21,
  'fase': 'guerra_talismanes',
  'activo': 1,
  'log': [
    'T21 [declaracion_ataque] IA ataca con Killgharrah, Draig Ifanc y Cathach el Dragón de la Tormenta',
    'T21 [guerra_talismanes] IA juega Capa De Invisibilidad (coste 3) en respuesta a Yvain Del León',
  ],
  'lados': [
    _lado('Caballero Armas de nombre largo', humano: true, llena: llena),
    _lado('Dragón control de torneo', humano: false, llena: llena),
  ],
};

final _decisiones = <String, Map<String, dynamic>?>{
  'sin decisión': null,
  'jugada': {
    'id': '1',
    'tipo': 'jugada',
    'titulo': 'Elige tu jugada',
    'opciones': [
      {'id': '0', 'titulo': 'pasar', 'tipoJugada': 'pasar'},
      {
        'id': '1',
        'titulo': 'jugar Carta con nombre largo 0',
        'tipoJugada': 'jugar',
        'cartaUid': 'm-0',
        'cartaTipo': 'Aliado',
      },
      {
        'id': '2',
        'titulo': 'activar Carta con nombre largo 1 · Paga 1: mueve un Aliado oponente de Ataque a Defensa',
        'tipoJugada': 'activar',
        'cartaUid': 'Caballero Armas de nombre largod-1',
        'cartaTipo': 'Aliado',
      },
    ],
  },
  'mano inicial': {
    'id': '2',
    'tipo': 'mano_inicial',
    'titulo': '¿Te quedas esta mano? Empieza el rival (dado: tú 1, rival 3)',
    'opciones': <Map>[],
  },
  'confirmar': {
    'id': '3',
    'tipo': 'confirmar',
    'titulo':
        '¿Usar Milano Negro (Si hace daño al Mazo Castillo oponente, puedes desterrar hasta 2 cartas de un Cementerio)?',
    'opciones': <Map>[],
  },
  'descartes': {
    'id': '4',
    'tipo': 'descartes',
    'titulo': 'Elige cartas para descartar',
    'cantidad': 2,
    'opciones': _varias(8, 'm'),
  },
};

void main() {
  for (final size in const [Size(320, 568), Size(360, 640), Size(360, 780), Size(412, 915)]) {
    for (final escala in const [1.0, 1.3]) {
      for (final llena in const [true, false]) {
        for (final d in _decisiones.entries) {
          testWidgets(
            'celular $size letra ×$escala ${llena ? 'mesa llena' : 'mesa vacía'} · ${d.key}',
            (tester) async {
              tester.view.physicalSize = size;
              tester.view.devicePixelRatio = 1;
              addTearDown(tester.view.resetPhysicalSize);
              addTearDown(tester.view.resetDevicePixelRatio);
              await tester.pumpWidget(
                MaterialApp(
                  home: MediaQuery(
                    data: MediaQueryData(size: size, textScaler: TextScaler.linear(escala)),
                    child: Scaffold(
                      body: TableroDesafio(
                        estado: _estado(llena: llena),
                        decision: d.value,
                        enviar: (_) async {},
                      ),
                    ),
                  ),
                ),
              );
              await tester.pump(const Duration(milliseconds: 600));
              expect(tester.takeException(), isNull);
              // El rival siempre a la vista: castillo, mano, cementerio y destierro.
              expect(find.textContaining('Castillo 40'), findsWidgets);
              expect(find.text('Cem. 21'), findsWidgets);
              expect(find.text('Dest. 3'), findsWidgets);
            },
          );
        }
      }
    }
  }
}

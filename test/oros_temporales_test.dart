import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myl_decks/screens/simulador/oro_temporal.dart';
import 'package:myl_decks/screens/simulador/tablero_desafio.dart';
import 'package:myl_decks/screens/simulador/tablero_screen.dart';

/// Reporte g3hq: los Oros generados se ven en la Reserva como fichas.
void main() {
  Map<String, dynamic> lado(String nombre, int virtuales) => {
    'nombre': nombre,
    'castillo': 40,
    'manoCantidad': 0,
    'mano': <Map>[],
    'reserva': <Map>[],
    'pagado': <Map>[],
    'defensa': <Map>[],
    'ataque': <Map>[],
    'apoyo': <Map>[],
    'cementerio': 0,
    'destierro': 0,
    'orosVirtuales': virtuales,
    'orosVirtualesDetalle': ['$virtuales libres'],
  };

  for (final size in [const Size(1280, 720), const Size(400, 760)]) {
    testWidgets('desafío: 2 oros temporales en tu Reserva ($size)', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: TableroDesafio(
        estado: {'turno': 3, 'fase': 'vigilia', 'activo': 0, 'lados': [lado('Tú', 2), lado('IA', 0)]},
        decision: null,
        enviar: (_) async {},
      ))));
      expect(tester.takeException(), isNull);
      expect(find.byType(OroTemporal), findsNWidgets(2));
    });
  }

  test('la letra del cuadro de la jugada se achica con textos largos', () {
    expect(tamanoTextoJugada('corto'), 14);
    expect(tamanoTextoJugada('x' * 300), lessThan(14));
    expect(tamanoTextoJugada('x' * 600), lessThan(tamanoTextoJugada('x' * 300)));
  });
}

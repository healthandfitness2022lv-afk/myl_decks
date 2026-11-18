import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:myl_decks/domain/torneo/torneo.dart';

List<JugadorTorneo> _jugadores(int n) => [
  for (var i = 1; i <= n; i++)
    JugadorTorneo(id: 'j$i', nombre: 'Jugador ${i.toString().padLeft(2, '0')}'),
];

/// Juega una ronda: gana siempre el de número más bajo (j1 es el mejor).
List<DueloTorneo> _jugar(List<Emparejamiento> pares, int ronda, {String fase = 'suizo'}) => [
  for (var i = 0; i < pares.length; i++)
    () {
      final p = pares[i];
      if (p.b == null) {
        return DueloTorneo(fase: fase, ronda: ronda, mesa: i + 1, a: p.a);
      }
      final ganaA = int.parse(p.a.substring(1)) < int.parse(p.b!.substring(1));
      return DueloTorneo(
        fase: fase,
        ronda: ronda,
        mesa: i + 1,
        a: p.a,
        b: p.b,
        scoreA: ganaA ? 2 : 0,
        scoreB: ganaA ? 0 : 2,
        confirmado: true,
      );
    }(),
];

void main() {
  test('rondas y top sugeridos', () {
    expect(rondasSugeridas(2), 1);
    expect(rondasSugeridas(8), 3);
    expect(rondasSugeridas(9), 4);
    expect(rondasSugeridas(16), 4);
    expect(rondasSugeridas(17), 5);
    expect(rondasSugeridas(1000), 8);
    expect(topSugerido(5), 0);
    expect(topSugerido(8), 4);
    expect(topSugerido(24), 8);
  });

  test('primera ronda: todos juegan una vez y el impar recibe bye', () {
    final pares = emparejarSuizo(_jugadores(13), const [], azar: Random(1));
    expect(pares.length, 7);
    expect(pares.where((p) => p.b == null).length, 1);
    final vistos = [for (final p in pares) ...[p.a, if (p.b != null) p.b!]];
    expect(vistos.toSet().length, 13);
  });

  test('torneo de 8: sin rivales repetidos y el mejor termina primero', () {
    final jugadores = _jugadores(8);
    final duelos = <DueloTorneo>[];
    for (var ronda = 1; ronda <= 3; ronda++) {
      final pares = emparejarSuizo(jugadores, duelos, azar: Random(ronda));
      expect(pares.length, 4);
      duelos.addAll(_jugar(pares, ronda));
    }
    final cruces = {for (final d in duelos) ([d.a, d.b!]..sort()).join('-')};
    expect(cruces.length, 12, reason: 'ningún cruce repetido');
    final tabla = calcularTabla(jugadores, duelos);
    expect(tabla.first.jugador.id, 'j1');
    expect(tabla.first.puntos, 9);
    expect(tabla.first.ganados, 3);
    expect(tabla.last.puntos, 0);
    // En la ronda 2 juegan entre sí los que ganaron en la ronda 1.
    final ganadoresR1 = {for (final d in duelos.where((d) => d.ronda == 1)) d.ganador};
    for (final d in duelos.where((d) => d.ronda == 2).take(2)) {
      expect(ganadoresR1.contains(d.a) && ganadoresR1.contains(d.b), isTrue);
    }
  });

  test('torneo de 13 con bye y retiro', () {
    var jugadores = _jugadores(13);
    final duelos = <DueloTorneo>[];
    final byes = <String>[];
    for (var ronda = 1; ronda <= 4; ronda++) {
      if (ronda == 3) {
        // j13 se retira: quedan 12, ya no hay bye.
        jugadores = [
          for (final j in jugadores)
            j.id == 'j13'
                ? JugadorTorneo(id: j.id, nombre: j.nombre, retirado: true)
                : j,
        ];
      }
      final pares = emparejarSuizo(jugadores, duelos, azar: Random(ronda));
      final ids = [for (final p in pares) ...[p.a, if (p.b != null) p.b!]];
      expect(ids.toSet().length, ids.length, reason: 'nadie juega dos veces');
      if (ronda >= 3) {
        expect(ids.contains('j13'), isFalse);
        expect(pares.every((p) => p.b != null), isTrue);
      } else {
        byes.add(pares.singleWhere((p) => p.b == null).a);
      }
      duelos.addAll(_jugar(pares, ronda));
    }
    expect(byes.toSet().length, 2, reason: 'nadie recibe dos byes');
    final sinBye = duelos.where((d) => !d.esBye);
    final cruces = {for (final d in sinBye) ([d.a, d.b!]..sort()).join('-')};
    expect(cruces.length, sinBye.length, reason: 'ningún cruce repetido');
    final tabla = calcularTabla(jugadores, duelos);
    expect(tabla.length, 13, reason: 'el retirado sigue en la tabla');
    expect(tabla.first.jugador.id, 'j1');
    expect(tabla.first.puntos, 12);
  });

  test('tabla: empates, bye y desempate por rivales', () {
    final jugadores = _jugadores(5);
    const duelos = [
      DueloTorneo(fase: 'suizo', ronda: 1, mesa: 1, a: 'j1', b: 'j2', scoreA: 2, scoreB: 1, confirmado: true),
      DueloTorneo(fase: 'suizo', ronda: 1, mesa: 2, a: 'j3', b: 'j4', scoreA: 1, scoreB: 1, confirmado: true),
      DueloTorneo(fase: 'suizo', ronda: 1, mesa: 3, a: 'j5'),
      // Sin confirmar: no cuenta.
      DueloTorneo(fase: 'suizo', ronda: 2, mesa: 1, a: 'j1', b: 'j5', scoreA: 0, scoreB: 2),
    ];
    final tabla = calcularTabla(jugadores, duelos);
    final por = {for (final f in tabla) f.jugador.id: f};
    expect(por['j1']!.puntos, 3);
    expect(por['j1']!.partidasGanadas, 2);
    expect(por['j1']!.partidasPerdidas, 1);
    expect(por['j2']!.puntos, 0);
    expect(por['j3']!.puntos, 1);
    expect(por['j3']!.empatados, 1);
    expect(por['j5']!.puntos, 3);
    expect(por['j5']!.byes, 1);
    expect(por['j5']!.rivales, isEmpty);
    // j1 y j5 tienen 3 puntos; j1 enfrentó a un rival, j5 no: j1 va primero.
    expect(tabla.first.jugador.id, 'j1');
    expect(por['j2']!.porcentajeDuelos, closeTo(1 / 3, 1e-9), reason: 'piso de 33%');
  });

  test('si no queda otra opción se repite rival en vez de dejar gente sin jugar', () {
    final jugadores = _jugadores(2);
    final duelos = _jugar([const Emparejamiento('j1', 'j2')], 1);
    final pares = emparejarSuizo(jugadores, duelos);
    expect(pares.single.toString(), 'j1 vs j2');
  });

  test('llave del top 8 y avance hasta la final', () {
    final top = [for (var i = 1; i <= 8; i++) 'j$i'];
    final cuartos = llaveInicial(top);
    expect(cuartos.map((p) => '$p').toList(), [
      'j1 vs j8',
      'j4 vs j5',
      'j2 vs j7',
      'j3 vs j6',
    ]);
    final rCuartos = _jugar(cuartos, 1, fase: 'top');
    final semis = siguienteLlave(rCuartos);
    expect(semis.map((p) => '$p').toList(), ['j1 vs j4', 'j2 vs j3']);
    final rSemis = _jugar(semis, 2, fase: 'top');
    final fin = siguienteLlave(rSemis);
    expect(fin.single.toString(), 'j1 vs j2');
    final rFinal = _jugar(fin, 3, fase: 'top');
    expect(siguienteLlave(rFinal), isEmpty);
    expect(rFinal.single.ganador, 'j1');
    expect(nombreRondaTop(4), 'Cuartos de final');
    expect(nombreRondaTop(2), 'Semifinal');
    expect(nombreRondaTop(1), 'Final');
  });

  test('llave del top 4 y tamaños inválidos', () {
    expect(llaveInicial(['a', 'b', 'c', 'd']).map((p) => '$p').toList(), [
      'a vs d',
      'b vs c',
    ]);
    expect(() => llaveInicial(['a', 'b', 'c']), throwsArgumentError);
  });

  test('la llave no avanza con un duelo sin confirmar', () {
    const ronda = [
      DueloTorneo(fase: 'top', ronda: 1, mesa: 1, a: 'a', b: 'd', scoreA: 2, scoreB: 0, confirmado: true),
      DueloTorneo(fase: 'top', ronda: 1, mesa: 2, a: 'b', b: 'c', scoreA: 2, scoreB: 1),
    ];
    expect(siguienteLlave(ronda), isEmpty);
  });

  test('marcadores válidos al mejor de 3', () {
    bool suizo(int a, int b) => marcadorValido(a, b, permiteEmpate: true);
    bool top(int a, int b) => marcadorValido(a, b, permiteEmpate: false);
    expect(suizo(2, 0), isTrue);
    expect(suizo(2, 1), isTrue);
    expect(suizo(1, 1), isTrue);
    expect(suizo(1, 0), isTrue, reason: 'cortado por tiempo');
    expect(suizo(0, 0), isFalse);
    expect(suizo(2, 2), isFalse);
    expect(suizo(3, 0), isFalse);
    expect(top(2, 1), isTrue);
    expect(top(1, 1), isFalse);
    expect(top(1, 0), isFalse);
  });
}

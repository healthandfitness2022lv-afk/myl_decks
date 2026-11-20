// Un torneo entero, de la primera ronda al campeón, con las mismas funciones
// que usa el servicio (sin Firestore): emparejar, cargar resultados, avanzar.
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:myl_decks/domain/torneo/torneo.dart';
import 'package:myl_decks/models/torneo.dart';

class _Mesa {
  Map<String, dynamic> torneo;
  List<Inscrito> inscritos;
  final List<DueloDoc> duelos = [];
  final mensajes = <String>[];

  _Mesa(int jugadores, {required int top, int rondas = 0})
    : torneo = {
        'name': 'Prueba',
        'ownerUid': 'org',
        'status': EstadoTorneo.suizo,
        'currentRound': 1,
        'swissRounds': rondas > 0 ? rondas : rondasSugeridas(jugadores),
        'topCut': top,
      },
      inscritos = [
        for (var i = 1; i <= jugadores; i++)
          Inscrito(uid: 'j$i', nombre: 'Jugador $i'),
      ];

  Torneo get t => Torneo.fromMap('t', torneo);

  void crear(String fase, int ronda, List<Emparejamiento> pares) {
    for (var i = 0; i < pares.length; i++) {
      final p = pares[i];
      duelos.add(
        DueloDoc.fromMap(DueloDoc.idDe(fase, ronda, i + 1), {
          'phase': fase,
          'round': ronda,
          'table': i + 1,
          'aUid': p.a,
          'aName': p.a,
          'bUid': p.b,
          'bName': p.b,
          if (p.b == null) ...{'scoreA': 2, 'scoreB': 0, 'confirmed': true},
        }),
      );
    }
  }

  /// Juega los duelos abiertos: gana el de número más bajo.
  void jugarAbiertos() {
    for (var i = 0; i < duelos.length; i++) {
      final d = duelos[i];
      if (d.dominio.cerrado) continue;
      final ganaA =
          int.parse(d.aUid.substring(1)) < int.parse(d.bUid!.substring(1));
      duelos[i] = DueloDoc.fromMap(d.id, {
        'phase': d.fase,
        'round': d.ronda,
        'table': d.mesa,
        'aUid': d.aUid,
        'aName': d.aNombre,
        'bUid': d.bUid,
        'bName': d.bNombre,
        'scoreA': ganaA ? 2 : 1,
        'scoreB': ganaA ? 1 : 2,
        'confirmed': true,
      });
    }
  }

  /// Aplica el siguiente paso; false si no hay nada que hacer.
  bool avanzar() {
    final a = siguienteAccion(t, inscritos, duelos);
    if (a == null) return false;
    mensajes.add(a.mensaje);
    if (a.cierra) {
      torneo = {
        ...torneo,
        'status': EstadoTorneo.finalizado,
        'championUid': a.campeon!.id,
        'championName': a.campeon!.nombre,
      };
    } else {
      crear(a.fase!, a.ronda, a.pares);
      torneo = {...torneo, ...a.patch};
    }
    return true;
  }

  void retirar(String uid) {
    inscritos = [
      for (final i in inscritos)
        i.uid == uid ? Inscrito(uid: i.uid, nombre: i.nombre, retirado: true) : i,
    ];
  }
}

void main() {
  test('8 jugadores: 3 rondas suizas, top 4 y campeón', () {
    final m = _Mesa(8, top: 4);
    m.crear(
      'suizo',
      1,
      emparejarSuizo([for (final i in m.inscritos) i.jugador], const [], azar: Random(3)),
    );
    // Con resultados pendientes no se puede avanzar.
    expect(m.avanzar(), isFalse);
    var pasos = 0;
    while (!m.t.finalizado && pasos++ < 20) {
      m.jugarAbiertos();
      expect(m.avanzar(), isTrue);
    }
    expect(m.mensajes, [
      'Ronda 2 generada',
      'Ronda 3 generada',
      'Top 4 generado',
      'Final generada',
      'Torneo finalizado',
    ]);
    expect(m.t.campeonUid, 'j1');
    expect(m.duelos.where((d) => d.fase == 'suizo').length, 12);
    expect(m.duelos.where((d) => d.fase == 'top').length, 3);
    // La final la juegan los dos mejores del suizo.
    final fin = m.duelos.last;
    expect({fin.aUid, fin.bUid}, {'j1', 'j2'});
    // Ya terminado, no hay más pasos.
    expect(m.avanzar(), isFalse);
  });

  test('13 jugadores con bye y un retiro: 4 rondas, top 8 y campeón', () {
    final m = _Mesa(13, top: 8);
    m.crear(
      'suizo',
      1,
      emparejarSuizo([for (final i in m.inscritos) i.jugador], const [], azar: Random(5)),
    );
    var pasos = 0;
    while (!m.t.finalizado && pasos++ < 20) {
      m.jugarAbiertos();
      // j2 se retira después de la ronda 2.
      if (m.t.estado == EstadoTorneo.suizo && m.t.rondaActual == 2) {
        m.retirar('j2');
      }
      expect(m.avanzar(), isTrue);
    }
    expect(m.mensajes, [
      'Ronda 2 generada',
      'Ronda 3 generada',
      'Ronda 4 generada',
      'Top 8 generado',
      'Semifinal generada',
      'Final generada',
      'Torneo finalizado',
    ]);
    expect(m.t.campeonUid, 'j1');
    final suizo = m.duelos.where((d) => d.fase == 'suizo').toList();
    // Rondas 1 y 2 con 13 jugadores: 6 duelos + 1 bye; rondas 3 y 4 con 12.
    for (final r in [1, 2]) {
      final ronda = suizo.where((d) => d.ronda == r);
      expect(ronda.length, 7);
      expect(ronda.where((d) => d.esBye).length, 1);
    }
    for (final r in [3, 4]) {
      final ronda = suizo.where((d) => d.ronda == r);
      expect(ronda.length, 6);
      expect(ronda.any((d) => d.esBye || d.juega('j2')), isFalse);
    }
    // El retirado no entra a la llave aunque tenga puntos.
    expect(
      m.duelos.where((d) => d.fase == 'top').any((d) => d.juega('j2')),
      isFalse,
    );
    // Nadie repite rival en el suizo.
    final cruces = [
      for (final d in suizo.where((d) => !d.esBye))
        ([d.aUid, d.bUid!]..sort()).join('-'),
    ];
    expect(cruces.toSet().length, cruces.length);
  });

  test('sin top: el primero de la tabla es el campeón', () {
    final m = _Mesa(4, top: 0);
    m.crear(
      'suizo',
      1,
      emparejarSuizo([for (final i in m.inscritos) i.jugador], const [], azar: Random(1)),
    );
    var pasos = 0;
    while (!m.t.finalizado && pasos++ < 10) {
      m.jugarAbiertos();
      expect(m.avanzar(), isTrue);
    }
    expect(m.mensajes, ['Ronda 2 generada', 'Torneo finalizado']);
    expect(m.t.campeonUid, 'j1');
  });

  test('con 3 jugadores un top 4 se reduce a una final', () {
    final m = _Mesa(3, top: 4);
    m.crear(
      'suizo',
      1,
      emparejarSuizo([for (final i in m.inscritos) i.jugador], const [], azar: Random(2)),
    );
    var pasos = 0;
    while (!m.t.finalizado && pasos++ < 10) {
      m.jugarAbiertos();
      expect(m.avanzar(), isTrue);
    }
    expect(m.mensajes, ['Ronda 2 generada', 'Top 2 generado', 'Torneo finalizado']);
    expect(m.t.topCut, 2);
    expect(m.t.campeonUid, 'j1');
  });
}

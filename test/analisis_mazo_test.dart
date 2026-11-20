import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:myl_decks/domain/analisis_mazo/analisis_mazo.dart';
import 'package:myl_decks/models/card_myl.dart';
import 'package:myl_decks/models/deck.dart';

CardMyL _carta(
  String id,
  String tipo,
  int coste,
  List<Map<String, dynamic>> habs, {
  int? fuerza,
  String texto = '',
  bool revisada = false,
}) => CardMyL.fromMap({
  'nombre': id,
  'tipo': tipo,
  'coste': coste,
  if (fuerza != null) 'fuerza': fuerza,
  'habilidad': texto,
  'habilidades': habs,
  'habilidadesRevisadas': revisada,
}, id);

void main() {
  final magma = _carta('Dragón de Magma', 'Aliado', 4, [
    {
      'accion': 'destruir',
      'cuando': 'al_jugar',
      'objetivo': {
        'quien': 'oponente',
        'zona': 'en_juego',
        'tipos': ['Aliado'],
      },
    },
  ], fuerza: 4);
  final medjay = _carta('Guerrero Medjay', 'Aliado', 2, [
    {'accion': 'imbloqueable', 'cuando': 'continua'},
    {
      'accion': 'botar',
      'cuando': 'al_atacar',
      'cantidad': 1,
      'objetivo': {'quien': 'ambos', 'zona': 'en_juego'},
    },
  ], fuerza: 2);
  final capa = _carta('Capa', 'Talismán', 2, [
    {
      'accion': 'barajar',
      'cuando': 'oponente_juega',
      'objetivo': {
        'quien': 'disparadora',
        'zona': 'en_juego',
        'tipos': ['Aliado'],
      },
    },
  ]);
  final vainilla = _carta('Soldado', 'Aliado', 1, const [], fuerza: 2);
  final pendiente = _carta(
    'Pendiente',
    'Aliado',
    2,
    const [],
    texto: 'Roba una carta.',
  );

  test('roles desde las habilidades', () {
    expect(rolesDeCarta(magma).keys, ['remocion']);
    expect(rolesDeCarta(magma)['remocion'], closeTo(1.0, 1e-9));
    expect(
      rolesDeCarta(medjay).keys,
      containsAll(['presion', 'dano_directo']),
    );
    expect(rolesDeCarta(capa).keys, containsAll(['remocion', 'respuesta']));
    expect(rolesDeCarta(vainilla), isEmpty);
  });

  test('el peso sube con el alcance y la repetición, y baja con el costo', () {
    Map<String, double> r(Map<String, dynamic> h) => rolesDeHabilidades([h]);
    final una = r({
      'accion': 'destruir',
      'cuando': 'al_jugar',
      'objetivo': {'quien': 'oponente', 'zona': 'en_juego'},
    });
    final todas = r({
      'accion': 'destruir',
      'cuando': 'al_jugar',
      'objetivo': {'quien': 'oponente', 'zona': 'en_juego', 'seleccion': 'todos'},
    });
    final activada = r({
      'accion': 'destruir',
      'cuando': 'activada',
      'objetivo': {'quien': 'oponente', 'zona': 'en_juego'},
    });
    final cara = r({
      'accion': 'destruir',
      'cuando': 'activada',
      'costo': {'oros': 3},
      'objetivo': {'quien': 'oponente', 'zona': 'en_juego'},
    });
    expect(todas['remocion']!, greaterThan(una['remocion']!));
    expect(activada['remocion']!, greaterThan(una['remocion']!));
    expect(cara['remocion']!, lessThan(activada['remocion']!));
    // Destruir lo propio no es remoción.
    expect(
      r({
        'accion': 'destruir',
        'cuando': 'al_jugar',
        'objetivo': {'quien': 'propio', 'zona': 'en_juego'},
      }),
      isEmpty,
    );
  });

  test('una carta no pasa del tope por rol', () {
    final r = rolesDeHabilidades([
      for (var i = 0; i < 5; i++)
        {
          'accion': 'destruir',
          'cuando': 'activada',
          'objetivo': {
            'quien': 'oponente',
            'zona': 'en_juego',
            'seleccion': 'todos',
          },
        },
    ]);
    expect(r['remocion'], topeCarta);
  });

  test('análisis del mazo: perfil, cobertura y consistencia', () {
    final cartas = {
      for (final c in [magma, medjay, capa, vainilla, pendiente]) c.id: c,
    };
    final deck = Deck(
      id: 'x',
      ownerId: 'u',
      name: 'Prueba',
      cards: const [
        DeckCardEntry(
          cardId: 'Dragón de Magma',
          name: 'Dragón de Magma',
          count: 3,
          coste: 4,
          tipo: 'Aliado',
        ),
        DeckCardEntry(
          cardId: 'Capa',
          name: 'Capa',
          count: 2,
          coste: 2,
          tipo: 'Talismán',
        ),
        DeckCardEntry(
          cardId: 'Soldado',
          name: 'Soldado',
          count: 3,
          coste: 1,
          tipo: 'Aliado',
        ),
        DeckCardEntry(
          cardId: 'Pendiente',
          name: 'Pendiente',
          count: 1,
          coste: 2,
          tipo: 'Aliado',
        ),
        DeckCardEntry(name: 'Oro', count: 6, tipo: 'Oro'),
      ],
    );
    final a = analizarMazo(deck, resolver: (e) => cartas[e.cardId]);
    expect(a.total, 15);
    expect(a.oros, 6);
    expect(a.noOros, 9);
    expect(a.copiasPorRol['remocion'], 5);
    expect(a.copiasPorRol['respuesta'], 2);
    // El aliado sin texto no cuenta como pendiente; el que tiene texto sí.
    expect(a.sinProgramar, 1);
    expect(a.perfil, 'Control');
    expect(a.aportes['remocion']!.first.nombre, 'Dragón de Magma');
    expect(a.curva, {1: 3, 2: 3, 4: 3});
    expect(a.consistencia.remocionInicial, closeTo(1 - _sinRemocion(15, 5, 8), 1e-9));
    expect(a.resumen, startsWith('Control'));
  });

  test('hipergeométrica', () {
    expect(hipergeometrica(40, 0, 8), 0);
    expect(hipergeometrica(40, 40, 8), 1);
    // 4 copias en 40, mano de 8: 1 - C(36,8)/C(40,8)
    expect(hipergeometrica(40, 4, 8), closeTo(0.6065, 1e-4));
    expect(hipergeometrica(40, 4, 8), closeTo(1 - _sinRemocion(40, 4, 8), 1e-9));
  });

  test('índice: más presión sube, más manejo y curva alta bajan', () {
    final base = indiceVelocidad(15, 15, 34, 2.4);
    expect(indiceVelocidad(30, 15, 34, 2.4), greaterThan(base));
    expect(indiceVelocidad(15, 35, 34, 2.4), lessThan(base));
    expect(indiceVelocidad(15, 15, 34, 3.1), lessThan(base));
    expect(indiceVelocidad(0, 0, 0, 0), 50);
  });

  test('mismo resultado que el simulador (perfil_casos.json)', () {
    final datos =
        jsonDecode(File('test/fixtures/perfil_casos.json').readAsStringSync())
            as Map<String, dynamic>;
    final casos = (datos['casos'] as List).cast<Map<String, dynamic>>();
    expect(casos, isNotEmpty);
    for (final caso in casos) {
      final esperado = caso['esperado'] as Map<String, dynamic>;
      final a = analizarCartas([
        for (final c in (caso['cartas'] as List).cast<Map<String, dynamic>>())
          () {
            // Pasa por el modelo de la app, como en las pantallas.
            final carta = CardMyL.fromMap(c, '${c['nombre']}');
            return CartaAnalisis(
              nombre: carta.nombre,
              tipo: carta.tipo,
              coste: carta.coste,
              fuerza: carta.fuerza ?? 0,
              copias: (c['copias'] as num).toInt(),
              roles: rolesDeCarta(carta),
              sinProgramar: cartaSinProgramar(carta),
            );
          }(),
      ]);
      final nombre = caso['nombre'];
      expect(a.total, esperado['total'], reason: '$nombre total');
      expect(a.oros, esperado['oros'], reason: '$nombre oros');
      expect(
        a.costeMedio,
        closeTo((esperado['costeMedio'] as num).toDouble(), 0.002),
        reason: '$nombre coste',
      );
      final puntos = (esperado['roles'] as Map).cast<String, dynamic>();
      for (final rol in roles) {
        expect(
          a.puntos[rol],
          closeTo((puntos[rol] as num).toDouble(), 0.02),
          reason: '$nombre $rol',
        );
        expect(
          a.copiasPorRol[rol],
          (esperado['copiasPorRol'] as Map)[rol],
          reason: '$nombre copias $rol',
        );
      }
      expect(a.indice, esperado['indice'], reason: '$nombre índice');
      expect(a.perfil, esperado['perfil'], reason: '$nombre perfil');
      expect(a.sinProgramar, esperado['sinProgramar'], reason: '$nombre');
      final cons = (esperado['consistencia'] as Map).cast<String, dynamic>();
      expect(
        a.consistencia.orosTurno3,
        closeTo((cons['orosTurno3'] as num).toDouble(), 1e-3),
      );
      expect(
        a.consistencia.remocionInicial,
        closeTo((cons['remocionInicial'] as num).toDouble(), 1e-3),
      );
    }
  });
}

/// C(total-exitos, muestra) / C(total, muestra): probabilidad de no ver ninguna.
double _sinRemocion(int total, int exitos, int muestra) {
  var p = 1.0;
  for (var i = 0; i < muestra; i++) {
    p *= (total - exitos - i) / (total - i);
  }
  return p;
}

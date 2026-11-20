import 'package:flutter_test/flutter_test.dart';
import 'package:myl_decks/domain/entrenamiento.dart';

RivalEscalera _rival(String id, int rating, {int nivel = 3}) => RivalEscalera(
  id: id,
  deck: id.split('|').first,
  nombre: 'Rival $id',
  raza: 'Faraón',
  perfil: 'Agro',
  nivel: nivel,
  rating: rating,
);

final _escalera = Escalera(
  rivales: [
    _rival('a|1', 900, nivel: 1),
    _rival('b|1', 1000, nivel: 1),
    _rival('a|2', 1100, nivel: 2),
    _rival('b|3', 1250),
    _rival('a|4', 1500, nivel: 4),
    _rival('b|5', 1700, nivel: 5),
  ],
  ratingInicial: 1000,
);

void main() {
  test('probabilidad esperada', () {
    expect(esperado(1200, 1200), closeTo(0.5, 1e-9));
    expect(esperado(1600, 1200), closeTo(0.909, 1e-3));
    expect(esperado(1200, 1600) + esperado(1600, 1200), closeTo(1, 1e-9));
  });

  test('el rating se mueve más en la colocación y según la dificultad', () {
    expect(factorK(0), kColocacion);
    expect(factorK(partidasDeColocacion), kNormal);
    // Contra un igual: ±K/2.
    expect(nuevoRating(1200, 1200, gano: true, partidas: 20), 1212);
    expect(nuevoRating(1200, 1200, gano: false, partidas: 20), 1188);
    expect(nuevoRating(1200, 1200, gano: true, partidas: 0), 1224);
    // Ganarle a uno más fuerte suma más que a uno más débil.
    final (arriba, _) = puntosEnJuego(1200, 1500, 20);
    final (abajo, pierde) = puntosEnJuego(1200, 900, 20);
    expect(arriba, greaterThan(abajo));
    expect(pierde, lessThan(0));
    // Nunca queda en cero.
    expect(nuevoRating(2000, 800, gano: true, partidas: 50), 2001);
    expect(nuevoRating(800, 2000, gano: false, partidas: 50), 799);
  });

  test('progreso: suma partidas, historial y no cuenta dos veces', () {
    var p = const ProgresoEntrenamiento(rating: 1000);
    expect(p.enColocacion, isTrue);
    final rival = _rival('b|1', 1000, nivel: 1);
    p = p.conPartida(
      desafio: 'd1',
      rival: rival,
      gano: true,
      fecha: DateTime(2026, 11, 17),
    );
    expect(p.rating, 1024);
    expect((p.partidas, p.ganadas, p.racha), (1, 1, 1));
    expect(p.mejorRating, 1024);
    final repetida = p.conPartida(
      desafio: 'd1',
      rival: rival,
      gano: true,
      fecha: DateTime(2026, 11, 17),
    );
    expect(identical(repetida, p), isTrue);
    p = p.conPartida(
      desafio: 'd2',
      rival: rival,
      gano: false,
      fecha: DateTime(2026, 11, 18),
    );
    expect(p.rating, lessThan(1024));
    expect(p.mejorRating, 1024);
    expect(p.racha, 0);
    expect(p.historial.first.desafio, 'd2');
    expect(p.historial.first.cambio, lessThan(0));

    // Ida y vuelta por Firestore.
    final copia = ProgresoEntrenamiento.fromMap(p.toMap(), inicial: 1);
    expect(copia.rating, p.rating);
    expect(copia.historial.length, 2);
    expect(copia.historial.last.gano, isTrue);
    expect(copia.yaContada('d1'), isTrue);
    // Sin datos: parte en el rating inicial.
    expect(ProgresoEntrenamiento.fromMap(null, inicial: 934).rating, 934);
  });

  test('el historial se recorta', () {
    var p = const ProgresoEntrenamiento(rating: 1000);
    for (var i = 0; i < ProgresoEntrenamiento.maxHistorial + 5; i++) {
      p = p.conPartida(
        desafio: 'd$i',
        rival: _rival('a|1', 900),
        gano: i.isEven,
        fecha: DateTime(2026),
      );
    }
    expect(p.historial.length, ProgresoEntrenamiento.maxHistorial);
    expect(p.partidas, ProgresoEntrenamiento.maxHistorial + 5);
  });

  test('rival propuesto: el más cercano que no se repite', () {
    var p = const ProgresoEntrenamiento(rating: 1000);
    expect(elegirRival(_escalera, p)!.id, 'b|1');
    p = p.conPartida(
      desafio: 'd1',
      rival: _escalera.rivales[1],
      gano: true,
      fecha: DateTime(2026),
    );
    // Rating 1024: b|1 es el más cercano pero se acaba de jugar.
    final siguiente = elegirRival(_escalera, p)!;
    expect(siguiente.id, isNot('b|1'));
    expect(siguiente.id, 'a|2');
    final alto = elegirRival(
      _escalera,
      const ProgresoEntrenamiento(rating: 1650),
    );
    expect(alto!.id, 'b|5');
    expect(
      elegirRival(const Escalera(rivales: [], ratingInicial: 1000), p),
      isNull,
    );
  });

  test('alternativas: uno más fácil y uno más difícil', () {
    final alt = alternativas(
      _escalera,
      const ProgresoEntrenamiento(rating: 1100),
      _escalera.rivales[2],
    );
    expect(alt.map((r) => r.id).toList(), ['b|1', 'b|3']);
    expect(
      alternativas(
        _escalera,
        const ProgresoEntrenamiento(rating: 900),
        _escalera.rivales.first,
      ).single.id,
      'b|1',
    );
  });

  test('rangos según el avance en la escalera', () {
    expect(rangoDe(_escalera, 900).nombre, 'Aprendiz');
    expect(rangoDe(_escalera, 500).nombre, 'Aprendiz');
    expect(rangoDe(_escalera, 1300).nombre, 'Guerrero');
    expect(rangoDe(_escalera, 1700).nombre, 'Leyenda');
    expect(avanceEnEscalera(_escalera, 1300), closeTo(0.5, 1e-9));
  });

  test('la escalera se lee de Firestore ordenada y sin entradas rotas', () {
    final e = Escalera.fromMap({
      'creado': '2026-11-17T20:00:00+00:00',
      'ratingInicial': 934,
      'rivales': [
        {'id': 'x|5', 'deck': 'x', 'nombre': 'Fuerte', 'nivel': 5, 'rating': 1700},
        {'id': 'x|1', 'deck': 'x', 'nombre': 'Fácil', 'nivel': 1, 'rating': 834},
        {'id': '', 'deck': ''},
        'basura',
      ],
    });
    expect(e.rivales.map((r) => r.id).toList(), ['x|1', 'x|5']);
    expect((e.piso, e.techo, e.ratingInicial), (834, 1700, 934));
    expect(e.creada, isNotNull);
    expect(Escalera.fromMap(const {}).vacia, isTrue);
  });
}

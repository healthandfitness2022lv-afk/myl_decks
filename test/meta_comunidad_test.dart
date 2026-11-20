import 'package:flutter_test/flutter_test.dart';
import 'package:myl_decks/domain/meta_comunidad.dart';
import 'package:myl_decks/models/card_myl.dart';

void main() {
  final rayo = CardMyL.fromMap({
    'nombre': 'Rayo',
    'tipo': 'Talismán',
    'coste': 4,
    'habilidades': [
      {
        'accion': 'destruir',
        'cuando': 'al_jugar',
        'objetivo': {'quien': 'oponente', 'zona': 'en_juego'},
      },
    ],
  }, 'rayo');
  final berserker = CardMyL.fromMap({
    'nombre': 'Berserker',
    'tipo': 'Aliado',
    'coste': 1,
    'fuerza': 3,
    'habilidades': [
      {'accion': 'furia', 'cuando': 'continua'},
    ],
  }, 'berserker');
  final cartas = {'rayo': rayo, 'berserker': berserker};

  Map<String, dynamic> mazo(String raza, String carta, int copias) => {
    'race': raza,
    'edition': 'Espada Sagrada',
    'cards': [
      {
        'cardId': carta,
        'name': cartas[carta]!.nombre.toLowerCase(),
        'count': copias,
        'coste': cartas[carta]!.coste,
        'tipo': cartas[carta]!.tipo,
      },
      {'name': 'oro', 'count': 16, 'tipo': 'Oro'},
    ],
  };

  test('agrega razas, cartas y estilo solo de los mazos completos', () {
    final m = agregarMeta([
      mazo('Dragón', 'rayo', 33),
      mazo('Dragón', 'rayo', 33),
      mazo('Faraón', 'berserker', 33),
      mazo('Faraón', 'berserker', 5), // borrador: no cuenta
      {'race': 'Titán'}, // sin cartas
    ], resolver: (e) => cartas[e.cardId]);
    expect(m.mazos, 3);
    expect(m.porRaza, {'Dragón': 2, 'Faraón': 1});
    expect(m.porEdicion, {'Espada Sagrada': 3});
    expect(m.porEstilo, {'Control': 2, 'Agro': 1});
    expect(m.indiceMedio, inInclusiveRange(1, 99));
    // Solo razas con 2 o más mazos.
    expect(m.indicePorRaza.keys, ['Dragón']);
    expect(m.indicePorRaza['Dragón'], lessThan(40));
    expect(m.cartasPorMazos.first.key, 'Rayo');
    expect(m.cartasPorMazos.first.value, 2);
    expect(m.cartasPorCopias.first.value, 66);
    expect(m.cartasPorCopias.any((e) => e.key.toLowerCase() == 'oro'), isFalse);
  });

  test('sin habilidades programadas no hay estilo', () {
    final m = agregarMeta([
      {
        'race': 'Héroe',
        'cards': [
          {'name': 'Soldado', 'count': 49, 'tipo': 'Aliado', 'coste': 1},
        ],
      },
    ], resolver: (_) => null);
    expect(m.mazos, 1);
    expect(m.porEstilo, isEmpty);
    expect(m.indiceMedio, isNull);
  });

  test('lectura del índice en palabras', () {
    expect(lecturaIndice(80), 'Muy agro');
    expect(lecturaIndice(62), 'Agro');
    expect(lecturaIndice(50), 'Parejo');
    expect(lecturaIndice(38), 'Control');
    expect(lecturaIndice(10), 'Muy control');
  });
}

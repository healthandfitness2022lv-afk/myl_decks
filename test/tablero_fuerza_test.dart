import 'package:flutter_test/flutter_test.dart';
import 'package:myl_decks/screens/simulador/tablero_desafio.dart';

void main() {
  test('desglose de fuerza (vUsU T9): quién sube o baja al Aliado', () {
    expect(desgloseFuerza({'fuerza': 3}), isNull);
    expect(
      desgloseFuerza({
        'fuerzaBase': 2,
        'fuerzaDesglose': [
          {'de': 'Guerrero Bereber', 'valor': '+2'},
          {'de': 'Toro Apis', 'valor': '-1'},
        ],
      }),
      'base 2 · +2 Guerrero Bereber · -1 Toro Apis',
    );
  });

  test('contador del ataque: suma la fuerza de los elegidos', () {
    expect(fuerzaAtaque(const []), 0);
    expect(fuerzaAtaque([{'fuerza': 4}, {'fuerza': 3}, {'nombre': 'sin fuerza'}]), 7);
  });
}

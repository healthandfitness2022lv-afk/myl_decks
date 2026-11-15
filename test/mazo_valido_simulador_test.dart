import 'package:flutter_test/flutter_test.dart';
import 'package:myl_decks/models/deck.dart';
import 'package:myl_decks/screens/simulador/estado_mazos.dart';

Deck _mazo(List<DeckCardEntry> cartas) =>
    Deck(id: 'd', ownerId: 'u', name: 'Mazo', cards: cartas);

List<DeckCardEntry> _base(int total) => [
  for (var i = 0; i < total ~/ 3; i++)
    DeckCardEntry(cardId: 'c$i', name: 'Carta $i', count: 3),
  if (total % 3 > 0)
    DeckCardEntry(cardId: 'resto', name: 'Resto', count: total % 3),
];

void main() {
  test('49 cartas dentro de la Ban List: válido', () {
    expect(mazoValidoParaSimular(_mazo(_base(49)), const {}), isTrue);
  });

  test('menos o más de 49 cartas: no aparece', () {
    expect(mazoValidoParaSimular(_mazo(_base(47)), const {}), isFalse);
    expect(mazoValidoParaSimular(_mazo(_base(50)), const {}), isFalse);
  });

  test('más copias que la Ban List o carta prohibida: no aparece', () {
    final mazo = _mazo(_base(49));
    expect(mazoValidoParaSimular(mazo, const {'c0': 2}), isFalse);
    expect(mazoValidoParaSimular(mazo, const {'resto': 0}), isFalse);
    expect(mazoValidoParaSimular(mazo, const {'c0': 3, 'otra': 0}), isTrue);
  });

  test('la misma carta repartida en dos entradas suma sus copias', () {
    final cartas = [
      ..._base(45),
      const DeckCardEntry(cardId: 'x', name: 'X', count: 2),
      const DeckCardEntry(cardId: 'x', name: 'X', count: 2),
    ];
    expect(mazoValidoParaSimular(_mazo(cartas), const {}), isFalse);
  });
}
